`timescale 1ns/1ps
`default_nettype none

// FoFa Switch Controller
// Inspects the head of DataForwardingQueue and decides whether to:
//   - Keep it in DataForwardingQueue (forward to nodeB)
//   - Move it to OAMreturnQueue (switch)
//   - Mark it for oamFrameLocal reinjection
//
// Conditions (PDF p169-170):
//   5.4.1 Normal Mode:  HeaderType=0, streamID=0, targetID=nodeID(nodeB)
//   5.4.2 Enumerate:    HeaderType=1, streamID=0, targetIDx=0, nodeID(nodeB)=0
//   oamFrameLocal:      targetID == local_node_id (PDF 5.6.1.5.2)
//
// The switch happens atomically: dequeue from DataFwdQ, enqueue into OAMreturnQ
// (or mark for local reinjection). The FoFa is a "conditionally switching queue"
// as labeled in Figure 5-5.

module fofa_switch_ctrl
  import asa_dll_pkg::*;
  import asa_fofa_pkg::*;
(
  input  logic         clk,
  input  logic         rst,

  // Configuration
  input  logic [4:0]   local_node_id_i,   // Own nodeID (register 2.0001)
  input  logic [4:0]   nodeb_id_i,        // Far-side nodeB nodeID (0=undiscovered)

  // DataForwardingQueue head inspection
  input  fofa_entry_t  data_fwd_head_i,
  input  logic         data_fwd_empty_i,

  // Decision output (combinational)
  output fofa_sw_decision_e decision_o,
  output fofa_reason_e      reason_o,
  output logic              consume_data_fwd_o  // Dequeue from DataFwdQ
);

  always_comb begin
    decision_o          = SW_KEEP_DATA_FWD;
    reason_o            = REASON_NONE;
    consume_data_fwd_o  = 1'b0;

    if (!data_fwd_empty_i && data_fwd_head_i.valid) begin
      // 5.4.1: Normal Mode switch to OAMreturnQueue
      // Note: oamFrameLocal is NOT decided here — it fires separately from
      // fofa_local_reinject monitoring the OAMreturnQueue head after switch.
      // Per PDF 5.6.1.5.2: "when OAMreturnQueue is not empty and targetID == local nodeID"
      if (fofa_check_5_4_1(data_fwd_head_i.header, nodeb_id_i)) begin
        decision_o         = SW_MOVE_OAM_RTN;
        reason_o           = REASON_5_4_1;
        consume_data_fwd_o = 1'b1;
      end
      // 5.4.2: Enumerate switch (nodeB not yet discovered)
      else if (fofa_check_5_4_2(data_fwd_head_i.header, nodeb_id_i)) begin
        decision_o         = SW_MOVE_OAM_RTN;
        reason_o           = REASON_5_4_2;
        consume_data_fwd_o = 1'b1;
      end
      else begin
        // Normal data forwarding — keep in DataForwardingQueue
        decision_o = SW_KEEP_DATA_FWD;
        reason_o   = REASON_DATA_FWD;
      end
    end
  end

endmodule

`default_nettype wire
