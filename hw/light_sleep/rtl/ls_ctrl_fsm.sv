`timescale 1ns/1ps
`default_nettype none

// Light Sleep Control FSM
// Spec: Section 5.8 (PDF pp189-193), Figures 5-12/5-13
//
// Fixes applied after review:
//   1. Root response counting: ROOT_MEDIATE_1 now issues announce and enters
//      ROOT_ANNOUNCE_1 to wait for all n_nodes_i confirm/deny responses before
//      evaluating LSpossible (Figure 5-12: "n" annotation on response arrows).
//   2. RESTARTING status: after dreaming → alarmclock fires → ROOT_RESTARTING_* /
//      NROOT_RESTARTING_* for one cycle with ls_status=RESTARTING and startup_req
//      pulsed. Then returns to IDLE. Matches LightSleepStatus1[1:0]=3 definition.
//   3. NROOT_DREAMING_3/4 direct-from-bedtime path retains no alarmclock; still
//      enters RESTARTING when external alarmclock fires (or immediately if no alarm).
//
// n_nodes_i: number of non-root nodes to wait for on the root side.
// IMPLEMENTATION ASSUMPTION: n_nodes_i=1 means one non-root must respond before
// root proceeds. Spec says "n nodes" without defining how n is determined at runtime;
// using a runtime input allows test flexibility.

module ls_ctrl_fsm
  import asa_ls_pkg::*;
