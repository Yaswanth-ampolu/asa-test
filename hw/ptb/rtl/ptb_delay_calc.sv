`timescale 1ns/1ps
`default_nettype none

module ptb_delay_calc
  import asa_ptb_pkg::*;
(
  input  logic        calc_valid_i,
  input  logic [13:0] t_ptb_rx_i,
  input  logic [13:0] follow_stamp_i,
  input  logic [13:0] delay_reply_stamp_i,
  input  logic [13:0] t_ptb_tx_i,
  output logic signed [15:0] offset_o,
  output logic [7:0]  delay_o,
  output logic        in_sync_o,
  output logic        invalid_o
);

  logic signed [15:0] rx_minus_follow;
  logic signed [15:0] dreply_minus_tx;
  logic signed [15:0] offset_calc;
  logic signed [15:0] delay_calc;

  always_comb begin
    rx_minus_follow = delta14(t_ptb_rx_i, follow_stamp_i);
    dreply_minus_tx = delta14(delay_reply_stamp_i, t_ptb_tx_i);
    offset_calc = (rx_minus_follow - dreply_minus_tx) >>> 1;
    delay_calc = rx_minus_follow - offset_calc;

    offset_o = offset_calc;
    delay_o = sat_u8_from_s16(delay_calc);
    in_sync_o = calc_valid_i && (abs_s16(offset_calc) <= PTB_LOCK_TOL);
    invalid_o = !calc_valid_i;
  end

endmodule

`default_nettype wire
