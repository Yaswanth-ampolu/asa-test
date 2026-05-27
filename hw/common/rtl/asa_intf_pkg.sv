`default_nettype none

// ASA Common Interfaces & Message Primitives Package
// Spec: Sections 2.2, 5.2.2, 5.6, 6.3 (Figures 5-1, 5-2, 5-3, 5-5)
//
// Defines typed structures for all inter-layer primitives:
//   - PLP_TX / PLP_RX (PHY <-> DLL)
//   - DLP_TX / DLP_RX (DLL <-> ASE/ASD/OAM/FoFa)
//   - Container header and payload formats
//   - OAM CAD (Command-Address-Data) primitives
//   - Security primitives (SecCoP, SIF)
//   - Forwarding Fabric queue interfaces

package asa_intf_pkg;

  // =========================================================================
  // Container payload sizes (Section 5.6.1.1.1)
  // =========================================================================
  typedef enum logic [3:0] {
    SLOT_DN_P2P      = 4'd0,   // 638 bytes downstream point-to-point
    SLOT_DN_P2P_SEC  = 4'd1,   // 620 bytes downstream P2P secured
    SLOT_DN_MC       = 4'd2,   // 636 bytes downstream multicast
    SLOT_DN_MC_SEC   = 4'd3,   // 618 bytes downstream multicast secured
    SLOT_UP_P2P      = 4'd4,   // 208 bytes upstream point-to-point
    SLOT_UP_P2P_SEC  = 4'd5,   // 190 bytes upstream P2P secured
    SLOT_UP_MC       = 4'd6,   // 206 bytes upstream multicast
    SLOT_UP_MC_SEC   = 4'd7,   // 188 bytes upstream multicast secured
    SLOT_OAM_FRAME   = 4'd8    // 188 bytes OAM frame (any direction)
  } slot_size_e;

  // Payload byte counts (for validation)
  function automatic int unsigned slot_byte_count(slot_size_e s);
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
      default:         return 0;
    endcase
  endfunction

  // =========================================================================
  // DLL Container Header (Figure 5-2, Table 5-1)
  //
  // Basic header (headerType=0): 4 bytes
  //   byte 0: [7] headerType=0, [6:2] nodeID, [1] KeySwitch, [0] streamID(MSB)
  //            Actually per Table 5-1:
  //   bit 0:    headerType
  //   bit 1:    KeySwitch
  //   bit 6:2:  nodeID[4:0]
  //   bit 12:7: streamID[5:0]
  //   bit 17:13: targetID[4:0]
  //   bit 22:18: packetID[4:0]
  //   bit 23:    reserved
  //   bits 31:24: reserved
  //
  // Extended header (headerType=1): 6 bytes
  //   basic fields + targetID1[4:0], targetID2[4:0], targetID3[4:0]
  // =========================================================================
  typedef struct packed {
    logic           header_type;   // 0=basic, 1=extended (multicast)
    logic           key_switch;    // Security key slot indicator
    logic [4:0]     node_id;       // Source nodeID (own)
    logic [5:0]     stream_id;     // DLP_TX_ID
    logic [4:0]     target_id;     // Primary target (unicast or 1st multicast)
    logic [4:0]     packet_id;     // Lower 5 bits of fullPacketID
    logic [7:0]     reserved;      // Reserved byte (basic header)
  } dll_container_hdr_t;

  // Extended header multicast targets (only when header_type=1)
  typedef struct packed {
    logic [4:0]     target_id1;    // 2nd multicast target
    logic [4:0]     target_id2;    // 3rd multicast target
    logic [4:0]     target_id3;    // 4th multicast target
    logic           reserved;
  } dll_hdr_ext_t;

  // =========================================================================
  // Security Payload Fields (Figure 5-3, Section 6.3.1.3)
  // When security is enabled, container payload becomes:
  //   [PPF][reserved 6:0][Counter lower byte] | DLL Payload (secured) | ICV
  //
  // PPF = Payload Protection Flag (1 bit)
  // Counter = lower 8 bits of security frame counter
  // ICV = Integrity Check Value (varies by algorithm, typically 4 or 8 bytes)
  // =========================================================================
  typedef struct packed {
    logic           ppf;           // Payload protection flag
    logic [6:0]     reserved;      // Reserved bits
    logic [7:0]     counter_lo;    // Lower byte of security counter
  } sec_payload_prefix_t;

  // =========================================================================
  // DLP_TX Primitives (Section 5.6.1)
  //
  // DLP_TX.indicateSlot(size)  — DLL -> ASE/OAM: request data
  // DLP_TX.dataUnit(payload)   — ASE -> DLL: provide payload
  // DLP_TX.oamUnit(payload, targetID, packetID, ndEn, targetIDs) — OAM -> DLL
  // DLP_TX.yield()             — ASE/FoFa -> DLL: no data available
  // DLP_TX.oamFrameLocal(container, phyLerrStat) — FoFa -> DLL: local OAM
  // DLP_TX.dataForward(container) — FoFa -> DLL: forwarded container
  // =========================================================================

  // indicateSlot request (DLL -> ASE/OAM)
  typedef struct packed {
    logic [5:0]     dlp_tx_id;     // Which DLP_TX port is being polled
    slot_size_e     size;          // Requested payload size
    logic           valid;         // Request is active
  } dlp_tx_indicate_t;

  // dataUnit response (ASE -> DLL)
  typedef struct packed {
    logic           valid;         // Payload is available
    logic           yield;         // No data (DLP_TX.yield)
  } dlp_tx_resp_t;

  // oamUnit response (OAM -> DLL)
  typedef struct packed {
    logic [4:0]     target_id;     // Target nodeID for OAM frame
    logic [4:0]     packet_id;     // OAMframeID[4:0]
    logic           nd_en;         // Node-Discover extended header
    logic [4:0]     target_id1;    // Extended: 2nd target
    logic [4:0]     target_id2;    // Extended: 3rd target
    logic [4:0]     target_id3;    // Extended: 4th target
    logic           valid;
  } dlp_tx_oam_resp_t;

  // =========================================================================
  // DLP_RX Primitives (Section 5.6.2 — receive side)
  //
  // DLP_RX.dataUnit(payload, hdr) — DLL -> ASD: received container
  // DLP_RX.oamFrame(payload, hdr) — DLL -> OAM: received OAM frame
  // DLP_RX.forward(container)     — DLL -> FoFa: container for forwarding
  // =========================================================================

  // Demux routing decision (Section 5.3.2)
  typedef enum logic [1:0] {
    DMX_LOCAL_SINK   = 2'd0,   // Deliver to local ASD
    DMX_FORWARD      = 2'd1,   // Forward to FoFa
    DMX_OAM_LOCAL    = 2'd2,   // Deliver to local OAM entity
    DMX_DROP         = 2'd3    // Drop (no valid route)
  } dmx_action_e;

  // Received container descriptor (DLL -> ASD/OAM/FoFa)
  typedef struct packed {
    dll_container_hdr_t hdr;       // Decoded header
    logic [5:0]         dlp_rx_id; // Destination DLP_RX port
    dmx_action_e        action;    // Demux routing decision
    logic               sec_valid; // Security check passed (if applicable)
    logic               phy_err;   // PHY-level error flag
  } dlp_rx_desc_t;

  // =========================================================================
  // PLP_TX / PLP_RX Primitives (Section 2.2.1, 4.7.1)
  // PHY <-> DLL byte-stream interface
  //
  // These are asynchronous primitive-based interfaces (spec Section 2.2.1.1)
  // In RTL, modeled as streaming byte interfaces with valid/ready
  // =========================================================================
  typedef struct packed {
    logic [7:0]     data;          // Byte to transmit/received
    logic           valid;         // Data is valid
    logic           sof;           // Start of frame (first byte of burst)
    logic           eof;           // End of frame (last byte of burst)
    logic           err;           // PHY error indication (PLP_RX only)
  } plp_data_t;

  // =========================================================================
  // OAM CAD (Command-Address-Data) Primitives (Section 5.5.3)
  // =========================================================================

  // OAM command codes moved to asa_oam_pkg (oam_cmd_code_e).
  // oam_cad_hdr_t kept here for callers that only import asa_intf_pkg.
  typedef struct packed {
    logic           cad_next;      // More CADs follow
    logic [6:0]     command;       // 7-bit command code
  } oam_cad_hdr_t;

  // OAM Read command address (Section 5.5.3.1)
  typedef struct packed {
    logic [2:0]     domain;        // AddressDomain
    logic [5:0]     dlp_id;        // DLP port (for ASE/ASD)
    logic [14:0]    reg_addr;      // Register address
  } oam_read_addr_t;

  // OAM Write command (Section 5.5.3.4)
  typedef struct packed {
    oam_read_addr_t addr;          // Target register
    logic [15:0]    data;          // Write data
  } oam_write_cmd_t;

  // StartTDD data (Section 5.5.3.9)
  typedef struct packed {
    logic [47:0]    ptb_time;      // Absolute PTB time to start Normal Mode
    logic [15:0]    dll_line_min;  // Mapper start pointer
    logic [15:0]    dll_line_max;  // Mapper end pointer
  } oam_start_tdd_t;

  // =========================================================================
  // Security Primitives (Section 6.3.2)
  //
  // LinkLayerSec.process_transmit_container(container) — DLL -> Sec
  // LinkLayerSec.process_receive_container(container)  — DLL -> Sec
  // SecCoP / SIF interfaces (Figure 5-1)
  // =========================================================================
  typedef struct packed {
    logic           valid;
    logic           encrypt;       // 1=encrypt+authenticate, 0=authenticate only
    logic           key_slot;      // Which key slot (KeySwitch bit)
  } sec_tx_req_t;

  typedef struct packed {
    logic           valid;
    logic           pass;          // 1=ICV valid, 0=authentication failed
    logic           key_slot;      // Key slot used
  } sec_rx_resp_t;

  // =========================================================================
  // KeyEx Primitives (Section 6.4)
  // =========================================================================
  typedef struct packed {
    logic           valid;
    logic           is_request;    // 1=request, 0=response
    logic [7:0]     msg_type;      // KeyEx message type
  } keyex_msg_t;

  // =========================================================================
  // Forwarding Fabric Queues (Figure 5-5, Section 5.4)
  //
  // DataForwardQueue: data containers for forwarding
  // OAMreturnQueue:   OAM containers routed back to local
  // =========================================================================
  typedef struct packed {
    dll_container_hdr_t hdr;
    logic               valid;
    logic               from_node_a; // Which node originated (for multi-node devices)
  } fofa_queue_entry_t;

  // =========================================================================
  // ASEP stream type enumeration (Table 7-1)
  // =========================================================================
  typedef enum logic [6:0] {
    STREAM_TYPE_GPIO    = 7'd0,
    STREAM_TYPE_SPI     = 7'd1,
    STREAM_TYPE_I2C     = 7'd2,
    STREAM_TYPE_I2S     = 7'd3,
    STREAM_TYPE_VIDEO   = 7'd4,
    STREAM_TYPE_UART    = 7'd5,
    STREAM_TYPE_L2_ETH  = 7'd6,
    STREAM_TYPE_EDP     = 7'd7,
    STREAM_TYPE_VENDOR  = 7'd127
  } asep_stream_type_e;

endpackage

`default_nettype wire
