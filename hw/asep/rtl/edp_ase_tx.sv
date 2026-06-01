`timescale 1ns/1ps
`default_nettype none

module edp_ase_tx
  import asa_asep_pkg::*;
  import asa_edp_asep_pkg::*;
(
  input  logic            build_vb_i,
  input  logic            build_edm_i,
  input  logic            build_aux_i,
  input  logic            build_stream_clock_i,
  input  logic            build_plm8_i,
  input  logic            build_plm132_i,
  input  asep_ts_mode_e   ts_mode_i,
  input  logic [31:0]     ts_value_i,
  input  logic [31:0]     vb_vbid_i,
  input  logic [31:0]     vb_mvid_i,
  input  logic [31:0]     vb_maud_i,
  input  logic            edm_dummy_sw_i,
  input  edp_lane_count_e edm_lane_count_i,
  input  logic [15:0]     edm_length_per_lane_i,
  input  logic [7:0]      edm_komma01_i,
  input  logic [7:0]      edm_komma23_i,
  input  edp_payload_t    edm_payload_i,
  input  logic [11:0]     edm_payload_len_i,
  input  logic [7:0]      edm_komma45_i,
  input  logic [7:0]      edm_komma67_i,
  input  edp_hpd_state_e  aux_hpd_state_i,
  input  edp_payload_t    aux_payload_i,
  input  logic [4:0]      aux_payload_len_i,
  input  logic [23:0]     stream_mvid_ptb_i,
  input  logic [23:0]     stream_nvid_ptb_i,
  input  edp_lane_count_e plm8_lane_count_i,
  input  logic [15:0]     plm8_symbol_count_i,
  input  edp_plm10_vec_t  plm8_symbols_i,
  input  logic [15:0]     plm132_symbol_count_i,
  input  edp_plm132_vec_t plm132_symbols_i,
  output logic            packet_valid_o,
  output asep_packet_t    packet_o,
  output logic [11:0]     packet_len_o
);

  asep_packet_t vb_pkt, edm_pkt, aux_pkt, clk_pkt, plm8_pkt, plm132_pkt;
  logic [11:0] vb_len, edm_len, aux_len, clk_len, plm8_len, plm132_len;

  edp_vb_codec u_vb(
    .encode_i(build_vb_i), .decode_i(1'b0), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .vbid_i(vb_vbid_i), .mvid_i(vb_mvid_i), .maud_i(vb_maud_i), .packet_i('0), .packet_len_i('0),
    .packet_o(vb_pkt), .packet_len_o(vb_len), .seen_o(), .vbid_o(), .mvid_o(), .maud_o(),
    .crc_error_o(), .format_error_o()
  );

  edp_edm_data_codec u_edm(
    .encode_i(build_edm_i), .decode_i(1'b0), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .dummy_sw_i(edm_dummy_sw_i), .lane_count_i(edm_lane_count_i), .length_per_lane_i(edm_length_per_lane_i),
    .komma01_i(edm_komma01_i), .komma23_i(edm_komma23_i), .payload_i(edm_payload_i),
    .payload_len_i(edm_payload_len_i), .komma45_i(edm_komma45_i), .komma67_i(edm_komma67_i),
    .packet_i('0), .packet_len_i('0), .packet_o(edm_pkt), .packet_len_o(edm_len), .seen_o(),
    .dummy_sw_o(), .lane_count_o(), .length_per_lane_o(), .komma01_o(), .komma23_o(), .payload_o(),
    .payload_len_o(), .komma45_o(), .komma67_o(), .crc_error_o(), .format_error_o()
  );

  edp_aux_codec u_aux(
    .encode_i(build_aux_i), .decode_i(1'b0), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .hpd_state_i(aux_hpd_state_i), .payload_i(aux_payload_i), .payload_len_i(aux_payload_len_i),
    .packet_i('0), .packet_len_i('0), .packet_o(aux_pkt), .packet_len_o(aux_len), .seen_o(),
    .hpd_state_o(), .payload_o(), .payload_len_o(), .crc_error_o(), .format_error_o()
  );

  edp_stream_clock_codec u_clk(
    .encode_i(build_stream_clock_i), .decode_i(1'b0), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .mvid_ptb_i(stream_mvid_ptb_i), .nvid_ptb_i(stream_nvid_ptb_i), .packet_i('0), .packet_len_i('0),
    .packet_o(clk_pkt), .packet_len_o(clk_len), .seen_o(), .mvid_ptb_o(), .nvid_ptb_o(), .crc_error_o(), .format_error_o()
  );

  edp_plm_8b10b_codec u_plm8(
    .encode_i(build_plm8_i), .decode_i(1'b0), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .lane_count_i(plm8_lane_count_i), .symbol_count_i(plm8_symbol_count_i), .symbols_i(plm8_symbols_i),
    .packet_i('0), .packet_len_i('0), .packet_o(plm8_pkt), .packet_len_o(plm8_len), .seen_o(),
    .lane_count_o(), .symbol_count_o(), .symbols_o(), .crc_error_o(), .format_error_o()
  );

  edp_plm_128b132b_codec u_plm132(
    .encode_i(build_plm132_i), .decode_i(1'b0), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .symbol_count_i(plm132_symbol_count_i), .symbols_i(plm132_symbols_i), .packet_i('0), .packet_len_i('0),
    .packet_o(plm132_pkt), .packet_len_o(plm132_len), .seen_o(), .symbol_count_o(), .symbols_o(),
    .crc_error_o(), .format_error_o()
  );

  always_comb begin
    packet_valid_o = build_vb_i || build_edm_i || build_aux_i || build_stream_clock_i || build_plm8_i || build_plm132_i;
    if (build_plm132_i) begin
      packet_o     = plm132_pkt;
      packet_len_o = plm132_len;
    end else if (build_plm8_i) begin
      packet_o     = plm8_pkt;
      packet_len_o = plm8_len;
    end else if (build_stream_clock_i) begin
      packet_o     = clk_pkt;
      packet_len_o = clk_len;
    end else if (build_aux_i) begin
      packet_o     = aux_pkt;
      packet_len_o = aux_len;
    end else if (build_edm_i) begin
      packet_o     = edm_pkt;
      packet_len_o = edm_len;
    end else begin
      packet_o     = vb_pkt;
      packet_len_o = vb_len;
    end
  end

endmodule

`default_nettype wire
