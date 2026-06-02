`default_nettype none

package asa_mle_pcs_pkg;
  import asa_pcs_pkg::*;

  typedef enum logic [2:0] {
    MLES_SYM1G0 = 3'd0,
    MLES_SYM2G5 = 3'd1,
    MLES_SYM5G0 = 3'd2,
    MLES_2G5_M  = 3'd3,
    MLES_5G0_M  = 3'd4,
    MLES_10G_M  = 3'd5,
    MLES_10G_G  = 3'd6
  } mle_mode_e;

  typedef enum logic [1:0] {
    PH1G_TRAINING = 2'b00,
    PH1G_PREPARED = 2'b01,
    PH1G_PROCEED  = 2'b10,
    PH1G_ERROR    = 2'b11
  } ph1g_status_e;

  typedef enum logic [2:0] {
    OAM_CTL_IDLE = 3'd0,
    OAM_CTL_JJ   = 3'd1,
    OAM_CTL_JK   = 3'd2,
    OAM_CTL_TI   = 3'd3,
    OAM_CTL_DATA = 3'd4
  } oam_slot_kind_e;

  localparam int unsigned MLE_PLB_BITS          = 1920;
  localparam int unsigned MLE_PLB_PAYLOAD_BITS  = 1712;
  localparam int unsigned MLE_PLB_PARITY_BITS   = 208;
  localparam int unsigned MLE_PLB_PAYLOAD_BYTES = 214;
  localparam int unsigned MLE_PLB_PARITY_BYTES  = 26;

  // Figure 8-3 and the m211..m0 / p25..p0 payload map imply 1690 payload bits
  // for 64b/65b data, which corresponds to 26 x 65-bit xMII blocks.
  localparam int unsigned MLE_XMII_BLOCKS_PER_PLB = 26;
  localparam int unsigned MLE_XMII_BLOCK_BITS     = 65;
  localparam int unsigned MLE_XMII_STREAM_BITS    = 1690;

  // Payload control region packed above the 64b/65b data stream.
  // [1711]    : secondary-control valid / format indicator
  // [1710:1701] : secondary-control payload (10 bits)
  // [1700:1691] : OAM slot (10 bits, one PLB worth of OAM fragment)
  // [1690:1]    : 26 x 65-bit xMII blocks
  // [0]         : reserved 0
  localparam int unsigned MLE_PAYLOAD_CTRL_BITS = 21;

  function automatic speed_grade_e mle_mode_to_sg(input mle_mode_e mode);
    case (mode)
      MLES_SYM1G0, MLES_2G5_M: return SG2;
      MLES_SYM2G5, MLES_5G0_M: return SG3;
      MLES_10G_M:              return SG4;
      MLES_SYM5G0, MLES_10G_G: return SG5;
      default:                 return SG2;
    endcase
  endfunction

  function automatic logic mle_mode_uses_sg45_scrambler(input mle_mode_e mode);
    case (mode)
      MLES_SYM5G0, MLES_10G_M, MLES_10G_G: return 1'b1;
      default:                              return 1'b0;
    endcase
  endfunction

  function automatic logic mle_fec_correction_mandatory(input mle_mode_e mode);
    case (mode)
      MLES_SYM5G0, MLES_10G_M, MLES_10G_G: return 1'b1;
      default:                              return 1'b0;
    endcase
  endfunction

  function automatic int unsigned mle_tdd_cycle_ptb(input mle_mode_e mode);
    case (mode)
      MLES_SYM1G0: return 628;
      MLES_SYM2G5: return 628;
      MLES_SYM5G0: return 568;
      MLES_2G5_M:  return 988;
      MLES_5G0_M:  return 748;
      MLES_10G_M:  return 6708;
      MLES_10G_G:  return 748;
      default:     return 628;
    endcase
  endfunction

  function automatic int unsigned mle_dn_plbs(input mle_mode_e mode);
    case (mode)
      MLES_SYM1G0: return 2;
      MLES_SYM2G5: return 4;
      MLES_SYM5G0: return 7;
      MLES_2G5_M:  return 6;
      MLES_5G0_M:  return 9;
      MLES_10G_M:  return 162;
      MLES_10G_G:  return 18;
      default:     return 2;
    endcase
  endfunction

  function automatic int unsigned mle_up_plbs(input mle_mode_e mode);
    case (mode)
      MLES_SYM1G0: return 2;
      MLES_SYM2G5: return 4;
      MLES_SYM5G0: return 7;
      MLES_2G5_M:  return 1;
      MLES_5G0_M:  return 1;
      MLES_10G_M:  return 2;
      MLES_10G_G:  return 2;
      default:     return 2;
    endcase
  endfunction

  function automatic int unsigned mle_qg_dn(input mle_mode_e mode);
    case (mode)
      MLES_SYM1G0: return 5440;
      MLES_SYM2G5: return 10880;
      MLES_SYM5G0: return 9920;
      MLES_2G5_M:  return 3520;
      MLES_5G0_M:  return 5120;
      MLES_10G_M:  return 4320;
      MLES_10G_G:  return 5120;
      default:     return 5440;
    endcase
  endfunction

  function automatic int unsigned mle_qg_up(input mle_mode_e mode);
    case (mode)
      MLES_SYM1G0: return 5440;
      MLES_SYM2G5: return 10880;
      MLES_SYM5G0: return 9920;
      MLES_2G5_M:  return 13120;
      MLES_5G0_M:  return 20480;
      MLES_10G_M:  return 157920;
      MLES_10G_G:  return 20480;
      default:     return 5440;
    endcase
  endfunction

  function automatic logic [4:0] encode_mle_mode(input mle_mode_e mode);
    case (mode)
      MLES_SYM1G0: return 5'b10000;
      MLES_SYM2G5: return 5'b01000;
      MLES_SYM5G0: return 5'b00100;
      MLES_2G5_M:  return 5'b00010;
      MLES_5G0_M:  return 5'b00001;
      MLES_10G_M:  return 5'b11000;
      MLES_10G_G:  return 5'b10100;
      default:     return 5'b11111;
    endcase
  endfunction

  function automatic logic [4:0] nibble_to_4b5b(input logic [3:0] nibble);
    case (nibble)
      4'h0: return 5'b11110;
      4'h1: return 5'b01001;
      4'h2: return 5'b10100;
      4'h3: return 5'b10101;
      4'h4: return 5'b01010;
      4'h5: return 5'b01011;
      4'h6: return 5'b01110;
      4'h7: return 5'b01111;
      4'h8: return 5'b10010;
      4'h9: return 5'b10011;
      4'hA: return 5'b10110;
      4'hB: return 5'b10111;
      4'hC: return 5'b11010;
      4'hD: return 5'b11011;
      4'hE: return 5'b11100;
      default: return 5'b11101;
    endcase
  endfunction

  function automatic logic [3:0] code5_to_nibble(input logic [4:0] code, output logic valid);
    valid = 1'b1;
    case (code)
      5'b11110: return 4'h0;
      5'b01001: return 4'h1;
      5'b10100: return 4'h2;
      5'b10101: return 4'h3;
      5'b01010: return 4'h4;
      5'b01011: return 4'h5;
      5'b01110: return 4'h6;
      5'b01111: return 4'h7;
      5'b10010: return 4'h8;
      5'b10011: return 4'h9;
      5'b10110: return 4'hA;
      5'b10111: return 4'hB;
      5'b11010: return 4'hC;
      5'b11011: return 4'hD;
      5'b11100: return 4'hE;
      5'b11101: return 4'hF;
      default: begin valid = 1'b0; return 4'h0; end
    endcase
  endfunction

  function automatic logic [4:0] ctrl_to_4b5b(input oam_slot_kind_e kind, input logic second_char);
    case (kind)
      OAM_CTL_IDLE: return 5'b11111; // I
      OAM_CTL_JJ:   return 5'b11000; // J
      OAM_CTL_JK:   return second_char ? 5'b10001 : 5'b11000; // J,K
      OAM_CTL_TI:   return second_char ? 5'b11111 : 5'b01101; // T,I
      default:      return 5'b11111;
    endcase
  endfunction

  function automatic logic [7:0] reflect8(input logic [7:0] v);
    logic [7:0] r;
    for (int i = 0; i < 8; i++) r[i] = v[7-i];
    return r;
  endfunction

  function automatic logic [7:0] crc8_step(input logic [7:0] crc, input logic [7:0] data);
    logic [7:0] c;
    logic [7:0] d;
    d = reflect8(data);
    c = crc ^ d;
    for (int i = 0; i < 8; i++) begin
      if (c[0]) c = (c >> 1) ^ 8'hA6;
      else      c = (c >> 1);
    end
    return c;
  endfunction

endpackage

`default_nettype wire
