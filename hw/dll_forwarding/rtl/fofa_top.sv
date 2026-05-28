`timescale 1ns/1ps
`default_nettype none

// DLL Forwarding Fabric Top
// Spec: Section 5.4, PDF pages 169-170, Figure 5-5
//
// Two-queue model per Figure 5-5:
//   DataForwardingQueue: receives DLP_RX.forwardUnit from DLL demux (5.7.1.2)
//   OAMreturnQueue:      receives containers switched from DataFwdQ per 5.4.1/5.4.2
//
// Queue-switch logic per Section 5.4:
//   5.4.1: HeaderType=0, streamID=0, targetID=nodeID(nodeB) -> OAMreturnQueue
//   5.4.2: HeaderType=1, streamID=0, targetIDx=0, nodeID(nodeB)=0 -> OAMreturnQueue
//   Otherwise: FIFO behavior in each queue
//
// TX side behavior (5.6.1.5, 5.6.1.6):
//   DLP_TX.forwardUnit: FoFa provides header+payload directly to DLL (header UNMODIFIED)
//   DLP_TX.oamFrameLocal: when OAMreturnQ has container with targetID==local nodeID
//   DLP_TX.yield: when no data available
//
// IMPLEMENTATION ASSUMPTION: OAM return traffic is prioritized over data-forward
// traffic when the TX scheduler offers a slot to prevent OAM starvation.

module fofa_top
  import asa_dll_pkg::*;
  import asa_fofa_pkg::*;
