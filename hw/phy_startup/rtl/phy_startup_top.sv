`timescale 1ns/1ps
`default_nettype none

// ASA PHY Startup and PMA Training FSM
// Spec: Sections 4.2.7 and 4.3.3.1. This block controls startup phase
// sequencing and exposes PCS/PMA controls; it does not implement the PCS
// pattern datapath itself.

module phy_startup_top
  import asa_node_pkg::*;
  import asa_error_pkg::*;
  import asa_phy_startup_pkg::*;
#(
  // Bind these to real clock-derived values at top integration.
  parameter int unsigned PH1G_TIMER_CYCLES     = 20, // spec timer: 200 us
  parameter int unsigned PHSG_TIMER_CYCLES     = 6,  // spec timer: 312 ns
  parameter int unsigned TEST_TIMER_CYCLES     = 10, // spec timer: 20 ms (+ runtime)
  parameter int unsigned MS_TICK_CYCLES        = 100
) (
  input  logic              clk,
  input  logic              rst,
  input  logic              soft_reset_i,

  // Node State Machine dependency.
  input  logic [3:0]        node_state_i,
  output logic              startup_complete_o,
  output logic              startup_fail_o,
  output logic              startup_test_mode_req_o,
  output logic              startup_test_complete_o,
  output logic              oam_config_skip_o,

  // Register/configuration inputs.
  input  logic              is_root_i,
  input  logic [15:0]       sg_config_i,
  input  logic [13:0]       sg_capability_i,
  input  logic [1:0]        security_policy_i,
  input  logic              phy_layer_mode_i,
  input  logic [15:0]       diag_test_ctrl_i,
  input  logic              oam_config_skip_req_i,
  input  logic [1:0]        polarity_status_i,

  // PCS decoded startup status inputs. Status values are from Tables 4-15/4-20.
  input  logic              ph1g_self_good_i,
  input  phy_start_status_e ph1g_lp_stat_i,
  input  logic              ph1g_lp_valid_i,
  input  logic              ph1g_test_req_i,
  input  logic              phsga_self_good_i,
  input  phy_start_status_e phsga_lp_stat_i,
  input  logic              phsga_lp_valid_i,
  input  logic              phsga_test_req_i,
  input  logic              phsgb_self_good_i,
  input  phy_start_status_e phsgb_lp_stat_i,
  input  logic              phsgb_lp_valid_i,
  input  logic              phsgc_self_good_i,
  input  phy_start_status_e phsgc_lp_stat_i,
  input  logic              phsgc_lp_valid_i,
  input  logic              rx_burst_active_i,

  // PCS/PMA controls.
  output phy_start_phase_e  startup_phase_o,
  output phy_start_pattern_e tx_pattern_sel_o,
  output logic              tx_start_o,
  output phy_start_status_e tx_status_o,
  output logic [39:0]       tx_phase1g_info_o,
  output logic [511:0]      tx_phasesg_info_o,
  output logic              pma_reset_o,
  output logic              pma_disable_o,
  output logic              pma_enable_o,
  output logic              startup_ptb_init_o,

  // Register status outputs.
  output logic [15:0]       link_training_status_o,
  output logic [15:0]       ext_link_training_status_o,
  output logic [15:0]       connectivity_id_o,
  output logic [7:0]        retry_count_o,
  output logic [4:0]        timeout_count_o,
  output logic [23:0]       phasesg_count_o,

  // Error reporting.
  output err_event_t        err_event_o
);

  typedef enum logic [4:0] {
    ST_IDLE,
    ST_INIT,
    ST_PH1G_TX,
    ST_PH1G_WAIT,
    ST_SGA_INIT,
    ST_SGA_TX,
    ST_SGA_WAIT,
    ST_SGB_INIT,
    ST_SGB_TX,
    ST_SGB_WAIT,
    ST_SGC_INIT,
    ST_SGC_TX,
    ST_SGC_WAIT,
    ST_TX_TEST_INIT,
    ST_TX_TEST_WAIT,
    ST_TX_TEST_RUN,
    ST_ROOT_RX_TEST_CMD,
    ST_ROOT_RX_TEST_WAIT,
    ST_RX_TEST_WAIT1,
    ST_RX_TEST_RUN,
    ST_RX_TEST_WAIT2,
    ST_RX_TEST_REPLY,
    ST_COMPLETE,
    ST_FAIL
  } state_e;

  state_e state_q, state_d, prev_state_q;
  logic [$clog2(PH1G_TIMER_CYCLES+PHSG_TIMER_CYCLES+TEST_TIMER_CYCLES+MS_TICK_CYCLES+2)-1:0] timer_q, timer_d;
  logic [7:0] retry_q, retry_d;
  logic [4:0] timeout_q, timeout_d;
  logic [4:0] lp_error_q, lp_error_d;
  logic [23:0] phasesg_count_q, phasesg_count_d;
  logic [7:0] train_ms_q, train_ms_d;
  logic [$clog2(MS_TICK_CYCLES+1)-1:0] ms_tick_q, ms_tick_d;
  logic com_ready_q, com_ready_d;
  logic completed_skip_q, completed_skip_d;

  phy_start_status_e tx_status_q, tx_status_d;
  phy_start_pattern_e tx_pattern_q, tx_pattern_d;
  phy_tx_test_e tx_test_sel;
  phy_rx_test_e rx_test_sel;
  logic tx_start_d;
  logic startup_complete_d;
  logic startup_fail_d;
  logic test_mode_req_d;
  logic test_complete_d;
  logic pma_reset_d;
  logic pma_disable_d;
  logic pma_enable_d;
  logic ptb_init_d;
  err_event_t err_event_d;

  logic diag_enable;
  logic [3:0] diag_type;
  logic diag_tx_test;
  logic diag_rx_test;
  logic leaf_ph1g_tx_test_req;
  logic root_sga_rx_test_req;
  logic leaf_sga_rx_test_req;
  logic in_startup_node_state;
  logic timer_done;
  logic phsgc_needed;

  assign diag_enable = diag_test_ctrl_i[0];
  assign diag_type   = diag_test_ctrl_i[4:1];
  assign diag_tx_test = diag_enable && (diag_type >= 4'd1) && (diag_type <= 4'd5);
  assign diag_rx_test = diag_enable && ((diag_type == 4'd6) || (diag_type == 4'd7));
  assign leaf_ph1g_tx_test_req = !is_root_i && ph1g_lp_valid_i &&
                                  (ph1g_lp_stat_i == PHY_START_STAT_PROCEED) &&
                                  ph1g_test_req_i;
  assign root_sga_rx_test_req = is_root_i &&
                                (diag_rx_test ||
                                 (phsga_lp_valid_i && phsga_test_req_i &&
                                  ((phsga_lp_stat_i == PHY_START_STAT_TRAINING) ||
                                   (phsga_lp_stat_i == PHY_START_STAT_PREPARED))));
  assign leaf_sga_rx_test_req = !is_root_i && phsga_lp_valid_i &&
                                (phsga_lp_stat_i == PHY_START_STAT_PREPARED) &&
                                phsga_test_req_i;
  assign in_startup_node_state = (node_state_i == ASA_STATE_STARTUP);
  assign timer_done = (timer_q == '0);
  assign phsgc_needed = speed_grade_needs_sgc(sg_config_i);

  always_comb begin
    case (diag_type)
      4'd1: tx_test_sel = PHY_TX_TEST_LINEARITY;
      4'd2: tx_test_sel = PHY_TX_TEST_JITTER;
      4'd3: tx_test_sel = PHY_TX_TEST_DROOP;
      4'd4: tx_test_sel = PHY_TX_TEST_PSD;
      4'd5: tx_test_sel = PHY_TX_TEST_BER;
      default: tx_test_sel = PHY_TX_TEST_NONE;
    endcase

    case (diag_type)
      4'd6: rx_test_sel = PHY_RX_TEST_NOISE;
      4'd7: rx_test_sel = PHY_RX_TEST_BER;
      default: rx_test_sel = PHY_RX_TEST_NONE;
    endcase
  end

  function automatic phy_start_phase_e public_phase(input state_e s);
    case (s)
      ST_INIT: public_phase = PHY_START_INIT;
      ST_PH1G_TX, ST_PH1G_WAIT: public_phase = PHY_START_PHASE1G;
      ST_SGA_INIT, ST_SGA_TX, ST_SGA_WAIT: public_phase = PHY_START_SGA;
      ST_SGB_INIT, ST_SGB_TX, ST_SGB_WAIT: public_phase = PHY_START_SGB;
      ST_SGC_INIT, ST_SGC_TX, ST_SGC_WAIT: public_phase = PHY_START_SGC;
      ST_TX_TEST_INIT, ST_TX_TEST_WAIT, ST_TX_TEST_RUN: public_phase = PHY_START_TX_TEST;
      ST_ROOT_RX_TEST_CMD, ST_ROOT_RX_TEST_WAIT: public_phase = PHY_START_RX_TEST;
      ST_RX_TEST_WAIT1, ST_RX_TEST_RUN, ST_RX_TEST_WAIT2, ST_RX_TEST_REPLY: public_phase = PHY_START_RX_TEST;
      ST_COMPLETE: public_phase = PHY_START_COMPLETE;
      ST_FAIL: public_phase = PHY_START_FAIL;
      default: public_phase = PHY_START_IDLE;
    endcase
  endfunction

  function automatic logic [7:0] sat_ms_inc(input logic [7:0] value);
    return (value >= 8'hFB) ? 8'hFB : value + 8'd1;
  endfunction

  function automatic logic should_retry_ph1g(
    input phy_start_status_e lp_stat,
    input logic lp_valid,
    input logic timeout
  );
    return timeout || (lp_valid && (lp_stat == PHY_START_STAT_ERROR));
  endfunction

  function automatic logic should_restart_phsg(
    input phy_start_status_e lp_stat,
    input logic lp_valid,
    input logic timeout
  );
    return timeout || (lp_valid && (lp_stat == PHY_START_STAT_ERROR));
  endfunction

  always_comb begin
    state_d = state_q;
    timer_d = (timer_q != '0) ? timer_q - {{($bits(timer_q)-1){1'b0}}, 1'b1} : '0;
    retry_d = retry_q;
    timeout_d = timeout_q;
    lp_error_d = lp_error_q;
    phasesg_count_d = phasesg_count_q;
    train_ms_d = train_ms_q;
    ms_tick_d = ms_tick_q;
    com_ready_d = com_ready_q;
    completed_skip_d = completed_skip_q;
    tx_status_d = tx_status_q;
    tx_pattern_d = tx_pattern_q;

    tx_start_d = 1'b0;
    startup_complete_d = 1'b0;
    startup_fail_d = 1'b0;
    test_mode_req_d = 1'b0;
    test_complete_d = 1'b0;
    pma_reset_d = 1'b0;
    pma_disable_d = 1'b0;
    pma_enable_d = 1'b0;
    ptb_init_d = 1'b0;
    err_event_d = '0;
    err_event_d.source = ERR_SRC_LOCAL_PHY;

    if ((state_q != ST_IDLE) && (state_q != ST_COMPLETE) && (state_q != ST_FAIL)) begin
      if (ms_tick_q == MS_TICK_CYCLES[$bits(ms_tick_q)-1:0] - 1'b1) begin
        ms_tick_d = '0;
        train_ms_d = sat_ms_inc(train_ms_q);
      end else begin
        ms_tick_d = ms_tick_q + {{($bits(ms_tick_q)-1){1'b0}}, 1'b1};
      end
    end

    unique case (state_q)
      ST_IDLE: begin
        com_ready_d = 1'b0;
        tx_pattern_d = PHY_PATTERN_IDLE;
        if (in_startup_node_state) begin
          state_d = ST_INIT;
        end
      end

      ST_INIT: begin
        if (prev_state_q == ST_IDLE) begin
          retry_d = 8'd0;
          timeout_d = 5'd0;
          lp_error_d = 5'd0;
          train_ms_d = 8'd0;
          ms_tick_d = '0;
        end
        phasesg_count_d = 24'd0;
        com_ready_d = 1'b0;
        completed_skip_d = 1'b0;
        pma_reset_d = 1'b1;
        pma_enable_d = 1'b1;
        ptb_init_d = 1'b1;
        timer_d = PH1G_TIMER_CYCLES[$bits(timer_q)-1:0];
        state_d = is_root_i ? ST_PH1G_TX : ST_PH1G_WAIT;
      end

      ST_PH1G_TX: begin
        tx_pattern_d = PHY_PATTERN_PHASE1G;
        tx_status_d = ph1g_self_good_i ? PHY_START_STAT_PREPARED : PHY_START_STAT_TRAINING;
        if (!rx_burst_active_i) begin
          tx_start_d = 1'b1;
          timer_d = PH1G_TIMER_CYCLES[$bits(timer_q)-1:0];
          state_d = ST_PH1G_WAIT;
        end
      end

      ST_PH1G_WAIT: begin
        if (diag_tx_test || leaf_ph1g_tx_test_req) begin
          test_mode_req_d = 1'b1;
          state_d = ST_TX_TEST_INIT;
        end else if (should_retry_ph1g(ph1g_lp_stat_i, ph1g_lp_valid_i, timer_done)) begin
          timeout_d = sat_inc5(timeout_q);
          if (ph1g_lp_valid_i && ph1g_lp_stat_i == PHY_START_STAT_ERROR) begin
            lp_error_d = sat_inc5(lp_error_q);
          end
          retry_d = sat_inc8(retry_q);
          if (sat_inc8(retry_q) >= PHY_PH1G_RTRY_CNT_LIMIT[7:0]) begin
            state_d = ST_FAIL;
          end else begin
            state_d = is_root_i ? ST_PH1G_TX : ST_PH1G_WAIT;
            timer_d = PH1G_TIMER_CYCLES[$bits(timer_q)-1:0];
          end
        end else if (is_root_i) begin
          if (ph1g_lp_valid_i && ph1g_self_good_i && ph1g_lp_stat_i == PHY_START_STAT_PROCEED) begin
            state_d = ST_SGA_INIT;
          end else if (ph1g_lp_valid_i &&
                       (ph1g_lp_stat_i == PHY_START_STAT_TRAINING ||
                        ph1g_lp_stat_i == PHY_START_STAT_PREPARED)) begin
            state_d = ST_PH1G_TX;
          end
        end else begin
          if (ph1g_lp_valid_i && ph1g_self_good_i &&
              ph1g_lp_stat_i == PHY_START_STAT_PREPARED &&
              !ph1g_test_req_i) begin
            tx_pattern_d = PHY_PATTERN_PHASE1G;
            tx_status_d = PHY_START_STAT_PROCEED;
            if (!rx_burst_active_i) begin
              tx_start_d = 1'b1;
              state_d = ST_SGA_INIT;
            end
          end else if (ph1g_lp_valid_i) begin
            state_d = ST_PH1G_TX;
          end
        end
      end

      ST_SGA_INIT: begin
        phasesg_count_d = 24'd0;
        state_d = is_root_i ? ST_SGA_TX : ST_SGA_WAIT;
        timer_d = PHSG_TIMER_CYCLES[$bits(timer_q)-1:0];
      end

      ST_SGA_TX: begin
        tx_pattern_d = PHY_PATTERN_PHASE_SGA;
        tx_status_d = phsga_self_good_i ? PHY_START_STAT_PREPARED : PHY_START_STAT_TRAINING;
        if (!rx_burst_active_i) begin
          tx_start_d = 1'b1;
          phasesg_count_d = phasesg_count_q + 24'd1;
          timer_d = PHSG_TIMER_CYCLES[$bits(timer_q)-1:0];
          state_d = ST_SGA_WAIT;
        end
      end

      ST_SGA_WAIT: begin
        if (root_sga_rx_test_req) begin
          test_mode_req_d = 1'b1;
          state_d = ST_ROOT_RX_TEST_CMD;
        end else if (leaf_sga_rx_test_req) begin
          test_mode_req_d = 1'b1;
          state_d = ST_RX_TEST_WAIT1;
          timer_d = TEST_TIMER_CYCLES[$bits(timer_q)-1:0];
        end else if (should_restart_phsg(phsga_lp_stat_i, phsga_lp_valid_i, timer_done)) begin
          timeout_d = sat_inc5(timeout_q);
          if (phsga_lp_valid_i && phsga_lp_stat_i == PHY_START_STAT_ERROR) lp_error_d = sat_inc5(lp_error_q);
          state_d = ST_INIT;
        end else if (is_root_i) begin
          if (phsga_lp_valid_i && phsga_self_good_i && phsga_lp_stat_i == PHY_START_STAT_PROCEED) state_d = ST_SGB_INIT;
          else if (phsga_lp_valid_i &&
                   (phsga_lp_stat_i == PHY_START_STAT_TRAINING ||
                    phsga_lp_stat_i == PHY_START_STAT_PREPARED)) state_d = ST_SGA_TX;
        end else begin
          if (phsga_lp_valid_i && phsga_self_good_i && phsga_lp_stat_i == PHY_START_STAT_PREPARED) begin
            tx_pattern_d = PHY_PATTERN_PHASE_SGA;
            tx_status_d = PHY_START_STAT_PROCEED;
            if (!rx_burst_active_i) begin
              tx_start_d = 1'b1;
              phasesg_count_d = phasesg_count_q + 24'd1;
              state_d = ST_SGB_INIT;
            end
          end else if (phsga_lp_valid_i) begin
            state_d = ST_SGA_TX;
          end
        end
      end

      ST_SGB_INIT: begin
        state_d = is_root_i ? ST_SGB_TX : ST_SGB_WAIT;
        timer_d = PHSG_TIMER_CYCLES[$bits(timer_q)-1:0];
      end

      ST_SGB_TX: begin
        tx_pattern_d = PHY_PATTERN_PHASE_SGB;
        tx_status_d = phsgb_self_good_i ? PHY_START_STAT_PREPARED : PHY_START_STAT_TRAINING;
        if (!rx_burst_active_i) begin
          tx_start_d = 1'b1;
          phasesg_count_d = phasesg_count_q + 24'd1;
          timer_d = PHSG_TIMER_CYCLES[$bits(timer_q)-1:0];
          state_d = ST_SGB_WAIT;
        end
      end

      ST_SGB_WAIT: begin
        if (should_restart_phsg(phsgb_lp_stat_i, phsgb_lp_valid_i, timer_done)) begin
          timeout_d = sat_inc5(timeout_q);
          if (phsgb_lp_valid_i && phsgb_lp_stat_i == PHY_START_STAT_ERROR) lp_error_d = sat_inc5(lp_error_q);
          state_d = ST_INIT;
        end else if (is_root_i) begin
          if (phsgb_lp_valid_i && phsgb_self_good_i && phsgb_lp_stat_i == PHY_START_STAT_PROCEED) begin
            state_d = phsgc_needed ? ST_SGC_INIT : ST_COMPLETE;
          end else if (phsgb_lp_valid_i &&
                       (phsgb_lp_stat_i == PHY_START_STAT_TRAINING ||
                        phsgb_lp_stat_i == PHY_START_STAT_PREPARED)) begin
            state_d = ST_SGB_TX;
          end
        end else begin
          if (phsgb_lp_valid_i && phsgb_self_good_i && phsgb_lp_stat_i == PHY_START_STAT_PREPARED) begin
            tx_pattern_d = PHY_PATTERN_PHASE_SGB;
            tx_status_d = PHY_START_STAT_PROCEED;
            if (!rx_burst_active_i) begin
              tx_start_d = 1'b1;
              phasesg_count_d = phasesg_count_q + 24'd1;
              state_d = phsgc_needed ? ST_SGC_INIT : ST_COMPLETE;
            end
          end else if (phsgb_lp_valid_i) begin
            state_d = ST_SGB_TX;
          end
        end
      end

      ST_SGC_INIT: begin
        state_d = is_root_i ? ST_SGC_TX : ST_SGC_WAIT;
        timer_d = PHSG_TIMER_CYCLES[$bits(timer_q)-1:0];
      end

      ST_SGC_TX: begin
        tx_pattern_d = PHY_PATTERN_PHASE_SGC;
        tx_status_d = phsgc_self_good_i ? PHY_START_STAT_PREPARED : PHY_START_STAT_TRAINING;
        if (!rx_burst_active_i) begin
          tx_start_d = 1'b1;
          phasesg_count_d = phasesg_count_q + 24'd1;
          timer_d = PHSG_TIMER_CYCLES[$bits(timer_q)-1:0];
          state_d = ST_SGC_WAIT;
        end
      end

      ST_SGC_WAIT: begin
        if (should_restart_phsg(phsgc_lp_stat_i, phsgc_lp_valid_i, timer_done)) begin
          timeout_d = sat_inc5(timeout_q);
          if (phsgc_lp_valid_i && phsgc_lp_stat_i == PHY_START_STAT_ERROR) lp_error_d = sat_inc5(lp_error_q);
          state_d = ST_INIT;
        end else if (is_root_i) begin
          if (phsgc_lp_valid_i && phsgc_self_good_i && phsgc_lp_stat_i == PHY_START_STAT_PROCEED) state_d = ST_COMPLETE;
          else if (phsgc_lp_valid_i &&
                   (phsgc_lp_stat_i == PHY_START_STAT_TRAINING ||
                    phsgc_lp_stat_i == PHY_START_STAT_PREPARED)) state_d = ST_SGC_TX;
        end else begin
          if (phsgc_lp_valid_i && phsgc_self_good_i && phsgc_lp_stat_i == PHY_START_STAT_PREPARED) begin
            tx_pattern_d = PHY_PATTERN_PHASE_SGC;
            tx_status_d = PHY_START_STAT_PROCEED;
            if (!rx_burst_active_i) begin
              tx_start_d = 1'b1;
              phasesg_count_d = phasesg_count_q + 24'd1;
              state_d = ST_COMPLETE;
            end
          end else if (phsgc_lp_valid_i) begin
            state_d = ST_SGC_TX;
          end
        end
      end

      ST_TX_TEST_INIT: begin
        tx_pattern_d = PHY_PATTERN_TX_TEST;
        pma_disable_d = 1'b1;
        state_d = ST_TX_TEST_WAIT;
        timer_d = TEST_TIMER_CYCLES[$bits(timer_q)-1:0];
      end

      ST_TX_TEST_WAIT: begin
        if (timer_done) state_d = ST_TX_TEST_RUN;
      end

      ST_TX_TEST_RUN: begin
        test_complete_d = 1'b1;
        state_d = ST_INIT;
      end

      ST_ROOT_RX_TEST_CMD: begin
        tx_pattern_d = PHY_PATTERN_PHASE_SGA;
        tx_status_d = PHY_START_STAT_PROCEED;
        pma_disable_d = 1'b1;
        test_mode_req_d = 1'b1;
        if (!rx_burst_active_i) begin
          tx_start_d = 1'b1;
          timer_d = TEST_TIMER_CYCLES[$bits(timer_q)-1:0];
          state_d = ST_ROOT_RX_TEST_WAIT;
        end
      end

      ST_ROOT_RX_TEST_WAIT: begin
        if (timer_done) begin
          test_complete_d = 1'b1;
          state_d = ST_INIT;
        end
      end

      ST_RX_TEST_WAIT1: begin
        if (timer_done) begin
          state_d = ST_RX_TEST_RUN;
          timer_d = TEST_TIMER_CYCLES[$bits(timer_q)-1:0];
        end
      end

      ST_RX_TEST_RUN: begin
        if (timer_done) begin
          state_d = ST_RX_TEST_WAIT2;
          timer_d = TEST_TIMER_CYCLES[$bits(timer_q)-1:0];
        end
      end

      ST_RX_TEST_WAIT2: begin
        if (timer_done) state_d = ST_RX_TEST_REPLY;
      end

      ST_RX_TEST_REPLY: begin
        tx_pattern_d = PHY_PATTERN_RX_REPLY;
        tx_status_d = PHY_START_STAT_PROCEED;
        if (!rx_burst_active_i) begin
          tx_start_d = 1'b1;
          test_complete_d = 1'b1;
          state_d = ST_INIT;
        end
      end

      ST_COMPLETE: begin
        com_ready_d = 1'b1;
        completed_skip_d = oam_config_skip_req_i;
        startup_complete_d = 1'b1;
        if (!in_startup_node_state) state_d = ST_IDLE;
      end

      ST_FAIL: begin
        startup_fail_d = 1'b1;
        pma_disable_d = 1'b1;
        err_event_d.valid = 1'b1;
        err_event_d.severity = ERR_SEV_FATAL;
        err_event_d.code = PHY_ERR_STARTUP_FAIL;
        if (!in_startup_node_state) state_d = ST_IDLE;
      end

      default: state_d = ST_IDLE;
    endcase

    if (!in_startup_node_state && state_q != ST_IDLE) begin
      state_d = ST_IDLE;
      pma_disable_d = 1'b1;
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q <= ST_IDLE;
      prev_state_q <= ST_IDLE;
      timer_q <= '0;
      retry_q <= 8'd0;
      timeout_q <= 5'd0;
      lp_error_q <= 5'd0;
      phasesg_count_q <= 24'd0;
      train_ms_q <= 8'd0;
      ms_tick_q <= '0;
      com_ready_q <= 1'b0;
      completed_skip_q <= 1'b0;
      tx_status_q <= PHY_START_STAT_TRAINING;
      tx_pattern_q <= PHY_PATTERN_IDLE;
    end else if (soft_reset_i) begin
      state_q <= in_startup_node_state ? ST_INIT : ST_IDLE;
      prev_state_q <= ST_IDLE;
      timer_q <= '0;
      retry_q <= 8'd0;
      timeout_q <= 5'd0;
      lp_error_q <= 5'd0;
      phasesg_count_q <= 24'd0;
      train_ms_q <= 8'd0;
      ms_tick_q <= '0;
      com_ready_q <= 1'b0;
      completed_skip_q <= 1'b0;
      tx_status_q <= PHY_START_STAT_TRAINING;
      tx_pattern_q <= PHY_PATTERN_IDLE;
    end else begin
      state_q <= state_d;
      prev_state_q <= state_q;
      timer_q <= timer_d;
      retry_q <= retry_d;
      timeout_q <= timeout_d;
      lp_error_q <= lp_error_d;
      phasesg_count_q <= phasesg_count_d;
      train_ms_q <= train_ms_d;
      ms_tick_q <= ms_tick_d;
      com_ready_q <= com_ready_d;
      completed_skip_q <= completed_skip_d;
      tx_status_q <= tx_status_d;
      tx_pattern_q <= tx_pattern_d;
    end
  end

  assign startup_phase_o = public_phase(state_q);
  assign tx_pattern_sel_o = tx_pattern_q;
  assign tx_status_o = tx_status_q;
  assign tx_start_o = tx_start_d;
  assign startup_complete_o = startup_complete_d;
  assign startup_fail_o = startup_fail_d;
  assign startup_test_mode_req_o = test_mode_req_d;
  assign startup_test_complete_o = test_complete_d;
  assign oam_config_skip_o = completed_skip_q;
  assign pma_reset_o = pma_reset_d;
  assign pma_disable_o = pma_disable_d;
  assign pma_enable_o = pma_enable_d;
  assign startup_ptb_init_o = ptb_init_d;
  assign err_event_o = err_event_d;

  assign retry_count_o = retry_q;
  assign timeout_count_o = timeout_q;
  assign phasesg_count_o = phasesg_count_q;

  assign tx_phase1g_info_o = build_phase1g_info(
    tx_status_q,
    sg_capability_i,
    sg_config_i[4:0],
    tx_test_sel,
    security_policy_i,
    phy_layer_mode_i
  );

  assign tx_phasesg_info_o = build_phasesg_info(
    tx_status_q,
    phasesg_count_q,
    oam_config_skip_req_i,
    rx_test_sel
  );

  assign link_training_status_o = {
    lp_error_q,
    com_ready_q,
    polarity_status_i,
    train_ms_q
  };

  assign ext_link_training_status_o = {
    3'b000,
    timeout_q,
    retry_q
  };

  assign connectivity_id_o = {
    9'd0,
    sg_config_i[6:5],
    5'd0
  };

endmodule

`default_nettype wire
