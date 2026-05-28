`timescale 1ns/1ps
`default_nettype none

// DLL Container Header Parser
// Spec: Section 5.2.2, Table 5-1 (PDF p164), Figure 5-2 (image)
//
// Takes the first 6 bytes of a received container (MSB of byte 0 = bit 7 of
// d_plp_tx<0>, i.e., headerType is bit 0 of the container bit stream, stored
// as LSB of our 48-bit packed vector).
//
// PDF spec (Section 5.2.1f): "d_plp_tx<7>,<0> is the MSB of the first byte
// of the DLL container header" → byte 0 bit 7 is transmitted first, but
// stored in our packed container vector as the first byte.
//
// Container bits in packed vector (bit 0 = first bit on wire = bit 0 of byte 0):
//   bit 0       HeaderType
//   bit 1       KeySwitch
//   bits 6:2    nodeID
//   bit 7       streamID (LSB of DLP_TX_ID)
//   bits 12:8   targetID[4:0] lower 5 bits
//   bits 15:13  targetID[7:5] upper 3 bits → targetID total = {h[17:13]} = 5-bit ID
//   bits 17:16  targetID[9:8]  (full targetID is 5 bits total per Table 5-1 bits 17:13)
//   bits 22:18  packetID
//   bit 23      reserved
//   bits 31:24  reserved

module dll_header_parse
  import asa_dll_pkg::*;
(
  input  logic [47:0]      hdr_raw_i,    // 6 bytes from received container
  input  logic             hdr_valid_i,  // Header bytes are valid

  // Decoded outputs
  output logic             header_type_o,   // 0=basic, 1=extended
  output logic             key_switch_o,
  output logic [4:0]       node_id_o,
  output logic [0:0]       stream_id_o,
  output logic [4:0]       target_id0_o,
  output logic [4:0]       packet_id_o,
  // Extended header targets (valid when header_type_o=1)
  output logic [4:0]       target_id1_o,
  output logic [4:0]       target_id2_o,
  output logic [4:0]       target_id3_o,

  // Validation
  output logic             hdr_ok_o         // 1=header structurally valid
);

  always_comb begin
    header_type_o = hdr_raw_i[0];
    key_switch_o  = hdr_raw_i[1];
    node_id_o     = hdr_raw_i[6:2];
    stream_id_o   = hdr_raw_i[7];
    target_id0_o  = hdr_raw_i[17:13];
    packet_id_o   = hdr_raw_i[22:18];
    target_id1_o  = hdr_raw_i[37:33];
    target_id2_o  = {hdr_raw_i[42:40], hdr_raw_i[39:38]};
    target_id3_o  = hdr_raw_i[47:43];

    // A header is structurally OK if:
    // - Basic: reserved bits 23, 31:24 are don't-care (always accept)
    // - Extended: extended fields are meaningful only if header_type=1
    // Per spec: malformed = cannot be decoded or matches no case in 5.3.2
    // We mark hdr_ok only based on structural validity; routing validation
    // is done in dll_rx_demux.
    hdr_ok_o = hdr_valid_i;
  end

endmodule

`default_nettype wire
