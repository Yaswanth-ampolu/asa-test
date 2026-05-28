`timescale 1ns/1ps
`default_nettype none

// FoFa Local OAM Reinjection
// Spec: Section 5.6.1.5 (PDF p186)
//
// "Always, when OAMreturnQueue is not empty and the targetID in the container
//  header is equal to the local nodeID."
//
// Effect (5.6.1.5.3): "DLL takes data the same way as from PLP_RX and feeds it
//  to the Data Link Layer Receive Process (5.3.1)"
// Additionally: "If nodeID=0, DLL copies FoFa ReturnPath onto register OAMdmxTX"
//
// This module monitors the OAMreturnQueue head and asserts oamFrameLocal_valid
// when targetID == local_node_id. The actual data is passed through; this module
// just drives the valid/consumed interface.

module fofa_local_reinject
  import asa_dll_pkg::*;
  import asa_fofa_pkg::*;
(
  input  logic         clk,
  input  logic         rst,

  // Own nodeID
  input  logic [4:0]   local_node_id_i,

  // OAMreturnQueue head
  input  fofa_entry_t  oam_rtn_head_i,
  input  logic         oam_rtn_empty_i,

  // DLP_TX.oamFrameLocal output (to DLL receive process)
  output logic         oam_local_valid_o,  // Signal: local OAM frame available
  output fofa_entry_t  oam_local_data_o,   // The container
  input  logic         oam_local_read_i,   // DLL acknowledged / dequeued

  // Dequeue from OAMreturnQueue
  output logic         consume_oam_rtn_o
);

  // The condition is purely combinational per the spec:
  // "Always, when OAMreturnQueue is not empty and targetID == local nodeID"
  logic is_local;
  assign is_local = (!oam_rtn_empty_i) && oam_rtn_head_i.valid &&
                    fofa_is_oam_local(oam_rtn_head_i.header, local_node_id_i);

  assign oam_local_valid_o  = is_local;
  assign oam_local_data_o   = oam_rtn_head_i;
  // Consume when DLL acknowledges receipt
  assign consume_oam_rtn_o  = is_local && oam_local_read_i;

endmodule

`default_nettype wire
