`timescale 1ns/1ps
`default_nettype none

// DLL Mapper/Demux Top
// Spec: Section 5, PDF p162-170
//
// Connects TX mapper, RX demux, header build/parse, and security interface.
// Parameters sized for implementation (not spec max of 64 DLP ports).

module dll_top
  import asa_dll_pkg::*;
#(
  parameter int unsigned MAX_MAPPER_LINES = 64,
  parameter int unsigned MAX_DMX1_ENTRIES = 64,  // DmxTable1: 64 DLP_RX_IDs
  parameter int unsigned MAX_DMX2_ENTRIES = 30   // DmxTable2: targetIDs 2-31
) (
  input  logic              clk,
  input  logic              rst,

  // =========================================================================
  // Control
  // =========================================================================
  input  logic              soft_reset_i,        // Reset counter to CounterMin
  input  logic              normal_mode_i,        // Node in Normal Mode (enable TX/RX)
  input  logic              mapper_init_i,        // Set counter=CounterMin (StartTDD)
  input  logic [15:0]       start_tdd_linemin_i,  // From StartTDD CAD
  input  logic [15:0]       start_tdd_linemax_i,

  // =========================================================================
  // Own node configuration (from register model)
  // =========================================================================
  input  logic [4:0]        own_node_id_i,       // Register 2.0001
  input  logic [15:0]       counter_min_i,       // 2.0142
  input  logic [15:0]       counter_max_i,       // 2.0143
  input  logic [15:0]       line_min_i,          // 2.0144
  input  logic [15:0]       line_max_i,          // 2.0145

  // Mapper table write interface (from register bank)
  input  logic              mapper_tbl_wr_en_i,
  input  logic [$clog2(MAX_MAPPER_LINES)-1:0] mapper_tbl_wr_addr_i,
  input  mapper_line_t      mapper_tbl_wr_data_i,

  // DmxTable1: DLP_RX_ID -> {nodeID, streamID} (for local sink lookup)
  input  logic [10:0]       dmx1_table_i [0:MAX_DMX1_ENTRIES-1],  // {nodeID(4:0),streamID(0)}
  // DmxTable2: targetID -> DLP_RX_ID (for forwarding lookup)
  input  logic [5:0]        dmx2_table_i [0:MAX_DMX2_ENTRIES-1],  // DLP_RX_ID per targetID
  input  logic              dmx2_valid_i  [0:MAX_DMX2_ENTRIES-1],  // entry is valid

  // =========================================================================
  // PCS TX trigger: one pulse per container TX opportunity
  // =========================================================================
  input  logic              pcs_tx_trigger_i,

  // =========================================================================
  // DLP_TX interface (to OAM / ASEP / FoFa)
  // =========================================================================
  // indicateSlot: DLL asks selected port to provide data
  output logic [5:0]        dlp_tx_indicate_id_o,
  output dll_slot_size_e    dlp_tx_indicate_size_o,
  output logic              dlp_tx_indicate_valid_o,

  // Response from ASEP: dataUnit or yield
  input  logic              dlp_tx_data_valid_i,   // dataUnit received
  input  logic              dlp_tx_yield_i,         // yield (no data)

  // Response from OAM: oamUnit
  input  logic              dlp_tx_oam_valid_i,
  input  logic [4:0]        dlp_tx_oam_target_id_i,
  input  logic [4:0]        dlp_tx_oam_packet_id_i,
  input  logic              dlp_tx_oam_nd_en_i,
  input  logic [4:0]        dlp_tx_oam_target_id1_i,
  input  logic [4:0]        dlp_tx_oam_target_id2_i,
  input  logic [4:0]        dlp_tx_oam_target_id3_i,

  // FoFa: forwardUnit (pre-built header)
  input  logic              dlp_tx_fwd_valid_i,
  input  logic [47:0]       dlp_tx_fwd_hdr_i,      // Pre-built header from FoFa

  // =========================================================================
  // TX container output to PCS
  // =========================================================================
  output logic              tx_container_valid_o,
  output logic [47:0]       tx_hdr_o,
  output logic              tx_is_extended_o,
  output dll_tx_src_e       tx_src_o,

  // =========================================================================
  // PCS RX interface: received container
  // =========================================================================
  input  logic              rx_container_valid_i,
  input  logic [47:0]       rx_hdr_raw_i,           // 6 bytes from received container
  input  logic              rx_key_switch_i,         // KeySwitch from received header

  // =========================================================================
  // DLP_RX output (to OAM / ASEP / FoFa)
  // =========================================================================
  output dll_rx_route_e     rx_route_o,
  output logic [5:0]        rx_dlp_rx_id_o,
  output logic              rx_route_valid_o,

  // OAM RX delivery
  output logic              rx_to_oam_valid_o,
  output logic [47:0]       rx_to_oam_hdr_o,

  // ASEP RX delivery
  output logic              rx_to_asep_valid_o,
  output logic [5:0]        rx_to_asep_dlp_rx_id_o,
  output logic [47:0]       rx_to_asep_hdr_o,

  // FoFa RX delivery
  output logic              rx_to_fwd_valid_o,
  output logic [5:0]        rx_to_fwd_dlp_rx_id_o,
  output logic [47:0]       rx_to_fwd_hdr_o,

  // =========================================================================
  // Packet ID tracking (per DLP_RX_ID, from register 4/5.i.0001)
  // Caller provides expected and receives update
  // =========================================================================
  output logic [5:0]        pktid_check_dlp_rx_id_o,
  output logic [4:0]        pktid_received_o,
  input  logic              pktid_ok_i,
  input  logic              pktid_dup_i,
  input  logic              pktid_miss_i,

  // =========================================================================
  // ASEP TX packet ID increment (per DLP_TX_ID)
  // =========================================================================
  output logic [5:0]        pktid_tx_dlp_tx_id_o,
  output logic              pktid_tx_incr_o,

  // =========================================================================
  // Error counter outputs (one-cycle pulses to register bank / error aggregator)
  // =========================================================================
  output logic              err_hdr_decode_o,
  output logic              err_dup_pktid_o,
  output logic              err_miss_pktid_o,
  output logic              err_dmx_local_o,
  output logic              err_dmx_fwd_o,
  output logic              err_mapper_err_o,
  output logic              err_addr_err_o,

  // Counter register readback
  output logic [15:0]       dll_counter_o       // Register 2.0141
);

  // =========================================================================
  // TX Mapper
  // =========================================================================
  logic        mapper_result_valid;
  logic [5:0]  mapper_dlp_tx_sel;
  logic        mapper_init_combined;

  assign mapper_init_combined = mapper_init_i | soft_reset_i;

  dll_tx_mapper #(.MAX_LINES(MAX_MAPPER_LINES)) u_mapper (
    .clk            (clk),
    .rst            (rst),
    .init_i         (mapper_init_combined),
    .eval_trigger_i (pcs_tx_trigger_i),
    .enable_i       (normal_mode_i),
    .counter_min_i  (counter_min_i),
    .counter_max_i  (counter_max_i),
    .line_min_i     (line_min_i),
    .line_max_i     (line_max_i),
    .tbl_wr_en_i    (mapper_tbl_wr_en_i),
    .tbl_wr_addr_i  (mapper_tbl_wr_addr_i),
    .tbl_wr_data_i  (mapper_tbl_wr_data_i),
    .result_valid_o (mapper_result_valid),
    .dlp_tx_id_sel_o(mapper_dlp_tx_sel),
    .counter_o      (dll_counter_o),
    .mapper_err_o   (err_mapper_err_o),
    .mapper_err_id_o()
  );

  // =========================================================================
  // TX Header Builder
  // =========================================================================
  logic [47:0] tx_hdr_built;
  logic        tx_is_ext_built;
  dll_tx_src_e tx_src_q;
  logic [4:0]  asep_pkt_id;

  // DLLaddrtable lookup: for selected DLP_TX_ID, get target IDs
  // IMPLEMENTATION STUB: for now only OAM (DLP_TX_ID=0) path is full; ASEP uses zeros
  // Real impl needs to read DLLaddrtable[mapper_dlp_tx_sel] from register bank
  logic [4:0]  asep_target_id0_wire;
  logic [4:0]  asep_target_id1_wire, asep_target_id2_wire, asep_target_id3_wire;
  logic        asep_t1v, asep_t2v, asep_t3v;
  assign asep_target_id0_wire = 5'd0;   // STUB: real impl reads from DLLaddrtable
  assign asep_target_id1_wire = 5'd0;
  assign asep_target_id2_wire = 5'd0;
  assign asep_target_id3_wire = 5'd0;
  assign asep_t1v = 1'b0;
  assign asep_t2v = 1'b0;
  assign asep_t3v = 1'b0;
  assign asep_pkt_id = 5'd0;           // STUB: real impl reads fullPacketID[4:0]
  assign err_addr_err_o = 1'b0;        // STUB

  dll_header_build u_hdr_build (
    .tx_src_i             (tx_src_q),
    .own_node_id_i        (own_node_id_i),
    .stream_id_i          (mapper_dlp_tx_sel[0]),
    .asep_target_id0_i    (asep_target_id0_wire),
    .asep_target_id1_i    (asep_target_id1_wire),
    .asep_target_id2_i    (asep_target_id2_wire),
    .asep_target_id3_i    (asep_target_id3_wire),
    .asep_target1_valid_i (asep_t1v),
    .asep_target2_valid_i (asep_t2v),
    .asep_target3_valid_i (asep_t3v),
    .asep_packet_id_i     (asep_pkt_id),
    .oam_target_id_i      (dlp_tx_oam_target_id_i),
    .oam_packet_id_i      (dlp_tx_oam_packet_id_i),
    .oam_nd_en_i          (dlp_tx_oam_nd_en_i),
    .oam_target_id1_i     (dlp_tx_oam_target_id1_i),
    .oam_target_id2_i     (dlp_tx_oam_target_id2_i),
    .oam_target_id3_i     (dlp_tx_oam_target_id3_i),
    .key_switch_i         (1'b0),
    .hdr_o                (tx_hdr_built),
    .is_extended_o        (tx_is_ext_built)
  );

  // TX output: use FoFa header as-is, or built header for OAM/ASEP
  always_comb begin
    if (tx_src_q == TX_SRC_FOFA) begin
      tx_hdr_o         = dlp_tx_fwd_hdr_i;
      tx_is_extended_o = dlp_tx_fwd_hdr_i[0]; // headerType in bit 0
    end else begin
      tx_hdr_o         = tx_hdr_built;
      tx_is_extended_o = tx_is_ext_built;
    end
    tx_src_o           = tx_src_q;
  end

  // TX container valid and indicateSlot
  // After mapper selects DLP_TX_ID, we drive indicateSlot then wait for response
  typedef enum logic [1:0] {S_TX_IDLE, S_TX_INDICATE, S_TX_WAIT, S_TX_BUILD} tx_state_e;
  tx_state_e tx_state_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      tx_state_q <= S_TX_IDLE;
      tx_src_q   <= TX_SRC_OAM;
    end else begin
      case (tx_state_q)
        S_TX_IDLE: begin
          if (mapper_result_valid) begin
            tx_state_q <= S_TX_INDICATE;
            tx_src_q   <= TX_SRC_OAM;
          end
        end
        S_TX_INDICATE: begin
          tx_state_q <= S_TX_WAIT;
        end
        S_TX_WAIT: begin
          if (dlp_tx_oam_valid_i) begin
            tx_src_q   <= TX_SRC_OAM;
            tx_state_q <= S_TX_BUILD;
          end else if (dlp_tx_data_valid_i) begin
            tx_src_q   <= TX_SRC_ASEP;
            tx_state_q <= S_TX_BUILD;
          end else if (dlp_tx_fwd_valid_i) begin
            tx_src_q   <= TX_SRC_FOFA;
            tx_state_q <= S_TX_BUILD;
          end else if (dlp_tx_yield_i) begin
            // Yield: fallback to OAM per Section 5.6.1.4.3
            tx_src_q   <= TX_SRC_OAM;
            tx_state_q <= S_TX_BUILD;
          end
        end
        S_TX_BUILD: begin
          tx_state_q <= S_TX_IDLE;
        end
        default: tx_state_q <= S_TX_IDLE;
      endcase
    end
  end

  assign dlp_tx_indicate_valid_o = (tx_state_q == S_TX_INDICATE) && normal_mode_i;
  assign dlp_tx_indicate_id_o    = mapper_dlp_tx_sel;
  assign dlp_tx_indicate_size_o  = SLOT_OAM_FRAME;  // STUB: size depends on DLP type
  assign tx_container_valid_o    = (tx_state_q == S_TX_BUILD);
  assign pktid_tx_dlp_tx_id_o    = mapper_dlp_tx_sel;
  assign pktid_tx_incr_o         = (tx_state_q == S_TX_BUILD) && (tx_src_q == TX_SRC_ASEP);

  // =========================================================================
  // RX Header Parser
  // =========================================================================
  logic        rx_hdr_type, rx_key_sw;
  logic [4:0]  rx_node_id, rx_target_id0, rx_packet_id;
  logic [0:0]  rx_stream_id;
  logic [4:0]  rx_target_id1, rx_target_id2, rx_target_id3;
  logic        rx_hdr_ok;

  dll_header_parse u_hdr_parse (
    .hdr_raw_i     (rx_hdr_raw_i),
    .hdr_valid_i   (rx_container_valid_i),
    .header_type_o (rx_hdr_type),
    .key_switch_o  (rx_key_sw),
    .node_id_o     (rx_node_id),
    .stream_id_o   (rx_stream_id),
    .target_id0_o  (rx_target_id0),
    .packet_id_o   (rx_packet_id),
    .target_id1_o  (rx_target_id1),
    .target_id2_o  (rx_target_id2),
    .target_id3_o  (rx_target_id3),
    .hdr_ok_o      (rx_hdr_ok)
  );

  // =========================================================================
  // DMX Table Lookups
  // =========================================================================
  // DmxTable1: find DLP_RX_ID where entry matches nodeID.streamID
  logic        dmx1_hit;
  logic [5:0]  dmx1_dlp_rx_id;
  logic [4:0]  dmx1_q_node_id;
  logic [0:0]  dmx1_q_stream_id;

  always_comb begin
    dmx1_hit       = 1'b0;
    dmx1_dlp_rx_id = 6'd0;
    for (int i = 0; i < MAX_DMX1_ENTRIES; i++) begin
      if (!dmx1_hit &&
          dmx1_table_i[i][9:5] == rx_node_id &&
          dmx1_table_i[i][0]   == rx_stream_id) begin
        dmx1_hit       = 1'b1;
        dmx1_dlp_rx_id = 6'(i);
      end
    end
  end
  assign dmx1_q_node_id   = rx_node_id;
  assign dmx1_q_stream_id = rx_stream_id;

  // DmxTable2: find DLP_RX_ID for target_id0
  logic        dmx2_hit;
  logic [5:0]  dmx2_dlp_rx_id;

  always_comb begin
    dmx2_hit       = 1'b0;
    dmx2_dlp_rx_id = 6'd0;
    // targetIDs start at 2; index = targetID - 2
    if (rx_target_id0 >= 5'd2 && rx_target_id0 < 5'(MAX_DMX2_ENTRIES + 2)) begin
      automatic int idx = int'(rx_target_id0) - 2;
      if (dmx2_valid_i[idx]) begin
        dmx2_hit       = 1'b1;
        dmx2_dlp_rx_id = dmx2_table_i[idx];
      end
    end
  end

  // =========================================================================
  // RX Demux
  // =========================================================================
  dll_rx_demux u_rx_demux (
    .clk                       (clk),
    .rst                       (rst),
    .hdr_valid_i               (rx_hdr_ok && normal_mode_i),
    .header_type_i             (rx_hdr_type),
    .stream_id_i               (rx_stream_id),
    .node_id_i                 (rx_node_id),
    .target_id0_i              (rx_target_id0),
    .target_id1_i              (rx_target_id1),
    .target_id2_i              (rx_target_id2),
    .target_id3_i              (rx_target_id3),
    .packet_id_i               (rx_packet_id),
    .own_node_id_i             (own_node_id_i),
    .dmx1_lookup_node_id_o     (),
    .dmx1_lookup_stream_id_o   (),
    .dmx1_hit_i                (dmx1_hit),
    .dmx1_dlp_rx_id_i          (dmx1_dlp_rx_id),
    .dmx2_lookup_target_id_o   (),
    .dmx2_hit_i                (dmx2_hit),
    .dmx2_dlp_rx_id_i          (dmx2_dlp_rx_id),
    .route_o                   (rx_route_o),
    .dlp_rx_id_o               (rx_dlp_rx_id_o),
    .route_valid_o             (rx_route_valid_o),
    .pkt_id_ok_i               (pktid_ok_i),
    .pkt_id_dup_i              (pktid_dup_i),
    .pkt_id_miss_i             (pktid_miss_i),
    .key_switch_i              (rx_key_switch_i),
    .err_hdr_decode_o          (err_hdr_decode_o),
    .err_dup_pktid_o           (err_dup_pktid_o),
    .err_miss_pktid_o          (err_miss_pktid_o),
    .err_dmx_local_o           (err_dmx_local_o),
    .err_dmx_fwd_o             (err_dmx_fwd_o)
  );

  // =========================================================================
  // RX delivery
  // =========================================================================
  always_comb begin
    rx_to_oam_valid_o       = 1'b0;
    rx_to_oam_hdr_o         = rx_hdr_raw_i;
    rx_to_asep_valid_o      = 1'b0;
    rx_to_asep_dlp_rx_id_o  = 6'd0;
    rx_to_asep_hdr_o        = rx_hdr_raw_i;
    rx_to_fwd_valid_o       = 1'b0;
    rx_to_fwd_dlp_rx_id_o   = 6'd0;
    rx_to_fwd_hdr_o         = rx_hdr_raw_i;

    if (rx_route_valid_o) begin
      case (rx_route_o)
        ROUTE_LOCAL_OAM: begin
          rx_to_oam_valid_o = 1'b1;
          rx_to_oam_hdr_o   = rx_hdr_raw_i;
        end
        ROUTE_LOCAL_ASEP: begin
          rx_to_asep_valid_o     = 1'b1;
          rx_to_asep_dlp_rx_id_o = rx_dlp_rx_id_o;
          rx_to_asep_hdr_o       = rx_hdr_raw_i;
        end
        ROUTE_FORWARD: begin
          rx_to_fwd_valid_o     = 1'b1;
          rx_to_fwd_dlp_rx_id_o = rx_dlp_rx_id_o;
          rx_to_fwd_hdr_o       = rx_hdr_raw_i;
        end
        default: begin end
      endcase
    end
  end

  // Packet ID check routing
  assign pktid_check_dlp_rx_id_o = rx_dlp_rx_id_o;
  assign pktid_received_o        = rx_packet_id;

endmodule

`default_nettype wire
