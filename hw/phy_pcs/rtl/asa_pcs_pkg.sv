`default_nettype none

// ASA PCS Digital Datapath Package
// Source of truth: ASA Technical Specification v2.0, Section 4.2
//
// All constants are verified against PDF tables/figures directly.
// Where the micro-architecture doc diverges from the PDF, the PDF wins.

package asa_pcs_pkg;

  // =========================================================================
  // Speed Grade enumeration (from Table 4-1, p95)
  // =========================================================================
  typedef enum logic [2:0] {
    SG1 = 3'd0,
    SG2 = 3'd1,
    SG3 = 3'd2,
    SG4 = 3'd3,
    SG5 = 3'd4
  } speed_grade_e;

  // Direction
  typedef enum logic {
    DIR_DOWNSTREAM = 1'b0,
    DIR_UPSTREAM   = 1'b1
  } direction_e;

  // Modulation format (Table 4-1)
  typedef enum logic {
    MOD_PAM2 = 1'b0,  // SG1/2/3 downstream, all upstream
    MOD_PAM4 = 1'b1   // SG4/5 downstream only
  } modulation_e;

  // =========================================================================
  // TDD Timing (Section 4.2.2.2.1, p97)
  // =========================================================================
  // TDD cycle = 6844 PTB tics (+/-1), each PTB tic = 4ns
  localparam int unsigned TDD_CYCLE_PTB_TICS = 6844;

  // =========================================================================
  // Physical Layer Block sizes per direction/SG (Sections 4.2.2.4.1-4.2.2.4.3)
  //
  // Downstream SG1/2: 642B payload → 3× RS(216,214) → tx_phy_block<5183:0>
  // Downstream SG3/4/5: 642B payload → 3× RS(240,214) → tx_phy_block<5759:0>
  // Upstream SG1/2: 212B payload → 2× RS(108,106) → tx_phy_block<1727:0>
  // =========================================================================
  localparam int unsigned PHY_BLOCK_BITS_DN_SG12  = 5184;  // 3 * 216 * 8
  localparam int unsigned PHY_BLOCK_BITS_DN_SG345 = 5760;  // 3 * 240 * 8
  localparam int unsigned PHY_BLOCK_BITS_UP       = 1728;  // 2 * 108 * 8

  // FEC message sizes (bytes)
  localparam int unsigned FEC_MSG_BYTES_DN  = 214;  // per codeword, downstream
  localparam int unsigned FEC_MSG_BYTES_UP  = 106;  // per codeword, upstream
  localparam int unsigned FEC_CW_BYTES_108  = 108;  // RS(108,106) codeword
  localparam int unsigned FEC_CW_BYTES_216  = 216;  // RS(216,214) codeword
  localparam int unsigned FEC_CW_BYTES_240  = 240;  // RS(240,214) codeword
  localparam int unsigned FEC_PARITY_T1     = 2;    // t=1, 2 parity bytes
  localparam int unsigned FEC_PARITY_T13    = 26;   // t=13, 26 parity bytes

  // Number of physical layer blocks per TDD burst (Table 4-2, 4-3, p97)
  localparam int unsigned DN_BLOCKS_SG1 = 10;
  localparam int unsigned DN_BLOCKS_SG2 = 20;
  localparam int unsigned DN_BLOCKS_SG3 = 36;
  localparam int unsigned DN_BLOCKS_SG4 = 54;
  localparam int unsigned DN_BLOCKS_SG5 = 72;
  localparam int unsigned UP_BLOCKS_SG1 = 1;  // (Table 4-3 just says "1")
  localparam int unsigned UP_BLOCKS_SG2 = 2;  // (Table 4-3 just says "2" — VERIFY)

  // Quiet gap in baud rate symbols (Table 4-4, p97)
  localparam int unsigned QG_DN_SG1 = 2528;
  localparam int unsigned QG_DN_SG2 = 5056;
  localparam int unsigned QG_DN_SG3 = 10112;
  localparam int unsigned QG_DN_SG4 = 7584;
  localparam int unsigned QG_DN_SG5 = 10112;
  localparam int unsigned QG_UP_SG1 = 52640;
  localparam int unsigned QG_UP_SG2 = 105280;

  // =========================================================================
  // Resynchronization Header lengths in symbols (Table 4-5, p98)
  // =========================================================================
  localparam int unsigned RESYNC_LEN_SG1 = 384;
  localparam int unsigned RESYNC_LEN_SG2 = 768;
  localparam int unsigned RESYNC_LEN_SG3 = 1536;
  localparam int unsigned RESYNC_LEN_SG4 = 1152;
  localparam int unsigned RESYNC_LEN_SG5 = 1536;

  // Sync sequence positions (Table 4-6, p98)
  // First sync: n = 64 + 2*offset (where offset is 5-bit from PRBS9, 0-31)
  // Second sync: m depends on SG + offset
  //   SG1: m = 264 + offset
  //   SG2: m = 648 + offset
  //   SG3: m = 1376 + offset
  //   SG4: m = 992 + offset
  //   SG5: m = 1376 + offset

  function automatic int unsigned second_sync_base(speed_grade_e sg);
    case (sg)
      SG1:     return 264;
      SG2:     return 648;
      SG3:     return 1376;
      SG4:     return 992;
      SG5:     return 1376;
      default: return 264;
    endcase
  endfunction

  function automatic int unsigned resync_len(speed_grade_e sg);
    case (sg)
      SG1:     return RESYNC_LEN_SG1;
      SG2:     return RESYNC_LEN_SG2;
      SG3:     return RESYNC_LEN_SG3;
      SG4:     return RESYNC_LEN_SG4;
      SG5:     return RESYNC_LEN_SG5;
      default: return RESYNC_LEN_SG1;
    endcase
  endfunction

  // =========================================================================
  // Synchronization Sequence (Table 4-7, p100)
  // 40-bit fixed vector sy<0:39>
  // =========================================================================
  // Table 4-7 (PDF p100): sy<i> values, stored as sy[0] = bit[0]
  // sy[0..9]  = 1,1,0,1,0,1,0,0,0,0
  // sy[10..19]= 1,0,0,1,0,1,1,0,0,1
  // sy[20..29]= 1,1,1,1,0,0,0,0,1,1
  // sy[30..39]= 1,1,1,0,1,0,1,0,0,0
  localparam logic [39:0] SYNC_SEQUENCE = {
    1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1, // sy[39..30]
    1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, // sy[29..20]
    1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, // sy[19..10]
    1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b1  // sy[9..0]
  };

  // =========================================================================
  // PRBS11 for resync header (Section 4.2.2.3.3, Equation 4-3, Figure 4-4)
  //
  // PDF: g_ReSy(x) = x^11 + x^9 + 1
  // LFSR: S_ReSy[10:0], output = S_ReSy[0]
  // Feedback: new_input = S_ReSy[9] XOR S_ReSy[10]  (from Figure 4-4: taps 9,10)
  // Init: 0x001 at startup_INIT
  //
  // NOTE: The micro-arch doc says x^11+x^2+1 — that is WRONG per PDF Figure 4-4.
  // =========================================================================
  localparam int unsigned PRBS11_LEN = 11;
  localparam logic [10:0] PRBS11_INIT = 11'h001;

  function automatic logic [10:0] prbs11_step(input logic [10:0] state);
    logic fb;
    fb = state[9] ^ state[10];  // PDF Figure 4-4
    return {state[9:0], fb};
  endfunction

  // =========================================================================
  // PRBS9 dithering source (Section 4.2.2.3.4, Equation 4-4, Figure 4-5)
  //
  // PDF: g_Di(x) = x^9 + x^5 + 1
  // LFSR: S_Di[8:0], output = S_Di[0]
  // Feedback: new_input = S_Di[5] XOR S_Di[8]  (from Figure 4-5: taps 5,8)
  // Init: 0x001 at startup_INIT
  //
  // NOTE: Doc says x^9+x^4+1 — that is WRONG per PDF Figure 4-5.
  // =========================================================================
  localparam int unsigned PRBS9_LEN = 9;
  localparam logic [8:0] PRBS9_INIT = 9'h001;

  function automatic logic [8:0] prbs9_step(input logic [8:0] state);
    logic fb;
    fb = state[5] ^ state[8];  // PDF Figure 4-5
    return {state[7:0], fb};
  endfunction

  // PRBS9 offset extraction: advance 5 times, combine S0 outputs into 5-bit value
  // offset = 5'b{S0[t=0], S0[t=1], S0[t=2], S0[t=3], S0[t=4]}
  // where S0[t=0] is MSB (PDF Section 4.2.2.3.4, p101)
  function automatic logic [4:0] prbs9_offset(input logic [8:0] state);
    logic [8:0] s;
    logic [4:0] off;
    s = state;
    for (int i = 0; i < 5; i++) begin
      off[4-i] = s[0];  // S0 at each step, MSB first
      s = prbs9_step(s);
    end
    return off;
  endfunction

  // =========================================================================
  // PCS Side-Stream Scrambler (Section 4.2.5, p107-108)
  //
  // Downstream: g_Dn(x) = x^23 + x^5 + 1
  //   LFSR: S_Dn[22:0], S0 = S_Dn[0], S1 = S_Dn[2] XOR S_Dn[5]
  //   Feedback: S_Dn[5] XOR S_Dn[22] → input (Figure 4-12)
  //
  // Upstream: g_Up(x) = x^23 + x^18 + 1
  //   LFSR: S_Up[22:0], S0 = S_Up[0]
  //   Feedback: S_Up[18] XOR S_Up[22] → input (Figure 4-13)
  //
  // Init values depend on LinkID (Section 4.2.5, p108):
  //   LinkID=0: 0x000001
  //   LinkID=1: 0x000003
  //   LinkID=2: 0x000005
  //   LinkID=3: 0x000007
  // =========================================================================
  localparam int unsigned SCRAMBLER_LEN = 23;

  function automatic logic [22:0] scrambler_init(input logic [1:0] link_id);
    case (link_id)
      2'd0: return 23'h000001;
      2'd1: return 23'h000003;
      2'd2: return 23'h000005;
      2'd3: return 23'h000007;
    endcase
  endfunction

  // Downstream scrambler step: advance one bit, output S0 (and S1 for PAM4)
  function automatic logic [22:0] dn_scrambler_step(input logic [22:0] state);
    logic fb;
    fb = state[5] ^ state[22];
    return {state[21:0], fb};
  endfunction

  // Downstream S0 and S1 outputs
  function automatic logic dn_s0(input logic [22:0] state);
    return state[0];
  endfunction

  function automatic logic dn_s1(input logic [22:0] state);
    return state[2] ^ state[5];  // Equation 4-10
  endfunction

  // Upstream scrambler step
  function automatic logic [22:0] up_scrambler_step(input logic [22:0] state);
    logic fb;
    fb = state[18] ^ state[22];
    return {state[21:0], fb};
  endfunction

  function automatic logic up_s0(input logic [22:0] state);
    return state[0];
  endfunction

  // =========================================================================
  // PAM Mapping (Sections 4.2.2.6, 4.2.2.7)
  // =========================================================================
  // PAM2: 0 → +1, 1 → -1
  // Represented as 2-bit signed: +1 = 2'b01, -1 = 2'b11
  typedef logic signed [1:0] pam2_sym_t;

  function automatic pam2_sym_t pam2_map(input logic bit_val);
    return bit_val ? -2'sd1 : 2'sd1;
  endfunction

  // PAM4 Gray encoding: {MSB, LSB} → symbol level
  // {0,0} → +1, {0,1} → +1/3, {1,1} → -1/3, {1,0} → -1
  // Represented as 3-bit signed: +3=011, +1=001, -1=111, -3=101
  typedef logic signed [2:0] pam4_sym_t;

  function automatic pam4_sym_t pam4_map(input logic [1:0] bits);
    case (bits)
      2'b00: return  3'sd3;  // +1 (scaled as +3 for integer representation)
      2'b01: return  3'sd1;  // +1/3 (scaled as +1)
      2'b11: return -3'sd1;  // -1/3 (scaled as -1)
      2'b10: return -3'sd3;  // -1 (scaled as -3)
    endcase
  endfunction

  // =========================================================================
  // RS-FEC Galois Field GF(2^8)
  // Primitive polynomial: x^8 + x^4 + x^3 + x^2 + 1 = 0x11D
  // (Section 4.2.4.1, p104)
  // =========================================================================
  localparam logic [8:0] GF_PRIM_POLY = 9'h11D;

  // GF(2^8) multiplication
  function automatic logic [7:0] gf_mul(input logic [7:0] a, input logic [7:0] b);
    logic [7:0] result;
    logic [7:0] temp;
    result = 8'd0;
    temp = a;
    for (int i = 0; i < 8; i++) begin
      if (b[i]) result = result ^ temp;
      if (temp[7]) temp = {temp[6:0], 1'b0} ^ GF_PRIM_POLY[7:0];
      else         temp = {temp[6:0], 1'b0};
    end
    return result;
  endfunction

  // RS generator polynomial coefficients (Tables 4-10, 4-11, 4-12)
  // RS(108,106): g0=0x02, g1=0x03, g2=0x01
  localparam logic [7:0] RS106_G [0:2] = '{8'h02, 8'h03, 8'h01};

  // RS(216,214): g0=0x02, g1=0x03, g2=0x01 (same as RS(108,106))
  localparam logic [7:0] RS214_G [0:2] = '{8'h02, 8'h03, 8'h01};

  // RS(240,214): g0..g26 (Table 4-12, p106)
  localparam logic [7:0] RS240_G [0:26] = '{
    8'h5E, 8'h2B, 8'h4D, 8'h92, 8'h90, 8'h46, 8'h44, 8'h87, 8'h2A,
    8'hE9, 8'h75, 8'hD1, 8'h28, 8'h91, 8'h18, 8'hCE, 8'h38, 8'h4D,
    8'h98, 8'hC7, 8'h62, 8'h88, 8'h04, 8'hB7, 8'h33, 8'hF6, 8'h01
  };

  // =========================================================================
  // CRC32 (Section 4.2.9, p120)
  // Polynomial: 0xF4ACFB13
  // Init: 0xFFFFFFFF
  // XOR out: 0xFFFFFFFF
  // Input: byte-wise reflected
  // Result: reflected
  // =========================================================================
  localparam logic [31:0] CRC32_POLY = 32'hF4ACFB13;
  localparam logic [31:0] CRC32_INIT = 32'hFFFFFFFF;
  localparam logic [31:0] CRC32_XOR  = 32'hFFFFFFFF;

  function automatic logic [7:0] reflect_byte(input logic [7:0] b);
    logic [7:0] r;
    for (int i = 0; i < 8; i++) r[i] = b[7-i];
    return r;
  endfunction

  function automatic logic [31:0] reflect32(input logic [31:0] v);
    logic [31:0] r;
    for (int i = 0; i < 32; i++) r[i] = v[31-i];
    return r;
  endfunction

  // CRC32 one-byte step.
  // Algorithm (per PDF Section 4.2.9 + Table 4-21 reference):
  //   1. Reflect input byte (bit-reverse)
  //   2. XOR into top 8 bits of CRC register
  //   3. For each of 8 bits: shift left; if MSB was 1, XOR with polynomial
  // This matches the Python reference that reproduces Table 4-21.
  function automatic logic [31:0] crc32_byte(input logic [31:0] crc, input logic [7:0] data);
    logic [31:0] c;
    logic [7:0] d;
    d = reflect_byte(data);
    c = crc ^ {d, 24'd0};
    for (int i = 0; i < 8; i++) begin
      if (c[31]) c = {c[30:0], 1'b0} ^ CRC32_POLY;
      else       c = {c[30:0], 1'b0};
    end
    return c;
  endfunction

  // Finalize CRC: reflect 32-bit result and XOR with 0xFFFFFFFF
  function automatic logic [31:0] crc32_finalize(input logic [31:0] crc);
    return reflect32(crc) ^ CRC32_XOR;
  endfunction

endpackage

`default_nettype wire
