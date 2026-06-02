`timescale 1ns/1ps
`default_nettype none

module mle_xmii_tx_top
  import asa_mle_pcs_pkg::*;
  import asa_mle_xmii_pkg::*;
(
  input  logic                            clk,
  input  logic                            rst,
  input  xmii_type_e                      xmii_type_i,
  input  logic                            host_tx_valid_i,
  input  logic [31:0]                     host_tx_data_i,
  input  logic [3:0]                      host_tx_ctrl_i,
  output logic                            host_tx_ready_o,
  input  logic                            block_slot_advance_i,
  output logic [MLE_XMII_STREAM_BITS-1:0] xmii_blocks_o,
  output logic                            plb_valid_o,
  output logic                            skip_inserted_o
);
  logic        word_valid;
  logic [63:0] word_data;
  logic [7:0]  word_ctrl;
  logic [64:0] enc_block, out_block;
  logic        used_input;
  logic [4:0]  block_cnt_q;
  logic [MLE_XMII_STREAM_BITS-1:0] buffer_q;

  mle_xmii_normalize_tx u_norm (
    .clk(clk), .rst(rst), .xmii_type_i(xmii_type_i),
    .host_valid_i(host_tx_valid_i), .host_data_i(host_tx_data_i), .host_ctrl_i(host_tx_ctrl_i),
    .host_ready_o(host_tx_ready_o), .word_valid_o(word_valid), .word_data_o(word_data), .word_ctrl_o(word_ctrl)
  );

  mle_64b65b_encode u_enc (
    .word_data_i(word_data),
    .word_ctrl_i(word_ctrl),
    .block_o(enc_block)
  );

  mle_rate_match_tx u_rm (
    .encoded_valid_i(word_valid),
    .encoded_block_i(enc_block),
    .slot_advance_i(block_slot_advance_i),
    .block_o(out_block),
    .used_input_o(used_input),
    .inserted_skip_o(skip_inserted_o)
  );

  assign xmii_blocks_o = buffer_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      block_cnt_q <= '0;
      buffer_q    <= '0;
      plb_valid_o <= 1'b0;
    end else begin
      plb_valid_o <= 1'b0;
      if (block_slot_advance_i) begin
        buffer_q[65*block_cnt_q +: 65] <= out_block;
        if (block_cnt_q == MLE_XMII_BLOCKS_PER_PLB-1) begin
          block_cnt_q <= '0;
          plb_valid_o <= 1'b1;
        end else begin
          block_cnt_q <= block_cnt_q + 1'b1;
        end
      end
    end
  end
endmodule

`default_nettype wire
