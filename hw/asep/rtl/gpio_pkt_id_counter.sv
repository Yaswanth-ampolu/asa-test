`timescale 1ns/1ps
`default_nettype none

module gpio_pkt_id_counter (
  input  logic       clk,
  input  logic       rst,
  input  logic       soft_reset_i,
  input  logic       advance_i,
  output logic [6:0] pkt_id_o
);

  always_ff @(posedge clk) begin
    if (rst || soft_reset_i) begin
      pkt_id_o <= 7'd1;
    end else if (advance_i) begin
      if (pkt_id_o == 7'd127) pkt_id_o <= 7'd1;
      else                    pkt_id_o <= pkt_id_o + 7'd1;
    end
  end

endmodule

`default_nettype wire
