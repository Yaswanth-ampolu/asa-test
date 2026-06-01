`timescale 1ns/1ps
`default_nettype none

module edp_asep_top
  import asa_asep_pkg::*;
  import asa_edp_asep_pkg::*;
(
  input  logic            clk,
  input  logic            rst,
  input  logic            soft_reset_i,
  input  logic            tx_build_vb_i,
  input  logic            tx_build_edm_i,
  input  logic            tx_build_aux_i,
  input  logic            tx_build_stream_clock_i,
  input  logic            tx_build_plm8_i,
  input  logic            tx_build_plm132_i,
  input  asep_ts_mode_e   tx_ts_mode_i,
  input  logic [31:0]     tx_ts_value_i,
  input  logic [31:0]     tx_vb_vbid_i,
  input  logic [31:0]     tx_vb_mvid_i,
  input  logic [31:0]     tx_vb_maud_i,
  input  logic            tx_edm_dummy_sw_i,
  input  edp_lane_count_e tx_edm_lane_count_i,
  input  logic [15:0]     tx_edm_length_per_lane_i,
  input  logic [7:0]      tx_edm_komma01_i,
  input  logic [7:0]      tx_edm_komma23_i,
  input  edp_payload_t    tx_edm_payload_i,
  input  logic [11:0]     tx_edm_payload_len_i,
  input  logic [7:0]      tx_edm_komma45_i,
  input  logic [7:0]      tx_edm_komma67_i,
  input  edp_hpd_state_e  tx_aux_hpd_state_i,
  input  edp_payload_t    tx_aux_payload_i,
  input  logic [4:0]      tx_aux_payload_len_i,
  input  logic [23:0]     tx_stream_mvid_ptb_i,
  input  logic [23:0]     tx_stream_nvid_ptb_i,
  input  edp_lane_count_e tx_plm8_lane_count_i,
  input  logic [15:0]     tx_plm8_symbol_count_i,
  input  edp_plm10_vec_t  tx_plm8_symbols_i,
  input  logic [15:0]     tx_plm132_symbol_count_i,
  input  edp_plm132_vec_t tx_plm132_symbols_i,
  input  logic            rx_packet_valid_i,
  input  asep_packet_t    rx_packet_i,
  input  logic [11:0]     rx_packet_len_i,
  output logic            tx_packet_valid_o,
  output asep_packet_t    tx_packet_o,
  output logic [11:0]     tx_packet_len_o,
  output logic            rx_vb_seen_o,
  output logic            rx_edm_seen_o,
  output logic            rx_aux_seen_o,
  output logic            rx_stream_clock_seen_o,
  output logic            rx_plm8_seen_o,
  output logic            rx_plm132_seen_o,
  output logic [31:0]     rx_vb_vbid_o,
  output logic [31:0]     rx_vb_mvid_o,
  output logic [31:0]     rx_vb_maud_o,
  output logic            rx_edm_dummy_sw_o,
  output edp_lane_count_e rx_edm_lane_count_o,
  output logic [15:0]     rx_edm_length_per_lane_o,
  output logic [7:0]      rx_edm_komma01_o,
  output logic [7:0]      rx_edm_komma23_o,
  output edp_payload_t    rx_edm_payload_o,
  output logic [11:0]     rx_edm_payload_len_o,
  output logic [7:0]      rx_edm_komma45_o,
  output logic [7:0]      rx_edm_komma67_o,
  output edp_hpd_state_e  rx_aux_hpd_state_o,
  output edp_payload_t    rx_aux_payload_o,
  output logic [4:0]      rx_aux_payload_len_o,
  output logic [23:0]     rx_stream_mvid_ptb_o,
  output logic [23:0]     rx_stream_nvid_ptb_o,
  output edp_lane_count_e rx_plm8_lane_count_o,
  output logic [15:0]     rx_plm8_symbol_count_o,
  output edp_plm10_vec_t  rx_plm8_symbols_o,
  output logic [15:0]     rx_plm132_symbol_count_o,
  output edp_plm132_vec_t rx_plm132_symbols_o,
  output logic            rx_crc_error_o,
  output logic            rx_format_error_o
);

  edp_ase_tx u_tx(
    .build_vb_i(tx_build_vb_i), .build_edm_i(tx_build_edm_i), .build_aux_i(tx_build_aux_i),
    .build_stream_clock_i(tx_build_stream_clock_i), .build_plm8_i(tx_build_plm8_i), .build_plm132_i(tx_build_plm132_i),
    .ts_mode_i(tx_ts_mode_i), .ts_value_i(tx_ts_value_i), .vb_vbid_i(tx_vb_vbid_i), .vb_mvid_i(tx_vb_mvid_i), .vb_maud_i(tx_vb_maud_i),
    .edm_dummy_sw_i(tx_edm_dummy_sw_i), .edm_lane_count_i(tx_edm_lane_count_i), .edm_length_per_lane_i(tx_edm_length_per_lane_i),
    .edm_komma01_i(tx_edm_komma01_i), .edm_komma23_i(tx_edm_komma23_i), .edm_payload_i(tx_edm_payload_i),
    .edm_payload_len_i(tx_edm_payload_len_i), .edm_komma45_i(tx_edm_komma45_i), .edm_komma67_i(tx_edm_komma67_i),
    .aux_hpd_state_i(tx_aux_hpd_state_i), .aux_payload_i(tx_aux_payload_i), .aux_payload_len_i(tx_aux_payload_len_i),
    .stream_mvid_ptb_i(tx_stream_mvid_ptb_i), .stream_nvid_ptb_i(tx_stream_nvid_ptb_i), .plm8_lane_count_i(tx_plm8_lane_count_i),
    .plm8_symbol_count_i(tx_plm8_symbol_count_i), .plm8_symbols_i(tx_plm8_symbols_i), .plm132_symbol_count_i(tx_plm132_symbol_count_i),
    .plm132_symbols_i(tx_plm132_symbols_i), .packet_valid_o(tx_packet_valid_o), .packet_o(tx_packet_o), .packet_len_o(tx_packet_len_o)
  );

  edp_asd_rx u_rx(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i), .rx_packet_valid_i(rx_packet_valid_i), .rx_packet_i(rx_packet_i),
    .rx_packet_len_i(rx_packet_len_i), .rx_vb_seen_o(rx_vb_seen_o), .rx_edm_seen_o(rx_edm_seen_o), .rx_aux_seen_o(rx_aux_seen_o),
    .rx_stream_clock_seen_o(rx_stream_clock_seen_o), .rx_plm8_seen_o(rx_plm8_seen_o), .rx_plm132_seen_o(rx_plm132_seen_o),
    .rx_vb_vbid_o(rx_vb_vbid_o), .rx_vb_mvid_o(rx_vb_mvid_o), .rx_vb_maud_o(rx_vb_maud_o), .rx_edm_dummy_sw_o(rx_edm_dummy_sw_o),
    .rx_edm_lane_count_o(rx_edm_lane_count_o), .rx_edm_length_per_lane_o(rx_edm_length_per_lane_o), .rx_edm_komma01_o(rx_edm_komma01_o),
    .rx_edm_komma23_o(rx_edm_komma23_o), .rx_edm_payload_o(rx_edm_payload_o), .rx_edm_payload_len_o(rx_edm_payload_len_o),
    .rx_edm_komma45_o(rx_edm_komma45_o), .rx_edm_komma67_o(rx_edm_komma67_o), .rx_aux_hpd_state_o(rx_aux_hpd_state_o),
    .rx_aux_payload_o(rx_aux_payload_o), .rx_aux_payload_len_o(rx_aux_payload_len_o), .rx_stream_mvid_ptb_o(rx_stream_mvid_ptb_o),
    .rx_stream_nvid_ptb_o(rx_stream_nvid_ptb_o), .rx_plm8_lane_count_o(rx_plm8_lane_count_o), .rx_plm8_symbol_count_o(rx_plm8_symbol_count_o),
    .rx_plm8_symbols_o(rx_plm8_symbols_o), .rx_plm132_symbol_count_o(rx_plm132_symbol_count_o), .rx_plm132_symbols_o(rx_plm132_symbols_o),
    .rx_crc_error_o(rx_crc_error_o), .rx_format_error_o(rx_format_error_o)
  );

endmodule

`default_nettype wire
