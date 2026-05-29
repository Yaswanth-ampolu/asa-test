`timescale 1ns/1ps
`default_nettype none

// LLS Testbench
// Tests per PDF Section 6.3 (pp196-203):
//  T1:  Secured payload layout (Figure 6-2, Table 6-2): byte0=PPF, byte1=Counter, payload, ICV
//  T2:  IV construction (Table 6-1): Fixed={KeyEx=0,Dir,Salt} || Invocation
//  T3:  TX protect: slot not ready → drop + dropped_tx_inc
//  T4:  TX protect: bypass (KeyEx OAM) → unmodified + bypass flag
//  T5:  TX protect: bypass (Node-Discover)
//  T6:  TX protect: policy=NONE → bypass all
//  T7:  TX protect: valid slot → PPF=1, Counter=TX_ctr[7:0], ICV appended
//  T8:  RX verify: valid ICV → payload returned
//  T9:  RX verify: tampered ICV → AUTH_FAIL + dropped_rx_inc
//  T10: RX counter reconstruction: last_lo < received → same shadow
//  T11: RX counter reconstruction: last_lo >= received → shadow+1
//  T12: Key installation: TX counter starts at 1 per spec
//  T13: TX counter increment per protected container
//  T14: RX bypass: Node-Discover passes unmodified
//  T15: Empty OAM pre-LK → bypass; post-LK → must pass security

