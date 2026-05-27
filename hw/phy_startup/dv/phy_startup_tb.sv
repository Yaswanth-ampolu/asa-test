`timescale 1ns/1ps
`default_nettype none

module phy_startup_tb;
  import asa_node_pkg::*;
  import asa_error_pkg::*;
  import asa_phy_startup_pkg::*;

  logic clk, rst, soft_reset;
  logic [3:0] node_state;
  logic startup_complete, startup_fail, startup_test_mode_req, startup_test_complete;
  logic oam_config_skip;
  logic is_root;
  logic [15:0] sg_config;
  logic [13:0] sg_capability;
  logic [1:0] security_policy;
  logic phy_layer_mode;
  logic [15:0] diag_test_ctrl;
  logic oam_config_skip_req;
  logic [1:0] polarity_status;
  logic ph1g_self_good;
  phy_start_status_e ph1g_lp_stat;
  logic ph1g_lp_valid;
  logic ph1g_test_req;
  logic phsga_self_good;
  phy_start_status_e phsga_lp_stat;
  logic phsga_lp_valid;
  logic phsga_test_req;
  logic phsgb_self_good;
  phy_start_status_e phsgb_lp_stat;
  logic phsgb_lp_valid;
  logic phsgc_self_good;
  phy_start_status_e phsgc_lp_stat;
  logic phsgc_lp_valid;
  logic rx_burst_active;
  phy_start_phase_e startup_phase;
  phy_start_pattern_e tx_pattern_sel;
  logic tx_start;
  phy_start_status_e tx_status;
  logic [39:0] tx_phase1g_info;
  logic [511:0] tx_phasesg_info;
  logic pma_reset, pma_disable, pma_enable, startup_ptb_init;
  logic [15:0] link_training_status;
  logic [15:0] ext_link_training_status;
  logic [15:0] connectivity_id;
  logic [7:0] retry_count;
  logic [4:0] timeout_count;
  logic [23:0] phasesg_count;
  err_event_t err_event;

  int errors;
  int checks;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  phy_startup_top #(
    .PH1G_TIMER_CYCLES (4),
    .PHSG_TIMER_CYCLES (3),
    .TEST_TIMER_CYCLES (3),
    .MS_TICK_CYCLES    (5)
  ) dut (
    .clk                       (clk),
    .rst                       (rst),
    .soft_reset_i              (soft_reset),
    .node_state_i              (node_state),
    .startup_complete_o        (startup_complete),
    .startup_fail_o            (startup_fail),
    .startup_test_mode_req_o   (startup_test_mode_req),
    .startup_test_complete_o   (startup_test_complete),
    .oam_config_skip_o         (oam_config_skip),
    .is_root_i                 (is_root),
    .sg_config_i               (sg_config),
    .sg_capability_i           (sg_capability),
    .security_policy_i         (security_policy),
    .phy_layer_mode_i          (phy_layer_mode),
    .diag_test_ctrl_i          (diag_test_ctrl),
    .oam_config_skip_req_i     (oam_config_skip_req),
    .polarity_status_i         (polarity_status),
    .ph1g_self_good_i          (ph1g_self_good),
    .ph1g_lp_stat_i            (ph1g_lp_stat),
    .ph1g_lp_valid_i           (ph1g_lp_valid),
    .ph1g_test_req_i           (ph1g_test_req),
    .phsga_self_good_i         (phsga_self_good),
    .phsga_lp_stat_i           (phsga_lp_stat),
    .phsga_lp_valid_i          (phsga_lp_valid),
    .phsga_test_req_i          (phsga_test_req),
    .phsgb_self_good_i         (phsgb_self_good),
    .phsgb_lp_stat_i           (phsgb_lp_stat),
    .phsgb_lp_valid_i          (phsgb_lp_valid),
    .phsgc_self_good_i         (phsgc_self_good),
    .phsgc_lp_stat_i           (phsgc_lp_stat),
    .phsgc_lp_valid_i          (phsgc_lp_valid),
    .rx_burst_active_i         (rx_burst_active),
    .startup_phase_o           (startup_phase),
    .tx_pattern_sel_o          (tx_pattern_sel),
    .tx_start_o                (tx_start),
    .tx_status_o               (tx_status),
    .tx_phase1g_info_o         (tx_phase1g_info),
    .tx_phasesg_info_o         (tx_phasesg_info),
    .pma_reset_o               (pma_reset),
    .pma_disable_o             (pma_disable),
    .pma_enable_o              (pma_enable),
    .startup_ptb_init_o        (startup_ptb_init),
    .link_training_status_o    (link_training_status),
    .ext_link_training_status_o(ext_link_training_status),
    .connectivity_id_o         (connectivity_id),
    .retry_count_o             (retry_count),
    .timeout_count_o           (timeout_count),
    .phasesg_count_o           (phasesg_count),
    .err_event_o               (err_event)
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
    node_state = ASA_STATE_STARTUP;
    is_root = 1'b1;
    sg_config = 16'h0002; // SG3, no PhaseSGC
    sg_capability = 14'h3FFF;
    security_policy = 2'b01;
    phy_layer_mode = 1'b0;
    diag_test_ctrl = 16'h0000;
    oam_config_skip_req = 1'b0;
    polarity_status = 2'b01;
    ph1g_self_good = 1'b1;
    ph1g_lp_stat = PHY_START_STAT_PROCEED;
    ph1g_lp_valid = 1'b1;
    ph1g_test_req = 1'b0;
    phsga_self_good = 1'b1;
    phsga_lp_stat = PHY_START_STAT_PROCEED;
    phsga_lp_valid = 1'b1;
    phsga_test_req = 1'b0;
    phsgb_self_good = 1'b1;
    phsgb_lp_stat = PHY_START_STAT_PROCEED;
    phsgb_lp_valid = 1'b1;
    phsgc_self_good = 1'b1;
    phsgc_lp_stat = PHY_START_STAT_PROCEED;
    phsgc_lp_valid = 1'b1;
    rx_burst_active = 1'b0;
  endtask

  task automatic reset_dut();
    rst = 1'b1;
    init_inputs();
    repeat (3) tick();
    rst = 1'b0;
    tick();
  endtask

  task automatic wait_for_complete(input int max_cycles, output logic seen);
    seen = 1'b0;
    for (int i = 0; i < max_cycles; i++) begin
      tick();
      if (startup_complete) seen = 1'b1;
    end
  endtask

  task automatic wait_for_phase(input phy_start_phase_e phase, input int max_cycles, output logic seen);
    seen = 1'b0;
    for (int i = 0; i < max_cycles; i++) begin
      tick();
      if (startup_phase == phase) seen = 1'b1;
    end
  endtask

  initial begin
    logic seen;
    logic saw_cmd;
    logic [479:0] crc_vec;
    errors = 0;
    checks = 0;

    // TEST 1: Root reaches G transition after Phase1G, SGA, SGB.
    reset_dut();
    wait_for_complete(40, seen);
    check(seen, "root startup completes without PhaseSGC");
    check(link_training_status[10] == 1'b1, "COMready set after startup complete");
    check(tx_phase1g_info[31:30] == PHY_START_STAT_PREPARED, "Phase1G status packed");
    check(tx_phase1g_info[39:32] == phase1g_parity_byte(tx_phase1g_info[31:0]), "Phase1G parity byte correct");
    check(ext_link_training_status[7:0] == retry_count, "ExtendedLinkTrainingStatus mirrors retry counter");
    crc_vec = '0;
    crc_vec[0*8 +: 8] = 8'h80;
    crc_vec[1*8 +: 8] = 8'h55;
    crc_vec[2*8 +: 8] = 8'h38;
    crc_vec[3*8 +: 8] = 8'h3F;
    crc_vec[4*8 +: 8] = 8'hB3;
    crc_vec[5*8 +: 8] = 8'h0C;
    crc_vec[6*8 +: 8] = 8'h80;
    crc_vec[7*8 +: 8] = 8'h0D;
    crc_vec[8*8 +: 8] = 8'h82;
    crc_vec[9*8 +: 8] = 8'h61;
    crc_vec[10*8 +: 8] = 8'h65;
    crc_vec[11*8 +: 8] = 8'h71;
    crc_vec[12*8 +: 8] = 8'h0B;
    crc_vec[13*8 +: 8] = 8'hDF;
    crc_vec[14*8 +: 8] = 8'hFF;
    check(asa_crc32(crc_vec, 15) == 32'hB843_C1B8, "CRC32 matches Section 4.2.9 image test vector");

    // TEST 2: SG4/5 path visits PhaseSGC before completion.
    reset_dut();
    sg_config = 16'h0003; // SG4 requires PhaseSGC
    wait_for_phase(PHY_START_SGC, 40, seen);
    check(seen, "SG4 startup visits PhaseSGC");
    wait_for_complete(40, seen);
    check(seen, "SG4 startup completes after PhaseSGC");

    // TEST 3: Leaf waits first, replies PROCEED, and completes.
    reset_dut();
    is_root = 1'b0;
    sg_config = 16'h0002;
    ph1g_lp_stat = PHY_START_STAT_PREPARED;
    phsga_lp_stat = PHY_START_STAT_PREPARED;
    phsgb_lp_stat = PHY_START_STAT_PREPARED;
    wait_for_complete(60, seen);
    check(seen, "leaf startup completes");
    check(phasesg_count >= 24'd2, "leaf sends PhaseSG info fields");

    // TEST 4: Missing partner status causes retry/timeout, not immediate failure.
    reset_dut();
    ph1g_lp_valid = 1'b0;
    repeat (20) tick();
    check(retry_count != 8'd0, "Phase1G timeout increments retry counter");
    check(timeout_count != 5'd0, "Phase1G timeout increments timeout counter");
    check(!startup_fail, "single timeout does not assert fail");

    // TEST 5: Phase1G retry limit fails exactly when the incremented count reaches 255.
    reset_dut();
    ph1g_lp_valid = 1'b0;
    repeat (1800) tick();
    check(startup_fail, "Phase1G retry limit asserts fail");
    check(retry_count == 8'd255, "Phase1G retry counter saturates at spec limit");

    // TEST 6: PhaseSG ERROR restarts startup_INIT and records LP error.
    reset_dut();
    phsga_lp_stat = PHY_START_STAT_ERROR;
    repeat (40) tick();
    check(link_training_status[15:11] != 5'd0, "LP ERROR increments LinkTraining LPerrors");
    check(timeout_count != 5'd0, "PhaseSG ERROR path records restart event");

    // TEST 7: Startup-triggered TX diagnostic requests node Test mode then returns.
    reset_dut();
    diag_test_ctrl = 16'h0003; // Enable=1, TestType=TX Linearity
    seen = 1'b0;
    repeat (20) begin
      tick();
      if (startup_test_mode_req) seen = 1'b1;
    end
    check(seen, "TX diagnostic asserts startup_test_mode_req");
    seen = 1'b0;
    repeat (20) begin
      tick();
      if (startup_test_complete) seen = 1'b1;
    end
    check(seen, "TX diagnostic completes");

    // TEST 8: Leaf Phase1G TX-test branch requires LP PROCEED plus test request.
    reset_dut();
    is_root = 1'b0;
    ph1g_lp_stat = PHY_START_STAT_PREPARED;
    ph1g_test_req = 1'b1;
    seen = 1'b0;
    repeat (16) begin
      tick();
      if (startup_phase == PHY_START_TX_TEST) seen = 1'b1;
    end
    check(!seen, "leaf Phase1G ignores test request until LP status is PROCEED");
    ph1g_lp_stat = PHY_START_STAT_PROCEED;
    repeat (12) begin
      tick();
      if (startup_phase == PHY_START_TX_TEST) seen = 1'b1;
    end
    check(seen, "leaf Phase1G enters TX test when LP status is PROCEED and test request is set");

    // TEST 9: Root PhaseSGA receiver-test command uses the root-specific command/wait path.
    reset_dut();
    phsga_lp_stat = PHY_START_STAT_PREPARED;
    phsga_test_req = 1'b1;
    seen = 1'b0;
    saw_cmd = 1'b0;
    repeat (40) begin
      tick();
      if (startup_phase == PHY_START_RX_TEST && startup_test_mode_req) seen = 1'b1;
      if (tx_start && tx_pattern_sel == PHY_PATTERN_PHASE_SGA && tx_status == PHY_START_STAT_PROCEED) begin
        saw_cmd = 1'b1;
      end
    end
    check(seen, "root PhaseSGA test request enters RX test mode");
    check(saw_cmd, "root PhaseSGA RX test emits SGA test command with PROCEED status");

    // TEST 10: Leaf PhaseSGA RX-test branch requires LP PREPARED plus test request.
    reset_dut();
    is_root = 1'b0;
    ph1g_lp_stat = PHY_START_STAT_PREPARED;
    phsga_lp_stat = PHY_START_STAT_TRAINING;
    phsga_test_req = 1'b1;
    seen = 1'b0;
    repeat (30) begin
      tick();
      if (startup_phase == PHY_START_RX_TEST) seen = 1'b1;
    end
    check(!seen, "leaf PhaseSGA ignores RX test request until LP status is PREPARED");
    phsga_lp_stat = PHY_START_STAT_PREPARED;
    repeat (20) begin
      tick();
      if (startup_phase == PHY_START_RX_TEST) seen = 1'b1;
    end
    check(seen, "leaf PhaseSGA enters RX test when LP status is PREPARED and test request is set");

    // TEST 11: OAMconfigSkip request is reported at completion.
    reset_dut();
    oam_config_skip_req = 1'b1;
    wait_for_complete(40, seen);
    check(seen && oam_config_skip, "OAMconfigSkip latched on G/H transition");
    check(tx_phasesg_info[18] == 1'b1, "PhaseSG info field carries OAMconfigSkip");

    if (errors == 0) begin
      $display("phy_startup_tb: ALL TESTS PASSED (%0d checks)", checks);
    end else begin
      $display("phy_startup_tb: %0d TESTS FAILED out of %0d checks", errors, checks);
    end
    $finish;
  end

endmodule

`default_nettype wire
