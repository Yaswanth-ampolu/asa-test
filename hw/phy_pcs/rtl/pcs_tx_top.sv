`timescale 1ns/1ps
`default_nettype none

// PCS TX Top
// Spec: Section 4.2.2, Figure 4-1 (Normal Mode PCS TX data flow)
//
// Pipeline (per Figure 4-1):
//   d_plp_tx (DLL bytes)
//     → Physical_layer_blocks (RS-FEC framing + RS encoding) → tx_phy_block
//     → PCS Scrambler → tx_phy_block_scr
//     + Resync Header → tx_phy_rsync_hdr
//     → concatenate [rsync_hdr | phy_block_scr]
//     → PAM2/PAM4 Mapping
//     → to PMA (symbols)
//
// This module handles Normal Mode data flow.
// Startup mode (Phase1G/SGA/SGB/SGC) uses same path but with:
//   - d_plp_tx = 0 except last block (startup info field)
//   - RS parity = 0 (PDF Section 4.2.7)
//   - Phase1G: symbol repeat factor m
//
// The startup FSM drives startup_phase_i and tx_pattern_sel_i to control behavior.
//
// IMPLEMENTATION NOTE: The full pipeline operates on entire bursts.
// For simulation purposes this module accepts byte-serial DLL input,
// accumulates a full physical-layer block, FEC-encodes it, then
// streams the scrambled result symbol-serial toward PMA.

module pcs_tx_top
  import asa_pcs_pkg::*;
