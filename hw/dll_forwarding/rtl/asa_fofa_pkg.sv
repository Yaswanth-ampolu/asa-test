`default_nettype none

// ASA Forwarding Fabric (FoFa) Package
// Source of truth: ASA Technical Specification v2.0, Section 5.4
// PDF pages 169-170, Figure 5-5
//
// All queue-switch conditions verified against PDF pp169-170:
//   5.4.1 Normal Mode switch:   HeaderType=0, streamID=0, targetID=nodeID(nodeB)
//   5.4.2 Enumerate switch:     HeaderType=1, streamID=0, targetIDx=0, nodeID(nodeB)=0
//
// oamFrameLocal trigger verified against PDF p186 (5.6.1.5.2):
//   "Always, when OAMreturnQueue is not empty and targetID == local nodeID"
//
// DLP_RX.forwardUnit effect verified against PDF p187 (5.7.1.2.3):
//   "Size, header and data are put on the DataForwardQueue" (header UNMODIFIED)

package asa_fofa_pkg;
  import asa_dll_pkg::*;

  // =========================================================================
  // Queue entry: carries the unmodified container from DLL demux
  // Header is preserved exactly as received (PDF 5.7.1.2: "unmodified DLL header")
  // =========================================================================
  typedef struct packed {
    logic [47:0] header;       // Unmodified DLL header (up to 6 bytes)
    logic        is_extended;  // 1=6-byte header, 0=4-byte
    logic        phy_err;      // phyLStat from 4.7.1.1
    logic [1:0]  dll_stat;     // 00=decode_good, 01=dup_pktid, 10=miss_pktid
    logic        valid;
  } fofa_entry_t;

  // =========================================================================
  // Queue switch decision (output of fofa_switch_ctrl)
  // =========================================================================
  typedef enum logic [1:0] {
    SW_KEEP_DATA_FWD  = 2'd0, // Stay in DataForwardingQueue
    SW_MOVE_OAM_RTN   = 2'd1, // Move to OAMreturnQueue (5.4.1 or 5.4.2)
    SW_LOCAL_REINJECT = 2'd2, // oamFrameLocal: targetID == local nodeID
    SW_DISCARD        = 2'd3  // Malformed/overflow
  } fofa_sw_decision_e;

  // =========================================================================
  // Reason codes for status outputs
  // =========================================================================
  typedef enum logic [2:0] {
    REASON_NONE         = 3'd0,
    REASON_5_4_1        = 3'd1, // Normal Mode OAM switch (PDF 5.4.1)
    REASON_5_4_2        = 3'd2, // Enumerate OAM switch (PDF 5.4.2)
    REASON_OAM_LOCAL    = 3'd3, // Local OAM reinjection (PDF 5.6.1.5.2)
    REASON_OVERFLOW     = 3'd4, // Queue full on enqueue
    REASON_DATA_FWD     = 3'd5  // Normal data forwarding
  } fofa_reason_e;

  // =========================================================================
  // Switch condition check functions
  // PDF 5.4.1: HeaderType=0, streamID=0, targetID=nodeB_id
  // =========================================================================
  function automatic logic fofa_check_5_4_1(
    input logic [47:0] hdr,
    input logic [4:0]  nodeb_id    // nodeID of far-side (nodeB)
  );
    logic hdr_type;
    logic [0:0] stream_id;
    logic [4:0] target_id0;
    hdr_type   = dll_header_type(hdr);
    stream_id  = dll_stream_id(hdr);
    target_id0 = dll_target_id(hdr);
    return (!hdr_type) && (stream_id == 1'b0) && (target_id0 == nodeb_id);
  endfunction

  // PDF 5.4.2: HeaderType=1, streamID=0, targetIDx=0, nodeB.nodeID=0
  function automatic logic fofa_check_5_4_2(
    input logic [47:0] hdr,
    input logic [4:0]  nodeb_id    // nodeID of far-side (0 = undiscovered)
  );
    logic hdr_type;
    logic [0:0] stream_id;
    logic [4:0] t0, t1, t2, t3;
    logic all_targets_zero;
    hdr_type  = dll_header_type(hdr);
    stream_id = dll_stream_id(hdr);
    t0 = dll_target_id(hdr);
    t1 = dll_target_id1(hdr);
    t2 = dll_target_id2(hdr);
    t3 = dll_target_id3(hdr);
    all_targets_zero = (t0 == 5'd0) && (t1 == 5'd0) && (t2 == 5'd0) && (t3 == 5'd0);
    return hdr_type && (stream_id == 1'b0) && all_targets_zero && (nodeb_id == 5'd0);
  endfunction

  // oamFrameLocal condition: targetID == local nodeID (PDF 5.6.1.5.2)
  function automatic logic fofa_is_oam_local(
    input logic [47:0] hdr,
    input logic [4:0]  local_node_id
  );
    logic [4:0] t0;
    t0 = dll_target_id(hdr);
    return (t0 == local_node_id) && (local_node_id != 5'd0);
  endfunction

endpackage

`default_nettype wire