(
  input  logic              clk,
  input  logic              rst,
  input  logic              soft_reset_i,

  input  logic              is_root_i,
  input  logic              ls_capable_i,
  input  logic              normal_mode_i,

  // Number of non-root nodes to wait for before proceeding
  // (Spec: root waits for "n" responses; set to actual topology count)
  input  logic [4:0]        n_nodes_i,

  input  logic              ptb_locked_i,
  input  logic [47:0]       ptb_clk_i,
  input  logic              ptb_bedtime_trigger_i,
  input  logic              ptb_alarmclock_trigger_i,
  output logic [47:0]       ptb_bedtime_o,
  output logic              ptb_bedtime_set_o,
  output logic [47:0]       ptb_alarmclock_o,
  output logic              ptb_alarmclock_set_o,

  input  logic              ls_announce_valid_i,
  input  logic [47:0]       ls_announce_bedtime_i,
  input  logic [11:0]       ls_announce_sleep_cycles_i,
  input  logic [7:0]        ls_announce_r1g_i,
  input  logic [7:0]        ls_announce_rsgx_i,

  input  logic              ls_confirm_valid_i,
  input  logic [7:0]        ls_confirm_r1g_a_i,
  input  logic [7:0]        ls_confirm_rsgx_a_i,

  input  logic              ls_deny_valid_i,

  input  logic              ls_sleep_valid_i,
  input  logic [47:0]       ls_sleep_alarmclock_i,
  input  logic [7:0]        ls_sleep_r1g_f_i,
  input  logic [7:0]        ls_sleep_rsgx_f_i,

  input  logic              app_ls_trigger_i,
  input  logic [47:0]       app_ptb_bedtime_i,
  input  logic [11:0]       app_sleep_cycles_i,
  input  logic [7:0]        app_r1g_i,
  input  logic [7:0]        app_rsgx_i,

  output logic              send_announce_o,
  output logic [47:0]       send_announce_bedtime_o,
  output logic [11:0]       send_announce_sleep_cycles_o,
  output logic [7:0]        send_announce_r1g_o,
  output logic [7:0]        send_announce_rsgx_o,

  output logic              send_confirm_o,
  output logic [7:0]        send_confirm_r1g_a_o,
  output logic [7:0]        send_confirm_rsgx_a_o,

  output logic              send_deny_o,

  output logic              send_sleep_o,
  output logic [47:0]       send_sleep_alarmclock_o,
  output logic [7:0]        send_sleep_r1g_f_o,
  output logic [7:0]        send_sleep_rsgx_f_o,

  output logic              pma_disable_o,
  output logic              mapper_halt_o,
  output logic              startup_req_o,
  output logic              ls_enter_o,
  output ls_status_e        ls_status_o,

  output logic              cnt_announced_o,
  output logic              cnt_denied_o,
  output logic              cnt_impossible_o,
  output logic [4:0]        cnt_impossible_node_o,
  output logic              cnt_executed_o,
  output logic              cnt_fail_o,

  output ls_event_e         event_o
);

  ls_root_state_e    root_q;
  ls_nonroot_state_e nroot_q;
  logic [47:0] bedtime_q, alarmclock_q;
  logic [11:0] sleep_cycles_q;
  logic [7:0]  r1g_q, rsgx_q;
  logic [7:0]  r1g_f_q, rsgx_f_q;

  // Response counter: how many confirms/denies collected so far
  // SPEC FACT (Section 5.8.1.2): root collects confirms from ALL affected nodes
  // (n >= 1 is required; n=0 is architecturally invalid per spec — no nodes to sleep with).
  // If n_nodes_i == 0 the FSM immediately aborts to IDLE rather than deadlocking.
  logic [4:0] resp_cnt_q;
  // n_valid: guard against n=0 misconfiguration
  logic n_valid;
  assign n_valid = (n_nodes_i >= 5'd1);

  // =========================================================================
  // Feasibility (combinational)
  // =========================================================================
  logic ls_possible;
  always_comb begin
    if (is_root_i)
      ls_possible = ls_root_feasible(ptb_locked_i, ptb_clk_i, bedtime_q,
                                      sleep_cycles_q, r1g_f_q, rsgx_f_q);
    else
      ls_possible = ls_nonroot_feasible(ptb_locked_i, ptb_clk_i, bedtime_q,
                                         sleep_cycles_q, r1g_q, rsgx_q);
  end

  // =========================================================================
  // Single combined always_ff
  // =========================================================================
  always_ff @(posedge clk or posedge rst) begin
    if (rst || soft_reset_i) begin
      root_q         <= ROOT_IDLE;
      nroot_q        <= NROOT_IDLE;
      bedtime_q      <= 48'd0;
      sleep_cycles_q <= 12'd0;
      r1g_q          <= 8'd0;
      rsgx_q         <= 8'd0;
      r1g_f_q        <= 8'd0;
      rsgx_f_q       <= 8'd0;
      alarmclock_q   <= 48'd0;
      resp_cnt_q     <= 5'd0;
    end else if (is_root_i) begin
      // =====================================================================
      // ROOT FSM (Figure 5-12)
      // =====================================================================
      case (root_q)
        ROOT_IDLE: begin
          if (ls_announce_valid_i && ls_capable_i && normal_mode_i && n_valid) begin
            // Non-root initiating: root mediates
            root_q         <= ROOT_MEDIATE_1;
            bedtime_q      <= ls_announce_bedtime_i;
            sleep_cycles_q <= ls_announce_sleep_cycles_i;
            r1g_q          <= ls_announce_r1g_i;
            rsgx_q         <= ls_announce_rsgx_i;
            r1g_f_q        <= ls_announce_r1g_i;
            rsgx_f_q       <= ls_announce_rsgx_i;
            resp_cnt_q     <= 5'd0;
          end else if (app_ls_trigger_i && ls_capable_i && normal_mode_i && n_valid) begin
            // Root initiating — n=0 would deadlock; abort immediately per spec intent
            root_q         <= ROOT_ANNOUNCE_2;
            bedtime_q      <= app_ptb_bedtime_i;
            sleep_cycles_q <= app_sleep_cycles_i;
            r1g_q          <= app_r1g_i;
            rsgx_q         <= app_rsgx_i;
            r1g_f_q        <= app_r1g_i;
            rsgx_f_q       <= app_rsgx_i;
            resp_cnt_q     <= 5'd0;
          end
        end

        ROOT_MEDIATE_1: begin
          // Issue LSannounce to n others; enter wait state for responses
          // (Figure 5-12: "n" annotation — must wait for all n non-root responses)
          root_q <= ROOT_ANNOUNCE_1;
        end

        ROOT_ANNOUNCE_1: begin
          // Wait for ALL n confirms/denies (PDF: "n" responses before deciding)
          // Guard: if n_nodes_i becomes 0 (illegal reconfiguration), abort.
          if (!n_valid) begin
            root_q <= ROOT_IDLE;
          end else if (ls_deny_valid_i) begin
            root_q <= ROOT_DENY_1;
          end else if (ls_confirm_valid_i) begin
            if (ls_confirm_r1g_a_i > r1g_f_q) r1g_f_q <= ls_confirm_r1g_a_i;
            if (ls_confirm_rsgx_a_i > rsgx_f_q) rsgx_f_q <= ls_confirm_rsgx_a_i;
            resp_cnt_q <= resp_cnt_q + 5'd1;
            if ((resp_cnt_q + 5'd1) >= n_nodes_i) begin
              if (ls_possible) root_q <= ROOT_CONFIRM_1;
              else             root_q <= ROOT_DENY_1;
            end
          end
        end

        ROOT_DENY_1: root_q <= ROOT_IDLE;

        ROOT_CONFIRM_1: begin
          root_q       <= ROOT_ISSUE_SLEEP_1;
          alarmclock_q <= ls_alarm_clock(bedtime_q, sleep_cycles_q, r1g_f_q, rsgx_f_q);
        end

        ROOT_ISSUE_SLEEP_1: root_q <= ROOT_LIGHTS_OUT_1;

        ROOT_LIGHTS_OUT_1: root_q <= ROOT_DREAMING_1;

        ROOT_DREAMING_1: begin
          if (ptb_alarmclock_trigger_i) root_q <= ROOT_RESTARTING_1;
        end

        ROOT_RESTARTING_1: begin
          // One-cycle RESTARTING state: startup_req pulses, status=RESTARTING
          // Then return to IDLE; startup FSM takes over
          root_q <= ROOT_IDLE;
        end

        // --- Root-initiating path ---
        ROOT_ANNOUNCE_2: begin
          // Wait for ALL n confirms/denies from non-roots.
          // Guard against n=0 misconfiguration during wait.
          if (!n_valid) begin
            root_q <= ROOT_IDLE;
          end else if (ls_deny_valid_i) begin
            root_q <= ROOT_IDLE;
          end else if (ls_confirm_valid_i) begin
            if (ls_confirm_r1g_a_i > r1g_f_q) r1g_f_q <= ls_confirm_r1g_a_i;
            if (ls_confirm_rsgx_a_i > rsgx_f_q) rsgx_f_q <= ls_confirm_rsgx_a_i;
            resp_cnt_q <= resp_cnt_q + 5'd1;
            if ((resp_cnt_q + 5'd1) >= n_nodes_i) begin
              root_q <= ROOT_CHECK_2;
            end
          end
        end

        ROOT_CHECK_2: begin
          if (ls_possible) root_q <= ROOT_ISSUE_SLEEP_2;
          else             root_q <= ROOT_IDLE;
        end

        ROOT_ISSUE_SLEEP_2: begin
          root_q       <= ROOT_LIGHTS_OUT_2;
          alarmclock_q <= ls_alarm_clock(bedtime_q, sleep_cycles_q, r1g_f_q, rsgx_f_q);
        end

        ROOT_LIGHTS_OUT_2: root_q <= ROOT_DREAMING_2;

        ROOT_DREAMING_2: begin
          if (ptb_alarmclock_trigger_i) root_q <= ROOT_RESTARTING_2;
        end

        ROOT_RESTARTING_2: root_q <= ROOT_IDLE;

        default: root_q <= ROOT_IDLE;
      endcase

    end else begin
      // =====================================================================
      // NON-ROOT FSM (Figure 5-13)
      // =====================================================================
      case (nroot_q)
        NROOT_IDLE: begin
          if (ls_announce_valid_i && ls_capable_i && normal_mode_i) begin
            nroot_q        <= NROOT_CHECK_3;
            bedtime_q      <= ls_announce_bedtime_i;
            sleep_cycles_q <= ls_announce_sleep_cycles_i;
            r1g_q          <= ls_announce_r1g_i;
            rsgx_q         <= ls_announce_rsgx_i;
          end else if (app_ls_trigger_i && ls_capable_i && normal_mode_i) begin
            nroot_q        <= NROOT_ANNOUNCE_2;
            bedtime_q      <= app_ptb_bedtime_i;
            sleep_cycles_q <= app_sleep_cycles_i;
            r1g_q          <= app_r1g_i;
            rsgx_q         <= app_rsgx_i;
          end
        end

        NROOT_CHECK_3: begin
          if (ls_possible) nroot_q <= NROOT_CONFIRM_3;
          else             nroot_q <= NROOT_DENY_3;
        end

        NROOT_DENY_3: nroot_q <= NROOT_IDLE;

        NROOT_CONFIRM_3: nroot_q <= NROOT_WAIT_3;

        NROOT_WAIT_3: begin
          if (ls_sleep_valid_i) begin
            nroot_q      <= NROOT_LIGHTS_OUT_3;
            alarmclock_q <= ls_sleep_alarmclock_i;
            r1g_f_q      <= ls_sleep_r1g_f_i;
            rsgx_f_q     <= ls_sleep_rsgx_f_i;
          end else if (ptb_bedtime_trigger_i) begin
            // Figure 5-13: bedtime fires before LSsleep → direct to (a)
            nroot_q <= NROOT_DREAMING_3;
          end
        end

        NROOT_LIGHTS_OUT_3: nroot_q <= NROOT_DREAMING_3;

        NROOT_DREAMING_3: begin
          if (ptb_alarmclock_trigger_i) nroot_q <= NROOT_RESTARTING_3;
        end

        NROOT_RESTARTING_3: nroot_q <= NROOT_IDLE;

        // Non-root initiating path
        NROOT_ANNOUNCE_2: begin
          if (ls_confirm_valid_i) nroot_q <= NROOT_PYJAMA_ON_4;
          else if (ls_deny_valid_i) nroot_q <= NROOT_IDLE;
        end

        NROOT_PYJAMA_ON_4: nroot_q <= NROOT_WAIT_4;

        NROOT_WAIT_4: begin
          if (ls_sleep_valid_i) begin
            nroot_q      <= NROOT_LIGHTS_OUT_4;
            alarmclock_q <= ls_sleep_alarmclock_i;
            r1g_f_q      <= ls_sleep_r1g_f_i;
            rsgx_f_q     <= ls_sleep_rsgx_f_i;
          end else if (ptb_bedtime_trigger_i) begin
            nroot_q <= NROOT_DREAMING_4;
          end
        end

        NROOT_LIGHTS_OUT_4: nroot_q <= NROOT_DREAMING_4;

        NROOT_DREAMING_4: begin
          if (ptb_alarmclock_trigger_i) nroot_q <= NROOT_RESTARTING_4;
        end

        NROOT_RESTARTING_4: nroot_q <= NROOT_IDLE;

        default: nroot_q <= NROOT_IDLE;
      endcase
    end
  end

  // =========================================================================
  // Combinational outputs
  // =========================================================================
  logic in_dreaming, in_lights_out, in_mediation, in_restarting;
  always_comb begin
    in_dreaming = is_root_i ?
      (root_q == ROOT_DREAMING_1 || root_q == ROOT_DREAMING_2) :
      (nroot_q == NROOT_DREAMING_3 || nroot_q == NROOT_DREAMING_4);

    in_lights_out = is_root_i ?
      (root_q == ROOT_LIGHTS_OUT_1 || root_q == ROOT_LIGHTS_OUT_2) :
      (nroot_q == NROOT_LIGHTS_OUT_3 || nroot_q == NROOT_LIGHTS_OUT_4);

    in_restarting = is_root_i ?
      (root_q == ROOT_RESTARTING_1 || root_q == ROOT_RESTARTING_2) :
      (nroot_q == NROOT_RESTARTING_3 || nroot_q == NROOT_RESTARTING_4);

    in_mediation = is_root_i ?
      (root_q != ROOT_IDLE && !in_dreaming && !in_restarting) :
      (nroot_q != NROOT_IDLE && !in_dreaming && !in_restarting);
  end

  always_comb begin
    if      (in_restarting) ls_status_o = LS_STATUS_RESTARTING;
    else if (in_dreaming)   ls_status_o = LS_STATUS_SLEEPING;
    else if (in_mediation)  ls_status_o = LS_STATUS_MEDIATING;
    else                    ls_status_o = LS_STATUS_NORMAL;
  end

  assign pma_disable_o  = in_dreaming;
  assign mapper_halt_o  = in_dreaming || in_lights_out;
  assign ls_enter_o     = in_lights_out;
  // startup_req: pulse in RESTARTING state (one cycle), not on every alarm trigger
  assign startup_req_o  = in_restarting;

  assign ptb_bedtime_o    = bedtime_q;
  assign ptb_alarmclock_o = alarmclock_q;

  assign ptb_bedtime_set_o = is_root_i ?
    (root_q == ROOT_CONFIRM_1 || root_q == ROOT_ANNOUNCE_2) :
    (nroot_q == NROOT_CONFIRM_3 || nroot_q == NROOT_PYJAMA_ON_4);

  assign ptb_alarmclock_set_o = in_lights_out;

  // OAM sends
  always_comb begin
    send_announce_o              = 1'b0;
    send_announce_bedtime_o      = bedtime_q;
    send_announce_sleep_cycles_o = sleep_cycles_q;
    send_announce_r1g_o          = r1g_q;
    send_announce_rsgx_o         = rsgx_q;
    send_confirm_o               = 1'b0;
    send_confirm_r1g_a_o         = r1g_q;
    send_confirm_rsgx_a_o        = rsgx_q;
    send_deny_o                  = 1'b0;
    send_sleep_o                 = 1'b0;
    send_sleep_alarmclock_o      = alarmclock_q;
    send_sleep_r1g_f_o           = r1g_f_q;
    send_sleep_rsgx_f_o          = rsgx_f_q;

    if (is_root_i) begin
      send_announce_o = (root_q == ROOT_MEDIATE_1 || root_q == ROOT_ANNOUNCE_2);
      send_deny_o     = (root_q == ROOT_DENY_1);
      send_confirm_o  = (root_q == ROOT_CONFIRM_1);
      send_sleep_o    = (root_q == ROOT_ISSUE_SLEEP_1 || root_q == ROOT_ISSUE_SLEEP_2);
    end else begin
      send_announce_o = (nroot_q == NROOT_ANNOUNCE_2);
      send_deny_o     = (nroot_q == NROOT_DENY_3);
      send_confirm_o  = (nroot_q == NROOT_CONFIRM_3);
    end
  end

  assign cnt_announced_o      = ls_announce_valid_i && normal_mode_i;
  assign cnt_denied_o         = ls_deny_valid_i;
  assign cnt_impossible_o     = is_root_i ?
    ((root_q == ROOT_ANNOUNCE_1 || root_q == ROOT_CHECK_2) && !ls_possible) :
    (nroot_q == NROOT_CHECK_3 && !ls_possible);
  assign cnt_impossible_node_o = 5'd0;
  assign cnt_executed_o       = in_restarting;  // LS cycle completed = entering restart
  assign cnt_fail_o           = 1'b0;

  always_comb begin
    if (in_restarting)          event_o = LS_EVT_WAKE;
    else if (ls_enter_o)        event_o = LS_EVT_ENTER_SLEEP;
    else if (send_deny_o)       event_o = LS_EVT_DENY_SENT;
    else if (cnt_denied_o)      event_o = LS_EVT_DENY_RCVD;
    else if (cnt_impossible_o)  event_o = LS_EVT_DENY_SENT;
    else                        event_o = LS_EVT_NONE;
  end

endmodule

`default_nettype wire
