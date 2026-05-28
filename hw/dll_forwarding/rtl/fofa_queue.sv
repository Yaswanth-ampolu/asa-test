`timescale 1ns/1ps
`default_nettype none

// FoFa FIFO Queue
// Generic synchronous FIFO with packed vector storage to avoid Verilator
// unpacked-array propagation issues.
// PDF 5.4 (p169): "each queue just operates as a first-in first-out buffer"

module fofa_queue
  import asa_fofa_pkg::*;
#(
  parameter int unsigned DEPTH = 8
) (
  input  logic        clk,
  input  logic        rst,
  input  logic        flush_i,

  // Enqueue port
  input  logic        wr_en_i,
  input  fofa_entry_t wr_data_i,
  output logic        full_o,

  // Dequeue port
  input  logic        rd_en_i,
  output fofa_entry_t rd_data_o,
  output logic        empty_o,

  output logic [$clog2(DEPTH+1)-1:0] count_o
);

  // Width of one fofa_entry_t (struct packed):
  //   header(48) + is_extended(1) + phy_err(1) + dll_stat(2) + valid(1) = 53 bits
  localparam int unsigned ENTRY_W = 53;
  localparam int unsigned PTR_W   = $clog2(DEPTH);

  // Packed backing store: avoids Verilator unpacked-array propagation issues
  logic [DEPTH*ENTRY_W-1:0] mem_packed_q;

  logic [PTR_W-1:0]              wr_ptr_q, rd_ptr_q;
  logic [$clog2(DEPTH+1)-1:0]   count_q;

  assign full_o  = (count_q == DEPTH[$clog2(DEPTH+1)-1:0]);
  assign empty_o = (count_q == '0);
  assign count_o = count_q;

  // Convert struct to bits for packing
  function automatic logic [ENTRY_W-1:0] entry_to_bits(input fofa_entry_t e);
    return {e.header, e.is_extended, e.phy_err, e.dll_stat, e.valid};
  endfunction

  function automatic fofa_entry_t bits_to_entry(input logic [ENTRY_W-1:0] b);
    fofa_entry_t e;
    e.header      = b[ENTRY_W-1:ENTRY_W-48];  // bits [52:5]
    e.is_extended = b[4];
    e.phy_err     = b[3];
    e.dll_stat    = b[2:1];
    e.valid       = b[0];
    return e;
  endfunction

  // Read head: combinational from packed storage via registered rd_ptr
  assign rd_data_o = bits_to_entry(mem_packed_q[rd_ptr_q*ENTRY_W +: ENTRY_W]);

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      wr_ptr_q   <= '0;
      rd_ptr_q   <= '0;
      count_q    <= '0;
      mem_packed_q <= '0;
    end else if (flush_i) begin
      wr_ptr_q   <= '0;
      rd_ptr_q   <= '0;
      count_q    <= '0;
    end else begin
      if (wr_en_i && !full_o) begin
        mem_packed_q[wr_ptr_q*ENTRY_W +: ENTRY_W] <= entry_to_bits(wr_data_i);
        wr_ptr_q <= wr_ptr_q + 1;
      end
      if (rd_en_i && !empty_o) begin
        rd_ptr_q <= rd_ptr_q + 1;
      end
      // Update count
      case ({wr_en_i && !full_o, rd_en_i && !empty_o})
        2'b10: count_q <= count_q + 1;
        2'b01: count_q <= count_q - 1;
        default: begin end
      endcase
    end
  end

endmodule

`default_nettype wire
