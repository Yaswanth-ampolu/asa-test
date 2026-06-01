`timescale 1ns/1ps
`default_nettype none

module video_pixelclk_codec
  import asa_asep_pkg::*;
  import asa_video_asep_pkg::*;
(
  input  logic            encode_i,
  input  logic            decode_i,
  input  asep_ts_mode_e   ts_mode_i,
  input  logic [31:0]     ts_value_i,
  input  logic [7:0]      frame_rate_i,
  input  logic [15:0]     lines_i,
  input  logic [13:0]     pixels_per_line_i,
  input  logic [7:0]      h_backporch_i,
  input  logic [7:0]      hsync_i,
  input  logic [7:0]      h_frontporch_i,
  input  logic            hsync_polarity_i,
  input  asep_packet_t    packet_i,
  input  logic [11:0]     packet_len_i,
  output asep_packet_t    packet_o,
  output logic [11:0]     packet_len_o,
  output logic            seen_o,
  output logic [7:0]      frame_rate_o,
  output logic [15:0]     lines_o,
  output logic [13:0]     pixels_per_line_o,
  output logic [7:0]      h_backporch_o,
  output logic [7:0]      hsync_o,
  output logic [7:0]      h_frontporch_o,
  output logic            hsync_polarity_o,
  output logic            crc_error_o,
  output logic            format_error_o
);

  always_comb begin
    packet_o          = '0;
    packet_len_o      = '0;
    seen_o            = 1'b0;
    frame_rate_o      = 8'd0;
    lines_o           = 16'd0;
    pixels_per_line_o = 14'd0;
    h_backporch_o     = 8'd0;
    hsync_o           = 8'd0;
    h_frontporch_o    = 8'd0;
    hsync_polarity_o  = 1'b0;
    crc_error_o       = 1'b0;
    format_error_o    = 1'b0;

    if (encode_i) begin
      asep_packet_t pkt;
      logic [31:0] crc;
      int unsigned idx;
      pkt = '0;
      pkt = asep_set_byte(pkt, 0, asep_hdr_byte0(ASEP_STREAM_VIDEO, 1'b0));
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
      pkt = asep_set_byte(pkt, idx + 0, video_pixelclk_byte0(VIDEO_PKT_PIXELCLK));
      pkt = asep_set_byte(pkt, idx + 1, frame_rate_i);
      pkt = asep_set_byte(pkt, idx + 2, lines_i[15:8]);
      pkt = asep_set_byte(pkt, idx + 3, lines_i[7:0]);
      pkt = asep_set_byte(pkt, idx + 4, {2'b00, pixels_per_line_i[13:8]});
      pkt = asep_set_byte(pkt, idx + 5, pixels_per_line_i[7:0]);
      pkt = asep_set_byte(pkt, idx + 6, h_backporch_i);
      pkt = asep_set_byte(pkt, idx + 7, hsync_i);
      pkt = asep_set_byte(pkt, idx + 8, {h_frontporch_i[6:0], hsync_polarity_i});
      crc = asep_video_crc32(pkt, 0, idx + 9);
      pkt = asep_set_byte(pkt, idx + 9,  crc[31:24]);
      pkt = asep_set_byte(pkt, idx + 10, crc[23:16]);
      pkt = asep_set_byte(pkt, idx + 11, crc[15:8]);
      pkt = asep_set_byte(pkt, idx + 12, crc[7:0]);
      packet_o     = pkt;
      packet_len_o = idx + 13;
    end

    if (decode_i) begin
      logic [7:0] b0, b1, sb0, sb4, sb8;
      logic [31:0] crc_calc, crc_seen;
      int unsigned idx;
      b0 = asep_get_byte(packet_i, 0);
      b1 = asep_get_byte(packet_i, 1);
      if (b0[7:1] != ASEP_STREAM_VIDEO) begin
        format_error_o = 1'b1;
      end else begin
        idx = (asep_ts_mode_e'(b1[1:0]) == ASEP_TS_NONE) ? 2 : 6;
        sb0 = asep_get_byte(packet_i, idx + 0);
        sb4 = asep_get_byte(packet_i, idx + 4);
        sb8 = asep_get_byte(packet_i, idx + 8);
        if (packet_len_i != idx + 13) begin
          format_error_o = 1'b1;
        end else if (video_pkt_type_e'(sb0[7:5]) != VIDEO_PKT_PIXELCLK) begin
          format_error_o = 1'b1;
        end else if (sb0[4:0] != 5'd0) begin
          format_error_o = 1'b1;
        end else if (sb4[7:6] != 2'b00) begin
          format_error_o = 1'b1;
        end else begin
          crc_calc = asep_video_crc32(packet_i, 0, idx + 9);
          crc_seen = {asep_get_byte(packet_i, idx + 9),
                      asep_get_byte(packet_i, idx + 10),
                      asep_get_byte(packet_i, idx + 11),
                      asep_get_byte(packet_i, idx + 12)};
          if (crc_calc != crc_seen) begin
            crc_error_o = 1'b1;
          end else begin
            frame_rate_o      = asep_get_byte(packet_i, idx + 1);
            lines_o           = {asep_get_byte(packet_i, idx + 2), asep_get_byte(packet_i, idx + 3)};
            pixels_per_line_o = {sb4[5:0], asep_get_byte(packet_i, idx + 5)};
            h_backporch_o     = asep_get_byte(packet_i, idx + 6);
            hsync_o           = asep_get_byte(packet_i, idx + 7);
            h_frontporch_o    = {1'b0, sb8[7:1]};
            hsync_polarity_o  = sb8[0];
            seen_o            = 1'b1;
          end
        end
      end
    end
  end

endmodule

`default_nettype wire