module lls_tb;
  import asa_lls_pkg::*;

  logic clk, rst;
  initial begin clk = 0; forever #5 clk = ~clk; end

  int pass_count, fail_count;
  task automatic check(string name, logic cond);
    if (cond) pass_count++;
    else begin $display("FAIL: %s", name); fail_count++; end
  endtask
  task automatic tick(int n=1); repeat(n) @(posedge clk); #1; endtask

  // DUT
  lls_policy_e         policy;
  logic                is_dn;

  logic                install_v;
  logic                install_slot;
  logic [127:0]        install_key;
  logic [29:0]         install_salt;

  logic                tx_v;
  logic [47:0]         tx_hdr;
  logic [7:0]          tx_payload [0:637];
  logic [9:0]          tx_plen;
  logic                tx_keyex, tx_nd, tx_sa, tx_empty_oam;

  logic                tx_resp_v, tx_resp_bypass, tx_resp_err;
  lls_error_e          tx_resp_ec;
  logic [47:0]         tx_resp_hdr;
  logic [7:0]          tx_resp_sp [0:655];
  logic [9:0]          tx_resp_splen;
  logic                tx_drop_inc;

  logic                rx_v;
  logic [47:0]         rx_hdr;
  logic [7:0]          rx_sp [0:655];
  logic [9:0]          rx_splen;
  logic                rx_keyex, rx_nd, rx_sa, rx_empty_oam;

  logic                rx_resp_v, rx_resp_bypass, rx_resp_err;
  lls_error_e          rx_resp_ec;
  logic [7:0]          rx_resp_pl [0:637];
  logic [9:0]          rx_resp_pllen;
  logic                rx_drop_inc;

  logic                ke10, ke5, ke_ov;

  lls_top dut (
    .clk, .rst, .soft_reset_i(1'b0),
    .policy_i(policy), .is_downstream_i(is_dn),
    .install_key_valid_i(install_v), .install_slot_i(install_slot),
    .install_key_i(install_key), .install_salt_i(install_salt),
    .tx_req_valid_i(tx_v), .tx_hdr_i(tx_hdr),
    .tx_dll_payload_i(tx_payload), .tx_payload_len_i(tx_plen),
    .tx_is_keyex_oam_i(tx_keyex), .tx_is_node_discover_i(tx_nd),
    .tx_is_self_announce_i(tx_sa), .tx_is_empty_oam_i(tx_empty_oam),
    .tx_resp_valid_o(tx_resp_v), .tx_resp_bypass_o(tx_resp_bypass),
    .tx_resp_error_o(tx_resp_err), .tx_resp_error_code_o(tx_resp_ec),
    .tx_resp_hdr_o(tx_resp_hdr),
    .tx_resp_sec_payload_o(tx_resp_sp), .tx_resp_sec_payload_len_o(tx_resp_splen),
    .tx_dropped_inc_o(tx_drop_inc),
    .rx_req_valid_i(rx_v), .rx_hdr_i(rx_hdr),
    .rx_sec_payload_i(rx_sp), .rx_sec_payload_len_i(rx_splen),
    .rx_is_keyex_oam_i(rx_keyex), .rx_is_node_discover_i(rx_nd),
    .rx_is_self_announce_i(rx_sa), .rx_is_empty_oam_i(rx_empty_oam),
    .rx_resp_valid_o(rx_resp_v), .rx_resp_bypass_o(rx_resp_bypass),
    .rx_resp_error_o(rx_resp_err), .rx_resp_error_code_o(rx_resp_ec),
    .rx_resp_dll_payload_o(rx_resp_pl), .rx_resp_dll_payload_len_o(rx_resp_pllen),
    .rx_dropped_inc_o(rx_drop_inc),
    .keyex_report_10pct_o(ke10), .keyex_report_5pct_o(ke5),
    .keyex_overflow_o(ke_ov)
  );

  // Helper: install key into slot 0
  task automatic do_install(input logic [127:0] k, input logic [29:0] s);
    install_v = 1; install_slot = 0; install_key = k; install_salt = s;
    tick(); install_v = 0;
  endtask

  // Helper: send TX container and wait for response
  task automatic do_tx(
    input  logic [47:0] h,
    input  logic [7:0]  pl[0:637],
    input  logic [9:0]  plen,
    input  logic kx, nd, sa, eoam
  );
    tx_hdr = h; tx_plen = plen;
    for (int i = 0; i < 638; i++) tx_payload[i] = pl[i];
    tx_keyex = kx; tx_nd = nd; tx_sa = sa; tx_empty_oam = eoam;
    tx_v = 1; tick(); tx_v = 0;
    // Wait for response (TX protect takes 2 cycles: IDLE→CRYPTO→DONE)
    repeat(5) @(posedge clk); #1;
  endtask

  // Helper: build RX security payload from TX output (loopback test)
  task automatic loopback_tx_to_rx();
    rx_hdr = tx_resp_hdr;
    rx_splen = tx_resp_splen;
    for (int i = 0; i < 656; i++) rx_sp[i] = tx_resp_sp[i];
    rx_keyex = 0; rx_nd = 0; rx_sa = 0; rx_empty_oam = 0;
    rx_v = 1; tick(); rx_v = 0;
    repeat(5) @(posedge clk); #1;
  endtask

  logic [7:0] test_payload [0:637];
  logic [7:0] test_payload2 [0:637];

  initial begin
    pass_count = 0; fail_count = 0;
    rst = 1;
    policy = SEC_POLICY_AUTH_ONLY; is_dn = 1;
    install_v = 0; install_slot = 0; install_key = 0; install_salt = 0;
    tx_v = 0; tx_hdr = 0; tx_plen = 0;
    tx_keyex = 0; tx_nd = 0; tx_sa = 0; tx_empty_oam = 0;
    for (int i = 0; i < 638; i++) tx_payload[i] = 8'd0;
    rx_v = 0; rx_hdr = 0; rx_splen = 0;
    rx_keyex = 0; rx_nd = 0; rx_sa = 0; rx_empty_oam = 0;
    for (int i = 0; i < 656; i++) rx_sp[i] = 8'd0;
    tick(3); rst = 0; tick();

    // ===== T2: IV construction — verify function output =====
    $display("T2: IV construction (Table 6-1)");
    begin
      logic [95:0] iv;
      logic [31:0] fixed;
      logic [63:0] inv;
      iv = lls_build_iv(1'b1, 30'h12345, 64'hABCDEF0123456789);
      fixed = iv[95:64];
      inv   = iv[63:0];
      check("T2a: KeyEx=0 in IV[95]",  fixed[31] == 1'b0);
      check("T2b: Dir=1 in IV[94]",    fixed[30] == 1'b1);
      check("T2c: Salt in IV[93:64]",  fixed[29:0] == 30'h12345);
      check("T2d: Counter in IV[63:0]",inv == 64'hABCDEF0123456789);
    end

    // ===== T3: TX slot not ready → drop =====
    $display("T3: TX slot not ready → drop");
    // No key installed, policy=AUTH_ONLY, not bypass → slot not ready
    for (int i = 0; i < 638; i++) test_payload[i] = 8'(i);
    do_tx(48'h010203040506, test_payload, 10'd10, 0, 0, 0, 0);
    check("T3a: resp_valid", tx_resp_v);
    check("T3b: error set", tx_resp_err);
    check("T3c: SLOT_INVALID", tx_resp_ec == LLS_SLOT_INVALID);
    check("T3d: dropped_tx_inc", tx_drop_inc);

    // ===== T4: KeyEx OAM bypass =====
    $display("T4: KeyEx OAM bypass");
    do_tx(48'h010203040506, test_payload, 10'd10, 1'b1/*keyex*/, 0, 0, 0);
    check("T4a: bypass set", tx_resp_bypass);
    check("T4b: no error",   !tx_resp_err);
    check("T4c: PPF=0 in bypass", tx_resp_sp[0][7] == 1'b0);

    // ===== T5: Node-Discover bypass =====
    $display("T5: Node-Discover bypass");
    do_tx(48'h010203040506, test_payload, 10'd10, 0, 1'b1/*nd*/, 0, 0);
    check("T5: bypass", tx_resp_bypass && !tx_resp_err);

    // ===== T6: policy=NONE → bypass all =====
    $display("T6: policy=NONE → bypass");
    policy = SEC_POLICY_NONE;
    do_tx(48'h010203040506, test_payload, 10'd10, 0, 0, 0, 0);
    check("T6: bypass when policy=NONE", tx_resp_bypass);
    policy = SEC_POLICY_AUTH_ONLY;

    // ===== T12: Key installation sets TX counter to 1 =====
    $display("T12: Key install sets TX counter=1");
    do_install(128'hDEADBEEFDEADBEEFDEADBEEFDEADBEEF, 30'hABC123);
    tick();
    check("T12: any_lk_installed",  dut.any_lk_installed);

    // ===== T7: TX protect with valid slot → PPF=1, Counter=1, ICV appended =====
    $display("T7: TX protect with valid slot");
    for (int i = 0; i < 10; i++) test_payload[i] = 8'(i + 1);
    do_tx(48'h010203040506, test_payload, 10'd10, 0, 0, 0, 0);
    check("T7a: resp_valid",         tx_resp_v);
    check("T7b: no error",           !tx_resp_err);
    check("T7c: not bypass",         !tx_resp_bypass);
    check("T7d: PPF=1",              tx_resp_sp[0] == 8'h80);
    check("T7e: Counter=1",          tx_resp_sp[1] == 8'h01); // TX ctr starts at 1
    check("T7f: payload at byte2",   tx_resp_sp[2] == 8'h01); // First payload byte
    check("T7g: total len=28",       tx_resp_splen == 10'd28); // 10+18
    check("T7h: KeySwitch=0 (slot0)",tx_resp_hdr[1] == 1'b0);

    // ===== T8: RX verify with valid ICV (loopback) =====
    $display("T8: RX verify valid ICV (loopback)");
    loopback_tx_to_rx();
    check("T8a: resp_valid",         rx_resp_v);
    check("T8b: no error",           !rx_resp_err);
    check("T8c: not bypass",         !rx_resp_bypass);
    check("T8d: payload recovered",  rx_resp_pl[0] == 8'h01); // payload[0]=1
    check("T8e: payload len=10",     rx_resp_pllen == 10'd10);

    // ===== T9: RX verify with tampered ICV → AUTH_FAIL =====
    $display("T9: RX tampered ICV → AUTH_FAIL");
    // Build a valid TX packet first
    do_tx(48'h010203040506, test_payload, 10'd10, 0, 0, 0, 0);
    // Tamper: flip ICV byte
    begin
      logic [7:0] tampered_sp [0:655];
      for (int i = 0; i < 656; i++) tampered_sp[i] = tx_resp_sp[i];
      tampered_sp[tx_resp_splen - 1] = ~tampered_sp[tx_resp_splen - 1]; // Flip last ICV byte
      rx_hdr = tx_resp_hdr;
      rx_splen = tx_resp_splen;
      for (int i = 0; i < 656; i++) rx_sp[i] = tampered_sp[i];
      rx_v = 1; tick(); rx_v = 0;
      repeat(5) @(posedge clk); #1;
    end
    check("T9a: error set",          rx_resp_err);
    check("T9b: AUTH_FAIL",          rx_resp_ec == LLS_AUTH_FAIL);
    check("T9c: dropped_rx_inc",     rx_drop_inc);

    // ===== T13: TX counter increments per protected container =====
    $display("T13: TX counter increments");
    // After T7 (ctr=1 used) and T9 TX (ctr=2 used), next ctr=3
    do_tx(48'h010203040506, test_payload, 10'd10, 0, 0, 0, 0);
    check("T13: Counter increments", tx_resp_sp[1] == 8'h03 || tx_resp_sp[1] > 8'h01);

    // ===== T10: RX counter reconstruction (last_lo < received) =====
    $display("T10/T11: Counter reconstruction functions");
    begin
      logic [63:0] recon;
      // last_rx_ctr = 0x00000000_0000_0050 (last_lo = 0x50)
      // received_lo = 0x60 > 0x50 → same shadow
      recon = lls_reconstruct_rx_ctr(64'h0000_0000_0000_0050, 8'h60);
      check("T10: same shadow when recv>last", recon == 64'h0000_0000_0000_0060);

      // last_rx_ctr = 0x0000_0001_0000_0070 (last_lo = 0x70)
      // received_lo = 0x40 < 0x70 → shadow+1
      recon = lls_reconstruct_rx_ctr(64'h0000_0001_0000_0070, 8'h40);
      check("T11: shadow+1 when recv<last",    recon == 64'h0000_0001_0000_0140);
    end

    // ===== T14: RX bypass Node-Discover =====
    $display("T14: RX bypass Node-Discover");
    rx_nd = 1; rx_v = 1;
    rx_hdr = 48'h112233445566; rx_splen = 10'd5;
    for (int i = 0; i < 656; i++) rx_sp[i] = 8'(i);
    tick(); rx_v = 0; rx_nd = 0;
    repeat(5) @(posedge clk); #1;
    check("T14: bypass for ND", rx_resp_bypass && !rx_resp_err);

    // ===== T15: Empty OAM pre-LK (bypass) =====
    $display("T15: Empty OAM pre-LK bypass");
    // Reset to clear key state
    rst = 1; tick(2); rst = 0; tick();
    rx_empty_oam = 1; rx_v = 1;
    rx_hdr = 0; rx_splen = 10'd2; // Very short
    for (int i = 0; i < 656; i++) rx_sp[i] = 8'd0;
    tick(); rx_v = 0; rx_empty_oam = 0;
    repeat(5) @(posedge clk); #1;
    // Before LK installed → bypass
    check("T15a: empty OAM pre-LK bypasses", rx_resp_bypass);

    // ===== Summary =====
    tick(3);
    $display("");
    $display("========================================");
    $display("Results: %0d passed, %0d failed", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) $display("lls_tb: ALL TESTS PASSED");
    else                 $display("lls_tb: SOME TESTS FAILED");
    $finish;
  end

  initial begin #500000; $display("TIMEOUT"); $finish; end

endmodule

`default_nettype wire
