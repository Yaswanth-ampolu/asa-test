`default_nettype none

// ASA Register Model Package
// Spec: Sections 3.1-3.8 (pages 28-92)
// Defines register addressing, access types, domain structure, and metadata

package asa_reg_pkg;

  // =========================================================================
  // Address format: d.a or d.i.a (Section 3.1)
  // =========================================================================

  // Domain encoding (Section 3.1)
  typedef enum logic [2:0] {
    REG_DOM_USER     = 3'd0,  // Implementer-defined
    REG_DOM_PHY      = 3'd1,  // PMA/PMD/PCS + MLE
    REG_DOM_DLL      = 3'd2,  // Data Link Layer, PTB, mapper, demux, LS
    REG_DOM_SEC      = 3'd3,  // Security
    REG_DOM_ASE      = 3'd4,  // Application Stream Encapsulator
    REG_DOM_ASD      = 3'd5   // Application Stream Decapsulator
  } reg_domain_e;

  // R/W type (Section 3.1)
  typedef enum logic [1:0] {
    REG_RW  = 2'd0,  // Normal read/write
    REG_RO  = 2'd1,  // Read-only (writes ignored)
    REG_SC  = 2'd2   // Self-clearing: returns value then clears to 0
  } reg_rw_type_e;

  // Access channel (Section 3.1)
  typedef enum logic {
    REG_ACCESS_L = 1'b0,  // Local register bus only
    REG_ACCESS_O = 1'b1   // OAM channel and local (O implies L)
  } reg_access_e;

  // Privilege level (Section 3.1)
  typedef enum logic [1:0] {
    REG_PRIV_NONE = 2'd0,  // No restriction
    REG_PRIV_RID  = 2'd1,  // Root nodeID only
    REG_PRIV_A    = 2'd2   // Authenticated link only
  } reg_privilege_e;

  // =========================================================================
  // Decoded register address structure
  // =========================================================================
  typedef struct packed {
    reg_domain_e    domain;       // [2:0]
    logic [5:0]     subdomain;    // DLP port ID (1-63 for ASE/ASD, 0 otherwise)
    logic [14:0]    addr;         // Register number within domain
  } reg_addr_t;

  // Bit-field select for partial register access
  typedef struct packed {
    logic           valid;        // 1 = bit-field access active
    logic [3:0]     msb;          // Bit position MSB
    logic [3:0]     lsb;          // Bit position LSB
  } reg_bitsel_t;

  // =========================================================================
  // Register metadata entry (per-register)
  // =========================================================================
  typedef struct packed {
    reg_rw_type_e   rw_type;      // RO / RW / SC
    reg_access_e    access;       // L / O
    reg_privilege_e privilege;    // NONE / RID / A
    logic           soft_reset_clears; // 1 = cleared by SoftReset
  } reg_meta_t;

  // =========================================================================
  // Bus request/response
  // =========================================================================
  typedef struct packed {
    reg_addr_t      addr;
    reg_bitsel_t    bitsel;
    logic [15:0]    wr_data;
    logic           wr_en;
    logic           rd_en;
    logic           oam_path;     // 1 = request from OAM channel
    logic [4:0]     src_node_id;  // Source nodeID (for RID check)
    logic           authenticated; // 1 = link is authenticated
  } reg_req_t;

  typedef struct packed {
    logic [15:0]    rd_data;
    logic           ack;
    logic           err_access;   // Access violation
    logic           err_addr;     // Invalid address
  } reg_resp_t;

  // =========================================================================
  // Domain 1 address constants (Section 3.2)
  // =========================================================================
  localparam logic [14:0] ADDR_PMA_CAPABILITY    = 15'd1;    // 1.0001
  localparam logic [14:0] ADDR_SGCONFIG          = 15'd2;    // 1.0002
  localparam logic [14:0] ADDR_PMA_CAPABILITY2   = 15'd3;    // 1.0003
  localparam logic [14:0] ADDR_CONNECTIVITY_ID   = 15'd4;    // 1.0004
  localparam logic [14:0] ADDR_ASA_VERSION       = 15'd5;    // 1.0005
  localparam logic [14:0] ADDR_NODE_STATE        = 15'd6;    // 1.0006
  localparam logic [14:0] ADDR_SOFT_RESET        = 15'd7;    // 1.0007
  localparam logic [14:0] ADDR_NODE_IRQ          = 15'd8;    // 1.0008
  localparam logic [14:0] ADDR_MLE_CAP1          = 15'd20;   // 1.0020
  localparam logic [14:0] ADDR_MLE_CAP2          = 15'd21;   // 1.0021
  localparam logic [14:0] ADDR_MLE_CONFIG        = 15'd22;   // 1.0022
  localparam logic [14:0] ADDR_LINK_TRAINING     = 15'd100;  // 1.0100
  localparam logic [14:0] ADDR_LINK_QUALITY      = 15'd101;  // 1.0101
  localparam logic [14:0] ADDR_SQI               = 15'd102;  // 1.0102
  localparam logic [14:0] ADDR_MSE               = 15'd103;  // 1.0103
  localparam logic [14:0] ADDR_FEC_STAT          = 15'd104;  // 1.0104
  localparam logic [14:0] ADDR_HARNESS_DIAG      = 15'd105;  // 1.0105
  localparam logic [14:0] ADDR_DIAG_TEST_CTRL    = 15'd106;  // 1.0106
  localparam logic [14:0] ADDR_LINK_IDENT        = 15'd107;  // 1.0107
  localparam logic [14:0] ADDR_EXT_LINK_TRAIN    = 15'd108;  // 1.0108

  // =========================================================================
  // Domain 2 address constants (Section 3.3)
  // =========================================================================
  localparam logic [14:0] ADDR_NODE_ID           = 15'd1;    // 2.0001
  localparam logic [14:0] ADDR_DLL_CONFIG1       = 15'd2;    // 2.0002
  localparam logic [14:0] ADDR_DLL_CONFIG2       = 15'd3;    // 2.0003
  localparam logic [14:0] ADDR_VENDOR_ID_LO      = 15'd4;    // 2.0004
  localparam logic [14:0] ADDR_VENDOR_ID_HI      = 15'd5;    // 2.0005
  localparam logic [14:0] ADDR_DEVICE_ID_LO      = 15'd6;    // 2.0006
  localparam logic [14:0] ADDR_DEVICE_ID_HI      = 15'd7;    // 2.0007
  localparam logic [14:0] ADDR_DLL_ADDR_TBL_BASE = 15'd8;    // 2.0008
  localparam logic [14:0] ADDR_DLL_ADDR_TBL_END  = 15'd133;  // 2.0133
  localparam logic [14:0] ADDR_DLL_TX_ERR        = 15'd140;  // 2.0140
  localparam logic [14:0] ADDR_DLL_COUNTER       = 15'd141;  // 2.0141
  localparam logic [14:0] ADDR_DLL_COUNTER_MIN   = 15'd142;  // 2.0142
  localparam logic [14:0] ADDR_DLL_COUNTER_MAX   = 15'd143;  // 2.0143
  localparam logic [14:0] ADDR_DLL_LINE_MIN      = 15'd144;  // 2.0144
  localparam logic [14:0] ADDR_DLL_LINE_MAX      = 15'd145;  // 2.0145
  localparam logic [14:0] ADDR_DLL_MAPPER_BASE   = 15'd146;  // 2.0146
  localparam logic [14:0] ADDR_DLL_MAPPER_END    = 15'd2065; // 2.2065
  localparam logic [14:0] ADDR_DLL_MTABLE_LEN    = 15'd2066; // 2.2066
  localparam logic [14:0] ADDR_DLL_DMX1_BASE     = 15'd2067; // 2.2067
  localparam logic [14:0] ADDR_DLL_DMX1_END      = 15'd2130; // 2.2130
  localparam logic [14:0] ADDR_DLL_DMX2_BASE     = 15'd2131; // 2.2131
  localparam logic [14:0] ADDR_DLL_DMX2_END      = 15'd2146; // 2.2146
  localparam logic [14:0] ADDR_DLL_DMX_STATUS    = 15'd2147; // 2.2147
  localparam logic [14:0] ADDR_OAM_DMX_TX        = 15'd2148; // 2.2148
  localparam logic [14:0] ADDR_PTB_CLK_LO        = 15'd2200; // 2.2200
  localparam logic [14:0] ADDR_PTB_CLK_MID       = 15'd2201; // 2.2201
  localparam logic [14:0] ADDR_PTB_CLK_HI        = 15'd2202; // 2.2202
  localparam logic [14:0] ADDR_PTB_STATUS        = 15'd2203; // 2.2203
  localparam logic [14:0] ADDR_PTB_OAM_CLK_LO    = 15'd2204; // 2.2204
  localparam logic [14:0] ADDR_PTB_OAM_CLK_MID   = 15'd2205; // 2.2205
  localparam logic [14:0] ADDR_PTB_OAM_CLK_HI    = 15'd2206; // 2.2206
  localparam logic [14:0] ADDR_PTB_OAM_DLY       = 15'd2207; // 2.2207
  localparam logic [14:0] ADDR_OAM_ERRORS1       = 15'd2208; // 2.2208
  localparam logic [14:0] ADDR_OAM_ERRORS2       = 15'd2209; // 2.2209
  localparam logic [14:0] ADDR_DLL_ERRORS1       = 15'd2210; // 2.2210
  localparam logic [14:0] ADDR_DLL_ERRORS2       = 15'd2211; // 2.2211
  localparam logic [14:0] ADDR_EXT_PTB_STATUS    = 15'd2212; // 2.2212
  localparam logic [14:0] ADDR_LS_CAPABILITY     = 15'd2250; // 2.2250
  localparam logic [14:0] ADDR_LS_STATUS1        = 15'd2251; // 2.2251
  localparam logic [14:0] ADDR_LS_STATUS2        = 15'd2252; // 2.2252
  localparam logic [14:0] ADDR_LS_TEST1          = 15'd2253; // 2.2253
  localparam logic [14:0] ADDR_LS_TEST2_BASE     = 15'd2254; // 2.2254
  localparam logic [14:0] ADDR_LS_TEST2_END      = 15'd2256; // 2.2256

  // =========================================================================
  // Domain 3 address constants (Section 3.4)
  // =========================================================================
  localparam logic [14:0] ADDR_SEC_POLICY        = 15'd1;    // 3.0001
  localparam logic [14:0] ADDR_SEC_DROP_RX       = 15'd2;    // 3.0002
  localparam logic [14:0] ADDR_SEC_DROP_TX       = 15'd3;    // 3.0003

  // =========================================================================
  // Domain 4/5 common ASEP address constants (Section 3.5-3.6)
  // =========================================================================
  localparam logic [14:0] ADDR_ASEP_PKT_ID_LO   = 15'd1;    // d.i.0001
  localparam logic [14:0] ADDR_ASEP_PKT_ID_MID  = 15'd2;    // d.i.0002
  localparam logic [14:0] ADDR_ASEP_PKT_ID_HI   = 15'd3;    // d.i.0003
  localparam logic [14:0] ADDR_ASEP_STREAM_TYPE  = 15'd4;    // d.i.0004
  localparam logic [14:0] ADDR_ASEP_VENDOR_ID    = 15'd5;    // d.i.0005
  localparam logic [14:0] ADDR_ASEP_TEST         = 15'd6;    // d.i.0006

  // =========================================================================
  // Helper functions
  // =========================================================================

  // Check if a domain uses subdomains
  function automatic logic domain_has_subdomain(reg_domain_e d);
    return (d == REG_DOM_ASE) || (d == REG_DOM_ASD);
  endfunction

  // Validate subdomain range (1-63, 0 is reserved)
  function automatic logic valid_subdomain(logic [5:0] sub);
    return (sub != 6'd0);
  endfunction

endpackage

`default_nettype wire
