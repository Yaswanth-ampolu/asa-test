`timescale 1ns/1ps
`default_nettype none

module mle_phase1g_info(
  input  logic [15:0] mlecapability1_i,
  input  logic [15:0] mlecapability2_i,
  input  logic [15:0] mleconfig_i,
  input  logic [1:0]  ph1g_status_i,
  input  logic [2:0]  txtest_i,
  output logic [39:0] inf_1g_o
);
  logic [31:0] low_bits;
  logic [7:0] parity;

  always_comb begin
    low_bits        = 32'd0;
    low_bits[31:30] = ph1g_status_i;
    low_bits[29:27] = mlecapability1_i[15:13];
    low_bits[26:25] = 2'b00;
    low_bits[24:19] = mlecapability2_i[15:10];
    low_bits[18:16] = 3'b000;
    low_bits[15:11] = mleconfig_i[15:11];
    low_bits[10:8]  = txtest_i;
    low_bits[7:1]   = 7'd0;
    low_bits[0]     = 1'b1;

    for (int k = 0; k < 8; k++) begin
      parity[k] = low_bits[k] ^ low_bits[8+k] ^ low_bits[16+k] ^ low_bits[24+k];
    end
    inf_1g_o = {parity, low_bits};
  end
endmodule

`default_nettype wire
