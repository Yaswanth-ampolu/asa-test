`timescale 1ns/1ps
`default_nettype none

// PCS Top-Level
// Spec: Sections 4.2.1-4.2.5, Figures 4-1/4-2
//
// Connects:
//   - TX datapath (DLL → FEC → scramble → resync header → PAM → PMA)
//   - RX datapath (PMA → burst sync → descramble → FEC check → DLL)
//   - PTB message vector pass-through
//   - Control interface from startup FSM and node FSM
//   - Status outputs to error aggregator and register model
//
// PCS reset behavior (Section 4.2.1, p95):
//   "The PCS reset function initializes all PCS functions including all LFSR
//    and the registers described in section 3.2."
//   PCS reset is executed at Power-On state AND at Fail state.
//   SoftReset is a SUBSET of PCS reset (does not impact configuration).

module pcs_top
  import asa_pcs_pkg::*;
  import asa_error_pkg::*;
(
  input  logic              clk,
  input  logic              rst,

  // =========================================================================
  // Configuration (from register model)
  // =========================================================================
  input  logic [15:0]       sg_config_i,       // Register 1.0002 (SGconfig)
  input  logic [1:0]        link_id_i,          // From register 3.2.19 (for scramblers)

  // =========================================================================
  // Control from startup FSM / node FSM
  // =========================================================================
  input  logic              pcs_reset_i,        // Full PCS reset (Power-On/Fail)
  input  logic              soft_reset_i,       // Soft reset (no config clear)
  input  logic              tx_enable_i,        // PMA.disable released
  input  logic              burst_start_i,      // Start new burst
  input  logic              burst_end_i,        // Burst complete, quiet gap
  input  logic              startup_phase_i,    // 1=startup mode RS-parity=0

  // =========================================================================
  // PTB interface (to/from PTB service)
  // =========================================================================
  input  logic [15:0]       m_ptb_tx_i,         // PTB message for TX header
  output logic [15:0]       m_ptb_rx_o,         // PTB message from RX header
  output logic              m_ptb_rx_valid_o,

  // =========================================================================
  // DLL TX interface
  // =========================================================================
  input  logic              dll_tx_valid_i,
  input  logic [7:0]        dll_tx_byte_i,
  output logic              dll_tx_ready_o,

  // =========================================================================
  // DLL RX interface
  // =========================================================================
  output logic [7:0]        dll_rx_byte_o,
  output logic              dll_rx_valid_o,
  output logic              dll_rx_fec_err_o,
  output logic              dll_rx_fec_corrected_o,

  // =========================================================================
  // PMA TX interface (symbols to PMA)
  // =========================================================================
  output pam2_sym_t         pma_tx_pam2_o,
  output pam4_sym_t         pma_tx_pam4_o,
  output logic              pma_tx_use_pam4_o,
  output logic              pma_tx_valid_o,

  // =========================================================================
  // PMA RX interface (bits from PMA)
  // =========================================================================
  input  logic              pma_rx_bit_i,
  input  logic              pma_rx_bit_valid_i,
  input  logic              pma_rx_burst_start_i,
  input  logic              pma_rx_polarity_inv_i,

  // =========================================================================
  // Status outputs (to error aggregator / register model)
  // =========================================================================
  output err_event_t        err_event_o,
  output logic              burst_sync_ok_o,
  output logic              burst_sync_fail_o,
  output logic              in_resync_hdr_o,
  output logic              in_phy_block_o,
  output logic              in_quiet_gap_o
);

  // Decode speed grade from sg_config register (bits 2:0 = Dn SG, Section 3.2.2)
  speed_grade_e sg;
  logic is_downstream;
  always_comb begin
    case (sg_config_i[2:0])
      3'd0: sg = SG1;
      3'd1: sg = SG2;
      3'd2: sg = SG3;
      3'd3: sg = SG4;
      3'd4: sg = SG5;
      default: sg = SG1;
    endcase
    // Bit 3 of SGconfig = direction: 0=Up TX/Dn RX, 1=Dn TX/Up RX
    is_downstream = sg_config_i[3];
  end

  logic pcs_init;
  assign pcs_init = pcs_reset_i | soft_reset_i;

  // =========================================================================
  // TX datapath
  // =========================================================================
  pcs_tx_top u_tx (
    .clk              (clk),
    .rst              (rst),
    .sg_i             (sg),
    .is_downstream_i  (is_downstream),
    .link_id_i        (link_id_i),
    .pcs_init_i       (pcs_init),
    .tx_enable_i      (tx_enable_i),
    .startup_phase_i  (startup_phase_i),
    .burst_start_i    (burst_start_i),
    .burst_end_i      (burst_end_i),
    .m_ptb_i          (m_ptb_tx_i),
    .dll_valid_i      (dll_tx_valid_i),
    .dll_byte_i       (dll_tx_byte_i),
    .dll_ready_o      (dll_tx_ready_o),
    .pam2_sym_o       (pma_tx_pam2_o),
    .pam4_sym_o       (pma_tx_pam4_o),
    .pam_use_pam4_o   (pma_tx_use_pam4_o),
    .sym_valid_o      (pma_tx_valid_o),
    .tx_busy_o        (),
    .in_resync_hdr_o  (in_resync_hdr_o),
    .in_phy_block_o   (in_phy_block_o),
    .in_quiet_gap_o   (in_quiet_gap_o)
  );

  // =========================================================================
  // RX datapath
  // =========================================================================
  pcs_rx_top u_rx (
    .clk                 (clk),
    .rst                 (rst),
    .sg_i                (sg),
    .is_downstream_i     (is_downstream),
    .link_id_i           (link_id_i),
    .pcs_init_i          (pcs_init),
    .rx_bit_i            (pma_rx_bit_i),
    .rx_bit_valid_i      (pma_rx_bit_valid_i),
    .rx_burst_start_i    (pma_rx_burst_start_i),
    .rx_polarity_inv_i   (pma_rx_polarity_inv_i),
    .m_ptb_rx_o          (m_ptb_rx_o),
    .m_ptb_rx_valid_o    (m_ptb_rx_valid_o),
    .dll_byte_o          (dll_rx_byte_o),
    .dll_byte_valid_o    (dll_rx_valid_o),
    .dll_fec_err_o       (dll_rx_fec_err_o),
    .dll_fec_corrected_o (dll_rx_fec_corrected_o),
    .burst_sync_ok_o     (burst_sync_ok_o),
    .burst_sync_fail_o   (burst_sync_fail_o)
  );

  // =========================================================================
  // Error event output
  // =========================================================================
  always_comb begin
    err_event_o.valid    = burst_sync_fail_o | dll_rx_fec_err_o;
    err_event_o.source   = ERR_SRC_LOCAL_PHY;
    err_event_o.severity = dll_rx_fec_err_o ? ERR_SEV_FATAL : ERR_SEV_WARN;
    err_event_o.code     = dll_rx_fec_err_o ? PHY_ERR_FEC_UNCORR : PHY_ERR_LINK_LOSS;
  end

endmodule

`default_nettype wire
