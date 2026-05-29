`default_nettype none

// ASA Link Layer Security (LLS) Package
// Source of truth: ASA Technical Specification v2.0, Section 6.3 (pp196-203)
// Figure 6-2 and Table 6-2 verified against PDF image/text.
//
// PDF-verified facts:
// - IV = Fixed(32b) || Invocation(64b) = 96 bits (Table 6-1, p197)
// - Fixed field: {KeyEx(1b)=0, Dir(1b), Salt(30b)}
//   NOTE: doc says Salt=1bit but PDF Table 6-1 shows Salt=30 bits. PDF wins.
// - Counter = least significant 8 bits of 64-bit TX AEAD Invocation Counter
// - Security Payload layout (Figure 6-2, Table 6-2):
//   byte0 = PPF byte (bit7=protection_flag, bits6:0=reserved)
//   byte1 = Counter (LSB 8 bits of 64-bit invocation counter)
//   byte2..byte2+N-1 = DLL Payload (N bytes, unchanged or encrypted)
//   byte2+N..byte2+N+15 = ICV (128 bits = 16 bytes)
//   NOTE: Table 6-2 shows byte position 3 for DLL Payload which appears to be
//   a formatting issue; Figure 6-2 shows PPF|Counter|Payload|ICV contiguously.
//   IMPLEMENTATION ASSUMPTION: byte2 = DLL Payload start.
// - ICV = 128 bits (16 bytes), Auth Tag from AES-GCM or AES-GMAC
// - TX AEAD Invocation Counter starts at 1, increments per protected container
// - RX counter reconstruction: split last_rx_ctr into shadow(56b)||last_lo(8b)
//   if received_lo > last_lo: assume_ctr = shadow || received_lo
//   else:                     assume_ctr = (shadow+1) || received_lo
// - Two key slots; KeySwitch=0 → slot 0, KeySwitch=1 → slot 1
// - Bypass: KeyEx OAM frames, Node-Discover, Self-Announce always bypass
// - Counter overflow thresholds: <10% margin → report, <5% → report, 0 → deactivate

package asa_lls_pkg;

  // =========================================================================
  // Security policy (register 3.0001, bits 1:0) — PDF p65
  // =========================================================================
  typedef enum logic [1:0] {
    SEC_POLICY_NONE       = 2'b00, // No security
    SEC_POLICY_AUTH_ONLY  = 2'b01, // Authentication only (AES-GMAC-128 mandatory)
    SEC_POLICY_RESERVED   = 2'b10, // Reserved — must not be used
    SEC_POLICY_AUTH_ENC   = 2'b11  // Authentication + Encryption (AES-GCM-128)
  } lls_policy_e;

  // =========================================================================
  // Key slot state — inferred from Section 6.3.3.1 / 6.3.4.1 usage
  // IMPLEMENTATION ASSUMPTION: state names are inferred, not normative
  // =========================================================================
  typedef enum logic [1:0] {
    SLOT_EMPTY      = 2'd0, // No key installed (factory default)
    SLOT_READY      = 2'd1, // Key installed, not yet confirmed active for RX
    SLOT_ACTIVE     = 2'd2, // Currently used for encryption/decryption
    SLOT_DEACTIVATED= 2'd3  // Old slot after key rotation
  } lls_slot_state_e;

  // =========================================================================
  // IV construction (Table 6-1, PDF p197)
  // Fixed(32b) = {KeyEx(1b)=0, Dir(1b), Salt(30b)}
  // Invocation(64b) = TX AEAD Invocation Counter
  // =========================================================================
  localparam int unsigned LLS_IV_BITS       = 96;
  localparam int unsigned LLS_ICV_BYTES     = 16;   // 128-bit ICV
  localparam int unsigned LLS_COUNTER_BYTES = 1;    // 8-bit counter in payload
  localparam int unsigned LLS_PPF_BYTES     = 1;    // Protection flag byte
  localparam int unsigned LLS_OVERHEAD_BYTES = LLS_PPF_BYTES + LLS_COUNTER_BYTES + LLS_ICV_BYTES; // 18

  // IV builder: Dir=0 for downstream, Dir=1 for upstream (PDF p197)
  function automatic logic [95:0] lls_build_iv(
    input logic        dir,            // 0=downstream, 1=upstream
    input logic [29:0] salt,           // 30-bit salt from key installation
    input logic [63:0] tx_ctr          // TX AEAD Invocation Counter
  );
    logic [31:0] fixed_field;
    fixed_field = {1'b0, dir, salt};   // KeyEx=0 || Dir || Salt(30b)
    return {fixed_field, tx_ctr};      // Fixed[31:0] || Invocation[63:0]
  endfunction

  // =========================================================================
  // RX counter reconstruction (Section 6.3.4.1, PDF p201)
  // =========================================================================
  function automatic logic [63:0] lls_reconstruct_rx_ctr(
    input logic [63:0] last_rx_ctr,     // Last RX AEAD Invocation Counter
    input logic [7:0]  received_ctr_lo  // Counter byte from received payload
  );
    logic [55:0] shadow;
    logic [7:0]  last_lo;
    shadow  = last_rx_ctr[63:8];
    last_lo = last_rx_ctr[7:0];

    if (received_ctr_lo > last_lo)
      return {shadow, received_ctr_lo};
    else
      return {shadow + 56'd1, received_ctr_lo};
  endfunction

  // =========================================================================
  // Bypass classification (Section 6.3.4.1/6.3.4.2, PDF pp200-202)
  // bypass_type encodes reason for clarity
  // =========================================================================
  typedef enum logic [2:0] {
    BYPASS_NONE          = 3'd0, // Not a bypass — must apply security
    BYPASS_KEYEX_OAM     = 3'd1, // KeyEx OAM frame — always bypass
    BYPASS_NODE_DISCOVER = 3'd2, // Node-Discover enumeration message
    BYPASS_SELF_ANNOUNCE = 3'd3, // Self-Announce enumeration message
    BYPASS_EMPTY_OAM_PRELK=3'd4, // Empty OAM frame before LKs installed
    BYPASS_NO_POLICY     = 3'd5  // securityPolicy=NONE — no security entity
  } lls_bypass_reason_e;

  // =========================================================================
  // Error/status codes
  // =========================================================================
  typedef enum logic [2:0] {
    LLS_OK           = 3'd0,
    LLS_AUTH_FAIL    = 3'd1, // RX ICV mismatch (auth failure)
    LLS_DECRYPT_FAIL = 3'd2, // RX decrypt failure (GCM)
    LLS_OAM_FILTER   = 3'd3, // Non-exempt OAM suppressed (LKs not installed)
    LLS_SLOT_INVALID = 3'd4, // Key slot not ready/active
    LLS_CTR_OVERFLOW = 3'd5  // TX counter at maximum
  } lls_error_e;

  // =========================================================================
  // Counter overflow thresholds (PDF p202, Section 6.3.4.2)
  // 64-bit counter max = 2^64-1; thresholds as percentage
  // =========================================================================
  // 10% of 2^64 ≈ 0x1999_9999_9999_9999 remaining
  localparam logic [63:0] CTR_THRESHOLD_10PCT = 64'h1999_9999_9999_9999;
  // 5% of 2^64 ≈ 0x0CCC_CCCC_CCCC_CCCC remaining
  localparam logic [63:0] CTR_THRESHOLD_5PCT  = 64'h0CCC_CCCC_CCCC_CCCD;
  // Maximum value (overflow)
  localparam logic [63:0] CTR_MAX = 64'hFFFF_FFFF_FFFF_FFFF;

endpackage

`default_nettype wire