(
  input  logic              clk,
  input  logic              rst,

  // Configuration from startup FSM / register model
  input  speed_grade_e      sg_i,             // Speed grade
  input  logic              is_downstream_i,  // Direction
  input  logic [1:0]        link_id_i,        // Scrambler seed

  // Control from startup FSM
  input  logic              pcs_init_i,       // PCS reset (at startup_INIT)
  input  logic              tx_enable_i,      // Enable TX (not in disable state)
  input  logic              startup_phase_i,  // 1=startup (RS parity=0), 0=normal
  input  logic              burst_start_i,    // Pulse: new burst begins
  input  logic              burst_end_i,      // Pulse: burst ended, enter quiet gap

  // PTB message vector (from PTB service)
  input  logic [15:0]       m_ptb_i,

  // DLL interface (byte-serial, one byte per clock when dll_valid_i)
  input  logic              dll_valid_i,
  input  logic [7:0]        dll_byte_i,
  output logic              dll_ready_o,

  // PMA symbol output (PAM2 or PAM4)
  output pam2_sym_t         pam2_sym_o,
  output pam4_sym_t         pam4_sym_o,
  output logic              pam_use_pam4_o,
  output logic              sym_valid_o,

  // Status
  output logic              tx_busy_o,
  output logic              in_resync_hdr_o,
  output logic              in_phy_block_o,
  output logic              in_quiet_gap_o
);

  // =========================================================================
  // Internal signals
  // =========================================================================

  // RS-FEC encoder
  logic        fec_init, fec_msg_valid, fec_parity_valid;
  logic [7:0]  fec_msg_byte, fec_parity_byte;
  logic        fec_msg_ready, fec_parity_read, fec_done, fec_busy;

  // Resync header generator
  logic        rsync_start, rsync_advance, rsync_valid, rsync_done;
  logic        rsync_bit;

  // Scrambler
  logic        scr_init, scr_advance;
  logic        scr_din_msb, scr_din_lsb;
  logic        scr_dout_msb, scr_dout_lsb;
  logic [22:0] scr_state;

  // PAM mapper
  logic        pam_msb, pam_lsb;
  logic        pam_is_pam4, pam_is_rsync;

  // TX state machine
  typedef enum logic [2:0] {
    S_IDLE,
    S_RESYNC_HDR,
    S_FEC_FEED,
    S_FEC_PAR,
    S_PHY_BLOCK,
    S_QUIET_GAP
  } tx_state_e;
  tx_state_e tx_state_q, tx_state_d;

  // Block counters
  logic [11:0] block_bit_q;   // Position within current scrambled block
  logic [11:0] block_bits;    // Total bits in current block type

  // FEC output buffer (accumulate full block before streaming)
  // Max block size: DN SG3/4/5 = 5760 bits = 720 bytes
  localparam int unsigned MAX_BLOCK_BYTES = 720;
  logic [7:0]  block_buf_q [0:MAX_BLOCK_BYTES-1];
  logic [9:0]  block_buf_wr_ptr_q;
  logic [9:0]  block_buf_rd_ptr_q;
  logic [9:0]  block_buf_bytes_q;

  // Speed-grade derived parameters
  logic        is_pam4;
  always_comb begin
    is_pam4 = (sg_i == SG4 || sg_i == SG5) && is_downstream_i;
  end

  // =========================================================================
  // Submodule instances
  // =========================================================================

  // RS-FEC encoder (parameterized for downstream SG1/2 = RS(216,214))
  // IMPLEMENTATION NOTE: Full RS encoder selection based on SG requires
  // parameterized instantiation or mux. For now, instantiate RS(216,214).
  // RS(240,214) for SG3/4/5 and RS(108,106) for upstream are
  // architecturally identical — only coefficient table differs.
  // This stub uses RS(216,214) as the default.
  pcs_rs_encoder #(
    .K_BYTES(214),
    .T_PARITY(2)
  ) u_fec_dn12 (
    .clk(clk), .rst(rst),
    .init_i       (fec_init),
    .msg_valid_i  (fec_msg_valid),
    .msg_byte_i   (fec_msg_byte),
    .msg_ready_o  (fec_msg_ready),
    .parity_valid_o(fec_parity_valid),
    .parity_byte_o (fec_parity_byte),
    .parity_read_i (fec_parity_read),
    .busy_o        (fec_busy),
    .done_o        (fec_done)
  );

  // Resync header generator
  pcs_resync_header u_rsync (
    .clk(clk), .rst(rst),
    .init_i    (pcs_init_i),
    .start_i   (rsync_start),
    .advance_i (rsync_advance),
    .sg_i      (sg_i),
    .m_ptb_i   (m_ptb_i),
    .bit_o     (rsync_bit),
    .valid_o   (rsync_valid),
    .done_o    (rsync_done)
  );

  // Scrambler
  pcs_scrambler u_scr (
    .clk(clk), .rst(rst),
    .init_i          (scr_init),
    .link_id_i       (link_id_i),
    .advance_i       (scr_advance),
    .is_downstream_i (is_downstream_i),
    .is_pam4_i       (is_pam4),
    .data_in_msb_i   (scr_din_msb),
    .data_in_lsb_i   (scr_din_lsb),
    .data_out_msb_o  (scr_dout_msb),
    .data_out_lsb_o  (scr_dout_lsb),
    .state_o         (scr_state)
  );

  // PAM mapper
  pcs_pam_map u_pam (
    .is_pam4_i       (pam_is_pam4),
    .is_resync_hdr_i (pam_is_rsync),
    .bit_msb_i       (pam_msb),
    .bit_lsb_i       (pam_lsb),
    .pam2_sym_o      (pam2_sym_o),
    .pam4_sym_o      (pam4_sym_o),
    .use_pam4_o      (pam_use_pam4_o)
  );

  // =========================================================================
  // TX state machine
  // IMPLEMENTATION STUB: basic flow control; full burst-accurate timing
  // requires integration with TDD counter and PTB trigger
  // =========================================================================
  assign dll_ready_o    = (tx_state_q == S_FEC_FEED) && fec_msg_ready;
  assign tx_busy_o      = (tx_state_q != S_IDLE);
  assign in_resync_hdr_o= (tx_state_q == S_RESYNC_HDR);
  assign in_phy_block_o = (tx_state_q == S_PHY_BLOCK);
  assign in_quiet_gap_o = (tx_state_q == S_QUIET_GAP);

  // Symbol output: during resync header output header bits,
  // during phy block output scrambled bits
  assign sym_valid_o  = tx_enable_i && (tx_state_q == S_RESYNC_HDR || tx_state_q == S_PHY_BLOCK);
  assign pam_is_rsync = (tx_state_q == S_RESYNC_HDR);
  assign pam_is_pam4  = is_pam4;

  always_comb begin
    if (tx_state_q == S_RESYNC_HDR) begin
      pam_msb = rsync_bit;
      pam_lsb = 1'b0;
    end else begin
      pam_msb = scr_dout_msb;
      pam_lsb = scr_dout_lsb;
    end
  end

  // Scrambler feeds from block buffer bits
  assign scr_din_msb = (block_buf_rd_ptr_q < block_buf_bytes_q) ?
                       block_buf_q[block_buf_rd_ptr_q][7 - block_bit_q[2:0]] : 1'b0;
  assign scr_din_lsb = 1'b0;  // PAM4 LSB sourced separately in full impl

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      tx_state_q        <= S_IDLE;
      fec_init          <= 1'b0;
      fec_msg_valid     <= 1'b0;
      fec_msg_byte      <= 8'd0;
      fec_parity_read   <= 1'b0;
      rsync_start       <= 1'b0;
      rsync_advance     <= 1'b0;
      scr_init          <= 1'b0;
      scr_advance       <= 1'b0;
      block_bit_q       <= 12'd0;
      block_buf_wr_ptr_q<= 10'd0;
      block_buf_rd_ptr_q<= 10'd0;
      block_buf_bytes_q <= 10'd0;
      // block_buf_q initialises to 0 by default (no loop needed)
    end else if (pcs_init_i) begin
      tx_state_q <= S_IDLE;
      scr_init   <= 1'b1;
    end else begin
      scr_init   <= 1'b0;
      fec_init   <= 1'b0;
      rsync_start<= 1'b0;

      case (tx_state_q)
        S_IDLE: begin
          if (burst_start_i && tx_enable_i) begin
            tx_state_q  <= S_RESYNC_HDR;
            rsync_start <= 1'b1;
          end
        end

        S_RESYNC_HDR: begin
          rsync_advance <= rsync_valid;
          if (rsync_done) begin
            tx_state_q    <= S_FEC_FEED;
            rsync_advance <= 1'b0;
            fec_init      <= 1'b1;
            block_buf_wr_ptr_q <= 10'd0;
          end
        end

        S_FEC_FEED: begin
          // Accept DLL bytes and feed to FEC
          if (dll_valid_i && fec_msg_ready) begin
            fec_msg_valid <= 1'b1;
            fec_msg_byte  <= dll_byte_i;
          end else begin
            fec_msg_valid <= 1'b0;
          end

          if (fec_parity_valid) begin
            tx_state_q <= S_FEC_PAR;
            fec_msg_valid <= 1'b0;
          end
        end

        S_FEC_PAR: begin
          // Collect parity bytes into block buffer
          if (fec_parity_valid) begin
            block_buf_q[block_buf_wr_ptr_q] <= fec_parity_byte;
            block_buf_wr_ptr_q <= block_buf_wr_ptr_q + 10'd1;
            fec_parity_read <= 1'b1;
          end else begin
            fec_parity_read <= 1'b0;
          end

          if (fec_done) begin
            tx_state_q         <= S_PHY_BLOCK;
            block_buf_bytes_q  <= block_buf_wr_ptr_q;
            block_buf_rd_ptr_q <= 10'd0;
            block_bit_q        <= 12'd0;
          end
        end

        S_PHY_BLOCK: begin
          // Stream scrambled bits toward PAM
          scr_advance <= 1'b1;
          block_bit_q <= block_bit_q + 12'd1;

          if (block_bit_q[2:0] == 3'd7) begin
            // Finished a byte
            block_buf_rd_ptr_q <= block_buf_rd_ptr_q + 10'd1;
            if (block_buf_rd_ptr_q + 10'd1 >= block_buf_bytes_q) begin
              tx_state_q  <= S_QUIET_GAP;
              scr_advance <= 1'b0;
            end
          end
        end

        S_QUIET_GAP: begin
          scr_advance <= 1'b0;
          if (burst_end_i)
            tx_state_q <= S_IDLE;
        end

        default: tx_state_q <= S_IDLE;
      endcase
    end
  end

endmodule

`default_nettype wire
