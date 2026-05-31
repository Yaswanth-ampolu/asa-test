`timescale 1ns/1ps
`default_nettype none

module i2s_data_codec
  import asa_asep_pkg::*;
  import asa_i2s_asep_pkg::*;
(
  input  logic            encode_i,
  input  logic            decode_i,
  input  logic [6:0]      pkt_id_i,
  input  asep_ts_mode_e   ts_mode_i,
  input  logic [31:0]     ts_value_i,
  input  logic [23:0]     start_ptb_stamp_i,
  input  i2s_bit_depth_e  bit_depth_i,
  input  logic            timestamps_only_i,
  input  logic [9:0]      data_len_i,
  input  logic [8:0]      word_count_i,
  input  i2s_word_vec_t   words_i,
  input  asep_packet_t    packet_i,
  input  logic [11:0]     packet_len_i,
  output asep_packet_t    packet_o,
  output logic [11:0]     packet_len_o,
  output logic            seen_o,
  output logic [6:0]      pkt_id_o,
  output logic [9:0]      data_len_o,
  output logic [23:0]     start_ptb_stamp_o,
  output logic            timestamps_only_o,
  output logic [8:0]      word_count_o,
  output i2s_word_vec_t   words_o,
  output logic            crc_error_o,
  output logic            format_error_o
);

  function automatic asep_packet_t encode_words(
    input asep_packet_t   pkt_in,
    input int unsigned    start_idx,
    input i2s_bit_depth_e depth,
    input logic [8:0]     word_count,
    input i2s_word_vec_t  words
  );
    asep_packet_t pkt;
    logic [31:0] w;
    int unsigned idx;
    pkt = pkt_in;
    idx = start_idx;
    for (int i = 0; i < word_count; i++) begin
      w = i2s_word_get(words, i);
      case (depth)
        I2S_DEPTH_8: begin
          pkt = asep_set_byte(pkt, idx + 0, w[7:0]);
          idx += 1;
        end
        I2S_DEPTH_12: begin
          pkt = asep_set_byte(pkt, idx + 0, {4'h0, w[11:8]});
          pkt = asep_set_byte(pkt, idx + 1, w[7:0]);
          idx += 2;
        end
        I2S_DEPTH_16: begin
          pkt = asep_set_byte(pkt, idx + 0, w[15:8]);
          pkt = asep_set_byte(pkt, idx + 1, w[7:0]);
          idx += 2;
        end
        I2S_DEPTH_20: begin
          pkt = asep_set_byte(pkt, idx + 0, {4'h0, w[19:16]});
          pkt = asep_set_byte(pkt, idx + 1, w[15:8]);
          pkt = asep_set_byte(pkt, idx + 2, w[7:0]);
          idx += 3;
        end
        I2S_DEPTH_24: begin
          pkt = asep_set_byte(pkt, idx + 0, w[23:16]);
          pkt = asep_set_byte(pkt, idx + 1, w[15:8]);
          pkt = asep_set_byte(pkt, idx + 2, w[7:0]);
          idx += 3;
        end
        default: begin
          pkt = asep_set_byte(pkt, idx + 0, w[31:24]);
          pkt = asep_set_byte(pkt, idx + 1, w[23:16]);
          pkt = asep_set_byte(pkt, idx + 2, w[15:8]);
          pkt = asep_set_byte(pkt, idx + 3, w[7:0]);
          idx += 4;
        end
      endcase
    end
    return pkt;
  endfunction

  function automatic i2s_word_vec_t decode_words(
    input asep_packet_t   pkt,
    input int unsigned    start_idx,
    input i2s_bit_depth_e depth,
    input logic [8:0]     word_count
  );
    i2s_word_vec_t outv;
    logic [31:0] w;
    int unsigned idx;
    outv = '0;
    idx = start_idx;
    for (int i = 0; i < word_count; i++) begin
      w = 32'd0;
      case (depth)
        I2S_DEPTH_8: begin
          w[7:0] = asep_get_byte(pkt, idx + 0);
          idx += 1;
        end
        I2S_DEPTH_12: begin
          logic [7:0] b0, b1;
          b0 = asep_get_byte(pkt, idx + 0);
          b1 = asep_get_byte(pkt, idx + 1);
          w[11:8] = b0[3:0];
          w[7:0]  = b1;
          idx += 2;
        end
        I2S_DEPTH_16: begin
          w[15:8] = asep_get_byte(pkt, idx + 0);
          w[7:0]  = asep_get_byte(pkt, idx + 1);
          idx += 2;
        end
        I2S_DEPTH_20: begin
          logic [7:0] b0, b1, b2;
          b0 = asep_get_byte(pkt, idx + 0);
          b1 = asep_get_byte(pkt, idx + 1);
          b2 = asep_get_byte(pkt, idx + 2);
          w[19:16] = b0[3:0];
          w[15:8]  = b1;
          w[7:0]   = b2;
          idx += 3;
        end
        I2S_DEPTH_24: begin
          w[23:16] = asep_get_byte(pkt, idx + 0);
          w[15:8]  = asep_get_byte(pkt, idx + 1);
          w[7:0]   = asep_get_byte(pkt, idx + 2);
          idx += 3;
        end
        default: begin
          w[31:24] = asep_get_byte(pkt, idx + 0);
          w[23:16] = asep_get_byte(pkt, idx + 1);
          w[15:8]  = asep_get_byte(pkt, idx + 2);
          w[7:0]   = asep_get_byte(pkt, idx + 3);
          idx += 4;
        end
      endcase
      outv = i2s_word_set(outv, i, w);
    end
    return outv;
  endfunction

  always_comb begin
    packet_o           = '0;
    packet_len_o       = '0;
    seen_o             = 1'b0;
    pkt_id_o           = 7'd0;
    data_len_o         = 10'd0;
    start_ptb_stamp_o  = 24'd0;
    timestamps_only_o  = 1'b0;
    word_count_o       = 9'd0;
    words_o            = '0;
    crc_error_o        = 1'b0;
    format_error_o     = 1'b0;

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
      pkt = asep_set_byte(pkt, idx + 0, i2s_pkt_header_byte(1'b1, pkt_id_i));
      pkt = asep_set_byte(pkt, idx + 1, {6'b0, data_len_i[9:8]});
      pkt = asep_set_byte(pkt, idx + 2, data_len_i[7:0]);
      pkt = asep_set_byte(pkt, idx + 3, start_ptb_stamp_i[23:16]);
      pkt = asep_set_byte(pkt, idx + 4, start_ptb_stamp_i[15:8]);
      pkt = asep_set_byte(pkt, idx + 5, start_ptb_stamp_i[7:0]);
      idx = idx + 6;
      if (!timestamps_only_i) begin
        pkt = encode_words(pkt, idx, bit_depth_i, word_count_i, words_i);
      end
      idx = idx + data_len_i;
      crc = asep_i2s_crc32(pkt, idx);
      pkt = asep_set_byte(pkt, idx + 0, crc[31:24]);
      pkt = asep_set_byte(pkt, idx + 1, crc[23:16]);
      pkt = asep_set_byte(pkt, idx + 2, crc[15:8]);
      pkt = asep_set_byte(pkt, idx + 3, crc[7:0]);
      packet_o     = pkt;
      packet_len_o = idx + 4;
    end

    if (decode_i) begin
      logic [7:0] b0, b1, hdr;
      logic [31:0] crc_calc, crc_seen;
      int unsigned idx;
      int unsigned bytes_per_word;
      b0 = asep_get_byte(packet_i, 0);
      b1 = asep_get_byte(packet_i, 1);
      if (b0[7:1] != ASEP_STREAM_I2S) begin
        format_error_o = 1'b1;
      end else begin
        idx = i2s_ts_start_idx(asep_ts_mode_e'(b1[1:0]));
        if (packet_len_i < idx + 6 + 4) begin
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
            if (hdr[7] != 1'b1) begin
              format_error_o = 1'b1;
            end else begin
              pkt_id_o          = hdr[6:0];
              b0                = asep_get_byte(packet_i, idx + 1);
              b1                = asep_get_byte(packet_i, idx + 2);
              data_len_o        = {b0[1:0], b1};
              start_ptb_stamp_o = {asep_get_byte(packet_i, idx + 3),
                                   asep_get_byte(packet_i, idx + 4),
                                   asep_get_byte(packet_i, idx + 5)};
              if (packet_len_i != idx + 6 + data_len_o + 4) begin
                format_error_o = 1'b1;
              end else begin
                timestamps_only_o = (data_len_o == 10'd0);
                if (data_len_o != 10'd0) begin
                  bytes_per_word = i2s_bytes_per_word(bit_depth_i);
                  if ((data_len_o % bytes_per_word) != 0) begin
                    format_error_o = 1'b1;
                  end else begin
                    word_count_o = data_len_o / bytes_per_word;
                    if (word_count_o > I2S_ASEP_MAX_WORDS) begin
                      format_error_o = 1'b1;
                    end else begin
                      words_o = decode_words(packet_i, idx + 6, bit_depth_i, word_count_o);
                    end
                  end
                end
                seen_o = !format_error_o;
              end
            end
          end
        end
      end
    end
  end

endmodule

`default_nettype wire
