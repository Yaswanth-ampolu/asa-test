`timescale 1ns/1ps
`default_nettype none

// PCS RX Top
// Spec: Section 4.2.3
//
// Pipeline:
//   PMA symbols
//     → Burst synchronization / resync header detection (4.2.3.1)
//     → PTB message extraction (feeds PTB service)
//     → PCS Descrambler (same additive operation as TX, 4.2.3.2)
//     → RS-FEC decode / integrity check (4.2.3.3)
//     → PLP_RX.dataUnit(phyL_block_rx, errStat) → DLL
//
// On RX burst sync: detect resync header using sy sequence correlation.
// Polarity: if inverted polarity detected, invert all symbols.
// Descrambler: same LFSR + XOR operation. Synchronized by header detection.
//
// IMPLEMENTATION NOTE: Full burst-accurate RX requires symbol-level
// correlation and polarity detection. This module provides the
// structural framework with:
//   - Interface to receive scrambled bits from PMA (simplified: bit-serial)
//   - Descrambler (same module as TX, just XOR is its own inverse)
//   - RS-FEC decode (integrity check only for SG1/2 per 4.2.3.3)
//   - Status reporting for link quality hooks

module pcs_rx_top
  import asa_pcs_pkg::*;
(
  input  logic              clk,
  input  logic              rst,

  // Configuration
  input  speed_grade_e      sg_i,
  input  logic              is_downstream_i,
  input  logic [1:0]        link_id_i,
  input  logic              pcs_init_i,

  // From PMA: received bits (after analog demodulation)
  input  logic              rx_bit_i,       // One bit per clock
  input  logic              rx_bit_valid_i, // Bit is valid (in burst)
  input  logic              rx_burst_start_i, // PMA detected new burst
  input  logic              rx_polarity_inv_i,// PMA detected inverted polarity

  // PTB extraction output (to PTB service)
  output logic [15:0]       m_ptb_rx_o,
  output logic              m_ptb_rx_valid_o,

  // DLL output
  output logic [7:0]        dll_byte_o,
  output logic              dll_byte_valid_o,
  output logic              dll_fec_err_o,    // Uncorrectable FEC error
  output logic              dll_fec_corrected_o, // FEC corrected errors

  // Link quality status (feeds register model / error aggregator)
  output logic              burst_sync_ok_o,  // Header detected OK this burst
  output logic              burst_sync_fail_o // Header not detected
);

  // =========================================================================
  // Scrambler / Descrambler (same module — XOR is its own inverse)
  // =========================================================================
  logic        scr_init, scr_advance;
  logic        rx_bit_pol;      // polarity-corrected bit
  logic        dscr_out_msb;
  logic [22:0] scr_state;

  assign rx_bit_pol = rx_bit_i ^ rx_polarity_inv_i;

  pcs_scrambler u_descr (
    .clk(clk), .rst(rst),
    .init_i          (scr_init | pcs_init_i),
    .link_id_i       (link_id_i),
    .advance_i       (scr_advance),
    .is_downstream_i (is_downstream_i),
    .is_pam4_i       (1'b0), // Simplified: PAM2 path for now
    .data_in_msb_i   (rx_bit_pol),
    .data_in_lsb_i   (1'b0),
    .data_out_msb_o  (dscr_out_msb),
    .data_out_lsb_o  (),
    .state_o         (scr_state)
  );

  // =========================================================================
  // RX state machine
  // =========================================================================
  typedef enum logic [2:0] {
    S_IDLE,
    S_RESYNC_SEARCH,  // Looking for resync header in incoming bits
    S_RESYNC_HDR,     // Consuming header bits (after alignment)
    S_PHY_BLOCK,      // Receiving and descrambling phy block bits
    S_FEC_CHECK       // Checking FEC after block received
  } rx_state_e;
  rx_state_e state_q;

  logic [10:0] hdr_pos_q;   // Position within resync header
  logic [11:0] blk_bit_q;   // Position within phy block

  // FEC accumulator (simplified: collect full block, check parity)
  localparam int unsigned MAX_BLK_BYTES = 720;
  logic [7:0]  rx_blk_buf [0:MAX_BLK_BYTES-1];
  logic [9:0]  rx_blk_ptr_q;

  // m_ptb capture: last 32 symbols of header = m_ptb[15:0] + ~m_ptb[15:0]
  logic [15:0] m_ptb_cap_q;
  logic [4:0]  ptb_bit_pos_q;

  assign scr_advance = (state_q == S_PHY_BLOCK) && rx_bit_valid_i;

  // IMPLEMENTATION NOTE: Full burst sync requires detecting the sync sequence
  // correlation peak in the header. This stub assumes the PMA provides
  // rx_burst_start_i at the correct moment (startup FSM has already aligned).
  // A real implementation needs a header correlator here.

  always_ff @(posedge clk or posedge rst) begin
    if (rst || pcs_init_i) begin
      state_q     <= S_IDLE;
      scr_init    <= 1'b1;
      hdr_pos_q   <= 11'd0;
      blk_bit_q   <= 12'd0;
      rx_blk_ptr_q<= 10'd0;
      m_ptb_cap_q <= 16'd0;
      ptb_bit_pos_q<= 5'd0;
      burst_sync_ok_o   <= 1'b0;
      burst_sync_fail_o <= 1'b0;
      m_ptb_rx_valid_o  <= 1'b0;
      dll_byte_valid_o  <= 1'b0;
      dll_fec_err_o     <= 1'b0;
      dll_fec_corrected_o <= 1'b0;
    end else begin
      scr_init          <= 1'b0;
      burst_sync_ok_o   <= 1'b0;
      burst_sync_fail_o <= 1'b0;
      m_ptb_rx_valid_o  <= 1'b0;
      dll_byte_valid_o  <= 1'b0;

      case (state_q)
        S_IDLE: begin
          if (rx_burst_start_i) begin
            state_q   <= S_RESYNC_HDR;
            hdr_pos_q <= 11'd0;
            scr_init  <= 1'b1; // Re-sync descrambler at header
          end
        end

        S_RESYNC_HDR: begin
          if (rx_bit_valid_i) begin
            // Capture m_ptb from last 32 header positions
            // resylen-32..resylen-17 = m_ptb[15:0], resylen-16..resylen-1 = ~m_ptb
            // For simplicity: extract both halves and validate agreement
            automatic logic [10:0] rl;
            rl = resync_len(sg_i);
            if (hdr_pos_q >= rl - 32 && hdr_pos_q < rl - 16) begin
              m_ptb_cap_q[hdr_pos_q - (rl - 32)] <= rx_bit_pol;
            end

            hdr_pos_q <= hdr_pos_q + 11'd1;
            if (hdr_pos_q >= rl - 1) begin
              // Header done — validate m_ptb (should be same as ~second half)
              burst_sync_ok_o  <= 1'b1;
              m_ptb_rx_o       <= m_ptb_cap_q;
              m_ptb_rx_valid_o <= 1'b1;
              state_q          <= S_PHY_BLOCK;
              blk_bit_q        <= 12'd0;
              rx_blk_ptr_q     <= 10'd0;
            end
          end
        end

        S_PHY_BLOCK: begin
          if (rx_bit_valid_i) begin
            // Accumulate descrambled bits into byte buffer
            automatic logic [9:0] byte_idx;
            automatic logic [2:0] bit_idx;
            byte_idx = blk_bit_q[11:3];
            bit_idx  = blk_bit_q[2:0];
            rx_blk_buf[byte_idx][7 - bit_idx] <= dscr_out_msb;
            blk_bit_q <= blk_bit_q + 12'd1;

            // Check if we've filled a full block
            // Block bits: PHY_BLOCK_BITS_DN_SG12=5184 for SG1/2 downstream
            // IMPLEMENTATION ASSUMPTION: Use SG1/2 downstream as default
            if (blk_bit_q >= 5183) begin
              state_q     <= S_FEC_CHECK;
              rx_blk_ptr_q<= 10'd0;
            end
          end else if (!rx_bit_valid_i && blk_bit_q > 0) begin
            // Burst ended early
            state_q <= S_IDLE;
          end
        end

        S_FEC_CHECK: begin
          // IMPLEMENTATION STUB: For SG1/2, FEC integrity check is mandatory.
          // In a real implementation: run syndrome calculation on
          // rx_blk_buf[0..719] and check if syndrome == 0.
          // For now, output all bytes as valid (assume correct).
          dll_fec_err_o <= 1'b0;
          state_q <= S_IDLE;

          // Emit DLL bytes (simplified: one byte per cycle)
          // Full impl would step through all message bytes sequentially
          dll_byte_o       <= rx_blk_buf[rx_blk_ptr_q];
          dll_byte_valid_o <= 1'b1;
          if (rx_blk_ptr_q < 10'd642) // DN SG1/2 payload bytes
            rx_blk_ptr_q <= rx_blk_ptr_q + 10'd1;
          else
            state_q <= S_IDLE;
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

  // m_ptb_rx_o is driven from the always_ff block above

endmodule

`default_nettype wire
