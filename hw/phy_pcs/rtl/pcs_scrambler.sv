`timescale 1ns/1ps
`default_nettype none

// PCS Additive Side-Stream Scrambler / Descrambler
// Spec: Section 4.2.5, Figures 4-12, 4-13
//
// The PCS scrambler is additive (XOR of data with LFSR output stream).
// Same module is used for both scramble and descramble (additive property).
//
// For SG1/2/3 downstream and all upstream: single-bit output S0
//   tx_phy_block_scr<MSB> = tx_phy_block<MSB> XOR S0
//   Scrambler advances one bit per symbol.
//
// For SG4/5 downstream: dual-bit outputs S0, S1
//   tx_phy_block_scr<MSB>   = tx_phy_block<MSB>   XOR S1
//   tx_phy_block_scr<MSB-1> = tx_phy_block<MSB-1> XOR S0
//   Scrambler advances once per two bits (one PAM4 symbol).
//
// The scrambler state is HELD during resync header and quiet gap (PDF p108).

module pcs_scrambler
  import asa_pcs_pkg::*;
(
  input  logic        clk,
  input  logic        rst,

  // Control
  input  logic        init_i,        // Load initial state
  input  logic [1:0]  link_id_i,     // Selects init value
  input  logic        advance_i,     // Shift one step
  input  logic        is_downstream_i, // Selects Dn vs Up polynomial
  input  logic        is_pam4_i,     // SG4/5 dual-bit mode

  // Data path (one symbol at a time for now)
  input  logic        data_in_msb_i,    // MSB of current pair (PAM4) or single bit
  input  logic        data_in_lsb_i,    // LSB of current pair (PAM4 only)
  output logic        data_out_msb_o,
  output logic        data_out_lsb_o,

  // Scrambler state output (for debug/status)
  output logic [22:0] state_o
);

  logic [22:0] state_q;
  logic [22:0] state_next;

  assign state_o = state_q;

  // Compute next state based on direction
  always_comb begin
    if (is_downstream_i)
      state_next = dn_scrambler_step(state_q);
    else
      state_next = up_scrambler_step(state_q);
  end

  // Output tap values
  logic s0, s1;
  always_comb begin
    if (is_downstream_i) begin
      s0 = dn_s0(state_q);
      s1 = dn_s1(state_q);
    end else begin
      s0 = up_s0(state_q);
      s1 = 1'b0; // Upstream is always PAM2, no S1
    end
  end

  // XOR scrambling
  always_comb begin
    if (is_pam4_i) begin
      // SG4/5: MSB XOR S1, LSB XOR S0
      data_out_msb_o = data_in_msb_i ^ s1;
      data_out_lsb_o = data_in_lsb_i ^ s0;
    end else begin
      // SG1/2/3 or Upstream: single bit XOR S0
      data_out_msb_o = data_in_msb_i ^ s0;
      data_out_lsb_o = data_in_lsb_i; // not used in PAM2 mode
    end
  end

  // State register
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q <= scrambler_init(2'd0);
    end else if (init_i) begin
      state_q <= scrambler_init(link_id_i);
    end else if (advance_i) begin
      state_q <= state_next;
    end
  end

endmodule

`default_nettype wire
