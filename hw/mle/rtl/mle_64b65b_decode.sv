`timescale 1ns/1ps
`default_nettype none

module mle_64b65b_decode(
  input  logic [64:0] block_i,
  output logic        data_valid_o,
  output logic [63:0] word_data_o,
  output logic [7:0]  word_ctrl_o
);
  always_comb begin
    word_data_o = '0;
    word_ctrl_o = '0;
    for (int i = 0; i < 8; i++) begin
      word_data_o[8*i +: 8] = block_i[1 + 8*i +: 8];
    end
    if (block_i[0]) begin
      word_ctrl_o = 8'hFF;
      data_valid_o = 1'b0;
    end else begin
      data_valid_o = 1'b1;
    end
  end
endmodule

`default_nettype wire
