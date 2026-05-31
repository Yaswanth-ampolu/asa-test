`timescale 1ns/1ps
`default_nettype none

module i2c_bulk_codec
  import asa_asep_pkg::*;
  import asa_i2c_asep_pkg::*;
(
  input  logic                                     encode_i,
  input  logic                                     decode_i,
  input  logic [7:0]                               cmd_id_i,
  input  asep_ts_mode_e                            ts_mode_i,
  input  logic [31:0]                              ts_value_i,
  input  logic                                     i2c_error_i,
  input  logic                                     current_loc_i,
  input  i2c_bulk_fmt_e                            fmt_i,
  input  logic [6:0]                               slave_addr_i,
  input  logic [15:0]                              offset_addr_i,
  input  logic [15:0]                              length_i,
  input  logic                                     offset_16b_i,
  input  asep_packet_t                             payload_i,
  input  logic [(ASEP_MAX_PACKET_BYTES*8)-1:0]     ack_payload_i,
  input  asep_packet_t                             packet_i,
  input  logic [11:0]                              packet_len_i,
  output asep_packet_t                             packet_o,
  output logic [11:0]                              packet_len_o,
  output logic                                     seen_o,
  output logic [7:0]                               cmd_id_o,
  output logic                                     i2c_error_o,
  output logic                                     current_loc_o,
  output i2c_bulk_fmt_e                            fmt_o,
  output logic [6:0]                               slave_addr_o,
  output logic [15:0]                              offset_addr_o,
  output logic [15:0]                              length_o,
  output asep_packet_t                             payload_o,
  output logic [(ASEP_MAX_PACKET_BYTES*8)-1:0]     ack_payload_o,
  output logic                                     crc_error_o,
  output logic                                     format_error_o
);

  always_comb begin
    packet_o        = '0;
    packet_len_o    = '0;
    seen_o          = 1'b0;
    cmd_id_o        = 8'h00;
    i2c_error_o     = 1'b0;
    current_loc_o   = 1'b0;
    fmt_o           = I2C_BULK_WRITE;
    slave_addr_o    = 7'h00;
    offset_addr_o   = 16'h0000;
    length_o        = 16'h0000;
    payload_o       = '0;
    ack_payload_o   = '0;
    crc_error_o     = 1'b0;
    format_error_o  = 1'b0;

    if (encode_i) begin
      asep_packet_t pkt;
      logic [31:0] crc;
      int unsigned idx;
      int unsigned pay_bytes;
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
      pkt = asep_set_byte(pkt, idx + 1, i2c_bulk_cmd_byte(i2c_error_i, current_loc_i, fmt_i));
      case (fmt_i)
        I2C_BULK_WRITE: begin
          pkt = asep_set_byte(pkt, idx + 2, {1'b0, slave_addr_i});
          pkt = asep_set_byte(pkt, idx + 3, offset_addr_i[15:8]);
          pkt = asep_set_byte(pkt, idx + 4, offset_addr_i[7:0]);
          pkt = asep_set_byte(pkt, idx + 5, length_i[15:8]);
          pkt = asep_set_byte(pkt, idx + 6, length_i[7:0]);
          for (int i = 0; i < length_i; i++) begin
            pkt = asep_set_byte(pkt, idx + 7 + i, asep_get_byte(payload_i, i));
          end
          idx = idx + 7 + length_i;
        end
        I2C_BULK_READ: begin
          pkt = asep_set_byte(pkt, idx + 2, {1'b0, slave_addr_i});
          pkt = asep_set_byte(pkt, idx + 3, offset_addr_i[15:8]);
          pkt = asep_set_byte(pkt, idx + 4, offset_addr_i[7:0]);
          pkt = asep_set_byte(pkt, idx + 5, length_i[15:8]);
          pkt = asep_set_byte(pkt, idx + 6, length_i[7:0]);
          idx = idx + 7;
        end
        I2C_BULK_ACK_NACK: begin
          pay_bytes = i2c_bulk_ack_payload_bytes(length_i);
          pkt = asep_set_byte(pkt, idx + 2, length_i[15:8]);
          pkt = asep_set_byte(pkt, idx + 3, length_i[7:0]);
          pkt = asep_set_byte(pkt, idx + 4, {1'b0, slave_addr_i});
          for (int i = 0; i < pay_bytes; i++) begin
            pkt = asep_set_byte(pkt, idx + 5 + i, i2c_ack_payload_get(ack_payload_i, i));
          end
          idx = idx + 5 + pay_bytes;
        end
        default: begin
          pkt = asep_set_byte(pkt, idx + 2, length_i[15:8]);
          pkt = asep_set_byte(pkt, idx + 3, length_i[7:0]);
          pkt = asep_set_byte(pkt, idx + 4, {1'b0, slave_addr_i});
          pkt = asep_set_byte(pkt, idx + 5,
                              {1'b1,
                               (!offset_16b_i || current_loc_i),
                               (current_loc_i ? 1'b1 : 1'b0),
                               5'b11111});
          for (int i = 0; i < length_i; i++) begin
            pkt = asep_set_byte(pkt, idx + 6 + i, asep_get_byte(payload_i, i));
          end
          idx = idx + 6 + length_i;
        end
      endcase
      crc = asep_i2c_crc32(pkt, idx);
      pkt = asep_set_byte(pkt, idx + 0, crc[31:24]);
      pkt = asep_set_byte(pkt, idx + 1, crc[23:16]);
      pkt = asep_set_byte(pkt, idx + 2, crc[15:8]);
      pkt = asep_set_byte(pkt, idx + 3, crc[7:0]);
      packet_o     = pkt;
      packet_len_o = idx + 4;
    end

    if (decode_i) begin
      logic [7:0] b0, b1, cmd, ctrl, pkt_byte;
      logic [31:0] crc_calc, crc_seen;
      int unsigned idx;
      int unsigned pay_bytes;
      b0 = asep_get_byte(packet_i, 0);
      b1 = asep_get_byte(packet_i, 1);
      if (b0[7:1] != ASEP_STREAM_I2C) begin
        format_error_o = 1'b1;
      end else begin
        idx = i2c_ts_start_idx(asep_ts_mode_e'(b1[1:0]));
        if (packet_len_i < idx + 9) begin
          format_error_o = 1'b1;
        end else begin
          crc_calc = asep_i2c_crc32(packet_i, packet_len_i - 4);
          crc_seen = {asep_get_byte(packet_i, packet_len_i - 4),
                      asep_get_byte(packet_i, packet_len_i - 3),
                      asep_get_byte(packet_i, packet_len_i - 2),
                      asep_get_byte(packet_i, packet_len_i - 1)};
          if (crc_calc != crc_seen) begin
            crc_error_o = 1'b1;
          end else begin
            cmd = asep_get_byte(packet_i, idx + 1);
            if ({cmd[7], cmd[5]} != 2'b00) begin
              format_error_o = 1'b1;
            end else begin
              cmd_id_o      = asep_get_byte(packet_i, idx + 0);
              i2c_error_o   = cmd[6];
              current_loc_o = cmd[3];
              fmt_o         = i2c_bulk_fmt_e'(cmd[2:0]);
              case (fmt_o)
                I2C_BULK_WRITE: begin
                  if (packet_len_i < idx + 11) begin
                    format_error_o = 1'b1;
                  end else begin
                    pkt_byte      = asep_get_byte(packet_i, idx + 2);
                    slave_addr_o  = pkt_byte[6:0];
                    offset_addr_o = {asep_get_byte(packet_i, idx + 3), asep_get_byte(packet_i, idx + 4)};
                    length_o      = {asep_get_byte(packet_i, idx + 5), asep_get_byte(packet_i, idx + 6)};
                    if (packet_len_i != idx + 7 + length_o + 4) begin
                      format_error_o = 1'b1;
                    end else begin
                      for (int i = 0; i < length_o; i++) begin
                        payload_o = asep_set_byte(payload_o, i, asep_get_byte(packet_i, idx + 7 + i));
                      end
                      seen_o = 1'b1;
                    end
                  end
                end
                I2C_BULK_READ: begin
                  pkt_byte      = asep_get_byte(packet_i, idx + 2);
                  slave_addr_o  = pkt_byte[6:0];
                  offset_addr_o = {asep_get_byte(packet_i, idx + 3), asep_get_byte(packet_i, idx + 4)};
                  length_o      = {asep_get_byte(packet_i, idx + 5), asep_get_byte(packet_i, idx + 6)};
                  if (packet_len_i != idx + 7 + 4) begin
                    format_error_o = 1'b1;
                  end else begin
                    seen_o = 1'b1;
                  end
                end
                I2C_BULK_ACK_NACK: begin
                  length_o     = {asep_get_byte(packet_i, idx + 2), asep_get_byte(packet_i, idx + 3)};
                  pkt_byte     = asep_get_byte(packet_i, idx + 4);
                  slave_addr_o = pkt_byte[6:0];
                  pay_bytes    = i2c_bulk_ack_payload_bytes(length_o);
                  if (packet_len_i != idx + 5 + pay_bytes + 4) begin
                    format_error_o = 1'b1;
                  end else begin
                    for (int i = 0; i < pay_bytes; i++) begin
                      ack_payload_o = i2c_ack_payload_set(ack_payload_o, i, asep_get_byte(packet_i, idx + 5 + i));
                    end
                    seen_o = 1'b1;
                  end
                end
                I2C_BULK_READ_RESP: begin
                  length_o     = {asep_get_byte(packet_i, idx + 2), asep_get_byte(packet_i, idx + 3)};
                  pkt_byte     = asep_get_byte(packet_i, idx + 4);
                  slave_addr_o = pkt_byte[6:0];
                  if (packet_len_i != idx + 6 + length_o + 4) begin
                    format_error_o = 1'b1;
                  end else begin
                    ack_payload_o = i2c_ack_payload_set(ack_payload_o, 0, asep_get_byte(packet_i, idx + 5));
                    for (int i = 0; i < length_o; i++) begin
                      payload_o = asep_set_byte(payload_o, i, asep_get_byte(packet_i, idx + 6 + i));
                    end
                    seen_o = 1'b1;
                  end
                end
                default: format_error_o = 1'b1;
              endcase
            end
          end
        end
      end
    end
  end

endmodule

`default_nettype wire
