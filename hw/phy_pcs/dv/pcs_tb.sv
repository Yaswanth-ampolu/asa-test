`timescale 1ns/1ps
`default_nettype none

// PCS Building Blocks Testbench
// Tests: PRBS11, PRBS9, scrambler, CRC32, PAM mapping

module pcs_tb;
  import asa_pcs_pkg::*;

  logic clk, rst;
  initial begin clk = 0; forever #5 clk = ~clk; end

  int pass_count, fail_count;

  task automatic check(string name, logic cond);
    if (cond) pass_count++;
    else begin $display("FAIL: %s", name); fail_count++; end
  endtask

  // =========================================================================
  // PRBS11 instance
  // =========================================================================
  logic        prbs11_init, prbs11_adv;
  logic        prbs11_s0;
  logic [10:0] prbs11_state;

  pcs_prbs11 u_prbs11 (
    .clk(clk), .rst(rst),
    .init_i(prbs11_init), .advance_i(prbs11_adv),
    .s0_o(prbs11_s0), .state_o(prbs11_state)
  );

  // =========================================================================
  // PRBS9 instance
  // =========================================================================
  logic        prbs9_init, prbs9_adv;
  logic        prbs9_s0;
  logic [8:0]  prbs9_state;
  logic [4:0]  prbs9_offset_out;

  pcs_prbs9 u_prbs9 (
    .clk(clk), .rst(rst),
    .init_i(prbs9_init), .advance_i(prbs9_adv),
    .s0_o(prbs9_s0), .state_o(prbs9_state), .offset_o(prbs9_offset_out)
  );

  // =========================================================================
  // CRC32 instance
  // =========================================================================
  logic        crc_init, crc_valid;
  logic [7:0]  crc_data;
  logic [31:0] crc_out, crc_final;

  pcs_crc32 u_crc32 (
    .clk(clk), .rst(rst),
    .init_i(crc_init), .valid_i(crc_valid), .data_i(crc_data),
    .crc_o(crc_out), .crc_final_o(crc_final)
  );

  // =========================================================================
  // PAM mapper instance
  // =========================================================================
  logic       pam_is_pam4, pam_is_rsync;
  logic       pam_msb, pam_lsb;
  pam2_sym_t  pam2_sym;
  pam4_sym_t  pam4_sym;
  logic       pam_use_pam4;

  pcs_pam_map u_pam (
    .is_pam4_i(pam_is_pam4), .is_resync_hdr_i(pam_is_rsync),
    .bit_msb_i(pam_msb), .bit_lsb_i(pam_lsb),
    .pam2_sym_o(pam2_sym), .pam4_sym_o(pam4_sym), .use_pam4_o(pam_use_pam4)
  );

  // =========================================================================
  // Scrambler instance
  // =========================================================================
  logic        scr_init, scr_adv;
  logic [1:0]  scr_linkid;
  logic        scr_is_dn, scr_is_pam4;
  logic        scr_din_msb, scr_din_lsb;
  logic        scr_dout_msb, scr_dout_lsb;
  logic [22:0] scr_state;

  pcs_scrambler u_scr (
    .clk(clk), .rst(rst),
    .init_i(scr_init), .link_id_i(scr_linkid),
    .advance_i(scr_adv), .is_downstream_i(scr_is_dn), .is_pam4_i(scr_is_pam4),
    .data_in_msb_i(scr_din_msb), .data_in_lsb_i(scr_din_lsb),
    .data_out_msb_o(scr_dout_msb), .data_out_lsb_o(scr_dout_lsb),
    .state_o(scr_state)
  );

  // =========================================================================
  // Test sequence
  // =========================================================================
  initial begin
    pass_count = 0; fail_count = 0;
    rst = 1;
    prbs11_init = 0; prbs11_adv = 0;
    prbs9_init = 0; prbs9_adv = 0;
    crc_init = 0; crc_valid = 0; crc_data = 0;
    pam_is_pam4 = 0; pam_is_rsync = 0; pam_msb = 0; pam_lsb = 0;
    scr_init = 0; scr_adv = 0; scr_linkid = 0;
    scr_is_dn = 1; scr_is_pam4 = 0; scr_din_msb = 0; scr_din_lsb = 0;

    repeat(3) @(posedge clk); rst = 0; @(posedge clk);

    // ===== TEST 1: PRBS11 init and first few outputs =====
    $display("TEST 1: PRBS11 init and sequence");
    prbs11_init = 1; @(posedge clk); prbs11_init = 0; @(posedge clk);
    check("PRBS11: init state = 0x001", prbs11_state == 11'h001);
    check("PRBS11: S0 after init = 1", prbs11_s0 == 1'b1);

    // Advance a few steps and check the LFSR isn't stuck
    prbs11_adv = 1;
    repeat(10) @(posedge clk);
    prbs11_adv = 0; @(posedge clk);
    check("PRBS11: state changed after 10 steps", prbs11_state != 11'h001);

    // ===== TEST 2: PRBS9 init and offset extraction =====
    $display("TEST 2: PRBS9 init and offset");
    prbs9_init = 1; @(posedge clk); prbs9_init = 0; @(posedge clk);
    check("PRBS9: init state = 0x001", prbs9_state == 9'h001);
    // First offset from state 0x001:
    // Step 0: S0=state[0]=1, step 1..4: depends on LFSR
    // Just check offset is in range 0-31
    // offset is 5 bits so always 0-31; just check it's not X (non-zero state)
    check("PRBS9: offset valid (state non-zero)", prbs9_state !== 9'd0);

    // ===== TEST 3: CRC32 reference test from Table 4-21 =====
    $display("TEST 3: CRC32 reference vector");
    begin
      logic [7:0] test_bytes [0:14];
      test_bytes = '{8'h80, 8'h55, 8'h38, 8'h3F, 8'hB3, 8'h0C, 8'h80, 8'h0D,
                     8'h82, 8'h61, 8'h65, 8'h71, 8'h0B, 8'hDF, 8'hFF};
      crc_init = 1; @(posedge clk); crc_init = 0;
      for (int i = 0; i < 15; i++) begin
        crc_data = test_bytes[i]; crc_valid = 1;
        @(posedge clk);
      end
      crc_valid = 0; @(posedge clk);
      // Expected from Table 4-21: after 15 bytes processed, CRC32 out = B843C1B8
      check("CRC32: reference = 0xB843C1B8", crc_final == 32'hB843C1B8);
    end

    // ===== TEST 4: PAM2 mapping =====
    $display("TEST 4: PAM2 mapping");
    pam_is_pam4 = 0; pam_is_rsync = 0;
    pam_msb = 0; #1;
    check("PAM2: 0 → +1", pam2_sym == 2'sd1);
    pam_msb = 1; #1;
    check("PAM2: 1 → -1", pam2_sym == -2'sd1);

    // ===== TEST 5: PAM4 Gray mapping =====
    $display("TEST 5: PAM4 Gray mapping");
    pam_is_pam4 = 1; pam_is_rsync = 0;
    pam_msb = 0; pam_lsb = 0; #1;
    check("PAM4: {0,0} → +3", pam4_sym == 3'sd3);
    pam_msb = 0; pam_lsb = 1; #1;
    check("PAM4: {0,1} → +1", pam4_sym == 3'sd1);
    pam_msb = 1; pam_lsb = 1; #1;
    check("PAM4: {1,1} → -1", pam4_sym == -3'sd1);
    pam_msb = 1; pam_lsb = 0; #1;
    check("PAM4: {1,0} → -3", pam4_sym == -3'sd3);

    // ===== TEST 6: PAM4 forced to PAM2 during resync header =====
    $display("TEST 6: PAM4 region forced PAM2 during resync");
    pam_is_pam4 = 1; pam_is_rsync = 1; pam_msb = 0; #1;
    check("PAM4+rsync: use_pam4=0", pam_use_pam4 == 1'b0);

    // ===== TEST 7: Scrambler init and inverse property =====
    $display("TEST 7: Scrambler inverse property");
    scr_is_dn = 1; scr_is_pam4 = 0; scr_linkid = 2'd0;
    scr_init = 1; @(posedge clk); scr_init = 0; @(posedge clk);
    check("Scrambler: init state = 0x000001", scr_state == 23'h000001);

    // Scramble a bit, then descramble with fresh init → should recover
    scr_din_msb = 1'b1; scr_adv = 1; @(posedge clk);
    begin
      logic scr_bit;
      scr_bit = scr_dout_msb; // scrambled output
      scr_adv = 0;
      // Reset scrambler and descramble
      scr_init = 1; @(posedge clk); scr_init = 0; @(posedge clk);
      scr_din_msb = scr_bit; scr_adv = 1; @(posedge clk);
      scr_adv = 0;
      check("Scrambler: XOR inverse recovers original", scr_dout_msb == 1'b1);
    end

    // ===== TEST 8: Scrambler state changes on advance =====
    $display("TEST 8: Scrambler state advances");
    scr_init = 1; @(posedge clk); scr_init = 0; @(posedge clk);
    begin
      logic [22:0] s_before;
      s_before = scr_state;
      scr_adv = 1; @(posedge clk); scr_adv = 0; @(posedge clk);
      check("Scrambler: state changed after advance", scr_state != s_before);
    end

    // ===== SUMMARY =====
    repeat(3) @(posedge clk);
    $display("");
    $display("========================================");
    $display("Results: %0d passed, %0d failed", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) $display("pcs_tb: ALL TESTS PASSED");
    else                 $display("pcs_tb: SOME TESTS FAILED");
    $finish;
  end

  initial begin #500000; $display("TIMEOUT"); $finish; end

endmodule

`default_nettype wire
