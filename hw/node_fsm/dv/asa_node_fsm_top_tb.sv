`timescale 1ns/1ps
`default_nettype none

module asa_node_fsm_top_tb;
  localparam logic [3:0] ST_POI     = 4'd0;
  localparam logic [3:0] ST_STARTUP = 4'd1;
  localparam logic [3:0] ST_OAM_CFG = 4'd2;
  localparam logic [3:0] ST_NORMAL  = 4'd3;
  localparam logic [3:0] ST_LS      = 4'd5;
  localparam logic [3:0] ST_FAIL    = 4'd6;
  localparam logic [3:0] ST_DSLEEP  = 4'd7;
  localparam logic [1:0] LS_SLEEPING   = 2'd2;
  localparam logic [1:0] LS_RESTARTING = 2'd3;

  logic        clk, rst;
  logic [3:0]  node_state_o;
  logic        soft_reset_wr_i;
  logic [13:0] irq_flags_o;
  logic        com_ready_o;
  logic        start_tdd_i;
  logic [47:0] start_tdd_ptb_time_i;
  logic [15:0] start_tdd_linemin_i;
  logic [15:0] start_tdd_linemax_i;
  logic        oam_config_active_o;
  logic [47:0] ptb_time_i;
  logic        phy_startup_complete_i;
  logic        phy_startup_fail_i;
  logic        phy_test_mode_req_i;
  logic        phy_test_complete_i;
  logic        phy_disable_o;
  logic        phy_enable_o;
  logic        oam_config_skip_i;
  logic        mapper_init_o;
  logic [15:0] mapper_linemin_o;
  logic [15:0] mapper_linemax_o;
  logic [47:0] mapper_ptb_start_o;
  logic        ls_enter_i;
  logic        ls_wake_i;
  logic        tdd_boundary_i;
  logic        link_loss_ind_i;
  logic [5:0]  consec_loss_count_o;
  logic [5:0]  link_loss_total_o;
  logic [1:0]  light_sleep_status_o;
  logic        power_on_init_done_i;
  logic        restart_req_i;
  logic        deep_sleep_req_i;

  asa_node_fsm_top dut (.*);

  always #5 clk = ~clk;

  int err_count = 0;

  task automatic check(input logic condition, input string msg);
    if (!condition) begin
      $error("FAIL: %s (time=%0t state=%0d)", msg, $time, node_state_o);
      err_count++;
    end
  endtask

  task automatic tick();
    @(posedge clk); #1;
  endtask

  task automatic reset_inputs();
    soft_reset_wr_i       = 1'b0;
    start_tdd_i           = 1'b0;
    start_tdd_ptb_time_i  = 48'd0;
    start_tdd_linemin_i   = 16'd0;
    start_tdd_linemax_i   = 16'd0;
    ptb_time_i            = 48'd0;
    phy_startup_complete_i = 1'b0;
    phy_startup_fail_i    = 1'b0;
    phy_test_mode_req_i   = 1'b0;
    phy_test_complete_i   = 1'b0;
    oam_config_skip_i     = 1'b0;
    ls_enter_i            = 1'b0;
    ls_wake_i             = 1'b0;
    tdd_boundary_i        = 1'b0;
    link_loss_ind_i       = 1'b0;
    power_on_init_done_i  = 1'b0;
    restart_req_i         = 1'b0;
    deep_sleep_req_i      = 1'b0;
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    reset_inputs();

    repeat (2) tick();
    rst = 1'b0;

    check(node_state_o == ST_POI, "T1: reset -> PowerOn/Init");
    tick();
    check(node_state_o == ST_POI, "T2: stays in PowerOn/Init until explicit done");

    power_on_init_done_i = 1'b1; tick(); power_on_init_done_i = 1'b0;
    check(node_state_o == ST_STARTUP, "T3: explicit power-on done -> Startup");

    phy_startup_complete_i = 1'b1; tick(); phy_startup_complete_i = 1'b0;
    check(node_state_o == ST_OAM_CFG, "T4: startup complete -> OAM Config");
    check(oam_config_active_o, "T4: OAM config active");

    start_tdd_ptb_time_i = 48'h1122_3344_5566;
    start_tdd_linemin_i  = 16'h0011;
    start_tdd_linemax_i  = 16'h00aa;
    start_tdd_i = 1'b1; tick(); start_tdd_i = 1'b0;
    check(node_state_o == ST_OAM_CFG, "T5: StartTDD capture holds in OAM Config until PTBtime");
    check(!mapper_init_o, "T5: mapper init waits for PTBtime");
    check(mapper_ptb_start_o == 48'h1122_3344_5566, "T5: mapper PTB captured");
    check(mapper_linemin_o == 16'h0011, "T5: mapper linemin captured");
    check(mapper_linemax_o == 16'h00aa, "T5: mapper linemax captured");
    ptb_time_i = 48'h1122_3344_5565; tick();
    check(node_state_o == ST_OAM_CFG, "T5b: still OAM Config before PTBtime");
    check(!mapper_init_o, "T5b: no mapper init before PTBtime");
    ptb_time_i = 48'h1122_3344_5566; tick();
    check(node_state_o == ST_NORMAL, "T5c: PTBtime reached -> Normal");
    check(mapper_init_o, "T5c: mapper init pulse at PTBtime");
    tick();
    check(!mapper_init_o, "T5d: mapper init pulse clears");

    ls_enter_i = 1'b1; tick(); ls_enter_i = 1'b0;
    check(node_state_o == ST_LS, "T6: enter Light Sleep");
    check(light_sleep_status_o == LS_SLEEPING, "T6: LS sleeping status");
    check(phy_disable_o, "T6: PHY disable pulse on sleep entry");

    ls_wake_i = 1'b1; tick(); ls_wake_i = 1'b0;
    check(node_state_o == ST_STARTUP, "T7: wake -> Startup");
    check(light_sleep_status_o == LS_RESTARTING, "T7: LS restarting status");
    check(phy_enable_o, "T7: PHY enable pulse on wake");

    phy_startup_fail_i = 1'b1; tick(); phy_startup_fail_i = 1'b0;
    check(node_state_o == ST_FAIL, "T8: startup fail -> Fail");

    restart_req_i = 1'b1; tick(); restart_req_i = 1'b0;
    check(node_state_o == ST_STARTUP, "T9: restart request -> Startup");

    phy_startup_fail_i = 1'b1; tick(); phy_startup_fail_i = 1'b0;
    check(node_state_o == ST_FAIL, "T10 setup: back to Fail");
    deep_sleep_req_i = 1'b1; tick(); deep_sleep_req_i = 1'b0;
    check(node_state_o == ST_DSLEEP, "T10: deep sleep request -> Deep Sleep");

    if (err_count == 0) begin
      $display("asa_node_fsm_top_tb: ALL TESTS PASSED");
    end else begin
      $display("asa_node_fsm_top_tb: %0d TESTS FAILED", err_count);
    end
    $finish;
  end
endmodule

`default_nettype wire
