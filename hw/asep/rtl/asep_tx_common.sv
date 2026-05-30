`timescale 1ns/1ps
`default_nettype none

module asep_tx_common
  import asa_intf_pkg::*;
  import asa_asep_pkg::*;
(
  input  logic            build_req_i,
  input  slot_size_e      slot_size_i,

  input  logic            pkt0_valid_i,
  input  logic [6:0]      pkt0_stream_type_i,
  input  asep_ts_mode_e   pkt0_ts_mode_i,
  input  logic [31:0]     pkt0_ts_value_i,
  input  asep_packet_t    pkt0_body_i,
  input  logic [11:0]     pkt0_body_len_i,
  input  logic [11:0]     pkt0_offset_i,

  input  logic            pkt1_valid_i,
  input  logic [6:0]      pkt1_stream_type_i,
  input  asep_ts_mode_e   pkt1_ts_mode_i,
  input  logic [31:0]     pkt1_ts_value_i,
  input  asep_packet_t    pkt1_body_i,
  input  logic [11:0]     pkt1_body_len_i,
  input  logic [11:0]     pkt1_offset_i,

  output logic            ptb_capture_req_o,
  output logic            data_valid_o,
  output logic            yield_o,
  output asep_frag_code_e frag_code_o,
  output logic [9:0]      boundary_pos_o,
  output asep_container_t dll_payload_o,
  output logic [10:0]     dll_payload_len_o,
  output logic [11:0]     used_pkt0_bytes_o,
  output logic [11:0]     used_pkt1_bytes_o,
  output logic            overflow_o
);

  asep_packet_t pkt0_full, pkt1_full;
  logic [11:0] pkt0_hdr_len, pkt1_hdr_len, pkt0_total_len, pkt1_total_len;
  logic [11:0] rem0, rem1;
  logic [10:0] slot_bytes;
  logic [10:0] payload_bytes;
  logic [10:0] boundary_tmp;
  logic follow_flag0;
  asep_frag_code_e frag_code_d;
  logic [9:0] boundary_d;
  asep_container_t frag_bytes_d, dll_payload_d;
  logic [11:0] used0_d, used1_d;
  logic [10:0] frag_len_d;
  logic data_valid_d, yield_d;
  logic overflow_enc;
  integer i;

  /* verilator lint_off WIDTHCONCAT */
  localparam asep_packet_t ASEP_PKT_ZERO = '0;
  localparam asep_container_t ASEP_CONT_ZERO = '0;
  /* verilator lint_on WIDTHCONCAT */

  function automatic asep_packet_t build_packet(
    input logic [6:0]    stream_type,
    input logic          follow_flag,
    input asep_ts_mode_e ts_mode,
    input logic [31:0]   ts_value,
    input asep_packet_t  body,
    input logic [11:0]   body_len
  );
    asep_packet_t p;
    integer j;
    p = ASEP_PKT_ZERO;
    p[7:0] = asep_hdr_byte0(stream_type, follow_flag);
    p[15:8] = asep_hdr_byte1(ts_mode);
    if (ts_mode != ASEP_TS_NONE) begin
      p[23:16] = ts_value[31:24];
      p[31:24] = ts_value[23:16];
      p[39:32] = ts_value[15:8];
      p[47:40] = ts_value[7:0];
    end
    for (j = 0; j < ASEP_MAX_PACKET_BYTES; j++) begin
      if (j < body_len) begin
        p[(asep_common_hdr_bytes(ts_mode) + j)*8 +: 8] = body[j*8 +: 8];
      end
    end
    return p;
  endfunction

  asep_frag_encode u_encode (
    .slot_size_i      (slot_size_i),
    .frag_code_i      (frag_code_d),
    .boundary_pos_i   (boundary_d),
    .frag_bytes_i     (frag_bytes_d),
    .frag_bytes_len_i (frag_len_d),
    .dll_payload_o    (dll_payload_d),
    .dll_payload_len_o(dll_payload_len_o),
    .byte1_present_o  (),
    .overflow_o       (overflow_enc)
  );

  always_comb begin
    pkt0_hdr_len = 12'(asep_common_hdr_bytes(pkt0_ts_mode_i));
    pkt1_hdr_len = 12'(asep_common_hdr_bytes(pkt1_ts_mode_i));
    pkt0_total_len = pkt0_hdr_len + pkt0_body_len_i;
    pkt1_total_len = pkt1_hdr_len + pkt1_body_len_i;
    rem0 = (pkt0_total_len > pkt0_offset_i) ? (pkt0_total_len - pkt0_offset_i) : 12'd0;
    rem1 = (pkt1_total_len > pkt1_offset_i) ? (pkt1_total_len - pkt1_offset_i) : 12'd0;
    slot_bytes = 11'(asep_slot_bytes(slot_size_i));
    payload_bytes = slot_bytes;
    ptb_capture_req_o = build_req_i && pkt0_valid_i && (pkt0_ts_mode_i == ASEP_TS_INGRESS);
    data_valid_d = 1'b0;
    yield_d = 1'b0;
    frag_code_d = ASEP_FRAG_END_LAST;
    boundary_d = 10'd0;
    frag_bytes_d = ASEP_CONT_ZERO;
    used0_d = 12'd0;
    used1_d = 12'd0;
    frag_len_d = 11'd0;
    follow_flag0 = 1'b0;
    boundary_tmp = 11'd0;
    pkt0_full = ASEP_PKT_ZERO;
    pkt1_full = ASEP_PKT_ZERO;

    if (!build_req_i) begin
      data_valid_d = 1'b0;
      yield_d = 1'b0;
    end else if (!pkt0_valid_i) begin
      yield_d = 1'b1;
    end else begin
      if (rem0 > (slot_bytes - 11'd1)) begin
        frag_code_d = ASEP_FRAG_MID;
        used0_d = slot_bytes - 11'd1;
        frag_len_d = slot_bytes - 11'd1;
      end else if ((pkt1_valid_i && (rem1 != 12'd0)) && (rem0 <= (slot_bytes - 11'd4))) begin
        frag_code_d = ASEP_FRAG_END_HEADER;
        boundary_tmp = 11'd2 + rem0;
        boundary_d = boundary_tmp[9:0];
        used0_d = rem0;
        used1_d = ((slot_bytes - boundary_tmp) > rem1) ? rem1 : (slot_bytes - boundary_tmp);
        frag_len_d = rem0 + used1_d;
        follow_flag0 = 1'b1;
      end else if (rem0 == (slot_bytes - 11'd1)) begin
        frag_code_d = ASEP_FRAG_END_LAST;
        used0_d = rem0;
        frag_len_d = rem0;
      end else begin
        frag_code_d = ASEP_FRAG_END_PAD;
        boundary_tmp = 11'd2 + rem0;
        boundary_d = boundary_tmp[9:0];
        used0_d = rem0;
        frag_len_d = rem0;
      end

      pkt0_full = build_packet(pkt0_stream_type_i, follow_flag0, pkt0_ts_mode_i, pkt0_ts_value_i,
                               pkt0_body_i, pkt0_body_len_i);
      pkt1_full = build_packet(pkt1_stream_type_i, 1'b0, pkt1_ts_mode_i, pkt1_ts_value_i,
                               pkt1_body_i, pkt1_body_len_i);

      for (i = 0; i < ASEP_MAX_CONTAINER_BYTES; i++) begin
        if (i < used0_d) begin
          frag_bytes_d[i*8 +: 8] = pkt0_full[(pkt0_offset_i + i)*8 +: 8];
        end else if ((i - used0_d) < used1_d) begin
          frag_bytes_d[i*8 +: 8] = pkt1_full[(pkt1_offset_i + (i - used0_d))*8 +: 8];
        end
      end
      data_valid_d = 1'b1;
    end
  end

  assign data_valid_o = data_valid_d;
  assign yield_o = yield_d;
  assign frag_code_o = frag_code_d;
  assign boundary_pos_o = boundary_d;
  assign dll_payload_o = dll_payload_d;
  assign used_pkt0_bytes_o = used0_d;
  assign used_pkt1_bytes_o = used1_d;
  assign overflow_o = overflow_enc;

endmodule
