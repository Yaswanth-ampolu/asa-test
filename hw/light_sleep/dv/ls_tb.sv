`timescale 1ns/1ps
`default_nettype none

// Light Sleep Controller Testbench
// Timing model: outputs are COMBINATIONAL from state register.
// Check outputs BEFORE tick() that would transition out of the state.

module ls_tb;
  import asa_ls_pkg::*;

  logic clk, rst;
  initial begin clk = 0; forever #5 clk = ~clk; end

  int pass_count, fail_count;
  task automatic check(string name, logic cond);
    if (cond) pass_count++;
    else begin $display("FAIL: %s", name); fail_count++; end
  endtask
  task automatic tick(int n=1); repeat(n) @(posedge clk); #1; endtask

  // DUT signals
  logic       soft_reset, is_root, ls_capable, normal_mode;
  logic [4:0] n_nodes;
  logic       ptb_locked; logic [47:0] ptb_clk;
  logic       ptb_bed_trig, ptb_alarm_trig;
  logic       ptb_be; logic [47:0] ptb_bv;
  logic       ptb_ae; logic [47:0] ptb_av;
  logic       oam_av; logic [47:0] oam_abt; logic [11:0] oam_asc;
  logic [7:0] oam_ar, oam_arsgx;
  logic       oam_cv; logic [7:0] oam_cr, oam_crsgx;
  logic       oam_dv, oam_sv; logic [47:0] oam_sac;
  logic [7:0] oam_sr, oam_srsgx;
  logic       oam_out_ann, oam_out_conf, oam_out_deny, oam_out_sleep;
  logic       app_trig; logic [47:0] app_bt; logic [11:0] app_sc;
  logic [7:0] app_r, app_rsgx;
  logic       pma_dis, map_halt, start_req, ls_enter;
  ls_status_e ls_status;
  logic       cnt_ann, cnt_den, cnt_imp, cnt_exec, cnt_fail;
  logic [4:0] cnt_imp_node;
  ls_event_e  ls_event;

  ls_top dut (
    .clk, .rst, .soft_reset_i(soft_reset),
    .is_root_i(is_root), .ls_capable_i(ls_capable), .normal_mode_i(normal_mode),
    .n_nodes_i(n_nodes),
    .ptb_locked_i(ptb_locked), .ptb_clk_i(ptb_clk),
    .ptb_bedtime_trigger_i(ptb_bed_trig),
    .ptb_alarmclock_trigger_i(ptb_alarm_trig),
    .ptb_bedtime_en_o(ptb_be), .ptb_bedtime_val_o(ptb_bv),
    .ptb_alarm_en_o(ptb_ae), .ptb_alarm_val_o(ptb_av),
    .oam_announce_valid_i(oam_av), .oam_announce_bedtime_i(oam_abt),
    .oam_announce_sleep_cycles_i(oam_asc),
    .oam_announce_r1g_i(oam_ar), .oam_announce_rsgx_i(oam_arsgx),
    .oam_confirm_valid_i(oam_cv), .oam_confirm_r1g_a_i(oam_cr),
    .oam_confirm_rsgx_a_i(oam_crsgx),
    .oam_deny_valid_i(oam_dv),
    .oam_sleep_valid_i(oam_sv), .oam_sleep_alarmclock_i(oam_sac),
    .oam_sleep_r1g_f_i(oam_sr), .oam_sleep_rsgx_f_i(oam_srsgx),
    .oam_send_announce_o(oam_out_ann), .oam_send_announce_bedtime_o(),
    .oam_send_announce_sleep_cycles_o(), .oam_send_announce_r1g_o(),
    .oam_send_announce_rsgx_o(),
    .oam_send_confirm_o(oam_out_conf), .oam_send_confirm_r1g_a_o(),
    .oam_send_confirm_rsgx_a_o(),
    .oam_send_deny_o(oam_out_deny),
    .oam_send_sleep_o(oam_out_sleep), .oam_send_sleep_alarmclock_o(),
    .oam_send_sleep_r1g_f_o(), .oam_send_sleep_rsgx_f_o(),
    .app_ls_trigger_i(app_trig), .app_ptb_bedtime_i(app_bt),
    .app_sleep_cycles_i(app_sc), .app_r1g_i(app_r), .app_rsgx_i(app_rsgx),
    .pma_disable_o(pma_dis), .mapper_halt_o(map_halt),
    .startup_req_o(start_req), .ls_enter_o(ls_enter), .ls_status_o(ls_status),
    .cnt_announced_o(cnt_ann), .cnt_denied_o(cnt_den),
    .cnt_impossible_o(cnt_imp), .cnt_impossible_node_o(cnt_imp_node),
    .cnt_executed_o(cnt_exec), .cnt_fail_o(cnt_fail),
    .event_o(ls_event)
  );

  // Send feasible announce: sleep_cycles=100 gives net_sleep >> 25000 tics
  task automatic send_feasible_ann();
    oam_av = 1; oam_abt = ptb_clk + 48'd50000; oam_asc = 12'd100;
    oam_ar = 8'd1; oam_arsgx = 8'd1;
    tick(); oam_av = 0;
  endtask

  task automatic send_lssleep();
    oam_sv = 1; oam_sac = ptb_clk + 48'd100000;
    oam_sr = 8'd1; oam_srsgx = 8'd1;
    tick(); oam_sv = 0;
  endtask

  initial begin
    pass_count = 0; fail_count = 0;
    rst = 1; soft_reset = 0;
    is_root = 0; ls_capable = 1; normal_mode = 1;
    ptb_locked = 1; ptb_clk = 48'd1_000_000;
    ptb_bed_trig = 0; ptb_alarm_trig = 0;
    oam_av = 0; oam_cv = 0; oam_dv = 0; oam_sv = 0;
    app_trig = 0; app_bt = 0; app_sc = 0; app_r = 0; app_rsgx = 0;
    n_nodes = 5'd1;  // Default: 1 non-root to wait for
    tick(3); rst = 0; tick();

    // ===== T1: Non-root feasible: full path announce→confirm→sleep→dream→wake =====
    $display("T1: Non-root feasible full path");
    // IDLE → CHECK_3
    send_feasible_ann();
    // Now in CHECK_3; sample before transition
    // → CONFIRM_3 (feasible)
    tick();
    // Now in CONFIRM_3: send_confirm is combinational from this state
    check("T1a: in CONFIRM_3 (mediating)", ls_status == LS_STATUS_MEDIATING);
    check("T1b: confirm sent in CONFIRM_3", oam_out_conf == 1'b1);

    // → WAIT_3
    tick();
    check("T1c: in WAIT_3", ls_status == LS_STATUS_MEDIATING);

    // Send LSsleep → LIGHTS_OUT_3
    send_lssleep();
    // Now in LIGHTS_OUT_3: ls_enter=1, set alarmclock
    check("T1d: lights out (enter)", ls_enter == 1'b1);
    check("T1e: mapper halted", map_halt == 1'b1);

    // → DREAMING_3
    tick();
    check("T1f: sleeping", ls_status == LS_STATUS_SLEEPING);
    check("T1g: PMA disabled", pma_dis == 1'b1);

    // Fire alarmclock → RESTARTING_3 (Fix 2: one-cycle RESTARTING)
    ptb_alarm_trig = 1; tick(); ptb_alarm_trig = 0;
    // Now in RESTARTING_3
    check("T1h: RESTARTING status", ls_status == LS_STATUS_RESTARTING);
    check("T1i: startup_req in RESTARTING", start_req == 1'b1);
    check("T1i2: cnt_executed", cnt_exec == 1'b1);
    tick();  // → IDLE
    check("T1j: back to NORMAL", ls_status == LS_STATUS_NORMAL);
    check("T1k: PMA re-enabled", pma_dis == 1'b0);

    // ===== T2: Non-root infeasible → deny =====
    $display("T2: Non-root infeasible (PTB unlocked) → deny");
    ptb_locked = 0;
    send_feasible_ann(); // IDLE → CHECK_3
    // In CHECK_3: cnt_impossible fires here (combinational)
    check("T2b: cnt_impossible in CHECK_3", cnt_imp == 1'b1);
    tick();              // → DENY_3 (infeasible since ptb_locked=0)
    check("T2a: deny sent in DENY_3", oam_out_deny == 1'b1);
    tick();
    check("T2c: back to NORMAL", ls_status == LS_STATUS_NORMAL);
    ptb_locked = 1;

    // ===== T3: timer_LSbedtime fires before LSsleep → direct dreaming =====
    $display("T3: bedtime fires before LSsleep → direct to dreaming");
    send_feasible_ann(); // → CHECK_3
    tick();              // → CONFIRM_3
    check("T3a: confirm sent", oam_out_conf == 1'b1);
    tick();              // → WAIT_3
    ptb_bed_trig = 1; tick(); ptb_bed_trig = 0;
    // → DREAMING_3 directly (Figure 5-13)
    tick();
    check("T3b: sleeping without alarmclock", ls_status == LS_STATUS_SLEEPING);
    // Wake via alarmclock → RESTARTING_3
    ptb_alarm_trig = 1; tick(); ptb_alarm_trig = 0;
    check("T3c: RESTARTING status", ls_status == LS_STATUS_RESTARTING);
    check("T3d: startup_req in RESTARTING", start_req == 1'b1);
    tick(); // → IDLE

    // ===== T4: Root receives non-root-initiated announce → mediate → wait n → sleep =====
    $display("T4: Root receives announce, mediates, waits for n=1 confirm → sleep");
    is_root = 1; n_nodes = 5'd1; tick();
    // IDLE → MEDIATE_1 (announce received from non-root)
    send_feasible_ann();
    // In MEDIATE_1: re-issues LSannounce to other affected nodes
    check("T4a: announce re-issued in MEDIATE_1", oam_out_ann == 1'b1);
    tick();  // → ANNOUNCE_1 (waiting for n=1 confirm)
    // Receive one confirm → collected all n=1 → evaluate feasibility → CONFIRM_1
    oam_cv = 1; oam_cr = 8'd1; oam_crsgx = 8'd1;
    tick(); oam_cv = 0;
    // Now in CONFIRM_1 (all n=1 confirmed, LSpossible=TRUE)
    check("T4b: confirm sent in CONFIRM_1", oam_out_conf == 1'b1);
    tick();  // → ISSUE_SLEEP_1
    check("T4c: sleep issued", oam_out_sleep == 1'b1);
    tick();  // → LIGHTS_OUT_1
    check("T4d: lights out", ls_enter == 1'b1);
    tick();  // → DREAMING_1
    check("T4e: sleeping", ls_status == LS_STATUS_SLEEPING);
    ptb_alarm_trig = 1; tick(); ptb_alarm_trig = 0;
    // → RESTARTING_1 (Fix 2: one-cycle RESTARTING status)
    check("T4f: RESTARTING status", ls_status == LS_STATUS_RESTARTING);
    check("T4g: startup_req in RESTARTING", start_req == 1'b1);
    tick();  // → IDLE
    check("T4h: back to NORMAL", ls_status == LS_STATUS_NORMAL);
    is_root = 0;

    // ===== T5: Root initiates → wait n confirms → check_2 → sleep =====
    $display("T5: Root initiates, waits n=1 confirm → sleep");
    is_root = 1; n_nodes = 5'd1; tick();
    app_trig = 1; app_bt = ptb_clk + 48'd50000; app_sc = 12'd100;
    app_r = 8'd1; app_rsgx = 8'd1;
    tick(); app_trig = 0;  // → ANNOUNCE_2
    check("T5a: announce_2 sent", oam_out_ann == 1'b1);
    // Receive n=1 confirm → move to CHECK_2
    oam_cv = 1; oam_cr = 8'd2; oam_crsgx = 8'd2;
    tick(); oam_cv = 0;  // → CHECK_2 (all n=1 responded)
    tick();   // → ISSUE_SLEEP_2 (feasible)
    check("T5b: sleep issued", oam_out_sleep == 1'b1);
    tick();   // → LIGHTS_OUT_2
    tick();   // → DREAMING_2
    check("T5c: sleeping", ls_status == LS_STATUS_SLEEPING);
    ptb_alarm_trig = 1; tick(); ptb_alarm_trig = 0;
    // → RESTARTING_2
    check("T5d: RESTARTING status", ls_status == LS_STATUS_RESTARTING);
    check("T5e: startup_req", start_req == 1'b1);
    tick(); is_root = 0;

    // ===== T_NEW1: Root waits for n=2 confirms before deciding (multi-node) =====
    $display("T_NEW1: Root waits n=2 confirms (multi-node response counting)");
    is_root = 1; n_nodes = 5'd2; tick();
    app_trig = 1; app_bt = ptb_clk + 48'd50000; app_sc = 12'd100;
    app_r = 8'd1; app_rsgx = 8'd1;
    tick(); app_trig = 0;  // → ANNOUNCE_2
    // First confirm: only 1 of 2 → stay in ANNOUNCE_2
    oam_cv = 1; oam_cr = 8'd1; oam_crsgx = 8'd1;
    tick(); oam_cv = 0; #1;
    check("TN1a: still waiting after 1 confirm", oam_out_sleep == 1'b0);
    // Second confirm: 2 of 2 → advance to CHECK_2
    oam_cv = 1; oam_cr = 8'd2; oam_crsgx = 8'd2;
    tick(); oam_cv = 0;  // → CHECK_2
    tick();  // → ISSUE_SLEEP_2
    check("TN1b: sleep issued after all n=2 confirms", oam_out_sleep == 1'b1);
    tick(); tick(); tick(); // lights-out, dreaming
    ptb_alarm_trig = 1; tick(); ptb_alarm_trig = 0; tick(); tick(); // dreaming → restarting → idle
    is_root = 0; n_nodes = 5'd1;

    // ===== T6: Root check_2 LSpossible=FALSE → deny → idle =====
    $display("T6: Root check_2 infeasible → deny");
    is_root = 1; ptb_locked = 0; tick();
    app_trig = 1; app_bt = ptb_clk + 48'd50000; app_sc = 12'd100;
    app_r = 8'd1; app_rsgx = 8'd1;
    tick(); app_trig = 0;  // → ANNOUNCE_2
    oam_cv = 1; oam_cr = 8'd1; oam_crsgx = 8'd1;
    tick(); oam_cv = 0;  // → CHECK_2
    tick();              // LSpossible=FALSE → IDLE
    check("T6: back to NORMAL", ls_status == LS_STATUS_NORMAL);
    is_root = 0; ptb_locked = 1;

    // ===== T7: capability=0 → ignore all LS activity =====
    $display("T7: ls_capable=0 → no LS");
    ls_capable = 0; tick();
    oam_av = 1; oam_abt = ptb_clk + 48'd50000; oam_asc = 12'd100;
    oam_ar = 8'd1; oam_arsgx = 8'd1;
    tick(); oam_av = 0; tick(3);
    check("T7: stays NORMAL", ls_status == LS_STATUS_NORMAL);
    ls_capable = 1;

    // ===== T8: Soft reset during mediation =====
    $display("T8: Soft reset during mediation");
    send_feasible_ann(); tick();  // → CHECK_3
    tick();  // → CONFIRM_3: check confirm NOW (before soft_reset)
    check("T8a: in CONFIRM_3 (mediating)", ls_status == LS_STATUS_MEDIATING);
    soft_reset = 1; tick(); soft_reset = 0; tick();
    check("T8b: reset to NORMAL", ls_status == LS_STATUS_NORMAL);

    // ===== T9: PMA disable only during dreaming =====
    $display("T9: PMA/mapper only in dreaming");
    check("T9a: PMA off at idle", pma_dis == 1'b0);
    check("T9b: mapper off at idle", map_halt == 1'b0);
    send_feasible_ann(); tick(); tick();  // → CONFIRM_3
    check("T9c: PMA off in mediation", pma_dis == 1'b0);
    tick();  // → WAIT_3
    send_lssleep();  // → LIGHTS_OUT_3
    check("T9d: mapper halt in lights-out", map_halt == 1'b1);
    check("T9e: PMA off in lights-out", pma_dis == 1'b0);
    tick();  // → DREAMING_3
    check("T9f: PMA dis in dreaming", pma_dis == 1'b1);
    check("T9g: mapper halt in dreaming", map_halt == 1'b1);
    ptb_alarm_trig = 1; tick(); ptb_alarm_trig = 0; tick(); tick(); // → RESTARTING → IDLE

    // ===== T10: startup_req only on alarmclock while dreaming =====
    $display("T10: startup_req only in dreaming");
    ptb_alarm_trig = 1; #1;
    check("T10: no spurious startup_req", start_req == 1'b0);
    ptb_alarm_trig = 0; tick();

    // ===== T11: cnt_announced increments on LSannounce =====
    $display("T11: cnt_announced");
    oam_av = 1; oam_abt = ptb_clk + 48'd50000; oam_asc = 12'd100;
    oam_ar = 8'd1; oam_arsgx = 8'd1; #1;
    check("T11: cnt_announced", cnt_ann == 1'b1);
    tick(); oam_av = 0;
    // Clean up: FSM may have entered mediation
    soft_reset = 1; tick(); soft_reset = 0; tick();

    // ===== T12: cnt_denied increments on LSdeny =====
    $display("T12: cnt_denied");
    oam_dv = 1; #1;
    check("T12: cnt_denied", cnt_den == 1'b1);
    tick(); oam_dv = 0;

    // ===== T13: Non-root announce_2 → root sends deny → idle =====
    $display("T13: Non-root initiates → root denies → idle");
    is_root = 0;
    app_trig = 1; app_bt = ptb_clk + 48'd50000; app_sc = 12'd100;
    app_r = 8'd1; app_rsgx = 8'd1;
    tick(); app_trig = 0;  // → ANNOUNCE_2
    check("T13a: announce_2 sent", oam_out_ann == 1'b1);
    oam_dv = 1; tick(); oam_dv = 0;  // root denies → IDLE
    tick();
    check("T13b: back to NORMAL", ls_status == LS_STATUS_NORMAL);

    // ===== T_NEW2: Soft reset clears PTB timer arming (Fix 3) =====
    $display("T_NEW2: Soft reset clears PTB bedtime/alarm armed flags");
    // Enter CONFIRM_3 state (arms bedtime timer)
    send_feasible_ann(); tick(); tick();  // → CONFIRM_3 (arms bedtime)
    check("TN2a: bedtime armed", ptb_be == 1'b1);
    // Now soft reset
    soft_reset = 1; tick(); soft_reset = 0; tick();
    // PTB timers should be disarmed
    check("TN2b: bedtime disarmed after soft_reset", ptb_be == 1'b0);
    check("TN2c: FSM back to NORMAL", ls_status == LS_STATUS_NORMAL);

    // ===== T_NEW3: n_nodes_i=0 is invalid — root ignores trigger (abort to IDLE) =====
    // Spec (Section 5.8.1.2): root collects from n>=1 affected nodes.
    // n=0 means no nodes to sleep with — architecturally illegal.
    $display("T_NEW3: n_nodes_i=0 → root ignores app trigger, stays NORMAL");
    is_root = 1; n_nodes = 5'd0; tick();
    app_trig = 1; app_bt = ptb_clk + 48'd50000; app_sc = 12'd100;
    app_r = 8'd1; app_rsgx = 8'd1;
    tick(); app_trig = 0; tick(3);
    check("TN3a: ignored (stays NORMAL)", ls_status == LS_STATUS_NORMAL);

    $display("T_NEW4: n_nodes_i=0 written mid-wait → immediate abort from ANNOUNCE_1");
    n_nodes = 5'd1; tick();
    // Start root-initiated path normally with n=1
    app_trig = 1; app_bt = ptb_clk + 48'd50000; app_sc = 12'd100;
    app_r = 8'd1; app_rsgx = 8'd1;
    tick(); app_trig = 0;  // → ANNOUNCE_2
    check("TN4a: mediating in ANNOUNCE_2", ls_status == LS_STATUS_MEDIATING);
    // Now corrupt n_nodes to 0 before any confirm arrives
    n_nodes = 5'd0; tick();
    // FSM should detect !n_valid and abort to IDLE
    check("TN4b: aborted to NORMAL", ls_status == LS_STATUS_NORMAL);
    n_nodes = 5'd1; is_root = 0;

    // ===== Summary =====
    tick(3);
    $display("");
    $display("========================================");
    $display("Results: %0d passed, %0d failed", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) $display("ls_tb: ALL TESTS PASSED");
    else                 $display("ls_tb: SOME TESTS FAILED");
    $finish;
  end

  initial begin #500000; $display("TIMEOUT"); $finish; end

endmodule

`default_nettype wire
