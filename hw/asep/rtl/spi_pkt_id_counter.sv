`timescale 1ns/1ps
`default_nettype none

module spi_pkt_id_counter
  import asa_spi_asep_pkg::*;
(
  input  logic       clk,
  input  logic       rst,
  input  logic       soft_reset_i,
  input  logic       advance_i,
  output logic [6:0] pkt_id_o
);

  always_ff @(posedge clk) begin
    if (rst || soft_reset_i) pkt_id_o <= 7'd1;
    else if (advance_i)      pkt_id_o <= spi_next_pkt_id(pkt_id_o);
  end

endmodule

`default_nettype wire
