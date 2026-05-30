`timescale 1ns/1ps
`default_nettype none

module gpio_asep_top
  import asa_asep_pkg::*;
  import asa_gpio_asep_pkg::*;
(
  input  logic            clk,
  input  logic            rst,
  input  logic            soft_reset_i,
  input  logic            ptb_tick_i,
  input  logic            tdd_boundary_i,

  input  logic            tx_build_cfg_i,
  input  logic            tx_build_data_i,
  input  logic            tx_cfg_mode2_i,
  input  gpio_cfg_cmd_e   tx_cfg_cmd_i,
  input  logic            tx_cfg_ack_ok_i,
  input  asep_ts_mode_e   tx_ts_mode_i,
  input  logic [31:0]     tx_ts_value_i,
  input  logic [15:0]     tx_active_mask_i,
  input  logic [3:0]      tx_cfg_pin_count_i,
  input  logic [15:0]     tx_cfg_pin_select_mask_i,

  input  logic [15:0]     cfg_pin_avail_i,
  input  logic [15:0]     cfg_pin_dir_i,
  input  logic [15:0]     cfg_pin_enable_i,
  input  logic [47:0]     cfg_pin_default_i,
  input  logic [31:0]     cfg_pin_drv_mode_i,
  input  logic [12:0]     cfg_sampling_period_i,
  input  logic            cfg_sampling_mode_eg_i,

  input  logic [15:0]     gpio_pin_in_i,

  output logic            tx_packet_valid_o,
  output asep_packet_t    tx_packet_o,
  output logic [11:0]     tx_packet_len_o,
  output logic            sample_tick_o,
  output logic [6:0]      tx_packet_id_o,

  input  logic            rx_packet_valid_i,
  input  asep_packet_t    rx_packet_i,
  input  logic [11:0]     rx_packet_len_i,
  output logic [12:0]     rx_sampling_period_o,
  output logic            rx_sampling_mode_eg_o,
  output logic [15:0]     rx_pin_dir_o,
  output logic [15:0]     rx_pin_enable_o,
  output logic [47:0]     rx_pin_default_o,
  output logic [31:0]     rx_pin_drv_mode_o,
  output logic [15:0]     gpio_pin_out_o,
  output logic            rx_crc_error_o,
  output logic            rx_pkt_id_gap_o,
  output logic            rx_format_error_o
);

  gpio_sample_clk_gen u_sclk (
    .clk(clk),
    .rst(rst),
    .soft_reset_i(soft_reset_i),
    .ptb_tick_i(ptb_tick_i),
    .tdd_boundary_i(tdd_boundary_i),
    .sampling_period_i(cfg_sampling_period_i),
    .sample_tick_o(sample_tick_o)
  );

  gpio_ase_tx u_tx (
    .clk(clk),
    .rst(rst),
    .soft_reset_i(soft_reset_i),
    .sample_tick_i(sample_tick_o),
    .tdd_boundary_i(tdd_boundary_i),
    .build_cfg_i(tx_build_cfg_i),
    .build_data_i(tx_build_data_i),
    .cfg_mode2_i(tx_cfg_mode2_i),
    .cfg_cmd_i(tx_cfg_cmd_i),
    .cfg_ack_ok_i(tx_cfg_ack_ok_i),
    .ts_mode_i(tx_ts_mode_i),
    .ts_value_i(tx_ts_value_i),
    .sampling_period_i(cfg_sampling_period_i),
    .sampling_mode_eg_i(cfg_sampling_mode_eg_i),
    .tx_active_mask_i(tx_active_mask_i),
    .pin_avail_i(cfg_pin_avail_i),
    .pin_dir_i(cfg_pin_dir_i),
    .pin_enable_i(cfg_pin_enable_i),
    .pin_default_i(cfg_pin_default_i),
    .pin_drv_mode_i(cfg_pin_drv_mode_i),
    .cfg_pin_count_i(tx_cfg_pin_count_i),
    .cfg_pin_select_mask_i(tx_cfg_pin_select_mask_i),
    .gpio_pin_in_i(gpio_pin_in_i),
    .packet_valid_o(tx_packet_valid_o),
    .packet_o(tx_packet_o),
    .packet_len_o(tx_packet_len_o),
    .packet_id_o(tx_packet_id_o),
    .sample_count_o(),
    .edge_count_o(),
    .data_build_error_o()
  );

  gpio_asd_rx u_rx (
    .clk(clk),
    .rst(rst),
    .soft_reset_i(soft_reset_i),
    .rx_valid_i(rx_packet_valid_i),
    .rx_packet_i(rx_packet_i),
    .rx_packet_len_i(rx_packet_len_i),
    .pin_avail_i(cfg_pin_avail_i),
    .sampling_period_o(rx_sampling_period_o),
    .sampling_mode_eg_o(rx_sampling_mode_eg_o),
    .pin_dir_o(rx_pin_dir_o),
    .pin_enable_o(rx_pin_enable_o),
    .pin_default_o(rx_pin_default_o),
    .pin_drv_mode_o(rx_pin_drv_mode_o),
    .gpio_pin_out_o(gpio_pin_out_o),
    .cfg_packet_seen_o(),
    .data_packet_seen_o(),
    .cfg_mode2_o(),
    .cfg_cmd_o(),
    .crc_error_o(rx_crc_error_o),
    .pkt_id_gap_o(rx_pkt_id_gap_o),
    .format_error_o(rx_format_error_o)
  );

endmodule

`default_nettype wire
