`timescale 1ns/1ps
`default_nettype none

module spi_tat_timer(
  input  logic        clk,
  input  logic        rst,
  input  logic        soft_reset_i,
  input  logic        ptb_tick_i,
  input  logic        start_i,
  input  logic [7:0]  tat_mult_i,
  input  logic [19:0] dcp_ticks_i,
  output logic        active_o,
  output logic        expired_pulse_o
);

  logic [27:0] count_q;
  logic [27:0] reload_count;
  assign reload_count = tat_mult_i * dcp_ticks_i;

  always_ff @(posedge clk) begin
    if (rst || soft_reset_i) begin
      count_q         <= '0;
      active_o        <= 1'b0;
      expired_pulse_o <= 1'b0;
    end else begin
      expired_pulse_o <= 1'b0;
      if (start_i) begin
        count_q  <= reload_count;
        active_o <= (reload_count != '0);
        if (reload_count == '0) expired_pulse_o <= 1'b1;
      end else if (active_o && ptb_tick_i) begin
        if (count_q <= 28'd1) begin
          count_q         <= '0;
          active_o        <= 1'b0;
          expired_pulse_o <= 1'b1;
        end else begin
          count_q <= count_q - 28'd1;
        end
      end
    end
  end

endmodule

`default_nettype wire
