`timescale 1ns/1ps
`default_nettype none

module ptb_timer_compare #(
  parameter int unsigned TDD_CYCLE_TICS = 6844
) (
  input  logic        clk,
  input  logic        rst,
  input  logic        soft_reset_i,
  input  logic        ptb_running_i,
  input  logic        leader_enable_i,
  input  logic [47:0] ptb_clk_i,
  input  logic        start_tdd_arm_i,
  input  logic [47:0] start_tdd_ptbtime_i,
  input  logic        ls_timer_arm_i,
  input  logic [47:0] ls_bedtime_i,
  input  logic [47:0] ls_alarmclock_i,
  input  logic        asep_ts_capture_req_i,
  output logic        tdd_cycle_start_o,
  output logic        start_tdd_trigger_o,
  output logic        ls_bedtime_trigger_o,
  output logic        ls_alarm_trigger_o,
  output logic [31:0] asep_ts_value_o
);

  logic [$clog2(TDD_CYCLE_TICS+1)-1:0] tdd_count_q;
  logic start_tdd_armed_q;
  logic ls_bedtime_armed_q;
  logic ls_alarm_armed_q;
  logic [31:0] asep_ts_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      tdd_count_q <= '0;
      start_tdd_armed_q <= 1'b0;
      ls_bedtime_armed_q <= 1'b0;
      ls_alarm_armed_q <= 1'b0;
      tdd_cycle_start_o <= 1'b0;
      start_tdd_trigger_o <= 1'b0;
      ls_bedtime_trigger_o <= 1'b0;
      ls_alarm_trigger_o <= 1'b0;
      asep_ts_q <= 32'd0;
    end else if (soft_reset_i) begin
      tdd_count_q <= '0;
      start_tdd_armed_q <= 1'b0;
      ls_bedtime_armed_q <= 1'b0;
      ls_alarm_armed_q <= 1'b0;
      tdd_cycle_start_o <= 1'b0;
      start_tdd_trigger_o <= 1'b0;
      ls_bedtime_trigger_o <= 1'b0;
      ls_alarm_trigger_o <= 1'b0;
      asep_ts_q <= 32'd0;
    end else begin
      tdd_cycle_start_o <= 1'b0;
      start_tdd_trigger_o <= 1'b0;
      ls_bedtime_trigger_o <= 1'b0;
      ls_alarm_trigger_o <= 1'b0;

      if (start_tdd_arm_i) start_tdd_armed_q <= 1'b1;
      if (ls_timer_arm_i) begin
        ls_bedtime_armed_q <= 1'b1;
        ls_alarm_armed_q <= 1'b1;
      end
      if (asep_ts_capture_req_i) asep_ts_q <= ptb_clk_i[31:0];

      if (ptb_running_i && leader_enable_i) begin
        if (tdd_count_q >= TDD_CYCLE_TICS[$bits(tdd_count_q)-1:0] - 1'b1) begin
          tdd_count_q <= '0;
          tdd_cycle_start_o <= 1'b1;
        end else begin
          tdd_count_q <= tdd_count_q + {{($bits(tdd_count_q)-1){1'b0}}, 1'b1};
        end
      end else begin
        tdd_count_q <= '0;
      end

      if (ptb_running_i && start_tdd_armed_q && (ptb_clk_i >= start_tdd_ptbtime_i)) begin
        start_tdd_trigger_o <= 1'b1;
        start_tdd_armed_q <= 1'b0;
      end

      if (ptb_running_i && ls_bedtime_armed_q && (ptb_clk_i >= ls_bedtime_i)) begin
        ls_bedtime_trigger_o <= 1'b1;
        ls_bedtime_armed_q <= 1'b0;
      end

      if (ptb_running_i && ls_alarm_armed_q && (ptb_clk_i >= ls_alarmclock_i)) begin
        ls_alarm_trigger_o <= 1'b1;
        ls_alarm_armed_q <= 1'b0;
      end
    end
  end

  assign asep_ts_value_o = asep_ts_q;

endmodule

`default_nettype wire
