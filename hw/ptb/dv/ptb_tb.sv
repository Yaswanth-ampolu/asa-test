`timescale 1ns/1ps
`default_nettype none

module ptb_tb;
  import asa_error_pkg::*;
  import asa_ptb_pkg::*;

  logic clk, rst, soft_reset;
  logic is_root, local_leader_enable, upstream_follower_locked, start_ptb;
  logic [47:0] upstream_ptbclk;
  logic reg_ptb_clk_wr_en;
  logic [47:0] reg_ptb_clk_wr_data;
  logic oam_tx_snapshot_req, oam_rx_valid;
  logic [47:0] oam_rx_ptbclk;
  logic ptb_rx_msg_valid;
  ptb_cmd_e ptb_rx_cmd;
  logic ptb_rx_status;
  logic [13:0] ptb_rx_stamp;
  logic mdi_tx_event, mdi_rx_event;
  logic start_tdd_arm;
  logic [47:0] start_tdd_ptbtime;
  logic ls_timer_arm;
  logic [47:0] ls_bedtime, ls_alarmclock;
  logic asep_ts_capture_req;
  logic [47:0] ptb_clk, ptb_oam_clk, oam_tx_ptbclk;
  logic [15:0] ptb_status, ptb_oam_dly, ptb_ext_status;
  logic ptb_locked, ptb_running;
  logic [8:0] oam_tx_ptbstatus;
  logic [7:0] oam_tx_header_byte4, oam_tx_header_byte5;
  ptb_cmd_e ptb_tx_cmd;
  logic ptb_tx_status;
  logic [13:0] ptb_tx_stamp;
  ptb_lock_state_e ptb_int_state;
  logic [4:0] cnt_follow, cnt_dly_reply, synced_updates;
  logic tdd_cycle_start, start_tdd_trigger, ls_bedtime_trigger, ls_alarm_trigger;
  logic [31:0] asep_ts_value;
  err_event_t err_event;

  int errors;
  int checks;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  ptb_top #(
    .TDD_CYCLE_TICS(8)
  ) dut (
    .clk                    (clk),
    .rst                    (rst),
    .soft_reset_i           (soft_reset),
    .is_root_i              (is_root),
    .local_leader_enable_i  (local_leader_enable),
    .upstream_follower_locked_i(upstream_follower_locked),
    .upstream_ptbclk_i      (upstream_ptbclk),
    .start_ptb_i            (start_ptb),
    .reg_ptb_clk_wr_en_i    (reg_ptb_clk_wr_en),
    .reg_ptb_clk_wr_data_i  (reg_ptb_clk_wr_data),
    .oam_tx_snapshot_req_i  (oam_tx_snapshot_req),
    .oam_rx_valid_i         (oam_rx_valid),
    .oam_rx_ptbclk_i        (oam_rx_ptbclk),
    .ptb_rx_msg_valid_i     (ptb_rx_msg_valid),
    .ptb_rx_cmd_i           (ptb_rx_cmd),
    .ptb_rx_status_i        (ptb_rx_status),
    .ptb_rx_stamp_i         (ptb_rx_stamp),
    .mdi_tx_event_i         (mdi_tx_event),
    .mdi_rx_event_i         (mdi_rx_event),
    .start_tdd_arm_i        (start_tdd_arm),
    .start_tdd_ptbtime_i    (start_tdd_ptbtime),
    .ls_timer_arm_i         (ls_timer_arm),
    .ls_bedtime_i           (ls_bedtime),
    .ls_alarmclock_i        (ls_alarmclock),
    .asep_ts_capture_req_i  (asep_ts_capture_req),
    .ptb_clk_o              (ptb_clk),
    .ptb_status_o           (ptb_status),
    .ptb_oam_clk_o          (ptb_oam_clk),
    .ptb_oam_dly_o          (ptb_oam_dly),
    .ptb_ext_status_o       (ptb_ext_status),
    .ptb_locked_o           (ptb_locked),
    .ptb_running_o          (ptb_running),
    .oam_tx_ptbclk_o        (oam_tx_ptbclk),
    .oam_tx_ptbstatus_o     (oam_tx_ptbstatus),
    .oam_tx_header_byte4_o  (oam_tx_header_byte4),
    .oam_tx_header_byte5_o  (oam_tx_header_byte5),
    .ptb_tx_cmd_o           (ptb_tx_cmd),
    .ptb_tx_status_o        (ptb_tx_status),
    .ptb_tx_stamp_o         (ptb_tx_stamp),
    .ptb_int_state_o        (ptb_int_state),
    .cnt_follow_o           (cnt_follow),
    .cnt_dly_reply_o        (cnt_dly_reply),
    .synced_updates_o       (synced_updates),
    .tdd_cycle_start_o      (tdd_cycle_start),
    .start_tdd_trigger_o    (start_tdd_trigger),
    .ls_bedtime_trigger_o   (ls_bedtime_trigger),
    .ls_alarm_trigger_o     (ls_alarm_trigger),
    .asep_ts_value_o        (asep_ts_value),
    .err_event_o            (err_event)
  );

  task automatic tick();
    @(posedge clk);
    #1;
  endtask

  task automatic check(input logic cond, input string msg);
    checks++;
    if (!cond) begin
      errors++;
      $display("FAIL: %s", msg);
    end
  endtask

  task automatic init_inputs();
    soft_reset = 1'b0;
    is_root = 1'b0;
    local_leader_enable = 1'b0;
    upstream_follower_locked = 1'b0;
    upstream_ptbclk = 48'd0;
    start_ptb = 1'b0;
    reg_ptb_clk_wr_en = 1'b0;
    reg_ptb_clk_wr_data = 48'd0;
    oam_tx_snapshot_req = 1'b0;
    oam_rx_valid = 1'b0;
    oam_rx_ptbclk = 48'd0;
    ptb_rx_msg_valid = 1'b0;
    ptb_rx_cmd = PTB_CMD_FOLLOW;
    ptb_rx_status = 1'b0;
    ptb_rx_stamp = 14'd0;
    mdi_tx_event = 1'b0;
    mdi_rx_event = 1'b0;
    start_tdd_arm = 1'b0;
    start_tdd_ptbtime = 48'd0;
    ls_timer_arm = 1'b0;
    ls_bedtime = 48'd0;
    ls_alarmclock = 48'd0;
    asep_ts_capture_req = 1'b0;
  endtask

  task automatic reset_dut();
    rst = 1'b1;
    init_inputs();
    repeat (3) tick();
    rst = 1'b0;
    tick();
  endtask

  task automatic pulse_start();
    start_ptb = 1'b1;
    tick();
    start_ptb = 1'b0;
    tick();
  endtask

  task automatic pulse_oam_rx(input logic [47:0] value);
    oam_rx_ptbclk = value;
    oam_rx_valid = 1'b1;
    tick();
    oam_rx_valid = 1'b0;
    tick();
  endtask

  task automatic pulse_mdi_tx();
    mdi_tx_event = 1'b1;
    tick();
    mdi_tx_event = 1'b0;
    tick();
  endtask

  task automatic send_ptb_msg(input ptb_cmd_e cmd, input logic [13:0] stamp);
    ptb_rx_cmd = cmd;
    ptb_rx_stamp = stamp;
    ptb_rx_status = 1'b1;
    ptb_rx_msg_valid = 1'b1;
    tick();
    ptb_rx_msg_valid = 1'b0;
    ptb_rx_status = 1'b0;
    tick();
  endtask

  task automatic send_dreply_follow(input logic signed [15:0] offset_target);
    logic [13:0] tx_stamp;
    logic [13:0] dly_stamp;
    logic [13:0] follow_stamp;
    tx_stamp = ptb_clk[13:0];
    pulse_mdi_tx();
    dly_stamp = tx_stamp + 14'd4;
    send_ptb_msg(PTB_CMD_DELAY_REPLY, dly_stamp);
    follow_stamp = ptb_clk[13:0] - (14'd4 + {offset_target[12:0], 1'b0});
    send_ptb_msg(PTB_CMD_FOLLOW, follow_stamp);
  endtask

  task automatic lock_follower();
    pulse_oam_rx(48'd100);
    for (int i = 0; i < 16; i++) begin
      send_dreply_follow(16'sd0);
    end
  endtask

  initial begin
    logic seen;
    logic seen_bedtime;
    logic seen_alarm;
    logic [47:0] saved_ptb;
    errors = 0;
    checks = 0;

    // TEST 1: PTBclk reset/start/repeated start behavior.
    reset_dut();
    check(ptb_clk == 48'd0, "PTBclk resets to zero");
    check(!ptb_running, "PTBclk is not running after reset");
    repeat (3) tick();
    check(ptb_clk == 48'd0, "PTBclk does not run before start/copy");
    pulse_start();
    saved_ptb = ptb_clk;
    repeat (3) tick();
    check(ptb_clk > saved_ptb, "startPTBclk starts the counter");
    saved_ptb = ptb_clk;
    pulse_start();
    check(ptb_clk > saved_ptb, "repeated start does not clear running PTBclk");

    // TEST 2: Register write overwrites the counter while preserving run state.
    reg_ptb_clk_wr_data = 48'd1000;
    reg_ptb_clk_wr_en = 1'b1;
    tick();
    reg_ptb_clk_wr_en = 1'b0;
    check(ptb_clk == 48'd1000, "PTBclk register write overwrites counter");
    tick();
    check(ptb_clk == 48'd1001, "PTBclk continues after register write");

    // TEST 3: OAM initial copy starts and overwrites only while unlocked.
    reset_dut();
    pulse_oam_rx(48'd200);
    check(ptb_running && ptb_clk >= 48'd200, "OAM initial copy starts PTBclk while unlocked");
    lock_follower();
    check(ptb_locked, "follower locks after 16 in-sync Follow updates");
    saved_ptb = ptb_clk;
    pulse_oam_rx(48'd50);
    check(ptb_clk > saved_ptb, "OAM frame does not overwrite PTBclk while locked");

    // TEST 4: OAM diagnostics and OAM header mapping.
    check(ptb_oam_clk == 48'd50, "PTBoamClk stores last received OAM PTBclk");
    check(ptb_oam_dly != 16'd0, "PTBoamDly updates when locked");
    oam_tx_snapshot_req = 1'b1;
    tick();
    oam_tx_snapshot_req = 1'b0;
    check(oam_tx_ptbclk != 48'd0, "OAM TX PTBclk snapshot is nonzero when locked");
    check(oam_tx_header_byte4[7] == ptb_status[8], "OAM byte4 bit7 carries PTBstatus[0]/PTBlocked");
    check(oam_tx_header_byte5 == ptb_status[7:0], "OAM byte5 carries PTBstatus[8:1]/PTBdelay");
    reset_dut();
    oam_tx_snapshot_req = 1'b1;
    tick();
    oam_tx_snapshot_req = 1'b0;
    check(oam_tx_ptbclk == 48'd0, "OAM TX PTBclk snapshot is zero when unlocked");
    check(ptb_oam_dly == 16'd0, "PTBoamDly is zero when unlocked");

    // TEST 5: Failed acquisition clears counters and remains unlocked.
    reset_dut();
    pulse_oam_rx(48'd300);
    for (int i = 0; i < 16; i++) begin
      send_dreply_follow(16'sd8);
    end
    check(!ptb_locked && ptb_int_state == PTB_STATE_UNLOCKED, "failed acquisition returns to unlocked");
    check(cnt_follow == 5'd0 && cnt_dly_reply == 5'd0, "failed acquisition clears counters");

    // TEST 6: Lock counters saturate and status packing reflects offset/delay.
    reset_dut();
    lock_follower();
    check(cnt_follow == 5'd16, "cnt_follow_received saturates at 16");
    check(cnt_dly_reply == 5'd16, "cnt_dlyRply_received saturates at 16");
    check(synced_updates == 5'd16, "in-sync updates saturate at acquisition window");
    send_dreply_follow(16'sd3);
    check(ptb_status[12:9] == 4'h3, "PTBstatus packs positive offset sign-magnitude");
    check(ptb_status[8] == 1'b1, "PTBstatus packs PTBlocked");
    check(offset_to_signmag(16'sd20, 1'b0) == 4'h7, "positive PTBoffset saturates to +7");
    check(offset_to_signmag(-16'sd20, 1'b0) == 4'hF, "negative PTBoffset saturates to -7");
    check(offset_to_signmag(16'sd0, 1'b1) == 4'h8, "invalid PTBoffset encodes 0x08");

    // TEST 7: Root leader TDD, StartTDD, LS timers, ASEP timestamp, TX m_ptb.
    reset_dut();
    is_root = 1'b1;
    pulse_start();
    check(ptb_locked && ptb_tx_status, "root leader reports valid PTB timing when running");
    check(ptb_tx_cmd == PTB_CMD_FOLLOW, "leader starts with Follow messages");
    seen = 1'b0;
    repeat (12) begin
      tick();
      if (tdd_cycle_start) seen = 1'b1;
    end
    check(seen, "leader emits TDD cycle pulse");
    start_tdd_ptbtime = ptb_clk + 48'd3;
    start_tdd_arm = 1'b1;
    tick();
    start_tdd_arm = 1'b0;
    ls_bedtime = ptb_clk + 48'd4;
    ls_alarmclock = ptb_clk + 48'd5;
    ls_timer_arm = 1'b1;
    tick();
    ls_timer_arm = 1'b0;
    asep_ts_capture_req = 1'b1;
    tick();
    asep_ts_capture_req = 1'b0;
    check(asep_ts_value == ptb_clk[31:0] - 32'd1, "ASEP timestamp captures lower 32 PTB bits");
    seen = 1'b0;
    seen_bedtime = 1'b0;
    seen_alarm = 1'b0;
    repeat (10) begin
      tick();
      if (start_tdd_trigger) seen = 1'b1;
      if (ls_bedtime_trigger) seen_bedtime = 1'b1;
      if (ls_alarm_trigger) seen_alarm = 1'b1;
    end
    check(seen, "StartTDD trigger fires at PTB target");
    check(seen_bedtime && seen_alarm, "Light Sleep bedtime and alarm triggers fire");

    // TEST 8: Local leader copies upstream follower PTBclk and validates status.
    reset_dut();
    local_leader_enable = 1'b1;
    upstream_follower_locked = 1'b1;
    upstream_ptbclk = 48'd1234;
    tick();
    check(ptb_clk == 48'd1234 && ptb_locked, "local leader copies locked upstream follower PTBclk");

    if (errors == 0) begin
      $display("ptb_tb: ALL TESTS PASSED (%0d checks)", checks);
    end else begin
      $display("ptb_tb: %0d TESTS FAILED out of %0d checks", errors, checks);
    end
    $finish;
  end

endmodule

`default_nettype wire
