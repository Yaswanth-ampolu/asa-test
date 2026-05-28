`timescale 1ns/1ps
`default_nettype none

// PCS CRC32 Calculator
// Spec: Section 4.2.9, Table 4-21 (p120)
//
// Polynomial: 0xF4ACFB13
// Init: 0xFFFFFFFF
// XOR out: 0xFFFFFFFF
// Input data: byte-wise reflected
// Result: reflected
//
// Verified against Table 4-21 reference:
//   Input bytes: 80,55,38,3F,B3,0C,80,0D,82,61,65,71,0B,DF,FF
//   After 15 bytes: CRC32 = B843C1B8

module pcs_crc32
  import asa_pcs_pkg::*;
(
  input  logic        clk,
  input  logic        rst,

  input  logic        init_i,       // Reset to CRC32_INIT
  input  logic        valid_i,      // Process one byte
  input  logic [7:0]  data_i,       // Input byte (un-reflected; module handles reflection)

  output logic [31:0] crc_o,        // Current CRC (intermediate, not finalized)
  output logic [31:0] crc_final_o   // Finalized CRC (reflected + XOR)
);

  logic [31:0] crc_q;

  assign crc_o       = crc_q;
  assign crc_final_o = crc32_finalize(crc_q);

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      crc_q <= CRC32_INIT;
    end else if (init_i) begin
      crc_q <= CRC32_INIT;
    end else if (valid_i) begin
      crc_q <= crc32_byte(crc_q, data_i);
    end
  end

endmodule

`default_nettype wire
