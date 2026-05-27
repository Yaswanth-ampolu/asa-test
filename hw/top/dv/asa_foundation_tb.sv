`timescale 1ns/1ps
`default_nettype none

// ASA Shared Foundation Testbench
// Tests: register access, interface contracts, error aggregation, node lifecycle
//
// This testbench exercises:
//   1. Register address decoding and routing
//   2. Access control (L vs O, RID privilege, RO protection)
//   3. Bit-field read/write
//   4. Error event aggregation and IRQ flag generation
//   5. Counter increment requests
//   6. Integration with Node State Machine outputs
//
// Build: iverilog -g2012 -o tb/asa_foundation_tb.vvp \
//          rtl/asa_node_pkg.sv rtl/asa_reg_pkg.sv rtl/asa_intf_pkg.sv \
//          rtl/asa_error_pkg.sv rtl/asa_reg_access.sv rtl/asa_error_aggregator.sv \
//          tb/asa_foundation_tb.sv

module asa_foundation_tb;
  import asa_reg_pkg::*;
  import asa_error_pkg::*;

  logic clk, rst;
  always #5 clk = ~clk;

  int err_count = 0;

  task automatic check(input logic cond, input string msg);
    if (!cond) begin
      $error("FAIL: %s (time=%0t)", msg, $time);
      err_count++;
    end
  endtask

  task automatic tick();
    @(posedge clk); #1;
  endtask

  // =========================================================================
  // Register Access Layer instance
  // =========================================================================
  reg_req_t   reg_req;
  reg_resp_t  reg_resp;

  // Domain bank stubs (simple echo-back for testing)
  logic        dom1_rd_en, dom1_wr_en;
  logic [14:0] dom1_addr;
  logic [15:0] dom1_wr_data, dom1_wr_mask;
  logic [15:0] dom1_rd_data;
  logic        dom1_valid;

  logic        dom2_rd_en, dom2_wr_en;
  logic [14:0] dom2_addr;
  logic [15:0] dom2_wr_data, dom2_wr_mask;
  logic [15:0] dom2_rd_data;
  logic        dom2_valid;

  logic        dom3_rd_en, dom3_wr_en;
  logic [14:0] dom3_addr;
  logic [15:0] dom3_wr_data, dom3_wr_mask;
  logic [15:0] dom3_rd_data;
  logic        dom3_valid;

  logic        dom4_rd_en, dom4_wr_en;
  logic [5:0]  dom4_subdomain;
  logic [14:0] dom4_addr;
  logic [15:0] dom4_wr_data, dom4_wr_mask;
  logic [15:0] dom4_rd_data;
  logic        dom4_valid;

  logic        dom5_rd_en, dom5_wr_en;
  logic [5:0]  dom5_subdomain;
  logic [14:0] dom5_addr;
  logic [15:0] dom5_wr_data, dom5_wr_mask;
  logic [15:0] dom5_rd_data;
  logic        dom5_valid;

  reg_meta_t   meta_stub;
  logic        meta_valid_stub;
  logic [4:0]  local_node_id;

  asa_reg_access #(
    .NUM_DOM1_REGS(32),
    .NUM_DOM2_REGS(64),
    .NUM_DOM3_REGS(3)
  ) u_reg_access (
    .clk(clk), .rst(rst),
    .req_i(reg_req), .resp_o(reg_resp),
    .dom1_rd_en(dom1_rd_en), .dom1_wr_en(dom1_wr_en),
    .dom1_addr(dom1_addr), .dom1_wr_data(dom1_wr_data),
    .dom1_wr_mask(dom1_wr_mask), .dom1_rd_data(dom1_rd_data),
    .dom1_valid(dom1_valid),
    .dom2_rd_en(dom2_rd_en), .dom2_wr_en(dom2_wr_en),
    .dom2_addr(dom2_addr), .dom2_wr_data(dom2_wr_data),
    .dom2_wr_mask(dom2_wr_mask), .dom2_rd_data(dom2_rd_data),
    .dom2_valid(dom2_valid),
    .dom3_rd_en(dom3_rd_en), .dom3_wr_en(dom3_wr_en),
    .dom3_addr(dom3_addr), .dom3_wr_data(dom3_wr_data),
    .dom3_wr_mask(dom3_wr_mask), .dom3_rd_data(dom3_rd_data),
    .dom3_valid(dom3_valid),
    .dom4_rd_en(dom4_rd_en), .dom4_wr_en(dom4_wr_en),
    .dom4_subdomain(dom4_subdomain), .dom4_addr(dom4_addr),
    .dom4_wr_data(dom4_wr_data), .dom4_wr_mask(dom4_wr_mask),
    .dom4_rd_data(dom4_rd_data), .dom4_valid(dom4_valid),
    .dom5_rd_en(dom5_rd_en), .dom5_wr_en(dom5_wr_en),
    .dom5_subdomain(dom5_subdomain), .dom5_addr(dom5_addr),
    .dom5_wr_data(dom5_wr_data), .dom5_wr_mask(dom5_wr_mask),
    .dom5_rd_data(dom5_rd_data), .dom5_valid(dom5_valid),
    .meta_i(meta_stub), .meta_valid_i(meta_valid_stub),
    .local_node_id(local_node_id)
  );

  // Domain bank stubs: simply echo back a known pattern
  assign dom1_rd_data = 16'hA001;
  assign dom1_valid   = dom1_rd_en;
  assign dom2_rd_data = 16'hB002;
  assign dom2_valid   = dom2_rd_en;
  assign dom3_rd_data = 16'hC003;
  assign dom3_valid   = dom3_rd_en;
  assign dom4_rd_data = 16'hD004;
  assign dom4_valid   = dom4_rd_en;
  assign dom5_rd_data = 16'hE005;
  assign dom5_valid   = dom5_rd_en;

  // =========================================================================
  // Error Aggregator instance
  // =========================================================================
  localparam int NUM_ERR_PORTS = 4;
  err_event_t [NUM_ERR_PORTS-1:0] err_events;
  logic [13:0]  irq_set;
  cnt_inc_req_t cnt_inc;
  status_snapshot_t status_snap;

  asa_error_aggregator #(.NUM_ERR_PORTS(NUM_ERR_PORTS)) u_err_agg (
    .clk(clk), .rst(rst), .soft_reset(1'b0),
    .err_events_i(err_events),
    .irq_set_o(irq_set),
    .cnt_inc_o(cnt_inc),
    .node_state_i(4'd3),   // Normal
    .com_ready_i(1'b1),
    .ptb_locked_i(1'b1),
    .sec_policy_i(2'b01),
    .link_losses_i(6'd0),
    .node_id_i(5'd2),
    .status_o(status_snap)
  );

  // =========================================================================
  // Helper task to build register requests
  // =========================================================================
  task automatic reg_read(
    input reg_domain_e dom,
    input logic [5:0]  sub,
    input logic [14:0] addr,
    input logic        oam,
    input logic [4:0]  src_nid
  );
    reg_req.addr.domain    = dom;
    reg_req.addr.subdomain = sub;
    reg_req.addr.addr      = addr;
    reg_req.bitsel.valid   = 0;
    reg_req.bitsel.msb     = 0;
    reg_req.bitsel.lsb     = 0;
    reg_req.wr_data        = 16'd0;
    reg_req.wr_en          = 0;
    reg_req.rd_en          = 1;
    reg_req.oam_path       = oam;
    reg_req.src_node_id    = src_nid;
    reg_req.authenticated  = 0;
  endtask

  task automatic reg_write(
    input reg_domain_e dom,
    input logic [5:0]  sub,
    input logic [14:0] addr,
    input logic [15:0] data,
    input logic        oam,
    input logic [4:0]  src_nid
  );
    reg_req.addr.domain    = dom;
    reg_req.addr.subdomain = sub;
    reg_req.addr.addr      = addr;
    reg_req.bitsel.valid   = 0;
    reg_req.bitsel.msb     = 0;
    reg_req.bitsel.lsb     = 0;
    reg_req.wr_data        = data;
    reg_req.wr_en          = 1;
    reg_req.rd_en          = 0;
    reg_req.oam_path       = oam;
    reg_req.src_node_id    = src_nid;
    reg_req.authenticated  = 0;
  endtask

  task automatic clear_req();
    reg_req.addr.domain    = REG_DOM_USER;
    reg_req.addr.subdomain = 6'd0;
    reg_req.addr.addr      = 15'd0;
    reg_req.bitsel.valid   = 0;
    reg_req.bitsel.msb     = 4'd0;
    reg_req.bitsel.lsb     = 4'd0;
    reg_req.wr_data        = 16'd0;
    reg_req.wr_en          = 0;
    reg_req.rd_en          = 0;
    reg_req.oam_path       = 0;
    reg_req.src_node_id    = 5'd0;
    reg_req.authenticated  = 0;
  endtask

  // =========================================================================
  // Test sequence
  // =========================================================================
  initial begin
    clk = 0; rst = 1;
    reg_req.addr.domain    = REG_DOM_USER;
    reg_req.addr.subdomain = 6'd0;
    reg_req.addr.addr      = 15'd0;
    reg_req.bitsel.valid   = 0;
    reg_req.bitsel.msb     = 4'd0;
    reg_req.bitsel.lsb     = 4'd0;
    reg_req.wr_data        = 16'd0;
    reg_req.wr_en          = 0;
    reg_req.rd_en          = 0;
    reg_req.oam_path       = 0;
    reg_req.src_node_id    = 5'd0;
    reg_req.authenticated  = 0;
    meta_stub.rw_type   = REG_RW;
    meta_stub.access    = REG_ACCESS_O;
    meta_stub.privilege = REG_PRIV_NONE;
    meta_stub.soft_reset_clears = 1'b0;
    meta_valid_stub = 1'b1;
    local_node_id = 5'd1; // We are root
    err_events[0].valid = 0; err_events[0].source = ERR_SRC_LOCAL_PHY;
    err_events[0].severity = ERR_SEV_WARN; err_events[0].code = 4'd0;
    err_events[1].valid = 0; err_events[1].source = ERR_SRC_LOCAL_PHY;
    err_events[1].severity = ERR_SEV_WARN; err_events[1].code = 4'd0;
    err_events[2].valid = 0; err_events[2].source = ERR_SRC_LOCAL_PHY;
    err_events[2].severity = ERR_SEV_WARN; err_events[2].code = 4'd0;
    err_events[3].valid = 0; err_events[3].source = ERR_SRC_LOCAL_PHY;
    err_events[3].severity = ERR_SEV_WARN; err_events[3].code = 4'd0;

    // Configure metadata for testing
    meta_stub.rw_type   = REG_RW;
    meta_stub.access    = REG_ACCESS_O;
    meta_stub.privilege = REG_PRIV_RID;
    meta_stub.soft_reset_clears = 1'b0;

    repeat (3) tick();
    rst = 0;

    // ==================================================================
    // TEST 1: Read Domain 1 register (PHY)
    // ==================================================================
    reg_read(REG_DOM_PHY, 6'd0, 15'd6, 1'b0, 5'd1); // Local read of 1.0006
    #1;
    check(dom1_rd_en == 1, "T1: dom1 read enabled");
    check(dom1_addr == 15'd6, "T1: dom1 addr = 6");
    check(reg_resp.rd_data == 16'hA001, "T1: read data from dom1");
    check(reg_resp.ack == 1, "T1: ack asserted");
    check(reg_resp.err_access == 0, "T1: no access error");
    clear_req(); #1;

    // ==================================================================
    // TEST 2: Read Domain 2 register (DLL)
    // ==================================================================
    reg_read(REG_DOM_DLL, 6'd0, 15'd2200, 1'b1, 5'd1); // OAM read of PTBclk
    #1;
    check(dom2_rd_en == 1, "T2: dom2 read enabled");
    check(dom2_addr == 15'd2200, "T2: dom2 addr = 2200");
    check(reg_resp.rd_data == 16'hB002, "T2: read data from dom2");
    clear_req(); #1;

    // ==================================================================
    // TEST 3: Read Domain 3 (Security)
    // ==================================================================
    reg_read(REG_DOM_SEC, 6'd0, 15'd1, 1'b0, 5'd1);
    #1;
    check(dom3_rd_en == 1, "T3: dom3 read enabled");
    check(reg_resp.rd_data == 16'hC003, "T3: read data from dom3");
    clear_req(); #1;

    // ==================================================================
    // TEST 4: Read Domain 4 (ASE) with subdomain
    // ==================================================================
    reg_read(REG_DOM_ASE, 6'd5, 15'd4, 1'b1, 5'd1); // OAM read of 4.5.0004
    #1;
    check(dom4_rd_en == 1, "T4: dom4 read enabled");
    check(dom4_subdomain == 6'd5, "T4: subdomain = 5");
    check(dom4_addr == 15'd4, "T4: dom4 addr = 4");
    check(reg_resp.rd_data == 16'hD004, "T4: read data from dom4");
    clear_req(); #1;

    // ==================================================================
    // TEST 5: Read Domain 5 (ASD)
    // ==================================================================
    reg_read(REG_DOM_ASD, 6'd10, 15'd1, 1'b1, 5'd1);
    #1;
    check(dom5_rd_en == 1, "T5: dom5 read enabled");
    check(dom5_subdomain == 6'd10, "T5: subdomain = 10");
    check(reg_resp.rd_data == 16'hE005, "T5: read data from dom5");
    clear_req(); #1;

    // ==================================================================
    // TEST 6: Invalid subdomain (0) for ASE -> error
    // ==================================================================
    reg_read(REG_DOM_ASE, 6'd0, 15'd4, 1'b1, 5'd1);
    #1;
    check(reg_resp.err_addr == 1, "T6: invalid subdomain 0 -> addr error");
    check(dom4_rd_en == 0, "T6: dom4 not activated");
    clear_req(); #1;

    // ==================================================================
    // TEST 7: Access control - L-only register denied via OAM
    // ==================================================================
    meta_stub.access = REG_ACCESS_L; // Switch to local-only
    reg_read(REG_DOM_PHY, 6'd0, 15'd106, 1'b1, 5'd1); // OAM path
    #1;
    check(reg_resp.err_access == 1, "T7: L-only register denied via OAM");
    check(dom1_rd_en == 0, "T7: dom1 not activated");
    clear_req(); #1;
    meta_stub.access = REG_ACCESS_O; // Restore

    // ==================================================================
    // TEST 8: Access control - RID check (non-root denied)
    // ==================================================================
    reg_read(REG_DOM_PHY, 6'd0, 15'd6, 1'b1, 5'd2); // OAM from node 2 (not root)
    #1;
    check(reg_resp.err_access == 1, "T8: non-root denied RID register");
    clear_req(); #1;

    // ==================================================================
    // TEST 9: Write to RO register denied
    // ==================================================================
    meta_stub.rw_type = REG_RO;
    reg_write(REG_DOM_PHY, 6'd0, 15'd6, 16'hBEEF, 1'b0, 5'd1);
    #1;
    check(reg_resp.err_access == 1, "T9: write to RO register denied");
    check(dom1_wr_en == 0, "T9: dom1 write not activated");
    clear_req(); #1;
    meta_stub.rw_type = REG_RW; // Restore

    // ==================================================================
    // TEST 10: Write with bit-field mask
    // ==================================================================
    reg_req.addr.domain    = REG_DOM_DLL;
    reg_req.addr.subdomain = 6'd0;
    reg_req.addr.addr      = 15'd1;
    reg_req.bitsel.valid   = 1;
    reg_req.bitsel.msb     = 4'd4;
    reg_req.bitsel.lsb     = 4'd0;
    reg_req.wr_data        = 16'h001F;
    reg_req.wr_en          = 1;
    reg_req.rd_en          = 0;
    reg_req.oam_path       = 0;
    reg_req.src_node_id    = 5'd1;
    reg_req.authenticated  = 0;
    #1;
    check(dom2_wr_en == 1, "T10: dom2 write enabled");
    check(dom2_wr_mask == 16'h001F, "T10: write mask = bits 4:0");
    clear_req(); #1;

    // ==================================================================
    // TEST 11: Bit-field read extracts correct bits
    // ==================================================================
    reg_req.addr.domain    = REG_DOM_DLL;
    reg_req.addr.subdomain = 6'd0;
    reg_req.addr.addr      = 15'd1;
    reg_req.bitsel.valid   = 1;
    reg_req.bitsel.msb     = 4'd7;
    reg_req.bitsel.lsb     = 4'd4;
    reg_req.wr_data        = 16'd0;
    reg_req.wr_en          = 0;
    reg_req.rd_en          = 1;
    reg_req.oam_path       = 0;
    reg_req.src_node_id    = 5'd1;
    reg_req.authenticated  = 0;
    #1;
    // dom2_rd_data = 0xB002 = 0b1011_0000_0000_0010
    // bits 7:4 = 0b0000 shifted right by 4 = 0x0000
    check(reg_resp.rd_data == 16'h0000, "T11: bit-field read extracts [7:4]");
    clear_req(); #1;

    // ==================================================================
    // TEST 12: Error aggregator - OAM error sets IRQ flag
    // ==================================================================
    err_events[0].valid    = 1;
    err_events[0].source   = ERR_SRC_OAM;
    err_events[0].severity = ERR_SEV_DROP;
    err_events[0].code     = OAM_ERR_HDR_DECODE;
    tick();
    err_events[0].valid = 0;
    check(irq_set[11] == 1, "T12: OAM IRQ flag (bit 11) set");

    // ==================================================================
    // TEST 13: Error aggregator - Security error sets IRQ flag
    // ==================================================================
    err_events[1].valid    = 1;
    err_events[1].source   = ERR_SRC_SECURITY;
    err_events[1].severity = ERR_SEV_DROP;
    err_events[1].code     = SEC_ERR_DROP_RX;
    tick();
    err_events[1].valid = 0;
    check(irq_set[7] == 1, "T13: Security IRQ flag (bit 7) set");

    // ==================================================================
    // TEST 14: Error aggregator - counter increment request generated
    // ==================================================================
    err_events[2].valid    = 1;
    err_events[2].source   = ERR_SRC_OAM;
    err_events[2].severity = ERR_SEV_DROP;
    err_events[2].code     = OAM_ERR_HDR_DECODE;
    #1;
    check(cnt_inc.valid == 1, "T14: counter increment request valid");
    check(cnt_inc.reg_addr == 15'd2208, "T14: target is OAMerrors1 (2.2208)");
    check(cnt_inc.field_msb == 4'd15, "T14: field MSB = 15");
    check(cnt_inc.field_lsb == 4'd8, "T14: field LSB = 8");
    err_events[2].valid = 0;
    tick();

    // ==================================================================
    // TEST 15: Status snapshot reflects inputs
    // ==================================================================
    check(status_snap.node_state == 4'd3, "T15: snapshot node_state = Normal");
    check(status_snap.com_ready == 1, "T15: snapshot com_ready = 1");
    check(status_snap.ptb_locked == 1, "T15: snapshot ptb_locked = 1");
    check(status_snap.sec_policy == 2'b01, "T15: snapshot sec_policy = auth");
    check(status_snap.node_id == 5'd2, "T15: snapshot node_id = 2");

    // ==================================================================
    // TEST 16: Multiple IRQ flags accumulate (sticky)
    // ==================================================================
    err_events[3].valid    = 1;
    err_events[3].source   = ERR_SRC_DLL_RX;
    err_events[3].severity = ERR_SEV_WARN;
    err_events[3].code     = DLL_RX_ERR_CRC;
    tick();
    err_events[3].valid = 0;
    check(irq_set[10] == 1, "T16: DLL RX flag set");
    check(irq_set[11] == 1, "T16: OAM flag still set (sticky)");
    check(irq_set[7] == 1, "T16: Security flag still set (sticky)");

    // ==================================================================
    // SUMMARY
    // ==================================================================
    if (err_count == 0) begin
      $display("asa_foundation_tb: ALL %0d TESTS PASSED", 16);
    end else begin
      $display("asa_foundation_tb: %0d TESTS FAILED", err_count);
    end
    $finish;
  end

endmodule

`default_nettype wire
