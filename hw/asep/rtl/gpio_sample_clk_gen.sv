`timescale 1ns/1ps
`default_nettype none

module gpio_sample_clk_gen (
  input  logic        clk,
  input  logic        rst,
  input  logic        soft_reset_i,
  input  logic        ptb_tick_i,
  input  logic        tdd_boundary_i,
  input  logic [12:0] sampling_period_i,
  output logic        sample_tick_o
);

  logic [12:0] count_q;

  always_ff @(posedge clk) begin
    if (rst || soft_reset_i) begin
      count_q       <= 13'd0;
      sample_tick_o <= 1'b0;
    end else begin
      sample_tick_o <= 1'b0;
      if (tdd_boundary_i) begin
        count_q <= 13'd0;
      end else if (ptb_tick_i && (sampling_period_i != 13'd0)) begin
        if (count_q == (sampling_period_i - 13'd1)) begin
          count_q       <= 13'd0;
          sample_tick_o <= 1'b1;
        end else begin
          count_q <= count_q + 13'd1;
        end
      end
    end
  end

endmodule

`default_nettype wire
