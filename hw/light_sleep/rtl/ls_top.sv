`timescale 1ns/1ps
`default_nettype none

// Light Sleep Controller Top
// Spec: Section 5.8, PDF pp189-193
//
// Connects ls_ctrl_fsm, ls_oam_bridge, and ls_ptb_if.
// Exposes the register-visible status/capability outputs.

module ls_top
  import asa_ls_pkg::*;
(
  input  logic              clk,
  input  logic              rst,
  input  logic              soft_reset_i,

  // Node configuration
  input  logic              is_root_i,
  input  logic              ls_capable_i,    // Register 2.2250 bit 0
  input  logic              normal_mode_i,
  // Number of non-root nodes to wait for on root side (topology count)
  input  logic [4:0]        n_nodes_i,

  // PTB service interface (timing is owned by PTB service)
  input  logic              ptb_locked_i,
  input  logic [47:0]       ptb_clk_i,
  input  logic              ptb_bedtime_trigger_i,
  input  logic              ptb_alarmclock_trigger_i,
  output logic              ptb_bedtime_en_o,
  output logic [47:0]       ptb_bedtime_val_o,
  output logic              ptb_alarm_en_o,
  output logic [47:0]       ptb_alarm_val_o,

  // OAM LS CAD events (from oam_top ls_bridge outputs)
  input  logic              oam_announce_valid_i,
  input  logic [47:0]       oam_announce_bedtime_i,
  input  logic [11:0]       oam_announce_sleep_cycles_i,
  input  logic [7:0]        oam_announce_r1g_i,
  input  logic [7:0]        oam_announce_rsgx_i,
  input  logic              oam_confirm_valid_i,
  input  logic [7:0]        oam_confirm_r1g_a_i,
  input  logic [7:0]        oam_confirm_rsgx_a_i,
  input  logic              oam_deny_valid_i,
  input  logic              oam_sleep_valid_i,
  input  logic [47:0]       oam_sleep_alarmclock_i,
  input  logic [7:0]        oam_sleep_r1g_f_i,
  input  logic [7:0]        oam_sleep_rsgx_f_i,

  // OAM send commands (to oam_top ls_bridge inputs)
  output logic              oam_send_announce_o,
  output logic [47:0]       oam_send_announce_bedtime_o,
  output logic [11:0]       oam_send_announce_sleep_cycles_o,
  output logic [7:0]        oam_send_announce_r1g_o,
  output logic [7:0]        oam_send_announce_rsgx_o,
  output logic              oam_send_confirm_o,
  output logic [7:0]        oam_send_confirm_r1g_a_o,
  output logic [7:0]        oam_send_confirm_rsgx_a_o,
  output logic              oam_send_deny_o,
  output logic              oam_send_sleep_o,
  output logic [47:0]       oam_send_sleep_alarmclock_o,
  output logic [7:0]        oam_send_sleep_r1g_f_o,
  output logic [7:0]        oam_send_sleep_rsgx_f_o,

  // Application trigger
  input  logic              app_ls_trigger_i,
  input  logic [47:0]       app_ptb_bedtime_i,
  input  logic [11:0]       app_sleep_cycles_i,
  input  logic [7:0]        app_r1g_i,
  input  logic [7:0]        app_rsgx_i,

  // Node/system control outputs
  output logic              pma_disable_o,
  output logic              mapper_halt_o,
  output logic              startup_req_o,
  output logic              ls_enter_o,
  output ls_status_e        ls_status_o,

  // Register status counter pulses
  output logic              cnt_announced_o,
  output logic              cnt_denied_o,
  output logic              cnt_impossible_o,
  output logic [4:0]        cnt_impossible_node_o,
  output logic              cnt_executed_o,
  output logic              cnt_fail_o,

  // Debug
  output ls_event_e         event_o
);

  // Internal wires
  logic [47:0] fsm_bedtime, fsm_alarmclock;
  logic        fsm_bedtime_set, fsm_alarmclock_set;
  logic        ptb_bed_trig, ptb_alarm_trig;

  logic        fsm_announce, fsm_confirm, fsm_deny, fsm_sleep;
  logic [47:0] fsm_ann_bedtime, fsm_sleep_alarmclock;
  logic [11:0] fsm_ann_sleep_cycles;
  logic [7:0]  fsm_ann_r1g, fsm_ann_rsgx;
  logic [7:0]  fsm_conf_r1g, fsm_conf_rsgx;
  logic [7:0]  fsm_sleep_r1g, fsm_sleep_rsgx;

  logic        bridge_ann_v; logic [47:0] bridge_ann_bt; logic [11:0] bridge_ann_sc;
  logic [7:0]  bridge_ann_r1g, bridge_ann_rsgx;
  logic        bridge_conf_v; logic [7:0] bridge_conf_r1g, bridge_conf_rsgx;
  logic        bridge_deny_v;
  logic        bridge_sleep_v; logic [47:0] bridge_sleep_ac;
  logic [7:0]  bridge_sleep_r1g, bridge_sleep_rsgx;

  // PTB interface
  ls_ptb_if u_ptb_if (
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i),
    .set_bedtime_i(fsm_bedtime_set),
    .bedtime_value_i(fsm_bedtime),
    .set_alarmclock_i(fsm_alarmclock_set),
    .alarmclock_value_i(fsm_alarmclock),
    .ptb_bedtime_en_o(ptb_bedtime_en_o),
    .ptb_bedtime_val_o(ptb_bedtime_val_o),
    .ptb_alarm_en_o(ptb_alarm_en_o),
    .ptb_alarm_val_o(ptb_alarm_val_o),
    .ptb_bedtime_trigger_i(ptb_bedtime_trigger_i),
    .ptb_alarm_trigger_i(ptb_alarmclock_trigger_i),
    .ls_bedtime_trigger_o(ptb_bed_trig),
    .ls_alarmclock_trigger_o(ptb_alarm_trig)
  );

  // OAM bridge
  ls_oam_bridge u_oam_bridge (
    .clk(clk), .rst(rst),
    .oam_announce_valid_i(oam_announce_valid_i),
    .oam_announce_bedtime_i(oam_announce_bedtime_i),
    .oam_announce_sleep_cycles_i(oam_announce_sleep_cycles_i),
    .oam_announce_r1g_i(oam_announce_r1g_i),
    .oam_announce_rsgx_i(oam_announce_rsgx_i),
    .oam_confirm_valid_i(oam_confirm_valid_i),
    .oam_confirm_r1g_a_i(oam_confirm_r1g_a_i),
    .oam_confirm_rsgx_a_i(oam_confirm_rsgx_a_i),
    .oam_deny_valid_i(oam_deny_valid_i),
    .oam_sleep_valid_i(oam_sleep_valid_i),
    .oam_sleep_alarmclock_i(oam_sleep_alarmclock_i),
    .oam_sleep_r1g_f_i(oam_sleep_r1g_f_i),
    .oam_sleep_rsgx_f_i(oam_sleep_rsgx_f_i),
    .ls_announce_valid_o(bridge_ann_v),
    .ls_announce_bedtime_o(bridge_ann_bt),
    .ls_announce_sleep_cycles_o(bridge_ann_sc),
    .ls_announce_r1g_o(bridge_ann_r1g),
    .ls_announce_rsgx_o(bridge_ann_rsgx),
    .ls_confirm_valid_o(bridge_conf_v),
    .ls_confirm_r1g_a_o(bridge_conf_r1g),
    .ls_confirm_rsgx_a_o(bridge_conf_rsgx),
    .ls_deny_valid_o(bridge_deny_v),
    .ls_sleep_valid_o(bridge_sleep_v),
    .ls_sleep_alarmclock_o(bridge_sleep_ac),
    .ls_sleep_r1g_f_o(bridge_sleep_r1g),
    .ls_sleep_rsgx_f_o(bridge_sleep_rsgx),
    .ls_send_announce_i(fsm_announce),
    .ls_send_announce_bedtime_i(fsm_ann_bedtime),
    .ls_send_announce_sleep_cycles_i(fsm_ann_sleep_cycles),
    .ls_send_announce_r1g_i(fsm_ann_r1g),
    .ls_send_announce_rsgx_i(fsm_ann_rsgx),
    .ls_send_confirm_i(fsm_confirm),
    .ls_send_confirm_r1g_a_i(fsm_conf_r1g),
    .ls_send_confirm_rsgx_a_i(fsm_conf_rsgx),
    .ls_send_deny_i(fsm_deny),
    .ls_send_sleep_i(fsm_sleep),
    .ls_send_sleep_alarmclock_i(fsm_sleep_alarmclock),
    .ls_send_sleep_r1g_f_i(fsm_sleep_r1g),
    .ls_send_sleep_rsgx_f_i(fsm_sleep_rsgx),
    .oam_send_announce_o(oam_send_announce_o),
    .oam_send_announce_bedtime_o(oam_send_announce_bedtime_o),
    .oam_send_announce_sleep_cycles_o(oam_send_announce_sleep_cycles_o),
    .oam_send_announce_r1g_o(oam_send_announce_r1g_o),
    .oam_send_announce_rsgx_o(oam_send_announce_rsgx_o),
    .oam_send_confirm_o(oam_send_confirm_o),
    .oam_send_confirm_r1g_a_o(oam_send_confirm_r1g_a_o),
    .oam_send_confirm_rsgx_a_o(oam_send_confirm_rsgx_a_o),
    .oam_send_deny_o(oam_send_deny_o),
    .oam_send_sleep_o(oam_send_sleep_o),
    .oam_send_sleep_alarmclock_o(oam_send_sleep_alarmclock_o),
    .oam_send_sleep_r1g_f_o(oam_send_sleep_r1g_f_o),
    .oam_send_sleep_rsgx_f_o(oam_send_sleep_rsgx_f_o)
  );

  // Core FSM
  ls_ctrl_fsm u_fsm (
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i),
    .is_root_i(is_root_i), .ls_capable_i(ls_capable_i),
    .normal_mode_i(normal_mode_i),
    .n_nodes_i(n_nodes_i),
    .ptb_locked_i(ptb_locked_i),
    .ptb_clk_i(ptb_clk_i),
    .ptb_bedtime_trigger_i(ptb_bed_trig),
    .ptb_alarmclock_trigger_i(ptb_alarm_trig),
    .ptb_bedtime_o(fsm_bedtime),
    .ptb_bedtime_set_o(fsm_bedtime_set),
    .ptb_alarmclock_o(fsm_alarmclock),
    .ptb_alarmclock_set_o(fsm_alarmclock_set),
    .ls_announce_valid_i(bridge_ann_v),
    .ls_announce_bedtime_i(bridge_ann_bt),
    .ls_announce_sleep_cycles_i(bridge_ann_sc),
    .ls_announce_r1g_i(bridge_ann_r1g),
    .ls_announce_rsgx_i(bridge_ann_rsgx),
    .ls_confirm_valid_i(bridge_conf_v),
    .ls_confirm_r1g_a_i(bridge_conf_r1g),
    .ls_confirm_rsgx_a_i(bridge_conf_rsgx),
    .ls_deny_valid_i(bridge_deny_v),
    .ls_sleep_valid_i(bridge_sleep_v),
    .ls_sleep_alarmclock_i(bridge_sleep_ac),
    .ls_sleep_r1g_f_i(bridge_sleep_r1g),
    .ls_sleep_rsgx_f_i(bridge_sleep_rsgx),
    .app_ls_trigger_i(app_ls_trigger_i),
    .app_ptb_bedtime_i(app_ptb_bedtime_i),
    .app_sleep_cycles_i(app_sleep_cycles_i),
    .app_r1g_i(app_r1g_i),
    .app_rsgx_i(app_rsgx_i),
    .send_announce_o(fsm_announce),
    .send_announce_bedtime_o(fsm_ann_bedtime),
    .send_announce_sleep_cycles_o(fsm_ann_sleep_cycles),
    .send_announce_r1g_o(fsm_ann_r1g),
    .send_announce_rsgx_o(fsm_ann_rsgx),
    .send_confirm_o(fsm_confirm),
    .send_confirm_r1g_a_o(fsm_conf_r1g),
    .send_confirm_rsgx_a_o(fsm_conf_rsgx),
    .send_deny_o(fsm_deny),
    .send_sleep_o(fsm_sleep),
    .send_sleep_alarmclock_o(fsm_sleep_alarmclock),
    .send_sleep_r1g_f_o(fsm_sleep_r1g),
    .send_sleep_rsgx_f_o(fsm_sleep_rsgx),
    .pma_disable_o(pma_disable_o),
    .mapper_halt_o(mapper_halt_o),
    .startup_req_o(startup_req_o),
    .ls_enter_o(ls_enter_o),
    .ls_status_o(ls_status_o),
    .cnt_announced_o(cnt_announced_o),
    .cnt_denied_o(cnt_denied_o),
    .cnt_impossible_o(cnt_impossible_o),
    .cnt_impossible_node_o(cnt_impossible_node_o),
    .cnt_executed_o(cnt_executed_o),
    .cnt_fail_o(cnt_fail_o),
    .event_o(event_o)
  );

endmodule

`default_nettype wire
