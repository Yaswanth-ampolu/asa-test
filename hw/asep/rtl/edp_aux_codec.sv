`timescale 1ns/1ps
`default_nettype none

module edp_aux_codec
  import asa_asep_pkg::*;
  import asa_edp_asep_pkg::*;
(
  input  logic           encode_i,
  input  logic           decode_i,
  input  asep_ts_mode_e  ts_mode_i,
  input  logic [31:0]    ts_value_i,
  input  edp_hpd_state_e hpd_state_i,
  input  edp_payload_t   payload_i,
  input  logic [4:0]     payload_len_i,
  input  asep_packet_t   packet_i,
  input  logic [11:0]    packet_len_i,
  output asep_packet_t   packet_o,
  output logic [11:0]    packet_len_o,
  output logic           seen_o,
  output edp_hpd_state_e hpd_state_o,
  output edp_payload_t   payload_o,
  output logic [4:0]     payload_len_o,
  output logic           crc_error_o,
  output logic           format_error_o
);

  always_comb begin
    int unsigned hdr_idx;
    logic [31:0] crc_seen, crc_calc;
    logic [7:0] byte1, type_byte, len_byte;
    packet_o       = '0;
    packet_len_o   = 12'd0;
    seen_o         = 1'b0;
    hpd_state_o    = EDP_HPD_LOW;
    payload_o      = '0;
    payload_len_o  = 5'd0;
    crc_error_o    = 1'b0;
    format_error_o = 1'b0;
    hdr_idx        = asep_common_hdr_bytes(ts_mode_i);

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
      pkt[(hdr_idx + 0)*8 +: 8] = {EDP_PKT_AUX, hpd_state_i, 3'b000};
      pkt[(hdr_idx + 1)*8 +: 8] = {3'b000, payload_len_i};
      for (int i = 0; i < payload_len_i; i++) begin
        pkt[(hdr_idx + 2 + i)*8 +: 8] = payload_i[i*8 +: 8];
      end
      packet_len_o = hdr_idx + 6 + payload_len_i;
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
      len_byte = asep_get_byte(packet_i, hdr_idx + 1);
      if ((packet_len_i >= (hdr_idx + 6)) && (type_byte[7:5] == EDP_PKT_AUX)) begin
        logic [4:0] dec_payload_len;
        edp_payload_t payload_tmp;
        seen_o        = 1'b1;
        hpd_state_o   = edp_hpd_state_e'(type_byte[4:3]);
        dec_payload_len = len_byte[4:0];
        payload_len_o = dec_payload_len;
        payload_tmp   = '0;
        for (int i = 0; i < dec_payload_len; i++) begin
          payload_tmp[i*8 +: 8] = packet_i[(hdr_idx + 2 + i)*8 +: 8];
        end
        payload_o = payload_tmp;
        format_error_o = (type_byte[2:0] != 3'b000) ||
                         (len_byte[7:5] != 3'b000) ||
                         (packet_len_i != (hdr_idx + 6 + dec_payload_len));
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
