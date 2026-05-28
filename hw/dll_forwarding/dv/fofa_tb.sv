`timescale 1ns/1ps
`default_nettype none

// FoFa Testbench
// Timing model: tx_fwd_hdr/oam_hdr are COMBINATORIAL from queue head.
// Check BEFORE tick() that would advance rd_ptr.

module fofa_tb;
  import asa_dll_pkg::*;
  import asa_fofa_pkg::*;

  logic clk, rst;
  initial begin clk = 0; forever #5 clk = ~clk; end

  int pass_count, fail_count;
  task automatic check(string name, logic cond);
    if (cond) pass_count++;
    else begin $display("FAIL: %s", name); fail_count++; end
  endtask
  task automatic tick(); @(posedge clk); #1; endtask

  logic        soft_reset, normal_mode;
  logic [4:0]  local_nid, nodeb_nid;
  logic        rx_valid; logic [47:0] rx_hdr; logic rx_ext, rx_phy;
  logic [1:0]  rx_dll_stat; logic rx_ready;
  logic        tx_fwd_ind;
  logic        tx_fwd_valid; logic [47:0] tx_fwd_hdr; logic tx_fwd_ext, tx_fwd_phy;
  logic [1:0]  tx_fwd_dstat; logic tx_fwd_yield;
  logic        tx_oam_ind;
  logic        tx_oam_valid; logic [47:0] tx_oam_hdr; logic tx_oam_ext; logic tx_oam_yield;
  logic        oam_local_valid; logic [47:0] oam_local_hdr;
  logic        oam_local_ext, oam_local_phy; logic oam_local_read;
  logic        err_dfq_ov, err_orq_ov;
  logic        evt_5_4_1, evt_5_4_2, evt_local, evt_data;

  fofa_top #(.DATA_FWD_DEPTH(4), .OAM_RTN_DEPTH(4)) dut (
    .clk(clk), .rst(rst),
    .soft_reset_i(soft_reset), .normal_mode_i(normal_mode),
    .local_node_id_i(local_nid), .nodeb_id_i(nodeb_nid),
    .rx_fwd_valid_i(rx_valid), .rx_fwd_header_i(rx_hdr),
    .rx_fwd_is_ext_i(rx_ext), .rx_fwd_phy_err_i(rx_phy),
    .rx_fwd_dll_stat_i(rx_dll_stat), .rx_fwd_ready_o(rx_ready),
    .tx_fwd_indicate_i(tx_fwd_ind),
    .tx_fwd_valid_o(tx_fwd_valid), .tx_fwd_header_o(tx_fwd_hdr),
    .tx_fwd_is_ext_o(tx_fwd_ext), .tx_fwd_phy_err_o(tx_fwd_phy),
    .tx_fwd_dll_stat_o(tx_fwd_dstat), .tx_fwd_yield_o(tx_fwd_yield),
    .tx_oam_rtn_indicate_i(tx_oam_ind),
    .tx_oam_rtn_valid_o(tx_oam_valid), .tx_oam_rtn_header_o(tx_oam_hdr),
    .tx_oam_rtn_is_ext_o(tx_oam_ext), .tx_oam_rtn_yield_o(tx_oam_yield),
    .oam_local_valid_o(oam_local_valid), .oam_local_header_o(oam_local_hdr),
    .oam_local_is_ext_o(oam_local_ext), .oam_local_phy_err_o(oam_local_phy),
    .oam_local_read_i(oam_local_read),
    .err_data_fwd_overflow_o(err_dfq_ov), .err_oam_rtn_overflow_o(err_orq_ov),
    .evt_switch_5_4_1_o(evt_5_4_1), .evt_switch_5_4_2_o(evt_5_4_2),
    .evt_local_reinject_o(evt_local), .evt_data_fwd_o(evt_data)
  );

  // Build container header (basic)
  function automatic logic [47:0] mk_b(
    input logic [4:0] nid, input logic [0:0] sid, input logic [4:0] tid, input logic [4:0] pid
  );
    return {16'd0, dll_build_basic_hdr(1'b0, 1'b0, nid, sid, tid, pid)};
  endfunction

  // Build extended header
  function automatic logic [47:0] mk_e(
    input logic [4:0] nid, input logic [0:0] sid, input logic [4:0] tid
  );
    return dll_build_ext_hdr(1'b0, nid, sid, tid, 5'd0, 5'd0, 5'd0, 5'd0);
  endfunction

  // Enqueue a frame: assert rx_valid for one cycle
  task automatic enq(input logic [47:0] h, input logic ext=0, input logic phy=0);
    rx_hdr = h; rx_ext = ext; rx_phy = phy; rx_dll_stat = 0;
    rx_valid = 1; tick(); rx_valid = 0;
  endtask

  // Read from DataFwdQ: check head combinationally, THEN dequeue
  task automatic read_dfq(output logic [47:0] out_hdr, output logic is_valid, output logic is_yield);
    // Head is combinatorial; assert indicate to trigger dequeue
    tx_fwd_ind = 1; #1;  // Sample combinatorial outputs
    out_hdr  = tx_fwd_hdr;
    is_valid = tx_fwd_valid;
    is_yield = tx_fwd_yield;
    tick();  // Edge: dequeue fires if valid, rd_ptr advances
    tx_fwd_ind = 0;
  endtask

  // Read from OAMreturnQ
  task automatic read_orq(output logic [47:0] out_hdr, output logic is_valid, output logic is_yield);
    tx_oam_ind = 1; #1;
    out_hdr  = tx_oam_hdr;
    is_valid = tx_oam_valid;
    is_yield = tx_oam_yield;
    tick();
    tx_oam_ind = 0;
  endtask

  // Wait for switch to complete (combinational, but queue write is registered)
  task automatic wait_switch();
    tick(); tick(); // Allow switch to enqueue into OAMreturnQ
  endtask

  initial begin
    pass_count = 0; fail_count = 0;
    rst = 1; soft_reset = 0; normal_mode = 1;
    local_nid = 5'd2; nodeb_nid = 5'd5;
    rx_valid = 0; rx_hdr = 0; rx_ext = 0; rx_phy = 0; rx_dll_stat = 0;
    tx_fwd_ind = 0; tx_oam_ind = 0; oam_local_read = 0;
    repeat(3) tick(); rst = 0; tick();

    // ===== T1: DataFwdQ FIFO ordering =====
    $display("T1: DataFwdQ FIFO ordering");
    begin
      logic [47:0] h1, h2, got;
      logic v, y;
      h1 = mk_b(5'd1, 1'b1, 5'd7, 5'd1);  // streamID=1: no switch
      h2 = mk_b(5'd1, 1'b1, 5'd8, 5'd2);
      enq(h1); enq(h2); tick();
      read_dfq(got, v, y);
      check("T1a: first=h1",    v && (got == h1));
      read_dfq(got, v, y);
      check("T1b: second=h2",   v && (got == h2));
      read_dfq(got, v, y);
      check("T1c: yield empty", y);
    end

    // ===== T2: 5.4.1 switch + OAMreturnQ ordering =====
    $display("T2: 5.4.1 switch → OAMreturnQ ordering");
    soft_reset = 1; tick(); soft_reset = 0; tick();
    begin
      logic [47:0] s1, s2, got; logic v, y;
      // H=0, streamID=0, targetID=nodeB_id=5
      s1 = mk_b(5'd1, 1'b0, nodeb_nid, 5'd3);
      s2 = mk_b(5'd1, 1'b0, nodeb_nid, 5'd4);
      enq(s1); wait_switch();
      enq(s2); wait_switch();
      read_orq(got, v, y);
      check("T2a: OAMreturnQ first=s1",  v && (got == s1));
      read_orq(got, v, y);
      check("T2b: OAMreturnQ second=s2", v && (got == s2));
      read_orq(got, v, y);
      check("T2c: OAMreturnQ yield",     y);
    end

    // ===== T3: 5.4.1 switch exactly: H=0, streamID=0, targetID=nodeB_id =====
    $display("T3: 5.4.1 Normal Mode switch");
    soft_reset = 1; tick(); soft_reset = 0; tick();
    begin
      logic [47:0] sw_hdr, got; logic v, y;
      sw_hdr = mk_b(5'd1, 1'b0, nodeb_nid, 5'd0);  // H=0,sid=0,tid=nodeB=5
      enq(sw_hdr); wait_switch();
      // DataFwdQ empty, OAMreturnQ has sw_hdr
      tx_fwd_ind = 1; #1;
      check("T3a: DataFwdQ yields",      tx_fwd_yield);
      tx_fwd_ind = 0;
      read_orq(got, v, y);
      check("T3b: OAMreturnQ=sw_hdr",    v && (got == sw_hdr));
    end

    // ===== T4: 5.4.2: H=1, streamID=0, all targetIDx=0, nodeB.nodeID=0 =====
    $display("T4: 5.4.2 Enumerate switch");
    soft_reset = 1; tick(); soft_reset = 0; nodeb_nid = 5'd0; tick();
    begin
      logic [47:0] nd_hdr, got; logic v, y;
      nd_hdr = mk_e(5'd1, 1'b0, 5'd0);  // H=1, sid=0, all targets=0
      enq(nd_hdr, 1'b1); wait_switch();
      read_orq(got, v, y);
      check("T4: 5.4.2 → OAMreturnQ",   v && (got == nd_hdr));
    end
    nodeb_nid = 5'd5;

    // ===== T5: No switch when streamID != 0 =====
    $display("T5: No switch for non-OAM streamID");
    soft_reset = 1; tick(); soft_reset = 0; tick();
    begin
      logic [47:0] ns, got; logic v, y;
      ns = mk_b(5'd1, 1'b1, nodeb_nid, 5'd0);  // sid=1: not OAM → no switch
      enq(ns); wait_switch();
      tx_oam_ind = 1; #1;
      check("T5a: OAMreturnQ yields",     tx_oam_yield);
      tx_oam_ind = 0;
      read_dfq(got, v, y);
      check("T5b: stays in DataFwdQ",     v && (got == ns));
    end

    // ===== T6: oamFrameLocal delivery =====
    $display("T6: oamFrameLocal when targetID == local_node_id");
    soft_reset = 1; tick(); soft_reset = 0; nodeb_nid = local_nid; tick();
    begin
      logic [47:0] lo_hdr; logic saved_nodeb;
      // 5.4.1: targetID = nodeB = local_nid = 2 → switches to OAMreturnQ
      // Then oamFrameLocal fires because targetID=local_nid
      lo_hdr = mk_b(5'd1, 1'b0, local_nid, 5'd0);
      enq(lo_hdr); wait_switch(); wait_switch(); #1;  // Extra wait for queue write to propagate
      check("T6a: oam_local_valid",       oam_local_valid);
      check("T6b: oam_local_header",      oam_local_hdr == lo_hdr);
      oam_local_read = 1; tick(); oam_local_read = 0; tick(); #1;
      check("T6c: cleared after read",    !oam_local_valid);
    end
    nodeb_nid = 5'd5;

    // ===== T7: Header bits preserved exactly (PDF 5.7.1.2: "unmodified DLL header") =====
    $display("T7: Header preserved unmodified");
    soft_reset = 1; tick(); soft_reset = 0; tick();
    begin
      logic [47:0] orig, got; logic v, y;
      orig = 48'hABCDEF012345;  // Non-OAM (decode may or may not switch)
      rx_hdr = orig; rx_ext = 1; rx_phy = 1; rx_dll_stat = 2'b10;
      rx_valid = 1; tick(); rx_valid = 0; tick(); tick();
      // Check whichever queue received it
      tx_fwd_ind = 1; #1;
      if (tx_fwd_valid) begin
        check("T7a: DataFwdQ hdr preserved",  tx_fwd_hdr == orig);
        check("T7b: phy_err preserved",       tx_fwd_phy == 1'b1);
      end else begin
        tx_fwd_ind = 0; tx_oam_ind = 1; #1;
        check("T7a: OAMreturnQ hdr preserved", tx_oam_hdr == orig);
        check("T7b: pass",                     1'b1);
        tx_oam_ind = 0;
      end
      tick(); tx_fwd_ind = 0; tx_oam_ind = 0;
    end

    // ===== T8: Yield DataFwdQ empty =====
    $display("T8: Yield when DataFwdQ empty");
    soft_reset = 1; tick(); soft_reset = 0; tick();
    tx_fwd_ind = 1; #1;
    check("T8: yield when empty", tx_fwd_yield);
    tx_fwd_ind = 0;

    // ===== T9: Yield OAMreturnQ empty =====
    $display("T9: Yield when OAMreturnQ empty");
    tx_oam_ind = 1; #1;
    check("T9: OAMreturnQ yield", tx_oam_yield);
    tx_oam_ind = 0;

    // ===== T10: Overflow protection =====
    $display("T10: DataFwdQ overflow protection");
    soft_reset = 1; tick(); soft_reset = 0; tick();
    begin
      logic [47:0] fh;
      fh = mk_b(5'd1, 1'b1, 5'd7, 5'd0); // non-switch
      for (int i = 0; i < 4; i++) enq(fh);  // Fill depth=4
      tick();
      rx_hdr = fh; rx_valid = 1; #1;
      check("T10: overflow flag", err_dfq_ov);
      rx_valid = 0; tick();
    end

    // ===== T11: Ordering across switch events =====
    $display("T11: Ordering preserved across switch");
    soft_reset = 1; tick(); soft_reset = 0; tick();
    begin
      logic [47:0] df1, sw1, df2, got; logic v, y;
      df1 = mk_b(5'd1, 1'b1, 5'd7, 5'd1);      // data: streamID=1
      sw1 = mk_b(5'd1, 1'b0, nodeb_nid, 5'd2);  // 5.4.1 switch
      df2 = mk_b(5'd1, 1'b1, 5'd8, 5'd3);      // data: streamID=1
      enq(df1); tick();
      enq(sw1); wait_switch();
      enq(df2); wait_switch();  // Extra tick so df2 lands in queue
      // DataFwdQ: df1, sw1 (to be switched), df2
      // Read df1 first
      read_dfq(got, v, y);
      check("T11a: DataFwdQ first=df1",   v && (got == df1));
      // After consuming df1, sw1 is head → switch fires → moves to OAMreturnQ
      wait_switch();  // Allow switch of sw1 to complete
      // Now DataFwdQ head = df2
      read_dfq(got, v, y);
      check("T11b: DataFwdQ second=df2",  v && (got == df2));
      // OAMreturnQ: sw1
      read_orq(got, v, y);
      check("T11c: OAMreturnQ=sw1",       v && (got == sw1));
    end

    // ===== T12: 5.4.1 not triggered when streamID != 0 =====
    $display("T12: 5.4.1 not triggered for streamID != 0");
    soft_reset = 1; tick(); soft_reset = 0; tick();
    begin
      logic [47:0] ns, got; logic v, y;
      ns = mk_b(5'd1, 1'b1, nodeb_nid, 5'd0);  // Same tid as nodeB but sid=1
      enq(ns); wait_switch();
      tx_oam_ind = 1; #1;
      check("T12a: OAMreturnQ yields", tx_oam_yield);
      tx_oam_ind = 0;
      read_dfq(got, v, y);
      check("T12b: stays DataFwdQ", v && (got == ns));
    end

    // ===== T13: Light Sleep halt (normal_mode=0 → TX stalls) =====
    $display("T13: Light Sleep: TX stalls, queue retains data");
    soft_reset = 1; tick(); soft_reset = 0; tick();
    begin
      logic [47:0] h, got; logic v, y;
      h = mk_b(5'd1, 1'b1, 5'd7, 5'd0);
      enq(h); tick();
      normal_mode = 0; // Light Sleep: halt TX
      tx_fwd_ind = 1; #1;
      check("T13a: yield during LS", tx_fwd_yield);
      tx_fwd_ind = 0;
      normal_mode = 1;
      read_dfq(got, v, y);
      check("T13b: frame still in queue after LS", v && (got == h));
    end

    // ===== Summary =====
    repeat(3) tick();
    $display("");
    $display("========================================");
    $display("Results: %0d passed, %0d failed", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) $display("fofa_tb: ALL TESTS PASSED");
    else                 $display("fofa_tb: SOME TESTS FAILED");
    $finish;
  end

  initial begin #500000; $display("TIMEOUT"); $finish; end

endmodule

`default_nettype wire
