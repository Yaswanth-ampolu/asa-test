`timescale 1ns/1ps
`default_nettype none

module i2c_byte_codec
  import asa_asep_pkg::*;
  import asa_i2c_asep_pkg::*;
(
  input  logic          encode_i,
  input  logic          decode_i,
  input  logic [7:0]    cmd_id_i,
  input  asep_ts_mode_e ts_mode_i,
  input  logic [31:0]   ts_value_i,
  input  logic          i2c_error_i,
  input  logic          start_i,
  input  logic          stop_i,
  input  logic          ack_i,
  input  logic          nack_i,
  input  logic          data_valid_i,
  input  logic [7:0]    data_i,
  input  asep_packet_t  packet_i,
  input  logic [11:0]   packet_len_i,
  output asep_packet_t  packet_o,
  output logic [11:0]   packet_len_o,
  output logic          seen_o,
  output logic [7:0]    cmd_id_o,
  output logic          i2c_error_o,
  output logic          start_o,
  output logic          stop_o,
  output logic          ack_o,
  output logic          nack_o,
  output logic          data_valid_o,
  output logic [7:0]    data_o,
  output logic          format_error_o
);

  always_comb begin
    packet_o        = '0;
    packet_len_o    = '0;
    seen_o          = 1'b0;
    cmd_id_o        = 8'h00;
    i2c_error_o     = 1'b0;
    start_o         = 1'b0;
    stop_o          = 1'b0;
    ack_o           = 1'b0;
    nack_o          = 1'b0;
    data_valid_o    = 1'b0;
    data_o          = 8'h00;
    format_error_o  = 1'b0;

    if (encode_i) begin
      asep_packet_t pkt;
      int unsigned idx;
      pkt = '0;
      pkt = asep_set_byte(pkt, 0, asep_hdr_byte0(ASEP_STREAM_I2C, 1'b0));
      pkt = asep_set_byte(pkt, 1, asep_hdr_byte1(ts_mode_i));
      if (ts_mode_i == ASEP_TS_NONE) begin
        idx = 2;
      end else begin
        pkt = asep_set_byte(pkt, 2, ts_value_i[31:24]);
        pkt = asep_set_byte(pkt, 3, ts_value_i[23:16]);
        pkt = asep_set_byte(pkt, 4, ts_value_i[15:8]);
        pkt = asep_set_byte(pkt, 5, ts_value_i[7:0]);
        idx = 6;
      end
      pkt = asep_set_byte(pkt, idx + 0, cmd_id_i);
      pkt = asep_set_byte(pkt, idx + 1, i2c_byte_cmd_byte(i2c_error_i, data_valid_i, nack_i, ack_i, stop_i, start_i));
      if (data_valid_i) begin
        pkt = asep_set_byte(pkt, idx + 2, data_i);
        packet_len_o = idx + 3;
      end else begin
        packet_len_o = idx + 2;
      end
      packet_o = pkt;
    end

    if (decode_i) begin
      int unsigned idx;
      logic [7:0] b0, b1, cmd;
      b0 = asep_get_byte(packet_i, 0);
      b1 = asep_get_byte(packet_i, 1);
      if (b0[7:1] != ASEP_STREAM_I2C) begin
        format_error_o = 1'b1;
      end else begin
        idx = i2c_ts_start_idx(asep_ts_mode_e'(b1[1:0]));
        if (packet_len_i < idx + 2) begin
          format_error_o = 1'b1;
        end else begin
          cmd_id_o    = asep_get_byte(packet_i, idx + 0);
          cmd         = asep_get_byte(packet_i, idx + 1);
          if ({cmd[7], cmd[5]} != 2'b10) begin
            format_error_o = 1'b1;
          end else if ((cmd[4] && (packet_len_i != idx + 3)) || (!cmd[4] && (packet_len_i != idx + 2))) begin
            format_error_o = 1'b1;
          end else begin
            seen_o       = 1'b1;
            i2c_error_o  = cmd[6];
            data_valid_o = cmd[4];
            nack_o       = cmd[3];
            ack_o        = cmd[2];
            stop_o       = cmd[1];
            start_o      = cmd[0];
            if (cmd[4]) data_o = asep_get_byte(packet_i, idx + 2);
          end
        end
      end
    end
  end

endmodule

`default_nettype wire
