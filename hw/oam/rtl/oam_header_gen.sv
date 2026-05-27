`default_nettype none

// OAM Header Generator
// Assembles 24-byte TX header from PTB/LinkHealth/frameID/error state.
// Spec: Section 5.5.2 (Table 5-2)

module oam_header_gen
  import asa_oam_pkg::*;
(
  // Inputs
  input  logic [31:0]   frame_id_i,
  input  logic          cad_next_i,         // 1 if payload has CADs
  input  oam_error_code_e oam_error_i,      // Error from PREVIOUS RX decode
  input  logic [8:0]    ptb_status_i,
  input  logic [47:0]   ptb_clk_i,
  input  logic [15:0]   link_health_1_i,    // LinkQuality
  input  logic [15:0]   link_health_2_i,    // SQI
  input  logic [15:0]   link_health_3_i,    // FECstat

  // Output: 24-byte header
  output oam_header_t   header_bytes_o  // 192-bit packed (24 bytes, byte0=bits[7:0])
);

  always_comb begin
    header_bytes_o = 192'd0;
    // Bytes 0-3: frameID[31:0] little-endian
    header_bytes_o[7:0]   = frame_id_i[7:0];
    header_bytes_o[15:8]  = frame_id_i[15:8];
    header_bytes_o[23:16] = frame_id_i[23:16];
    header_bytes_o[31:24] = frame_id_i[31:24];
    // Byte 4: bit0 CADnext, bits5:3 OAMerror, bit6 StatusValid, bit7 PTBstatus[0]
    header_bytes_o[39:32] = {ptb_status_i[0], 1'b1, oam_error_i, 2'b00, cad_next_i};
    // Byte 5: PTBstatus[8:1]
    header_bytes_o[47:40] = ptb_status_i[8:1];
    // Bytes 6-11: PTBclk little-endian
    header_bytes_o[55:48]  = ptb_clk_i[7:0];
    header_bytes_o[63:56]  = ptb_clk_i[15:8];
    header_bytes_o[71:64]  = ptb_clk_i[23:16];
    header_bytes_o[79:72]  = ptb_clk_i[31:24];
    header_bytes_o[87:80]  = ptb_clk_i[39:32];
    header_bytes_o[95:88]  = ptb_clk_i[47:40];
    // Bytes 12-13: LinkHealth1
    header_bytes_o[103:96]  = link_health_1_i[7:0];
    header_bytes_o[111:104] = link_health_1_i[15:8];
    // Bytes 14-15: LinkHealth2
    header_bytes_o[119:112] = link_health_2_i[7:0];
    header_bytes_o[127:120] = link_health_2_i[15:8];
    // Bytes 16-17: LinkHealth3
    header_bytes_o[135:128] = link_health_3_i[7:0];
    header_bytes_o[143:136] = link_health_3_i[15:8];
    // Bytes 18-23: vendor zeros (already 0 from init)
  end

endmodule

`default_nettype wire
