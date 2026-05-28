`timescale 1ns/1ps
`default_nettype none

// DLL RX Demultiplexer
// Spec: Section 5.3.2, PDF p167-168
//
// Implements the six routing cases exactly as specified:
//   5.3.2.1  Local Sink:         targetIDx == NodeID && targetIDx != 0
//   5.3.2.2  Forward:            targetIDx != NodeID && targetIDx != 0
//   5.3.2.3  Receive Node-Disc:  hdrType=1 & streamID=0 & targetIDx=0 & own nodeID=0
//   5.3.2.4  Distribute ND:      hdrType=1 & streamID=0 & targetIDx=0 & no DMX2 match
//   5.3.2.5  Receive Self-Ann:   hdrType=1 & streamID=0 & targetID0=1
//   5.3.2.6  Forward Self-Ann:   hdrType=1 & streamID=0 & targetIDx=1
//
// Error handling (PDF p167):
//   "If the header cannot be decoded or does not match any of the cases,
//    2.2210.15:8 shall be incremented and the container discarded."

module dll_rx_demux
  import asa_dll_pkg::*;
(
  input  logic clk,
  input  logic rst,

  // Parsed header inputs (from dll_header_parse)
  input  logic             hdr_valid_i,
  input  logic             header_type_i,
  input  logic [0:0]       stream_id_i,
  input  logic [4:0]       node_id_i,       // source nodeID from header
  input  logic [4:0]       target_id0_i,
  input  logic [4:0]       target_id1_i,
  input  logic [4:0]       target_id2_i,
  input  logic [4:0]       target_id3_i,
  input  logic [4:0]       packet_id_i,

  // Own nodeID (from register 2.0001)
  input  logic [4:0]       own_node_id_i,

  // DmxTable1 lookup interface (nodeID.streamID -> DLP_RX_ID)
  // Caller provides the lookup result for the current header's nodeID.streamID
  output logic [4:0]       dmx1_lookup_node_id_o,
  output logic [0:0]       dmx1_lookup_stream_id_o,
  input  logic             dmx1_hit_i,
  input  logic [5:0]       dmx1_dlp_rx_id_i,

  // DmxTable2 lookup interface (targetID -> DLP_RX_ID for forwarding)
  output logic [4:0]       dmx2_lookup_target_id_o,
  input  logic             dmx2_hit_i,
  input  logic [5:0]       dmx2_dlp_rx_id_i,

  // Routing decision output
  output dll_rx_route_e    route_o,
  output logic [5:0]       dlp_rx_id_o,     // Target DLP_RX port
  output logic             route_valid_o,

  // Packet ID check result (for local sink case)
  // Caller computes expected and provides result
  input  logic             pkt_id_ok_i,
  input  logic             pkt_id_dup_i,    // too low: duplicate
  input  logic             pkt_id_miss_i,   // too high: missing

  // Security: is this container secured (KeySwitch set)?
  input  logic             key_switch_i,

  // Error counter increment outputs (SC counters, one-cycle pulses)
  output logic             err_hdr_decode_o,    // 2.2210[15:8]
  output logic             err_dup_pktid_o,     // 2.2210[7:0]
  output logic             err_miss_pktid_o,    // 2.2211[15:8]
  output logic             err_dmx_local_o,     // 2.2147[15:8]
  output logic             err_dmx_fwd_o        // 2.2147[7:0]
);

  // DMX table lookups are driven combinationally
  assign dmx1_lookup_node_id_o   = node_id_i;
  assign dmx1_lookup_stream_id_o = stream_id_i;

  // DMX2 lookup: try each targetID in priority order
  // For simplicity, try target_id0 first; full multi-target is checked below
  assign dmx2_lookup_target_id_o = target_id0_i;

  // =========================================================================
  // Routing logic (Section 5.3.2, PDF p167-168)
  // Both 5.3.2.1 (local) and 5.3.2.2 (forward) must be checked for ALL targetIDs.
  // We check target_id0 as primary; multicast would iterate all targets.
  // IMPLEMENTATION ASSUMPTION: For this implementation we check target_id0 and
  // the first valid extended header target. Full multicast delivery (all targets
  // simultaneously) requires external sequencing for each targetID — flagged as
  // architectural stub.
  // =========================================================================

  // Helper: check if any targetID matches NodeID (local sink condition)
  logic target0_local, target1_local, target2_local, target3_local;
  logic target0_fwd, target1_fwd, target2_fwd, target3_fwd;
  logic any_local, any_forward;
  logic any_target_nonzero;

  always_comb begin
    target0_local = (target_id0_i == own_node_id_i) && (target_id0_i != 5'd0);
    target1_local = header_type_i && (target_id1_i == own_node_id_i) && (target_id1_i != 5'd0);
    target2_local = header_type_i && (target_id2_i == own_node_id_i) && (target_id2_i != 5'd0);
    target3_local = header_type_i && (target_id3_i == own_node_id_i) && (target_id3_i != 5'd0);

    target0_fwd = (target_id0_i != own_node_id_i) && (target_id0_i != 5'd0);
    target1_fwd = header_type_i && (target_id1_i != own_node_id_i) && (target_id1_i != 5'd0);
    target2_fwd = header_type_i && (target_id2_i != own_node_id_i) && (target_id2_i != 5'd0);
    target3_fwd = header_type_i && (target_id3_i != own_node_id_i) && (target_id3_i != 5'd0);

    any_local   = target0_local | target1_local | target2_local | target3_local;
    any_forward = target0_fwd   | target1_fwd   | target2_fwd   | target3_fwd;

    any_target_nonzero = (target_id0_i != 5'd0) ||
                         (header_type_i && (target_id1_i != 5'd0 ||
                                            target_id2_i != 5'd0 ||
                                            target_id3_i != 5'd0));
  end

  always_comb begin
    route_o          = ROUTE_DISCARD;
    dlp_rx_id_o      = 6'd0;
    route_valid_o    = 1'b0;
    err_hdr_decode_o = 1'b0;
    err_dup_pktid_o  = 1'b0;
    err_miss_pktid_o = 1'b0;
    err_dmx_local_o  = 1'b0;
    err_dmx_fwd_o    = 1'b0;

    if (hdr_valid_i) begin
      // Security pre-processing: if key_switch set, route to security ingress first
      if (key_switch_i) begin
        route_o       = ROUTE_SEC_INGRESS;
        route_valid_o = 1'b1;
      end

      // === Case 5.3.2.3: Receive Node-Discover ===
      // hdrType=1, streamID=0, all targetIDx=0, own nodeID=0
      else if (header_type_i && stream_id_i == 1'b0 &&
               !any_target_nonzero && own_node_id_i == 5'd0) begin
        route_o       = ROUTE_LOCAL_OAM;
        dlp_rx_id_o   = 6'd0;  // DLP_RX_ID=0 is OAM
        route_valid_o = 1'b1;
      end

      // === Case 5.3.2.5: Receive Self-Announce ===
      // hdrType=1, streamID=0, targetID0=1
      else if (header_type_i && stream_id_i == 1'b0 && target_id0_i == 5'd1) begin
        route_o       = ROUTE_LOCAL_OAM;
        dlp_rx_id_o   = 6'd0;
        route_valid_o = 1'b1;
      end

      // === Case 5.3.2.6: Forward Self-Announce ===
      // hdrType=1, streamID=0, any targetIDx=1 (but not own node)
      else if (header_type_i && stream_id_i == 1'b0 &&
               (target_id1_i == 5'd1 || target_id2_i == 5'd1 || target_id3_i == 5'd1)) begin
        if (dmx2_hit_i) begin
          route_o       = ROUTE_FORWARD;
          dlp_rx_id_o   = dmx2_dlp_rx_id_i;
          route_valid_o = 1'b1;
        end else begin
          route_o          = ROUTE_DISCARD;
          err_dmx_fwd_o    = 1'b1;   // 2.2147.7:0
          route_valid_o    = 1'b1;
        end
      end

      // === Case 5.3.2.4: Distribute Node-Discover ===
      // hdrType=1, streamID=0, all targetIDx=0, no DMX2 match
      else if (header_type_i && stream_id_i == 1'b0 && !any_target_nonzero) begin
        if (dmx2_hit_i) begin
          route_o       = ROUTE_FORWARD;
          dlp_rx_id_o   = dmx2_dlp_rx_id_i;
          route_valid_o = 1'b1;
        end else begin
          route_o       = ROUTE_DISCARD;
          route_valid_o = 1'b1;
        end
      end

      // === Case 5.3.2.1: Local Sink ===
      else if (any_local) begin
        if (dmx1_hit_i) begin
          route_o       = ROUTE_LOCAL_ASEP;
          dlp_rx_id_o   = dmx1_dlp_rx_id_i;
          route_valid_o = 1'b1;
          // PacketID checks
          if (pkt_id_dup_i)  err_dup_pktid_o  = 1'b1;
          if (pkt_id_miss_i) err_miss_pktid_o = 1'b1;
        end else begin
          route_o         = ROUTE_DISCARD;
          err_dmx_local_o = 1'b1;   // nodeID.streamID not in DmxTable1
          route_valid_o   = 1'b1;
        end
      end

      // === Case 5.3.2.2: Forward ===
      else if (any_forward) begin
        if (dmx2_hit_i) begin
          route_o       = ROUTE_FORWARD;
          dlp_rx_id_o   = dmx2_dlp_rx_id_i;
          route_valid_o = 1'b1;
        end else begin
          route_o       = ROUTE_DISCARD;
          err_dmx_fwd_o = 1'b1;    // targetID unset in DmxTable2
          route_valid_o = 1'b1;
        end
      end

      // === No case matched ===
      else begin
        route_o          = ROUTE_DISCARD;
        err_hdr_decode_o = 1'b1;   // 2.2210.15:8
        route_valid_o    = 1'b1;
      end
    end
  end

endmodule

`default_nettype wire
