`timescale 1ns/1ps
`default_nettype none

module video_ase_tx
  import asa_asep_pkg::*;
  import asa_video_asep_pkg::*;
(
  input  logic               build_line_i,
  input  logic               build_pixelclk_i,
  input  asep_ts_mode_e      ts_mode_i,
  input  logic [31:0]        ts_value_i,
  input  video_pkt_type_e    line_pkt_type_i,
  input  logic               line_vsync_i,
  input  logic               line_vend_i,
  input  logic [3:0]         line_video_stream_i,
  input  logic [13:0]        line_video_length_i,
  input  video_pix_fmt_e     line_pix_fmt_i,
  input  video_pix_depth_e   line_pix_depth_i,
  input  video_alpha_depth_e line_alpha_depth_i,
  input  video_payload_t     line_payload_i,
  input  logic [11:0]        line_payload_len_i,
  input  logic [7:0]         frame_rate_i,
  input  logic [15:0]        lines_i,
  input  logic [13:0]        pixels_per_line_i,
  input  logic [7:0]         h_backporch_i,
  input  logic [7:0]         hsync_i,
  input  logic [7:0]         h_frontporch_i,
  input  logic               hsync_polarity_i,
  output logic               packet_valid_o,
  output asep_packet_t       packet_o,
  output logic [11:0]        packet_len_o
);

  asep_packet_t line_pkt, pixelclk_pkt;
  logic [11:0] line_len, pixelclk_len;

  video_line_hdr u_line(
    .encode_i(build_line_i), .decode_i(1'b0), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .pkt_type_i(line_pkt_type_i), .vsync_i(line_vsync_i), .vend_i(line_vend_i),
    .video_stream_i(line_video_stream_i), .video_length_i(line_video_length_i), .pix_fmt_i(line_pix_fmt_i),
    .pix_depth_i(line_pix_depth_i), .alpha_depth_i(line_alpha_depth_i), .payload_i(line_payload_i),
    .payload_len_i(line_payload_len_i), .packet_i('0), .packet_len_i('0), .packet_o(line_pkt), .packet_len_o(line_len),
    .seen_o(), .pkt_type_o(), .vsync_o(), .vend_o(), .video_stream_o(), .video_length_o(), .pix_fmt_o(), .pix_depth_o(),
    .alpha_depth_o(), .payload_o(), .payload_len_o(), .hdr_crc_error_o(), .payload_crc_error_o(), .format_error_o()
  );

  video_pixelclk_codec u_pixelclk(
    .encode_i(build_pixelclk_i), .decode_i(1'b0), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .frame_rate_i(frame_rate_i), .lines_i(lines_i), .pixels_per_line_i(pixels_per_line_i), .h_backporch_i(h_backporch_i),
    .hsync_i(hsync_i), .h_frontporch_i(h_frontporch_i), .hsync_polarity_i(hsync_polarity_i), .packet_i('0), .packet_len_i('0),
    .packet_o(pixelclk_pkt), .packet_len_o(pixelclk_len), .seen_o(), .frame_rate_o(), .lines_o(), .pixels_per_line_o(),
    .h_backporch_o(), .hsync_o(), .h_frontporch_o(), .hsync_polarity_o(), .crc_error_o(), .format_error_o()
  );

  always_comb begin
    packet_valid_o = build_line_i || build_pixelclk_i;
    if (build_pixelclk_i) begin
      packet_o     = pixelclk_pkt;
      packet_len_o = pixelclk_len;
    end else begin
      packet_o     = line_pkt;
      packet_len_o = line_len;
    end
  end

endmodule

`default_nettype wire
