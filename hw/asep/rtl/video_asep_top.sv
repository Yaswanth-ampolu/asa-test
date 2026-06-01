`timescale 1ns/1ps
`default_nettype none

module video_asep_top
  import asa_asep_pkg::*;
  import asa_video_asep_pkg::*;
(
  input  logic               clk,
  input  logic               rst,
  input  logic               soft_reset_i,
  input  logic               tx_build_line_i,
  input  logic               tx_build_pixelclk_i,
  input  asep_ts_mode_e      tx_ts_mode_i,
  input  logic [31:0]        tx_ts_value_i,
  input  video_pkt_type_e    tx_line_pkt_type_i,
  input  logic               tx_line_vsync_i,
  input  logic               tx_line_vend_i,
  input  logic [3:0]         tx_line_video_stream_i,
  input  logic [13:0]        tx_line_video_length_i,
  input  video_pix_fmt_e     tx_line_pix_fmt_i,
  input  video_pix_depth_e   tx_line_pix_depth_i,
  input  video_alpha_depth_e tx_line_alpha_depth_i,
  input  video_payload_t     tx_line_payload_i,
  input  logic [11:0]        tx_line_payload_len_i,
  input  logic [7:0]         tx_frame_rate_i,
  input  logic [15:0]        tx_lines_i,
  input  logic [13:0]        tx_pixels_per_line_i,
  input  logic [7:0]         tx_h_backporch_i,
  input  logic [7:0]         tx_hsync_i,
  input  logic [7:0]         tx_h_frontporch_i,
  input  logic               tx_hsync_polarity_i,
  input  logic               rx_packet_valid_i,
  input  asep_packet_t       rx_packet_i,
  input  logic [11:0]        rx_packet_len_i,
  output logic               tx_packet_valid_o,
  output asep_packet_t       tx_packet_o,
  output logic [11:0]        tx_packet_len_o,
  output logic               rx_line_seen_o,
  output logic               rx_pixelclk_seen_o,
  output video_pkt_type_e    rx_line_pkt_type_o,
  output logic               rx_line_vsync_o,
  output logic               rx_line_vend_o,
  output logic [3:0]         rx_line_video_stream_o,
  output logic [13:0]        rx_line_video_length_o,
  output video_pix_fmt_e     rx_line_pix_fmt_o,
  output video_pix_depth_e   rx_line_pix_depth_o,
  output video_alpha_depth_e rx_line_alpha_depth_o,
  output video_payload_t     rx_line_payload_o,
  output logic [11:0]        rx_line_payload_len_o,
  output logic [7:0]         rx_frame_rate_o,
  output logic [15:0]        rx_lines_o,
  output logic [13:0]        rx_pixels_per_line_o,
  output logic [7:0]         rx_h_backporch_o,
  output logic [7:0]         rx_hsync_o,
  output logic [7:0]         rx_h_frontporch_o,
  output logic               rx_hsync_polarity_o,
  output logic               rx_line_hdr_crc_error_o,
  output logic               rx_line_payload_crc_error_o,
  output logic               rx_pixelclk_crc_error_o,
  output logic               rx_line_format_error_o,
  output logic               rx_pixelclk_format_error_o
);

  video_ase_tx u_tx(
    .build_line_i(tx_build_line_i), .build_pixelclk_i(tx_build_pixelclk_i), .ts_mode_i(tx_ts_mode_i), .ts_value_i(tx_ts_value_i),
    .line_pkt_type_i(tx_line_pkt_type_i), .line_vsync_i(tx_line_vsync_i), .line_vend_i(tx_line_vend_i),
    .line_video_stream_i(tx_line_video_stream_i), .line_video_length_i(tx_line_video_length_i), .line_pix_fmt_i(tx_line_pix_fmt_i),
    .line_pix_depth_i(tx_line_pix_depth_i), .line_alpha_depth_i(tx_line_alpha_depth_i), .line_payload_i(tx_line_payload_i),
    .line_payload_len_i(tx_line_payload_len_i), .frame_rate_i(tx_frame_rate_i), .lines_i(tx_lines_i), .pixels_per_line_i(tx_pixels_per_line_i),
    .h_backporch_i(tx_h_backporch_i), .hsync_i(tx_hsync_i), .h_frontporch_i(tx_h_frontporch_i), .hsync_polarity_i(tx_hsync_polarity_i),
    .packet_valid_o(tx_packet_valid_o), .packet_o(tx_packet_o), .packet_len_o(tx_packet_len_o)
  );

  video_asd_rx u_rx(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i), .rx_packet_valid_i(rx_packet_valid_i), .rx_packet_i(rx_packet_i),
    .rx_packet_len_i(rx_packet_len_i), .line_seen_o(rx_line_seen_o), .pixelclk_seen_o(rx_pixelclk_seen_o),
    .line_pkt_type_o(rx_line_pkt_type_o), .line_vsync_o(rx_line_vsync_o), .line_vend_o(rx_line_vend_o),
    .line_video_stream_o(rx_line_video_stream_o), .line_video_length_o(rx_line_video_length_o), .line_pix_fmt_o(rx_line_pix_fmt_o),
    .line_pix_depth_o(rx_line_pix_depth_o), .line_alpha_depth_o(rx_line_alpha_depth_o), .line_payload_o(rx_line_payload_o),
    .line_payload_len_o(rx_line_payload_len_o), .frame_rate_o(rx_frame_rate_o), .lines_o(rx_lines_o), .pixels_per_line_o(rx_pixels_per_line_o),
    .h_backporch_o(rx_h_backporch_o), .hsync_o(rx_hsync_o), .h_frontporch_o(rx_h_frontporch_o), .hsync_polarity_o(rx_hsync_polarity_o),
    .line_hdr_crc_error_o(rx_line_hdr_crc_error_o), .line_payload_crc_error_o(rx_line_payload_crc_error_o),
    .pixelclk_crc_error_o(rx_pixelclk_crc_error_o), .line_format_error_o(rx_line_format_error_o),
    .pixelclk_format_error_o(rx_pixelclk_format_error_o)
  );

endmodule

`default_nettype wire
