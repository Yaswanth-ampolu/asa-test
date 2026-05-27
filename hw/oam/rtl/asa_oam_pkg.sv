`default_nettype none

// ASA OAM Control Plane Package
// Spec: Section 5.5 (pages 171-184), Section 6.4.2 (pages 205-206)
//
// Defines OAM-specific types, command codes, frame formats, and error encodings.
// Integrates with: asa_reg_pkg (register access), asa_intf_pkg (DLP primitives),
//                  asa_error_pkg (error reporting)

package asa_oam_pkg;
  import asa_reg_pkg::*;
  import asa_error_pkg::*;

  // =========================================================================
  // OAM Frame Constants
  // =========================================================================
  localparam int unsigned OAM_FRAME_SIZE     = 188;   // Total OAM frame bytes
  localparam int unsigned OAM_HEADER_SIZE    = 24;    // Header bytes
  localparam int unsigned OAM_PAYLOAD_SIZE   = 164;   // Available for CADs + padding
  localparam int unsigned LONGATOM_LIMIT     = 32;    // 32nd frame must be LongAtomClose
  localparam int unsigned OAM_MAX_FRAME_CADS = 32;    // Worst-case CAD count in one frame
  localparam int unsigned OAM_KEYEX_MAX_BYTES = OAM_PAYLOAD_SIZE - 1;

  // =========================================================================
  // Packed vector frame types
  // Byte N occupies bits [N*8+7 : N*8].  Byte 0 = bits[7:0].
  // =========================================================================
  typedef logic [1503:0] oam_frame_t;    // 188 bytes
  typedef logic [191:0]  oam_header_t;  // 24 bytes
  typedef logic [1311:0] oam_payload_t; // 164 bytes (bytes 24-187)
  typedef logic [47:0]   oam_hdr_phy_t; // 6 bytes for PTB/health sub-fields
  typedef logic [(OAM_KEYEX_MAX_BYTES*8)-1:0] oam_cad_bytes_t;

  // Read one byte from a packed frame at byte index idx (0=LSB end)
  function automatic logic [7:0] oam_get_byte(
    input logic [1503:0] frame,
    input int unsigned   idx
  );
    return frame[idx*8 +: 8];
  endfunction

  // Write one byte into a packed frame, returning the updated frame
  function automatic logic [1503:0] oam_set_byte(
    input logic [1503:0] frame,
    input int unsigned   idx,
    input logic [7:0]    value
  );
    logic [1503:0] result;
    result = frame;
    result[idx*8 +: 8] = value;
    return result;
  endfunction

  // Same helpers for the 24-byte header
  function automatic logic [7:0] oam_hdr_get_byte(
    input logic [191:0] hdr,
    input int unsigned  idx
  );
    return hdr[idx*8 +: 8];
  endfunction

  function automatic logic [191:0] oam_hdr_set_byte(
    input logic [191:0] hdr,
    input int unsigned  idx,
    input logic [7:0]   value
  );
    logic [191:0] result;
    result = hdr;
    result[idx*8 +: 8] = value;
    return result;
  endfunction

  // Same helpers for 164-byte payload
  function automatic logic [7:0] oam_pay_get_byte(
    input logic [1311:0] payload,
    input int unsigned   idx
  );
    return payload[idx*8 +: 8];
  endfunction

  function automatic logic [1311:0] oam_pay_set_byte(
    input logic [1311:0] payload,
    input int unsigned   idx,
    input logic [7:0]    value
  );
    logic [1311:0] result;
    result = payload;
    result[idx*8 +: 8] = value;
    return result;
  endfunction

  // Extract the 164-byte payload from a full 188-byte frame (bytes 24-187)
  function automatic oam_payload_t oam_frame_payload(input oam_frame_t frame);
    return frame[1503:192];  // bytes 24-187 = bits[1503:192]
  endfunction

  // Insert payload back into frame at bytes 24-187
  function automatic oam_frame_t oam_frame_set_payload(
    input oam_frame_t   frame,
    input oam_payload_t payload
  );
    oam_frame_t result;
    result = frame;
    result[1503:192] = payload;
    return result;
  endfunction

  // =========================================================================
  // OAM Command Codes (Table 5-4, p177)
  // =========================================================================
  typedef enum logic [6:0] {
    OAM_CMD_RESERVED         = 7'h00,
    OAM_CMD_READ             = 7'h01,
    OAM_CMD_RETURN           = 7'h02,
    OAM_CMD_READ_ERROR       = 7'h03,
    OAM_CMD_WRITE            = 7'h04,
    OAM_CMD_WRITE_ACK        = 7'h05,
    OAM_CMD_START_ENUM       = 7'h06,
    OAM_CMD_LONG_ATOM        = 7'h07,
    OAM_CMD_LONG_ATOM_CLOSE  = 7'h08,
    OAM_CMD_START_TDD        = 7'h09,
    OAM_CMD_LS_ANNOUNCE      = 7'h0A,
    OAM_CMD_LS_CONFIRM       = 7'h0B,
    OAM_CMD_LS_DENY          = 7'h0C,
    OAM_CMD_LS_SLEEP         = 7'h0D,
    OAM_CMD_KEYEX_REQ        = 7'h7C,  // Section 6.4.2.1
    OAM_CMD_KEYEX_RESP       = 7'h7D   // Section 6.4.2.2
  } oam_cmd_code_e;

  // CAD byte sizes per command type
  function automatic int unsigned cad_size(oam_cmd_code_e cmd);
    case (cmd)
      OAM_CMD_READ:            return 4;
      OAM_CMD_RETURN:          return 6;
      OAM_CMD_READ_ERROR:      return 6;
      OAM_CMD_WRITE:           return 6;
      OAM_CMD_WRITE_ACK:       return 6;
      OAM_CMD_START_ENUM:      return 6;
      OAM_CMD_LONG_ATOM:       return 2;
      OAM_CMD_LONG_ATOM_CLOSE: return 2;
      OAM_CMD_START_TDD:       return 12;
      OAM_CMD_LS_ANNOUNCE:     return 12;
      OAM_CMD_LS_CONFIRM:      return 4;
      OAM_CMD_LS_DENY:         return 2;
      OAM_CMD_LS_SLEEP:        return 10;
      OAM_CMD_KEYEX_REQ:       return 0; // variable length
      OAM_CMD_KEYEX_RESP:      return 0; // variable length
      default:                 return 0;
    endcase
  endfunction

  // OAMerror encoding (Table 5-2, byte 4 bits 5:3)
  typedef enum logic [2:0] {
    OAM_HDRFLD_NONE          = 3'd0,
    OAM_HDRFLD_DUPL_ID       = 3'd1,
    OAM_HDRFLD_MISS_ID       = 3'd2,
    OAM_HDRFLD_HDR_DECODE    = 3'd3,
    OAM_HDRFLD_CAD_DECODE    = 3'd4
  } oam_error_code_e;

  // =========================================================================
  // CAD Address Field (shared by Read/Return/ReadError/Write/WriteAck)
  // Section 5.5.3.1
  // =========================================================================
  typedef struct packed {
    logic [2:0]     domain;       // n+1 bits 7:5
    logic [5:0]     dlp_id;       // n+1 bits 4:0 + n+2 bit 7
    logic [14:0]    addr;         // n+2 bits 6:0 + n+3 bits 7:0
  } oam_cad_addr_t;

  // =========================================================================
  // ReadError codes (Section 5.5.3.3)
  // =========================================================================
  typedef enum logic [7:0] {
    READ_ERR_ADDR_NOT_EXIST = 8'h00,
    READ_ERR_ACCESS_DENIED  = 8'h01
  } read_error_code_e;

  // =========================================================================
  // WriteAck return codes (Section 5.5.3.5)
  // =========================================================================
  typedef enum logic [7:0] {
    WRITE_ACK_SUCCESS       = 8'h01,
    WRITE_ACK_FAIL          = 8'h02,
    WRITE_ACK_RO_ONLY       = 8'h04,
    WRITE_ACK_AUTH_DENIED   = 8'h06,
    WRITE_ACK_ADDR_MISSING  = 8'h08
  } write_ack_code_e;

  // =========================================================================
  // StartTDD parameters (Section 5.5.3.9)
  // =========================================================================
  typedef struct packed {
    logic [47:0]    ptb_time;     // PTB timestamp to start Normal Mode
    logic [15:0]    dll_line_min; // Mapper start pointer
    logic [15:0]    dll_line_max; // Mapper end pointer
  } start_tdd_params_t;

  // =========================================================================
  // Light Sleep CAD parameters (Sections 5.5.3.10-13)
  // =========================================================================
  typedef struct packed {
    logic [47:0]    ptb_bedtime;
    logic [11:0]    sleep_cycles;
    logic [7:0]     restart_cycles_1g;
    logic [7:0]     restart_cycles_sgx;
  } ls_announce_params_t;

  typedef struct packed {
    logic [7:0]     restart_cycles_1g_a;
    logic [7:0]     restart_cycles_sgx_a;
  } ls_confirm_params_t;

  typedef struct packed {
    logic [47:0]    ptb_alarmclock;
    logic [7:0]     restart_cycles_1g_f;
    logic [7:0]     restart_cycles_sgx_f;
  } ls_sleep_params_t;

  // =========================================================================
  // Decoded CAD command (output of CAD parser)
  // =========================================================================
  typedef struct packed {
    logic           valid;
    oam_cmd_code_e  cmd;
    oam_cad_addr_t  addr;         // Valid for Read/Write/Return/ReadError/WriteAck
    logic [15:0]    data;         // Valid for Write/Return
    logic [7:0]     error_code;   // Valid for ReadError/WriteAck
    logic [4:0]     free_node_id; // Valid for StartEnum
    logic [4:0]     longatom_cnt; // Valid for LongAtom
  } oam_decoded_cad_t;

  typedef struct packed {
    logic           valid;
    logic           is_response;
    logic [7:0]     payload_len;  // bytes after command byte
    oam_cad_bytes_t payload;      // byte0 = Primitive ID
  } oam_keyex_msg_t;

  typedef struct packed {
    logic           valid;
    logic [4:0]     target_id;
    logic           nd_en;
    logic [4:0]     target_id1;
    logic [4:0]     target_id2;
    logic [4:0]     target_id3;
    oam_cmd_code_e  cmd;
    logic [7:0]     payload_len;  // bytes after command byte, pre-encoded per spec
    oam_cad_bytes_t payload;
  } oam_tx_cmd_t;

  // =========================================================================
  // CAD Response entry (for CADrespFIFO)
  // =========================================================================
  typedef struct packed {
    logic           valid;
    oam_cmd_code_e  cmd;          // Return/ReadError/WriteAck/LSconfirm/LSdeny/KeyExResp
    oam_cad_addr_t  addr;         // Echo address for Return/ReadError/WriteAck
    logic [15:0]    data;         // Register value for Return, or error/ack code
  } oam_cad_resp_t;

  // =========================================================================
  // OAM TX request (to DLP_TX.oamUnit)
  // =========================================================================
  typedef struct packed {
    logic [4:0]     target_id;    // Destination nodeID
    logic [4:0]     packet_id;    // OAMframeID[4:0]
    logic           nd_en;        // Node-Discover extended header
    logic [4:0]     target_id1;   // Extended header target 1
    logic [4:0]     target_id2;   // Extended header target 2
    logic [4:0]     target_id3;   // Extended header target 3
  } oam_tx_meta_t;

  // =========================================================================
  // OAM RX descriptor (from DLP_RX.oamUnit)
  // =========================================================================
  typedef struct packed {
    logic           valid;
    logic [4:0]     src_node_id;  // Source nodeID (from container header)
    logic           phy_err;      // phylStat error flag
    logic           dll_err;      // dllStat error flag
    logic           sec_err;      // secStat error flag (VERIFY: spec unclear on usage)
  } oam_rx_status_t;

  // =========================================================================
  // OAM session state (per non-root node for root, single for non-root)
  // =========================================================================
  typedef struct packed {
    logic [31:0]    tx_frame_id;  // nID.txOAMframeID
    logic [31:0]    rx_frame_id;  // nID.rxOAMframeID
    oam_error_code_e pending_error; // Error to report in next TX header
  } oam_session_state_t;

  // =========================================================================
  // Register bridge request (OAM -> register access layer)
  // Maps to reg_req_t from asa_reg_pkg
  // =========================================================================
  function automatic reg_req_t oam_to_reg_req(
    oam_cad_addr_t  cad_addr,
    logic [15:0]    wr_data,
    logic           is_write,
    logic [4:0]     src_node_id,
    logic           authenticated
  );
    reg_req_t req;
    req.addr.domain    = reg_domain_e'(cad_addr.domain);
    req.addr.subdomain = cad_addr.dlp_id;
    req.addr.addr      = cad_addr.addr;
    req.bitsel.valid   = 1'b0;
    req.bitsel.msb     = 4'd0;
    req.bitsel.lsb     = 4'd0;
    req.wr_data        = wr_data;
    req.wr_en          = is_write;
    req.rd_en          = !is_write;
    req.oam_path       = 1'b1;
    req.src_node_id    = src_node_id;
    req.authenticated  = authenticated;
    return req;
  endfunction

  // Map register response to WriteAck code
  function automatic write_ack_code_e reg_resp_to_write_ack(reg_resp_t resp);
    if (resp.err_addr)   return WRITE_ACK_ADDR_MISSING;
    if (resp.err_access) return WRITE_ACK_RO_ONLY; // VERIFY: distinguishing RO vs auth
    if (resp.ack)        return WRITE_ACK_SUCCESS;
    return WRITE_ACK_FAIL;
  endfunction

  // Map register response to ReadError code
  function automatic read_error_code_e reg_resp_to_read_err(reg_resp_t resp);
    if (resp.err_addr)   return READ_ERR_ADDR_NOT_EXIST;
    if (resp.err_access) return READ_ERR_ACCESS_DENIED;
    return READ_ERR_ADDR_NOT_EXIST; // should not reach
  endfunction

endpackage

`default_nettype wire
