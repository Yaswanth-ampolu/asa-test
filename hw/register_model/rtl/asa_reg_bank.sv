`timescale 1ns/1ps
`default_nettype none

// ASA Domain Register Bank
// Spec: Section 3 (micro-architecture-register-model.md Section 8.3)
//
// Parameterized register bank with RW/RO/SC storage, HW write, saturating
// increment, self-clearing read, and SoftReset selective clear.

module asa_reg_bank
  import asa_reg_pkg::*;
#(
  parameter int unsigned NUM_REGS  = 32,
  parameter int unsigned BASE_ADDR = 0
) (
  input  logic              clk,
  input  logic              rst,
  input  logic              soft_reset,

  // Bus interface
  input  logic              rd_en,
  input  logic              wr_en,
  input  logic [14:0]       addr,
  input  logic [15:0]       wr_data,
  input  logic [15:0]       wr_mask,
  output logic [15:0]       rd_data,
  output logic              valid,

  // Per-register metadata
  input  reg_meta_t [NUM_REGS-1:0] meta,

  // Hardware write port (FSMs write status registers)
  input  logic              hw_wr_en,
  input  logic [14:0]       hw_wr_addr,
  input  logic [15:0]       hw_wr_data,
  input  logic [15:0]       hw_wr_mask,

  // Saturating increment port
  input  logic              inc_en,
  input  logic [14:0]       inc_addr,
  input  logic [3:0]        inc_field_msb,
  input  logic [3:0]        inc_field_lsb
);

  localparam int IDX_W = (NUM_REGS > 1) ? $clog2(NUM_REGS) : 1;

  // Storage
  logic [15:0] regs_q [NUM_REGS];

  // Address hit detection
  logic        bus_hit;
  logic [IDX_W-1:0] bus_idx;

  logic        hw_hit;
  logic [IDX_W-1:0] hw_idx;

  logic        inc_hit;
  logic [IDX_W-1:0] inc_idx;

  always_comb begin
    bus_hit = 1'b0;
    bus_idx = '0;
    if (addr >= BASE_ADDR[14:0] && addr < (BASE_ADDR + NUM_REGS)) begin
      bus_hit = 1'b1;
      bus_idx = (addr - BASE_ADDR[14:0]);
    end

    hw_hit = 1'b0;
    hw_idx = '0;
    if (hw_wr_en && hw_wr_addr >= BASE_ADDR[14:0] && hw_wr_addr < (BASE_ADDR + NUM_REGS)) begin
      hw_hit = 1'b1;
      hw_idx = (hw_wr_addr - BASE_ADDR[14:0]);
    end

    inc_hit = 1'b0;
    inc_idx = '0;
    if (inc_en && inc_addr >= BASE_ADDR[14:0] && inc_addr < (BASE_ADDR + NUM_REGS)) begin
      inc_hit = 1'b1;
      inc_idx = (inc_addr - BASE_ADDR[14:0]);
    end
  end

  // Read output: combinational from current regs_q
  assign valid   = bus_hit && rd_en;
  assign rd_data = bus_hit ? regs_q[bus_idx] : 16'd0;

  // SC clear tracking: clear happens one cycle AFTER the read
  logic sc_clear_pending_q;
  logic [IDX_W-1:0] sc_clear_idx_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      sc_clear_pending_q <= 1'b0;
      sc_clear_idx_q     <= '0;
    end else begin
      sc_clear_pending_q <= rd_en && bus_hit && meta[bus_idx].rw_type == REG_SC;
      sc_clear_idx_q     <= bus_idx;
    end
  end

  // Increment field mask and value
  logic [15:0] inc_field_mask;
  logic [15:0] inc_cur_val;
  logic [15:0] inc_max_val;
  logic [15:0] inc_new_field;

  always_comb begin
    inc_field_mask = 16'd0;
    for (int b = 0; b < 16; b++) begin
      if (b[3:0] >= inc_field_lsb && b[3:0] <= inc_field_msb)
        inc_field_mask[b] = 1'b1;
    end
    inc_cur_val  = (inc_hit ? regs_q[inc_idx] : 16'd0) & inc_field_mask;
    inc_cur_val  = inc_cur_val >> inc_field_lsb;
    inc_max_val  = (16'd1 << (inc_field_msb - inc_field_lsb + 4'd1)) - 16'd1;
    inc_new_field = (inc_cur_val < inc_max_val) ?
                    ((inc_cur_val + 16'd1) << inc_field_lsb) :
                    (inc_cur_val << inc_field_lsb);
  end

  // Register update
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      for (int i = 0; i < NUM_REGS; i++)
        regs_q[i] <= 16'd0;
    end else if (soft_reset) begin
      for (int i = 0; i < NUM_REGS; i++) begin
        if (meta[i].soft_reset_clears)
          regs_q[i] <= 16'd0;
      end
    end else begin
      // Hardware write (highest priority)
      if (hw_hit)
        regs_q[hw_idx] <= (regs_q[hw_idx] & ~hw_wr_mask) | (hw_wr_data & hw_wr_mask);

      // Saturating increment
      if (inc_hit && !(hw_hit && hw_idx == inc_idx))
        regs_q[inc_idx] <= (regs_q[inc_idx] & ~inc_field_mask) | (inc_new_field & inc_field_mask);

      // Bus write
      if (wr_en && bus_hit && meta[bus_idx].rw_type == REG_RW &&
          !(hw_hit && hw_idx == bus_idx))
        regs_q[bus_idx] <= (regs_q[bus_idx] & ~wr_mask) | (wr_data & wr_mask);

      // SC clear-on-read (deferred: clears one cycle after read)
      if (sc_clear_pending_q && !(hw_hit && hw_idx == sc_clear_idx_q))
        regs_q[sc_clear_idx_q] <= 16'd0;
    end
  end

endmodule

`default_nettype wire
