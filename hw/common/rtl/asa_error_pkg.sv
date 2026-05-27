`default_nettype none

// ASA Error & Status Reporting Package
// Spec: Sections 3.2.8, 3.2.12, 3.2.13, 3.2.16, 3.2.20, 3.3.23-3.3.26,
//        3.4.2, 3.4.3, 5.3.x error handling
//
// Provides a unified error/status subsystem used by all ASA modules to:
//   - Increment register-backed saturating counters
//   - Set IRQ flag bits
//   - Report module-level error codes
//   - Distinguish recoverable vs. fatal conditions

package asa_error_pkg;

  // =========================================================================
  // Error severity levels
  // =========================================================================
  typedef enum logic [1:0] {
    ERR_SEV_WARN    = 2'd0,  // Recoverable: counter increment, no state change
    ERR_SEV_DROP    = 2'd1,  // Packet/container dropped, counter increment
    ERR_SEV_PROTO   = 2'd2,  // Protocol/authentication failure, IRQ + counter
    ERR_SEV_FATAL   = 2'd3   // Unrecoverable: triggers state change (e.g. Fail)
  } err_severity_e;

  // =========================================================================
  // Error source identification (maps to IRQ flags in 1.0008)
  // =========================================================================
  typedef enum logic [3:0] {
    ERR_SRC_LOCAL_PHY   = 4'd0,   // bit 0: Local PMA/PMD/PCS
    ERR_SRC_REMOTE_PHY  = 4'd1,   // bit 1: Remote PMA/PMD/PCS (via OAM)
    ERR_SRC_SECURITY    = 4'd2,   // bit 7: Security flag
    ERR_SRC_PTB         = 4'd3,   // bit 8: PTB flag
    ERR_SRC_DLL_TX      = 4'd4,   // bit 9: DLL Transmit flag
    ERR_SRC_DLL_RX      = 4'd5,   // bit 10: DLL Receive flag
    ERR_SRC_OAM         = 4'd6,   // bit 11: OAM flag
    ERR_SRC_ASE         = 4'd7,   // bit 12: ASE flag
    ERR_SRC_ASD         = 4'd8    // bit 13: ASD flag
  } err_source_e;

  // Map err_source_e to IRQ bit position in register 1.0008
  function automatic int unsigned irq_bit_for_source(err_source_e src);
    case (src)
      ERR_SRC_LOCAL_PHY:  return 0;
      ERR_SRC_REMOTE_PHY: return 1;
      ERR_SRC_SECURITY:   return 7;
      ERR_SRC_PTB:        return 8;
      ERR_SRC_DLL_TX:     return 9;
      ERR_SRC_DLL_RX:     return 10;
      ERR_SRC_OAM:        return 11;
      ERR_SRC_ASE:        return 12;
      ERR_SRC_ASD:        return 13;
      default:            return 0;
    endcase
  endfunction

  // =========================================================================
  // Error event structure (from any module -> error aggregator)
  // =========================================================================
  typedef struct packed {
    logic           valid;         // Error event is active
    err_source_e    source;        // Which subsystem
    err_severity_e  severity;      // How bad
    logic [3:0]     code;          // Module-specific error code
  } err_event_t;

  // =========================================================================
  // Saturating counter configuration
  //
  // Multiple registers use saturating counters with various widths:
  //   LinkQuality[15:10]  — 6-bit, saturates at 0x3F (Section 3.2.13)
  //   LinkQuality[9:0]    — 10-bit, saturates at 0x3FF (Section 3.2.13)
  //   OAMerrors1[15:8]    — 8-bit, saturates at 0xFF (Section 3.3.23)
  //   OAMerrors1[7:0]     — 8-bit, saturates at 0xFF (Section 3.3.23)
  //   DLLerrors1[15:8]    — 8-bit, saturates at 0xFF (Section 3.3.25)
  //   DLLerrors1[7:0]     — 8-bit, saturates at 0xFF (Section 3.3.25)
  //   droppedContSecRX    — 16-bit, saturates at 0xFFFF (Section 3.4.2)
  //   droppedContSecTX    — 16-bit, saturates at 0xFFFF (Section 3.4.3)
  //   LPerrors[15:11]     — 5-bit, saturates at 0x1F (Section 3.2.12)
  //   RetryCounter[7:0]   — 8-bit, equals ph1G_retry_cnt (Section 3.2.20)
  //   Timeouts[12:8]      — 5-bit, saturates at 0x1F (Section 3.2.20)
  // =========================================================================

  // Counter width enumeration
  typedef enum logic [2:0] {
    CNT_WIDTH_5   = 3'd0,  // 5-bit (0x1F max)
    CNT_WIDTH_6   = 3'd1,  // 6-bit (0x3F max)
    CNT_WIDTH_8   = 3'd2,  // 8-bit (0xFF max)
    CNT_WIDTH_10  = 3'd3,  // 10-bit (0x3FF max)
    CNT_WIDTH_16  = 3'd4   // 16-bit (0xFFFF max)
  } cnt_width_e;

  // Maximum value for each width
  function automatic logic [15:0] cnt_max(cnt_width_e w);
    case (w)
      CNT_WIDTH_5:  return 16'h001F;
      CNT_WIDTH_6:  return 16'h003F;
      CNT_WIDTH_8:  return 16'h00FF;
      CNT_WIDTH_10: return 16'h03FF;
      CNT_WIDTH_16: return 16'hFFFF;
      default:      return 16'hFFFF;
    endcase
  endfunction

  // =========================================================================
  // Counter increment request (module -> register bank)
  // =========================================================================
  typedef struct packed {
    logic           valid;         // Increment request active
    logic [14:0]    reg_addr;      // Target register address
    logic [3:0]     field_msb;     // MSB of counter field
    logic [3:0]     field_lsb;     // LSB of counter field
    cnt_width_e     width;         // Counter width for saturation
  } cnt_inc_req_t;

  // =========================================================================
  // Status snapshot (for diagnostic readback)
  // =========================================================================
  typedef struct packed {
    logic [3:0]     node_state;    // Current ASAnodeState
    logic           com_ready;     // COMready flag
    logic           ptb_locked;    // PTB lock status
    logic [1:0]     sec_policy;    // Active security policy
    logic [5:0]     link_losses;   // Current link loss counter
    logic [4:0]     node_id;       // Own nodeID
  } status_snapshot_t;

  // =========================================================================
  // Module-specific error codes
  // =========================================================================

  // PHY error codes (source = ERR_SRC_LOCAL_PHY)
  localparam logic [3:0] PHY_ERR_LINK_LOSS      = 4'd0;
  localparam logic [3:0] PHY_ERR_STARTUP_FAIL   = 4'd1;
  localparam logic [3:0] PHY_ERR_POLARITY       = 4'd2;
  localparam logic [3:0] PHY_ERR_FEC_UNCORR     = 4'd3;

  // OAM error codes (source = ERR_SRC_OAM)
  localparam logic [3:0] OAM_ERR_HDR_DECODE     = 4'd0;
  localparam logic [3:0] OAM_ERR_DUPL_FRAME_ID  = 4'd1;
  localparam logic [3:0] OAM_ERR_ADDR_INVALID   = 4'd2;
  localparam logic [3:0] OAM_ERR_PRIVILEGE       = 4'd3;

  // DLL TX error codes (source = ERR_SRC_DLL_TX)
  localparam logic [3:0] DLL_TX_ERR_ADDR_MISS   = 4'd0;  // DLP has no addr table entry
  localparam logic [3:0] DLL_TX_ERR_MAPPER_MISS = 4'd1;  // DLP not in mapper table

  // DLL RX error codes (source = ERR_SRC_DLL_RX)
  localparam logic [3:0] DLL_RX_ERR_CRC         = 4'd0;
  localparam logic [3:0] DLL_RX_ERR_PKT_ID      = 4'd1;  // Missing packetID
  localparam logic [3:0] DLL_RX_ERR_DMX_LOCAL   = 4'd2;  // Demux error (local)
  localparam logic [3:0] DLL_RX_ERR_DMX_FWD     = 4'd3;  // Demux error (forward)

  // Security error codes (source = ERR_SRC_SECURITY)
  localparam logic [3:0] SEC_ERR_ICV_FAIL       = 4'd0;  // Authentication failed
  localparam logic [3:0] SEC_ERR_COUNTER        = 4'd1;  // Replay counter mismatch
  localparam logic [3:0] SEC_ERR_KEY_MISSING    = 4'd2;  // No key installed
  localparam logic [3:0] SEC_ERR_DROP_RX        = 4'd3;  // Container dropped RX
  localparam logic [3:0] SEC_ERR_DROP_TX        = 4'd4;  // Container dropped TX

  // PTB error codes (source = ERR_SRC_PTB)
  localparam logic [3:0] PTB_ERR_UNLOCK         = 4'd0;  // PTB lost lock
  localparam logic [3:0] PTB_ERR_UPDATE         = 4'd1;  // PTB update error

endpackage

`default_nettype wire
