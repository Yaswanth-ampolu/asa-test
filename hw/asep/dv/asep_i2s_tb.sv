`timescale 1ns/1ps
`default_nettype none

module asep_i2s_tb;
  import asa_asep_pkg::*;
  import asa_i2s_asep_pkg::*;

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

  logic adv_id;
  logic [6:0] pkt_id;
  i2s_pkt_id_counter u_ctr(.clk(clk), .rst(rst), .soft_reset_i(soft_reset), .advance_i(adv_id), .pkt_id_o(pkt_id));

  logic cfg_enc, cfg_dec;
  logic [6:0] cfg_pkt_id_i, cfg_pkt_id_o;
  asep_ts_mode_e cfg_ts_mode;
  logic [31:0] cfg_ts_value;
  i2s_cfg_cmd_e cfg_cmd_i, cfg_cmd_o;
  logic cfg_ack_i, cfg_ack_o;
  i2s_bit_depth_e cfg_depth_i, cfg_depth_o;
  i2s_data_fmt_e cfg_fmt_i, cfg_fmt_o;
  logic [2:0] cfg_channels_i, cfg_channels_o;
  logic [4:0] cfg_rate_i, cfg_rate_o;
  logic cfg_host_i, cfg_host_o, cfg_clk_i, cfg_clk_o;
  logic [9:0] cfg_k_i, cfg_k_o;
  logic [15:0] cfg_n_i, cfg_n_o;
  asep_packet_t cfg_pkt_enc, cfg_pkt_dec;
  logic [11:0] cfg_len_enc, cfg_len_dec;
  logic cfg_seen, cfg_crc_err, cfg_fmt_err;

  i2s_cfg_codec u_cfg(
    .encode_i(cfg_enc), .decode_i(cfg_dec), .pkt_id_i(cfg_pkt_id_i), .ts_mode_i(cfg_ts_mode), .ts_value_i(cfg_ts_value),
    .cmd_i(cfg_cmd_i), .ack_ok_i(cfg_ack_i), .bit_depth_i(cfg_depth_i), .data_fmt_i(cfg_fmt_i), .num_channels_i(cfg_channels_i),
    .sample_rate_i(cfg_rate_i), .timing_host_rx_i(cfg_host_i), .target_clk_mck_i(cfg_clk_i), .coeff_k_i(cfg_k_i), .divisor_n_i(cfg_n_i),
    .packet_i(cfg_pkt_dec), .packet_len_i(cfg_len_dec), .packet_o(cfg_pkt_enc), .packet_len_o(cfg_len_enc), .seen_o(cfg_seen),
    .pkt_id_o(cfg_pkt_id_o), .cmd_o(cfg_cmd_o), .ack_ok_o(cfg_ack_o), .bit_depth_o(cfg_depth_o), .data_fmt_o(cfg_fmt_o),
    .num_channels_o(cfg_channels_o), .sample_rate_o(cfg_rate_o), .timing_host_rx_o(cfg_host_o), .target_clk_mck_o(cfg_clk_o),
    .coeff_k_o(cfg_k_o), .divisor_n_o(cfg_n_o), .crc_error_o(cfg_crc_err), .format_error_o(cfg_fmt_err)
  );

  logic data_enc, data_dec;
  logic [6:0] data_pkt_id_i, data_pkt_id_o;
  logic [23:0] start_stamp_i, start_stamp_o;
  logic ts_only_i, ts_only_o;
  logic [9:0] data_len_i, data_len_o;
  logic [8:0] word_count_i, word_count_o;
  i2s_word_vec_t words_i, words_o;
  asep_packet_t data_pkt_enc, data_pkt_dec;
  logic [11:0] data_len_enc, data_len_dec;
  logic data_seen, data_crc_err, data_fmt_err;

  i2s_data_codec u_data(
    .encode_i(data_enc), .decode_i(data_dec), .pkt_id_i(data_pkt_id_i), .ts_mode_i(cfg_ts_mode), .ts_value_i(cfg_ts_value),
    .start_ptb_stamp_i(start_stamp_i), .bit_depth_i(cfg_depth_i), .timestamps_only_i(ts_only_i), .data_len_i(data_len_i),
    .word_count_i(word_count_i), .words_i(words_i), .packet_i(data_pkt_dec), .packet_len_i(data_len_dec), .packet_o(data_pkt_enc),
    .packet_len_o(data_len_enc), .seen_o(data_seen), .pkt_id_o(data_pkt_id_o), .data_len_o(data_len_o), .start_ptb_stamp_o(start_stamp_o),
    .timestamps_only_o(ts_only_o), .word_count_o(word_count_o), .words_o(words_o), .crc_error_o(data_crc_err), .format_error_o(data_fmt_err)
  );

  logic [31:0] tb_word0, tb_word1;

  logic sync_edge, sync_cap, sync_delta_v;
  logic [23:0] sync_ptb, sync_cap_stamp, sync_delta;
  i2s_ptb_sync u_sync(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset), .clk_edge_i(sync_edge), .coeff_k_i(cfg_k_i), .divisor_n_i(cfg_n_i),
    .ptb_timestamp_i(sync_ptb), .rx_stamp_valid_i(data_seen), .rx_stamp_i(start_stamp_o), .capture_pulse_o(sync_cap),
    .captured_stamp_o(sync_cap_stamp), .delta_valid_o(sync_delta_v), .delta_ticks_o(sync_delta), .reconstructed_ratio_k_o(), .reconstructed_div_n_o()
  );

  logic top_tx_cfg, top_tx_data, top_rx_valid, top_rx_cfg_resp;
  asep_packet_t top_tx_pkt, top_rx_pkt;
  logic [11:0] top_tx_len, top_rx_len;
  logic [6:0] top_cfg_id, top_data_id, top_rx_cfg_id, top_rx_data_id;
  logic top_rx_cfg_seen, top_rx_data_seen, top_rx_cfg_ack, top_rx_cfg_crc, top_rx_data_crc, top_rx_cfg_gap, top_rx_data_gap;
  logic top_rx_cfg_fmt, top_rx_data_fmt, top_sync_cap, top_sync_dv;
  logic [23:0] top_sync_stamp, top_sync_delta;
  logic [8:0] top_rx_word_count;
  i2s_word_vec_t top_rx_words;
  i2s_cfg_cmd_e top_rx_cfg_cmd;
  i2s_bit_depth_e top_rx_depth;
  i2s_data_fmt_e top_rx_fmt;
  logic [2:0] top_rx_channels;
  logic [4:0] top_rx_rate;
  logic top_rx_host, top_rx_clk, top_rx_ts_only;
  logic [9:0] top_rx_k;
  logic [15:0] top_rx_n;
  logic [23:0] top_rx_start;

  i2s_asep_top u_top(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset), .tx_build_cfg_i(top_tx_cfg), .tx_build_data_i(top_tx_data),
    .tx_cfg_cmd_i(cfg_cmd_i), .tx_cfg_ack_ok_i(cfg_ack_i), .tx_ts_mode_i(cfg_ts_mode), .tx_ts_value_i(cfg_ts_value),
    .tx_bit_depth_i(cfg_depth_i), .tx_data_fmt_i(cfg_fmt_i), .tx_num_channels_i(cfg_channels_i), .tx_sample_rate_i(cfg_rate_i),
    .tx_timing_host_rx_i(cfg_host_i), .tx_target_clk_mck_i(cfg_clk_i), .tx_coeff_k_i(cfg_k_i), .tx_divisor_n_i(cfg_n_i),
    .tx_start_ptb_stamp_i(start_stamp_i), .tx_timestamps_only_i(ts_only_i), .tx_word_count_i(word_count_i), .tx_words_i(words_i),
    .sync_clk_edge_i(sync_edge), .sync_ptb_timestamp_i(sync_ptb), .rx_packet_valid_i(top_rx_valid), .rx_packet_i(top_rx_pkt),
    .rx_packet_len_i(top_rx_len), .rx_build_cfg_resp_i(top_rx_cfg_resp), .rx_cfg_resp_cmd_i(I2S_CFG_ACK), .rx_cfg_ack_ok_i(1'b1),
    .tx_packet_valid_o(), .tx_packet_o(top_tx_pkt), .tx_packet_len_o(top_tx_len), .tx_cfg_pkt_id_o(top_cfg_id), .tx_data_pkt_id_o(top_data_id),
    .rx_cfg_seen_o(top_rx_cfg_seen), .rx_data_seen_o(top_rx_data_seen), .rx_cfg_pkt_id_o(top_rx_cfg_id), .rx_data_pkt_id_o(top_rx_data_id),
    .rx_cfg_cmd_o(top_rx_cfg_cmd), .rx_cfg_ack_ok_o(top_rx_cfg_ack), .rx_bit_depth_o(top_rx_depth), .rx_data_fmt_o(top_rx_fmt),
    .rx_num_channels_o(top_rx_channels), .rx_sample_rate_o(top_rx_rate), .rx_timing_host_rx_o(top_rx_host), .rx_target_clk_mck_o(top_rx_clk),
    .rx_coeff_k_o(top_rx_k), .rx_divisor_n_o(top_rx_n), .rx_start_ptb_stamp_o(top_rx_start), .rx_timestamps_only_o(top_rx_ts_only),
    .rx_word_count_o(top_rx_word_count), .rx_words_o(top_rx_words), .rx_cfg_crc_error_o(top_rx_cfg_crc), .rx_data_crc_error_o(top_rx_data_crc),
    .rx_cfg_format_error_o(top_rx_cfg_fmt), .rx_data_format_error_o(top_rx_data_fmt), .rx_cfg_pkt_id_gap_o(top_rx_cfg_gap),
    .rx_data_pkt_id_gap_o(top_rx_data_gap), .sync_capture_pulse_o(top_sync_cap), .sync_captured_stamp_o(top_sync_stamp),
    .sync_delta_valid_o(top_sync_dv), .sync_delta_ticks_o(top_sync_delta)
  );

  initial begin
    clk = 0;
    rst = 1;
    soft_reset = 0;
    adv_id = 0;
    cfg_enc = 0; cfg_dec = 0; cfg_pkt_id_i = 7'd1; cfg_ts_mode = ASEP_TS_NONE; cfg_ts_value = 32'h0;
    cfg_cmd_i = I2S_CFG_WRITE; cfg_ack_i = 0; cfg_depth_i = I2S_DEPTH_24; cfg_fmt_i = I2S_FMT_I2S;
    cfg_channels_i = 3'd2; cfg_rate_i = 5'h09; cfg_host_i = 0; cfg_clk_i = 1; cfg_k_i = 10'd256; cfg_n_i = 16'd1024;
    data_enc = 0; data_dec = 0; data_pkt_id_i = 7'd1; start_stamp_i = 24'h123456; ts_only_i = 0; data_len_i = 0; word_count_i = 0; words_i = '0;
    sync_edge = 0; sync_ptb = 24'd0;
    top_tx_cfg = 0; top_tx_data = 0; top_rx_valid = 0; top_rx_pkt = '0; top_rx_len = '0; top_rx_cfg_resp = 0;
    pass_count = 0; fail_count = 0;

    tick(2); rst = 0; tick(1);

    check("T1 pkt id reset", pkt_id == 7'd1);
    adv_id = 1; tick(1); adv_id = 0;
    check("T1 pkt id incr", pkt_id == 7'd2);

    // T2 config write encode/decode
    cfg_enc = 1; #1;
    check("T2 cfg len", cfg_len_enc == 12'd14);
    cfg_pkt_dec = cfg_pkt_enc; cfg_len_dec = cfg_len_enc; cfg_enc = 0; cfg_dec = 1; #1;
    check("T2 cfg seen", cfg_seen);
    check("T2 cfg cmd", cfg_cmd_o == I2S_CFG_WRITE);
    check("T2 cfg depth", cfg_depth_o == I2S_DEPTH_24);
    check("T2 cfg fmt", cfg_fmt_o == I2S_FMT_I2S);
    check("T2 cfg ch", cfg_channels_o == 3'd2);
    check("T2 cfg rate", cfg_rate_o == 5'h09);
    check("T2 cfg host", cfg_host_o == 1'b0);
    check("T2 cfg clk", cfg_clk_o == 1'b1);
    check("T2 cfg k", cfg_k_o == 10'd256);
    check("T2 cfg n", cfg_n_o == 16'd1024);
    cfg_dec = 0;

    // T3 config read no payload
    cfg_cmd_i = I2S_CFG_READ; cfg_enc = 1; #1;
    check("T3 cfg read len", cfg_len_enc == 12'd8);
    cfg_pkt_dec = cfg_pkt_enc; cfg_len_dec = cfg_len_enc; cfg_enc = 0; cfg_dec = 1; #1;
    check("T3 cfg read seen", cfg_seen);
    check("T3 cfg read cmd", cfg_cmd_o == I2S_CFG_READ);
    cfg_dec = 0;

    // T4 data 24-bit stereo
    cfg_depth_i = I2S_DEPTH_24;
    word_count_i = 9'd2;
    words_i = i2s_word_set('0, 0, 32'h00112233);
    words_i = i2s_word_set(words_i, 1, 32'h00445566);
    data_len_i = word_count_i * i2s_bytes_per_word(cfg_depth_i);
    data_enc = 1; #1;
    check("T4 data len", data_len_enc == 12'd18);
    data_pkt_dec = data_pkt_enc; data_len_dec = data_len_enc; data_enc = 0; data_dec = 1; #1;
    check("T4 data seen", data_seen);
    check("T4 data pid", data_pkt_id_o == 7'd1);
    check("T4 start stamp", start_stamp_o == 24'h123456);
    tb_word0 = i2s_word_get(words_o, 0);
    tb_word1 = i2s_word_get(words_o, 1);
    check("T4 words", tb_word0 == 32'h00112233 && tb_word1 == 32'h00445566);
    data_dec = 0;

    // T5 12-bit packing
    cfg_depth_i = I2S_DEPTH_12;
    word_count_i = 9'd1;
    words_i = i2s_word_set('0, 0, 32'h00000ABC);
    data_len_i = 10'd2;
    data_enc = 1; #1;
    data_pkt_dec = data_pkt_enc; data_len_dec = data_len_enc; data_enc = 0; data_dec = 1; #1;
    tb_word0 = i2s_word_get(words_o, 0);
    check("T5 12bit word", tb_word0[11:0] == 12'hABC);
    data_dec = 0;

    // T6 timestamps-only RX host packet
    cfg_depth_i = I2S_DEPTH_16;
    word_count_i = 9'd0;
    words_i = '0;
    data_len_i = 10'd0;
    ts_only_i = 1;
    data_enc = 1; #1;
    data_pkt_dec = data_pkt_enc; data_len_dec = data_len_enc; data_enc = 0; data_dec = 1; #1;
    check("T6 ts only", ts_only_o && word_count_o == 0);
    data_dec = 0; ts_only_i = 0;

    // T7 crc error
    cfg_cmd_i = I2S_CFG_WRITE; cfg_enc = 1; #1; cfg_enc = 0;
    cfg_pkt_dec = cfg_pkt_enc; cfg_len_dec = cfg_len_enc;
    cfg_pkt_dec = asep_set_byte(cfg_pkt_dec, cfg_len_dec - 1, 8'h00);
    cfg_dec = 1; #1;
    check("T7 cfg crc err", cfg_crc_err);
    cfg_dec = 0;

    // T8 ptb sync capture after N edges
    cfg_n_i = 16'd4;
    sync_ptb = 24'h000100;
    repeat (3) begin sync_edge = 1; tick(1); sync_edge = 0; end
    check("T8 no capture early", !sync_cap);
    sync_edge = 1; tick(1); sync_edge = 0;
    check("T8 capture", sync_cap && sync_cap_stamp == 24'h000100);

    // T9 ptb delta from successive data stamps
    cfg_depth_i = I2S_DEPTH_16;
    word_count_i = 9'd0;
    data_len_i = 10'd0;
    ts_only_i = 1;
    start_stamp_i = 24'd100; data_enc = 1; #1; data_pkt_dec = data_pkt_enc; data_len_dec = data_len_enc; data_enc = 0; data_dec = 1; tick(1); data_dec = 0;
    start_stamp_i = 24'd140; data_enc = 1; #1; data_pkt_dec = data_pkt_enc; data_len_dec = data_len_enc; data_enc = 0; data_dec = 1; tick(1); data_dec = 0;
    check("T9 delta valid", sync_delta_v && sync_delta == 24'd40);
    ts_only_i = 0;

    // T10 top cfg then cfg gap detection
    cfg_depth_i = I2S_DEPTH_24; cfg_fmt_i = I2S_FMT_LEFT_J; cfg_channels_i = 3'd4; cfg_rate_i = 5'h0E; cfg_host_i = 1; cfg_clk_i = 0; cfg_k_i = 10'd64; cfg_n_i = 16'd512;
    top_tx_cfg = 1; #1; top_rx_pkt = top_tx_pkt; top_rx_len = top_tx_len; tick(1); top_tx_cfg = 0; top_rx_valid = 1; tick(1); top_rx_valid = 0;
    check("T10 top cfg seen", top_rx_cfg_seen);
    check("T10 top cfg shadow", top_rx_depth == I2S_DEPTH_24 && top_rx_fmt == I2S_FMT_LEFT_J && top_rx_channels == 3'd4);
    cfg_pkt_id_i = 7'd5;
    cfg_enc = 1; #1; cfg_enc = 0;
    top_rx_pkt = cfg_pkt_enc; top_rx_len = cfg_len_enc; top_rx_valid = 1; tick(1); top_rx_valid = 0;
    check("T10 top cfg gap", top_rx_cfg_gap);
    cfg_pkt_id_i = 7'd1;

    // T11 top data path
    word_count_i = 9'd2;
    words_i = i2s_word_set('0, 0, 32'h00001234);
    words_i = i2s_word_set(words_i, 1, 32'h00005678);
    start_stamp_i = 24'h0A0B0C;
    top_tx_data = 1; #1; top_rx_pkt = top_tx_pkt; top_rx_len = top_tx_len; tick(1); top_tx_data = 0; top_rx_valid = 1; tick(1); top_rx_valid = 0;
    check("T11 top data seen", top_rx_data_seen);
    tb_word0 = i2s_word_get(top_rx_words, 0);
    tb_word1 = i2s_word_get(top_rx_words, 1);
    check("T11 top data words", tb_word0[15:0] == 16'h1234 && tb_word1[15:0] == 16'h5678);
    check("T11 top start stamp", top_rx_start == 24'h0A0B0C);

    // T12 top cfg response generation
    top_rx_cfg_resp = 1; tick(1); top_rx_cfg_resp = 0;
    check("T12 top cfg resp built", u_top.u_rx.tx_packet_valid_o && u_top.u_rx.tx_packet_len_o != 0);

    if (fail_count == 0) $display("asep_i2s_tb: %0d passed, 0 failed", pass_count);
    else $display("asep_i2s_tb: %0d passed, %0d failed", pass_count, fail_count);
    $finish;
  end
endmodule

`default_nettype wire
