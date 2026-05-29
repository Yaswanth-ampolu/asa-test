`timescale 1ns/1ps
`default_nettype none

// Light Sleep PTB Interface
// Spec: Section 5.8.3.3, PDF p191
//
// PTB service owns ALL timer calculations and PTBclk management.
// This module provides the clean interface between the LS FSM and PTB service.
//
// Timers (Section 5.8.3.3):
//   timer_LSbedtime:    fires when PTBclk >= PTBbedtime
//   timer_LSalarmClock: fires when PTBclk >= PTBalarmclock
//
// The actual compare logic lives in the PTB service (ptb_top/ptb_timer_compare).
// This module just registers the set requests and connects the trigger outputs.

module ls_ptb_if (
  input  logic        clk,
  input  logic        rst,
  input  logic        soft_reset_i,  // Also clears armed timers (Fix 3)

  // From LS FSM: timer set requests
  input  logic        set_bedtime_i,        // Pulse to arm bedtime timer
  input  logic [47:0] bedtime_value_i,      // PTBbedtime value

  input  logic        set_alarmclock_i,     // Pulse to arm alarmclock timer
  input  logic [47:0] alarmclock_value_i,   // PTBalarmclock value

  // To PTB service: timer configuration
  output logic        ptb_bedtime_en_o,     // Enable bedtime compare
  output logic [47:0] ptb_bedtime_val_o,
  output logic        ptb_alarm_en_o,       // Enable alarmclock compare
  output logic [47:0] ptb_alarm_val_o,

  // From PTB service: trigger outputs
  input  logic        ptb_bedtime_trigger_i,    // timer_LSbedtime_trigger=TRUE
  input  logic        ptb_alarm_trigger_i,      // timer_LSalarmClock_trigger=TRUE

  // To LS FSM: trigger signals
  output logic        ls_bedtime_trigger_o,
  output logic        ls_alarmclock_trigger_o
);

  logic [47:0] bedtime_q, alarmclock_q;
  logic        bedtime_armed_q, alarm_armed_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst || soft_reset_i) begin
      bedtime_q       <= 48'd0;
      alarmclock_q    <= 48'd0;
      bedtime_armed_q <= 1'b0;
      alarm_armed_q   <= 1'b0;
    end else begin
      if (set_bedtime_i) begin
        bedtime_q       <= bedtime_value_i;
        bedtime_armed_q <= 1'b1;
      end else if (ptb_bedtime_trigger_i) begin
        bedtime_armed_q <= 1'b0;
      end

      if (set_alarmclock_i) begin
        alarmclock_q  <= alarmclock_value_i;
        alarm_armed_q <= 1'b1;
      end else if (ptb_alarm_trigger_i) begin
        alarm_armed_q <= 1'b0;
      end
    end
  end

  assign ptb_bedtime_en_o  = bedtime_armed_q;
  assign ptb_bedtime_val_o = bedtime_q;
  assign ptb_alarm_en_o    = alarm_armed_q;
  assign ptb_alarm_val_o   = alarmclock_q;

  assign ls_bedtime_trigger_o   = ptb_bedtime_trigger_i;
  assign ls_alarmclock_trigger_o = ptb_alarm_trigger_i;

endmodule

`default_nettype wire
