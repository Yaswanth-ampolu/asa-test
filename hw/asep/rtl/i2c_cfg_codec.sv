`timescale 1ns/1ps
`default_nettype none

module i2c_cfg_codec
  import asa_asep_pkg::*;
  import asa_i2c_asep_pkg::*;
(
  input  logic               encode_i,
  input  logic               decode_i,
  input  logic [7:0]         cmd_id_i,
  input  asep_ts_mode_e      ts_mode_i,
  input  logic [31:0]        ts_value_i,
  input  logic               i2c_error_i,
  input  i2c_cfg_cmd_e       cmd_i,
  input  logic [3:0]         addr_count_i,
  input  logic [5:0]         clock_rate_i,
  input  i2c_addr_cfg_vec_t  addr_cfg_i,
  input  logic               ack_ok_i,
  input  asep_packet_t       packet_i,
  input  logic [11:0]        packet_len_i,
  output asep_packet_t       packet_o,
  output logic [11:0]        packet_len_o,
  output logic               seen_o,
  output logic [7:0]         cmd_id_o,
  output logic               i2c_error_o,
  output i2c_cfg_cmd_e       cmd_o,
  output logic [3:0]         addr_count_o,
  output logic [5:0]         clock_rate_o,
  output i2c_addr_cfg_vec_t  addr_cfg_o,
  output logic               ack_ok_o,
  output logic               crc_error_o,
  output logic               format_error_o
);

  always_comb begin
    packet_o       = '0;
    packet_len_o   = '0;
    seen_o         = 1'b0;
    cmd_id_o       = 8'h00;
    i2c_error_o    = 1'b0;
    cmd_o          = I2C_CFG_WRITE;
    addr_count_o   = 4'h0;
    clock_rate_o   = 6'h00;
    addr_cfg_o     = '0;
    ack_ok_o       = 1'b0;
    crc_error_o    = 1'b0;
    format_error_o = 1'b0;

    if (encode_i) begin
      asep_packet_t pkt;
      logic [31:0] crc;
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
      pkt = asep_set_byte(pkt, idx + 1, i2c_cfg_cmd_hdr_byte(i2c_error_i, cmd_i));
      pkt = asep_set_byte(pkt, idx + 2, i2c_cfg_count_byte(addr_count_i));
      case (cmd_i)
        I2C_CFG_WRITE, I2C_CFG_READ_RESP: begin
          pkt = asep_set_byte(pkt, idx + 3, {2'b00, clock_rate_i});
          for (int i = 0; i < addr_count_i; i++) begin
            pkt = asep_set_byte(pkt, idx + 4 + i, i2c_addr_cfg_get(addr_cfg_i, i));
          end
          idx = idx + 4 + addr_count_i;
        end
        I2C_CFG_READ: begin
          idx = idx + 3;
        end
        default: begin
          pkt = asep_set_byte(pkt, idx + 3, {7'h00, ack_ok_i});
          idx = idx + 4;
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
      logic [7:0] b0, b1, hdr, cnt, pkt_byte;
      logic [31:0] crc_calc, crc_seen;
      int unsigned idx;
      b0 = asep_get_byte(packet_i, 0);
      b1 = asep_get_byte(packet_i, 1);
      if (b0[7:1] != ASEP_STREAM_I2C) begin
        format_error_o = 1'b1;
      end else begin
        idx = i2c_ts_start_idx(asep_ts_mode_e'(b1[1:0]));
        if (packet_len_i < idx + 7) begin
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
            hdr = asep_get_byte(packet_i, idx + 1);
            if ({hdr[7], hdr[5]} != 2'b01) begin
              format_error_o = 1'b1;
            end else begin
              cmd_id_o     = asep_get_byte(packet_i, idx + 0);
              i2c_error_o  = hdr[6];
              cmd_o        = i2c_cfg_cmd_e'(hdr[2:0]);
              cnt          = asep_get_byte(packet_i, idx + 2);
              addr_count_o = cnt[3:0];
              if (addr_count_o == 4'd0) begin
                format_error_o = 1'b1;
              end else begin
                case (cmd_o)
                  I2C_CFG_WRITE, I2C_CFG_READ_RESP: begin
                    if (packet_len_i != idx + 4 + addr_count_o + 4) begin
                      format_error_o = 1'b1;
                    end else begin
                      pkt_byte     = asep_get_byte(packet_i, idx + 3);
                      clock_rate_o = pkt_byte[5:0];
                      for (int i = 0; i < addr_count_o; i++) begin
                        addr_cfg_o = i2c_addr_cfg_set(addr_cfg_o, i, asep_get_byte(packet_i, idx + 4 + i));
                      end
                      seen_o = 1'b1;
                    end
                  end
                  I2C_CFG_READ: begin
                    if (packet_len_i != idx + 3 + 4) format_error_o = 1'b1;
                    else seen_o = 1'b1;
                  end
                  I2C_CFG_ACK_NACK: begin
                    if (packet_len_i != idx + 4 + 4) format_error_o = 1'b1;
                    else begin
                      pkt_byte = asep_get_byte(packet_i, idx + 3);
                      ack_ok_o = pkt_byte[0];
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
  end

endmodule

`default_nettype wire
