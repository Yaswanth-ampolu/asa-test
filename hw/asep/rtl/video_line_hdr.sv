`timescale 1ns/1ps
`default_nettype none

module video_line_hdr
  import asa_asep_pkg::*;
  import asa_video_asep_pkg::*;
(
  input  logic               encode_i,
  input  logic               decode_i,
  input  asep_ts_mode_e      ts_mode_i,
  input  logic [31:0]        ts_value_i,
  input  video_pkt_type_e    pkt_type_i,
  input  logic               vsync_i,
  input  logic               vend_i,
  input  logic [3:0]         video_stream_i,
  input  logic [13:0]        video_length_i,
  input  video_pix_fmt_e     pix_fmt_i,
  input  video_pix_depth_e   pix_depth_i,
  input  video_alpha_depth_e alpha_depth_i,
  input  video_payload_t     payload_i,
  input  logic [11:0]        payload_len_i,
  input  asep_packet_t       packet_i,
  input  logic [11:0]        packet_len_i,
  output asep_packet_t       packet_o,
  output logic [11:0]        packet_len_o,
  output logic               seen_o,
  output video_pkt_type_e    pkt_type_o,
  output logic               vsync_o,
  output logic               vend_o,
  output logic [3:0]         video_stream_o,
  output logic [13:0]        video_length_o,
  output video_pix_fmt_e     pix_fmt_o,
  output video_pix_depth_e   pix_depth_o,
  output video_alpha_depth_e alpha_depth_o,
  output video_payload_t     payload_o,
  output logic [11:0]        payload_len_o,
  output logic               hdr_crc_error_o,
  output logic               payload_crc_error_o,
  output logic               format_error_o
);

  always_comb begin
    packet_o           = '0;
    packet_len_o       = '0;
    seen_o             = 1'b0;
    pkt_type_o         = VIDEO_PKT_LINE_VIDEO;
    vsync_o            = 1'b0;
    vend_o             = 1'b0;
    video_stream_o     = 4'd0;
    video_length_o     = 14'd0;
    pix_fmt_o          = VIDEO_FMT_RAW;
    pix_depth_o        = VIDEO_DEPTH_8;
    alpha_depth_o      = VIDEO_ALPHA_NONE;
    payload_o          = '0;
    payload_len_o      = '0;
    hdr_crc_error_o    = 1'b0;
    payload_crc_error_o= 1'b0;
    format_error_o     = 1'b0;

    if (encode_i) begin
      asep_packet_t pkt;
      logic [31:0] crc_hdr, crc_payload;
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
      pkt = asep_set_byte(pkt, idx + 0, video_line_byte0(pkt_type_i, vsync_i, vend_i, video_stream_i));
      pkt = asep_set_byte(pkt, idx + 1, video_line_byte1(video_stream_i, video_length_i));
      pkt = asep_set_byte(pkt, idx + 2, video_length_i[7:0]);
      pkt = asep_set_byte(pkt, idx + 3, {pix_fmt_i, pix_depth_i});
      pkt = asep_set_byte(pkt, idx + 4, {alpha_depth_i, 6'd0});
      crc_hdr = asep_video_crc32(pkt, 0, idx + 5);
      pkt = asep_set_byte(pkt, idx + 5, crc_hdr[31:24]);
      pkt = asep_set_byte(pkt, idx + 6, crc_hdr[23:16]);
      pkt = asep_set_byte(pkt, idx + 7, crc_hdr[15:8]);
      pkt = asep_set_byte(pkt, idx + 8, crc_hdr[7:0]);
      for (int i = 0; i < payload_len_i; i++) begin
        pkt = asep_set_byte(pkt, idx + 9 + i, payload_i[i*8 +: 8]);
      end
      crc_payload = asep_video_crc32(pkt, idx + 9, payload_len_i);
      pkt = asep_set_byte(pkt, idx + 9 + payload_len_i + 0, crc_payload[31:24]);
      pkt = asep_set_byte(pkt, idx + 9 + payload_len_i + 1, crc_payload[23:16]);
      pkt = asep_set_byte(pkt, idx + 9 + payload_len_i + 2, crc_payload[15:8]);
      pkt = asep_set_byte(pkt, idx + 9 + payload_len_i + 3, crc_payload[7:0]);
      packet_o     = pkt;
      packet_len_o = idx + 9 + payload_len_i + 4;
    end

    if (decode_i) begin
      logic [7:0] b0, b1, sb0, sb1, sb3, sb4;
      logic [31:0] crc_hdr_calc, crc_hdr_seen, crc_payload_calc, crc_payload_seen;
      int unsigned idx;
      b0 = asep_get_byte(packet_i, 0);
      b1 = asep_get_byte(packet_i, 1);
      if (b0[7:1] != ASEP_STREAM_VIDEO) begin
        format_error_o = 1'b1;
      end else begin
        idx = (asep_ts_mode_e'(b1[1:0]) == ASEP_TS_NONE) ? 2 : 6;
        if (packet_len_i < idx + 9 + 4) begin
          format_error_o = 1'b1;
        end else begin
          sb0 = asep_get_byte(packet_i, idx + 0);
          sb1 = asep_get_byte(packet_i, idx + 1);
          sb3 = asep_get_byte(packet_i, idx + 3);
          sb4 = asep_get_byte(packet_i, idx + 4);
          pkt_type_o = video_pkt_type_e'(sb0[7:5]);
          if ((pkt_type_o == VIDEO_PKT_PIXELCLK) || (pkt_type_o > VIDEO_PKT_LINE_NULL)) begin
            format_error_o = 1'b1;
          end else begin
            crc_hdr_calc = asep_video_crc32(packet_i, 0, idx + 5);
            crc_hdr_seen = {asep_get_byte(packet_i, idx + 5),
                            asep_get_byte(packet_i, idx + 6),
                            asep_get_byte(packet_i, idx + 7),
                            asep_get_byte(packet_i, idx + 8)};
            if (crc_hdr_calc != crc_hdr_seen) begin
              hdr_crc_error_o = 1'b1;
            end else begin
              vsync_o        = sb0[4];
              vend_o         = sb0[3];
              video_stream_o = {sb0[1:0], sb1[7:6]};
              video_length_o = {sb1[5:0], asep_get_byte(packet_i, idx + 2)};
              pix_fmt_o      = video_pix_fmt_e'(sb3[7:4]);
              pix_depth_o    = video_pix_depth_e'(sb3[3:0]);
              alpha_depth_o  = video_alpha_depth_e'(sb4[7:6]);
              if (sb0[2] || (sb4[5:0] != 6'd0)) begin
                format_error_o = 1'b1;
              end else begin
                payload_len_o = packet_len_i - (idx + 9) - 4;
                crc_payload_calc = asep_video_crc32(packet_i, idx + 9, payload_len_o);
                crc_payload_seen = {asep_get_byte(packet_i, packet_len_i - 4),
                                    asep_get_byte(packet_i, packet_len_i - 3),
                                    asep_get_byte(packet_i, packet_len_i - 2),
                                    asep_get_byte(packet_i, packet_len_i - 1)};
                if (crc_payload_calc != crc_payload_seen) begin
                  payload_crc_error_o = 1'b1;
                end else begin
                  for (int i = 0; i < payload_len_o; i++) begin
                    payload_o[i*8 +: 8] = asep_get_byte(packet_i, idx + 9 + i);
                  end
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
