`timescale 1ns/1ps
`default_nettype none

// DLL Mapper/Demux Testbench
// Tests per spec requirements (PDF Sections 5.2.2, 5.2.3, 5.3.2):
//  T1:  Header bit layout matches PDF Table 5-1 (basic header)
//  T2:  Header bit layout matches PDF Table 5-1 (extended header)
//  T3:  Secured payload flag recognition (Figure 5-3)
//  T4:  OAM containers route to DLP_RX_ID=0 (case 5.3.2.1 with nodeID match)
//  T5:  ASEP containers route to correct DLP_RX_ID via DmxTable1
//  T6:  Forward containers route via DmxTable2 (case 5.3.2.2)
//  T7:  Malformed container hits error path (no case matches)
//  T8:  Mapper evaluation step exact pseudocode (Figure 5-4): no match → OAM
//  T9:  Mapper evaluation: LINE_sel=1 selects correct DLP_TX_ID
//  T10: Mapper counter wraps CounterMin→CounterMax→CounterMin
//  T11: TX header builder produces correct bit layout for OAM source
//  T12: Node-Discover receive case (5.3.2.3)
//  T13: Forward case 5.3.2.4 (distribute ND)
//  T14: Self-Announce receive (5.3.2.5)
//  T15: Default mapper (no LINEs) → always OAM

