`timescale 1ns/1ps
`default_nettype none

// ASA SoftReset Controller
// Spec: Section 3.2.7, micro-architecture-register-model.md Section 8.3
//
// Monitors register 1.0007 bit 0 (write-one-trigger, self-clearing).
// On assertion:
//   1. Asserts soft_reset pulse for one cycle
//   2. State machines reset (node FSM -> Startup)
//   3. Status/SC registers cleared
//   4. Configuration registers preserved
//   5. Bit self-clears (reads as 0 after write)

module asa_soft_reset_ctrl (
  input  logic        clk,
  input  logic        rst,

  // From register bus: write to 1.0007
  input  logic        soft_reset_wr,    // Write pulse to SoftReset register
  input  logic [15:0] soft_reset_data,  // Written data

  // Output: one-cycle pulse to all subsystems
  output logic        soft_reset_out
);

  logic trigger_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      trigger_q <= 1'b0;
    end else begin
      if (soft_reset_wr && soft_reset_data[0]) begin
        trigger_q <= 1'b1;
      end else begin
        trigger_q <= 1'b0;
      end
    end
  end

  assign soft_reset_out = trigger_q;

endmodule

`default_nettype wire
