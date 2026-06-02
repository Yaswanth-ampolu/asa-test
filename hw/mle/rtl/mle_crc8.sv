`timescale 1ns/1ps
`default_nettype none

module mle_crc8
  import asa_mle_pcs_pkg::*;
(
  input  logic       clk,
  input  logic       rst,
  input  logic       init_i,
  input  logic       valid_i,
  input  logic [7:0] data_i,
  output logic [7:0] crc_o,
  output logic [7:0] crc_final_o
);
  logic [7:0] crc_q;

  assign crc_o       = crc_q;
  assign crc_final_o = reflect8(crc_q ^ 8'hFF);

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      crc_q <= 8'hFF;
    end else if (init_i) begin
      crc_q <= 8'hFF;
    end else if (valid_i) begin
      crc_q <= crc8_step(crc_q, data_i);
    end
  end
endmodule

`default_nettype wire
