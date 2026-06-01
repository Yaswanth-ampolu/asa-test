`default_nettype none

package asa_edp_asep_pkg;
  import asa_asep_pkg::*;

  localparam int unsigned EDP_MAX_AUX_BYTES       = 31;
  localparam int unsigned EDP_MAX_EDM_BYTES       = 1536;
  localparam int unsigned EDP_MAX_PLM10_SYMBOLS   = 512;
  localparam int unsigned EDP_MAX_PLM132_SYMBOLS  = 96;

  typedef logic [(EDP_MAX_EDM_BYTES*8)-1:0]       edp_payload_t;
  typedef logic [(EDP_MAX_PLM10_SYMBOLS*10)-1:0]  edp_plm10_vec_t;
  typedef logic [(EDP_MAX_PLM132_SYMBOLS*132)-1:0] edp_plm132_vec_t;

  typedef enum logic [2:0] {
    EDP_PKT_EDM_VB         = 3'b000,
    EDP_PKT_EDM_DATA       = 3'b001,
    EDP_PKT_AUX            = 3'b010,
    EDP_PKT_STREAM_CLOCK   = 3'b011,
    EDP_PKT_PLM_8B10B      = 3'b100,
    EDP_PKT_PLM_128B132B   = 3'b101
  } edp_pkt_type_e;

  typedef enum logic [1:0] {
    EDP_LANES_1 = 2'b00,
    EDP_LANES_2 = 2'b01,
    EDP_LANES_4 = 2'b10
  } edp_lane_count_e;

  typedef enum logic [1:0] {
    EDP_HPD_LOW       = 2'b00,
    EDP_HPD_HIGH      = 2'b01,
    EDP_HPD_IRQ       = 2'b10,
    EDP_HPD_HOTPLUG   = 2'b11
  } edp_hpd_state_e;

  typedef enum logic [3:0] {
    EDP_KOMMA_NONE      = 4'h0,
    EDP_KOMMA_BS        = 4'h1,
    EDP_KOMMA_BE        = 4'h2,
    EDP_KOMMA_FS        = 4'h3,
    EDP_KOMMA_FE        = 4'h4,
    EDP_KOMMA_SS        = 4'h5,
    EDP_KOMMA_SE        = 4'h6,
    EDP_KOMMA_SR        = 4'h7,
    EDP_KOMMA_CP        = 4'h8,
    EDP_KOMMA_CPBS      = 4'h9,
    EDP_KOMMA_CPSR      = 4'hA,
    EDP_KOMMA_BF        = 4'hB,
    EDP_KOMMA_EOC       = 4'hC,
    EDP_KOMMA_SDPSPLIT  = 4'hD
  } edp_komma_e;

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

  function automatic logic [31:0] asep_edp_crc32(
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

  function automatic int unsigned edp_lane_mult(input edp_lane_count_e lanes);
    case (lanes)
      EDP_LANES_1: return 1;
      EDP_LANES_2: return 2;
      default:     return 4;
    endcase
  endfunction

  function automatic logic edp_lane_valid(input logic [1:0] lanes);
    return (lanes != 2'b11);
  endfunction

  function automatic logic [7:0] edp_type_byte(input edp_pkt_type_e pkt_type);
    return {pkt_type, 5'd0};
  endfunction

  function automatic logic [7:0] edp_vb_vec_byte(
    input logic [31:0] vec,
    input int unsigned idx
  );
    return vec[idx*8 +: 8];
  endfunction

  function automatic logic [31:0] edp_vb_vec_set_byte(
    input logic [31:0] vec,
    input int unsigned idx,
    input logic [7:0]  value
  );
    logic [31:0] tmp;
    tmp = vec;
    tmp[idx*8 +: 8] = value;
    return tmp;
  endfunction

  function automatic logic [7:0] edp_payload_get_byte(
    input edp_payload_t payload,
    input int unsigned  idx
  );
    return payload[idx*8 +: 8];
  endfunction

  function automatic edp_payload_t edp_payload_set_byte(
    input edp_payload_t payload,
    input int unsigned  idx,
    input logic [7:0]   value
  );
    edp_payload_t tmp;
    tmp = payload;
    tmp[idx*8 +: 8] = value;
    return tmp;
  endfunction

  function automatic logic [9:0] edp_plm10_get(
    input edp_plm10_vec_t vec,
    input int unsigned    idx
  );
    return vec[idx*10 +: 10];
  endfunction

  function automatic edp_plm10_vec_t edp_plm10_set(
    input edp_plm10_vec_t vec,
    input int unsigned    idx,
    input logic [9:0]     value
  );
    edp_plm10_vec_t tmp;
    tmp = vec;
    tmp[idx*10 +: 10] = value;
    return tmp;
  endfunction

  function automatic logic [131:0] edp_plm132_get(
    input edp_plm132_vec_t vec,
    input int unsigned     idx
  );
    return vec[idx*132 +: 132];
  endfunction

  function automatic edp_plm132_vec_t edp_plm132_set(
    input edp_plm132_vec_t vec,
    input int unsigned     idx,
    input logic [131:0]    value
  );
    edp_plm132_vec_t tmp;
    tmp = vec;
    tmp[idx*132 +: 132] = value;
    return tmp;
  endfunction

  function automatic asep_packet_t edp_packet_set_be_bit(
    input asep_packet_t pkt,
    input int unsigned  byte_start,
    input int unsigned  bit_pos,
    input logic         bit_value
  );
    asep_packet_t tmp;
    int unsigned byte_idx;
    int unsigned bit_idx;
    tmp = pkt;
    byte_idx = byte_start + (bit_pos / 8);
    bit_idx  = 7 - (bit_pos % 8);
    tmp[byte_idx*8 + bit_idx] = bit_value;
    return tmp;
  endfunction

  function automatic logic edp_packet_get_be_bit(
    input asep_packet_t pkt,
    input int unsigned  byte_start,
    input int unsigned  bit_pos
  );
    int unsigned byte_idx;
    int unsigned bit_idx;
    byte_idx = byte_start + (bit_pos / 8);
    bit_idx  = 7 - (bit_pos % 8);
    return pkt[byte_idx*8 + bit_idx];
  endfunction

  function automatic int unsigned edp_bytes_for_10b(input int unsigned sym_count);
    return (sym_count * 10 + 7) / 8;
  endfunction

  function automatic int unsigned edp_bytes_for_132b(input int unsigned sym_count);
    return (sym_count * 132 + 7) / 8;
  endfunction

  function automatic logic edp_komma_valid(input logic [3:0] code);
    return (code == EDP_KOMMA_NONE) || (code == EDP_KOMMA_BS) || (code == EDP_KOMMA_BE) ||
           (code == EDP_KOMMA_FS)   || (code == EDP_KOMMA_FE) || (code == EDP_KOMMA_SS) ||
           (code == EDP_KOMMA_SE)   || (code == EDP_KOMMA_SR) || (code == EDP_KOMMA_CP) ||
           (code == EDP_KOMMA_CPBS) || (code == EDP_KOMMA_CPSR) || (code == EDP_KOMMA_BF) ||
           (code == EDP_KOMMA_EOC)  || (code == EDP_KOMMA_SDPSPLIT);
  endfunction

endpackage

`default_nettype wire
