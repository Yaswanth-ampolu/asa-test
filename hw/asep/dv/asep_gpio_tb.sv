`timescale 1ns/1ps
`default_nettype none

module asep_gpio_tb;
  import asa_asep_pkg::*;
  import asa_gpio_asep_pkg::*;

  logic clk, rst, soft_reset;
  initial begin clk = 1'b0; forever #5 clk = ~clk; end

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

  // Packet ID counter
  logic pkt_adv;
  logic [6:0] pkt_id;

  gpio_pkt_id_counter u_ctr (
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset), .advance_i(pkt_adv), .pkt_id_o(pkt_id)
  );

  // Config codec
  logic cfg_mode2, cfg_ack_ok;
  gpio_cfg_cmd_e cfg_cmd;
  asep_ts_mode_e cfg_ts_mode;
  logic [31:0] cfg_ts_value;
  logic [12:0] cfg_sampling_period;
  logic cfg_sampling_mode_eg;
  logic [15:0] pin_avail, pin_dir, pin_enable, pin_select_mask;
  logic [47:0] pin_default;
  logic [31:0] pin_drv_mode;
  logic [3:0] pin_count;
  asep_packet_t cfg_packet;
  logic [11:0] cfg_packet_len;

  gpio_cfg_codec u_cfg (
    .mode2_i(cfg_mode2), .cmd_i(cfg_cmd), .ack_ok_i(cfg_ack_ok), .pkt_id_i(pkt_id),
    .ts_mode_i(cfg_ts_mode), .ts_value_i(cfg_ts_value),
    .sampling_period_i(cfg_sampling_period), .sampling_mode_eg_i(cfg_sampling_mode_eg),
    .pin_avail_i(pin_avail), .pin_dir_i(pin_dir), .pin_enable_i(pin_enable),
    .pin_default_i(pin_default), .pin_drv_mode_i(pin_drv_mode),
    .pin_count_i(pin_count), .pin_select_mask_i(pin_select_mask),
    .packet_o(cfg_packet), .packet_len_o(cfg_packet_len)
  );

  // FS codec
  logic [15:0] fs_active_mask;
  logic [9:0] fs_sample_count_i, fs_sample_count_o;
  gpio_sample_vec_t fs_samples_i, fs_samples_o;
  asep_packet_t fs_payload;
  logic [10:0] fs_payload_len;
  logic fs_err;

  gpio_fs_codec u_fs_enc (
    .encode_i(1'b1), .decode_i(1'b0), .active_mask_i(fs_active_mask),
    .sample_count_i(fs_sample_count_i), .samples_i(fs_samples_i),
    .payload_i('0), .payload_len_i('0),
    .payload_o(fs_payload), .payload_len_o(fs_payload_len),
    .samples_o(), .sample_count_o(), .error_o(fs_err)
  );

  gpio_fs_codec u_fs_dec (
    .encode_i(1'b0), .decode_i(1'b1), .active_mask_i(fs_active_mask),
    .sample_count_i('0), .samples_i('0),
    .payload_i(fs_payload), .payload_len_i(fs_payload_len),
    .payload_o(), .payload_len_o(),
    .samples_o(fs_samples_o), .sample_count_o(fs_sample_count_o), .error_o()
  );

  // EG codec
  logic [9:0] eg_edge_count_i, eg_edge_count_o;
  gpio_edge_vec_t eg_edges_i, eg_edges_o;
  asep_packet_t eg_payload;
  logic [10:0] eg_payload_len;
  logic eg_err;

  gpio_eg_codec u_eg_enc (
    .encode_i(1'b1), .decode_i(1'b0), .edge_count_i(eg_edge_count_i), .edges_i(eg_edges_i),
    .payload_i('0), .payload_len_i('0),
    .payload_o(eg_payload), .payload_len_o(eg_payload_len), .edges_o(), .edge_count_o(), .error_o(eg_err)
  );

  gpio_eg_codec u_eg_dec (
    .encode_i(1'b0), .decode_i(1'b1), .edge_count_i('0), .edges_i('0),
    .payload_i(eg_payload), .payload_len_i(eg_payload_len),
    .payload_o(), .payload_len_o(), .edges_o(eg_edges_o), .edge_count_o(eg_edge_count_o), .error_o()
  );

  // RX parser
  logic rx_valid;
  asep_packet_t rx_packet;
  logic [11:0] rx_packet_len;
  logic [12:0] rx_sampling_period;
  logic rx_sampling_mode_eg;
  logic [15:0] rx_pin_dir, rx_pin_enable, gpio_pin_out;
  logic [47:0] rx_pin_default;
  logic [31:0] rx_pin_drv_mode;
  logic cfg_seen, data_seen, cfg_mode2_seen;
  gpio_cfg_cmd_e cfg_cmd_seen;
  logic crc_error, pkt_gap, fmt_error;

  gpio_asd_rx u_rx (
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset), .rx_valid_i(rx_valid),
    .rx_packet_i(rx_packet), .rx_packet_len_i(rx_packet_len), .pin_avail_i(pin_avail),
    .sampling_period_o(rx_sampling_period), .sampling_mode_eg_o(rx_sampling_mode_eg),
    .pin_dir_o(rx_pin_dir), .pin_enable_o(rx_pin_enable), .pin_default_o(rx_pin_default),
    .pin_drv_mode_o(rx_pin_drv_mode), .gpio_pin_out_o(gpio_pin_out),
    .cfg_packet_seen_o(cfg_seen), .data_packet_seen_o(data_seen), .cfg_mode2_o(cfg_mode2_seen),
    .cfg_cmd_o(cfg_cmd_seen), .crc_error_o(crc_error), .pkt_id_gap_o(pkt_gap), .format_error_o(fmt_error)
  );

  function automatic asep_packet_t set_fs_sample(input gpio_sample_vec_t cur, input int idx, input logic [15:0] v);
    return gpio_sample_set(cur, idx, v);
  endfunction

  function automatic asep_packet_t build_data_pkt(
    input logic eg_mode,
    input logic [6:0] pkt_id_f,
    input logic [15:0] active_mask,
    input logic [9:0] data_len,
    input asep_packet_t payload,
    input logic [10:0] payload_len
  );
    asep_packet_t pkt;
    logic [31:0] crc;
    int idx;
    pkt = '0;
    pkt = asep_set_byte(pkt, 0, asep_hdr_byte0(ASEP_STREAM_GPIO, 1'b0));
    pkt = asep_set_byte(pkt, 1, asep_hdr_byte1(ASEP_TS_NONE));
    pkt = asep_set_byte(pkt, 2, gpio_pkt_header_byte(1'b1, pkt_id_f));
    pkt = asep_set_byte(pkt, 3, {eg_mode, 5'd0, data_len[9:8]});
    pkt = asep_set_byte(pkt, 4, data_len[7:0]);
    pkt = asep_set_byte(pkt, 5, active_mask[15:8]);
    pkt = asep_set_byte(pkt, 6, active_mask[7:0]);
    idx = 7;
    for (int i = 0; i < payload_len; i++) pkt = asep_set_byte(pkt, idx+i, asep_get_byte(payload, i));
    idx += payload_len;
    crc = asep_crc32(pkt, idx);
    pkt = asep_set_byte(pkt, idx+0, crc[31:24]);
    pkt = asep_set_byte(pkt, idx+1, crc[23:16]);
    pkt = asep_set_byte(pkt, idx+2, crc[15:8]);
    pkt = asep_set_byte(pkt, idx+3, crc[7:0]);
    return pkt;
  endfunction

  initial begin
    logic [7:0] b;
    logic [9:0] cnt10;
    gpio_edge_t eg_item;
    asep_packet_t data_pkt, cfg_packet_m1, cfg_packet_m2;
    logic [11:0] cfg_len_m1, cfg_len_m2;
    logic [31:0] crc_fix;
    logic [15:0] sample_tmp;

    rst = 1'b1;
    soft_reset = 1'b0;
    pkt_adv = 1'b0;
    cfg_mode2 = 1'b0;
    cfg_ack_ok = 1'b1;
    cfg_cmd = GPIO_CFG_WRITE;
    cfg_ts_mode = ASEP_TS_NONE;
    cfg_ts_value = 32'd0;
    cfg_sampling_period = 13'd0;
    cfg_sampling_mode_eg = 1'b0;
    pin_avail = 16'hFFFF;
    pin_dir = 16'h0000;
    pin_enable = 16'h0000;
    pin_select_mask = 16'h0000;
    pin_default = '0;
    pin_drv_mode = '0;
    pin_count = 4'd0;
    fs_active_mask = 16'h0000;
    fs_sample_count_i = 10'd0;
    fs_samples_i = '0;
    eg_edge_count_i = 10'd0;
    eg_edges_i = '0;
    rx_valid = 1'b0;
    rx_packet = '0;
    rx_packet_len = '0;
    pass_count = 0;
    fail_count = 0;

    tick(2);
    rst = 1'b0;
    tick(1);

    // T1: packet counter
    check("T1 pkt id reset", pkt_id == 7'd1);
    pkt_adv = 1'b1; tick(1); pkt_adv = 1'b0;
    check("T1 pkt id increment", pkt_id == 7'd2);

    // T2: Mode1 config packet
    pin_dir[0] = 1'b1;
    pin_enable[0] = 1'b1;
    pin_default[0 +: 3] = 3'b010;
    pin_drv_mode[0 +: 2] = 2'b01;
    pin_enable[2] = 1'b1;
    pin_select_mask = 16'h0005;
    pin_count = 4'd2;
    cfg_mode2 = 1'b0;
    #1;
    b = asep_get_byte(cfg_packet, 0);
    check("T2 stream type", b[7:1] == ASEP_STREAM_GPIO);
    check("T2 cfg header", asep_get_byte(cfg_packet, 2) == 8'h02);
    check("T2 cfg cmd", asep_get_byte(cfg_packet, 3) == 8'h02);
    check("T2 pin0 cfg", asep_get_byte(cfg_packet, 5) == 8'h53);
    cfg_packet_m1 = cfg_packet;
    cfg_len_m1 = cfg_packet_len;

    // T3: Mode2 config packet
    cfg_mode2 = 1'b1;
    cfg_sampling_period = 13'd23;
    cfg_sampling_mode_eg = 1'b1;
    #1;
    check("T3 mode2 cmd", asep_get_byte(cfg_packet, 3) == 8'h80);
    b = asep_get_byte(cfg_packet, 5);
    check("T3 mode2 eg bit", b[7] == 1'b1);
    cfg_packet_m2 = cfg_packet;
    cfg_len_m2 = cfg_packet_len;

    // T4: FS 1-pin encode/decode
    fs_active_mask = 16'h0001;
    fs_sample_count_i = 10'd8;
    for (int i = 0; i < 8; i++) fs_samples_i = gpio_sample_set(fs_samples_i, i, {15'd0, i[0]});
    #1;
    check("T4 fs payload len", fs_payload_len == 11'd1);
    check("T4 fs payload", asep_get_byte(fs_payload, 0) == 8'h55);
    check("T4 fs decode count", fs_sample_count_o == 10'd8);
    sample_tmp = gpio_sample_get(fs_samples_o, 7);
    check("T4 fs decode sample7", sample_tmp[0] == 1'b1);

    // T5: EG encode/decode
    eg_item.initial_state = 1'b0;
    eg_item.pin_id = 4'd0;
    eg_item.section = 6'd0;
    eg_item.position = 13'd0;
    eg_edges_i = gpio_edge_set(eg_edges_i, 0, eg_item);
    eg_item.initial_state = 1'b1;
    eg_item.position = 13'd4;
    eg_edges_i = gpio_edge_set(eg_edges_i, 1, eg_item);
    eg_edge_count_i = 10'd2;
    #1;
    check("T5 eg payload len", eg_payload_len == 11'd6);
    b = asep_get_byte(eg_payload, 0);
    check("T5 eg first pin", b[6:3] == 4'd0);
    check("T5 eg decode count", eg_edge_count_o == 10'd2);
    eg_item = gpio_edge_get(eg_edges_o, 1);
    check("T5 eg decode pos", eg_item.position == 13'd4);

    // T6: RX mode1 config apply
    rx_packet = cfg_packet_m1;
    rx_packet_len = cfg_len_m1;
    rx_valid = 1'b1;
    tick(1);
    check("T6 cfg seen", cfg_seen);
    check("T6 rx dir", rx_pin_dir[0] == 1'b1);
    check("T6 rx enable", rx_pin_enable[2] == 1'b1);
    rx_valid = 1'b0;
    tick(1);

    // T7: RX mode2 config apply
    cfg_mode2 = 1'b1;
    rx_packet = cfg_packet_m2;
    rx_packet_len = cfg_len_m2;
    rx_valid = 1'b1;
    tick(1);
    check("T7 cfg mode2 seen", cfg_mode2_seen);
    check("T7 rx sample period", rx_sampling_period == 13'd23);
    check("T7 rx eg mode", rx_sampling_mode_eg == 1'b1);
    rx_valid = 1'b0;
    tick(1);

    // T8: RX FS data packet
    data_pkt = build_data_pkt(1'b0, 7'd10, fs_active_mask, 10'd8, fs_payload, fs_payload_len);
    rx_packet = data_pkt;
    rx_packet_len = 12'(7 + fs_payload_len + 4);
    rx_valid = 1'b1;
    tick(1);
    check("T8 data seen", data_seen);
    check("T8 gpio out fs", gpio_pin_out[0] == 1'b1);
    rx_valid = 1'b0;
    tick(1);

    // T9: RX EG data packet
    data_pkt = build_data_pkt(1'b1, 7'd11, 16'h0001, 10'd2, eg_payload, eg_payload_len);
    rx_packet = data_pkt;
    rx_packet_len = 12'(7 + eg_payload_len + 4);
    rx_valid = 1'b1;
    tick(1);
    check("T9 gpio out eg", gpio_pin_out[0] == 1'b0);
    rx_valid = 1'b0;
    tick(1);

    // T10: packet ID gap detection with valid CRC
    rx_packet = data_pkt;
    rx_packet = asep_set_byte(rx_packet, 2, gpio_pkt_header_byte(1'b1, 7'd100));
    crc_fix = asep_crc32(rx_packet, rx_packet_len - 4);
    rx_packet = asep_set_byte(rx_packet, rx_packet_len - 4, crc_fix[31:24]);
    rx_packet = asep_set_byte(rx_packet, rx_packet_len - 3, crc_fix[23:16]);
    rx_packet = asep_set_byte(rx_packet, rx_packet_len - 2, crc_fix[15:8]);
    rx_packet = asep_set_byte(rx_packet, rx_packet_len - 1, crc_fix[7:0]);
    rx_valid = 1'b1;
    tick(1);
    check("T10 pkt gap", pkt_gap);
    rx_valid = 1'b0;
    tick(1);

    $display("asep_gpio_tb: %0d passed, %0d failed", pass_count, fail_count);
    if (fail_count != 0) $fatal(1);
    $finish;
  end

endmodule

`default_nettype wire
