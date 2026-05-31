`default_nettype none

package asa_i2s_asep_pkg;
  import asa_asep_pkg::*;

  localparam int unsigned I2S_ASEP_MAX_WORDS = 256;
  typedef logic [(I2S_ASEP_MAX_WORDS*32)-1:0] i2s_word_vec_t;

  typedef enum logic {
    I2S_MODE_CONFIG = 1'b0,
    I2S_MODE_DATA   = 1'b1
  } i2s_pkt_mode_e;

  typedef enum logic [1:0] {
    I2S_CFG_WRITE = 2'b00,
    I2S_CFG_READ  = 2'b01,
    I2S_CFG_ACK   = 2'b10,
    I2S_CFG_RRESP = 2'b11
  } i2s_cfg_cmd_e;

  typedef enum logic [3:0] {
    I2S_DEPTH_8  = 4'd0,
    I2S_DEPTH_12 = 4'd1,
    I2S_DEPTH_16 = 4'd2,
    I2S_DEPTH_20 = 4'd3,
    I2S_DEPTH_24 = 4'd4,
    I2S_DEPTH_32 = 4'd5
  } i2s_bit_depth_e;

  typedef enum logic [2:0] {
    I2S_FMT_I2S         = 3'd0,
    I2S_FMT_LEFT_J      = 3'd1,
    I2S_FMT_RIGHT_J     = 3'd2,
    I2S_FMT_TDM         = 3'd3
  } i2s_data_fmt_e;

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

  function automatic logic [31:0] asep_i2s_crc32(
    input asep_packet_t bytes,
    input int unsigned  num_bytes
  );
    logic [31:0] crc;
    crc = CRC32_INIT;
    for (int i = 0; i < num_bytes; i++) begin
      crc = crc32_byte(crc, asep_get_byte(bytes, i));
    end
    return crc32_finalize(crc);
  endfunction

  function automatic logic [6:0] i2s_next_pkt_id(input logic [6:0] cur);
    if ((cur == 7'd0) || (cur >= 7'd120)) return 7'd1;
    return cur + 7'd1;
  endfunction

  function automatic logic [7:0] i2s_pkt_header_byte(
    input logic       is_data_mode,
    input logic [6:0] pkt_id
  );
    return {is_data_mode, pkt_id};
  endfunction

  function automatic int unsigned i2s_ts_start_idx(input asep_ts_mode_e mode);
    return (mode == ASEP_TS_NONE) ? 2 : 6;
  endfunction

  function automatic int unsigned i2s_bytes_per_word(input i2s_bit_depth_e depth);
    case (depth)
      I2S_DEPTH_8:  return 1;
      I2S_DEPTH_12: return 2;
      I2S_DEPTH_16: return 2;
      I2S_DEPTH_20: return 3;
      I2S_DEPTH_24: return 3;
      default:      return 4;
    endcase
  endfunction

  function automatic logic [31:0] i2s_word_get(
    input i2s_word_vec_t words,
    input int unsigned   idx
  );
    return words[idx*32 +: 32];
  endfunction

  function automatic i2s_word_vec_t i2s_word_set(
    input i2s_word_vec_t words,
    input int unsigned   idx,
    input logic [31:0]   value
  );
    i2s_word_vec_t tmp;
    tmp = words;
    tmp[idx*32 +: 32] = value;
    return tmp;
  endfunction

endpackage

`default_nettype wire
