`timescale 1ns/1ps
`default_nettype none

module ptb_follow_fsm
  import asa_ptb_pkg::*;
(
  input  logic               clk,
  input  logic               rst,
  input  logic               soft_reset_i,
  input  logic               follower_enable_i,
  input  logic               ptb_running_i,
  input  logic [47:0]        ptb_clk_i,
  input  logic               rx_msg_valid_i,
  input  ptb_cmd_e           rx_cmd_i,
  input  logic               rx_status_i,
  input  logic [13:0]        rx_stamp_i,
  input  logic [13:0]        t_ptb_tx_i,
  output ptb_lock_state_e    state_o,
  output logic               locked_o,
  output logic [4:0]         cnt_follow_o,
  output logic [4:0]         cnt_dly_reply_o,
  output logic [4:0]         synced_updates_o,
  output logic signed [15:0] offset_o,
  output logic [7:0]         delay_o,
  output logic               offset_valid_o,
  output logic               offset_apply_o,
  output logic signed [15:0] offset_apply_value_o,
  output logic               lock_lost_o
);

  ptb_lock_state_e state_q, state_d;
  logic [4:0] cnt_follow_q, cnt_follow_d;
  logic [4:0] cnt_dly_q, cnt_dly_d;
  logic [4:0] synced_q, synced_d;
  logic signed [15:0] offset_q, offset_d;
  logic [7:0] delay_q, delay_d;
  logic offset_valid_q, offset_valid_d;
  logic [13:0] follow_stamp_q, follow_stamp_d;
  logic [13:0] delay_reply_stamp_q, delay_reply_stamp_d;
  logic [13:0] t_ptb_rx_q, t_ptb_rx_d;
  logic locked_q;

  logic follow_event;
  logic dly_event;
  logic calc_valid;
  logic signed [15:0] calc_offset;
  logic [7:0] calc_delay;
  logic calc_in_sync;
  logic calc_invalid;
  logic [4:0] next_follow_count;
  logic [4:0] next_synced_count;

  assign follow_event = follower_enable_i && rx_msg_valid_i && rx_status_i &&
                        (rx_cmd_i == PTB_CMD_FOLLOW);
  assign dly_event = follower_enable_i && rx_msg_valid_i && rx_status_i &&
                     (rx_cmd_i == PTB_CMD_DELAY_REPLY);
  assign calc_valid = follow_event && ptb_running_i && (ptb_clk_i != 48'd0) && (cnt_dly_q >= 5'd1);

  ptb_delay_calc u_delay_calc (
    .calc_valid_i        (calc_valid),
    .t_ptb_rx_i          (ptb_clk_i[13:0]),
    .follow_stamp_i      (rx_stamp_i),
    .delay_reply_stamp_i (delay_reply_stamp_q),
    .t_ptb_tx_i          (t_ptb_tx_i),
    .offset_o            (calc_offset),
    .delay_o             (calc_delay),
    .in_sync_o           (calc_in_sync),
    .invalid_o           (calc_invalid)
  );

  always_comb begin
    state_d = state_q;
    cnt_follow_d = cnt_follow_q;
    cnt_dly_d = cnt_dly_q;
    synced_d = synced_q;
    offset_d = offset_q;
    delay_d = delay_q;
    offset_valid_d = offset_valid_q;
    follow_stamp_d = follow_stamp_q;
    delay_reply_stamp_d = delay_reply_stamp_q;
    t_ptb_rx_d = t_ptb_rx_q;
    offset_apply_o = 1'b0;
    offset_apply_value_o = 16'sd0;
    lock_lost_o = 1'b0;
    next_follow_count = cnt_follow_q;
    next_synced_count = synced_q;

    if (!follower_enable_i) begin
      state_d = PTB_STATE_UNLOCKED;
      cnt_follow_d = 5'd0;
      cnt_dly_d = 5'd0;
      synced_d = 5'd0;
      offset_valid_d = 1'b0;
    end else begin
      if (dly_event) begin
        delay_reply_stamp_d = rx_stamp_i;
        cnt_dly_d = sat_inc_acq(cnt_dly_q);
      end

      if (follow_event) begin
        follow_stamp_d = rx_stamp_i;
        t_ptb_rx_d = ptb_clk_i[13:0];
      end

      if (calc_valid) begin
        next_follow_count = sat_inc_acq(cnt_follow_q);
        next_synced_count = calc_in_sync ? sat_inc_acq(synced_q) : synced_q;

        cnt_follow_d = next_follow_count;
        synced_d = next_synced_count;
        offset_d = calc_offset;
        delay_d = calc_delay;
        offset_valid_d = !calc_invalid;
        offset_apply_o = 1'b1;
        offset_apply_value_o = calc_offset;
        if (state_q != PTB_STATE_LOCKED) state_d = PTB_STATE_ACQUISITION;

        if (next_follow_count >= PTB_ACQ_WINDOW[4:0]) begin
          if (next_synced_count >= PTB_LOCK_THRESH[4:0]) begin
            state_d = PTB_STATE_LOCKED;
          end else begin
            if (state_q == PTB_STATE_LOCKED) lock_lost_o = 1'b1;
            state_d = PTB_STATE_UNLOCKED;
            cnt_follow_d = 5'd0;
            cnt_dly_d = 5'd0;
            synced_d = 5'd0;
          end
        end
      end
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q <= PTB_STATE_UNLOCKED;
      cnt_follow_q <= 5'd0;
      cnt_dly_q <= 5'd0;
      synced_q <= 5'd0;
      offset_q <= 16'sd0;
      delay_q <= 8'd0;
      offset_valid_q <= 1'b0;
      follow_stamp_q <= 14'd0;
      delay_reply_stamp_q <= 14'd0;
      t_ptb_rx_q <= 14'd0;
    end else if (soft_reset_i) begin
      state_q <= PTB_STATE_UNLOCKED;
      cnt_follow_q <= 5'd0;
      cnt_dly_q <= 5'd0;
      synced_q <= 5'd0;
      offset_q <= 16'sd0;
      delay_q <= 8'd0;
      offset_valid_q <= 1'b0;
      follow_stamp_q <= 14'd0;
      delay_reply_stamp_q <= 14'd0;
      t_ptb_rx_q <= 14'd0;
    end else begin
      state_q <= state_d;
      cnt_follow_q <= cnt_follow_d;
      cnt_dly_q <= cnt_dly_d;
      synced_q <= synced_d;
      offset_q <= offset_d;
      delay_q <= delay_d;
      offset_valid_q <= offset_valid_d;
      follow_stamp_q <= follow_stamp_d;
      delay_reply_stamp_q <= delay_reply_stamp_d;
      t_ptb_rx_q <= t_ptb_rx_d;
    end
  end

  assign locked_q = (state_q == PTB_STATE_LOCKED);
  assign state_o = state_q;
  assign locked_o = locked_q;
  assign cnt_follow_o = cnt_follow_q;
  assign cnt_dly_reply_o = cnt_dly_q;
  assign synced_updates_o = synced_q;
  assign offset_o = offset_q;
  assign delay_o = delay_q;
  assign offset_valid_o = offset_valid_q;

endmodule

`default_nettype wire
