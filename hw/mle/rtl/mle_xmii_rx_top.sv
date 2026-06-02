`timescale 1ns/1ps
`default_nettype none

module mle_xmii_rx_top
  import asa_mle_pcs_pkg::*;
  import asa_mle_xmii_pkg::*;
(
  input  logic                            clk,
  input  logic                            rst,
  input  xmii_type_e                      xmii_type_i,
  input  logic                            plb_load_i,
  input  logic [MLE_XMII_STREAM_BITS-1:0] xmii_blocks_i,
  input  logic                            block_step_i,
  output logic                            host_rx_valid_o,
  output logic [31:0]                     host_rx_data_o,
  output logic [3:0]                      host_rx_ctrl_o,
  output logic                            skip_removed_o
);
  logic [MLE_XMII_STREAM_BITS-1:0] hold_q;
  logic [4:0] idx_q;
  logic active_q;
  logic [64:0] block_cur;
  logic pass_block;
  logic [63:0] word_data;
  logic [7:0]  word_ctrl;
  logic data_valid;

  assign block_cur = hold_q[65*idx_q +: 65];

  mle_rate_match_rx u_rm (
    .block_i(block_cur),
    .pass_block_o(pass_block),
    .removed_skip_o(skip_removed_o)
  );

  mle_64b65b_decode u_dec (
    .block_i(block_cur),
    .data_valid_o(data_valid),
    .word_data_o(word_data),
    .word_ctrl_o(word_ctrl)
  );

  mle_xmii_denormalize_rx u_denorm (
    .clk(clk), .rst(rst), .xmii_type_i(xmii_type_i),
    .word_valid_i(block_step_i && active_q && pass_block && data_valid),
    .word_data_i(word_data), .word_ctrl_i(word_ctrl),
    .host_valid_o(host_rx_valid_o), .host_data_o(host_rx_data_o), .host_ctrl_o(host_rx_ctrl_o)
  );

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      hold_q <= '0;
      idx_q <= '0;
      active_q <= 1'b0;
    end else begin
      if (plb_load_i) begin
        hold_q <= xmii_blocks_i;
        idx_q <= '0;
        active_q <= 1'b1;
      end else if (block_step_i && active_q) begin
        if (idx_q == MLE_XMII_BLOCKS_PER_PLB-1) begin
          idx_q <= '0;
          active_q <= 1'b0;
        end else begin
          idx_q <= idx_q + 1'b1;
        end
      end
    end
  end
endmodule

`default_nettype wire
