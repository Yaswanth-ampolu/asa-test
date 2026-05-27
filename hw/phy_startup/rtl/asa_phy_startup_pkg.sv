`default_nettype none

// ASA PHY startup package
// Spec: ASA v2.0 Sections 4.2.7 and 4.3.3.1.

package asa_phy_startup_pkg;

  typedef enum logic [1:0] {
    PHY_START_STAT_TRAINING = 2'b00,
    PHY_START_STAT_PREPARED = 2'b01,
    PHY_START_STAT_PROCEED  = 2'b10,
    PHY_START_STAT_ERROR    = 2'b11
  } phy_start_status_e;

  typedef enum logic [3:0] {
    PHY_START_IDLE     = 4'd0,
    PHY_START_INIT     = 4'd1,
    PHY_START_PHASE1G  = 4'd2,
    PHY_START_SGA      = 4'd3,
    PHY_START_SGB      = 4'd4,
    PHY_START_SGC      = 4'd5,
    PHY_START_TX_TEST  = 4'd6,
    PHY_START_RX_TEST  = 4'd7,
    PHY_START_COMPLETE = 4'd8,
    PHY_START_FAIL     = 4'd9
  } phy_start_phase_e;

  typedef enum logic [2:0] {
    PHY_TX_TEST_NONE      = 3'b000,
    PHY_TX_TEST_LINEARITY = 3'b001,
    PHY_TX_TEST_JITTER    = 3'b010,
    PHY_TX_TEST_DROOP     = 3'b011,
    PHY_TX_TEST_PSD       = 3'b100,
    PHY_TX_TEST_BER       = 3'b101
  } phy_tx_test_e;

  typedef enum logic [2:0] {
    PHY_RX_TEST_NONE   = 3'b000,
    PHY_RX_TEST_NOISE  = 3'b110,
    PHY_RX_TEST_BER    = 3'b111
  } phy_rx_test_e;

  typedef enum logic [2:0] {
    PHY_PATTERN_IDLE      = 3'd0,
    PHY_PATTERN_PHASE1G   = 3'd1,
    PHY_PATTERN_PHASE_SGA = 3'd2,
    PHY_PATTERN_PHASE_SGB = 3'd3,
    PHY_PATTERN_PHASE_SGC = 3'd4,
    PHY_PATTERN_TX_TEST   = 3'd5,
    PHY_PATTERN_RX_REPLY  = 3'd6
  } phy_start_pattern_e;

  localparam int unsigned PHY_PH1G_RTRY_CNT_LIMIT = 255;

  function automatic logic [7:0] phase1g_parity_byte(input logic [31:0] info_low);
    logic [7:0] parity;
    for (int k = 0; k < 8; k++) begin
      parity[k] = info_low[k] ^ info_low[8+k] ^ info_low[16+k] ^ info_low[24+k];
    end
    return parity;
  endfunction

  function automatic logic [39:0] build_phase1g_info(
    input phy_start_status_e status,
    input logic [13:0]       sg_capability,
    input logic [4:0]        sg_config_lsb,
    input phy_tx_test_e      tx_test,
    input logic [1:0]        security_policy,
    input logic              phy_layer_mode
  );
    logic [31:0] low;
    low = '0;
    low[31:30] = status;
    low[29:16] = sg_capability;
    low[15:11] = sg_config_lsb;
    low[10:8]  = tx_test;
    low[2:1]   = security_policy;
    low[0]     = phy_layer_mode;
    return {phase1g_parity_byte(low), low};
  endfunction

  function automatic logic [7:0] reflect8(input logic [7:0] value);
    logic [7:0] reflected;
    for (int k = 0; k < 8; k++) begin
      reflected[7-k] = value[k];
    end
    return reflected;
  endfunction

  function automatic logic [31:0] reflect32(input logic [31:0] value);
    logic [31:0] reflected;
    for (int k = 0; k < 32; k++) begin
      reflected[31-k] = value[k];
    end
    return reflected;
  endfunction

  // Section 4.2.9: polynomial 0xF4ACFB13, start value 0xFFFFFFFF,
  // final XOR 0xFFFFFFFF, byte-wise reflected input, reflected output.
  function automatic logic [31:0] asa_crc32(
    input logic [479:0] data,
    input int unsigned  byte_count
  );
    logic [31:0] crc;
    logic        feedback;
    logic [7:0]  byte_reflected;
    crc = 32'hFFFF_FFFF;
    for (int byte_idx = 0; byte_idx < byte_count; byte_idx++) begin
      byte_reflected = reflect8(data[byte_idx*8 +: 8]);
      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        feedback = crc[31] ^ byte_reflected[bit_idx];
        crc = {crc[30:0], 1'b0};
        if (feedback) crc ^= 32'hF4AC_FB13;
      end
    end
    return reflect32(crc) ^ 32'hFFFF_FFFF;
  endfunction

  function automatic logic [31:0] asa_crc32_480(input logic [479:0] data);
    return asa_crc32(data, 60);
  endfunction

  function automatic logic [511:0] build_phasesg_info(
    input phy_start_status_e status,
    input logic [23:0]       info_count,
    input logic              oam_config_skip,
    input phy_rx_test_e      rx_test
  );
    logic [479:0] low;
    low = '0;
    low[42:19] = info_count;
    low[18]    = oam_config_skip;
    low[17:16] = status;
    low[10:8]  = rx_test;
    return {asa_crc32_480(low), low};
  endfunction

  function automatic logic speed_grade_needs_sgc(input logic [15:0] sg_config);
    // Section 3.2.2 / startup doc: Dn SG 3'b011 and 3'b100 are SG4/SG5.
    return (sg_config[2:0] == 3'b011) || (sg_config[2:0] == 3'b100);
  endfunction

  function automatic logic [7:0] sat_inc8(input logic [7:0] value);
    return (value == 8'hFF) ? 8'hFF : value + 8'd1;
  endfunction

  function automatic logic [4:0] sat_inc5(input logic [4:0] value);
    return (value == 5'h1F) ? 5'h1F : value + 5'd1;
  endfunction

endpackage

`default_nettype wire
