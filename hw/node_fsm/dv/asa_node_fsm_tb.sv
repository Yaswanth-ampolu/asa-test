`timescale 1ns/1ps
`default_nettype none

// Testbench for asa_node_fsm
// Validates all transitions from Figure 2-3 and register semantics from
// Sections 3.2.6, 3.2.7, 3.2.8, 3.2.12, 3.2.13

module asa_node_fsm_tb;

  // State encodings (mirror asa_node_pkg)
  localparam logic [3:0] ST_POI     = 4'd0; // PowerOn/Init
  localparam logic [3:0] ST_STARTUP = 4'd1;
  localparam logic [3:0] ST_OAM_CFG = 4'd2;
  localparam logic [3:0] ST_NORMAL  = 4'd3;
  localparam logic [3:0] ST_TEST    = 4'd4;
  localparam logic [3:0] ST_LS      = 4'd5; // Light Sleep
  localparam logic [3:0] ST_FAIL    = 4'd6;
  localparam logic [3:0] ST_DSLEEP  = 4'd7; // Deep Sleep

  localparam logic [1:0] LS_NORMAL     = 2'd0;
  localparam logic [1:0] LS_SLEEPING   = 2'd2;
  localparam logic [1:0] LS_RESTARTING = 2'd3;

  logic clk, rst;
  logic soft_reset, init_done;
  logic startup_done, startup_failed;
  logic startup_test_mode_req, startup_test_complete;
  logic startup_skip_oam_cfg;
  logic start_tdd;
  logic light_sleep_enter, light_sleep_wake;
  logic tdd_boundary, link_loss_ind;
  logic restart_req, deep_sleep_req;

  logic [3:0]  node_state;
  logic [1:0]  light_sleep_status;
  logic        com_ready;
  logic [5:0]  consec_loss_count;
  logic [5:0]  link_loss_total;
  logic [13:0] irq_flags;

  asa_node_fsm dut (.*);

  always #5 clk = ~clk;

  int err_count = 0;

  task automatic check(input logic condition, input string msg);
    if (!condition) begin
      $error("FAIL: %s (time=%0t, state=%0d)", msg, $time, node_state);
      err_count++;
    end
  endtask

  task automatic tick();
    @(posedge clk); #1;
  endtask

  task automatic reset_inputs();
    soft_reset           = 0;
    init_done            = 0;
    startup_done         = 0;
    startup_failed       = 0;
    startup_test_mode_req = 0;
    startup_test_complete = 0;
    startup_skip_oam_cfg = 0;
    start_tdd            = 0;
    light_sleep_enter    = 0;
    light_sleep_wake     = 0;
    tdd_boundary         = 0;
    link_loss_ind        = 0;
    restart_req          = 0;
    deep_sleep_req       = 0;
  endtask

  // Simulate one TDD cycle boundary with valid burst
  task automatic tdd_burst_valid();
    tdd_boundary = 1;
    link_loss_ind = 0;
    tick();
    tdd_boundary = 0;
  endtask

  // Simulate one TDD cycle boundary with lost burst
  task automatic tdd_burst_lost();
    tdd_boundary = 1;
    link_loss_ind = 1;
    tick();
    tdd_boundary = 0;
    link_loss_ind = 0;
  endtask

  initial begin
    clk = 0;
    rst = 1;
    reset_inputs();

    repeat (2) tick();
    rst = 0;

    // ================================================================
    // TEST 1: Reset enters PowerOn/Init (state 0)
    // ================================================================
    check(node_state == ST_POI, "T1: reset -> PowerOn/Init");
    check(com_ready == 0, "T1: COMready low after reset");
    check(light_sleep_status == LS_NORMAL, "T1: LS status normal");
    check(link_loss_total == 0, "T1: total loss counter zero");

    // ================================================================
    // TEST 2: PowerOn/Init -> Startup on init_done
    // ================================================================
    init_done = 1; tick(); init_done = 0;
    check(node_state == ST_STARTUP, "T2: init_done -> Startup");
    check(com_ready == 0, "T2: COMready low in Startup");

    // ================================================================
    // TEST 3: Startup -> OAM Config (normal path, transition G/H)
    // ================================================================
    startup_done = 1; tick(); startup_done = 0;
    check(node_state == ST_OAM_CFG, "T3: startup_done -> OAM Config");
    check(com_ready == 1, "T3: COMready high in OAM Config");

    // ================================================================
    // TEST 4: OAM Config -> Normal on StartTDD (Section 5.5.3.9)
    // ================================================================
    start_tdd = 1; tick(); start_tdd = 0;
    check(node_state == ST_NORMAL, "T4: StartTDD -> Normal");
    check(com_ready == 1, "T4: COMready high in Normal");

    // ================================================================
    // TEST 5: Normal Mode link loss - 2 consecutive bursts, no fail
    // ================================================================
    tdd_burst_lost();
    check(node_state == ST_NORMAL, "T5a: 1st loss stays Normal");
    check(consec_loss_count == 6'd1, "T5a: consec=1");
    check(link_loss_total == 6'd1, "T5a: total=1");

    tdd_burst_lost();
    check(node_state == ST_NORMAL, "T5b: 2nd loss stays Normal");
    check(consec_loss_count == 6'd2, "T5b: consec=2");
    check(link_loss_total == 6'd2, "T5b: total=2");

    // ================================================================
    // TEST 6: Normal -> Fail on 3rd consecutive lost burst (Spec 2.4)
    // ================================================================
    tdd_burst_lost();
    check(node_state == ST_FAIL, "T6: 3rd loss -> Fail");
    check(com_ready == 0, "T6: COMready low in Fail");
    check(irq_flags[0] == 1, "T6: Local PHY IRQ asserted");
    check(link_loss_total == 6'd3, "T6: total=3");

    // ================================================================
    // TEST 7: Fail -> Startup on restart_req
    // ================================================================
    restart_req = 1; tick(); restart_req = 0;
    check(node_state == ST_STARTUP, "T7: restart -> Startup");
    check(link_loss_total == 6'd3, "T7: total counter preserved on restart");

    // ================================================================
    // TEST 8: Startup -> Test Mode (transition T)
    // ================================================================
    startup_test_mode_req = 1; tick(); startup_test_mode_req = 0;
    check(node_state == ST_TEST, "T8: test_mode_req -> Test");

    // ================================================================
    // TEST 9: Test Mode -> Startup (transition R)
    // ================================================================
    startup_test_complete = 1; tick(); startup_test_complete = 0;
    check(node_state == ST_STARTUP, "T9: test_complete -> Startup");

    // ================================================================
    // TEST 10: Startup with OAMconfigSkip -> Normal directly
    // ================================================================
    startup_skip_oam_cfg = 1;
    startup_done = 1; tick();
    startup_done = 0; startup_skip_oam_cfg = 0;
    check(node_state == ST_NORMAL, "T10: skip OAM -> Normal directly");

    // ================================================================
    // TEST 11: Consecutive loss counter resets on valid burst
    // ================================================================
    tdd_burst_lost();
    check(consec_loss_count == 6'd1, "T11a: 1 loss");
    tdd_burst_valid();
    check(consec_loss_count == 6'd0, "T11b: valid burst resets consec");
    check(node_state == ST_NORMAL, "T11b: still Normal");
    check(link_loss_total == 6'd4, "T11b: cumulative total preserved across restart");

    // ================================================================
    // TEST 12: Normal -> Light Sleep (transition a)
    // ================================================================
    light_sleep_enter = 1; tick(); light_sleep_enter = 0;
    check(node_state == ST_LS, "T12: enter Light Sleep");
    check(light_sleep_status == LS_SLEEPING, "T12: LS status sleeping");
    check(com_ready == 0, "T12: COMready low in LS");

    // ================================================================
    // TEST 13: Light Sleep -> Startup (transition b, alarm clock)
    // ================================================================
    light_sleep_wake = 1; tick(); light_sleep_wake = 0;
    check(node_state == ST_STARTUP, "T13: wake -> Startup");
    check(light_sleep_status == LS_RESTARTING, "T13: LS status restarting");

    // ================================================================
    // TEST 14: Post-LS restart with OAMconfigSkip
    // ================================================================
    startup_done = 1; startup_skip_oam_cfg = 1;
    tick();
    startup_done = 0; startup_skip_oam_cfg = 0;
    check(node_state == ST_NORMAL, "T14: post-LS skip -> Normal");
    check(light_sleep_status == LS_NORMAL, "T14: LS status cleared");

    // ================================================================
    // TEST 15: SoftReset from Normal (Section 3.2.7)
    // ================================================================
    soft_reset = 1; tick(); soft_reset = 0;
    check(node_state == ST_STARTUP, "T15: SoftReset -> Startup");
    check(com_ready == 0, "T15: COMready low");
    check(irq_flags == 14'd0, "T15: IRQ cleared by SoftReset");
    check(link_loss_total == 6'd0, "T15: total loss cleared by SoftReset");

    // ================================================================
    // TEST 16: Startup -> Fail on startup_failed (retry exhausted)
    // ================================================================
    startup_failed = 1; tick(); startup_failed = 0;
    check(node_state == ST_FAIL, "T16: startup_failed -> Fail");
    check(irq_flags[0] == 1, "T16: Local PHY IRQ on startup fail");

    // ================================================================
    // TEST 17: Fail -> Deep Sleep
    // ================================================================
    deep_sleep_req = 1; tick(); deep_sleep_req = 0;
    check(node_state == ST_DSLEEP, "T17: deep_sleep_req -> Deep Sleep");

    // ================================================================
    // TEST 18: OAM Config -> Fail on 3 consecutive TDD burst losses
    //          (Figure 2-3, transition Z from OAM Config)
    // ================================================================
    // Get back to OAM Config: reset path
    rst = 1; tick(); rst = 0;
    init_done = 1; tick(); init_done = 0;
    startup_done = 1; tick(); startup_done = 0;
    check(node_state == ST_OAM_CFG, "T18 setup: in OAM Config");

    tdd_burst_lost();
    check(node_state == ST_OAM_CFG, "T18a: 1st loss stays OAM Config");
    tdd_burst_lost();
    check(node_state == ST_OAM_CFG, "T18b: 2nd loss stays OAM Config");
    tdd_burst_lost();
    check(node_state == ST_FAIL, "T18c: 3rd loss -> Fail from OAM Config");

    // ================================================================
    // TEST 19: LinkQuality total counter saturates at 0x3F
    // ================================================================
    rst = 1; tick(); rst = 0;
    init_done = 1; tick(); init_done = 0;
    startup_done = 1; tick(); startup_done = 0;
    start_tdd = 1; tick(); start_tdd = 0;
    check(node_state == ST_NORMAL, "T19 setup: Normal");

    // Accumulate losses without triggering Fail (2 lost, 1 valid, repeat)
    begin : sat_loop
      integer i;
      for (i = 0; i < 70; i = i + 1) begin
        tdd_burst_lost();
        tdd_burst_lost();
        tdd_burst_valid();
        if (node_state == ST_FAIL) begin
          check(0, "T19: unexpected Fail");
          disable sat_loop;
        end
      end
    end
    check(link_loss_total == 6'd63, "T19: total saturates at 63 (0x3F)");

    // ================================================================
    // TEST 20: OAM Config valid burst resets consecutive counter
    // ================================================================
    rst = 1; tick(); rst = 0;
    init_done = 1; tick(); init_done = 0;
    startup_done = 1; tick(); startup_done = 0;
    check(node_state == ST_OAM_CFG, "T20 setup: OAM Config");

    tdd_burst_lost();
    tdd_burst_lost();
    tdd_burst_valid(); // resets consecutive
    tdd_burst_lost();
    tdd_burst_lost();
    check(node_state == ST_OAM_CFG, "T20: no Fail after interleaved valid");
    check(consec_loss_count == 6'd2, "T20: consec=2 after reset+2");

    // ================================================================
    // SUMMARY
    // ================================================================
    if (err_count == 0) begin
      $display("asa_node_fsm_tb: ALL TESTS PASSED");
    end else begin
      $display("asa_node_fsm_tb: %0d TESTS FAILED", err_count);
    end
    $finish;
  end

endmodule

`default_nettype wire
