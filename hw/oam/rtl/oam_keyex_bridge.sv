`default_nettype none

// OAM KeyEx Bridge
// Routes KeyExMsg to/from external KeyEx entity.
// Spec: Section 6.4.2 — KeyExMsg is always sole CAD in frame.

module oam_keyex_bridge
  import asa_oam_pkg::*;
(
  input  logic          clk,
  input  logic          rst,

  input  oam_decoded_cad_t cad_i,
  input  logic          cad_valid_i,
  input  oam_payload_t  payload_i,
  input  logic [7:0]    cad_offset_i,
  input  logic [4:0]    src_node_id_i,
  output logic          keyex_msg_valid_o,
  output logic [4:0]    keyex_msg_src_node_id_o,
  output oam_keyex_msg_t keyex_msg_o
);

  always_comb begin
    keyex_msg_valid_o = 1'b0;
    keyex_msg_src_node_id_o = src_node_id_i;
    keyex_msg_o = '0;

    if (cad_valid_i &&
        ((cad_i.cmd == OAM_CMD_KEYEX_REQ) || (cad_i.cmd == OAM_CMD_KEYEX_RESP))) begin
      keyex_msg_valid_o = 1'b1;
      keyex_msg_o.valid = 1'b1;
      keyex_msg_o.is_response = (cad_i.cmd == OAM_CMD_KEYEX_RESP);
      keyex_msg_o.payload_len = OAM_PAYLOAD_SIZE - cad_offset_i - 8'd1;
      for (int i = 0; i < OAM_KEYEX_MAX_BYTES; i++) begin
        keyex_msg_o.payload[i*8 +: 8] = (i < keyex_msg_o.payload_len) ?
          oam_pay_get_byte(payload_i, cad_offset_i + 1 + i) : 8'd0;
      end
    end
  end

endmodule

`default_nettype wire
