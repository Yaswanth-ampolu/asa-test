`timescale 1ns/1ps
`default_nettype none

module spi_ase_tx
  import asa_asep_pkg::*;
  import asa_spi_asep_pkg::*;
(
  input  logic            clk,
  input  logic            rst,
  input  logic            soft_reset_i,
  input  logic            ptb_tick_i,
  input  logic            tx_frame_start_i,
  input  logic            slot_indicate_i,
  input  logic            build_cfg_i,
  input  logic            build_data_i,
  input  logic            build_irq_i,
  input  spi_cfg_cmd_e    cfg_cmd_i,
  input  logic            cfg_ack_ok_i,
  input  asep_ts_mode_e   ts_mode_i,
  input  logic [31:0]     ts_value_i,
  input  logic [15:0]     spi_cfg_reg_i,
  input  logic [15:0]     spi_min_idle_reg_i,
  input  logic [7:0]      spi_stc_i,
  input  logic [7:0]      spi_tat_mult_i,
  input  logic [19:0]     spi_dcp_ticks_i,
  input  logic            reduce_latency_i,
  input  logic [3:0]      csn_i,
  input  spi_pkt_status_e pkt_status_i,
  input  logic [29:0]     last_cs_pos_i,
  input  spi_op_status_e  op_status_i,
  input  logic            irq_flag_i,
  input  logic            reset_req_i,
  input  logic [7:0]      spi_len_i,
  input  spi_symbol_vec_t symbols_i,
  output logic            packet_valid_o,
  output asep_packet_t    packet_o,
  output logic [11:0]     packet_len_o,
  output logic [6:0]      packet_id_o,
  output logic [7:0]      irq_count_o,
  output logic            dcp_waiting_o,
  output logic            tat_active_o,
  output logic            stc_tx_err_o
);

  logic [6:0] pkt_id_q;
  logic [7:0] irq_cnt_q;
  logic pkt_adv, irq_adv;
  logic dcp_active, dcp_expire, tat_active, tat_expire;
  logic wait_after_first_q, wait_after_first_n;
  logic [7:0] slot_wait_q, slot_wait_n;
  logic [6:0] use_pkt_id;
  logic [7:0] use_irq_cnt;
  asep_packet_t cfg_packet, data_packet;
  logic [11:0] cfg_packet_len, data_packet_len;

  spi_pkt_id_counter u_pid(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i), .advance_i(pkt_adv), .pkt_id_o(pkt_id_q)
  );

  spi_irq_counter u_irq(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i), .advance_i(irq_adv), .irq_count_o(irq_cnt_q)
  );

  spi_dcp_timer u_dcp(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i), .ptb_tick_i(ptb_tick_i),
    .start_i(tx_frame_start_i), .dcp_ticks_i(spi_dcp_ticks_i),
    .active_o(dcp_active), .expired_pulse_o(dcp_expire)
  );

  spi_tat_timer u_tat(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i), .ptb_tick_i(ptb_tick_i),
    .start_i(build_data_i && (pkt_status_i == SPI_PKT_VALID)),
    .tat_mult_i(spi_tat_mult_i), .dcp_ticks_i(spi_dcp_ticks_i),
    .active_o(tat_active), .expired_pulse_o(tat_expire)
  );

  spi_cfg_codec u_cfg(
    .cmd_i(cfg_cmd_i), .ack_ok_i(cfg_ack_ok_i), .pkt_id_i(pkt_id_q),
    .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .spi_cfg_reg_i(spi_cfg_reg_i), .spi_min_idle_reg_i(spi_min_idle_reg_i),
    .packet_o(cfg_packet), .packet_len_o(cfg_packet_len)
  );

  spi_data_codec u_data(
    .encode_i(1'b1), .decode_i(1'b0), .is_interrupt_i(build_irq_i),
    .pkt_id_i(pkt_id_q), .irq_count_i(irq_cnt_q), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .reduce_latency_i(reduce_latency_i), .csn_i(csn_i), .pkt_status_i(pkt_status_i),
    .spi_len_i(spi_len_i), .last_cs_pos_i(last_cs_pos_i), .op_status_i(op_status_i),
    .irq_flag_i(irq_flag_i), .reset_req_i(reset_req_i), .symbols_i(symbols_i),
    .packet_i('0), .packet_len_i('0),
    .packet_o(data_packet), .packet_len_o(data_packet_len),
    .is_interrupt_o(), .pkt_id_o(), .irq_count_o(), .reduce_latency_o(), .csn_o(),
    .pkt_status_o(), .spi_len_o(), .last_cs_pos_o(), .op_status_o(), .irq_flag_o(),
    .reset_req_o(), .symbols_o(), .crc_error_o(), .format_error_o()
  );

  always_comb begin
    wait_after_first_n = wait_after_first_q;
    slot_wait_n        = slot_wait_q;
    stc_tx_err_o       = 1'b0;

    if (tx_frame_start_i) begin
      wait_after_first_n = 1'b1;
      slot_wait_n        = 8'd0;
    end else if (wait_after_first_q && slot_indicate_i) begin
      wait_after_first_n = 1'b0;
    end

    if (wait_after_first_q && !dcp_active && !slot_indicate_i) begin
      if (slot_wait_q >= spi_stc_i && (spi_stc_i != 8'd0)) stc_tx_err_o = 1'b1;
      else slot_wait_n = slot_wait_q + 8'd1;
    end

    if (slot_indicate_i) slot_wait_n = 8'd0;
  end

  always_ff @(posedge clk) begin
    if (rst || soft_reset_i) begin
      wait_after_first_q <= 1'b0;
      slot_wait_q        <= 8'd0;
    end else begin
      wait_after_first_q <= wait_after_first_n;
      slot_wait_q        <= slot_wait_n;
    end
  end

  always_comb begin
    packet_valid_o = 1'b0;
    packet_o       = '0;
    packet_len_o   = 12'd0;
    pkt_adv        = 1'b0;
    irq_adv        = 1'b0;

    if (build_cfg_i) begin
      packet_valid_o = 1'b1;
      packet_o       = cfg_packet;
      packet_len_o   = cfg_packet_len;
      pkt_adv        = 1'b1;
    end else if (build_data_i) begin
      if (!wait_after_first_q || !dcp_active || slot_indicate_i) begin
        packet_valid_o = 1'b1;
        packet_o       = data_packet;
        packet_len_o   = data_packet_len;
        pkt_adv        = 1'b1;
        irq_adv        = build_irq_i;
      end
    end
  end

  assign packet_id_o   = pkt_id_q;
  assign irq_count_o   = irq_cnt_q;
  assign dcp_waiting_o = dcp_active;
  assign tat_active_o  = tat_active;

endmodule

`default_nettype wire
