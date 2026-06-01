`default_nettype none

package asa_video_asep_pkg;
  import asa_asep_pkg::*;

  localparam int unsigned VIDEO_MAX_PAYLOAD_BYTES = 1536;
  localparam int unsigned VIDEO_MAX_COMPONENTS    = 4096;

  typedef logic [(VIDEO_MAX_PAYLOAD_BYTES*8)-1:0] video_payload_t;
  typedef logic [(VIDEO_MAX_COMPONENTS*32)-1:0]   video_component_vec_t;

  typedef enum logic [2:0] {
    VIDEO_PKT_PIXELCLK        = 3'b000,
    VIDEO_PKT_LINE_VIDEO      = 3'b001,
    VIDEO_PKT_LINE_FORMAT     = 3'b010,
    VIDEO_PKT_LINE_VENDOR     = 3'b011,
    VIDEO_PKT_LINE_NULL       = 3'b100
  } video_pkt_type_e;

  typedef enum logic [3:0] {
    VIDEO_FMT_RAW     = 4'h0,
    VIDEO_FMT_RGB     = 4'h1,
    VIDEO_FMT_RGBA    = 4'h2,
    VIDEO_FMT_RGBW    = 4'h3,
    VIDEO_FMT_YUV444  = 4'h4,
    VIDEO_FMT_YUV422  = 4'h5,
    VIDEO_FMT_YUV411  = 4'h6
  } video_pix_fmt_e;

  typedef enum logic [3:0] {
    VIDEO_DEPTH_8     = 4'h0,
    VIDEO_DEPTH_10    = 4'h1,
    VIDEO_DEPTH_12    = 4'h2,
    VIDEO_DEPTH_14    = 4'h3,
    VIDEO_DEPTH_16    = 4'h4,
    VIDEO_DEPTH_20    = 4'h5,
    VIDEO_DEPTH_24    = 4'h6,
    VIDEO_DEPTH_28    = 4'h7,
    VIDEO_DEPTH_32    = 4'h8
  } video_pix_depth_e;

  typedef enum logic [1:0] {
    VIDEO_ALPHA_NONE  = 2'b00,
    VIDEO_ALPHA_1BIT  = 2'b01,
    VIDEO_ALPHA_8BIT  = 2'b10,
    VIDEO_ALPHA_SAME  = 2'b11
  } video_alpha_depth_e;

  localparam logic [31:0] CRC32_POLY = 32'hF4ACFB13;
  localparam logic [31:0] CRC32_INIT = 32'hFFFFFFFF;
  localparam logic [31:0] CRC32_XOR  = 32'hFFFFFFFF;

  function automatic logic [7:0] reflect_byte(input logic [7:0] b);
    logic [7:0] r;
    for (int i = 0; i < 8; i++) r[i] = b[7-i];
    return r;
  endfunction

  function automatic logic [31:0] reflect32(input logic [31:0] v);
    logic [31:0] r;
    for (int i = 0; i < 32; i++) r[i] = v[31-i];
    return r;
  endfunction

  function automatic logic [31:0] crc32_byte(input logic [31:0] crc, input logic [7:0] data);
    logic [31:0] c;
    logic [7:0] d;
    d = reflect_byte(data);
    c = crc ^ {d, 24'd0};
    for (int i = 0; i < 8; i++) begin
      if (c[31]) c = {c[30:0], 1'b0} ^ CRC32_POLY;
      else       c = {c[30:0], 1'b0};
    end
    return c;
  endfunction

  function automatic logic [31:0] crc32_finalize(input logic [31:0] crc);
    return reflect32(crc) ^ CRC32_XOR;
  endfunction

  function automatic logic [31:0] asep_video_crc32(
    input asep_packet_t bytes,
    input int unsigned  start_idx,
    input int unsigned  num_bytes
  );
    logic [31:0] crc;
    crc = CRC32_INIT;
    for (int i = 0; i < num_bytes; i++) begin
      crc = crc32_byte(crc, asep_get_byte(bytes, start_idx + i));
    end
    return crc32_finalize(crc);
  endfunction

  function automatic logic [31:0] video_comp_get(
    input video_component_vec_t comps,
    input int unsigned          idx
  );
    return comps[idx*32 +: 32];
  endfunction

  function automatic video_component_vec_t video_comp_set(
    input video_component_vec_t comps,
    input int unsigned          idx,
    input logic [31:0]          value
  );
    video_component_vec_t tmp;
    tmp = comps;
    tmp[idx*32 +: 32] = value;
    return tmp;
  endfunction

  function automatic int unsigned video_depth_bits(input video_pix_depth_e depth);
    case (depth)
      VIDEO_DEPTH_8:  return 8;
      VIDEO_DEPTH_10: return 10;
      VIDEO_DEPTH_12: return 12;
      VIDEO_DEPTH_14: return 14;
      VIDEO_DEPTH_16: return 16;
      VIDEO_DEPTH_20: return 20;
      VIDEO_DEPTH_24: return 24;
      VIDEO_DEPTH_28: return 28;
      default:        return 32;
    endcase
  endfunction

  function automatic int unsigned video_alpha_bits(
    input video_alpha_depth_e alpha,
    input video_pix_depth_e   depth
  );
    case (alpha)
      VIDEO_ALPHA_NONE: return 0;
      VIDEO_ALPHA_1BIT: return 1;
      VIDEO_ALPHA_8BIT: return 8;
      default:          return video_depth_bits(depth);
    endcase
  endfunction

  function automatic logic video_depth_valid(
    input video_pix_fmt_e   fmt,
    input video_pix_depth_e depth
  );
    if (fmt == VIDEO_FMT_RAW) return 1'b1;
    return (depth <= VIDEO_DEPTH_16);
  endfunction

  function automatic logic video_alpha_valid(
    input video_pix_fmt_e      fmt,
    input video_alpha_depth_e  alpha
  );
    if (fmt == VIDEO_FMT_RGBA) return 1'b1;
    return (alpha == VIDEO_ALPHA_NONE);
  endfunction

  function automatic int unsigned video_base_pixels(input video_pix_fmt_e fmt);
    case (fmt)
      VIDEO_FMT_YUV422: return 2;
      VIDEO_FMT_YUV411: return 4;
      default:          return 1;
    endcase
  endfunction

  function automatic int unsigned video_base_components(input video_pix_fmt_e fmt);
    case (fmt)
      VIDEO_FMT_RAW:    return 1;
      VIDEO_FMT_RGB:    return 3;
      VIDEO_FMT_RGBA:   return 4;
      VIDEO_FMT_RGBW:   return 4;
      VIDEO_FMT_YUV444: return 3;
      VIDEO_FMT_YUV422: return 4;
      default:          return 6; // YUV411
    endcase
  endfunction

  function automatic int unsigned video_base_group_bits(
    input video_pix_fmt_e      fmt,
    input video_pix_depth_e    depth,
    input video_alpha_depth_e  alpha
  );
    int unsigned d;
    int unsigned a;
    d = video_depth_bits(depth);
    a = video_alpha_bits(alpha, depth);
    case (fmt)
      VIDEO_FMT_RAW:    return d;
      VIDEO_FMT_RGB:    return 3*d;
      VIDEO_FMT_RGBA:   return (3*d) + a;
      VIDEO_FMT_RGBW:   return 4*d;
      VIDEO_FMT_YUV444: return 3*d;
      VIDEO_FMT_YUV422: return 4*d;
      default:          return 6*d; // YUV411
    endcase
  endfunction

  function automatic int unsigned video_repeat_groups(
    input video_pix_fmt_e      fmt,
    input video_pix_depth_e    depth,
    input video_alpha_depth_e  alpha
  );
    int unsigned bits;
    int unsigned reps;
    bits = video_base_group_bits(fmt, depth, alpha);
    reps = 1;
    while (((bits * reps) % 8) != 0) reps++;
    return reps;
  endfunction

  function automatic int unsigned video_atomic_pixels(
    input video_pix_fmt_e      fmt,
    input video_pix_depth_e    depth,
    input video_alpha_depth_e  alpha
  );
    return video_base_pixels(fmt) * video_repeat_groups(fmt, depth, alpha);
  endfunction

  function automatic int unsigned video_atomic_bytes(
    input video_pix_fmt_e      fmt,
    input video_pix_depth_e    depth,
    input video_alpha_depth_e  alpha
  );
    return (video_base_group_bits(fmt, depth, alpha) * video_repeat_groups(fmt, depth, alpha)) / 8;
  endfunction

  function automatic int unsigned video_component_count_for_pixels(
    input video_pix_fmt_e   fmt,
    input int unsigned      pixel_count
  );
    case (fmt)
      VIDEO_FMT_RAW:    return pixel_count;
      VIDEO_FMT_RGB:    return pixel_count * 3;
      VIDEO_FMT_RGBA:   return pixel_count * 4;
      VIDEO_FMT_RGBW:   return pixel_count * 4;
      VIDEO_FMT_YUV444: return pixel_count * 3;
      VIDEO_FMT_YUV422: return (pixel_count / 2) * 4;
      default:          return (pixel_count / 4) * 6;
    endcase
  endfunction

  function automatic logic video_pixel_count_valid(
    input video_pix_fmt_e fmt,
    input int unsigned    pixel_count
  );
    case (fmt)
      VIDEO_FMT_YUV422: return (pixel_count % 2) == 0;
      VIDEO_FMT_YUV411: return (pixel_count % 4) == 0;
      default:          return 1'b1;
    endcase
  endfunction

  function automatic int unsigned video_expected_payload_bytes(
    input video_pix_fmt_e      fmt,
    input video_pix_depth_e    depth,
    input video_alpha_depth_e  alpha,
    input int unsigned         pixel_count
  );
    return (video_base_group_bits(fmt, depth, alpha) * pixel_count) / video_base_pixels(fmt) / 8;
  endfunction

  function automatic logic [7:0] video_line_byte0(
    input video_pkt_type_e pkt_type,
    input logic            vsync,
    input logic            vend,
    input logic [3:0]      video_stream
  );
    return {pkt_type, vsync, vend, 1'b0, video_stream[3:2]};
  endfunction

  function automatic logic [7:0] video_line_byte1(
    input logic [3:0]  video_stream,
    input logic [13:0] video_length
  );
    return {video_stream[1:0], video_length[13:8]};
  endfunction

  function automatic logic [7:0] video_pixelclk_byte0(input video_pkt_type_e pkt_type);
    return {pkt_type, 5'd0};
  endfunction

  function automatic logic [7:0] video_component_width(
    input video_pix_fmt_e      fmt,
    input video_pix_depth_e    depth,
    input video_alpha_depth_e  alpha,
    input int unsigned         comp_idx_in_base
  );
    if (fmt == VIDEO_FMT_RGBA && (comp_idx_in_base % 4) == 3) return video_alpha_bits(alpha, depth);
    return video_depth_bits(depth);
  endfunction

endpackage

`default_nettype wire
