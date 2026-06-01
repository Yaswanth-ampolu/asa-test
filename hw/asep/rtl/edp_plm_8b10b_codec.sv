`timescale 1ns/1ps
`default_nettype none

module edp_plm_8b10b_codec
#(
  parameter int unsigned MAX_SYMBOLS = asa_edp_asep_pkg::EDP_MAX_PLM10_SYMBOLS
)
(
  input  logic            encode_i,
  input  logic            decode_i,
  input  asa_asep_pkg::asep_ts_mode_e ts_mode_i,
  input  logic [31:0]     ts_value_i,
  input  asa_edp_asep_pkg::edp_lane_count_e lane_count_i,
  input  logic [15:0]     symbol_count_i,
  input  logic [(MAX_SYMBOLS*10)-1:0] symbols_i,
  input  asa_asep_pkg::asep_packet_t packet_i,
  input  logic [11:0]     packet_len_i,
  output asa_asep_pkg::asep_packet_t packet_o,
  output logic [11:0]     packet_len_o,
  output logic            seen_o,
  output asa_edp_asep_pkg::edp_lane_count_e lane_count_o,
  output logic [15:0]     symbol_count_o,
  output logic [(MAX_SYMBOLS*10)-1:0] symbols_o,
  output logic            crc_error_o,
  output logic            format_error_o
);
  import asa_asep_pkg::*;
  import asa_edp_asep_pkg::*;

  always @* begin
    int unsigned hdr_idx;
    int unsigned payload_bytes;
    int unsigned i;
    logic [31:0] crc_seen, crc_calc;
    logic [7:0] byte1, type_byte;
    packet_o        = '0;
    packet_len_o    = 12'd0;
    seen_o          = 1'b0;
    lane_count_o    = EDP_LANES_1;
    symbol_count_o  = 16'd0;
    symbols_o       = '0;
    crc_error_o     = 1'b0;
    format_error_o  = 1'b0;
    hdr_idx         = asep_common_hdr_bytes(ts_mode_i);
    payload_bytes   = edp_bytes_for_10b(symbol_count_i);

    if (encode_i) begin
      asep_packet_t pkt;
      pkt = '0;
      pkt[0*8 +: 8] = asep_hdr_byte0(ASEP_STREAM_EDP, 1'b0);
      pkt[1*8 +: 8] = asep_hdr_byte1(ts_mode_i);
      if (ts_mode_i != ASEP_TS_NONE) begin
        pkt[2*8 +: 8] = ts_value_i[31:24];
        pkt[3*8 +: 8] = ts_value_i[23:16];
        pkt[4*8 +: 8] = ts_value_i[15:8];
        pkt[5*8 +: 8] = ts_value_i[7:0];
      end
      pkt[(hdr_idx + 0)*8 +: 8] = {EDP_PKT_PLM_8B10B, 3'b000, lane_count_i};
      pkt[(hdr_idx + 1)*8 +: 8] = symbol_count_i[15:8];
      pkt[(hdr_idx + 2)*8 +: 8] = symbol_count_i[7:0];
      for (i = 0; i < symbol_count_i; i++) begin
        logic [9:0] sym;
        sym = symbols_i[i*10 +: 10];
        for (int b = 0; b < 10; b++) begin
          int unsigned byte_idx;
          int unsigned bit_idx;
          byte_idx = hdr_idx + 3 + ((i*10 + b) / 8);
          bit_idx  = 7 - ((i*10 + b) % 8);
          pkt[byte_idx*8 + bit_idx] = sym[9-b];
        end
      end
      packet_len_o = hdr_idx + 3 + payload_bytes + 4;
      format_error_o = !edp_lane_valid(lane_count_i);
      crc_calc = asep_edp_crc32(pkt, 0, packet_len_o - 4);
      pkt[(packet_len_o - 4)*8 +: 8] = crc_calc[31:24];
      pkt[(packet_len_o - 3)*8 +: 8] = crc_calc[23:16];
      pkt[(packet_len_o - 2)*8 +: 8] = crc_calc[15:8];
      pkt[(packet_len_o - 1)*8 +: 8] = crc_calc[7:0];
      packet_o = pkt;
    end

    if (decode_i) begin
      byte1 = asep_get_byte(packet_i, 1);
      hdr_idx = asep_common_hdr_bytes(asep_ts_mode_e'(byte1[1:0]));
      type_byte = asep_get_byte(packet_i, hdr_idx);
      if ((packet_len_i >= (hdr_idx + 7)) && (type_byte[7:5] == EDP_PKT_PLM_8B10B)) begin
        edp_lane_count_e dec_lane_count;
        logic [15:0] dec_symbol_count;
        logic [(MAX_SYMBOLS*10)-1:0] sym_vec_tmp;
        seen_o         = 1'b1;
        dec_lane_count = edp_lane_count_e'(type_byte[1:0]);
        dec_symbol_count = {asep_get_byte(packet_i, hdr_idx + 1), asep_get_byte(packet_i, hdr_idx + 2)};
        lane_count_o   = dec_lane_count;
        symbol_count_o = dec_symbol_count;
        payload_bytes  = edp_bytes_for_10b(dec_symbol_count);
        sym_vec_tmp    = '0;
        for (i = 0; i < dec_symbol_count; i++) begin
          logic [9:0] sym;
          sym = 10'd0;
          for (int b = 0; b < 10; b++) begin
            sym[9-b] = edp_packet_get_be_bit(packet_i, hdr_idx + 3, i*10 + b);
          end
          sym_vec_tmp[i*10 +: 10] = sym;
        end
        symbols_o = sym_vec_tmp;
        format_error_o = (type_byte[4:2] != 3'b000) ||
                         !edp_lane_valid(dec_lane_count) ||
                         (packet_len_i != (hdr_idx + 3 + payload_bytes + 4));
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
