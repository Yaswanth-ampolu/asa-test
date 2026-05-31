`timescale 1ns/1ps
`default_nettype none

module i2s_cfg_codec
  import asa_asep_pkg::*;
  import asa_i2s_asep_pkg::*;
(
  input  logic            encode_i,
  input  logic            decode_i,
  input  logic [6:0]      pkt_id_i,
  input  asep_ts_mode_e   ts_mode_i,
  input  logic [31:0]     ts_value_i,
  input  i2s_cfg_cmd_e    cmd_i,
  input  logic            ack_ok_i,
  input  i2s_bit_depth_e  bit_depth_i,
  input  i2s_data_fmt_e   data_fmt_i,
  input  logic [2:0]      num_channels_i,
  input  logic [4:0]      sample_rate_i,
  input  logic            timing_host_rx_i,
  input  logic            target_clk_mck_i,
  input  logic [9:0]      coeff_k_i,
  input  logic [15:0]     divisor_n_i,
  input  asep_packet_t    packet_i,
  input  logic [11:0]     packet_len_i,
  output asep_packet_t    packet_o,
  output logic [11:0]     packet_len_o,
  output logic            seen_o,
  output logic [6:0]      pkt_id_o,
  output i2s_cfg_cmd_e    cmd_o,
  output logic            ack_ok_o,
  output i2s_bit_depth_e  bit_depth_o,
  output i2s_data_fmt_e   data_fmt_o,
  output logic [2:0]      num_channels_o,
  output logic [4:0]      sample_rate_o,
  output logic            timing_host_rx_o,
  output logic            target_clk_mck_o,
  output logic [9:0]      coeff_k_o,
  output logic [15:0]     divisor_n_o,
  output logic            crc_error_o,
  output logic            format_error_o
);

  always_comb begin
    packet_o         = '0;
    packet_len_o     = '0;
    seen_o           = 1'b0;
    pkt_id_o         = 7'd0;
    cmd_o            = I2S_CFG_WRITE;
    ack_ok_o         = 1'b0;
    bit_depth_o      = I2S_DEPTH_8;
    data_fmt_o       = I2S_FMT_I2S;
    num_channels_o   = 3'd0;
    sample_rate_o    = 5'd0;
    timing_host_rx_o = 1'b0;
    target_clk_mck_o = 1'b0;
    coeff_k_o        = 10'd0;
    divisor_n_o      = 16'd0;
    crc_error_o      = 1'b0;
    format_error_o   = 1'b0;

    if (encode_i) begin
      asep_packet_t pkt;
      logic [31:0] crc;
      int unsigned idx;
      pkt = '0;
      pkt = asep_set_byte(pkt, 0, asep_hdr_byte0(ASEP_STREAM_I2S, 1'b0));
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
      pkt = asep_set_byte(pkt, idx + 0, i2s_pkt_header_byte(1'b0, pkt_id_i));
      pkt = asep_set_byte(pkt, idx + 1, {cmd_i, 1'b0, ack_ok_i & (cmd_i == I2S_CFG_ACK), bit_depth_i});
      if (cmd_i != I2S_CFG_READ) begin
        pkt = asep_set_byte(pkt, idx + 2, {1'b0, data_fmt_i, 1'b0, num_channels_i});
        pkt = asep_set_byte(pkt, idx + 3, {3'b000, sample_rate_i});
        pkt = asep_set_byte(pkt, idx + 4, {1'b0, timing_host_rx_i, target_clk_mck_i, 1'b0, 2'b00, coeff_k_i[9:8]});
        pkt = asep_set_byte(pkt, idx + 5, coeff_k_i[7:0]);
        pkt = asep_set_byte(pkt, idx + 6, divisor_n_i[15:8]);
        pkt = asep_set_byte(pkt, idx + 7, divisor_n_i[7:0]);
        idx = idx + 8;
      end else begin
        idx = idx + 2;
      end
      crc = asep_i2s_crc32(pkt, idx);
      pkt = asep_set_byte(pkt, idx + 0, crc[31:24]);
      pkt = asep_set_byte(pkt, idx + 1, crc[23:16]);
      pkt = asep_set_byte(pkt, idx + 2, crc[15:8]);
      pkt = asep_set_byte(pkt, idx + 3, crc[7:0]);
      packet_o     = pkt;
      packet_len_o = idx + 4;
    end

    if (decode_i) begin
      logic [7:0] b0, b1, hdr, c0, c1, c2, c3, c4, c5;
      logic [31:0] crc_calc, crc_seen;
      int unsigned idx;
      b0 = asep_get_byte(packet_i, 0);
      b1 = asep_get_byte(packet_i, 1);
      if (b0[7:1] != ASEP_STREAM_I2S) begin
        format_error_o = 1'b1;
      end else begin
        idx = i2s_ts_start_idx(asep_ts_mode_e'(b1[1:0]));
        if (packet_len_i < idx + 2 + 4) begin
          format_error_o = 1'b1;
        end else begin
          crc_calc = asep_i2s_crc32(packet_i, packet_len_i - 4);
          crc_seen = {asep_get_byte(packet_i, packet_len_i - 4),
                      asep_get_byte(packet_i, packet_len_i - 3),
                      asep_get_byte(packet_i, packet_len_i - 2),
                      asep_get_byte(packet_i, packet_len_i - 1)};
          if (crc_calc != crc_seen) begin
            crc_error_o = 1'b1;
          end else begin
            hdr = asep_get_byte(packet_i, idx + 0);
            if (hdr[7] != 1'b0) begin
              format_error_o = 1'b1;
            end else begin
              pkt_id_o = hdr[6:0];
              c0 = asep_get_byte(packet_i, idx + 1);
              cmd_o = i2s_cfg_cmd_e'(c0[7:6]);
              ack_ok_o = c0[4];
              bit_depth_o = i2s_bit_depth_e'(c0[3:0]);
              if (cmd_o == I2S_CFG_READ) begin
                if (packet_len_i != idx + 2 + 4) begin
                  format_error_o = 1'b1;
                end else begin
                  seen_o = 1'b1;
                end
              end else if (packet_len_i != idx + 8 + 4) begin
                format_error_o = 1'b1;
              end else begin
                c1 = asep_get_byte(packet_i, idx + 2);
                c2 = asep_get_byte(packet_i, idx + 3);
                c3 = asep_get_byte(packet_i, idx + 4);
                c4 = asep_get_byte(packet_i, idx + 5);
                c5 = asep_get_byte(packet_i, idx + 6);
                data_fmt_o       = i2s_data_fmt_e'(c1[6:4]);
                num_channels_o   = c1[2:0];
                sample_rate_o    = c2[4:0];
                timing_host_rx_o = c3[6];
                target_clk_mck_o = c3[5];
                coeff_k_o        = {c3[1:0], c4};
                divisor_n_o      = {c5, asep_get_byte(packet_i, idx + 7)};
                if ((num_channels_o == 3'd0) || (coeff_k_o == 10'd0) || (divisor_n_o == 16'd0)) begin
                  format_error_o = 1'b1;
                end else begin
                  seen_o = 1'b1;
                end
              end
            end
          end
        end
      end
    end
  end

endmodule

`default_nettype wire
