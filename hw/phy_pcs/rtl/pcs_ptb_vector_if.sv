`timescale 1ns/1ps
`default_nettype none

// PCS PTB Message Vector Interface
// Spec: Section 4.2.2.3.5 (PTB message), Tables 4-8 and 4-9
//
// The m_ptb<15:0> field is placed at the end of the resync header.
//
// Clock leader TX (Table 4-8):
//   bit 15: PTB command (0=follow, 1=delay reply)
//   bit 14: PTB status  (0=not valid, 1=valid)
//   bits 13:0: TDDstamp (lower 14 bits of PTBclk at moment first sym of first
//              phy block of TDD burst passes MDI — see Section 4.2.8.1.2)
//
// Clock follower TX (Table 4-9):
//   bit 15: reserved (0)
//   bit 14: PTB status (0=not valid, 1=locked to clock leader)
//   bits 13:0: TDDstamp (lower 14 bits of PTBclk at TX moment — Section 4.2.8.2.1)
//
// RX extraction: PTB service consumes m_ptb extracted from received header.

module pcs_ptb_vector_if (
  // TX side: from PTB service
  input  logic [15:0] ptb_m_ptb_tx_i,  // Assembled m_ptb from PTB service

  // TX side: to resync header generator
  output logic [15:0] m_ptb_o,          // Direct pass-through

  // RX side: extracted m_ptb from received resync header
  input  logic [15:0] m_ptb_rx_i,       // From burst synchronizer/header decoder
  input  logic        m_ptb_rx_valid_i,  // Header check passed

  // RX side: to PTB service
  output logic [15:0] ptb_m_ptb_rx_o,   // m_ptb to PTB service
  output logic        ptb_m_ptb_rx_valid_o
);

  // Direct pass-through — no combinational logic needed here
  assign m_ptb_o             = ptb_m_ptb_tx_i;
  assign ptb_m_ptb_rx_o      = m_ptb_rx_i;
  assign ptb_m_ptb_rx_valid_o = m_ptb_rx_valid_i;

endmodule

`default_nettype wire
