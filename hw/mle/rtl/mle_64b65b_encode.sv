`timescale 1ns/1ps
`default_nettype none

module mle_64b65b_encode
  import asa_mle_xmii_pkg::*;
(
  input  logic [63:0] word_data_i,
  input  logic [7:0]  word_ctrl_i,
  output logic [64:0] block_o
);
  logic any_ctrl;
  logic [63:0] ctrl_bytes;

  always_comb begin
    any_ctrl = |word_ctrl_i;
    ctrl_bytes = word_data_i;
    if (any_ctrl) block_o = make_control_block(ctrl_bytes);
    else          block_o = make_data_block(word_data_i);
  end
endmodule

`default_nettype wire
