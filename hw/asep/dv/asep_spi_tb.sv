`timescale 1ns/1ps
`default_nettype none

module asep_spi_tb;
  import asa_asep_pkg::*;
  import asa_spi_asep_pkg::*;

  logic clk, rst, soft_reset;
  initial begin clk = 0; forever #5 clk = ~clk; end

  int pass_count, fail_count;
  task automatic check(input string name, input logic cond);
    if (cond) pass_count++;
    else begin
      $display("FAIL: %s", name);
      fail_count++;
    end
  endtask
  task automatic tick(input int n = 1);
    repeat (n) @(posedge clk);
    #1;
  endtask

  logic adv;
  logic [6:0] pkt_id;
  spi_pkt_id_counter u_ctr(.clk(clk), .rst(rst), .soft_reset_i(soft_reset), .advance_i(adv), .pkt_id_o(pkt_id));

  logic irq_adv;
  logic [7:0] irq_count;
  spi_irq_counter u_irq(.clk(clk), .rst(rst), .soft_reset_i(soft_reset), .advance_i(irq_adv), .irq_count_o(irq_count));

  spi_cfg_cmd_e cfg_cmd;
  logic cfg_ack_ok;
  asep_ts_mode_e ts_mode;
  logic [31:0] ts_value;
  logic [15:0] spi_cfg_reg, spi_idle_reg;
  asep_packet_t cfg_pkt;
  logic [11:0] cfg_len;
  spi_cfg_codec u_cfg(
    .cmd_i(cfg_cmd), .ack_ok_i(cfg_ack_ok), .pkt_id_i(pkt_id), .ts_mode_i(ts_mode), .ts_value_i(ts_value),
    .spi_cfg_reg_i(spi_cfg_reg), .spi_min_idle_reg_i(spi_idle_reg), .packet_o(cfg_pkt), .packet_len_o(cfg_len)
  );

  logic enc_irq, reduce_latency, irq_flag, reset_req;
  logic [3:0] csn;
  spi_pkt_status_e pkt_status, dec_pkt_status;
  logic [7:0] spi_len, dec_spi_len;
  logic [29:0] last_cs_pos, dec_last_cs_pos;
  spi_op_status_e op_status, dec_op_status;
  spi_symbol_vec_t symbols_in, symbols_out;
  asep_packet_t data_pkt;
  logic [11:0] data_len;
  logic dec_is_irq, dec_reduce, dec_irq_flag, dec_reset, dec_crc_err, dec_fmt_err;
  logic [6:0] dec_pkt_id;
  logic [7:0] dec_irq_count;
  logic [3:0] dec_csn;

  spi_data_codec u_codec(
    .encode_i(1'b1), .decode_i(1'b0), .is_interrupt_i(enc_irq), .pkt_id_i(pkt_id), .irq_count_i(irq_count),
    .ts_mode_i(ts_mode), .ts_value_i(ts_value), .reduce_latency_i(reduce_latency), .csn_i(csn),
    .pkt_status_i(pkt_status), .spi_len_i(spi_len), .last_cs_pos_i(last_cs_pos), .op_status_i(op_status),
    .irq_flag_i(irq_flag), .reset_req_i(reset_req), .symbols_i(symbols_in),
    .packet_i('0), .packet_len_i('0),
    .packet_o(data_pkt), .packet_len_o(data_len), .is_interrupt_o(), .pkt_id_o(), .irq_count_o(),
    .reduce_latency_o(), .csn_o(), .pkt_status_o(), .spi_len_o(), .last_cs_pos_o(), .op_status_o(),
    .irq_flag_o(), .reset_req_o(), .symbols_o(), .crc_error_o(), .format_error_o()
  );

  spi_data_codec u_dec(
    .encode_i(1'b0), .decode_i(1'b1), .is_interrupt_i(1'b0), .pkt_id_i('0), .irq_count_i('0),
    .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0), .reduce_latency_i('0), .csn_i('0),
    .pkt_status_i(SPI_PKT_VOID), .spi_len_i('0), .last_cs_pos_i('0), .op_status_i(SPI_OP_NORMAL),
    .irq_flag_i('0), .reset_req_i('0), .symbols_i('0),
    .packet_i(data_pkt), .packet_len_i(data_len),
    .packet_o(), .packet_len_o(), .is_interrupt_o(dec_is_irq), .pkt_id_o(dec_pkt_id), .irq_count_o(dec_irq_count),
    .reduce_latency_o(dec_reduce), .csn_o(dec_csn), .pkt_status_o(dec_pkt_status), .spi_len_o(dec_spi_len),
    .last_cs_pos_o(dec_last_cs_pos), .op_status_o(dec_op_status), .irq_flag_o(dec_irq_flag),
    .reset_req_o(dec_reset), .symbols_o(symbols_out), .crc_error_o(dec_crc_err), .format_error_o(dec_fmt_err)
  );

  logic ptb_tick, dcp_start, dcp_active, dcp_expire;
  spi_dcp_timer u_dcp(.clk(clk), .rst(rst), .soft_reset_i(soft_reset), .ptb_tick_i(ptb_tick), .start_i(dcp_start), .dcp_ticks_i(20'd3), .active_o(dcp_active), .expired_pulse_o(dcp_expire));
  logic tat_start, tat_active, tat_expire;
  spi_tat_timer u_tat(.clk(clk), .rst(rst), .soft_reset_i(soft_reset), .ptb_tick_i(ptb_tick), .start_i(tat_start), .tat_mult_i(8'd2), .dcp_ticks_i(20'd3), .active_o(tat_active), .expired_pulse_o(tat_expire));

  logic tx_frame_start, slot_ind, tx_build_cfg, tx_build_data, tx_build_irq;
  logic [7:0] spi_stc, tat_mult;
  logic [19:0] dcp_ticks;
  logic tx_pkt_valid, tx_dcp_wait, tx_tat_active, stc_tx_err;
  asep_packet_t tx_pkt;
  logic [11:0] tx_pkt_len;
  logic [6:0] tx_pkt_id;
  logic [7:0] tx_irq_count;

  logic rx_valid;
  asep_packet_t rx_in_pkt;
  logic [11:0] rx_in_pkt_len;
  logic [15:0] rx_cfg_shadow, rx_idle_shadow;
  logic rx_cfg_seen, rx_data_seen, rx_irq_seen, rx_reduce, rx_irq_flag, rx_reset_req, rx_crc_err, rx_gap, rx_fmt_err, stc_rx_err;
  spi_cfg_cmd_e rx_cfg_cmd;
  logic [3:0] rx_csn;
  spi_pkt_status_e rx_pkt_status;
  logic [7:0] rx_spi_len, rx_irq_cnt_seen;
  logic [29:0] rx_last_cs;
  spi_op_status_e rx_op_status;
  spi_symbol_vec_t rx_symbols;

  spi_asep_top u_top(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset), .ptb_tick_i(ptb_tick),
    .tx_frame_start_i(tx_frame_start), .slot_indicate_i(slot_ind),
    .tx_build_cfg_i(tx_build_cfg), .tx_build_data_i(tx_build_data), .tx_build_irq_i(tx_build_irq),
    .tx_cfg_cmd_i(cfg_cmd), .tx_cfg_ack_ok_i(cfg_ack_ok), .tx_ts_mode_i(ts_mode), .tx_ts_value_i(ts_value),
    .tx_spi_cfg_reg_i(spi_cfg_reg), .tx_spi_min_idle_reg_i(spi_idle_reg), .tx_spi_stc_i(spi_stc),
    .tx_spi_tat_mult_i(tat_mult), .tx_spi_dcp_ticks_i(dcp_ticks), .tx_reduce_latency_i(reduce_latency),
    .tx_csn_i(csn), .tx_pkt_status_i(pkt_status), .tx_last_cs_pos_i(last_cs_pos), .tx_op_status_i(op_status),
    .tx_irq_flag_i(irq_flag), .tx_reset_req_i(reset_req), .tx_spi_len_i(spi_len), .tx_symbols_i(symbols_in),
    .tx_packet_valid_o(tx_pkt_valid), .tx_packet_o(tx_pkt), .tx_packet_len_o(tx_pkt_len), .tx_packet_id_o(tx_pkt_id),
    .tx_irq_count_o(tx_irq_count), .tx_dcp_waiting_o(tx_dcp_wait), .tx_tat_active_o(tx_tat_active), .stc_tx_err_o(stc_tx_err),
    .rx_packet_valid_i(rx_valid), .rx_packet_i(rx_in_pkt), .rx_packet_len_i(rx_in_pkt_len),
    .rx_spi_cfg_shadow_o(rx_cfg_shadow), .rx_spi_min_idle_shadow_o(rx_idle_shadow),
    .rx_cfg_seen_o(rx_cfg_seen), .rx_data_seen_o(rx_data_seen), .rx_irq_seen_o(rx_irq_seen), .rx_cfg_cmd_o(rx_cfg_cmd),
    .rx_reduce_latency_o(rx_reduce), .rx_csn_o(rx_csn), .rx_pkt_status_o(rx_pkt_status), .rx_spi_len_o(rx_spi_len),
    .rx_last_cs_pos_o(rx_last_cs), .rx_op_status_o(rx_op_status), .rx_irq_flag_o(rx_irq_flag), .rx_reset_req_o(rx_reset_req),
    .rx_irq_count_o(rx_irq_cnt_seen), .rx_symbols_o(rx_symbols), .rx_crc_error_o(rx_crc_err), .rx_pkt_id_gap_o(rx_gap),
    .rx_format_error_o(rx_fmt_err), .stc_rx_err_o(stc_rx_err)
  );

  function automatic spi_symbol_vec_t sym_set(input spi_symbol_vec_t cur, input int idx, input logic cs1_f, input logic cs0_f, input logic [7:0] data_f);
    spi_symbol_t s;
    s.cs1 = cs1_f;
    s.cs0 = cs0_f;
    s.data = data_f;
    return spi_symbol_set(cur, idx, s);
  endfunction

  initial begin
    logic [31:0] crc_fix;
    logic [7:0] tb_byte;
    rst = 1'b1; soft_reset = 1'b0; ptb_tick = 1'b0; dcp_start = 1'b0; tat_start = 1'b0;
    adv = 1'b0; irq_adv = 1'b0; cfg_cmd = SPI_CFG_WRITE; cfg_ack_ok = 1'b1; ts_mode = ASEP_TS_NONE; ts_value = 32'd0;
    spi_cfg_reg = 16'h1234; spi_idle_reg = 16'h0055; enc_irq = 1'b0; reduce_latency = 1'b1; csn = 4'd3;
    pkt_status = SPI_PKT_VALID; spi_len = 8'd4; last_cs_pos = 30'h01234567; op_status = SPI_OP_BUSY; irq_flag = 1'b1; reset_req = 1'b0;
    symbols_in = '0; symbols_in = sym_set(symbols_in,0,1'b1,1'b0,8'hA5); symbols_in = sym_set(symbols_in,1,1'b0,1'b0,8'h5A);
    symbols_in = sym_set(symbols_in,2,1'b0,1'b1,8'h3C); symbols_in = sym_set(symbols_in,3,1'b1,1'b1,8'hC3);
    tx_frame_start=0; slot_ind=0; tx_build_cfg=0; tx_build_data=0; tx_build_irq=0; spi_stc=8'd2; tat_mult=8'd2; dcp_ticks=20'd3; rx_valid=0;
    rx_in_pkt='0; rx_in_pkt_len='0;
    pass_count=0; fail_count=0;

    tick(2); rst = 1'b0; tick(1);

    check("T1 pkt id reset", pkt_id == 7'd1);
    adv = 1'b1; tick(1); adv = 1'b0;
    check("T1 pkt id increment", pkt_id == 7'd2);

    repeat (119) begin adv = 1'b1; tick(1); adv = 1'b0; end
    check("T2 pkt id wraps 120->1", pkt_id == 7'd1);

    check("T3 irq count reset", irq_count == 8'd1);
    repeat (127) begin irq_adv = 1'b1; tick(1); irq_adv = 1'b0; end
    check("T3 irq wraps 127->1", irq_count == 8'd1);

    // T4 config write
    cfg_cmd = SPI_CFG_WRITE; #1;
    tb_byte = asep_get_byte(cfg_pkt,0);
    check("T4 stream type", tb_byte[7:1] == ASEP_STREAM_SPI);
    check("T4 cfg header", asep_get_byte(cfg_pkt,2) == 8'h01);
    tb_byte = asep_get_byte(cfg_pkt,3);
    check("T4 cfg mode", tb_byte[7:6] == SPI_CFG_WRITE);
    check("T4 cfg min idle", asep_get_byte(cfg_pkt,4) == 8'h55);
    tb_byte = asep_get_byte(cfg_pkt,5);
    check("T4 cfg sck hi", tb_byte[1:0] == 2'b01);
    check("T4 cfg sck lo", asep_get_byte(cfg_pkt,6) == 8'h23);

    // T5 config read shorter
    cfg_cmd = SPI_CFG_READ; #1;
    check("T5 cfg read len", cfg_len == 12'd8);

    // T6 data encode/decode
    enc_irq = 1'b0; #1;
    tb_byte = asep_get_byte(data_pkt,2);
    check("T6 data header", tb_byte[7] == 1'b1);
    check("T6 data len field", asep_get_byte(data_pkt,4) == 8'd4);
    check("T6 decode no crc", !dec_crc_err);
    check("T6 decode no fmt", !dec_fmt_err);
    check("T6 decode pkt id", dec_pkt_id == pkt_id);
    check("T6 decode csn", dec_csn == csn);
    check("T6 decode status", dec_pkt_status == pkt_status);
    check("T6 decode len", dec_spi_len == spi_len);
    check("T6 decode opstatus", dec_op_status == op_status);
    check("T6 sym0 data", spi_symbol_get(symbols_out,0).data == 8'hA5);
    check("T6 sym3 cs0", spi_symbol_get(symbols_out,3).cs0 == 1'b1);

    // T7 interrupt encode/decode
    enc_irq = 1'b1; reset_req = 1'b1; #1;
    tb_byte = asep_get_byte(data_pkt,2);
    check("T7 irq pkt id 127", tb_byte[6:0] == 7'd127);
    check("T7 irq decode flag", dec_is_irq);
    check("T7 irq decode count", dec_irq_count == irq_count);
    check("T7 irq decode reset", dec_reset);
    enc_irq = 1'b0; reset_req = 1'b0; #1;

    // T8 timers
    dcp_start = 1'b1; tick(1); dcp_start = 1'b0;
    check("T8 dcp active", dcp_active);
    repeat (3) begin ptb_tick = 1'b1; tick(1); ptb_tick = 1'b0; end
    check("T8 dcp expire", dcp_expire);
    tat_start = 1'b1; tick(1); tat_start = 1'b0;
    repeat (6) begin ptb_tick = 1'b1; tick(1); ptb_tick = 1'b0; end
    check("T8 tat expire", tat_expire);

    // T9 top cfg path
    cfg_cmd = SPI_CFG_WRITE; tx_build_cfg = 1'b1; tick(1); tx_build_cfg = 1'b0;
    check("T9 top tx cfg valid", tx_pkt_valid);
    rx_in_pkt = tx_pkt;
    rx_in_pkt_len = tx_pkt_len;
    rx_valid = 1'b1; tick(1);
    check("T9 top rx cfg seen", rx_cfg_seen);
    check("T9 top cfg shadow", rx_cfg_shadow[11:4] == 8'h23);
    rx_valid = 1'b0; tick(1);

    // T10 top data path
    tx_frame_start = 1'b1; tick(1); tx_frame_start = 1'b0;
    repeat (3) begin ptb_tick = 1'b1; tick(1); ptb_tick = 1'b0; end
    tx_build_data = 1'b1; tick(1); tx_build_data = 1'b0;
    check("T10 top tx data valid", tx_pkt_valid);
    rx_in_pkt = tx_pkt;
    rx_in_pkt_len = tx_pkt_len;
    rx_valid = 1'b1; tick(1);
    check("T10 top rx data seen", rx_data_seen);
    check("T10 top rx len", rx_spi_len == spi_len);
    check("T10 top rx sym2", spi_symbol_get(rx_symbols,2).data == 8'h3C);
    rx_valid = 1'b0; tick(1);

    // T11 pkt gap
    tx_build_data = 1'b1; tick(1); tx_build_data = 1'b0;
    rx_in_pkt = asep_set_byte(tx_pkt, 2, {1'b1, 7'd100});
    rx_in_pkt_len = tx_pkt_len;
    crc_fix = asep_crc32(rx_in_pkt, rx_in_pkt_len - 4);
    rx_in_pkt = asep_set_byte(rx_in_pkt, rx_in_pkt_len - 4, crc_fix[31:24]);
    rx_in_pkt = asep_set_byte(rx_in_pkt, rx_in_pkt_len - 3, crc_fix[23:16]);
    rx_in_pkt = asep_set_byte(rx_in_pkt, rx_in_pkt_len - 2, crc_fix[15:8]);
    rx_in_pkt = asep_set_byte(rx_in_pkt, rx_in_pkt_len - 1, crc_fix[7:0]);
    rx_valid = 1'b1; tick(1);
    check("T11 pkt gap", rx_gap);
    rx_valid = 1'b0; tick(1);

    // T12 CRC error
    rx_in_pkt = asep_set_byte(rx_in_pkt, rx_in_pkt_len - 1, 8'h00);
    rx_valid = 1'b1; tick(1);
    check("T12 crc err", rx_crc_err);
    rx_valid = 1'b0; tick(1);

    $display("asep_spi_tb: %0d passed, %0d failed", pass_count, fail_count);
    if (fail_count != 0) $fatal(1);
    $finish;
  end
endmodule

`default_nettype wire
