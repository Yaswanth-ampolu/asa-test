`timescale 1ns/1ps
`default_nettype none

// PCS PRBS11 Generator for Resynchronization Header
// Spec: Section 4.2.2.3.3, Equation 4-3, Figure 4-4
//
// Polynomial: g_ReSy(x) = x^11 + x^9 + 1
// LFSR: S_ReSy[10:0], output tap S0 = S_ReSy[0]
// Feedback: S_ReSy[9] XOR S_ReSy[10] → new bit shifted in
// Init: 0x001 at startup_INIT

module pcs_prbs11
  import asa_pcs_pkg::*;
(
  input  logic        clk,
  input  logic        rst,

  input  logic        init_i,      // Reset to PRBS11_INIT
  input  logic        advance_i,   // Shift one step

  output logic        s0_o,        // Current output bit
  output logic [10:0] state_o      // Full state for debug
);

  logic [10:0] state_q;

  assign s0_o    = state_q[0];
  assign state_o = state_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q <= PRBS11_INIT;
    end else if (init_i) begin
      state_q <= PRBS11_INIT;
    end else if (advance_i) begin
      state_q <= prbs11_step(state_q);
    end
  end

endmodule

`default_nettype wire
