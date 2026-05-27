`timescale 1ns/1ps
`default_nettype none

// ASA Node State Machine Top
// Spec: micro-architecture-node-state-machine.md Sections 14-15
//
// Wraps the core FSM (asa_node_fsm.sv) with all doc-specified interfaces:
//   14.1 Register Model
//   14.2 OAM Control Plane
//   14.3 PTB Clock Service
//   14.4 PHY/PCS/PMA Startup Engine
//   14.5 DLL Mapper/Demux
//   14.6 Light Sleep Controller
//   14.7 Security
//
// Instantiates asa_node_fsm as the core state machine and adds:
//   - StartTDD capture + PTB-timed mapper_init/start_tdd dispatch
//   - OAM config active flag
//   - PHY enable/disable outputs
//   - PTB timer comparison for LS wake

module asa_node_fsm_top
  import asa_node_pkg::*;
(
  input  logic              clk,
  input  logic              rst,

  // =========================================================================
  // 14.1 Interface to Register Model
  // =========================================================================
  output logic [3:0]        node_state_o,         // -> 1.0006[3:0]
  input  logic              soft_reset_wr_i,      // <- 1.0007 bit 0 write
  input  logic              power_on_init_done_i, // external completion of PowerOn/Init
  output logic [13:0]       irq_flags_o,          // -> 1.0008
  output logic              com_ready_o,          // -> 1.0100 bit 10

  // =========================================================================
  // 14.2 Interface to OAM Control Plane
  // =========================================================================
  input  logic              start_tdd_i,          // StartTDD CAD received
  input  logic [47:0]       start_tdd_ptb_time_i, // PTBtime from StartTDD
  input  logic [15:0]       start_tdd_linemin_i,  // DLLlinemin from StartTDD
  input  logic [15:0]       start_tdd_linemax_i,  // DLLlinemax from StartTDD
  output logic              oam_config_active_o,  // Node is in OAM Config

  // =========================================================================
  // 14.3 Interface to PTB Clock Service
  // =========================================================================
  input  logic [47:0]       ptb_time_i,            // Current PTB time

  // =========================================================================
  // 14.4 Interface to PHY/PCS/PMA Startup Engine
  // =========================================================================
  input  logic              phy_startup_complete_i, // Transition G/H
  input  logic              phy_startup_fail_i,     // Retry limit or ERROR
  input  logic              phy_test_mode_req_i,    // Test mode (T)
  input  logic              phy_test_complete_i,    // Test done (R)
  output logic              phy_disable_o,          // Disable TX/RX
  output logic              phy_enable_o,           // Re-enable TX/RX
  input  logic              oam_config_skip_i,      // OAMconfigSkip confirmed

  // =========================================================================
  // 14.5 Interface to DLL Mapper/Demux
  // =========================================================================
  output logic              mapper_init_o,          // Trigger mapper init
  output logic [15:0]       mapper_linemin_o,       // DLLlinemin
  output logic [15:0]       mapper_linemax_o,       // DLLlinemax
  output logic [47:0]       mapper_ptb_start_o,     // PTB time for mapper

  // =========================================================================
  // 14.6 Interface to Light Sleep Controller
  // =========================================================================
  input  logic              ls_enter_i,             // Bedtime reached
  input  logic              ls_wake_i,              // Alarm triggered

  // =========================================================================
  // TDD boundary interface (from PHY for link loss counting)
  // =========================================================================
  input  logic              tdd_boundary_i,
  input  logic              link_loss_ind_i,

  // =========================================================================
  // Status outputs
  // =========================================================================
  output logic [5:0]        consec_loss_count_o,
  output logic [5:0]        link_loss_total_o,
  output logic [1:0]        light_sleep_status_o,

  // =========================================================================
  // Recovery control
  // =========================================================================
  input  logic              restart_req_i,
  input  logic              deep_sleep_req_i
);

  // =========================================================================
  // Internal signals from/to core FSM
  // =========================================================================
  logic        soft_reset_pulse;
  logic [3:0]  core_node_state;
  logic [1:0]  core_ls_status;
  logic        core_com_ready;
  logic [5:0]  core_consec_loss;
  logic [5:0]  core_link_loss_total;
  logic [13:0] core_irq_flags;
  logic        start_tdd_dispatch;

  // =========================================================================
  // SoftReset handling (write-one-trigger, self-clearing)
  // =========================================================================
  logic soft_reset_q;
  always_ff @(posedge clk or posedge rst) begin
    if (rst)
      soft_reset_q <= 1'b0;
    else if (soft_reset_wr_i)
      soft_reset_q <= 1'b1;
    else
      soft_reset_q <= 1'b0;
  end
  assign soft_reset_pulse = soft_reset_q;

  // =========================================================================
  // Core FSM instance (existing verified module)
  // =========================================================================
  asa_node_fsm u_core_fsm (
    .clk                    (clk),
    .rst                    (rst),
    .soft_reset             (soft_reset_pulse),
    .init_done              (power_on_init_done_i),
    .startup_done           (phy_startup_complete_i),
    .startup_failed         (phy_startup_fail_i),
    .startup_test_mode_req  (phy_test_mode_req_i),
    .startup_test_complete  (phy_test_complete_i),
    .startup_skip_oam_cfg   (oam_config_skip_i),
    .start_tdd              (start_tdd_dispatch),
    .light_sleep_enter      (ls_enter_i),
    .light_sleep_wake       (ls_wake_i),
    .tdd_boundary           (tdd_boundary_i),
    .link_loss_ind          (link_loss_ind_i),
    .restart_req            (restart_req_i),
    .deep_sleep_req         (deep_sleep_req_i),
    .node_state             (core_node_state),
    .light_sleep_status     (core_ls_status),
    .com_ready              (core_com_ready),
    .consec_loss_count      (core_consec_loss),
    .link_loss_total        (core_link_loss_total),
    .irq_flags              (core_irq_flags)
  );

  // =========================================================================
  // Output assignments (14.1 Register Model)
  // =========================================================================
  assign node_state_o         = core_node_state;
  assign irq_flags_o          = core_irq_flags;
  assign com_ready_o          = core_com_ready;
  assign consec_loss_count_o  = core_consec_loss;
  assign link_loss_total_o    = core_link_loss_total;
  assign light_sleep_status_o = core_ls_status;

  // =========================================================================
  // 14.2 OAM Config Active
  // =========================================================================
  assign oam_config_active_o = (core_node_state == ASA_STATE_OAM_CONFIG);

  // =========================================================================
  // 14.4 PHY Enable/Disable
  // PHY disabled in Light Sleep and Deep Sleep
  // PHY enabled on transition out of those states
  // =========================================================================
  logic prev_in_sleep_q;
  logic in_sleep;
  assign in_sleep = (core_node_state == ASA_STATE_LIGHT_SLEEP) ||
                    (core_node_state == ASA_STATE_DEEP_SLEEP);

  always_ff @(posedge clk or posedge rst) begin
    if (rst)
      prev_in_sleep_q <= 1'b0;
    else
      prev_in_sleep_q <= in_sleep;
  end

  assign phy_disable_o = in_sleep && !prev_in_sleep_q;  // entering sleep
  assign phy_enable_o  = !in_sleep && prev_in_sleep_q;  // leaving sleep

  // =========================================================================
  // 14.5 DLL Mapper/Demux
  // StartTDD stores the requested PTB start time and mapper pointers.
  // The actual transition to Normal Mode and mapper init happen when the
  // current PTB time reaches the requested PTBtime from the command.
  // =========================================================================
  logic [47:0] mapper_ptb_q;
  logic [15:0] mapper_lmin_q, mapper_lmax_q;
  logic        start_tdd_pending_q;
  logic        start_tdd_release;
  logic        mapper_init_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      mapper_ptb_q  <= 48'd0;
      mapper_lmin_q <= 16'd0;
      mapper_lmax_q <= 16'd0;
      start_tdd_pending_q <= 1'b0;
      mapper_init_q <= 1'b0;
    end else if (soft_reset_pulse) begin
      start_tdd_pending_q <= 1'b0;
      mapper_init_q <= 1'b0;
    end else begin
      mapper_init_q <= start_tdd_release;
      if (start_tdd_i) begin
        mapper_ptb_q  <= start_tdd_ptb_time_i;
        mapper_lmin_q <= start_tdd_linemin_i;
        mapper_lmax_q <= start_tdd_linemax_i;
        start_tdd_pending_q <= 1'b1;
      end else if (start_tdd_release) begin
        start_tdd_pending_q <= 1'b0;
      end
    end
  end

  assign start_tdd_release  = start_tdd_pending_q &&
                              (core_node_state == ASA_STATE_OAM_CONFIG) &&
                              (ptb_time_i >= mapper_ptb_q);
  assign start_tdd_dispatch = start_tdd_release;
  assign mapper_init_o      = mapper_init_q;
  assign mapper_linemin_o   = mapper_lmin_q;
  assign mapper_linemax_o   = mapper_lmax_q;
  assign mapper_ptb_start_o = mapper_ptb_q;

endmodule

`default_nettype wire
