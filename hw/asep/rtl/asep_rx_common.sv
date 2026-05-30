`timescale 1ns/1ps
`default_nettype none

module asep_rx_common
  import asa_asep_pkg::*;
(
  input  logic          clk,
  input  logic          rst,
  input  logic          soft_reset_i,
  input  logic          container_valid_i,
  input  logic          packet_id_ok_i,
  input  asep_container_t dll_payload_i,
  input  logic [10:0]   dll_payload_len_i,

  output logic          packet_valid_o,
  output asep_packet_t  packet_o,
  output logic [11:0]   packet_len_o,
  output logic [6:0]    stream_type_o,
  output logic          follow_flag_o,
  output asep_ts_mode_e ts_mode_o,
  output logic [31:0]   ts_value_o,
  output asep_frag_code_e frag_code_o,
  output logic [9:0]    boundary_pos_o,
  output logic          error_o,
  output logic          assembling_o
);

  logic [10:0] data_start_idx;
  logic malformed;
  logic append_valid, terminate, seed_next_valid;
  asep_packet_t append_bytes, seed_next_bytes;
  logic [11:0] append_len, seed_next_len;
  integer i;
  logic packet_valid_int, error_int;
  asep_packet_t packet_int;
  logic [11:0] packet_len_int;
  logic [7:0] pkt_b0, pkt_b1;

  /* verilator lint_off WIDTHCONCAT */
  localparam asep_packet_t ASEP_PKT_ZERO = '0;
  /* verilator lint_on WIDTHCONCAT */

  assign pkt_b0 = asep_get_byte(packet_int, 0);
  assign pkt_b1 = asep_get_byte(packet_int, 1);

  asep_frag_decode u_decode (
    .dll_payload_i     (dll_payload_i),
    .dll_payload_len_i (dll_payload_len_i),
    .frag_code_o       (frag_code_o),
    .boundary_pos_o    (boundary_pos_o),
    .byte1_present_o   (),
    .data_start_idx_o  (data_start_idx),
    .malformed_o       (malformed)
  );

  always_comb begin
    append_valid = 1'b0;
    append_bytes = ASEP_PKT_ZERO;
    append_len = 12'd0;
    terminate = 1'b0;
    seed_next_valid = 1'b0;
    seed_next_bytes = ASEP_PKT_ZERO;
    seed_next_len = 12'd0;

    if (container_valid_i && !malformed) begin
      case (frag_code_o)
        ASEP_FRAG_MID: begin
          append_valid = 1'b1;
          append_len = dll_payload_len_i - data_start_idx;
          for (i = 0; i < ASEP_MAX_PACKET_BYTES; i++) begin
            if (i < append_len) begin
              append_bytes[i*8 +: 8] = dll_payload_i[(data_start_idx + i)*8 +: 8];
            end
          end
        end
        ASEP_FRAG_END_LAST: begin
          append_valid = 1'b1;
          terminate = 1'b1;
          append_len = dll_payload_len_i - data_start_idx;
          for (i = 0; i < ASEP_MAX_PACKET_BYTES; i++) begin
            if (i < append_len) begin
              append_bytes[i*8 +: 8] = dll_payload_i[(data_start_idx + i)*8 +: 8];
            end
          end
        end
        ASEP_FRAG_END_PAD: begin
          if (boundary_pos_o >= data_start_idx) begin
            append_valid = 1'b1;
            terminate = 1'b1;
            append_len = boundary_pos_o - data_start_idx;
            for (i = 0; i < ASEP_MAX_PACKET_BYTES; i++) begin
              if (i < append_len) begin
                append_bytes[i*8 +: 8] = dll_payload_i[(data_start_idx + i)*8 +: 8];
              end
            end
          end
        end
        ASEP_FRAG_END_HEADER: begin
          if ((boundary_pos_o >= data_start_idx) &&
              (boundary_pos_o < dll_payload_len_i) &&
              ((dll_payload_len_i - boundary_pos_o) >= 11'd2)) begin
            append_valid = 1'b1;
            terminate = 1'b1;
            append_len = boundary_pos_o - data_start_idx;
            seed_next_valid = 1'b1;
            seed_next_len = dll_payload_len_i - boundary_pos_o;
            for (i = 0; i < ASEP_MAX_PACKET_BYTES; i++) begin
              if (i < append_len) begin
                append_bytes[i*8 +: 8] = dll_payload_i[(data_start_idx + i)*8 +: 8];
              end
              if (i < seed_next_len) begin
                seed_next_bytes[i*8 +: 8] = dll_payload_i[(boundary_pos_o + i)*8 +: 8];
              end
            end
          end
        end
        default: begin end
      endcase
    end
  end

  asep_reassembly u_reassembly (
    .clk              (clk),
    .rst              (rst),
    .soft_reset_i     (soft_reset_i),
    .packet_id_ok_i   (packet_id_ok_i),
    .append_valid_i   (append_valid),
    .append_bytes_i   (append_bytes),
    .append_len_i     (append_len),
    .terminate_i      (terminate),
    .seed_next_valid_i(seed_next_valid),
    .seed_next_bytes_i(seed_next_bytes),
    .seed_next_len_i  (seed_next_len),
    .packet_valid_o   (packet_valid_int),
    .packet_o         (packet_int),
    .packet_len_o     (packet_len_int),
    .error_o          (error_int),
    .assembling_o     (assembling_o)
  );

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      packet_valid_o <= 1'b0;
      packet_o <= ASEP_PKT_ZERO;
      packet_len_o <= 12'd0;
      stream_type_o <= 7'd0;
      follow_flag_o <= 1'b0;
      ts_mode_o <= ASEP_TS_NONE;
      ts_value_o <= 32'd0;
      error_o <= 1'b0;
    end else if (soft_reset_i) begin
      packet_valid_o <= 1'b0;
      packet_o <= ASEP_PKT_ZERO;
      packet_len_o <= 12'd0;
      stream_type_o <= 7'd0;
      follow_flag_o <= 1'b0;
      ts_mode_o <= ASEP_TS_NONE;
      ts_value_o <= 32'd0;
      error_o <= 1'b0;
    end else begin
      packet_valid_o <= packet_valid_int;
      packet_o <= packet_int;
      packet_len_o <= packet_len_int;
      error_o <= error_int || (container_valid_i && malformed);
      if (packet_valid_int) begin
        stream_type_o <= pkt_b0[7:1];
        follow_flag_o <= pkt_b0[0];
        ts_mode_o <= asep_ts_mode_e'(pkt_b1[1:0]);
        if (pkt_b1[1:0] != ASEP_TS_NONE) begin
          ts_value_o <= asep_get_u32_be(packet_int, 2);
        end else begin
          ts_value_o <= 32'd0;
        end
      end
    end
  end

endmodule
