`timescale 1ns/1ps
`default_nettype none

module i2s_pkt_id_counter
  import asa_i2s_asep_pkg::*;
(
  input  logic       clk,
  input  logic       rst,
  input  logic       soft_reset_i,
  input  logic       advance_i,
  output logic [6:0] pkt_id_o
);

  logic [6:0] pkt_id_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      pkt_id_q <= 7'd1;
    end else if (soft_reset_i) begin
      pkt_id_q <= 7'd1;
    end else if (advance_i) begin
      pkt_id_q <= i2s_next_pkt_id(pkt_id_q);
    end
  end

  assign pkt_id_o = pkt_id_q;

endmodule

`default_nettype wire
