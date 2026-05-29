`timescale 1ns/1ps
`default_nettype none

// LLS TX Protection (process_outgoing_message)
// Spec: Section 6.3.4.2, PDF pp201-202
//
// Steps per PDF (exact order):
//   1. Check bypass (KeyEx OAM / Node-Discover / Self-Announce)
//   2. Set byte0,bit7 = 1 (protection flag)
//   3. Select key slot
//   4. Check slot ready/active → drop if not
//   5. Construct IV
//   6. Set Counter byte = LSB 8 bits of TX counter
//   7. Perform crypto (AES-GMAC or AES-GCM)
//   8. Increment TX counter
//   9. Update KeySwitch in header
//   10. Return via 6.3.2.2
//
// AEAD engine is stubbed: for simulation correctness we compute a deterministic
// fake ICV (XOR of key, IV, and payload bytes). Real AES-GCM/GMAC must replace
// the engine stub in silicon implementation.

module lls_tx_protect
  import asa_lls_pkg::*;
(
  input  logic              clk,
  input  logic              rst,

  // Security policy
  input  lls_policy_e       policy_i,
  input  logic              is_downstream_i,  // Dir bit for IV

  // Container input (from DLL process_transmit_container)
  input  logic              req_valid_i,
  input  logic [47:0]       hdr_i,            // Container header (may have KeySwitch)
  input  logic [7:0]        dll_payload_i [0:637], // Max Dn_P2P payload (638 bytes)
  input  logic [9:0]        payload_len_i,    // Actual payload bytes

  // Bypass classification input
  input  lls_bypass_reason_e bypass_reason_i,
  input  logic              any_lk_installed_i,

  // Key slot inputs
  input  logic              tx_slot_i,
  input  logic [127:0]      tx_key_i,
  input  logic [29:0]       tx_salt_i,
  input  logic [63:0]       tx_ctr_i,
  input  logic              tx_slot_ready_i,

  // Key slot use output (tells keyslot_ctrl to increment)
  output logic              tx_use_o,

  // Output (to DLL via 6.3.2.2)
  output logic              resp_valid_o,
  output logic              resp_is_bypass_o,     // bypassed unmodified
  output logic              resp_error_o,          // dropped
  output lls_error_e        resp_error_code_o,
  output logic [47:0]       resp_hdr_o,           // header with KeySwitch updated
  // Security payload: byte0=PPF, byte1=Counter, byte2..N+1=payload, byte N+2..N+17=ICV
  output logic [7:0]        resp_sec_payload_o [0:655], // 638+18 bytes max
  output logic [9:0]        resp_sec_payload_len_o,
  output logic              dropped_tx_inc_o      // increment droppedContainersSecTX
);

  // =========================================================================
  // State
  // =========================================================================
  typedef enum logic [1:0] {S_IDLE, S_CRYPTO, S_DONE} state_e;
  state_e state_q;

  logic [47:0]  hdr_q;
  logic [7:0]   payload_q [0:637];
  logic [9:0]   plen_q;
  logic [95:0]  iv_q;
  logic [7:0]   ctr_byte_q;
  logic         bypass_q, error_q;
  logic         resp_valid_q;
  lls_error_e   err_code_q;
  lls_bypass_reason_e bypass_rsn_q;

  // Fake AEAD engine: XOR-based stub (NOT real AES-GCM/GMAC)
  // Real implementation must replace with AES-GCM/GMAC per NIST SP 800-38D
  logic [127:0] icv_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q   <= S_IDLE;
      bypass_q  <= 1'b0;
      error_q   <= 1'b0;
      resp_valid_q <= 1'b0;
      err_code_q<= LLS_OK;
      icv_q     <= 128'd0;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (req_valid_i) begin
            resp_valid_q <= 1'b0;
            hdr_q        <= hdr_i;
            plen_q       <= payload_len_i;
            bypass_rsn_q <= bypass_reason_i;
            // NOTE: Array copy deferred to generate-based always_ff below

            // Step 1: Check bypass
            if (bypass_reason_i != BYPASS_NONE || policy_i == SEC_POLICY_NONE) begin
              bypass_q  <= 1'b1;
              error_q   <= 1'b0;
              state_q   <= S_DONE;
            end
            // Step 4: Check slot ready
            else if (!tx_slot_ready_i) begin
              bypass_q  <= 1'b0;
              error_q   <= 1'b1;
              err_code_q<= LLS_SLOT_INVALID;
              state_q   <= S_DONE;
            end
            // Step 5: Construct IV
            else begin
              iv_q       <= lls_build_iv(~is_downstream_i, tx_salt_i, tx_ctr_i);
              ctr_byte_q <= tx_ctr_i[7:0]; // Step 6: Counter byte = LSB 8 bits
              bypass_q   <= 1'b0;
              error_q    <= 1'b0;
              state_q    <= S_CRYPTO;
            end
          end
        end

        S_CRYPTO: begin
          // Steps 7-8: AEAD computation (stubbed)
          // Stub ICV = XOR of key lower 128 bits XOR IV XOR first 128 bits of payload
          begin
            automatic logic [127:0] fake_icv;
            automatic logic [127:0] payload_block;
            payload_block = 128'd0;
            for (int i = 0; i < 16 && i < int'(plen_q); i++)
              payload_block[127 - i*8 -: 8] = payload_q[i];
            fake_icv = tx_key_i ^ iv_q[95:0] ^ {32'd0, iv_q[63:0]} ^ payload_block;
            icv_q <= fake_icv;
          end
          state_q <= S_DONE;
        end

        S_DONE: begin
          resp_valid_q <= 1'b1;
          state_q <= S_IDLE;
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

  // =========================================================================
  // Outputs
  // =========================================================================
  assign tx_use_o = (state_q == S_DONE) && !bypass_q && !error_q;
  assign dropped_tx_inc_o = resp_valid_q && error_q;
  assign resp_valid_o = resp_valid_q;
  assign resp_is_bypass_o = resp_valid_q && bypass_q;
  assign resp_error_o = resp_valid_q && error_q;
  assign resp_error_code_o = err_code_q;

  // Build header with KeySwitch updated (bit 1 of byte 0 per spec Table 5-1)
  always_comb begin
    resp_hdr_o = hdr_q;
    if (resp_valid_q && !bypass_q && !error_q) begin
      resp_hdr_o[1] = tx_slot_i; // KeySwitch bit = active TX slot
    end
  end

  // Build security payload (Figure 6-2, Table 6-2)
  always_comb begin
    for (int i = 0; i < 656; i++) resp_sec_payload_o[i] = 8'd0;
    resp_sec_payload_len_o = 10'd0;

    if (resp_valid_q && !bypass_q && !error_q) begin
      // byte0: PPF = 1 (bit7), bits6:0 = reserved = 0
      resp_sec_payload_o[0] = 8'h80;
      // byte1: Counter = LSB 8 bits of TX counter
      resp_sec_payload_o[1] = ctr_byte_q;
      // byte2..byte2+N-1: DLL Payload (encrypted if AES-GCM, unchanged if GMAC)
      for (int i = 0; i < 638; i++) begin
        if (i < int'(plen_q))
          resp_sec_payload_o[2 + i] = payload_q[i];
      end
      // byte2+N..byte2+N+15: ICV (16 bytes)
      for (int i = 0; i < 16; i++)
        resp_sec_payload_o[2 + int'(plen_q) + i] = icv_q[127 - i*8 -: 8];
      // Total length: PPF(1) + Counter(1) + payload(N) + ICV(16) = N+18
      resp_sec_payload_len_o = plen_q + 10'd18;
    end else if (resp_valid_q && bypass_q) begin
      // Bypass: return as-is; bypass containers have PPF=0
      resp_sec_payload_o[0] = 8'h00; // PPF=0 for bypassed frames
      for (int i = 0; i < 638; i++) begin
        if (i < int'(plen_q))
          resp_sec_payload_o[1 + i] = payload_q[i];
      end
      resp_sec_payload_len_o = plen_q + 10'd1; // Just the PPF byte prepended
    end
  end

  // Separate payload capture: registered when FSM is in IDLE and req arrives
  generate
    genvar gi;
    for (gi = 0; gi < 638; gi++) begin : gen_payload_cap
      always_ff @(posedge clk) begin
        if (req_valid_i && state_q == S_IDLE)
          payload_q[gi] <= dll_payload_i[gi];
      end
    end
  endgenerate

endmodule

`default_nettype wire
