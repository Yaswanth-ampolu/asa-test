`timescale 1ns/1ps
`default_nettype none

module i2s_asep_top
  import asa_asep_pkg::*;
  import asa_i2s_asep_pkg::*;
(
  input  logic            clk,
  input  logic            rst,
  input  logic            soft_reset_i,
  input  logic            tx_build_cfg_i,
  input  logic            tx_build_data_i,
  input  i2s_cfg_cmd_e    tx_cfg_cmd_i,
  input  logic            tx_cfg_ack_ok_i,
  input  asep_ts_mode_e   tx_ts_mode_i,
  input  logic [31:0]     tx_ts_value_i,
  input  i2s_bit_depth_e  tx_bit_depth_i,
  input  i2s_data_fmt_e   tx_data_fmt_i,
  input  logic [2:0]      tx_num_channels_i,
  input  logic [4:0]      tx_sample_rate_i,
  input  logic            tx_timing_host_rx_i,
  input  logic            tx_target_clk_mck_i,
  input  logic [9:0]      tx_coeff_k_i,
  input  logic [15:0]     tx_divisor_n_i,
  input  logic [23:0]     tx_start_ptb_stamp_i,
  input  logic            tx_timestamps_only_i,
  input  logic [8:0]      tx_word_count_i,
  input  i2s_word_vec_t   tx_words_i,
  input  logic            sync_clk_edge_i,
  input  logic [23:0]     sync_ptb_timestamp_i,
  input  logic            rx_packet_valid_i,
  input  asep_packet_t    rx_packet_i,
  input  logic [11:0]     rx_packet_len_i,
  input  logic            rx_build_cfg_resp_i,
  input  i2s_cfg_cmd_e    rx_cfg_resp_cmd_i,
  input  logic            rx_cfg_ack_ok_i,
  output logic            tx_packet_valid_o,
  output asep_packet_t    tx_packet_o,
  output logic [11:0]     tx_packet_len_o,
  output logic [6:0]      tx_cfg_pkt_id_o,
  output logic [6:0]      tx_data_pkt_id_o,
  output logic            rx_cfg_seen_o,
  output logic            rx_data_seen_o,
  output logic [6:0]      rx_cfg_pkt_id_o,
  output logic [6:0]      rx_data_pkt_id_o,
  output i2s_cfg_cmd_e    rx_cfg_cmd_o,
  output logic            rx_cfg_ack_ok_o,
  output i2s_bit_depth_e  rx_bit_depth_o,
  output i2s_data_fmt_e   rx_data_fmt_o,
  output logic [2:0]      rx_num_channels_o,
  output logic [4:0]      rx_sample_rate_o,
  output logic            rx_timing_host_rx_o,
  output logic            rx_target_clk_mck_o,
  output logic [9:0]      rx_coeff_k_o,
  output logic [15:0]     rx_divisor_n_o,
  output logic [23:0]     rx_start_ptb_stamp_o,
  output logic            rx_timestamps_only_o,
  output logic [8:0]      rx_word_count_o,
  output i2s_word_vec_t   rx_words_o,
  output logic            rx_cfg_crc_error_o,
  output logic            rx_data_crc_error_o,
  output logic            rx_cfg_format_error_o,
  output logic            rx_data_format_error_o,
  output logic            rx_cfg_pkt_id_gap_o,
  output logic            rx_data_pkt_id_gap_o,
  output logic            sync_capture_pulse_o,
  output logic [23:0]     sync_captured_stamp_o,
  output logic            sync_delta_valid_o,
  output logic [23:0]     sync_delta_ticks_o
);

  logic rx_cfg_resp_valid;
  asep_packet_t rx_cfg_resp_pkt;
  logic [11:0] rx_cfg_resp_len;
  logic [9:0] sync_ratio_k_unused;
  logic [15:0] sync_div_n_unused;

  i2s_ase_tx u_tx(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i), .build_cfg_i(tx_build_cfg_i), .build_data_i(tx_build_data_i),
    .cfg_cmd_i(tx_cfg_cmd_i), .cfg_ack_ok_i(tx_cfg_ack_ok_i), .ts_mode_i(tx_ts_mode_i), .ts_value_i(tx_ts_value_i),
    .bit_depth_i(tx_bit_depth_i), .data_fmt_i(tx_data_fmt_i), .num_channels_i(tx_num_channels_i), .sample_rate_i(tx_sample_rate_i),
    .timing_host_rx_i(tx_timing_host_rx_i), .target_clk_mck_i(tx_target_clk_mck_i), .coeff_k_i(tx_coeff_k_i), .divisor_n_i(tx_divisor_n_i),
    .start_ptb_stamp_i(tx_start_ptb_stamp_i), .timestamps_only_i(tx_timestamps_only_i), .word_count_i(tx_word_count_i), .words_i(tx_words_i),
    .packet_valid_o(tx_packet_valid_o), .packet_o(tx_packet_o), .packet_len_o(tx_packet_len_o), .cfg_pkt_id_o(tx_cfg_pkt_id_o), .data_pkt_id_o(tx_data_pkt_id_o)
  );

  i2s_asd_rx u_rx(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i), .cfg_ts_mode_i(tx_ts_mode_i), .cfg_ts_value_i(tx_ts_value_i),
    .rx_packet_valid_i(rx_packet_valid_i), .rx_packet_i(rx_packet_i), .rx_packet_len_i(rx_packet_len_i),
    .tx_build_cfg_resp_i(rx_build_cfg_resp_i), .tx_cfg_resp_cmd_i(rx_cfg_resp_cmd_i), .tx_cfg_ack_ok_i(rx_cfg_ack_ok_i),
    .tx_packet_valid_o(rx_cfg_resp_valid), .tx_packet_o(rx_cfg_resp_pkt), .tx_packet_len_o(rx_cfg_resp_len),
    .cfg_seen_o(rx_cfg_seen_o), .data_seen_o(rx_data_seen_o), .cfg_pkt_id_o(rx_cfg_pkt_id_o), .data_pkt_id_o(rx_data_pkt_id_o),
    .cfg_cmd_o(rx_cfg_cmd_o), .cfg_ack_ok_o(rx_cfg_ack_ok_o), .bit_depth_o(rx_bit_depth_o), .data_fmt_o(rx_data_fmt_o),
    .num_channels_o(rx_num_channels_o), .sample_rate_o(rx_sample_rate_o), .timing_host_rx_o(rx_timing_host_rx_o), .target_clk_mck_o(rx_target_clk_mck_o),
    .coeff_k_o(rx_coeff_k_o), .divisor_n_o(rx_divisor_n_o), .start_ptb_stamp_o(rx_start_ptb_stamp_o), .timestamps_only_o(rx_timestamps_only_o),
    .word_count_o(rx_word_count_o), .words_o(rx_words_o), .cfg_crc_error_o(rx_cfg_crc_error_o), .data_crc_error_o(rx_data_crc_error_o),
    .cfg_format_error_o(rx_cfg_format_error_o), .data_format_error_o(rx_data_format_error_o), .cfg_pkt_id_gap_o(rx_cfg_pkt_id_gap_o),
    .data_pkt_id_gap_o(rx_data_pkt_id_gap_o)
  );

  i2s_ptb_sync u_sync(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i), .clk_edge_i(sync_clk_edge_i), .coeff_k_i(tx_coeff_k_i), .divisor_n_i(tx_divisor_n_i),
    .ptb_timestamp_i(sync_ptb_timestamp_i), .rx_stamp_valid_i(rx_data_seen_o), .rx_stamp_i(rx_start_ptb_stamp_o),
    .capture_pulse_o(sync_capture_pulse_o), .captured_stamp_o(sync_captured_stamp_o), .delta_valid_o(sync_delta_valid_o),
    .delta_ticks_o(sync_delta_ticks_o), .reconstructed_ratio_k_o(sync_ratio_k_unused), .reconstructed_div_n_o(sync_div_n_unused)
  );

endmodule

`default_nettype wire
