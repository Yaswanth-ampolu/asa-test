`timescale 1ns/1ps
`default_nettype none

module ptb_top
  import asa_error_pkg::*;
  import asa_ptb_pkg::*;
#(
  parameter int unsigned TDD_CYCLE_TICS = PTB_TDD_CYCLE_TICS
) (
  input  logic        clk,
  input  logic        rst,
  input  logic        soft_reset_i,

  input  logic        is_root_i,
  input  logic        local_leader_enable_i,
  input  logic        upstream_follower_locked_i,
  input  logic [47:0] upstream_ptbclk_i,
  input  logic        start_ptb_i,

  input  logic        reg_ptb_clk_wr_en_i,
  input  logic [47:0] reg_ptb_clk_wr_data_i,

  input  logic        oam_tx_snapshot_req_i,
  input  logic        oam_rx_valid_i,
  input  logic [47:0] oam_rx_ptbclk_i,

  input  logic        ptb_rx_msg_valid_i,
  input  ptb_cmd_e    ptb_rx_cmd_i,
  input  logic        ptb_rx_status_i,
  input  logic [13:0] ptb_rx_stamp_i,
  input  logic        mdi_tx_event_i,
  input  logic        mdi_rx_event_i,

  input  logic        start_tdd_arm_i,
  input  logic [47:0] start_tdd_ptbtime_i,
  input  logic        ls_timer_arm_i,
  input  logic [47:0] ls_bedtime_i,
  input  logic [47:0] ls_alarmclock_i,
  input  logic        asep_ts_capture_req_i,

  output logic [47:0] ptb_clk_o,
  output logic [15:0] ptb_status_o,
  output logic [47:0] ptb_oam_clk_o,
  output logic [15:0] ptb_oam_dly_o,
  output logic [15:0] ptb_ext_status_o,
  output logic        ptb_locked_o,
  output logic        ptb_running_o,

  output logic [47:0] oam_tx_ptbclk_o,
  output logic [8:0]  oam_tx_ptbstatus_o,
  output logic [7:0]  oam_tx_header_byte4_o,
  output logic [7:0]  oam_tx_header_byte5_o,

  output ptb_cmd_e    ptb_tx_cmd_o,
  output logic        ptb_tx_status_o,
  output logic [13:0] ptb_tx_stamp_o,

  output ptb_lock_state_e ptb_int_state_o,
  output logic [4:0]  cnt_follow_o,
  output logic [4:0]  cnt_dly_reply_o,
  output logic [4:0]  synced_updates_o,

  output logic        tdd_cycle_start_o,
  output logic        start_tdd_trigger_o,
  output logic        ls_bedtime_trigger_o,
  output logic        ls_alarm_trigger_o,
  output logic [31:0] asep_ts_value_o,

  output err_event_t  err_event_o
);

  logic follower_enable;
  logic leader_enable;
  logic local_copy_en;
  logic [47:0] ptb_clk;
  logic ptb_running;
  logic copy_oam_en;
  logic [47:0] copy_oam_value;
  logic follower_locked;
  logic signed [15:0] follower_offset;
  logic [7:0] follower_delay;
  logic follower_offset_valid;
  logic offset_apply;
  logic signed [15:0] offset_apply_value;
  logic lock_lost;
  logic [13:0] t_ptb_tx_q;
  logic [2:0] leader_follow_seq_q;
  logic status_locked;
  logic offset_invalid;
  logic signed [15:0] status_offset;
  logic [7:0] status_delay;
  err_event_t err_event_d;

  assign follower_enable = !is_root_i && !local_leader_enable_i;
  assign leader_enable = is_root_i || local_leader_enable_i;
  assign local_copy_en = local_leader_enable_i && upstream_follower_locked_i;

  ptb_counter_48 u_counter (
    .clk              (clk),
    .rst              (rst),
    .soft_reset_i     (soft_reset_i),
    .start_i          (start_ptb_i),
    .wr_en_i          (reg_ptb_clk_wr_en_i),
    .wr_value_i       (reg_ptb_clk_wr_data_i),
    .copy_oam_en_i    (copy_oam_en),
    .copy_oam_value_i (copy_oam_value),
    .local_copy_en_i  (local_copy_en),
    .local_copy_value_i(upstream_ptbclk_i),
    .offset_apply_i   (offset_apply),
    .offset_i         (offset_apply_value),
    .ptb_clk_o        (ptb_clk),
    .running_o        (ptb_running)
  );

  ptb_follow_fsm u_follow_fsm (
    .clk                 (clk),
    .rst                 (rst),
    .soft_reset_i        (soft_reset_i),
    .follower_enable_i   (follower_enable),
    .ptb_running_i       (ptb_running),
    .ptb_clk_i           (ptb_clk),
    .rx_msg_valid_i      (ptb_rx_msg_valid_i),
    .rx_cmd_i            (ptb_rx_cmd_i),
    .rx_status_i         (ptb_rx_status_i),
    .rx_stamp_i          (ptb_rx_stamp_i),
    .t_ptb_tx_i          (t_ptb_tx_q),
    .state_o             (ptb_int_state_o),
    .locked_o            (follower_locked),
    .cnt_follow_o        (cnt_follow_o),
    .cnt_dly_reply_o     (cnt_dly_reply_o),
    .synced_updates_o    (synced_updates_o),
    .offset_o            (follower_offset),
    .delay_o             (follower_delay),
    .offset_valid_o      (follower_offset_valid),
    .offset_apply_o      (offset_apply),
    .offset_apply_value_o(offset_apply_value),
    .lock_lost_o         (lock_lost)
  );

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      t_ptb_tx_q <= 14'd0;
      leader_follow_seq_q <= 3'd0;
    end else if (soft_reset_i) begin
      t_ptb_tx_q <= 14'd0;
      leader_follow_seq_q <= 3'd0;
    end else begin
      if (mdi_tx_event_i) begin
        t_ptb_tx_q <= ptb_clk[13:0];
        if (leader_enable && ptb_running) leader_follow_seq_q <= leader_follow_seq_q + 3'd1;
      end
    end
  end

  assign status_locked = is_root_i ? ptb_running :
                         (local_leader_enable_i ? upstream_follower_locked_i : follower_locked);
  assign status_offset = (is_root_i || local_leader_enable_i) ? 16'sd0 : follower_offset;
  assign offset_invalid = follower_enable && !follower_offset_valid && (cnt_follow_o != 5'd0);
  assign status_delay = (is_root_i || local_leader_enable_i) ? 8'd0 : follower_delay;

  assign ptb_status_o = pack_ptb_status(status_offset, offset_invalid, status_locked, status_delay);

  ptb_oam_header_if u_oam_header_if (
    .clk                  (clk),
    .rst                  (rst),
    .soft_reset_i         (soft_reset_i),
    .ptb_clk_i            (ptb_clk),
    .ptb_status_i         (ptb_status_o),
    .ptb_locked_i         (status_locked),
    .ptb_valid_i          (ptb_running),
    .oam_tx_snapshot_req_i(oam_tx_snapshot_req_i),
    .oam_rx_valid_i       (oam_rx_valid_i),
    .oam_rx_ptbclk_i      (oam_rx_ptbclk_i),
    .oam_tx_ptbclk_o      (oam_tx_ptbclk_o),
    .oam_tx_ptbstatus_o   (oam_tx_ptbstatus_o),
    .oam_tx_header_byte4_o(oam_tx_header_byte4_o),
    .oam_tx_header_byte5_o(oam_tx_header_byte5_o),
    .copy_oam_en_o        (copy_oam_en),
    .copy_oam_value_o     (copy_oam_value),
    .ptb_oam_clk_o        (ptb_oam_clk_o),
    .ptb_oam_dly_o        (ptb_oam_dly_o)
  );

  ptb_timer_compare #(
    .TDD_CYCLE_TICS(TDD_CYCLE_TICS)
  ) u_timer_compare (
    .clk                  (clk),
    .rst                  (rst),
    .soft_reset_i         (soft_reset_i),
    .ptb_running_i        (ptb_running),
    .leader_enable_i      (leader_enable),
    .ptb_clk_i            (ptb_clk),
    .start_tdd_arm_i      (start_tdd_arm_i),
    .start_tdd_ptbtime_i  (start_tdd_ptbtime_i),
    .ls_timer_arm_i       (ls_timer_arm_i),
    .ls_bedtime_i         (ls_bedtime_i),
    .ls_alarmclock_i      (ls_alarmclock_i),
    .asep_ts_capture_req_i(asep_ts_capture_req_i),
    .tdd_cycle_start_o    (tdd_cycle_start_o),
    .start_tdd_trigger_o  (start_tdd_trigger_o),
    .ls_bedtime_trigger_o (ls_bedtime_trigger_o),
    .ls_alarm_trigger_o   (ls_alarm_trigger_o),
    .asep_ts_value_o      (asep_ts_value_o)
  );

  always_comb begin
    err_event_d = '0;
    err_event_d.source = ERR_SRC_PTB;
    err_event_d.severity = ERR_SEV_PROTO;
    if (lock_lost) begin
      err_event_d.valid = 1'b1;
      err_event_d.code = PTB_ERR_UNLOCK;
    end else if (offset_invalid) begin
      err_event_d.valid = 1'b1;
      err_event_d.code = PTB_ERR_UPDATE;
    end else if (start_tdd_trigger_o || ls_bedtime_trigger_o || ls_alarm_trigger_o) begin
      err_event_d.valid = 1'b1;
      err_event_d.severity = ERR_SEV_WARN;
      err_event_d.code = PTB_ERR_UPDATE;
    end
  end

  assign ptb_clk_o = ptb_clk;
  assign ptb_running_o = ptb_running;
  assign ptb_locked_o = status_locked;
  assign ptb_ext_status_o = {6'd0, cnt_dly_reply_o, cnt_follow_o};
  assign ptb_tx_cmd_o = (leader_enable && (leader_follow_seq_q == 3'd7)) ?
                        PTB_CMD_DELAY_REPLY : PTB_CMD_FOLLOW;
  assign ptb_tx_status_o = status_locked;
  assign ptb_tx_stamp_o = ptb_clk[13:0];
  assign err_event_o = err_event_d;

  // MDI RX event is consumed by the PCS integration point in future revisions.
  // The current abstract m_ptb interface presents the decoded stamp with valid.
  logic unused_mdi_rx_event;
  assign unused_mdi_rx_event = mdi_rx_event_i;

endmodule

`default_nettype wire
