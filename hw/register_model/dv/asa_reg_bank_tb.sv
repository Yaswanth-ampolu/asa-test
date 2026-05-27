`timescale 1ns/1ps
`default_nettype none

// Testbench for asa_reg_bank
// Tests: RW, RO, SC, SoftReset, HW write, saturating increment

module asa_reg_bank_tb;
  import asa_reg_pkg::*;

  localparam int NUM_REGS  = 8;
  localparam int BASE_ADDR = 100;

  logic clk, rst, soft_reset;
  logic rd_en, wr_en;
  logic [14:0] addr;
  logic [15:0] wr_data, wr_mask;
  logic [15:0] rd_data;
  logic valid;

  reg_meta_t [NUM_REGS-1:0] meta;

  logic hw_wr_en;
  logic [14:0] hw_wr_addr;
  logic [15:0] hw_wr_data, hw_wr_mask;

  logic inc_en;
  logic [14:0] inc_addr;
  logic [3:0] inc_field_msb, inc_field_lsb;

  asa_reg_bank #(.NUM_REGS(NUM_REGS), .BASE_ADDR(BASE_ADDR)) dut (.*);

  always #5 clk = ~clk;
  int err_count = 0;

  task automatic check(input logic cond, input string msg);
    if (!cond) begin $error("FAIL: %s (rd_data=0x%04x)", msg, rd_data); err_count++; end
  endtask

  task automatic tick(); @(posedge clk); #1; endtask

  // Combinational read: set addr+rd_en, wait one tick, check result
  task automatic do_read(input logic [14:0] a);
    addr = a; rd_en = 1;
    tick();  // posedge: SC clear fires, but rd_data was combinational PRE-edge
    rd_en = 0;
  endtask

  task automatic do_write(input logic [14:0] a, input logic [15:0] d);
    addr = a; wr_data = d; wr_en = 1;
    tick();
    wr_en = 0;
  endtask

  task automatic do_hw_write(input logic [14:0] a, input logic [15:0] d);
    hw_wr_en = 1; hw_wr_addr = a; hw_wr_data = d; hw_wr_mask = 16'hFFFF;
    tick();
    hw_wr_en = 0;
  endtask

  initial begin
    clk = 0; rst = 1; soft_reset = 0;
    rd_en = 0; wr_en = 0; addr = 0; wr_data = 0; wr_mask = 16'hFFFF;
    hw_wr_en = 0; hw_wr_addr = 0; hw_wr_data = 0; hw_wr_mask = 16'hFFFF;
    inc_en = 0; inc_addr = 0; inc_field_msb = 0; inc_field_lsb = 0;

    // Reg 0 (100): RW, status (cleared by soft reset)
    meta[0] = '{rw_type: REG_RW, access: REG_ACCESS_O, privilege: REG_PRIV_RID, soft_reset_clears: 1'b1};
    // Reg 1 (101): RO (HW write only)
    meta[1] = '{rw_type: REG_RO, access: REG_ACCESS_O, privilege: REG_PRIV_RID, soft_reset_clears: 1'b0};
    // Reg 2 (102): SC (clear on read)
    meta[2] = '{rw_type: REG_SC, access: REG_ACCESS_O, privilege: REG_PRIV_RID, soft_reset_clears: 1'b1};
    // Reg 3 (103): RW config (preserved on soft reset)
    meta[3] = '{rw_type: REG_RW, access: REG_ACCESS_O, privilege: REG_PRIV_RID, soft_reset_clears: 1'b0};
    // Reg 4-7: RW counters
    for (int i = 4; i < NUM_REGS; i++)
      meta[i] = '{rw_type: REG_RW, access: REG_ACCESS_O, privilege: REG_PRIV_RID, soft_reset_clears: 1'b1};

    repeat(2) tick();
    rst = 0;
    tick();

    // === TEST 1: RW write and read ===
    do_write(15'd100, 16'hCAFE);
    do_read(15'd100);
    check(rd_data == 16'hCAFE, "T1: RW write/read");
    check(valid == 1, "T1: valid");

    // === TEST 2: RO ignores bus write ===
    do_hw_write(15'd101, 16'hBEEF);
    do_write(15'd101, 16'h1111);  // should be ignored
    do_read(15'd101);
    check(rd_data == 16'hBEEF, "T2: RO ignores bus write");

    // === TEST 3: SC returns value then clears ===
    do_hw_write(15'd102, 16'hDEAD);
    do_read(15'd102);  // first read: returns value
    check(rd_data == 16'hDEAD, "T3a: SC returns value");
    do_read(15'd102);  // second read: cleared
    check(rd_data == 16'h0000, "T3b: SC cleared after read");

    // === TEST 4: SoftReset selective clear ===
    do_write(15'd103, 16'hF00D);  // config (preserved)
    do_write(15'd100, 16'h9999);  // status (cleared)
    soft_reset = 1; tick(); soft_reset = 0; tick();
    do_read(15'd100);
    check(rd_data == 16'h0000, "T4a: status cleared");
    do_read(15'd103);
    check(rd_data == 16'hF00D, "T4b: config preserved");

    // === TEST 5: Saturating increment ===
    do_write(15'd104, 16'h00FD);
    // Increment field [7:0]
    inc_en = 1; inc_addr = 15'd104; inc_field_msb = 4'd7; inc_field_lsb = 4'd0;
    tick(); inc_en = 0;
    do_read(15'd104);
    check(rd_data[7:0] == 8'hFE, "T5a: inc to 0xFE");

    inc_en = 1; tick(); inc_en = 0;
    do_read(15'd104);
    check(rd_data[7:0] == 8'hFF, "T5b: inc to 0xFF");

    inc_en = 1; tick(); inc_en = 0;
    do_read(15'd104);
    check(rd_data[7:0] == 8'hFF, "T5c: saturates at 0xFF");

    // === TEST 6: Masked write ===
    do_write(15'd100, 16'h0000);  // clear first
    wr_mask = 16'hFF00;
    do_write(15'd100, 16'hAB00);
    wr_mask = 16'hFFFF;
    do_read(15'd100);
    check(rd_data == 16'hAB00, "T6: masked write upper byte");

    // === TEST 7: Out-of-range ===
    do_read(15'd200);
    check(valid == 0, "T7: out-of-range no valid");

    // === SUMMARY ===
    if (err_count == 0)
      $display("asa_reg_bank_tb: ALL TESTS PASSED");
    else
      $display("asa_reg_bank_tb: %0d TESTS FAILED", err_count);
    $finish;
  end

endmodule

`default_nettype wire
