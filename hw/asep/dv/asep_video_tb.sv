`timescale 1ns/1ps
`default_nettype none

module asep_video_tb;
  import asa_asep_pkg::*;
  import asa_video_asep_pkg::*;

  logic clk, rst, soft_reset;
  initial begin clk = 0; forever #5 clk = ~clk; end

  int pass_count, fail_count;
  task automatic check(input string name, input logic cond);
    if (cond) pass_count++;
    else begin
      $display("FAIL: %s", name);
      fail_count++;
    end
  endtask

  task automatic tick(input int n = 1);
    repeat (n) @(posedge clk);
    #1;
  endtask

  logic pay_enc, pay_dec, pay_seen, pay_fmt_err, pay_len_err;
  video_payload_t payload_enc, payload_dec;
  logic [11:0] payload_len_enc, payload_len_dec;
  logic [13:0] pixel_count;
  video_component_vec_t comps_i, comps_o;
  logic [12:0] comp_count_o;
  video_pix_fmt_e pay_fmt;
  video_pix_depth_e pay_depth;
  video_alpha_depth_e pay_alpha;

  video_payload_codec u_payload(
    .encode_i(pay_enc), .decode_i(pay_dec), .pix_fmt_i(pay_fmt), .pix_depth_i(pay_depth), .alpha_depth_i(pay_alpha),
    .pixel_count_i(pixel_count), .components_i(comps_i), .payload_i(payload_dec), .payload_len_i(payload_len_dec),
    .payload_o(payload_enc), .payload_len_o(payload_len_enc), .components_o(comps_o), .component_count_o(comp_count_o),
    .seen_o(pay_seen), .format_error_o(pay_fmt_err), .length_error_o(pay_len_err)
  );

  logic line_enc, line_dec, line_seen, line_hdr_crc_err, line_pay_crc_err, line_fmt_err;
  logic line_vsync_i, line_vend_i, line_vsync_o, line_vend_o;
  logic [3:0] line_stream_i, line_stream_o;
  logic [13:0] line_vid_len_i, line_vid_len_o;
  video_pkt_type_e line_type_i, line_type_o;
  video_pix_fmt_e line_fmt_i, line_fmt_o;
  video_pix_depth_e line_depth_i, line_depth_o;
  video_alpha_depth_e line_alpha_i, line_alpha_o;
  asep_ts_mode_e line_ts_mode;
  logic [31:0] line_ts_value;
  asep_packet_t line_pkt_enc, line_pkt_dec;
  logic [11:0] line_pkt_len_enc, line_pkt_len_dec;
  video_payload_t line_payload_i, line_payload_o;
  logic [11:0] line_payload_len_i, line_payload_len_o;

  video_line_hdr u_line(
    .encode_i(line_enc), .decode_i(line_dec), .ts_mode_i(line_ts_mode), .ts_value_i(line_ts_value), .pkt_type_i(line_type_i),
    .vsync_i(line_vsync_i), .vend_i(line_vend_i), .video_stream_i(line_stream_i), .video_length_i(line_vid_len_i),
    .pix_fmt_i(line_fmt_i), .pix_depth_i(line_depth_i), .alpha_depth_i(line_alpha_i), .payload_i(line_payload_i),
    .payload_len_i(line_payload_len_i), .packet_i(line_pkt_dec), .packet_len_i(line_pkt_len_dec), .packet_o(line_pkt_enc),
    .packet_len_o(line_pkt_len_enc), .seen_o(line_seen), .pkt_type_o(line_type_o), .vsync_o(line_vsync_o), .vend_o(line_vend_o),
    .video_stream_o(line_stream_o), .video_length_o(line_vid_len_o), .pix_fmt_o(line_fmt_o), .pix_depth_o(line_depth_o),
    .alpha_depth_o(line_alpha_o), .payload_o(line_payload_o), .payload_len_o(line_payload_len_o), .hdr_crc_error_o(line_hdr_crc_err),
    .payload_crc_error_o(line_pay_crc_err), .format_error_o(line_fmt_err)
  );

  logic pix_enc, pix_dec, pix_seen, pix_crc_err, pix_fmt_err;
  logic [7:0] fr_i, fr_o, hbp_i, hbp_o, hs_i, hs_o, hfp_i, hfp_o;
  logic [15:0] lines_i, lines_o;
  logic [13:0] ppl_i, ppl_o;
  logic hpol_i, hpol_o;
  asep_packet_t pix_pkt_enc, pix_pkt_dec;
  logic [11:0] pix_pkt_len_enc, pix_pkt_len_dec;

  video_pixelclk_codec u_pix(
    .encode_i(pix_enc), .decode_i(pix_dec), .ts_mode_i(line_ts_mode), .ts_value_i(line_ts_value), .frame_rate_i(fr_i), .lines_i(lines_i),
    .pixels_per_line_i(ppl_i), .h_backporch_i(hbp_i), .hsync_i(hs_i), .h_frontporch_i(hfp_i), .hsync_polarity_i(hpol_i),
    .packet_i(pix_pkt_dec), .packet_len_i(pix_pkt_len_dec), .packet_o(pix_pkt_enc), .packet_len_o(pix_pkt_len_enc),
    .seen_o(pix_seen), .frame_rate_o(fr_o), .lines_o(lines_o), .pixels_per_line_o(ppl_o), .h_backporch_o(hbp_o),
    .hsync_o(hs_o), .h_frontporch_o(hfp_o), .hsync_polarity_o(hpol_o), .crc_error_o(pix_crc_err), .format_error_o(pix_fmt_err)
  );

  logic top_tx_line, top_tx_pix, top_rx_valid;
  asep_packet_t top_tx_pkt, top_rx_pkt;
  logic [11:0] top_tx_len, top_rx_len;
  logic top_rx_line_seen, top_rx_pix_seen, top_rx_line_hdr_crc, top_rx_line_pay_crc, top_rx_pix_crc, top_rx_line_fmt_err, top_rx_pix_fmt_err;
  video_pkt_type_e top_rx_line_type;
  logic top_rx_line_vsync, top_rx_line_vend;
  logic [3:0] top_rx_line_stream;
  logic [13:0] top_rx_line_len, top_rx_ppl;
  video_pix_fmt_e top_rx_line_fmt;
  video_pix_depth_e top_rx_line_depth;
  video_alpha_depth_e top_rx_line_alpha;
  video_payload_t top_rx_line_payload;
  logic [11:0] top_rx_line_payload_len;
  logic [7:0] top_rx_fr, top_rx_hbp, top_rx_hs, top_rx_hfp;
  logic [15:0] top_rx_lines;
  logic top_rx_hpol;
  logic [31:0] dbg_crc_calc, dbg_crc_seen;
  asep_packet_t saved_line_pkt;
  logic [11:0] saved_line_pkt_len;

  video_asep_top u_top(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset), .tx_build_line_i(top_tx_line), .tx_build_pixelclk_i(top_tx_pix),
    .tx_ts_mode_i(line_ts_mode), .tx_ts_value_i(line_ts_value), .tx_line_pkt_type_i(line_type_i), .tx_line_vsync_i(line_vsync_i),
    .tx_line_vend_i(line_vend_i), .tx_line_video_stream_i(line_stream_i), .tx_line_video_length_i(line_vid_len_i),
    .tx_line_pix_fmt_i(line_fmt_i), .tx_line_pix_depth_i(line_depth_i), .tx_line_alpha_depth_i(line_alpha_i),
    .tx_line_payload_i(line_payload_i), .tx_line_payload_len_i(line_payload_len_i), .tx_frame_rate_i(fr_i), .tx_lines_i(lines_i),
    .tx_pixels_per_line_i(ppl_i), .tx_h_backporch_i(hbp_i), .tx_hsync_i(hs_i), .tx_h_frontporch_i(hfp_i), .tx_hsync_polarity_i(hpol_i),
    .rx_packet_valid_i(top_rx_valid), .rx_packet_i(top_rx_pkt), .rx_packet_len_i(top_rx_len), .tx_packet_valid_o(), .tx_packet_o(top_tx_pkt),
    .tx_packet_len_o(top_tx_len), .rx_line_seen_o(top_rx_line_seen), .rx_pixelclk_seen_o(top_rx_pix_seen), .rx_line_pkt_type_o(top_rx_line_type),
    .rx_line_vsync_o(top_rx_line_vsync), .rx_line_vend_o(top_rx_line_vend), .rx_line_video_stream_o(top_rx_line_stream),
    .rx_line_video_length_o(top_rx_line_len), .rx_line_pix_fmt_o(top_rx_line_fmt), .rx_line_pix_depth_o(top_rx_line_depth),
    .rx_line_alpha_depth_o(top_rx_line_alpha), .rx_line_payload_o(top_rx_line_payload), .rx_line_payload_len_o(top_rx_line_payload_len),
    .rx_frame_rate_o(top_rx_fr), .rx_lines_o(top_rx_lines), .rx_pixels_per_line_o(top_rx_ppl), .rx_h_backporch_o(top_rx_hbp),
    .rx_hsync_o(top_rx_hs), .rx_h_frontporch_o(top_rx_hfp), .rx_hsync_polarity_o(top_rx_hpol),
    .rx_line_hdr_crc_error_o(top_rx_line_hdr_crc), .rx_line_payload_crc_error_o(top_rx_line_pay_crc), .rx_pixelclk_crc_error_o(top_rx_pix_crc),
    .rx_line_format_error_o(top_rx_line_fmt_err), .rx_pixelclk_format_error_o(top_rx_pix_fmt_err)
  );

  initial begin
    rst = 1;
    soft_reset = 0;
    pass_count = 0;
    fail_count = 0;
    pay_enc = 0; pay_dec = 0; payload_dec = '0; payload_len_dec = '0;
    pay_fmt = VIDEO_FMT_RGB; pay_depth = VIDEO_DEPTH_8; pay_alpha = VIDEO_ALPHA_NONE; pixel_count = 0; comps_i = '0;
    line_enc = 0; line_dec = 0; line_ts_mode = ASEP_TS_NONE; line_ts_value = 32'h0;
    line_type_i = VIDEO_PKT_LINE_VIDEO; line_vsync_i = 0; line_vend_i = 0; line_stream_i = 4'd0; line_vid_len_i = 14'd0;
    line_fmt_i = VIDEO_FMT_RGB; line_depth_i = VIDEO_DEPTH_8; line_alpha_i = VIDEO_ALPHA_NONE; line_payload_i = '0; line_payload_len_i = '0;
    pix_enc = 0; pix_dec = 0; fr_i = 8'h84; lines_i = 16'd1125; ppl_i = 14'd2200; hbp_i = 8'd148; hs_i = 8'd44; hfp_i = 8'd88; hpol_i = 1'b1;
    top_tx_line = 0; top_tx_pix = 0; top_rx_valid = 0; top_rx_pkt = '0; top_rx_len = '0;

    tick(2); rst = 0; tick(1);

    // T1 RGB8 payload roundtrip
    pay_fmt = VIDEO_FMT_RGB; pay_depth = VIDEO_DEPTH_8; pay_alpha = VIDEO_ALPHA_NONE; pixel_count = 14'd2; comps_i = '0;
    comps_i = video_comp_set(comps_i, 0, 32'h11);
    comps_i = video_comp_set(comps_i, 1, 32'h22);
    comps_i = video_comp_set(comps_i, 2, 32'h33);
    comps_i = video_comp_set(comps_i, 3, 32'h44);
    comps_i = video_comp_set(comps_i, 4, 32'h55);
    comps_i = video_comp_set(comps_i, 5, 32'h66);
    pay_enc = 1; #1;
    check("T1 payload len", payload_len_enc == 12'd6);
    payload_dec = payload_enc; payload_len_dec = payload_len_enc; pay_enc = 0; pay_dec = 1; #1;
    check("T1 seen", pay_seen);
    check("T1 comp count", comp_count_o == 13'd6);
    check("T1 roundtrip", video_comp_get(comps_o, 0) == 32'h11 && video_comp_get(comps_o, 5) == 32'h66);
    pay_dec = 0;

    // T2 RGB10 payload roundtrip
    pay_fmt = VIDEO_FMT_RGB; pay_depth = VIDEO_DEPTH_10; pay_alpha = VIDEO_ALPHA_NONE; pixel_count = 14'd4; comps_i = '0;
    for (int i = 0; i < 12; i++) comps_i = video_comp_set(comps_i, i, i + 1);
    pay_enc = 1; #1;
    check("T2 payload len", payload_len_enc == 12'd15);
    payload_dec = payload_enc; payload_len_dec = payload_len_enc; pay_enc = 0; pay_dec = 1; #1;
    check("T2 seen", pay_seen);
    check("T2 roundtrip", video_comp_get(comps_o, 0) == 32'd1 && video_comp_get(comps_o, 11) == 32'd12);
    pay_dec = 0;

    // T3 YUV422_8 payload roundtrip
    pay_fmt = VIDEO_FMT_YUV422; pay_depth = VIDEO_DEPTH_8; pay_alpha = VIDEO_ALPHA_NONE; pixel_count = 14'd2; comps_i = '0;
    comps_i = video_comp_set(comps_i, 0, 32'hAA);
    comps_i = video_comp_set(comps_i, 1, 32'h11);
    comps_i = video_comp_set(comps_i, 2, 32'hBB);
    comps_i = video_comp_set(comps_i, 3, 32'h22);
    pay_enc = 1; #1;
    check("T3 payload len", payload_len_enc == 12'd4);
    payload_dec = payload_enc; payload_len_dec = payload_len_enc; pay_enc = 0; pay_dec = 1; #1;
    check("T3 roundtrip", video_comp_get(comps_o, 0) == 32'hAA && video_comp_get(comps_o, 3) == 32'h22);
    pay_dec = 0;

    // T4 RAW32 payload roundtrip
    pay_fmt = VIDEO_FMT_RAW; pay_depth = VIDEO_DEPTH_32; pay_alpha = VIDEO_ALPHA_NONE; pixel_count = 14'd1; comps_i = '0;
    comps_i = video_comp_set(comps_i, 0, 32'hDEADBEEF);
    pay_enc = 1; #1;
    check("T4 raw bytes", payload_enc[7:0] == 8'hEF && payload_enc[15:8] == 8'hBE && payload_enc[23:16] == 8'hAD && payload_enc[31:24] == 8'hDE);
    payload_dec = payload_enc; payload_len_dec = payload_len_enc; pay_enc = 0; pay_dec = 1; #1;
    check("T4 raw roundtrip", video_comp_get(comps_o, 0) == 32'hDEADBEEF);
    pay_dec = 0;

    // T5 invalid non-raw 20-bit rejected
    pay_fmt = VIDEO_FMT_RGB; pay_depth = VIDEO_DEPTH_20; pixel_count = 14'd1; pay_enc = 1; #1;
    check("T5 invalid depth", pay_fmt_err);
    pay_enc = 0;

    // T6 line encode/decode
    line_ts_mode = ASEP_TS_PRESENTATION;
    line_ts_value = 32'h12345678;
    line_type_i = VIDEO_PKT_LINE_VIDEO;
    line_vsync_i = 1'b1; line_vend_i = 1'b0; line_stream_i = 4'hA; line_vid_len_i = 14'd1;
    line_fmt_i = VIDEO_FMT_RGB; line_depth_i = VIDEO_DEPTH_8; line_alpha_i = VIDEO_ALPHA_NONE;
    line_payload_i = payload_enc; line_payload_len_i = 12'd6;
    line_enc = 1; #1;
    check("T6 line len", line_pkt_len_enc == 12'd25);
    line_pkt_dec = line_pkt_enc; line_pkt_len_dec = line_pkt_len_enc; line_enc = 0; line_dec = 1; #1;
    check("T6 line seen", line_seen);
    check("T6 line fields", line_type_o == VIDEO_PKT_LINE_VIDEO && line_vsync_o && !line_vend_o && line_stream_o == 4'hA);
    check("T6 line payload len", line_payload_len_o == 12'd6);
    saved_line_pkt = line_pkt_dec;
    saved_line_pkt_len = line_pkt_len_dec;
    line_dec = 0;

    // T7 line header crc error
    line_pkt_dec = saved_line_pkt; line_pkt_len_dec = saved_line_pkt_len;
    line_pkt_dec = asep_set_byte(line_pkt_dec, ((line_ts_mode == ASEP_TS_NONE) ? 2 : 6) + 3,
                                 asep_get_byte(line_pkt_dec, ((line_ts_mode == ASEP_TS_NONE) ? 2 : 6) + 3) ^ 8'h01);
    dbg_crc_calc = asep_video_crc32(line_pkt_dec, 0, ((line_ts_mode == ASEP_TS_NONE) ? 2 : 6) + 5);
    dbg_crc_seen = {asep_get_byte(line_pkt_dec, ((line_ts_mode == ASEP_TS_NONE) ? 2 : 6) + 5),
                    asep_get_byte(line_pkt_dec, ((line_ts_mode == ASEP_TS_NONE) ? 2 : 6) + 6),
                    asep_get_byte(line_pkt_dec, ((line_ts_mode == ASEP_TS_NONE) ? 2 : 6) + 7),
                    asep_get_byte(line_pkt_dec, ((line_ts_mode == ASEP_TS_NONE) ? 2 : 6) + 8)};
    check("T7 hdr mismatch basis", dbg_crc_calc != dbg_crc_seen);
    line_dec = 1; #1;
    check("T7 hdr crc", line_hdr_crc_err);
    line_dec = 0;

    // T8 line payload crc error
    line_pkt_dec = saved_line_pkt; line_pkt_len_dec = saved_line_pkt_len;
    line_pkt_dec = asep_set_byte(line_pkt_dec, ((line_ts_mode == ASEP_TS_NONE) ? 2 : 6) + 9,
                                 asep_get_byte(line_pkt_dec, ((line_ts_mode == ASEP_TS_NONE) ? 2 : 6) + 9) ^ 8'h01);
    dbg_crc_calc = asep_video_crc32(line_pkt_dec, ((line_ts_mode == ASEP_TS_NONE) ? 2 : 6) + 9, line_payload_len_i);
    dbg_crc_seen = {asep_get_byte(line_pkt_dec, line_pkt_len_dec - 4),
                    asep_get_byte(line_pkt_dec, line_pkt_len_dec - 3),
                    asep_get_byte(line_pkt_dec, line_pkt_len_dec - 2),
                    asep_get_byte(line_pkt_dec, line_pkt_len_dec - 1)};
    check("T8 payload mismatch basis", dbg_crc_calc != dbg_crc_seen);
    line_dec = 1; #1;
    check("T8 payload crc", line_pay_crc_err);
    line_dec = 0;

    // T9 pixelclk encode/decode
    pix_enc = 1; #1;
    check("T9 pixel len", pix_pkt_len_enc == 12'd19);
    pix_pkt_dec = pix_pkt_enc; pix_pkt_len_dec = pix_pkt_len_enc; pix_enc = 0; pix_dec = 1; #1;
    check("T9 pixel seen", pix_seen);
    check("T9 pixel fields", fr_o == 8'h84 && lines_o == 16'd1125 && ppl_o == 14'd2200 && hbp_o == 8'd148 && hs_o == 8'd44 && hfp_o == 8'd88 && hpol_o);
    pix_dec = 0;

    // T10 top line path
    top_tx_line = 1; #1; top_rx_pkt = top_tx_pkt; top_rx_len = top_tx_len; tick(1); top_tx_line = 0; top_rx_valid = 1; tick(1); top_rx_valid = 0;
    check("T10 top line seen", top_rx_line_seen);
    check("T10 top line fmt", top_rx_line_fmt == VIDEO_FMT_RGB && top_rx_line_depth == VIDEO_DEPTH_8);

    // T11 top pixelclk path
    top_tx_pix = 1; #1; top_rx_pkt = top_tx_pkt; top_rx_len = top_tx_len; tick(1); top_tx_pix = 0; top_rx_valid = 1; tick(1); top_rx_valid = 0;
    check("T11 top pixel seen", top_rx_pix_seen);
    check("T11 top pixel fields", top_rx_fr == 8'h84 && top_rx_lines == 16'd1125 && top_rx_ppl == 14'd2200);

    // T12 YUV411_10 length / roundtrip sanity
    pay_fmt = VIDEO_FMT_YUV411; pay_depth = VIDEO_DEPTH_10; pay_alpha = VIDEO_ALPHA_NONE; pixel_count = 14'd8; comps_i = '0;
    for (int i = 0; i < 12; i++) comps_i = video_comp_set(comps_i, i, 32'(i + 10));
    pay_enc = 1; #1;
    check("T12 payload len", payload_len_enc == 12'd15);
    payload_dec = payload_enc; payload_len_dec = payload_len_enc; pay_enc = 0; pay_dec = 1; #1;
    check("T12 seen", pay_seen);
    check("T12 roundtrip", video_comp_get(comps_o, 0) == 32'd10 && video_comp_get(comps_o, 11) == 32'd21);
    pay_dec = 0;

    if (fail_count == 0) $display("asep_video_tb: %0d passed, 0 failed", pass_count);
    else $display("asep_video_tb: %0d passed, %0d failed", pass_count, fail_count);
    $finish;
  end

endmodule

`default_nettype wire