#(
  parameter int unsigned DATA_FWD_DEPTH = 8,
  parameter int unsigned OAM_RTN_DEPTH  = 8
) (
  input  logic              clk,
  input  logic              rst,

  // Control
  input  logic              soft_reset_i,     // Flush queues
  input  logic              normal_mode_i,    // Enable TX dequeue (stopped during light sleep)
  input  logic [4:0]        local_node_id_i,  // Own nodeID (register 2.0001)
  input  logic [4:0]        nodeb_id_i,       // Far-side nodeB nodeID (0=undiscovered)

  // =========================================================================
  // DLP_RX input from DLL demux
  // Implements DLP_RX.forwardUnit (Section 5.7.1.2)
  // Header is UNMODIFIED (PDF 5.7.1.2: "Header ... unmodified DLL header")
  // =========================================================================
  input  logic              rx_fwd_valid_i,   // DLL delivers container to FoFa
  input  logic [47:0]       rx_fwd_header_i,  // Unmodified container header
  input  logic              rx_fwd_is_ext_i,  // 1=extended header
  input  logic              rx_fwd_phy_err_i, // phyLStat
  input  logic [1:0]        rx_fwd_dll_stat_i,// dllStat
  output logic              rx_fwd_ready_o,   // FoFa can accept

  // =========================================================================
  // DLP_TX Data Forward output (to DLL TX scheduler for far-side DLP_TX)
  // Implements DLP_TX.forwardUnit (Section 5.6.1.6)
  // =========================================================================
  input  logic              tx_fwd_indicate_i, // DLL requests container for Data Forward slot
  output logic              tx_fwd_valid_o,    // FoFa has Data Forward container
  output logic [47:0]       tx_fwd_header_o,   // Unmodified header (DLL uses directly)
  output logic              tx_fwd_is_ext_o,
  output logic              tx_fwd_phy_err_o,
  output logic [1:0]        tx_fwd_dll_stat_o,
  output logic              tx_fwd_yield_o,    // DLP_TX.yield (no data)

  // =========================================================================
  // DLP_TX OAM Return output (to DLL TX scheduler for near-side OAM return)
  // Switched containers that don't match local delivery
  // =========================================================================
  input  logic              tx_oam_rtn_indicate_i,
  output logic              tx_oam_rtn_valid_o,
  output logic [47:0]       tx_oam_rtn_header_o,
  output logic              tx_oam_rtn_is_ext_o,
  output logic              tx_oam_rtn_yield_o,

  // =========================================================================
  // DLP_TX.oamFrameLocal output (Section 5.6.1.5)
  // Delivers OAM return containers addressed to local node into DLL receive path
  // =========================================================================
  output logic              oam_local_valid_o,
  output logic [47:0]       oam_local_header_o,
  output logic              oam_local_is_ext_o,
  output logic              oam_local_phy_err_o,
  input  logic              oam_local_read_i,   // DLL consumed the local OAM frame

  // =========================================================================
  // Status/error outputs
  // =========================================================================
  output logic              err_data_fwd_overflow_o, // DataFwdQ full on enqueue
  output logic              err_oam_rtn_overflow_o,  // OAMreturnQ full on switch
  output logic              evt_switch_5_4_1_o,      // 5.4.1 switch occurred
  output logic              evt_switch_5_4_2_o,      // 5.4.2 switch occurred
  output logic              evt_local_reinject_o,     // oamFrameLocal triggered
  output logic              evt_data_fwd_o            // Normal data forward dequeued
);

  // =========================================================================
  // DataForwardingQueue
  // =========================================================================
  fofa_entry_t  dfq_wr_data, dfq_rd_data;
  logic         dfq_wr_en, dfq_rd_en;
  logic         dfq_full, dfq_empty;

  fofa_queue #(.DEPTH(DATA_FWD_DEPTH)) u_data_fwd_q (
    .clk(clk), .rst(rst), .flush_i(soft_reset_i),
    .wr_en_i(dfq_wr_en), .wr_data_i(dfq_wr_data), .full_o(dfq_full),
    .rd_en_i(dfq_rd_en), .rd_data_o(dfq_rd_data), .empty_o(dfq_empty),
    .count_o()
  );

  // =========================================================================
  // OAMreturnQueue
  // =========================================================================
  fofa_entry_t  orq_wr_data, orq_rd_data;
  logic         orq_wr_en, orq_rd_en;
  logic         orq_full, orq_empty;

  fofa_queue #(.DEPTH(OAM_RTN_DEPTH)) u_oam_rtn_q (
    .clk(clk), .rst(rst), .flush_i(soft_reset_i),
    .wr_en_i(orq_wr_en), .wr_data_i(orq_wr_data), .full_o(orq_full),
    .rd_en_i(orq_rd_en), .rd_data_o(orq_rd_data), .empty_o(orq_empty),
    .count_o()
  );

  // =========================================================================
  // Switch Controller
  // =========================================================================
  fofa_sw_decision_e sw_decision;
  fofa_reason_e      sw_reason;
  logic              sw_consume_dfq;

  fofa_switch_ctrl u_sw_ctrl (
    .clk(clk), .rst(rst),
    .local_node_id_i(local_node_id_i),
    .nodeb_id_i(nodeb_id_i),
    .data_fwd_head_i(dfq_rd_data),
    .data_fwd_empty_i(dfq_empty),
    .decision_o(sw_decision),
    .reason_o(sw_reason),
    .consume_data_fwd_o(sw_consume_dfq)
  );

  // =========================================================================
  // Local Reinjection Monitor
  // =========================================================================
  logic oam_local_valid_int;
  fofa_entry_t oam_local_data_int;
  logic consume_orq_local;

  fofa_local_reinject u_local_reinj (
    .clk(clk), .rst(rst),
    .local_node_id_i(local_node_id_i),
    .oam_rtn_head_i(orq_rd_data),
    .oam_rtn_empty_i(orq_empty),
    .oam_local_valid_o(oam_local_valid_int),
    .oam_local_data_o(oam_local_data_int),
    .oam_local_read_i(oam_local_read_i),
    .consume_oam_rtn_o(consume_orq_local)
  );

  // =========================================================================
  // RX input path: enqueue into DataForwardingQueue
  // =========================================================================
  always_comb begin
    dfq_wr_data.header      = rx_fwd_header_i;
    dfq_wr_data.is_extended = rx_fwd_is_ext_i;
    dfq_wr_data.phy_err     = rx_fwd_phy_err_i;
    dfq_wr_data.dll_stat    = rx_fwd_dll_stat_i;
    dfq_wr_data.valid       = 1'b1;
    dfq_wr_en               = rx_fwd_valid_i && !dfq_full;
    rx_fwd_ready_o          = !dfq_full;
    err_data_fwd_overflow_o = rx_fwd_valid_i && dfq_full;
  end

  // =========================================================================
  // Switch execution: dequeue from DataFwdQ, enqueue into OAMreturnQ
  // This is a "move" operation — atomic dequeue+enqueue
  // =========================================================================
  logic switch_exec;  // Actually perform the switch this cycle
  assign switch_exec = sw_consume_dfq &&
                       (sw_decision == SW_MOVE_OAM_RTN) &&
                       !dfq_empty && !orq_full;

  always_comb begin
    orq_wr_data  = dfq_rd_data;
    orq_wr_en    = switch_exec;
    err_oam_rtn_overflow_o = sw_consume_dfq &&
                             (sw_decision == SW_MOVE_OAM_RTN) && orq_full;
  end

  // =========================================================================
  // DataForwardingQueue TX dequeue
  // Called when DLL TX scheduler offers a Data Forward slot AND no switch needed
  // IMPLEMENTATION ASSUMPTION: switch has priority over TX dequeue
  // =========================================================================
  logic dfq_tx_dequeue;
  assign dfq_tx_dequeue = tx_fwd_indicate_i && !dfq_empty && normal_mode_i &&
                          (sw_decision == SW_KEEP_DATA_FWD);

  always_comb begin
    // dfq_rd_en: either switch consuming OR TX dequeuing
    dfq_rd_en = switch_exec || dfq_tx_dequeue;

    tx_fwd_valid_o    = !dfq_empty && (sw_decision == SW_KEEP_DATA_FWD) && normal_mode_i;
    tx_fwd_header_o   = dfq_rd_data.header;
    tx_fwd_is_ext_o   = dfq_rd_data.is_extended;
    tx_fwd_phy_err_o  = dfq_rd_data.phy_err;
    tx_fwd_dll_stat_o = dfq_rd_data.dll_stat;
    tx_fwd_yield_o    = tx_fwd_indicate_i && (dfq_empty || !normal_mode_i ||
                                              sw_decision != SW_KEEP_DATA_FWD);
  end

  // =========================================================================
  // OAMreturnQueue TX dequeue (for non-local containers → far-side OAM Return)
  // IMPLEMENTATION ASSUMPTION: OAM return has higher priority than data forward
  // =========================================================================
  logic orq_tx_dequeue;
  assign orq_tx_dequeue = tx_oam_rtn_indicate_i && !orq_empty && !oam_local_valid_int
                          && normal_mode_i;

  always_comb begin
    // orq_rd_en: either local reinjection consuming OR OAM return TX dequeuing
    orq_rd_en = consume_orq_local || orq_tx_dequeue;

    tx_oam_rtn_valid_o    = !orq_empty && !oam_local_valid_int && normal_mode_i;
    tx_oam_rtn_header_o   = orq_rd_data.header;
    tx_oam_rtn_is_ext_o   = orq_rd_data.is_extended;
    tx_oam_rtn_yield_o    = tx_oam_rtn_indicate_i &&
                             (orq_empty || oam_local_valid_int || !normal_mode_i);
  end

  // =========================================================================
  // oamFrameLocal output
  // =========================================================================
  assign oam_local_valid_o   = oam_local_valid_int;
  assign oam_local_header_o  = oam_local_data_int.header;
  assign oam_local_is_ext_o  = oam_local_data_int.is_extended;
  assign oam_local_phy_err_o = oam_local_data_int.phy_err;

  // =========================================================================
  // Event outputs
  // =========================================================================
  assign evt_switch_5_4_1_o  = switch_exec && (sw_reason == REASON_5_4_1);
  assign evt_switch_5_4_2_o  = switch_exec && (sw_reason == REASON_5_4_2);
  assign evt_local_reinject_o= consume_orq_local;
  assign evt_data_fwd_o      = dfq_tx_dequeue;

endmodule

`default_nettype wire
