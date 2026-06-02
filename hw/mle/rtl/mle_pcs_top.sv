`timescale 1ns/1ps
`default_nettype none

module mle_pcs_top
  import asa_pcs_pkg::*;
  import asa_mle_pcs_pkg::*;
(
  input  logic                            clk,
  input  logic                            rst,
  input  mle_mode_e                       mle_mode_i,
  input  logic [15:0]                     mlecapability1_i,
  input  logic [15:0]                     mlecapability2_i,
  input  logic [15:0]                     mleconfig_i,
  input  logic [1:0]                      ph1g_status_i,
  input  logic [2:0]                      txtest_i,
  input  logic [MLE_XMII_STREAM_BITS-1:0] xmii_blocks_tx_i,
  input  logic [9:0]                      oam_slot_tx_i,
  input  logic [9:0]                      secondary_ctrl_tx_i,
  input  logic                            secondary_valid_tx_i,
  output logic [MLE_PLB_BITS-1:0]         tx_phy_blockE_o,
  output logic [39:0]                     inf_1g_o,
  output speed_grade_e                    mapped_sg_o,
  output logic                            use_sg45_scrambler_o,
  output logic                            fec_correction_mandatory_o,
  output logic [12:0]                     tdd_cycle_ptb_o,
  output logic [7:0]                      dn_plbs_o,
  output logic [7:0]                      up_plbs_o,
  output logic [17:0]                     qg_dn_o,
  output logic [17:0]                     qg_up_o,

  input  logic [MLE_PLB_BITS-1:0]         rx_phy_blockE_i,
  output logic [MLE_XMII_STREAM_BITS-1:0] xmii_blocks_rx_o,
  output logic [9:0]                      oam_slot_rx_o,
  output logic [9:0]                      secondary_ctrl_rx_o,
  output logic                            secondary_valid_rx_o,
  output logic                            rx_parity_ok_o
);
  assign mapped_sg_o                = mle_mode_to_sg(mle_mode_i);
  assign use_sg45_scrambler_o       = mle_mode_uses_sg45_scrambler(mle_mode_i);
  assign fec_correction_mandatory_o = mle_fec_correction_mandatory(mle_mode_i);
  assign tdd_cycle_ptb_o            = mle_tdd_cycle_ptb(mle_mode_i);
  assign dn_plbs_o                  = mle_dn_plbs(mle_mode_i);
  assign up_plbs_o                  = mle_up_plbs(mle_mode_i);
  assign qg_dn_o                    = mle_qg_dn(mle_mode_i);
  assign qg_up_o                    = mle_qg_up(mle_mode_i);

  mle_phase1g_info u_phase1g (
    .mlecapability1_i (mlecapability1_i),
    .mlecapability2_i (mlecapability2_i),
    .mleconfig_i      (mleconfig_i),
    .ph1g_status_i    (ph1g_status_i),
    .txtest_i         (txtest_i),
    .inf_1g_o         (inf_1g_o)
  );

  mle_plb_codec u_plb (
    .xmii_blocks_i      (xmii_blocks_tx_i),
    .oam_slot_i         (oam_slot_tx_i),
    .secondary_ctrl_i   (secondary_ctrl_tx_i),
    .secondary_valid_i  (secondary_valid_tx_i),
    .tx_phy_blockE_o    (tx_phy_blockE_o),
    .rx_phy_blockE_i    (rx_phy_blockE_i),
    .xmii_blocks_o      (xmii_blocks_rx_o),
    .oam_slot_o         (oam_slot_rx_o),
    .secondary_ctrl_o   (secondary_ctrl_rx_o),
    .secondary_valid_o  (secondary_valid_rx_o),
    .parity_ok_o        (rx_parity_ok_o)
  );
endmodule

`default_nettype wire
