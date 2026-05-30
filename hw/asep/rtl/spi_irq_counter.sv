`timescale 1ns/1ps
`default_nettype none

module spi_irq_counter
  import asa_spi_asep_pkg::*;
(
  input  logic       clk,
  input  logic       rst,
  input  logic       soft_reset_i,
  input  logic       advance_i,
  output logic [7:0] irq_count_o
);

  always_ff @(posedge clk) begin
    if (rst || soft_reset_i) irq_count_o <= 8'd1;
    else if (advance_i)      irq_count_o <= spi_next_irq_count(irq_count_o);
  end

endmodule

`default_nettype wire