module dll_tb;
  import asa_dll_pkg::*;

  logic clk, rst;
  initial begin clk = 0; forever #5 clk = ~clk; end

  int pass_count, fail_count;
  task automatic check(string name, logic cond);
    if (cond) pass_count++;
    else begin $display("FAIL: %s", name); fail_count++; end
  endtask

  // =========================================================================
  // Header parse DUT
  // =========================================================================
  logic [47:0]   hp_raw;
  logic          hp_valid;
  logic          hp_hdr_type, hp_key_sw;
  logic [4:0]    hp_node_id, hp_target0, hp_pkt_id;
  logic [0:0]    hp_stream_id;
  logic [4:0]    hp_t1, hp_t2, hp_t3;
  logic          hp_ok;

  dll_header_parse u_hp (
    .hdr_raw_i(hp_raw), .hdr_valid_i(hp_valid),
    .header_type_o(hp_hdr_type), .key_switch_o(hp_key_sw),
    .node_id_o(hp_node_id), .stream_id_o(hp_stream_id),
    .target_id0_o(hp_target0), .packet_id_o(hp_pkt_id),
    .target_id1_o(hp_t1), .target_id2_o(hp_t2), .target_id3_o(hp_t3),
    .hdr_ok_o(hp_ok)
  );

  // =========================================================================
  // Header build DUT
  // =========================================================================
  dll_tx_src_e   hb_src;
  logic [4:0]    hb_own_nid, hb_oam_tid, hb_oam_pid;
  logic          hb_oam_nd;
  logic [4:0]    hb_oam_t1, hb_oam_t2, hb_oam_t3;
  logic [47:0]   hb_hdr_o;
  logic          hb_ext_o;

  dll_header_build u_hb (
    .tx_src_i(hb_src), .own_node_id_i(hb_own_nid),
    .stream_id_i(1'b0),
    .asep_target_id0_i(5'd0), .asep_target_id1_i(5'd0),
    .asep_target_id2_i(5'd0), .asep_target_id3_i(5'd0),
    .asep_target1_valid_i(1'b0), .asep_target2_valid_i(1'b0),
    .asep_target3_valid_i(1'b0), .asep_packet_id_i(5'd0),
    .oam_target_id_i(hb_oam_tid), .oam_packet_id_i(hb_oam_pid),
    .oam_nd_en_i(hb_oam_nd),
    .oam_target_id1_i(hb_oam_t1), .oam_target_id2_i(hb_oam_t2),
    .oam_target_id3_i(hb_oam_t3),
    .key_switch_i(1'b0),
    .hdr_o(hb_hdr_o), .is_extended_o(hb_ext_o)
  );

  // =========================================================================
  // RX Demux DUT
  // =========================================================================
  logic          rd_hdr_valid, rd_hdr_type;
  logic [0:0]    rd_stream_id;
  logic [4:0]    rd_node_id, rd_t0, rd_t1, rd_t2, rd_t3, rd_pkt_id;
  logic [4:0]    rd_own_nid;
  logic [4:0]    rd_dmx1_q_nid;
  logic [0:0]    rd_dmx1_q_sid;
  logic          rd_dmx1_hit;
  logic [5:0]    rd_dmx1_rx_id;
  logic [4:0]    rd_dmx2_q_tid;
  logic          rd_dmx2_hit;
  logic [5:0]    rd_dmx2_rx_id;
  dll_rx_route_e rd_route;
  logic [5:0]    rd_dlp_rx_id;
  logic          rd_valid;
  logic          rd_pktok, rd_pktdup, rd_pktmiss, rd_ksw;
  logic          rd_e_hdr, rd_e_dup, rd_e_miss, rd_e_loc, rd_e_fwd;

  dll_rx_demux u_rd (
    .clk(clk), .rst(rst),
    .hdr_valid_i(rd_hdr_valid), .header_type_i(rd_hdr_type),
    .stream_id_i(rd_stream_id), .node_id_i(rd_node_id),
    .target_id0_i(rd_t0), .target_id1_i(rd_t1),
    .target_id2_i(rd_t2), .target_id3_i(rd_t3),
    .packet_id_i(rd_pkt_id),
    .own_node_id_i(rd_own_nid),
    .dmx1_lookup_node_id_o(rd_dmx1_q_nid),
    .dmx1_lookup_stream_id_o(rd_dmx1_q_sid),
    .dmx1_hit_i(rd_dmx1_hit), .dmx1_dlp_rx_id_i(rd_dmx1_rx_id),
    .dmx2_lookup_target_id_o(rd_dmx2_q_tid),
    .dmx2_hit_i(rd_dmx2_hit), .dmx2_dlp_rx_id_i(rd_dmx2_rx_id),
    .route_o(rd_route), .dlp_rx_id_o(rd_dlp_rx_id),
    .route_valid_o(rd_valid),
    .pkt_id_ok_i(rd_pktok), .pkt_id_dup_i(rd_pktdup),
    .pkt_id_miss_i(rd_pktmiss),
    .key_switch_i(rd_ksw),
    .err_hdr_decode_o(rd_e_hdr), .err_dup_pktid_o(rd_e_dup),
    .err_miss_pktid_o(rd_e_miss),
    .err_dmx_local_o(rd_e_loc), .err_dmx_fwd_o(rd_e_fwd)
  );

  // =========================================================================
  // TX Mapper DUT
  // =========================================================================
  logic               mp_init, mp_eval, mp_en;
  logic [15:0]        mp_cmin, mp_cmax, mp_lmin, mp_lmax;
  logic               mp_valid;
  logic [5:0]         mp_sel;
  logic [15:0]        mp_counter;
  // Write interface for mapper table
  logic               mp_wr_en;
  logic [2:0]         mp_wr_addr;  // 3 bits for MAX_LINES=8
  mapper_line_t       mp_wr_data;

  dll_tx_mapper #(.MAX_LINES(8)) u_mp (
    .clk(clk), .rst(rst),
    .init_i(mp_init), .eval_trigger_i(mp_eval), .enable_i(mp_en),
    .counter_min_i(mp_cmin), .counter_max_i(mp_cmax),
    .line_min_i(mp_lmin), .line_max_i(mp_lmax),
    .tbl_wr_en_i(mp_wr_en), .tbl_wr_addr_i(mp_wr_addr), .tbl_wr_data_i(mp_wr_data),
    .result_valid_o(mp_valid), .dlp_tx_id_sel_o(mp_sel),
    .counter_o(mp_counter),
    .mapper_err_o(), .mapper_err_id_o()
  );

  // =========================================================================
  // Test sequence
  // =========================================================================
  initial begin
    pass_count = 0; fail_count = 0;
    rst = 1;
    hp_raw = 0; hp_valid = 0;
    hb_src = TX_SRC_OAM; hb_own_nid = 5'd2;
    hb_oam_tid = 5'd1; hb_oam_pid = 5'd7;
    hb_oam_nd = 0; hb_oam_t1 = 0; hb_oam_t2 = 0; hb_oam_t3 = 0;
    rd_hdr_valid = 0; rd_hdr_type = 0; rd_stream_id = 0;
    rd_node_id = 0; rd_t0 = 0; rd_t1 = 0; rd_t2 = 0; rd_t3 = 0; rd_pkt_id = 0;
    rd_own_nid = 5'd2; rd_dmx1_hit = 0; rd_dmx1_rx_id = 0;
    rd_dmx2_hit = 0; rd_dmx2_rx_id = 0;
    rd_pktok = 0; rd_pktdup = 0; rd_pktmiss = 0; rd_ksw = 0;
    mp_init = 0; mp_eval = 0; mp_en = 1;
    mp_cmin = 16'd0; mp_cmax = 16'd3; mp_lmin = 16'd0; mp_lmax = 16'd0;
    mp_wr_en = 0; mp_wr_addr = 0;
    mp_wr_data.bitmask = 16'd0; mp_wr_data.compare_value = 16'd0;
    mp_wr_data.dlp_tx_id_to_send = 6'd0;
    repeat(3) @(posedge clk); rst = 0; @(posedge clk);

    // ===== T1: Basic header bit layout (Table 5-1, PDF p164) =====
    $display("T1: Basic header parse");
    // Build a basic header: headerType=0, keySwitch=0, nodeID=5'b00101, streamID=1,
    //   targetID=5'b00011 (at bits 17:13), packetID=5'b10101 (at bits 22:18)
    begin
      logic [47:0] h;
      h = 48'd0;
      h[0]   = 1'b0;         // headerType=0
      h[1]   = 1'b0;         // keySwitch=0
      h[6:2] = 5'b00101;     // nodeID=5
      h[7]   = 1'b1;         // streamID=1
      h[17:13] = 5'b00011;   // targetID=3
      h[22:18] = 5'b10101;   // packetID=21
      hp_raw = h; hp_valid = 1; #1;
      check("T1a: headerType=0",      hp_hdr_type == 1'b0);
      check("T1b: nodeID=5",          hp_node_id  == 5'd5);
      check("T1c: streamID=1",        hp_stream_id == 1'b1);
      check("T1d: targetID=3",        hp_target0  == 5'd3);
      check("T1e: packetID=21",       hp_pkt_id   == 5'd21);
      check("T1f: hdr_ok=1",          hp_ok == 1'b1);
      hp_valid = 0;
    end

    // ===== T2: Extended header bit layout =====
    $display("T2: Extended header parse");
    begin
      logic [47:0] h;
      h = 48'd0;
      h[0]    = 1'b1;         // headerType=1
      h[6:2]  = 5'b00010;    // nodeID=2
      h[17:13]= 5'b00001;    // targetID0=1
      h[22:18]= 5'b00101;    // packetID=5
      h[37:33]= 5'b00100;    // targetID1=4
      // targetID2: bits 42:40 (4:2) and bits 39:38 (1:0)
      h[42:40]= 3'b010;
      h[39:38]= 2'b11;        // targetID2 = {010,11} = 5'b01011 = 11
      h[47:43]= 5'b01001;    // targetID3=9
      hp_raw = h; hp_valid = 1; #1;
      check("T2a: headerType=1",      hp_hdr_type == 1'b1);
      check("T2b: nodeID=2",          hp_node_id  == 5'd2);
      check("T2c: targetID0=1",       hp_target0  == 5'd1);
      check("T2d: targetID1=4",       hp_t1       == 5'd4);
      check("T2e: targetID2=11",      hp_t2       == 5'd11);
      check("T2f: targetID3=9",       hp_t3       == 5'd9);
      hp_valid = 0;
    end

    // ===== T3: Secured payload PPF recognition =====
    $display("T3: Secured payload prefix (Figure 5-3)");
    begin
      // Build a secured payload prefix: PPF=1, reserved=0, Counter_lo=0xAB
      logic [15:0] sec_prefix;
      sec_prefix = 16'd0;
      sec_prefix[7]  = 1'b1;    // PPF = bit 7 of first byte
      sec_prefix[15:8] = 8'hAB; // Counter lower byte
      check("T3a: PPF=1",         sec_ppf(sec_prefix) == 1'b1);
      check("T3b: counter=0xAB",  sec_counter_lo(sec_prefix) == 8'hAB);
      // Unsecured: PPF=0
      sec_prefix[7] = 1'b0;
      check("T3c: PPF=0 unsecured", sec_ppf(sec_prefix) == 1'b0);
    end

    // ===== T4: OAM container routes to OAM (case 5.3.2.1 with nodeID match) =====
    $display("T4: OAM container -> ROUTE_LOCAL_OAM");
    // Send container with targetID=own_node_id=2, streamID=0, nodeID=1 (root)
    // DmxTable1: DLP_RX_ID=0 matches nodeID=1, streamID=0
    rd_hdr_valid  = 1; rd_hdr_type = 0;
    rd_node_id    = 5'd1;   // root nodeID as source
    rd_stream_id  = 1'b0;   // streamID=0 (OAM stream)
    rd_t0         = 5'd2;   // targetID=own nodeID
    rd_t1 = 0; rd_t2 = 0; rd_t3 = 0;
    rd_own_nid    = 5'd2;
    rd_dmx1_hit   = 1'b1;
    rd_dmx1_rx_id = 6'd0;   // DmxTable1 says DLP_RX_ID=0 for nodeID=1,streamID=0
    rd_dmx2_hit   = 1'b0;
    rd_ksw = 1'b0;
    rd_pktok = 1'b1; rd_pktdup = 0; rd_pktmiss = 0;
    #1;
    check("T4a: route=LOCAL_ASEP",   rd_route == ROUTE_LOCAL_ASEP);
    check("T4b: dlp_rx_id=0",        rd_dlp_rx_id == 6'd0);
    check("T4c: route_valid",        rd_valid == 1'b1);
    check("T4d: no errors",          rd_e_hdr==0 && rd_e_loc==0 && rd_e_fwd==0);
    rd_hdr_valid = 0;

    // ===== T5: ASEP container routes to correct DLP_RX via DmxTable1 =====
    $display("T5: ASEP container -> ROUTE_LOCAL_ASEP");
    rd_hdr_valid  = 1; rd_hdr_type = 0;
    rd_node_id    = 5'd3;  // source nodeID=3
    rd_stream_id  = 1'b1;  // streamID=1
    rd_t0         = 5'd2;  // targetID=own nodeID
    rd_t1 = 0; rd_t2 = 0; rd_t3 = 0;
    rd_own_nid    = 5'd2;
    rd_dmx1_hit   = 1'b1;
    rd_dmx1_rx_id = 6'd5;  // DmxTable1 says DLP_RX_ID=5
    rd_dmx2_hit   = 1'b0;
    rd_ksw = 0; rd_pktok = 1; rd_pktdup = 0; rd_pktmiss = 0;
    #1;
    check("T5a: route=LOCAL_ASEP",   rd_route == ROUTE_LOCAL_ASEP);
    check("T5b: dlp_rx_id=5",        rd_dlp_rx_id == 6'd5);
    check("T5c: no errors",          rd_e_hdr==0 && rd_e_loc==0);
    rd_hdr_valid = 0;

    // ===== T6: Forward container via DmxTable2 =====
    $display("T6: Forward container -> ROUTE_FORWARD");
    rd_hdr_valid  = 1; rd_hdr_type = 0;
    rd_node_id    = 5'd1;
    rd_stream_id  = 1'b0;
    rd_t0         = 5'd4;  // targetID=4 (not own nodeID=2)
    rd_t1 = 0; rd_t2 = 0; rd_t3 = 0;
    rd_own_nid    = 5'd2;
    rd_dmx1_hit   = 1'b0;  // Not a local sink
    rd_dmx2_hit   = 1'b1;
    rd_dmx2_rx_id = 6'd7;  // DmxTable2 says forward to DLP_RX_ID=7
    rd_ksw = 0; rd_pktok = 0; rd_pktdup = 0; rd_pktmiss = 0;
    #1;
    check("T6a: route=FORWARD",      rd_route == ROUTE_FORWARD);
    check("T6b: dlp_rx_id=7",        rd_dlp_rx_id == 6'd7);
    check("T6c: no fwd error",       rd_e_fwd == 0);
    rd_hdr_valid = 0;

    // ===== T7: Malformed container (no case matches) =====
    $display("T7: Malformed -> ROUTE_DISCARD + error");
    // targetID=0 in basic header with own nodeID!=0 → no case matches
    rd_hdr_valid  = 1; rd_hdr_type = 0;
    rd_node_id    = 5'd1;
    rd_stream_id  = 1'b0;
    rd_t0         = 5'd0;  // targetID=0 → no case
    rd_t1 = 0; rd_t2 = 0; rd_t3 = 0;
    rd_own_nid    = 5'd2;
    rd_dmx1_hit   = 1'b0;
    rd_dmx2_hit   = 1'b0;
    rd_ksw = 0;
    #1;
    check("T7a: route=DISCARD",      rd_route == ROUTE_DISCARD);
    check("T7b: hdr_decode_error",   rd_e_hdr == 1'b1);
    rd_hdr_valid = 0;

    // ===== T8: Mapper with no matching LINEs → default OAM =====
    $display("T8: Mapper no-match -> DLP_TX_ID=0");
    // LINE 0: BitMask=0xFFFF, CompareValue=0xFFFF → only matches counter=0xFFFF
    mp_wr_addr = 3'd0; mp_wr_data.bitmask = 16'hFFFF;
    mp_wr_data.compare_value = 16'hFFFF; mp_wr_data.dlp_tx_id_to_send = 6'd5;
    mp_wr_en = 1; @(posedge clk); mp_wr_en = 0; @(posedge clk);
    mp_cmin = 16'd0; mp_cmax = 16'd3;
    mp_lmin = 16'd0; mp_lmax = 16'd0;
    mp_init = 1; @(posedge clk); mp_init = 0; @(posedge clk);
    // Counter=0, 0 & 0xFFFF = 0 ≠ 0xFFFF → no match → OAM
    mp_eval = 1; @(posedge clk); mp_eval = 0;
    repeat(5) @(posedge clk);
    check("T8: no-match → OAM(0)",   mp_sel == 6'd0);

    // ===== T9: Mapper LINE_sel=1 → selects DLP_TX_ID per line =====
    $display("T9: Mapper match -> selects DLP_TX_ID");
    // LINE 0: BitMask=0x0003, CompareValue=0x0001, DLP_TX_ID=3
    // Counter=1 → 1 & 0x0003 = 1 == 0x0001 → match → select DLP_TX_ID=3
    mp_wr_addr = 3'd0; mp_wr_data.bitmask = 16'h0003;
    mp_wr_data.compare_value = 16'h0001; mp_wr_data.dlp_tx_id_to_send = 6'd3;
    mp_wr_en = 1; @(posedge clk); mp_wr_en = 0; @(posedge clk);
    mp_cmin = 16'd1; mp_cmax = 16'd4;
    mp_lmin = 16'd0; mp_lmax = 16'd0;
    mp_init = 1; @(posedge clk); mp_init = 0; @(posedge clk);
    // Counter=1 after init
    mp_eval = 1; @(posedge clk); mp_eval = 0;
    repeat(5) @(posedge clk);
    check("T9: match → DLP_TX_ID=3", mp_sel == 6'd3);

    // ===== T10: Mapper counter wraps =====
    $display("T10: Counter wrap");
    // LINE 0: never matches (BitMask=0x0001, CompareValue=0x0001, Counter starts at 0)
    mp_wr_addr = 3'd0; mp_wr_data.bitmask = 16'h0001;
    mp_wr_data.compare_value = 16'h0001; mp_wr_data.dlp_tx_id_to_send = 6'd0;
    mp_wr_en = 1; @(posedge clk); mp_wr_en = 0; @(posedge clk);
    mp_cmin = 16'd0; mp_cmax = 16'd2;
    mp_lmin = 16'd0; mp_lmax = 16'd0;
    mp_init = 1; @(posedge clk); mp_init = 0; @(posedge clk);
    // Counter=0 after init
    mp_eval = 1; @(posedge clk); mp_eval = 0; // eval: Counter 0→1
    repeat(5) @(posedge clk);
    check("T10a: counter became 1",  mp_counter == 16'd1);
    mp_eval = 1; @(posedge clk); mp_eval = 0; // eval: Counter 1→2
    repeat(5) @(posedge clk);
    check("T10b: counter became 2",  mp_counter == 16'd2);
    mp_eval = 1; @(posedge clk); mp_eval = 0; // eval: Counter 2→wrap→0
    repeat(5) @(posedge clk);
    check("T10c: counter wrapped→0", mp_counter == 16'd0);

    // ===== T11: TX header builder for OAM source =====
    $display("T11: TX header build OAM");
    hb_src = TX_SRC_OAM; hb_own_nid = 5'd2;
    hb_oam_tid = 5'd1; hb_oam_pid = 5'd7;
    hb_oam_nd = 0; #1;
    check("T11a: headerType=0",      hb_hdr_o[0]    == 1'b0);
    check("T11b: nodeID=2",          hb_hdr_o[6:2]  == 5'd2);
    check("T11c: streamID=0",        hb_hdr_o[7]    == 1'b0);
    check("T11d: targetID=1",        hb_hdr_o[17:13]== 5'd1);
    check("T11e: packetID=7",        hb_hdr_o[22:18]== 5'd7);
    check("T11f: not extended",      hb_ext_o == 1'b0);

    // ===== T12: Receive Node-Discover (5.3.2.3) =====
    $display("T12: Receive Node-Discover");
    rd_hdr_valid  = 1; rd_hdr_type = 1;
    rd_stream_id  = 1'b0;
    rd_node_id    = 5'd1;   // source=root
    rd_t0         = 5'd0;   // all targetIDs=0
    rd_t1 = 0; rd_t2 = 0; rd_t3 = 0;
    rd_own_nid    = 5'd0;   // own nodeID=0 (undiscovered)
    rd_dmx1_hit   = 1'b0;
    rd_dmx2_hit   = 1'b0;
    rd_ksw = 0;
    #1;
    check("T12: Rx ND → LOCAL_OAM",  rd_route == ROUTE_LOCAL_OAM);
    check("T12b: dlp_rx_id=0",       rd_dlp_rx_id == 6'd0);
    rd_hdr_valid = 0;

    // ===== T14: Self-Announce receive (5.3.2.5) =====
    $display("T14: Self-Announce receive");
    rd_hdr_valid  = 1; rd_hdr_type = 1;
    rd_stream_id  = 1'b0;
    rd_node_id    = 5'd5;
    rd_t0         = 5'd1;   // targetID0=1 → receive self-announce
    rd_t1 = 0; rd_t2 = 0; rd_t3 = 0;
    rd_own_nid    = 5'd2;
    rd_dmx1_hit   = 1'b0;
    rd_dmx2_hit   = 1'b0;
    rd_ksw = 0;
    #1;
    check("T14: SA → LOCAL_OAM",     rd_route == ROUTE_LOCAL_OAM);
    check("T14b: dlp_rx_id=0",       rd_dlp_rx_id == 6'd0);
    rd_hdr_valid = 0;

    // ===== T15: Default mapper (linemax < linemin) → always OAM =====
    $display("T15: Default mapper (no LINES) → OAM");
    mp_cmin = 16'd0; mp_cmax = 16'd0;
    mp_lmin = 16'd0; mp_lmax = 16'd0;
    mp_init = 1; @(posedge clk); mp_init = 0; @(posedge clk);
    mp_eval = 1; @(posedge clk); mp_eval = 0;
    repeat(5) @(posedge clk);
    // LINE 0: BitMask=0x0001, CompareValue=0x0001; Counter starts at 0
    // 0 & 0x0001 = 0 ≠ 0x0001 → no match → default OAM
    mp_wr_addr = 3'd0; mp_wr_data.bitmask = 16'h0001;
    mp_wr_data.compare_value = 16'h0001; mp_wr_data.dlp_tx_id_to_send = 6'd9;
    mp_wr_en = 1; @(posedge clk); mp_wr_en = 0; @(posedge clk);
    mp_init = 1; @(posedge clk); mp_init = 0; @(posedge clk);
    mp_eval = 1; @(posedge clk); mp_eval = 0;
    repeat(5) @(posedge clk);
    // Counter=0: 0 & 0x0001 = 0 ≠ 0x0001 → no match → default OAM
    check("T15: default → OAM(0)",   mp_sel == 6'd0);

    // ===== Summary =====
    $display("");
    $display("========================================");
    $display("Results: %0d passed, %0d failed", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) $display("dll_tb: ALL TESTS PASSED");
    else                 $display("dll_tb: SOME TESTS FAILED");
    $finish;
  end

  initial begin #500000; $display("TIMEOUT"); $finish; end

endmodule

`default_nettype wire
