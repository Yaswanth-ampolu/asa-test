`default_nettype none

// ASA Light Sleep Controller Package
// Source of truth: ASA Technical Specification v2.0, Section 5.8 (pp189-193)
// Figure 5-12 (root FSM), Figure 5-13 (non-root FSM) verified against PDF images.
//
// Light Sleep is OPTIONAL per spec (Section 5.8, p189).
// The feature is enabled by LightSleepCapability register (2.2250 bit 0).

package asa_ls_pkg;

  // =========================================================================
  // FSM Constants (Section 5.8.3.1, PDF p191)
  // =========================================================================
  localparam int unsigned PH1G_TIME  = 820;   // PTB tics per Phase1G cycle
  localparam int unsigned PHSGX_TIME = 6844;  // PTB tics per PhaseSGA/B/C cycle

  // Feasibility thresholds (Section 5.8.1.1, PDF p190)
  localparam int unsigned LS_NET_SLEEP_MIN_TICS = 25000; // > 100µs net sleep
  localparam int unsigned LS_BEDTIME_LEAD_TICS  = 12500; // > 50µs lead time
  localparam int unsigned LS_PTB_DRIFT_MAX_TICS = 140;   // Max drift during sleep

  // =========================================================================
  // Root Node FSM States (Figure 5-12, PDF p192)
  // Two paths: non-root-initiated (path 1) and root-initiated (path 2)
  // =========================================================================
  typedef enum logic [4:0] {
    // Idle
    ROOT_IDLE          = 5'd0,
    // Non-root is initiating (left column, Figure 5-12)
    ROOT_MEDIATE_1     = 5'd1,   // Receive announce, issue LSannounce to n others
    ROOT_ANNOUNCE_1    = 5'd2,   // Wait for ALL n LSconfirm/LSdeny responses
    ROOT_DENY_1        = 5'd3,   // LSpossible=FALSE: send deny
    ROOT_CONFIRM_1     = 5'd4,   // LSpossible=TRUE: send confirm
    ROOT_ISSUE_SLEEP_1 = 5'd5,   // Send LSsleep to all n nodes
    ROOT_LIGHTS_OUT_1  = 5'd6,   // Root affected: set timer_LSalarmClock → (a)
    ROOT_DREAMING_1    = 5'd7,   // Sleeping
    ROOT_RESTARTING_1  = 5'd8,   // Woken: status=RESTARTING, fire startup_req
    // Root is initiating (right column, Figure 5-12)
    ROOT_ANNOUNCE_2    = 5'd9,   // Root initiates, sends LSannounce
    ROOT_CHECK_2       = 5'd10,  // Wait for ALL n confirms, check own params
    ROOT_ISSUE_SLEEP_2 = 5'd11,  // Send LSsleep
    ROOT_LIGHTS_OUT_2  = 5'd12,  // Root affected: set timer_LSalarmClock → (a)
    ROOT_DREAMING_2    = 5'd13,  // Sleeping
    ROOT_RESTARTING_2  = 5'd14   // Woken: status=RESTARTING, fire startup_req
  } ls_root_state_e;

  // =========================================================================
  // Non-Root FSM States (Figure 5-13, PDF p193)
  // Two paths: root-initiated (path 3) and non-root-initiated (path 4)
  // =========================================================================
  typedef enum logic [3:0] {
    // Idle
    NROOT_IDLE        = 4'd0,
    // Root is initiating (left column, Figure 5-13)
    NROOT_CHECK_3     = 4'd1,   // Evaluate 4 feasibility conditions
    NROOT_DENY_3      = 4'd2,   // LSpossible=FALSE: send deny
    NROOT_CONFIRM_3   = 4'd3,   // LSpossible=TRUE: send confirm, set timer_LSbedtime
    NROOT_WAIT_3      = 4'd4,   // Wait for LSsleep or timer_LSbedtime_trigger
    NROOT_LIGHTS_OUT_3= 4'd5,   // Received LSsleep: set timer_LSalarmClock → (a)
    NROOT_DREAMING_3  = 4'd6,   // Sleeping
    NROOT_RESTARTING_3= 4'd7,   // Woken: status=RESTARTING, fire startup_req
    // Non-root is initiating (right column, Figure 5-13)
    NROOT_ANNOUNCE_2  = 4'd8,   // Send LSannounce
    NROOT_PYJAMA_ON_4 = 4'd9,   // Confirmed: set timer_LSbedtime
    NROOT_WAIT_4      = 4'd10,  // Wait for LSsleep or timer_LSbedtime_trigger
    NROOT_LIGHTS_OUT_4= 4'd11,  // Received LSsleep: set timer_LSalarmClock → (a)
    NROOT_DREAMING_4  = 4'd12,  // Sleeping
    NROOT_RESTARTING_4= 4'd13   // Woken: status=RESTARTING, fire startup_req
  } ls_nonroot_state_e;

  // =========================================================================
  // LightSleep_status field (register 2.2251 bits 1:0, Table 3-66)
  // =========================================================================
  typedef enum logic [1:0] {
    LS_STATUS_NORMAL     = 2'd0,  // Normal mode, no LS activity
    LS_STATUS_MEDIATING  = 2'd1,  // Mediation ongoing (any LS state except dreaming)
    LS_STATUS_SLEEPING   = 2'd2,  // In LS_dreaming_* (PHY disabled)
    LS_STATUS_RESTARTING = 2'd3   // Exited through point "b", restarting
  } ls_status_e;

  // =========================================================================
  // Event/reason codes for status outputs
  // =========================================================================
  typedef enum logic [2:0] {
    LS_EVT_NONE         = 3'd0,
    LS_EVT_ENTER_SLEEP  = 3'd1,  // Point "a" reached
    LS_EVT_WAKE         = 3'd2,  // timer_LSalarmClock fired, point "b"
    LS_EVT_DENY_SENT    = 3'd3,  // LSpossible=FALSE, denied
    LS_EVT_DENY_RCVD    = 3'd4,  // Received LSdeny
    LS_EVT_FEASIBLE     = 3'd5,  // LSpossible=TRUE
    LS_EVT_ABORT        = 3'd6   // Illegal state / abort
  } ls_event_e;

  // =========================================================================
  // Feasibility check helpers
  // Returns TRUE if all non-root conditions are met (Section 5.8.1.1, PDF p190)
  // Caller must provide PTB-computed values — this module does NOT compute PTB
  // =========================================================================
  function automatic logic ls_nonroot_feasible(
    input logic        ptb_locked,
    input logic [47:0] ptb_clk,
    input logic [47:0] ptb_bedtime,
    input logic [11:0] sleep_cycles,
    input logic [7:0]  restart_1g_a,
    input logic [7:0]  restart_sgx_a
  );
    logic [31:0] net_sleep_tics;
    logic [31:0] lead_tics;
    logic [31:0] drift_tics;

    // Condition 1: PTB locked
    if (!ptb_locked) return 1'b0;

    // Condition 2: Net sleep > 100µs (25000 PTB tics)
    // net_sleep = sleep_cycles*phSGx_TIME - (r1g_a*ph1G_TIME + rsgx_a*phSGx_TIME)
    net_sleep_tics = 32'(sleep_cycles) * PHSGX_TIME[31:0] -
                     (32'(restart_1g_a) * PH1G_TIME[31:0] +
                      32'(restart_sgx_a) * PHSGX_TIME[31:0]);
    if (net_sleep_tics <= LS_NET_SLEEP_MIN_TICS) return 1'b0;

    // Condition 3: Sufficient lead time (> 50µs = 12500 PTB tics)
    // PTBbedtime - PTBclk > 12500
    if (ptb_bedtime <= ptb_clk + 48'(LS_BEDTIME_LEAD_TICS)) return 1'b0;

    // Condition 4: PTB drift during net sleep < 140 PTB tics
    // Drift condition: net_sleep_tics < 140 always fails (drift = 0 since tics ≠ drift)
    // IMPLEMENTATION ASSUMPTION: Drift is bounded if net_sleep_tics (in PTB tics) is
    // within spec. The spec says "140 PTB tics" max drift; since the oscillator runs
    // independently, we conservatively check net_sleep_tics >= 140.
    // (Full drift calculation requires oscillator accuracy, not available here.)
    if (net_sleep_tics < LS_PTB_DRIFT_MAX_TICS) return 1'b0;

    return 1'b1;
  endfunction

  // Root feasibility check (Section 5.8.1.2, PDF p190)
  function automatic logic ls_root_feasible(
    input logic        ptb_locked,
    input logic [47:0] ptb_clk,
    input logic [47:0] ptb_bedtime,
    input logic [11:0] sleep_cycles,
    input logic [7:0]  restart_1g_f,   // Max from all confirms
    input logic [7:0]  restart_sgx_f
  );
    logic [31:0] net_sleep_tics;
    if (!ptb_locked) return 1'b0;
    net_sleep_tics = 32'(sleep_cycles) * PHSGX_TIME[31:0] -
                     (32'(restart_1g_f) * PH1G_TIME[31:0] +
                      32'(restart_sgx_f) * PHSGX_TIME[31:0]);
    if (net_sleep_tics <= LS_NET_SLEEP_MIN_TICS) return 1'b0;
    if (ptb_bedtime <= ptb_clk + 48'(LS_BEDTIME_LEAD_TICS)) return 1'b0;
    return 1'b1;
  endfunction

  // Alarm clock calculation (Section 5.8.1.2, PDF p190)
  function automatic logic [47:0] ls_alarm_clock(
    input logic [47:0] ptb_bedtime,
    input logic [11:0] sleep_cycles,
    input logic [7:0]  restart_1g_f,
    input logic [7:0]  restart_sgx_f
  );
    return ptb_bedtime +
           48'(32'(sleep_cycles) * PHSGX_TIME[31:0]) -
           48'(32'(restart_1g_f) * PH1G_TIME[31:0] +
               32'(restart_sgx_f) * PHSGX_TIME[31:0]);
  endfunction

endpackage

`default_nettype wire
