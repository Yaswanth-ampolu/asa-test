`default_nettype none

// ASA DLL Mapper/Demux Package
// Source of truth: ASA Technical Specification v2.0, Section 5
//
// All container header bit positions verified against PDF Table 5-1 (p164)
// and Figure 5-2 image.
// Secured payload layout verified against Figure 5-3 (p163) image.
// Mapper pseudocode verified against Figure 5-4 (p167) image.

package asa_dll_pkg;

  // =========================================================================
  // Container Header (Table 5-1, PDF p164, Figure 5-2)
  //
  // Bit layout (d_plp_tx notation, bit 0 = first transmitted):
  //   bit 0       HeaderType  0=basic(4B), 1=extended(6B)
  //   bit 1       KeySwitch   0=no security; security entity value otherwise
  //   bits 6:2    nodeID      own nodeID (5 bits)
  //   bit 7       streamID    DLP_TX_ID (1 bit — LSB of DLP_TX_ID)
  //   bits 12:8   targetID[12:8] (with bits 15:13 in byte 1)
  //   bits 15:13  targetID[15:13]  → targetID = {byte1[7:5], byte1[4:0], byte2[1:0]}
  //                               = bits 17:13 from spec → bits 4:0 of node addr space
  //   bits 22:18  packetID    lower 5 bits of fullPacketID
  //   bit 23      Reserved
  //   bits 31:24  Reserved
  //   -- Extended header only (headerType=1) --
  //   bit 32      Reserved
  //   bits 37:33  targetID1   second multicast address (5 bits)
  //   bits 39:38  targetID2[1:0]  third multicast address (bits 1:0)
  //   bits 42:40  targetID2[4:2]
  //   bits 47:43  targetID3   fourth multicast address (5 bits)
  //
  // Stored as packed vector: bit 0 = LSB of packed value.
  // =========================================================================

  // Basic header: 4 bytes = 32 bits
  // Extended header: 6 bytes = 48 bits
  localparam int unsigned DLL_HDR_BASIC_BITS = 32;
  localparam int unsigned DLL_HDR_EXT_BITS   = 48;

  typedef logic [31:0] dll_hdr_basic_t;
  typedef logic [47:0] dll_hdr_ext_t;

  // Field extraction from basic header (PDF Table 5-1)
  function automatic logic dll_header_type(input logic [47:0] h);
    return h[0];
  endfunction

  function automatic logic dll_key_switch(input logic [47:0] h);
    return h[1];
  endfunction

  function automatic logic [4:0] dll_node_id(input logic [47:0] h);
    return h[6:2];
  endfunction

  // streamID: PDF says bit 7 = streamID = DLP_TX_ID
  // NOTE: DLP_TX_ID is 6 bits (0-63), but only LSB is in the container header.
  // The spec says "Equal to sending DLP_TX_ID" at bit 7.
  // IMPLEMENTATION ASSUMPTION: Only 1 bit of streamID is in the header per Table 5-1.
  // The upstream interpretation of the full DLP_TX_ID requires out-of-band context.
  function automatic logic [0:0] dll_stream_id(input logic [47:0] h);
    return h[7];
  endfunction

  // targetID: bits 17:13 (5 bits) per Table 5-1
  // bytes: <1><4:0>=bits12:8, <1><7:5>=bits15:13, <2><1:0>=bits17:16
  function automatic logic [4:0] dll_target_id(input logic [47:0] h);
    return h[17:13];
  endfunction

  // packetID: bits 22:18 (5 bits)
  function automatic logic [4:0] dll_packet_id(input logic [47:0] h);
    return h[22:18];
  endfunction

  // Extended header fields
  function automatic logic [4:0] dll_target_id1(input logic [47:0] h);
    return h[37:33];
  endfunction

  function automatic logic [4:0] dll_target_id2(input logic [47:0] h);
    return {h[42:40], h[39:38]};
  endfunction

  function automatic logic [4:0] dll_target_id3(input logic [47:0] h);
    return h[47:43];
  endfunction

  // =========================================================================
  // Build basic container header from fields
  // =========================================================================
  function automatic logic [31:0] dll_build_basic_hdr(
    input logic        header_type,
    input logic        key_switch,
    input logic [4:0]  node_id,
    input logic [0:0]  stream_id,
    input logic [4:0]  target_id,
    input logic [4:0]  packet_id
  );
    logic [31:0] h;
    h = 32'd0;
    h[0]    = header_type;
    h[1]    = key_switch;
    h[6:2]  = node_id;
    h[7]    = stream_id;
    h[17:13]= target_id;  // bits 17:13
    h[22:18]= packet_id;
    // bits 12:8 hold targetID[12:8] but targetID is only 5 bits → h[12:8] = 0
    // bit 23 reserved = 0, bits 31:24 reserved = 0
    return h;
  endfunction

  // Build extended header (adds 2 bytes for multicast targetIDs)
  function automatic logic [47:0] dll_build_ext_hdr(
    input logic        key_switch,
    input logic [4:0]  node_id,
    input logic [0:0]  stream_id,
    input logic [4:0]  target_id,
    input logic [4:0]  packet_id,
    input logic [4:0]  target_id1,
    input logic [4:0]  target_id2,
    input logic [4:0]  target_id3
  );
    logic [47:0] h;
    h = 48'd0;
    h[0]    = 1'b1;         // header_type = 1
    h[1]    = key_switch;
    h[6:2]  = node_id;
    h[7]    = stream_id;
    h[17:13]= target_id;
    h[22:18]= packet_id;
    // bit 32: reserved
    h[37:33]= target_id1;
    h[39:38]= target_id2[1:0];
    h[42:40]= target_id2[4:2];
    h[47:43]= target_id3;
    return h;
  endfunction

  // =========================================================================
  // Secured payload prefix (Figure 5-3, PDF p163)
  // Security payload prefix: PPF(1) | reserved(6:0) | Counter_low_byte(7:0) = 2 bytes
  // =========================================================================
  localparam int unsigned SEC_PREFIX_BYTES = 2; // PPF byte + Counter lower byte

  function automatic logic sec_ppf(input logic [15:0] sec_prefix);
    return sec_prefix[7]; // PPF is MSB of first byte
  endfunction

  function automatic logic [7:0] sec_counter_lo(input logic [15:0] sec_prefix);
    return sec_prefix[15:8]; // Second byte = Counter lower byte
  endfunction

  // =========================================================================
  // Payload sizes (Section 5.6.1.1.1)
  // =========================================================================
  typedef enum logic [3:0] {
    SLOT_DN_P2P     = 4'd0,  // 638 bytes
    SLOT_DN_P2P_SEC = 4'd1,  // 620 bytes
    SLOT_DN_MC      = 4'd2,  // 636 bytes
    SLOT_DN_MC_SEC  = 4'd3,  // 618 bytes
    SLOT_UP_P2P     = 4'd4,  // 208 bytes
    SLOT_UP_P2P_SEC = 4'd5,  // 190 bytes
    SLOT_UP_MC      = 4'd6,  // 206 bytes
    SLOT_UP_MC_SEC  = 4'd7,  // 188 bytes
    SLOT_OAM_FRAME  = 4'd8   // 188 bytes
  } dll_slot_size_e;

  function automatic int unsigned dll_slot_bytes(dll_slot_size_e s);
    case (s)
      SLOT_DN_P2P:     return 638;
      SLOT_DN_P2P_SEC: return 620;
      SLOT_DN_MC:      return 636;
      SLOT_DN_MC_SEC:  return 618;
      SLOT_UP_P2P:     return 208;
      SLOT_UP_P2P_SEC: return 190;
      SLOT_UP_MC:      return 206;
      SLOT_UP_MC_SEC:  return 188;
      SLOT_OAM_FRAME:  return 188;
      default:         return 188;
    endcase
  endfunction

  // =========================================================================
  // RX routing decision (result of demux classification, Section 5.3.2)
  // =========================================================================
  typedef enum logic [2:0] {
    ROUTE_LOCAL_OAM   = 3'd0, // OAM entity (DLP_RX_ID=0)
    ROUTE_LOCAL_ASEP  = 3'd1, // Local ASEP/ASD sink
    ROUTE_FORWARD     = 3'd2, // Forward via FoFa (DLP_RX forwardUnit)
    ROUTE_DISCARD     = 3'd3, // Malformed or no match
    ROUTE_SEC_INGRESS = 3'd4  // Hand to security for decryption before routing
  } dll_rx_route_e;

  // =========================================================================
  // TX source type (what generated this container)
  // =========================================================================
  typedef enum logic [1:0] {
    TX_SRC_OAM     = 2'd0,  // OAM entity → oamUnit primitive
    TX_SRC_ASEP    = 2'd1,  // ASEP → dataUnit primitive
    TX_SRC_FOFA    = 2'd2,  // Forwarding Fabric → forwardUnit primitive (header pre-built)
    TX_SRC_YIELD   = 2'd3   // Yield (no data) → fallback to OAM
  } dll_tx_src_e;

  // =========================================================================
  // Mapper table line structure (Table 3-46, Section 3.3.13)
  // Three registers per line: BitMask, CompareValue, DLP_TX_ID_toSend
  // =========================================================================
  typedef struct packed {
    logic [15:0] bitmask;
    logic [15:0] compare_value;
    logic [5:0]  dlp_tx_id_to_send;
  } mapper_line_t;

  // =========================================================================
  // DLL error event codes (for asa_error_pkg integration)
  // =========================================================================
  localparam logic [3:0] DLL_ERR_HDR_DECODE   = 4'd0; // 2.2210[15:8]
  localparam logic [3:0] DLL_ERR_DUP_PKTID    = 4'd1; // 2.2210[7:0]
  localparam logic [3:0] DLL_ERR_MISS_PKTID   = 4'd2; // 2.2211[15:8]
  localparam logic [3:0] DLL_ERR_DMX_LOCAL    = 4'd3; // 2.2147[15:8]
  localparam logic [3:0] DLL_ERR_DMX_FWD      = 4'd4; // 2.2147[7:0]
  localparam logic [3:0] DLL_ERR_MAPPER_ERR   = 4'd5; // 2.0140[5:0]
  localparam logic [3:0] DLL_ERR_ADDR_ERR     = 4'd6; // 2.0140[11:6]

endpackage

`default_nettype wire
