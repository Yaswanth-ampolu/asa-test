`timescale 1ns/1ps
`default_nettype none

// DLL Container Header Builder
// Spec: Section 5.2.2, Table 5-1 (PDF p164)
//
// Constructs container header for TX path based on source type:
//   - ASEP: fields from registers (DLLaddrtable, own nodeID, fullPacketID)
//   - OAM:  targetID, packetID, ndEn from oamUnit primitive
//   - FoFa: full header pre-supplied by forwardUnit — this module not used

module dll_header_build
  import asa_dll_pkg::*;
(
  // Source selection
  input  dll_tx_src_e      tx_src_i,         // TX_SRC_ASEP or TX_SRC_OAM

  // Own node config (from register 2.0001)
  input  logic [4:0]       own_node_id_i,

  // ASEP fields (from DLLaddrtable for selected DLP_TX_ID)
  input  logic [0:0]       stream_id_i,      // DLP_TX_ID[0] (1-bit in header)
  input  logic [4:0]       asep_target_id0_i,
  input  logic [4:0]       asep_target_id1_i,
  input  logic [4:0]       asep_target_id2_i,
  input  logic [4:0]       asep_target_id3_i,
  input  logic             asep_target1_valid_i,
  input  logic             asep_target2_valid_i,
  input  logic             asep_target3_valid_i,
  input  logic [4:0]       asep_packet_id_i,  // fullPacketID[4:0]

  // OAM fields (from oamUnit primitive, Section 5.6.1.3)
  input  logic [4:0]       oam_target_id_i,
  input  logic [4:0]       oam_packet_id_i,
  input  logic             oam_nd_en_i,       // Node-Discover: use extended header
  input  logic [4:0]       oam_target_id1_i,
  input  logic [4:0]       oam_target_id2_i,
  input  logic [4:0]       oam_target_id3_i,

  // Security: key switch from security entity
  input  logic             key_switch_i,      // 0 if no security entity

  // Outputs
  output logic [47:0]      hdr_o,             // Container header (up to 48 bits)
  output logic             is_extended_o      // 1=6-byte header, 0=4-byte
);

  always_comb begin
    hdr_o        = 48'd0;
    is_extended_o = 1'b0;

    case (tx_src_i)
      TX_SRC_OAM: begin
        if (oam_nd_en_i) begin
          // Node-Discover: extended header with targetIDs (Section 5.2.2.5)
          is_extended_o = 1'b1;
          hdr_o = dll_build_ext_hdr(
            key_switch_i, own_node_id_i, 1'b0,
            oam_target_id_i, oam_packet_id_i,
            oam_target_id1_i, oam_target_id2_i, oam_target_id3_i
          );
        end else begin
          is_extended_o = 1'b0;
          hdr_o[31:0] = dll_build_basic_hdr(
            1'b0, key_switch_i, own_node_id_i, 1'b0,
            oam_target_id_i, oam_packet_id_i
          );
        end
      end

      TX_SRC_ASEP: begin
        // Use extended header if any of targetID1/2/3 are valid (Section 5.2.2.1)
        is_extended_o = asep_target1_valid_i | asep_target2_valid_i | asep_target3_valid_i;
        if (is_extended_o) begin
          hdr_o = dll_build_ext_hdr(
            key_switch_i, own_node_id_i, stream_id_i,
            asep_target_id0_i, asep_packet_id_i,
            asep_target1_valid_i ? asep_target_id1_i : 5'd0,
            asep_target2_valid_i ? asep_target_id2_i : 5'd0,
            asep_target3_valid_i ? asep_target_id3_i : 5'd0
          );
        end else begin
          hdr_o[31:0] = dll_build_basic_hdr(
            1'b0, key_switch_i, own_node_id_i, stream_id_i,
            asep_target_id0_i, asep_packet_id_i
          );
        end
      end

      default: begin
        hdr_o         = 48'd0;
        is_extended_o = 1'b0;
      end
    endcase
  end

endmodule

`default_nettype wire
