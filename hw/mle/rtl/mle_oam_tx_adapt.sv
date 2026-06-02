`timescale 1ns/1ps
`default_nettype none

module mle_oam_tx_adapt
  import asa_mle_pcs_pkg::*;
(
  input  logic       clk,
  input  logic       rst,
  input  logic       frame_start_i,
  input  logic       frame_valid_i,
  input  logic       frame_last_i,
  input  logic [7:0] frame_byte_i,
  input  logic       slot_advance_i,
  output logic [9:0] slot_o,
  output logic       jk_pulse_o
);
  typedef enum logic [2:0] {
    S_IDLE,
    S_JJ,
    S_JK,
    S_DATA,
    S_CRC,
    S_TI
  } state_e;

  state_e state_q;
  logic [7:0] crc_byte_q;
  logic [9:0] data_slot_q;
  logic [7:0] last_byte_q;
  logic       last_seen_q;
  logic       jk_pulse_q;

  mle_crc8 u_crc (
    .clk(clk), .rst(rst),
    .init_i(frame_start_i),
    .valid_i(frame_valid_i),
    .data_i(frame_byte_i),
    .crc_o(),
    .crc_final_o(crc_byte_q)
  );

  always_comb begin
    slot_o = {ctrl_to_4b5b(OAM_CTL_IDLE, 1'b1), ctrl_to_4b5b(OAM_CTL_IDLE, 1'b0)};
    jk_pulse_o = jk_pulse_q;
    case (state_q)
      S_JJ:   slot_o = {ctrl_to_4b5b(OAM_CTL_JJ, 1'b1), ctrl_to_4b5b(OAM_CTL_JJ, 1'b0)};
      S_JK: begin
        slot_o = {ctrl_to_4b5b(OAM_CTL_JK, 1'b1), ctrl_to_4b5b(OAM_CTL_JK, 1'b0)};
      end
      S_DATA: slot_o = data_slot_q;
      S_CRC:  slot_o = {nibble_to_4b5b(crc_byte_q[7:4]), nibble_to_4b5b(crc_byte_q[3:0])};
      S_TI:   slot_o = {ctrl_to_4b5b(OAM_CTL_TI, 1'b1), ctrl_to_4b5b(OAM_CTL_TI, 1'b0)};
      default: ;
    endcase
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q <= S_IDLE;
      data_slot_q <= '0;
      last_byte_q <= '0;
      last_seen_q <= 1'b0;
      jk_pulse_q <= 1'b0;
    end else begin
      jk_pulse_q <= 1'b0;
      if (frame_valid_i) begin
        data_slot_q <= {nibble_to_4b5b(frame_byte_i[7:4]), nibble_to_4b5b(frame_byte_i[3:0])};
        last_byte_q <= frame_byte_i;
        last_seen_q <= frame_last_i;
      end
      if (frame_start_i) begin
        state_q <= S_JJ;
      end else if (slot_advance_i) begin
        case (state_q)
          S_IDLE: ;
          S_JJ:   state_q <= S_JK;
          S_JK: begin
            state_q <= last_seen_q ? S_DATA : S_IDLE;
            jk_pulse_q <= 1'b1;
          end
          S_DATA: state_q <= last_seen_q ? S_CRC : S_DATA;
          S_CRC:  state_q <= S_TI;
          S_TI: begin
            state_q <= S_IDLE;
            last_seen_q <= 1'b0;
          end
          default: state_q <= S_IDLE;
        endcase
      end
    end
  end
endmodule

`default_nettype wire
