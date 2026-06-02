`timescale 1ns/1ps
`default_nettype none

module mle_oam_rx_adapt
  import asa_mle_pcs_pkg::*;
(
  input  logic       clk,
  input  logic       rst,
  input  logic [9:0] slot_i,
  input  logic       slot_valid_i,
  output logic       frame_start_o,
  output logic       frame_valid_o,
  output logic       frame_end_o,
  output logic [7:0] frame_byte_o,
  output logic       crc_error_o,
  output logic       jk_pulse_o
);
  logic dec_is_data;
  logic [7:0] dec_byte;
  oam_slot_kind_e dec_kind;
  logic dec_valid;
  logic [7:0] crc_final;
  logic crc_init, crc_feed;
  logic in_frame_q;
  logic [7:0] prev_byte_q;
  logic have_prev_q;
  logic jk_pulse_q;

  mle_4b5b_codec u_dec (
    .is_data_i('0), .data_byte_i('0), .ctrl_kind_i(OAM_CTL_IDLE), .slot_o(),
    .slot_i(slot_i), .dec_is_data_o(dec_is_data), .dec_data_byte_o(dec_byte),
    .dec_ctrl_kind_o(dec_kind), .dec_valid_o(dec_valid)
  );

  mle_crc8 u_crc (
    .clk(clk), .rst(rst), .init_i(crc_init), .valid_i(crc_feed), .data_i(prev_byte_q),
    .crc_o(), .crc_final_o(crc_final)
  );

  assign jk_pulse_o = jk_pulse_q;

  always_comb begin
    frame_start_o = 1'b0;
    frame_valid_o = 1'b0;
    frame_end_o   = 1'b0;
    frame_byte_o  = 8'h00;
    crc_error_o   = 1'b0;
    crc_init      = 1'b0;
    crc_feed      = 1'b0;

    if (slot_valid_i && dec_valid) begin
      if (!dec_is_data && dec_kind == OAM_CTL_JK) begin
        frame_start_o = 1'b1;
        crc_init      = 1'b1;
      end else if (in_frame_q && dec_is_data) begin
        if (have_prev_q) begin
          frame_valid_o = 1'b1;
          frame_byte_o  = prev_byte_q;
          crc_feed      = 1'b1;
        end
      end else if (in_frame_q && !dec_is_data && dec_kind == OAM_CTL_TI) begin
        frame_end_o = 1'b1;
        crc_error_o = have_prev_q && (prev_byte_q != crc_final);
      end
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      in_frame_q  <= 1'b0;
      prev_byte_q <= 8'h00;
      have_prev_q <= 1'b0;
      jk_pulse_q  <= 1'b0;
    end else if (slot_valid_i && dec_valid) begin
      jk_pulse_q <= 1'b0;
      if (!dec_is_data && dec_kind == OAM_CTL_JK) begin
        in_frame_q  <= 1'b1;
        have_prev_q <= 1'b0;
        jk_pulse_q  <= 1'b1;
      end else if (in_frame_q && dec_is_data) begin
        prev_byte_q <= dec_byte;
        have_prev_q <= 1'b1;
      end else if (in_frame_q && !dec_is_data && dec_kind == OAM_CTL_TI) begin
        in_frame_q  <= 1'b0;
        have_prev_q <= 1'b0;
      end
    end else begin
      jk_pulse_q <= 1'b0;
    end
  end
endmodule

`default_nettype wire
