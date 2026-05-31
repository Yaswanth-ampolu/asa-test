`timescale 1ns/1ps
`default_nettype none

module i2s_ptb_sync(
  input  logic        clk,
  input  logic        rst,
  input  logic        soft_reset_i,
  input  logic        clk_edge_i,
  input  logic [9:0]  coeff_k_i,
  input  logic [15:0] divisor_n_i,
  input  logic [23:0] ptb_timestamp_i,
  input  logic        rx_stamp_valid_i,
  input  logic [23:0] rx_stamp_i,
  output logic        capture_pulse_o,
  output logic [23:0] captured_stamp_o,
  output logic        delta_valid_o,
  output logic [23:0] delta_ticks_o,
  output logic [9:0]  reconstructed_ratio_k_o,
  output logic [15:0] reconstructed_div_n_o
);

  logic [15:0] clk_count_q;
  logic        have_prev_q;
  logic [23:0] prev_rx_stamp_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      clk_count_q              <= 16'd0;
      capture_pulse_o          <= 1'b0;
      captured_stamp_o         <= 24'd0;
      delta_valid_o            <= 1'b0;
      delta_ticks_o            <= 24'd0;
      reconstructed_ratio_k_o  <= 10'd0;
      reconstructed_div_n_o    <= 16'd0;
      have_prev_q              <= 1'b0;
      prev_rx_stamp_q          <= 24'd0;
    end else begin
      capture_pulse_o <= 1'b0;
      delta_valid_o   <= 1'b0;
      if (soft_reset_i) begin
        clk_count_q     <= 16'd0;
        have_prev_q     <= 1'b0;
        prev_rx_stamp_q <= 24'd0;
      end else begin
        if (clk_edge_i && (divisor_n_i != 16'd0)) begin
          if (clk_count_q == divisor_n_i - 16'd1) begin
            clk_count_q      <= 16'd0;
            capture_pulse_o  <= 1'b1;
            captured_stamp_o <= ptb_timestamp_i;
          end else begin
            clk_count_q <= clk_count_q + 16'd1;
          end
        end
        if (rx_stamp_valid_i) begin
          if (have_prev_q) begin
            delta_ticks_o <= rx_stamp_i - prev_rx_stamp_q;
            delta_valid_o <= 1'b1;
          end
          prev_rx_stamp_q         <= rx_stamp_i;
          have_prev_q             <= 1'b1;
          reconstructed_ratio_k_o <= coeff_k_i;
          reconstructed_div_n_o   <= divisor_n_i;
        end
      end
    end
  end

endmodule

`default_nettype wire
