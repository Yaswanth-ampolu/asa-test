`timescale 1ns/1ps
`default_nettype none

// ASA Node State Machine
// Spec: Section 2.4 (Figure 2-3), 3.2.6, 3.2.7, 3.2.8, 3.2.12, 3.2.13
//
// Interface model: The PHY generates one pulse on tdd_burst_valid at the end
// of each TDD cycle if a valid burst was received. link_loss_ind pulses once
// per TDD cycle when the burst was entirely lost. These two signals are
// mutually exclusive and exactly one fires per TDD cycle boundary.
//
// This lets the FSM count consecutive lost bursts correctly without
// conflating clock cycles with TDD cycles.

module asa_node_fsm
  import asa_node_pkg::*;
(
  input  logic        clk,
  input  logic        rst,

  // Control inputs
  input  logic        soft_reset,
  input  logic        init_done,

  // PHY startup interface (Section 4.3.3.1)
  input  logic        startup_done,       // transition G/H reached
  input  logic        startup_failed,     // retry exhausted or ERROR
  input  logic        startup_test_mode_req, // transition T
  input  logic        startup_test_complete, // transition R
  input  logic        startup_skip_oam_cfg,  // OAMconfigSkip confirmed

  // OAM interface
  input  logic        start_tdd,          // StartTDD CAD (Section 5.5.3.9)

  // Light Sleep interface (Section 5.8)
  input  logic        light_sleep_enter,  // bedtime reached
  input  logic        light_sleep_wake,   // alarm clock triggered

  // Link quality interface (Section 3.2.13)
  // One pulse per TDD cycle boundary: either burst_valid or link_loss_ind
  input  logic        tdd_boundary,       // marks TDD cycle boundary
  input  logic        link_loss_ind,      // burst lost this TDD cycle

  // Fail recovery
  input  logic        restart_req,
  input  logic        deep_sleep_req,

  // Outputs
  output logic [3:0]  node_state,         // ASAnodeState (1.0006)
  output logic [1:0]  light_sleep_status, // LightSleepStatus1 (2.2251)
  output logic        com_ready,          // COMready - LinkTraining (1.0100) bit 10
  output logic [5:0]  consec_loss_count,  // consecutive lost bursts (internal)
  output logic [5:0]  link_loss_total,    // LinkQuality (1.0101) bits 15:10
  output logic [13:0] irq_flags           // ASAnodeIRQ (1.0008)
);

  // State registers
  asa_node_state_e         state_q, state_d;
  asa_light_sleep_status_e ls_status_q, ls_status_d;
  logic                    ls_restart_pending_q, ls_restart_pending_d;
  logic [5:0]              consec_loss_q, consec_loss_d;
  logic [5:0]              total_loss_q, total_loss_d;
  logic [13:0]             irq_flags_q, irq_flags_d;

  always_comb begin
    state_d              = state_q;
    ls_status_d          = ls_status_q;
    ls_restart_pending_d = ls_restart_pending_q;
    consec_loss_d        = consec_loss_q;
    total_loss_d         = total_loss_q;
    irq_flags_d          = irq_flags_q;

    if (soft_reset) begin
      // SoftReset (1.0007): resets state machines and status, keeps config
      // Spec Section 3.2.7: State -> Startup, status cleared
      state_d              = ASA_STATE_STARTUP;
      ls_status_d          = ASA_LS_STATUS_NORMAL;
      ls_restart_pending_d = 1'b0;
      consec_loss_d        = '0;
      total_loss_d         = '0;
      irq_flags_d          = '0;
    end else begin
      unique case (state_q)

        ASA_STATE_POWER_ON_INIT: begin
          consec_loss_d = '0;
          total_loss_d  = '0;
          ls_status_d   = ASA_LS_STATUS_NORMAL;
          if (init_done) begin
            state_d = ASA_STATE_STARTUP;
          end
        end

        ASA_STATE_STARTUP: begin
          consec_loss_d = '0;
          if (ls_restart_pending_q) begin
            ls_status_d = ASA_LS_STATUS_RESTARTING;
          end else begin
            ls_status_d = ASA_LS_STATUS_NORMAL;
          end

          if (startup_failed) begin
            state_d = ASA_STATE_FAIL;
            irq_flags_d[ASA_IRQ_LOCAL_PHY_BIT] = 1'b1;
            ls_restart_pending_d = 1'b0;
            ls_status_d = ASA_LS_STATUS_NORMAL;
          end else if (startup_test_mode_req) begin
            state_d = ASA_STATE_TEST;
          end else if (startup_done) begin
            ls_restart_pending_d = 1'b0;
            ls_status_d = ASA_LS_STATUS_NORMAL;
            if (startup_skip_oam_cfg) begin
              state_d = ASA_STATE_NORMAL;
            end else begin
              state_d = ASA_STATE_OAM_CONFIG;
            end
          end
        end

        ASA_STATE_OAM_CONFIG: begin
          ls_status_d = ASA_LS_STATUS_NORMAL;
          // Figure 2-3 transition Z: link loss during OAM Config -> Fail
          if (tdd_boundary && link_loss_ind) begin
            consec_loss_d = consec_loss_q + 6'd1;
            if (total_loss_q < ASA_LINK_LOSS_SAT[5:0]) begin
              total_loss_d = total_loss_q + 6'd1;
            end
            if (consec_loss_q + 6'd1 >= ASA_LINK_LOSS_FAIL_THRESHOLD[5:0]) begin
              state_d = ASA_STATE_FAIL;
              irq_flags_d[ASA_IRQ_LOCAL_PHY_BIT] = 1'b1;
            end
          end else if (tdd_boundary && !link_loss_ind) begin
            consec_loss_d = '0;
          end

          if (start_tdd && state_d != ASA_STATE_FAIL) begin
            state_d = ASA_STATE_NORMAL;
            consec_loss_d = '0;
          end
        end

        ASA_STATE_NORMAL: begin
          ls_status_d = ASA_LS_STATUS_NORMAL;

          if (tdd_boundary && link_loss_ind) begin
            consec_loss_d = consec_loss_q + 6'd1;
            // LinkQuality[15:10] cumulative counter, saturates to 0x3F
            if (total_loss_q < ASA_LINK_LOSS_SAT[5:0]) begin
              total_loss_d = total_loss_q + 6'd1;
            end
            // Fail on 3 consecutive (Spec Section 2.4)
            if (consec_loss_q + 6'd1 >= ASA_LINK_LOSS_FAIL_THRESHOLD[5:0]) begin
              state_d = ASA_STATE_FAIL;
              irq_flags_d[ASA_IRQ_LOCAL_PHY_BIT] = 1'b1;
            end
          end else if (tdd_boundary && !link_loss_ind) begin
            consec_loss_d = '0;
          end

          if (light_sleep_enter && state_d != ASA_STATE_FAIL) begin
            state_d = ASA_STATE_LIGHT_SLEEP;
            ls_status_d = ASA_LS_STATUS_SLEEPING;
            consec_loss_d = '0;
          end
        end

        ASA_STATE_TEST: begin
          consec_loss_d = '0;
          ls_status_d   = ASA_LS_STATUS_NORMAL;
          if (startup_test_complete) begin
            state_d = ASA_STATE_STARTUP;
          end
        end

        ASA_STATE_LIGHT_SLEEP: begin
          consec_loss_d = '0;
          ls_status_d   = ASA_LS_STATUS_SLEEPING;
          if (light_sleep_wake) begin
            state_d              = ASA_STATE_STARTUP;
            ls_restart_pending_d = 1'b1;
            ls_status_d          = ASA_LS_STATUS_RESTARTING;
          end
        end

        ASA_STATE_FAIL: begin
          consec_loss_d        = '0;
          ls_status_d          = ASA_LS_STATUS_NORMAL;
          ls_restart_pending_d = 1'b0;
          if (deep_sleep_req) begin
            state_d = ASA_STATE_DEEP_SLEEP;
          end else if (restart_req) begin
            state_d = ASA_STATE_STARTUP;
          end
        end

        ASA_STATE_DEEP_SLEEP: begin
          consec_loss_d        = '0;
          ls_status_d          = ASA_LS_STATUS_NORMAL;
          ls_restart_pending_d = 1'b0;
        end

        default: begin
          state_d              = ASA_STATE_POWER_ON_INIT;
          ls_status_d          = ASA_LS_STATUS_NORMAL;
          ls_restart_pending_d = 1'b0;
          consec_loss_d        = '0;
          total_loss_d         = '0;
        end
      endcase
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q              <= ASA_STATE_POWER_ON_INIT;
      ls_status_q          <= ASA_LS_STATUS_NORMAL;
      ls_restart_pending_q <= 1'b0;
      consec_loss_q        <= '0;
      total_loss_q         <= '0;
      irq_flags_q          <= '0;
    end else begin
      state_q              <= state_d;
      ls_status_q          <= ls_status_d;
      ls_restart_pending_q <= ls_restart_pending_d;
      consec_loss_q        <= consec_loss_d;
      total_loss_q         <= total_loss_d;
      irq_flags_q          <= irq_flags_d;
    end
  end

  // Output assignments
  assign node_state         = state_q;
  assign light_sleep_status = ls_status_q;
  // COMready: "goes high after startup" (Spec 3.2.12)
  assign com_ready          = ((state_q == ASA_STATE_OAM_CONFIG) ||
                               (state_q == ASA_STATE_NORMAL));
  assign consec_loss_count  = consec_loss_q;
  assign link_loss_total    = total_loss_q;
  assign irq_flags          = irq_flags_q;

endmodule

`default_nettype wire
