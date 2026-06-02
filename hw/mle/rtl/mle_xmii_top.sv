`timescale 1ns/1ps
`default_nettype none

module mle_xmii_top
  import asa_mle_pcs_pkg::*;
  import asa_mle_xmii_pkg::*;
(
  input  logic                            clk,
  input  logic                            rst,
  input  xmii_type_e                      xmii_type_i,
  input  logic                            host_tx_valid_i,
  input  logic [31:0]                     host_tx_data_i,
  input  logic [3:0]                      host_tx_ctrl_i,
  output logic                            host_tx_ready_o,
  input  logic                            tx_block_slot_advance_i,
  output logic [MLE_XMII_STREAM_BITS-1:0] xmii_blocks_tx_o,
  output logic                            xmii_blocks_tx_valid_o,
  output logic                            tx_skip_inserted_o,

  input  logic                            rx_plb_load_i,
  input  logic [MLE_XMII_STREAM_BITS-1:0] xmii_blocks_rx_i,
  input  logic                            rx_block_step_i,
  output logic                            host_rx_valid_o,
  output logic [31:0]                     host_rx_data_o,
  output logic [3:0]                      host_rx_ctrl_o,
  output logic                            rx_skip_removed_o,

  input  logic                            oam_frame_start_i,
  input  logic                            oam_frame_valid_i,
  input  logic                            oam_frame_last_i,
  input  logic [7:0]                      oam_frame_byte_i,
  input  logic                            oam_slot_advance_i,
  output logic [9:0]                      oam_slot_tx_o,
  output logic                            ptb_mdi_tx_oam_o,

  input  logic [9:0]                      oam_slot_rx_i,
  input  logic                            oam_slot_rx_valid_i,
  output logic                            oam_frame_rx_start_o,
  output logic                            oam_frame_rx_valid_o,
  output logic                            oam_frame_rx_end_o,
  output logic [7:0]                      oam_frame_rx_byte_o,
  output logic                            oam_crc_error_o,
  output logic                            ptb_mdi_rx_oam_o
);
  mle_xmii_tx_top u_tx (
    .clk(clk), .rst(rst), .xmii_type_i(xmii_type_i),
    .host_tx_valid_i(host_tx_valid_i), .host_tx_data_i(host_tx_data_i), .host_tx_ctrl_i(host_tx_ctrl_i),
    .host_tx_ready_o(host_tx_ready_o), .block_slot_advance_i(tx_block_slot_advance_i),
    .xmii_blocks_o(xmii_blocks_tx_o), .plb_valid_o(xmii_blocks_tx_valid_o), .skip_inserted_o(tx_skip_inserted_o)
  );

  mle_xmii_rx_top u_rx (
    .clk(clk), .rst(rst), .xmii_type_i(xmii_type_i),
    .plb_load_i(rx_plb_load_i), .xmii_blocks_i(xmii_blocks_rx_i), .block_step_i(rx_block_step_i),
    .host_rx_valid_o(host_rx_valid_o), .host_rx_data_o(host_rx_data_o), .host_rx_ctrl_o(host_rx_ctrl_o),
    .skip_removed_o(rx_skip_removed_o)
  );

  mle_oam_tx_adapt u_oam_tx (
    .clk(clk), .rst(rst),
    .frame_start_i(oam_frame_start_i), .frame_valid_i(oam_frame_valid_i),
    .frame_last_i(oam_frame_last_i), .frame_byte_i(oam_frame_byte_i),
    .slot_advance_i(oam_slot_advance_i), .slot_o(oam_slot_tx_o), .jk_pulse_o(ptb_mdi_tx_oam_o)
  );

  mle_oam_rx_adapt u_oam_rx (
    .clk(clk), .rst(rst), .slot_i(oam_slot_rx_i), .slot_valid_i(oam_slot_rx_valid_i),
    .frame_start_o(oam_frame_rx_start_o), .frame_valid_o(oam_frame_rx_valid_o),
    .frame_end_o(oam_frame_rx_end_o), .frame_byte_o(oam_frame_rx_byte_o),
    .crc_error_o(oam_crc_error_o), .jk_pulse_o(ptb_mdi_rx_oam_o)
  );
endmodule

`default_nettype wire
