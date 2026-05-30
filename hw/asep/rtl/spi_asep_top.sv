`timescale 1ns/1ps
`default_nettype none

module spi_asep_top
  import asa_asep_pkg::*;
  import asa_spi_asep_pkg::*;
(
  input  logic            clk,
  input  logic            rst,
  input  logic            soft_reset_i,
  input  logic            ptb_tick_i,
  input  logic            tx_frame_start_i,
  input  logic            slot_indicate_i,
  input  logic            tx_build_cfg_i,
  input  logic            tx_build_data_i,
  input  logic            tx_build_irq_i,
  input  spi_cfg_cmd_e    tx_cfg_cmd_i,
  input  logic            tx_cfg_ack_ok_i,
  input  asep_ts_mode_e   tx_ts_mode_i,
  input  logic [31:0]     tx_ts_value_i,
  input  logic [15:0]     tx_spi_cfg_reg_i,
  input  logic [15:0]     tx_spi_min_idle_reg_i,
  input  logic [7:0]      tx_spi_stc_i,
  input  logic [7:0]      tx_spi_tat_mult_i,
  input  logic [19:0]     tx_spi_dcp_ticks_i,
  input  logic            tx_reduce_latency_i,
  input  logic [3:0]      tx_csn_i,
  input  spi_pkt_status_e tx_pkt_status_i,
  input  logic [29:0]     tx_last_cs_pos_i,
  input  spi_op_status_e  tx_op_status_i,
  input  logic            tx_irq_flag_i,
  input  logic            tx_reset_req_i,
  input  logic [7:0]      tx_spi_len_i,
  input  spi_symbol_vec_t tx_symbols_i,
  output logic            tx_packet_valid_o,
  output asep_packet_t    tx_packet_o,
  output logic [11:0]     tx_packet_len_o,
  output logic [6:0]      tx_packet_id_o,
  output logic [7:0]      tx_irq_count_o,
  output logic            tx_dcp_waiting_o,
  output logic            tx_tat_active_o,
  output logic            stc_tx_err_o,

  input  logic            rx_packet_valid_i,
  input  asep_packet_t    rx_packet_i,
  input  logic [11:0]     rx_packet_len_i,
  output logic [15:0]     rx_spi_cfg_shadow_o,
  output logic [15:0]     rx_spi_min_idle_shadow_o,
  output logic            rx_cfg_seen_o,
  output logic            rx_data_seen_o,
  output logic            rx_irq_seen_o,
  output spi_cfg_cmd_e    rx_cfg_cmd_o,
  output logic            rx_reduce_latency_o,
  output logic [3:0]      rx_csn_o,
  output spi_pkt_status_e rx_pkt_status_o,
  output logic [7:0]      rx_spi_len_o,
  output logic [29:0]     rx_last_cs_pos_o,
  output spi_op_status_e  rx_op_status_o,
  output logic            rx_irq_flag_o,
  output logic            rx_reset_req_o,
  output logic [7:0]      rx_irq_count_o,
  output spi_symbol_vec_t rx_symbols_o,
  output logic            rx_crc_error_o,
  output logic            rx_pkt_id_gap_o,
  output logic            rx_format_error_o,
  output logic            stc_rx_err_o
);

  spi_ase_tx u_tx(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i), .ptb_tick_i(ptb_tick_i),
    .tx_frame_start_i(tx_frame_start_i), .slot_indicate_i(slot_indicate_i),
    .build_cfg_i(tx_build_cfg_i), .build_data_i(tx_build_data_i), .build_irq_i(tx_build_irq_i),
    .cfg_cmd_i(tx_cfg_cmd_i), .cfg_ack_ok_i(tx_cfg_ack_ok_i), .ts_mode_i(tx_ts_mode_i),
    .ts_value_i(tx_ts_value_i), .spi_cfg_reg_i(tx_spi_cfg_reg_i), .spi_min_idle_reg_i(tx_spi_min_idle_reg_i),
    .spi_stc_i(tx_spi_stc_i), .spi_tat_mult_i(tx_spi_tat_mult_i), .spi_dcp_ticks_i(tx_spi_dcp_ticks_i),
    .reduce_latency_i(tx_reduce_latency_i), .csn_i(tx_csn_i), .pkt_status_i(tx_pkt_status_i),
    .last_cs_pos_i(tx_last_cs_pos_i), .op_status_i(tx_op_status_i), .irq_flag_i(tx_irq_flag_i),
    .reset_req_i(tx_reset_req_i), .spi_len_i(tx_spi_len_i), .symbols_i(tx_symbols_i),
    .packet_valid_o(tx_packet_valid_o), .packet_o(tx_packet_o), .packet_len_o(tx_packet_len_o),
    .packet_id_o(tx_packet_id_o), .irq_count_o(tx_irq_count_o), .dcp_waiting_o(tx_dcp_waiting_o),
    .tat_active_o(tx_tat_active_o), .stc_tx_err_o(stc_tx_err_o)
  );

  spi_asd_rx u_rx(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i), .rx_valid_i(rx_packet_valid_i),
    .rx_packet_i(rx_packet_i), .rx_packet_len_i(rx_packet_len_i), .spi_stc_i(tx_spi_stc_i),
    .spi_cfg_shadow_o(rx_spi_cfg_shadow_o), .spi_min_idle_shadow_o(rx_spi_min_idle_shadow_o),
    .cfg_packet_seen_o(rx_cfg_seen_o), .data_packet_seen_o(rx_data_seen_o), .irq_packet_seen_o(rx_irq_seen_o),
    .cfg_cmd_o(rx_cfg_cmd_o), .reduce_latency_o(rx_reduce_latency_o), .csn_o(rx_csn_o),
    .pkt_status_o(rx_pkt_status_o), .spi_len_o(rx_spi_len_o), .last_cs_pos_o(rx_last_cs_pos_o),
    .op_status_o(rx_op_status_o), .irq_flag_o(rx_irq_flag_o), .reset_req_o(rx_reset_req_o),
    .irq_count_o(rx_irq_count_o), .symbols_o(rx_symbols_o), .crc_error_o(rx_crc_error_o),
    .pkt_id_gap_o(rx_pkt_id_gap_o), .format_error_o(rx_format_error_o), .stc_rx_err_o(stc_rx_err_o)
  );

endmodule

`default_nettype wire
