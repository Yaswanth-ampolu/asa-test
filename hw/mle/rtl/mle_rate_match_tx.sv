`timescale 1ns/1ps
`default_nettype none

module mle_rate_match_tx
  import asa_mle_xmii_pkg::*;
(
  input  logic        encoded_valid_i,
  input  logic [64:0] encoded_block_i,
  input  logic        slot_advance_i,
  output logic [64:0] block_o,
  output logic        used_input_o,
  output logic        inserted_skip_o
);
  always_comb begin
    block_o          = make_skip_block();
    used_input_o     = 1'b0;
    inserted_skip_o  = 1'b0;
    if (slot_advance_i) begin
      if (encoded_valid_i) begin
        block_o      = encoded_block_i;
        used_input_o = 1'b1;
      end else begin
        inserted_skip_o = 1'b1;
      end
    end
  end
endmodule

`default_nettype wire
