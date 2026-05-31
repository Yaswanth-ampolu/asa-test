`timescale 1ns/1ps
`default_nettype none

module i2c_cmd_id_mgr(
  input  logic       clk,
  input  logic       rst,
  input  logic       soft_reset_i,
  input  logic       alloc_i,
  output logic [7:0] cmd_id_o
);
  import asa_i2c_asep_pkg::*;

  logic [7:0] cmd_id_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      cmd_id_q <= 8'h01;
    end else if (soft_reset_i) begin
      cmd_id_q <= 8'h01;
    end else if (alloc_i) begin
      cmd_id_q <= i2c_next_cmd_id(cmd_id_q);
    end
  end

  assign cmd_id_o = cmd_id_q;

endmodule

`default_nettype wire
