`default_nettype none

package asa_asep_pkg;
  import asa_intf_pkg::*;

  localparam int unsigned ASEP_MAX_CONTAINER_BYTES = 638;
  localparam int unsigned ASEP_MAX_PACKET_BYTES    = 2048;

  typedef logic [(ASEP_MAX_CONTAINER_BYTES*8)-1:0] asep_container_t;
  typedef logic [(ASEP_MAX_PACKET_BYTES*8)-1:0]    asep_packet_t;

  typedef enum logic [6:0] {
    ASEP_STREAM_VIDEO   = 7'h01,
    ASEP_STREAM_I2C     = 7'h02,
    ASEP_STREAM_ETH_L2  = 7'h03,
    ASEP_STREAM_SPI     = 7'h04,
    ASEP_STREAM_GPIO    = 7'h05,
    ASEP_STREAM_EDP     = 7'h06,
    ASEP_STREAM_I2S     = 7'h07,
    ASEP_STREAM_TEST    = 7'h37,
    ASEP_STREAM_FWD     = 7'h7E,
    ASEP_STREAM_RET_OAM = 7'h7F
  } asep_stream_type_e;

  typedef enum logic [1:0] {
    ASEP_TS_NONE         = 2'b00,
    ASEP_TS_INGRESS      = 2'b01,
    ASEP_TS_PRESENTATION = 2'b10,
    ASEP_TS_USER         = 2'b11
  } asep_ts_mode_e;

  typedef enum logic [1:0] {
    ASEP_FRAG_MID        = 2'b00,
    ASEP_FRAG_END_LAST   = 2'b01,
    ASEP_FRAG_END_PAD    = 2'b10,
    ASEP_FRAG_END_HEADER = 2'b11
  } asep_frag_code_e;

  function automatic int unsigned asep_common_hdr_bytes(input asep_ts_mode_e mode);
    return (mode == ASEP_TS_NONE) ? 2 : 6;
  endfunction

  function automatic logic [7:0] asep_get_byte(
    input logic [(ASEP_MAX_PACKET_BYTES*8)-1:0] bytes,
    input int unsigned idx
  );
    return bytes[idx*8 +: 8];
  endfunction

  function automatic asep_packet_t asep_set_byte(
    input asep_packet_t bytes,
    input int unsigned  idx,
    input logic [7:0]   value
  );
    asep_packet_t tmp;
    tmp = bytes;
    tmp[idx*8 +: 8] = value;
    return tmp;
  endfunction

  function automatic logic [7:0] asep_cont_get_byte(
    input asep_container_t bytes,
    input int unsigned     idx
  );
    return bytes[idx*8 +: 8];
  endfunction

  function automatic asep_container_t asep_cont_set_byte(
    input asep_container_t bytes,
    input int unsigned     idx,
    input logic [7:0]      value
  );
    asep_container_t tmp;
    tmp = bytes;
    tmp[idx*8 +: 8] = value;
    return tmp;
  endfunction

  function automatic logic [7:0] asep_hdr_byte0(
    input logic [6:0] stream_type,
    input logic       follow_flag
  );
    return {stream_type, follow_flag};
  endfunction

  function automatic logic [7:0] asep_hdr_byte1(input asep_ts_mode_e mode);
    return {6'd0, mode};
  endfunction

  function automatic logic [7:0] asep_frag_byte0(
    input asep_frag_code_e frag,
    input logic [9:0]      boundary_pos
  );
    logic [7:0] b;
    b = 8'h00;
    b[7:6] = frag;
    b[5:0] = boundary_pos[9:4];
    return b;
  endfunction

  function automatic logic [7:0] asep_frag_byte1(input logic [9:0] boundary_pos);
    return {boundary_pos[3:0], 4'h0};
  endfunction

  function automatic logic [9:0] asep_boundary_pos(
    input logic [7:0] byte0,
    input logic [7:0] byte1
  );
    return {byte0[5:0], byte1[7:4]};
  endfunction

  function automatic int unsigned asep_slot_bytes(input slot_size_e s);
    return slot_byte_count(s);
  endfunction

  function automatic logic [31:0] asep_get_u32_be(
    input asep_packet_t bytes,
    input int unsigned  idx
  );
    return {asep_get_byte(bytes, idx + 0),
            asep_get_byte(bytes, idx + 1),
            asep_get_byte(bytes, idx + 2),
            asep_get_byte(bytes, idx + 3)};
  endfunction

  function automatic logic [31:0] asep_cont_get_u32_be(
    input asep_container_t bytes,
    input int unsigned     idx
  );
    return {asep_cont_get_byte(bytes, idx + 0),
            asep_cont_get_byte(bytes, idx + 1),
            asep_cont_get_byte(bytes, idx + 2),
            asep_cont_get_byte(bytes, idx + 3)};
  endfunction

endpackage

