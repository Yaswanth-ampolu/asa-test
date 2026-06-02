`timescale 1ns/1ps
`default_nettype none

module mle_4b5b_codec
  import asa_mle_pcs_pkg::*;
(
  input  logic          is_data_i,
  input  logic [7:0]    data_byte_i,
  input  oam_slot_kind_e ctrl_kind_i,
  output logic [9:0]    slot_o,

  input  logic [9:0]    slot_i,
  output logic          dec_is_data_o,
  output logic [7:0]    dec_data_byte_o,
  output oam_slot_kind_e dec_ctrl_kind_o,
  output logic          dec_valid_o
);
  logic lo_valid, hi_valid;
  logic [3:0] lo_nib, hi_nib;

  always_comb begin
    if (is_data_i) begin
      slot_o = {nibble_to_4b5b(data_byte_i[7:4]), nibble_to_4b5b(data_byte_i[3:0])};
    end else begin
      slot_o = {ctrl_to_4b5b(ctrl_kind_i, 1'b1), ctrl_to_4b5b(ctrl_kind_i, 1'b0)};
    end
  end

  always_comb begin
    dec_is_data_o   = 1'b0;
    dec_data_byte_o = 8'h00;
    dec_ctrl_kind_o = OAM_CTL_IDLE;
    dec_valid_o     = 1'b1;

    lo_nib = code5_to_nibble(slot_i[4:0], lo_valid);
    hi_nib = code5_to_nibble(slot_i[9:5], hi_valid);
    if (lo_valid && hi_valid) begin
      dec_is_data_o   = 1'b1;
      dec_data_byte_o = {hi_nib, lo_nib};
    end else if (slot_i == {5'b11111, 5'b11111}) begin
      dec_ctrl_kind_o = OAM_CTL_IDLE;
    end else if (slot_i == {5'b11000, 5'b11000}) begin
      dec_ctrl_kind_o = OAM_CTL_JJ;
    end else if (slot_i == {5'b10001, 5'b11000}) begin
      dec_ctrl_kind_o = OAM_CTL_JK;
    end else if (slot_i == {5'b11111, 5'b01101}) begin
      dec_ctrl_kind_o = OAM_CTL_TI;
    end else begin
      dec_valid_o = 1'b0;
    end
  end

endmodule

`default_nettype wire
