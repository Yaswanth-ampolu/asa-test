`timescale 1ns/1ps
`default_nettype none

module mle_plb_codec
  import asa_pcs_pkg::*;
  import asa_mle_pcs_pkg::*;
(
  input  logic [MLE_XMII_STREAM_BITS-1:0] xmii_blocks_i,
  input  logic [9:0]                      oam_slot_i,
  input  logic [9:0]                      secondary_ctrl_i,
  input  logic                            secondary_valid_i,
  output logic [MLE_PLB_BITS-1:0]         tx_phy_blockE_o,

  input  logic [MLE_PLB_BITS-1:0]         rx_phy_blockE_i,
  output logic [MLE_XMII_STREAM_BITS-1:0] xmii_blocks_o,
  output logic [9:0]                      oam_slot_o,
  output logic [9:0]                      secondary_ctrl_o,
  output logic                            secondary_valid_o,
  output logic                            parity_ok_o
);
  logic [MLE_PLB_PAYLOAD_BITS-1:0] payload_bits;
  logic [MLE_PLB_PARITY_BITS-1:0]  parity_bits;
  logic [MLE_PLB_PAYLOAD_BITS-1:0] rx_payload_bits;
  logic [MLE_PLB_PARITY_BITS-1:0]  rx_parity_bits;
  logic [MLE_PLB_PARITY_BITS-1:0]  rx_expected_parity_bits;

  function automatic logic [MLE_PLB_PARITY_BITS-1:0] rs240_parity_bits_fn(
    input logic [MLE_PLB_PAYLOAD_BITS-1:0] payload
  );
    logic [7:0] parity_regs [0:25];
    logic [7:0] feedback;
    logic [7:0] msg_byte;
    logic [MLE_PLB_PARITY_BITS-1:0] result;
    for (int j = 0; j < 26; j++) parity_regs[j] = 8'h00;
    for (int i = 0; i < MLE_PLB_PAYLOAD_BYTES; i++) begin
      msg_byte = payload[MLE_PLB_PAYLOAD_BITS-1-(i*8) -: 8];
      feedback = msg_byte ^ parity_regs[25];
      for (int j = 25; j > 0; j--) begin
        parity_regs[j] = parity_regs[j-1] ^ gf_mul(feedback, RS240_G[j]);
      end
      parity_regs[0] = gf_mul(feedback, RS240_G[0]);
    end
    result = '0;
    for (int j = 0; j < 26; j++) begin
      result[MLE_PLB_PARITY_BITS-1-(j*8) -: 8] = parity_regs[25-j];
    end
    return result;
  endfunction

  always_comb begin
    payload_bits = '0;
    payload_bits[1711]    = secondary_valid_i;
    payload_bits[1710:1701] = secondary_ctrl_i;
    payload_bits[1700:1691] = oam_slot_i;
    payload_bits[1690:1]    = xmii_blocks_i;
    payload_bits[0]         = 1'b0;
    parity_bits             = rs240_parity_bits_fn(payload_bits);
    tx_phy_blockE_o         = {payload_bits, parity_bits};

    rx_payload_bits         = rx_phy_blockE_i[MLE_PLB_BITS-1:MLE_PLB_PARITY_BITS];
    rx_parity_bits          = rx_phy_blockE_i[MLE_PLB_PARITY_BITS-1:0];
    rx_expected_parity_bits = rs240_parity_bits_fn(rx_payload_bits);

    secondary_valid_o = rx_payload_bits[1711];
    secondary_ctrl_o  = rx_payload_bits[1710:1701];
    oam_slot_o        = rx_payload_bits[1700:1691];
    xmii_blocks_o     = rx_payload_bits[1690:1];
    parity_ok_o       = (rx_parity_bits == rx_expected_parity_bits);
  end
endmodule

`default_nettype wire
