`timescale 1ns/1ps
`default_nettype none

module edp_asd_rx
  import asa_asep_pkg::*;
  import asa_edp_asep_pkg::*;
(
  input  logic            clk,
  input  logic            rst,
  input  logic            soft_reset_i,
  input  logic            rx_packet_valid_i,
  input  asep_packet_t    rx_packet_i,
  input  logic [11:0]     rx_packet_len_i,
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

  logic vb_seen, vb_crc, vb_fmt;
  logic [31:0] vb_vbid, vb_mvid, vb_maud;
  logic edm_seen, edm_crc, edm_fmt, edm_dummy;
  edp_lane_count_e edm_lanes;
  logic [15:0] edm_len_per_lane;
  logic [7:0] edm_k01, edm_k23, edm_k45, edm_k67;
  edp_payload_t edm_payload;
  logic [11:0] edm_payload_len;
  logic aux_seen, aux_crc, aux_fmt;
  edp_hpd_state_e aux_hpd;
  edp_payload_t aux_payload;
  logic [4:0] aux_len;
  logic clk_seen, clk_crc, clk_fmt;
  logic [23:0] clk_mvid, clk_nvid;
  logic plm8_seen, plm8_crc, plm8_fmt;
  edp_lane_count_e plm8_lanes;
  logic [15:0] plm8_count;
  edp_plm10_vec_t plm8_syms;
  logic plm132_seen, plm132_crc, plm132_fmt;
  logic [15:0] plm132_count;
  edp_plm132_vec_t plm132_syms;

  edp_vb_codec u_vb(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0), .vbid_i('0), .mvid_i('0), .maud_i('0),
    .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i), .packet_o(), .packet_len_o(), .seen_o(vb_seen),
    .vbid_o(vb_vbid), .mvid_o(vb_mvid), .maud_o(vb_maud), .crc_error_o(vb_crc), .format_error_o(vb_fmt)
  );

  edp_edm_data_codec u_edm(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0), .dummy_sw_i('0),
    .lane_count_i(EDP_LANES_1), .length_per_lane_i('0), .komma01_i('0), .komma23_i('0), .payload_i('0), .payload_len_i('0),
    .komma45_i('0), .komma67_i('0), .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i), .packet_o(), .packet_len_o(),
    .seen_o(edm_seen), .dummy_sw_o(edm_dummy), .lane_count_o(edm_lanes), .length_per_lane_o(edm_len_per_lane), .komma01_o(edm_k01),
    .komma23_o(edm_k23), .payload_o(edm_payload), .payload_len_o(edm_payload_len), .komma45_o(edm_k45), .komma67_o(edm_k67),
    .crc_error_o(edm_crc), .format_error_o(edm_fmt)
  );

  edp_aux_codec u_aux(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0), .hpd_state_i(EDP_HPD_LOW),
    .payload_i('0), .payload_len_i('0), .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i), .packet_o(), .packet_len_o(),
    .seen_o(aux_seen), .hpd_state_o(aux_hpd), .payload_o(aux_payload), .payload_len_o(aux_len), .crc_error_o(aux_crc), .format_error_o(aux_fmt)
  );

  edp_stream_clock_codec u_clk(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0), .mvid_ptb_i('0), .nvid_ptb_i('0),
    .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i), .packet_o(), .packet_len_o(), .seen_o(clk_seen),
    .mvid_ptb_o(clk_mvid), .nvid_ptb_o(clk_nvid), .crc_error_o(clk_crc), .format_error_o(clk_fmt)
  );

  edp_plm_8b10b_codec u_plm8(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0), .lane_count_i(EDP_LANES_1),
    .symbol_count_i('0), .symbols_i('0), .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i), .packet_o(), .packet_len_o(),
    .seen_o(plm8_seen), .lane_count_o(plm8_lanes), .symbol_count_o(plm8_count), .symbols_o(plm8_syms),
    .crc_error_o(plm8_crc), .format_error_o(plm8_fmt)
  );

  edp_plm_128b132b_codec u_plm132(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0), .symbol_count_i('0), .symbols_i('0),
    .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i), .packet_o(), .packet_len_o(), .seen_o(plm132_seen),
    .symbol_count_o(plm132_count), .symbols_o(plm132_syms), .crc_error_o(plm132_crc), .format_error_o(plm132_fmt)
  );

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      rx_vb_seen_o            <= 1'b0;
      rx_edm_seen_o           <= 1'b0;
      rx_aux_seen_o           <= 1'b0;
      rx_stream_clock_seen_o  <= 1'b0;
      rx_plm8_seen_o          <= 1'b0;
      rx_plm132_seen_o        <= 1'b0;
      rx_vb_vbid_o            <= 32'd0;
      rx_vb_mvid_o            <= 32'd0;
      rx_vb_maud_o            <= 32'd0;
      rx_edm_dummy_sw_o       <= 1'b0;
      rx_edm_lane_count_o     <= EDP_LANES_1;
      rx_edm_length_per_lane_o<= 16'd0;
      rx_edm_komma01_o        <= 8'd0;
      rx_edm_komma23_o        <= 8'd0;
      rx_edm_payload_o        <= '0;
      rx_edm_payload_len_o    <= 12'd0;
      rx_edm_komma45_o        <= 8'd0;
      rx_edm_komma67_o        <= 8'd0;
      rx_aux_hpd_state_o      <= EDP_HPD_LOW;
      rx_aux_payload_o        <= '0;
      rx_aux_payload_len_o    <= 5'd0;
      rx_stream_mvid_ptb_o    <= 24'd0;
      rx_stream_nvid_ptb_o    <= 24'd0;
      rx_plm8_lane_count_o    <= EDP_LANES_1;
      rx_plm8_symbol_count_o  <= 16'd0;
      rx_plm8_symbols_o       <= '0;
      rx_plm132_symbol_count_o<= 16'd0;
      rx_plm132_symbols_o     <= '0;
      rx_crc_error_o          <= 1'b0;
      rx_format_error_o       <= 1'b0;
    end else begin
      rx_vb_seen_o            <= 1'b0;
      rx_edm_seen_o           <= 1'b0;
      rx_aux_seen_o           <= 1'b0;
      rx_stream_clock_seen_o  <= 1'b0;
      rx_plm8_seen_o          <= 1'b0;
      rx_plm132_seen_o        <= 1'b0;
      rx_crc_error_o          <= 1'b0;
      rx_format_error_o       <= 1'b0;
      if (soft_reset_i) begin
        // stateless decode path
      end else if (rx_packet_valid_i) begin
        if (vb_seen) begin
          rx_vb_seen_o         <= 1'b1;
          rx_vb_vbid_o         <= vb_vbid;
          rx_vb_mvid_o         <= vb_mvid;
          rx_vb_maud_o         <= vb_maud;
          rx_crc_error_o       <= vb_crc;
          rx_format_error_o    <= vb_fmt;
        end else if (edm_seen) begin
          rx_edm_seen_o        <= 1'b1;
          rx_edm_dummy_sw_o    <= edm_dummy;
          rx_edm_lane_count_o  <= edm_lanes;
          rx_edm_length_per_lane_o <= edm_len_per_lane;
          rx_edm_komma01_o     <= edm_k01;
          rx_edm_komma23_o     <= edm_k23;
          rx_edm_payload_o     <= edm_payload;
          rx_edm_payload_len_o <= edm_payload_len;
          rx_edm_komma45_o     <= edm_k45;
          rx_edm_komma67_o     <= edm_k67;
          rx_crc_error_o       <= edm_crc;
          rx_format_error_o    <= edm_fmt;
        end else if (aux_seen) begin
          rx_aux_seen_o        <= 1'b1;
          rx_aux_hpd_state_o   <= aux_hpd;
          rx_aux_payload_o     <= aux_payload;
          rx_aux_payload_len_o <= aux_len;
          rx_crc_error_o       <= aux_crc;
          rx_format_error_o    <= aux_fmt;
        end else if (clk_seen) begin
          rx_stream_clock_seen_o <= 1'b1;
          rx_stream_mvid_ptb_o   <= clk_mvid;
          rx_stream_nvid_ptb_o   <= clk_nvid;
          rx_crc_error_o         <= clk_crc;
          rx_format_error_o      <= clk_fmt;
        end else if (plm8_seen) begin
          rx_plm8_seen_o         <= 1'b1;
          rx_plm8_lane_count_o   <= plm8_lanes;
          rx_plm8_symbol_count_o <= plm8_count;
          rx_plm8_symbols_o      <= plm8_syms;
          rx_crc_error_o         <= plm8_crc;
          rx_format_error_o      <= plm8_fmt;
        end else if (plm132_seen) begin
          rx_plm132_seen_o        <= 1'b1;
          rx_plm132_symbol_count_o<= plm132_count;
          rx_plm132_symbols_o     <= plm132_syms;
          rx_crc_error_o          <= plm132_crc;
          rx_format_error_o       <= plm132_fmt;
        end
      end
    end
  end

endmodule

`default_nettype wire
