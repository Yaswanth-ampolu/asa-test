`timescale 1ns/1ps
`default_nettype none

// LLS RX Verification (process_incoming_message)
// Spec: Section 6.3.4.1, PDF pp200-201
//
// Steps per PDF (exact order):
//   1. Check bypass (KeyEx OAM / Node-Discover / Self-Announce → return via 6.3.2.4)
//      Non-exempt OAM + LKs not installed → OAM_FILTER
//      Empty OAM pre-LK → bypass
//   2. Determine key slot from KeySwitch header bit
//   3. Check slot validity → drop if invalid
//   4. Reconstruct assumed IV from counter
//   5. Perform crypto (AES-GMAC or AES-GCM)
//   6. Check ICV → drop on failure
//   7. On success: update RX counter, return payload
//      If ICV valid from OTHER slot → trigger key slot switch

module lls_rx_verify
  import asa_lls_pkg::*;
(
  input  logic              clk,
  input  logic              rst,

  input  lls_policy_e       policy_i,
  input  logic              is_downstream_i,

  // RX container input (from DLL process_receive_container)
  input  logic              req_valid_i,
  input  logic [47:0]       hdr_i,
  input  logic [7:0]        sec_payload_i [0:655],  // Full security payload
  input  logic [9:0]        sec_payload_len_i,       // Including PPF+CTR+payload+ICV

  // Bypass classification
  input  lls_bypass_reason_e bypass_reason_i,
  input  logic              any_lk_installed_i,

  // Key slot inputs (for the slot indicated by KeySwitch)
  // Also the OTHER slot inputs for rotation detection
  input  logic              keysw_i,              // KeySwitch from header
  input  logic [127:0]      rx_key_i,             // Key for keysw slot
  input  logic [29:0]       rx_salt_i,
  input  logic [63:0]       rx_last_ctr_i,        // Last RX AEAD Invocation Counter
  input  logic              rx_slot_ready_i,

  // OTHER slot (for rotation detection)
  input  logic [127:0]      rx_other_key_i,
  input  logic [29:0]       rx_other_salt_i,
  input  logic [63:0]       rx_other_last_ctr_i,
  input  logic              rx_other_slot_ready_i,

  // RX counter update output
  output logic              rx_ctr_update_o,
  output logic              rx_ctr_slot_o,
  output logic [63:0]       rx_ctr_new_o,

  // Key rotation trigger
  output logic              rx_key_switch_o,
  output logic              rx_switch_new_slot_o,

  // Outputs
  output logic              resp_valid_o,
  output logic              resp_is_bypass_o,
  output logic              resp_error_o,
  output lls_error_e        resp_error_code_o,
  // DLL payload (stripped of PPF/Counter/ICV)
  output logic [7:0]        resp_dll_payload_o [0:637],
  output logic [9:0]        resp_dll_payload_len_o,
  output logic              dropped_rx_inc_o
);

  typedef enum logic [1:0] {S_IDLE, S_CRYPTO, S_DONE} state_e;
  state_e state_q;

  logic [47:0] hdr_q;
  logic [7:0]  sec_q [0:655];
  logic [9:0]  slen_q;
  logic        bypass_q, error_q;
  logic        resp_valid_q;
  lls_error_e  err_code_q;
  logic        keysw_q;
  logic [63:0] assumed_ctr_q;
  logic [95:0] iv_q;
  logic [7:0]  recv_ctr_lo_q;
  logic        icv_ok_q;
  logic        other_slot_tested_q;

  // Extracted payload length (sec_len - PPF(1) - CTR(1) - ICV(16) = sec_len - 18)
  logic [9:0] dll_plen_q;

  // Fake AEAD verification: accept ICV if it matches our stub computation
  // Real implementation must use AES-GCM/GMAC per NIST SP 800-38D
  logic [127:0] expected_icv_q, received_icv_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q            <= S_IDLE;
      bypass_q           <= 1'b0;
      error_q            <= 1'b0;
      resp_valid_q       <= 1'b0;
      err_code_q         <= LLS_OK;
      icv_ok_q           <= 1'b0;
      other_slot_tested_q<= 1'b0;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (req_valid_i) begin
            resp_valid_q <= 1'b0;
            hdr_q    <= hdr_i;
            slen_q   <= sec_payload_len_i;
            keysw_q  <= keysw_i;
            // NOTE: Array copy deferred to generate-based always_ff below

            // Step 1: Bypass check
            if (bypass_reason_i != BYPASS_NONE || policy_i == SEC_POLICY_NONE) begin
              bypass_q  <= 1'b1;
              error_q   <= 1'b0;
              state_q   <= S_DONE;
            end
            // OAM_FILTER: non-exempt OAM with no LKs
            else if (!any_lk_installed_i &&
                     bypass_reason_i == BYPASS_NONE) begin
              bypass_q  <= 1'b0;
              error_q   <= 1'b1;
              err_code_q<= LLS_OAM_FILTER;
              state_q   <= S_DONE;
            end
            // Step 3: Check slot validity
            else if (!rx_slot_ready_i) begin
              bypass_q  <= 1'b0;
              error_q   <= 1'b1;
              err_code_q<= LLS_SLOT_INVALID;
              state_q   <= S_DONE;
            end
            else begin
              bypass_q  <= 1'b0;
              error_q   <= 1'b0;
              // Step 4: Reconstruct IV
              recv_ctr_lo_q  <= sec_payload_i[1]; // Counter byte at position 1
              // DLL payload length = total - PPF(1) - CTR(1) - ICV(16)
              dll_plen_q <= (sec_payload_len_i > 10'd18) ?
                             sec_payload_len_i - 10'd18 : 10'd0;
              begin
                automatic logic [63:0] assumed;
                assumed = lls_reconstruct_rx_ctr(rx_last_ctr_i, sec_payload_i[1]);
                assumed_ctr_q <= assumed;
                iv_q <= lls_build_iv(~is_downstream_i, rx_salt_i, assumed);
              end
              state_q <= S_CRYPTO;
            end
          end
        end

        S_CRYPTO: begin
          // Steps 5-6: Compute expected ICV and compare with received ICV
          begin
            automatic logic [127:0] payload_block;
            automatic logic [127:0] exp_icv;
            automatic logic [127:0] rcv_icv;
            automatic logic [9:0]   pay_start;

            payload_block = 128'd0;
            pay_start = 10'd2; // DLL payload starts at byte 2
            for (int i = 0; i < 16 && (i < int'(dll_plen_q)); i++)
              payload_block[127 - i*8 -: 8] = sec_q[2 + i];

            // Stub: expected ICV = XOR of key, IV, payload (matches TX stub)
            exp_icv = rx_key_i ^ iv_q[95:0] ^ {32'd0, iv_q[63:0]} ^ payload_block;
            expected_icv_q <= exp_icv;

            // Received ICV: last 16 bytes of sec_payload
            rcv_icv = 128'd0;
            for (int i = 0; i < 16; i++)
              rcv_icv[127 - i*8 -: 8] = sec_q[2 + int'(dll_plen_q) + i];
            received_icv_q <= rcv_icv;

            icv_ok_q <= (exp_icv == rcv_icv);
            other_slot_tested_q <= 1'b0;
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
  // ICV valid from other slot check (combinational from S_DONE)
  // Only relevant if current slot ICV failed — check the other slot's ICV
  // IMPLEMENTATION ASSUMPTION: We check other slot only when main ICV fails.
  // In a real pipeline both slots might be checked in parallel.
  // =========================================================================
  logic other_icv_ok;
  logic [127:0] other_iv, other_exp_icv;
  logic [63:0]  other_assumed_ctr;

  always_comb begin
    other_iv         = 96'd0;
    other_exp_icv    = 128'd0;
    other_assumed_ctr= 64'd0;
    other_icv_ok     = 1'b0;

    if (resp_valid_q && !bypass_q && !error_q && !icv_ok_q && rx_other_slot_ready_i) begin
      // Build payload block for other-slot ICV check
      other_assumed_ctr = lls_reconstruct_rx_ctr(rx_other_last_ctr_i, sec_q[1]);
      other_iv          = lls_build_iv(~is_downstream_i, rx_other_salt_i, other_assumed_ctr);
      other_exp_icv     = rx_other_key_i ^ other_iv[95:0] ^ {32'd0, other_iv[63:0]};
      // XOR with up to 16 payload bytes
      for (int i = 0; i < 16; i++) begin
        if (i < int'(dll_plen_q))
          other_exp_icv[127 - i*8 -: 8] = other_exp_icv[127 - i*8 -: 8] ^ sec_q[2 + i];
      end
      other_icv_ok = (other_exp_icv == received_icv_q);
    end
  end

  // =========================================================================
  // Output combinational
  // =========================================================================
  assign resp_valid_o          = resp_valid_q;
  assign resp_is_bypass_o      = resp_valid_q && bypass_q;
  assign resp_error_o          = resp_valid_q && (error_q || (!bypass_q && !icv_ok_q && !other_icv_ok));
  assign resp_error_code_o     = error_q ? err_code_q : LLS_AUTH_FAIL;
  assign dropped_rx_inc_o      = resp_valid_q && !bypass_q && (!error_q ? !icv_ok_q && !other_icv_ok : error_q == LLS_SLOT_INVALID);

  // RX counter update: only on ICV success from the queried slot
  assign rx_ctr_update_o      = resp_valid_q && !bypass_q && !error_q && icv_ok_q;
  assign rx_ctr_slot_o        = keysw_q;
  assign rx_ctr_new_o         = assumed_ctr_q;

  // Key slot rotation: valid ICV from OTHER slot (Section 6.3.4.1)
  assign rx_key_switch_o      = resp_valid_q && other_icv_ok;
  assign rx_switch_new_slot_o = ~keysw_q; // Switch to the other slot

  // DLL payload output (stripped of PPF/Counter/ICV)
  always_comb begin
    for (int i = 0; i < 638; i++) resp_dll_payload_o[i] = 8'd0;
    resp_dll_payload_len_o = 10'd0;

    if (resp_valid_q) begin
      if (bypass_q) begin
        // Bypass: strip PPF byte (byte0), return rest
        for (int i = 0; i < 638; i++) begin
          if (i < int'(sec_q[1] == 8'h00 ? slen_q - 10'd1 : slen_q - 10'd1))
            resp_dll_payload_o[i] = sec_q[1 + i];
        end
        resp_dll_payload_len_o = (slen_q > 10'd1) ? slen_q - 10'd1 : 10'd0;
      end else if (!error_q && icv_ok_q) begin
        // Verified: return DLL payload (bytes 2..2+N-1)
        for (int i = 0; i < 638; i++) begin
          if (i < int'(dll_plen_q))
            resp_dll_payload_o[i] = sec_q[2 + i];
        end
        resp_dll_payload_len_o = dll_plen_q;
      end
    end
  end

  // Separate SEC payload capture
  generate
    genvar gi;
    for (gi = 0; gi < 656; gi++) begin : gen_sec_cap
      always_ff @(posedge clk) begin
        if (req_valid_i && state_q == S_IDLE)
          sec_q[gi] <= sec_payload_i[gi];
      end
    end
  endgenerate

endmodule

`default_nettype wire
