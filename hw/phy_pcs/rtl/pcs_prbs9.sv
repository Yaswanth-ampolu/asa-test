`timescale 1ns/1ps
`default_nettype none

// PCS PRBS9 Dithering Source
// Spec: Section 4.2.2.3.4, Equation 4-4, Figure 4-5
//
// Polynomial: g_Di(x) = x^9 + x^5 + 1
// LFSR: S_Di[8:0], output tap S0 = S_Di[0]
// Feedback: S_Di[5] XOR S_Di[8] → new bit shifted in
// Init: 0x001 at startup_INIT
//
// Used to compute sync sequence offset (0-31) by extracting
// 5 consecutive S0 outputs into a 5-bit value.

module pcs_prbs9
  import asa_pcs_pkg::*;
(
  input  logic        clk,
  input  logic        rst,

  input  logic        init_i,      // Reset to PRBS9_INIT
  input  logic        advance_i,   // Shift one step (advanced 5x per resync header)

  output logic        s0_o,        // Current output bit
  output logic [8:0]  state_o,     // Full state for debug
  output logic [4:0]  offset_o     // Computed 5-bit dithering offset from current state
);

  logic [8:0] state_q;

  assign s0_o    = state_q[0];
  assign state_o = state_q;
  assign offset_o = prbs9_offset(state_q);

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q <= PRBS9_INIT;
    end else if (init_i) begin
      state_q <= PRBS9_INIT;
    end else if (advance_i) begin
      state_q <= prbs9_step(state_q);
    end
  end

endmodule

`default_nettype wire
