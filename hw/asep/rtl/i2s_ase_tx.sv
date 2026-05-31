`timescale 1ns/1ps
`default_nettype none

module i2s_ase_tx
  import asa_asep_pkg::*;
  import asa_i2s_asep_pkg::*;
(
  input  logic            clk,
  input  logic            rst,
  input  logic            soft_reset_i,
  input  logic            build_cfg_i,
  input  logic            build_data_i,
  input  i2s_cfg_cmd_e    cfg_cmd_i,
  input  logic            cfg_ack_ok_i,
  input  asep_ts_mode_e   ts_mode_i,
  input  logic [31:0]     ts_value_i,
  input  i2s_bit_depth_e  bit_depth_i,
  input  i2s_data_fmt_e   data_fmt_i,
  input  logic [2:0]      num_channels_i,
  input  logic [4:0]      sample_rate_i,
  input  logic            timing_host_rx_i,
  input  logic            target_clk_mck_i,
  input  logic [9:0]      coeff_k_i,
  input  logic [15:0]     divisor_n_i,
  input  logic [23:0]     start_ptb_stamp_i,
  input  logic            timestamps_only_i,
  input  logic [8:0]      word_count_i,
  input  i2s_word_vec_t   words_i,
  output logic            packet_valid_o,
  output asep_packet_t    packet_o,
  output logic [11:0]     packet_len_o,
  output logic [6:0]      cfg_pkt_id_o,
  output logic [6:0]      data_pkt_id_o
);

  logic [6:0] cfg_pkt_id, data_pkt_id;
  logic       adv_cfg, adv_data;
  asep_packet_t cfg_pkt, data_pkt;
  logic [11:0] cfg_len, data_len;

  i2s_pkt_id_counter u_cfg_ctr(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i), .advance_i(adv_cfg), .pkt_id_o(cfg_pkt_id)
  );

  i2s_pkt_id_counter u_data_ctr(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i), .advance_i(adv_data), .pkt_id_o(data_pkt_id)
  );

  i2s_cfg_codec u_cfg(
    .encode_i(1'b1), .decode_i(1'b0), .pkt_id_i(cfg_pkt_id), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .cmd_i(cfg_cmd_i), .ack_ok_i(cfg_ack_ok_i), .bit_depth_i(bit_depth_i), .data_fmt_i(data_fmt_i),
    .num_channels_i(num_channels_i), .sample_rate_i(sample_rate_i), .timing_host_rx_i(timing_host_rx_i),
    .target_clk_mck_i(target_clk_mck_i), .coeff_k_i(coeff_k_i), .divisor_n_i(divisor_n_i),
    .packet_i('0), .packet_len_i('0), .packet_o(cfg_pkt), .packet_len_o(cfg_len), .seen_o(), .pkt_id_o(),
    .cmd_o(), .ack_ok_o(), .bit_depth_o(), .data_fmt_o(), .num_channels_o(), .sample_rate_o(),
    .timing_host_rx_o(), .target_clk_mck_o(), .coeff_k_o(), .divisor_n_o(), .crc_error_o(), .format_error_o()
  );

  i2s_data_codec u_data(
    .encode_i(1'b1), .decode_i(1'b0), .pkt_id_i(data_pkt_id), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .start_ptb_stamp_i(start_ptb_stamp_i), .bit_depth_i(bit_depth_i), .timestamps_only_i(timestamps_only_i),
    .data_len_i(word_count_i * i2s_bytes_per_word(bit_depth_i)), .word_count_i(word_count_i), .words_i(words_i),
    .packet_i('0), .packet_len_i('0), .packet_o(data_pkt), .packet_len_o(data_len), .seen_o(), .pkt_id_o(),
    .data_len_o(), .start_ptb_stamp_o(), .timestamps_only_o(), .word_count_o(), .words_o(), .crc_error_o(), .format_error_o()
  );

  always_comb begin
    packet_valid_o = 1'b0;
    packet_o       = '0;
    packet_len_o   = '0;
    adv_cfg        = 1'b0;
    adv_data       = 1'b0;
    if (build_cfg_i) begin
      packet_valid_o = 1'b1;
      packet_o       = cfg_pkt;
      packet_len_o   = cfg_len;
      adv_cfg        = 1'b1;
    end else if (build_data_i) begin
      packet_valid_o = 1'b1;
      packet_o       = data_pkt;
      packet_len_o   = data_len;
      adv_data       = 1'b1;
    end
  end

  assign cfg_pkt_id_o  = cfg_pkt_id;
  assign data_pkt_id_o = data_pkt_id;

endmodule

`default_nettype wire
