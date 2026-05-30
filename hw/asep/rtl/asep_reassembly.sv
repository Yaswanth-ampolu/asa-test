`timescale 1ns/1ps
`default_nettype none

module asep_reassembly
  import asa_asep_pkg::*;
(
  input  logic          clk,
  input  logic          rst,
  input  logic          soft_reset_i,
  input  logic          packet_id_ok_i,
  input  logic          append_valid_i,
  input  asep_packet_t  append_bytes_i,
  input  logic [11:0]   append_len_i,
  input  logic          terminate_i,
  input  logic          seed_next_valid_i,
  input  asep_packet_t  seed_next_bytes_i,
  input  logic [11:0]   seed_next_len_i,
  output logic          packet_valid_o,
  output asep_packet_t  packet_o,
  output logic [11:0]   packet_len_o,
  output logic          error_o,
  output logic          assembling_o
);

  asep_packet_t buf_q, buf_d;
  logic [11:0]  len_q, len_d;
  logic         packet_valid_d, error_d, assembling_d;
  asep_packet_t packet_d;
  logic [11:0]  packet_len_d;
  integer i;

  /* verilator lint_off WIDTHCONCAT */
  localparam asep_packet_t ASEP_PKT_ZERO = '0;
  /* verilator lint_on WIDTHCONCAT */

  always_comb begin
    buf_d = buf_q;
    len_d = len_q;
    packet_d = ASEP_PKT_ZERO;
    packet_len_d = 12'd0;
    packet_valid_d = 1'b0;
    error_d = 1'b0;

    if (!packet_id_ok_i && (len_q != 12'd0)) begin
      buf_d = ASEP_PKT_ZERO;
      len_d = 12'd0;
      error_d = 1'b1;
    end else if (append_valid_i) begin
      if ((len_q + append_len_i) > ASEP_MAX_PACKET_BYTES) begin
        buf_d = ASEP_PKT_ZERO;
        len_d = 12'd0;
        error_d = 1'b1;
      end else begin
        for (i = 0; i < ASEP_MAX_PACKET_BYTES; i++) begin
          if (i < append_len_i) begin
            buf_d[(len_q + i)*8 +: 8] = append_bytes_i[i*8 +: 8];
          end
        end
        len_d = len_q + append_len_i;

        if (terminate_i) begin
          packet_d = buf_d;
          packet_len_d = len_q + append_len_i;
          packet_valid_d = 1'b1;
          buf_d = ASEP_PKT_ZERO;
          len_d = 12'd0;
          if (seed_next_valid_i) begin
            if (seed_next_len_i > ASEP_MAX_PACKET_BYTES) begin
              error_d = 1'b1;
            end else begin
              buf_d = seed_next_bytes_i;
              len_d = seed_next_len_i;
            end
          end
        end
      end
    end

    assembling_d = (len_d != 12'd0);
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      buf_q <= ASEP_PKT_ZERO;
      len_q <= 12'd0;
      packet_valid_o <= 1'b0;
      packet_o <= ASEP_PKT_ZERO;
      packet_len_o <= 12'd0;
      error_o <= 1'b0;
      assembling_o <= 1'b0;
    end else if (soft_reset_i) begin
      buf_q <= ASEP_PKT_ZERO;
      len_q <= 12'd0;
      packet_valid_o <= 1'b0;
      packet_o <= ASEP_PKT_ZERO;
      packet_len_o <= 12'd0;
      error_o <= 1'b0;
      assembling_o <= 1'b0;
    end else begin
      buf_q <= buf_d;
      len_q <= len_d;
      packet_valid_o <= packet_valid_d;
      packet_o <= packet_d;
      packet_len_o <= packet_len_d;
      error_o <= error_d;
      assembling_o <= assembling_d;
    end
  end

endmodule
