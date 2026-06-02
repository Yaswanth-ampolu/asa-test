`timescale 1ns/1ps
`default_nettype none

module mle_rate_match_rx
  import asa_mle_xmii_pkg::*;
(
  input  logic [64:0] block_i,
  output logic        pass_block_o,
  output logic        removed_skip_o
);
  always_comb begin
    removed_skip_o = is_skip_block(block_i);
    pass_block_o   = !removed_skip_o;
  end
endmodule

`default_nettype wire
