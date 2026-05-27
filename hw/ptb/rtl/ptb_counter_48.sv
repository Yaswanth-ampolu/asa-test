`timescale 1ns/1ps
`default_nettype none

module ptb_counter_48 (
  input  logic               clk,
  input  logic               rst,
  input  logic               soft_reset_i,
  input  logic               start_i,
  input  logic               wr_en_i,
  input  logic [47:0]        wr_value_i,
  input  logic               copy_oam_en_i,
  input  logic [47:0]        copy_oam_value_i,
  input  logic               local_copy_en_i,
  input  logic [47:0]        local_copy_value_i,
  input  logic               offset_apply_i,
  input  logic signed [15:0] offset_i,
  output logic [47:0]        ptb_clk_o,
  output logic               running_o
);

  logic [47:0] ptb_clk_q;
  logic        running_q;

  function automatic logic [47:0] apply_offset(input logic [47:0] value,
                                               input logic signed [15:0] offset);
    logic signed [49:0] extended;
    extended = $signed({2'b00, value}) + $signed(offset);
    if (extended < 50'sd0) begin
      return 48'd0;
    end
    return extended[47:0];
  endfunction

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      ptb_clk_q <= 48'd0;
      running_q <= 1'b0;
    end else if (soft_reset_i) begin
      ptb_clk_q <= 48'd0;
      running_q <= 1'b0;
    end else begin
      if (start_i) running_q <= 1'b1;

      if (local_copy_en_i) begin
        ptb_clk_q <= local_copy_value_i;
        running_q <= 1'b1;
      end else if (copy_oam_en_i) begin
        ptb_clk_q <= copy_oam_value_i;
        running_q <= 1'b1;
      end else if (wr_en_i) begin
        ptb_clk_q <= wr_value_i;
      end else if (offset_apply_i) begin
        ptb_clk_q <= apply_offset(ptb_clk_q, offset_i);
      end else if (running_q) begin
        ptb_clk_q <= ptb_clk_q + 48'd1;
      end
    end
  end

  assign ptb_clk_o = ptb_clk_q;
  assign running_o = running_q;

endmodule

`default_nettype wire
