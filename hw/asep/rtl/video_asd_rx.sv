`timescale 1ns/1ps
`default_nettype none

module video_asd_rx
  import asa_asep_pkg::*;
  import asa_video_asep_pkg::*;
(
  input  logic               clk,
  input  logic               rst,
  input  logic               soft_reset_i,
  input  logic               rx_packet_valid_i,
  input  asep_packet_t       rx_packet_i,
  input  logic [11:0]        rx_packet_len_i,
  output logic               line_seen_o,
  output logic               pixelclk_seen_o,
  output video_pkt_type_e    line_pkt_type_o,
  output logic               line_vsync_o,
  output logic               line_vend_o,
  output logic [3:0]         line_video_stream_o,
  output logic [13:0]        line_video_length_o,
  output video_pix_fmt_e     line_pix_fmt_o,
  output video_pix_depth_e   line_pix_depth_o,
  output video_alpha_depth_e line_alpha_depth_o,
  output video_payload_t     line_payload_o,
  output logic [11:0]        line_payload_len_o,
  output logic [7:0]         frame_rate_o,
  output logic [15:0]        lines_o,
  output logic [13:0]        pixels_per_line_o,
  output logic [7:0]         h_backporch_o,
  output logic [7:0]         hsync_o,
  output logic [7:0]         h_frontporch_o,
  output logic               hsync_polarity_o,
  output logic               line_hdr_crc_error_o,
  output logic               line_payload_crc_error_o,
  output logic               pixelclk_crc_error_o,
  output logic               line_format_error_o,
  output logic               pixelclk_format_error_o
);

  logic line_seen, pixel_seen;
  video_pkt_type_e line_type_int;
  logic line_vsync_int, line_vend_int;
  logic [3:0] line_stream_int;
  logic [13:0] line_len_int;
  video_pix_fmt_e line_fmt_int;
  video_pix_depth_e line_depth_int;
  video_alpha_depth_e line_alpha_int;
  video_payload_t line_payload_int;
  logic [11:0] line_payload_len_int;
  logic line_hdr_crc_int, line_payload_crc_int, line_fmt_err_int;

  logic [7:0] frame_rate_int;
  logic [15:0] lines_int;
  logic [13:0] ppl_int;
  logic [7:0] hbp_int, hsync_int, hfp_int;
  logic hpol_int, pixel_crc_int, pixel_fmt_int;

  video_line_hdr u_line_dec(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0),
    .pkt_type_i(VIDEO_PKT_LINE_VIDEO), .vsync_i('0), .vend_i('0), .video_stream_i('0), .video_length_i('0),
    .pix_fmt_i(VIDEO_FMT_RAW), .pix_depth_i(VIDEO_DEPTH_8), .alpha_depth_i(VIDEO_ALPHA_NONE), .payload_i('0),
    .payload_len_i('0), .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i), .packet_o(), .packet_len_o(), .seen_o(line_seen),
    .pkt_type_o(line_type_int), .vsync_o(line_vsync_int), .vend_o(line_vend_int), .video_stream_o(line_stream_int),
    .video_length_o(line_len_int), .pix_fmt_o(line_fmt_int), .pix_depth_o(line_depth_int), .alpha_depth_o(line_alpha_int),
    .payload_o(line_payload_int), .payload_len_o(line_payload_len_int), .hdr_crc_error_o(line_hdr_crc_int),
    .payload_crc_error_o(line_payload_crc_int), .format_error_o(line_fmt_err_int)
  );

  video_pixelclk_codec u_pixel_dec(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0), .frame_rate_i('0), .lines_i('0),
    .pixels_per_line_i('0), .h_backporch_i('0), .hsync_i('0), .h_frontporch_i('0), .hsync_polarity_i('0),
    .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i), .packet_o(), .packet_len_o(), .seen_o(pixel_seen),
    .frame_rate_o(frame_rate_int), .lines_o(lines_int), .pixels_per_line_o(ppl_int), .h_backporch_o(hbp_int),
    .hsync_o(hsync_int), .h_frontporch_o(hfp_int), .hsync_polarity_o(hpol_int), .crc_error_o(pixel_crc_int),
    .format_error_o(pixel_fmt_int)
  );

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      line_seen_o              <= 1'b0;
      pixelclk_seen_o          <= 1'b0;
      line_pkt_type_o          <= VIDEO_PKT_LINE_VIDEO;
      line_vsync_o             <= 1'b0;
      line_vend_o              <= 1'b0;
      line_video_stream_o      <= 4'd0;
      line_video_length_o      <= 14'd0;
      line_pix_fmt_o           <= VIDEO_FMT_RAW;
      line_pix_depth_o         <= VIDEO_DEPTH_8;
      line_alpha_depth_o       <= VIDEO_ALPHA_NONE;
      line_payload_o           <= '0;
      line_payload_len_o       <= 12'd0;
      frame_rate_o             <= 8'd0;
      lines_o                  <= 16'd0;
      pixels_per_line_o        <= 14'd0;
      h_backporch_o            <= 8'd0;
      hsync_o                  <= 8'd0;
      h_frontporch_o           <= 8'd0;
      hsync_polarity_o         <= 1'b0;
      line_hdr_crc_error_o     <= 1'b0;
      line_payload_crc_error_o <= 1'b0;
      pixelclk_crc_error_o     <= 1'b0;
      line_format_error_o      <= 1'b0;
      pixelclk_format_error_o  <= 1'b0;
    end else begin
      logic [7:0] type_byte;
      logic [7:0] rx_hdr1;
      int unsigned hdr_idx;
      line_seen_o              <= 1'b0;
      pixelclk_seen_o          <= 1'b0;
      line_hdr_crc_error_o     <= 1'b0;
      line_payload_crc_error_o <= 1'b0;
      pixelclk_crc_error_o     <= 1'b0;
      line_format_error_o      <= 1'b0;
      pixelclk_format_error_o  <= 1'b0;
      if (soft_reset_i) begin
        // state-free receiver
      end else if (rx_packet_valid_i) begin
        rx_hdr1 = asep_get_byte(rx_packet_i, 1);
        hdr_idx = (asep_ts_mode_e'(rx_hdr1[1:0]) == ASEP_TS_NONE) ? 2 : 6;
        type_byte = asep_get_byte(rx_packet_i, hdr_idx);
        if (type_byte[7:5] == VIDEO_PKT_PIXELCLK) begin
          pixelclk_crc_error_o    <= pixel_crc_int;
          pixelclk_format_error_o <= pixel_fmt_int;
          if (pixel_seen) begin
            pixelclk_seen_o   <= 1'b1;
            frame_rate_o      <= frame_rate_int;
            lines_o           <= lines_int;
            pixels_per_line_o <= ppl_int;
            h_backporch_o     <= hbp_int;
            hsync_o           <= hsync_int;
            h_frontporch_o    <= hfp_int;
            hsync_polarity_o  <= hpol_int;
          end
        end else begin
          line_hdr_crc_error_o     <= line_hdr_crc_int;
          line_payload_crc_error_o <= line_payload_crc_int;
          line_format_error_o      <= line_fmt_err_int;
          if (line_seen) begin
            line_seen_o         <= 1'b1;
            line_pkt_type_o     <= line_type_int;
            line_vsync_o        <= line_vsync_int;
            line_vend_o         <= line_vend_int;
            line_video_stream_o <= line_stream_int;
            line_video_length_o <= line_len_int;
            line_pix_fmt_o      <= line_fmt_int;
            line_pix_depth_o    <= line_depth_int;
            line_alpha_depth_o  <= line_alpha_int;
            line_payload_o      <= line_payload_int;
            line_payload_len_o  <= line_payload_len_int;
          end
        end
      end
    end
  end

endmodule

`default_nettype wire
