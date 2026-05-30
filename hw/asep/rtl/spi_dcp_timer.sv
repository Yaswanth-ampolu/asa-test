`timescale 1ns/1ps
`default_nettype none

module spi_dcp_timer(
  input  logic        clk,
  input  logic        rst,
  input  logic        soft_reset_i,
  input  logic        ptb_tick_i,
  input  logic        start_i,
  input  logic [19:0] dcp_ticks_i,
  output logic        active_o,
  output logic        expired_pulse_o
);

  logic [19:0] count_q;

  always_ff @(posedge clk) begin
    if (rst || soft_reset_i) begin
      count_q          <= 20'd0;
      active_o         <= 1'b0;
      expired_pulse_o  <= 1'b0;
    end else begin
      expired_pulse_o <= 1'b0;
      if (start_i) begin
        count_q  <= dcp_ticks_i;
        active_o <= (dcp_ticks_i != 20'd0);
        if (dcp_ticks_i == 20'd0) expired_pulse_o <= 1'b1;
      end else if (active_o && ptb_tick_i) begin
        if (count_q <= 20'd1) begin
          count_q         <= 20'd0;
          active_o        <= 1'b0;
          expired_pulse_o <= 1'b1;
        end else begin
          count_q <= count_q - 20'd1;
        end
      end
    end
  end

endmodule

`default_nettype wire
