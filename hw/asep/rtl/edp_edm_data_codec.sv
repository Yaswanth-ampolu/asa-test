`timescale 1ns/1ps
`default_nettype none

module edp_edm_data_codec
#(
  parameter int unsigned PAYLOAD_BYTES = asa_edp_asep_pkg::EDP_MAX_EDM_BYTES
)
(
  input  logic            encode_i,
  input  logic            decode_i,
  input  asa_asep_pkg::asep_ts_mode_e ts_mode_i,
  input  logic [31:0]     ts_value_i,
  input  logic            dummy_sw_i,
  input  asa_edp_asep_pkg::edp_lane_count_e lane_count_i,
  input  logic [15:0]     length_per_lane_i,
  input  logic [7:0]      komma01_i,
  input  logic [7:0]      komma23_i,
  input  logic [(PAYLOAD_BYTES*8)-1:0] payload_i,
  input  logic [11:0]     payload_len_i,
  input  logic [7:0]      komma45_i,
  input  logic [7:0]      komma67_i,
  input  asa_asep_pkg::asep_packet_t packet_i,
  input  logic [11:0]     packet_len_i,
  output asa_asep_pkg::asep_packet_t packet_o,
  output logic [11:0]     packet_len_o,
  output logic            seen_o,
  output logic            dummy_sw_o,
  output asa_edp_asep_pkg::edp_lane_count_e lane_count_o,
  output logic [15:0]     length_per_lane_o,
  output logic [7:0]      komma01_o,
  output logic [7:0]      komma23_o,
  output logic [(PAYLOAD_BYTES*8)-1:0] payload_o,
  output logic [11:0]     payload_len_o,
  output logic [7:0]      komma45_o,
  output logic [7:0]      komma67_o,
  output logic            crc_error_o,
  output logic            format_error_o
);
  import asa_asep_pkg::*;
  import asa_edp_asep_pkg::*;

  always @* begin
    int unsigned hdr_idx;
    int unsigned lane_mult;
    logic [31:0] crc_seen, crc_calc;
    logic [7:0] byte1, type_byte;
    packet_o         = '0;
    packet_len_o     = 12'd0;
    seen_o           = 1'b0;
    dummy_sw_o       = 1'b0;
    lane_count_o     = EDP_LANES_1;
    length_per_lane_o= 16'd0;
    komma01_o        = 8'd0;
    komma23_o        = 8'd0;
    payload_o        = '0;
    payload_len_o    = 12'd0;
    komma45_o        = 8'd0;
    komma67_o        = 8'd0;
    crc_error_o      = 1'b0;
    format_error_o   = 1'b0;
    hdr_idx          = asep_common_hdr_bytes(ts_mode_i);
    lane_mult        = edp_lane_mult(lane_count_i);

    if (encode_i) begin
      asep_packet_t pkt;
      logic [11:0] enc_packet_len;
      logic enc_format_error;
      pkt = '0;
      pkt[0*8 +: 8] = asep_hdr_byte0(ASEP_STREAM_EDP, 1'b0);
      pkt[1*8 +: 8] = asep_hdr_byte1(ts_mode_i);
      if (ts_mode_i != ASEP_TS_NONE) begin
        pkt[2*8 +: 8] = ts_value_i[31:24];
        pkt[3*8 +: 8] = ts_value_i[23:16];
        pkt[4*8 +: 8] = ts_value_i[15:8];
        pkt[5*8 +: 8] = ts_value_i[7:0];
      end
      pkt[(hdr_idx + 0)*8 +: 8] = {EDP_PKT_EDM_DATA, dummy_sw_i, lane_count_i, 2'b00};
      pkt[(hdr_idx + 1)*8 +: 8] = length_per_lane_i[15:8];
      pkt[(hdr_idx + 2)*8 +: 8] = length_per_lane_i[7:0];
      pkt[(hdr_idx + 3)*8 +: 8] = komma01_i;
      pkt[(hdr_idx + 4)*8 +: 8] = komma23_i;
      for (int i = 0; i < payload_len_i; i++) begin
        pkt[(hdr_idx + 5 + i)*8 +: 8] = payload_i[i*8 +: 8];
      end
      pkt[(hdr_idx + 5 + payload_len_i + 0)*8 +: 8] = komma45_i;
      pkt[(hdr_idx + 5 + payload_len_i + 1)*8 +: 8] = komma67_i;
      enc_packet_len = hdr_idx + 11 + payload_len_i;
      enc_format_error = !edp_lane_valid(lane_count_i) ||
                         !edp_komma_valid(komma01_i[7:4]) || !edp_komma_valid(komma01_i[3:0]) ||
                         !edp_komma_valid(komma23_i[7:4]) || !edp_komma_valid(komma23_i[3:0]) ||
                         !edp_komma_valid(komma45_i[7:4]) || !edp_komma_valid(komma45_i[3:0]) ||
                         !edp_komma_valid(komma67_i[7:4]) || !edp_komma_valid(komma67_i[3:0]) ||
                         (payload_len_i != length_per_lane_i * lane_mult);
      crc_calc = asep_edp_crc32(pkt, 0, enc_packet_len - 4);
      pkt[(enc_packet_len - 4)*8 +: 8] = crc_calc[31:24];
      pkt[(enc_packet_len - 3)*8 +: 8] = crc_calc[23:16];
      pkt[(enc_packet_len - 2)*8 +: 8] = crc_calc[15:8];
      pkt[(enc_packet_len - 1)*8 +: 8] = crc_calc[7:0];
      packet_len_o = enc_packet_len;
      format_error_o = enc_format_error;
      packet_o = pkt;
    end

    if (decode_i) begin
      byte1 = asep_get_byte(packet_i, 1);
      hdr_idx = asep_common_hdr_bytes(asep_ts_mode_e'(byte1[1:0]));
      type_byte = asep_get_byte(packet_i, hdr_idx);
      if ((packet_len_i >= (hdr_idx + 11)) && (type_byte[7:5] == EDP_PKT_EDM_DATA)) begin
        logic [11:0] dec_payload_len;
        edp_lane_count_e dec_lane_count;
        logic [15:0] dec_length_per_lane;
        logic [7:0] dec_k01, dec_k23, dec_k45, dec_k67;
        logic dec_format_error;
        logic [(PAYLOAD_BYTES*8)-1:0] payload_tmp;
        seen_o            = 1'b1;
        dummy_sw_o        = type_byte[4];
        dec_lane_count    = edp_lane_count_e'(type_byte[3:2]);
        dec_length_per_lane = {asep_get_byte(packet_i, hdr_idx + 1), asep_get_byte(packet_i, hdr_idx + 2)};
        dec_k01           = asep_get_byte(packet_i, hdr_idx + 3);
        dec_k23           = asep_get_byte(packet_i, hdr_idx + 4);
        dec_payload_len   = packet_len_i - hdr_idx - 11;
        payload_tmp       = '0;
        for (int i = 0; i < dec_payload_len; i++) begin
          payload_tmp[i*8 +: 8] = packet_i[(hdr_idx + 5 + i)*8 +: 8];
        end
        dec_k45 = asep_get_byte(packet_i, hdr_idx + 5 + dec_payload_len + 0);
        dec_k67 = asep_get_byte(packet_i, hdr_idx + 5 + dec_payload_len + 1);
        lane_mult = edp_lane_mult(dec_lane_count);
        dec_format_error = (type_byte[1:0] != 2'b00) ||
                           !edp_lane_valid(dec_lane_count) ||
                           !edp_komma_valid(dec_k01[7:4]) || !edp_komma_valid(dec_k01[3:0]) ||
                           !edp_komma_valid(dec_k23[7:4]) || !edp_komma_valid(dec_k23[3:0]) ||
                           !edp_komma_valid(dec_k45[7:4]) || !edp_komma_valid(dec_k45[3:0]) ||
                           !edp_komma_valid(dec_k67[7:4]) || !edp_komma_valid(dec_k67[3:0]) ||
                           (dec_payload_len != dec_length_per_lane * lane_mult);
        lane_count_o      = dec_lane_count;
        length_per_lane_o = dec_length_per_lane;
        komma01_o         = dec_k01;
        komma23_o         = dec_k23;
        payload_o         = payload_tmp;
        payload_len_o     = dec_payload_len;
        komma45_o         = dec_k45;
        komma67_o         = dec_k67;
        format_error_o    = dec_format_error;
        crc_calc = asep_edp_crc32(packet_i, 0, packet_len_i - 4);
        crc_seen = {asep_get_byte(packet_i, packet_len_i - 4),
                    asep_get_byte(packet_i, packet_len_i - 3),
                    asep_get_byte(packet_i, packet_len_i - 2),
                    asep_get_byte(packet_i, packet_len_i - 1)};
        crc_error_o = (crc_calc != crc_seen);
      end
    end
  end

endmodule

`default_nettype wire
