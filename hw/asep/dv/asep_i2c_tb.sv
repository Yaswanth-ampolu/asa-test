`timescale 1ns/1ps
`default_nettype none

module asep_i2c_tb;
  import asa_asep_pkg::*;
  import asa_i2c_asep_pkg::*;

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

  logic alloc;
  logic [7:0] cmd_id;
  i2c_cmd_id_mgr u_ctr(.clk(clk), .rst(rst), .soft_reset_i(soft_reset), .alloc_i(alloc), .cmd_id_o(cmd_id));

  logic [5:0] cfg_clk_rate;
  logic [3:0] cfg_addr_count;
  i2c_addr_cfg_vec_t cfg_entries;

  logic byte_enc, byte_dec;
  logic byte_start, byte_stop, byte_ack, byte_nack, byte_dv, byte_err;
  logic [7:0] byte_data;
  asep_packet_t byte_pkt_enc, byte_pkt_dec;
  logic [11:0] byte_pkt_len_enc, byte_pkt_len_dec;
  logic byte_seen, byte_fmt_err, dec_byte_start, dec_byte_stop, dec_byte_ack, dec_byte_nack, dec_byte_dv, dec_byte_err;
  logic [7:0] dec_byte_cmd_id, dec_byte_data;

  i2c_byte_codec u_byte(
    .encode_i(byte_enc), .decode_i(byte_dec), .cmd_id_i(cmd_id), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0),
    .i2c_error_i(byte_err), .start_i(byte_start), .stop_i(byte_stop), .ack_i(byte_ack), .nack_i(byte_nack), .data_valid_i(byte_dv), .data_i(byte_data),
    .packet_i(byte_pkt_dec), .packet_len_i(byte_pkt_len_dec), .packet_o(byte_pkt_enc), .packet_len_o(byte_pkt_len_enc), .seen_o(byte_seen), .cmd_id_o(dec_byte_cmd_id),
    .i2c_error_o(dec_byte_err), .start_o(dec_byte_start), .stop_o(dec_byte_stop), .ack_o(dec_byte_ack), .nack_o(dec_byte_nack),
    .data_valid_o(dec_byte_dv), .data_o(dec_byte_data), .format_error_o(byte_fmt_err)
  );

  logic bulk_enc, bulk_dec;
  logic bulk_cur_loc, bulk_off16, bulk_err;
  logic [6:0] bulk_slave, dec_bulk_slave;
  logic [15:0] bulk_offs, bulk_len, dec_bulk_offs, dec_bulk_len;
  i2c_bulk_fmt_e bulk_fmt, dec_bulk_fmt;
  asep_packet_t bulk_payload, bulk_pkt_enc, bulk_pkt_dec, dec_bulk_payload;
  logic [(ASEP_MAX_PACKET_BYTES*8)-1:0] ack_payload, dec_ack_payload;
  logic [11:0] bulk_pkt_len_enc, bulk_pkt_len_dec;
  logic bulk_seen, bulk_crc_err, bulk_fmt_err, dec_bulk_cur, dec_bulk_err;
  logic [7:0] dec_bulk_cmd_id;

  i2c_bulk_codec u_bulk(
    .encode_i(bulk_enc), .decode_i(bulk_dec), .cmd_id_i(cmd_id), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0),
    .i2c_error_i(bulk_err), .current_loc_i(bulk_cur_loc), .fmt_i(bulk_fmt), .slave_addr_i(bulk_slave), .offset_addr_i(bulk_offs),
    .length_i(bulk_len), .offset_16b_i(bulk_off16), .payload_i(bulk_payload), .ack_payload_i(ack_payload),
    .packet_i(bulk_pkt_dec), .packet_len_i(bulk_pkt_len_dec), .packet_o(bulk_pkt_enc), .packet_len_o(bulk_pkt_len_enc), .seen_o(bulk_seen),
    .cmd_id_o(dec_bulk_cmd_id), .i2c_error_o(dec_bulk_err), .current_loc_o(dec_bulk_cur), .fmt_o(dec_bulk_fmt), .slave_addr_o(dec_bulk_slave),
    .offset_addr_o(dec_bulk_offs), .length_o(dec_bulk_len), .payload_o(dec_bulk_payload), .ack_payload_o(dec_ack_payload),
    .crc_error_o(bulk_crc_err), .format_error_o(bulk_fmt_err)
  );

  logic cfg_enc, cfg_dec, cfg_ack_ok, dec_cfg_ack_ok, cfg_crc_err, cfg_fmt_err, cfg_seen, dec_cfg_err;
  i2c_cfg_cmd_e cfg_cmd, dec_cfg_cmd;
  asep_packet_t cfg_pkt_enc, cfg_pkt_dec;
  logic [11:0] cfg_pkt_len_enc, cfg_pkt_len_dec;
  logic [7:0] dec_cfg_cmd_id;
  logic [3:0] dec_cfg_count;
  logic [5:0] dec_cfg_clk;
  i2c_addr_cfg_vec_t dec_cfg_entries;

  i2c_cfg_codec u_cfg(
    .encode_i(cfg_enc), .decode_i(cfg_dec), .cmd_id_i(cmd_id), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0), .i2c_error_i(1'b0),
    .cmd_i(cfg_cmd), .addr_count_i(cfg_addr_count), .clock_rate_i(cfg_clk_rate), .addr_cfg_i(cfg_entries), .ack_ok_i(cfg_ack_ok),
    .packet_i(cfg_pkt_dec), .packet_len_i(cfg_pkt_len_dec), .packet_o(cfg_pkt_enc), .packet_len_o(cfg_pkt_len_enc), .seen_o(cfg_seen), .cmd_id_o(dec_cfg_cmd_id),
    .i2c_error_o(dec_cfg_err), .cmd_o(dec_cfg_cmd), .addr_count_o(dec_cfg_count), .clock_rate_o(dec_cfg_clk), .addr_cfg_o(dec_cfg_entries),
    .ack_ok_o(dec_cfg_ack_ok), .crc_error_o(cfg_crc_err), .format_error_o(cfg_fmt_err)
  );

  logic startup_sync, cfg_reg_wr;
  logic tx_build_byte, tx_build_bulk_wr, tx_build_bulk_rd, tx_build_cfg_wr, tx_build_cfg_rd;
  logic [15:0] watchdog_cycles;
  logic root_rx_valid;
  asep_packet_t root_rx_pkt;
  logic [11:0] root_rx_pkt_len;
  logic root_tx_valid, root_pending, root_timeout, root_resp_bulk_ack_seen, root_resp_bulk_read_seen, root_resp_cfg_ack_seen, root_resp_cfg_read_seen;
  logic [7:0] root_tx_cmd_id, root_resp_cmd_id;
  logic root_resp_ack_ok, root_resp_crc_err, root_resp_fmt_err;
  logic [15:0] root_resp_len;
  logic [(ASEP_MAX_PACKET_BYTES*8)-1:0] root_resp_ack_payload;
  asep_packet_t root_resp_rdata;
  logic [5:0] root_resp_cfg_clk;
  i2c_addr_cfg_vec_t root_resp_cfg_entries;
  asep_packet_t root_tx_pkt, asd_tx_pkt;
  logic [11:0] root_tx_pkt_len, asd_tx_pkt_len;
  logic asd_rx_valid, asd_tx_valid;
  asep_packet_t asd_rx_pkt;
  logic [11:0] asd_rx_pkt_len;
  logic asd_resp_bulk_ack_valid, asd_resp_bulk_read_valid, asd_resp_cfg_ack_valid, asd_resp_cfg_read_valid, asd_resp_cfg_ack_ok;
  logic [15:0] asd_resp_bulk_ack_len, asd_resp_bulk_read_len;
  logic [(ASEP_MAX_PACKET_BYTES*8)-1:0] asd_resp_bulk_ack_payload;
  asep_packet_t asd_resp_bulk_rdata;
  logic [5:0] asd_resp_cfg_clk;
  logic [3:0] asd_resp_cfg_count;
  i2c_addr_cfg_vec_t asd_resp_cfg_entries;
  logic asd_req_byte_seen, asd_req_bulk_write_seen, asd_req_bulk_read_seen, asd_req_cfg_write_seen, asd_req_cfg_read_seen;
  logic [7:0] asd_req_cmd_id, asd_req_byte_data;
  logic asd_req_i2c_err, asd_req_byte_start, asd_req_byte_stop, asd_req_byte_ack, asd_req_byte_nack, asd_req_byte_dv;
  logic asd_req_bulk_cur;
  logic [6:0] asd_req_bulk_slave;
  logic [15:0] asd_req_bulk_offs, asd_req_bulk_len;
  asep_packet_t asd_req_bulk_wdata;
  logic [5:0] asd_req_cfg_clk;
  logic [3:0] asd_req_cfg_count;
  i2c_addr_cfg_vec_t asd_req_cfg_entries;
  logic asd_req_crc_err, asd_req_fmt_err;

  i2c_asep_top u_top(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset), .startup_sync_i(startup_sync), .cfg_reg_write_i(cfg_reg_wr),
    .root_tx_build_byte_i(tx_build_byte), .root_tx_build_bulk_write_i(tx_build_bulk_wr), .root_tx_build_bulk_read_i(tx_build_bulk_rd),
    .root_tx_build_cfg_write_i(tx_build_cfg_wr), .root_tx_build_cfg_read_i(tx_build_cfg_rd), .root_ts_mode_i(ASEP_TS_NONE), .root_ts_value_i('0),
    .root_i2c_error_i(1'b0), .root_byte_start_i(byte_start), .root_byte_stop_i(byte_stop), .root_byte_ack_i(byte_ack), .root_byte_nack_i(byte_nack),
    .root_byte_data_valid_i(byte_dv), .root_byte_data_i(byte_data), .root_bulk_current_loc_i(bulk_cur_loc), .root_bulk_offset_16b_i(bulk_off16),
    .root_bulk_slave_addr_i(bulk_slave), .root_bulk_offset_addr_i(bulk_offs), .root_bulk_len_i(bulk_len), .root_bulk_wdata_i(bulk_payload),
    .root_cfg_clock_rate_i(cfg_clk_rate), .root_cfg_addr_count_i(cfg_addr_count), .root_cfg_addr_cfg_i(cfg_entries), .watchdog_cycles_i(watchdog_cycles),
    .root_rx_packet_valid_i(root_rx_valid), .root_rx_packet_i(root_rx_pkt), .root_rx_packet_len_i(root_rx_pkt_len),
    .root_tx_packet_valid_o(root_tx_valid), .root_tx_packet_o(root_tx_pkt), .root_tx_packet_len_o(root_tx_pkt_len), .root_tx_cmd_id_o(root_tx_cmd_id),
    .root_pending_o(root_pending), .root_timeout_o(root_timeout), .root_resp_bulk_ack_seen_o(root_resp_bulk_ack_seen),
    .root_resp_bulk_read_seen_o(root_resp_bulk_read_seen), .root_resp_cfg_ack_seen_o(root_resp_cfg_ack_seen), .root_resp_cfg_read_seen_o(root_resp_cfg_read_seen),
    .root_resp_cmd_id_o(root_resp_cmd_id), .root_resp_ack_ok_o(root_resp_ack_ok), .root_resp_length_o(root_resp_len),
    .root_resp_ack_payload_o(root_resp_ack_payload), .root_resp_rdata_o(root_resp_rdata), .root_resp_cfg_clock_rate_o(root_resp_cfg_clk),
    .root_resp_cfg_addr_cfg_o(root_resp_cfg_entries), .root_resp_crc_error_o(root_resp_crc_err), .root_resp_format_error_o(root_resp_fmt_err),
    .asd_rx_packet_valid_i(asd_rx_valid), .asd_rx_packet_i(asd_rx_pkt), .asd_rx_packet_len_i(asd_rx_pkt_len),
    .asd_resp_bulk_ack_valid_i(asd_resp_bulk_ack_valid), .asd_resp_bulk_ack_len_i(asd_resp_bulk_ack_len), .asd_resp_bulk_ack_payload_i(asd_resp_bulk_ack_payload),
    .asd_resp_bulk_read_valid_i(asd_resp_bulk_read_valid), .asd_resp_bulk_read_len_i(asd_resp_bulk_read_len), .asd_resp_bulk_rdata_i(asd_resp_bulk_rdata),
    .asd_resp_cfg_ack_valid_i(asd_resp_cfg_ack_valid), .asd_resp_cfg_ack_ok_i(asd_resp_cfg_ack_ok), .asd_resp_cfg_read_valid_i(asd_resp_cfg_read_valid),
    .asd_resp_cfg_clock_rate_i(asd_resp_cfg_clk), .asd_resp_cfg_addr_count_i(asd_resp_cfg_count), .asd_resp_cfg_addr_cfg_i(asd_resp_cfg_entries),
    .asd_tx_packet_valid_o(asd_tx_valid), .asd_tx_packet_o(asd_tx_pkt), .asd_tx_packet_len_o(asd_tx_pkt_len),
    .asd_req_byte_seen_o(asd_req_byte_seen), .asd_req_bulk_write_seen_o(asd_req_bulk_write_seen), .asd_req_bulk_read_seen_o(asd_req_bulk_read_seen),
    .asd_req_cfg_write_seen_o(asd_req_cfg_write_seen), .asd_req_cfg_read_seen_o(asd_req_cfg_read_seen), .asd_req_cmd_id_o(asd_req_cmd_id),
    .asd_req_i2c_error_o(asd_req_i2c_err), .asd_req_byte_start_o(asd_req_byte_start), .asd_req_byte_stop_o(asd_req_byte_stop),
    .asd_req_byte_ack_o(asd_req_byte_ack), .asd_req_byte_nack_o(asd_req_byte_nack), .asd_req_byte_data_valid_o(asd_req_byte_dv), .asd_req_byte_data_o(asd_req_byte_data),
    .asd_req_bulk_current_loc_o(asd_req_bulk_cur), .asd_req_bulk_slave_addr_o(asd_req_bulk_slave), .asd_req_bulk_offset_addr_o(asd_req_bulk_offs),
    .asd_req_bulk_length_o(asd_req_bulk_len), .asd_req_bulk_wdata_o(asd_req_bulk_wdata), .asd_req_cfg_clock_rate_o(asd_req_cfg_clk),
    .asd_req_cfg_addr_count_o(asd_req_cfg_count), .asd_req_cfg_addr_cfg_o(asd_req_cfg_entries), .asd_req_crc_error_o(asd_req_crc_err),
    .asd_req_format_error_o(asd_req_fmt_err)
  );

  initial begin
    logic [31:0] crc_fix;
    logic [7:0] tmpb;
    asep_packet_t snap_pkt;
    logic [11:0] snap_len;
    clk = 0;
    rst = 1; soft_reset = 0; alloc = 0;
    byte_enc = 0; byte_dec = 0; byte_start = 0; byte_stop = 0; byte_ack = 0; byte_nack = 0; byte_dv = 0; byte_err = 0; byte_data = 8'h00;
    bulk_enc = 0; bulk_dec = 0; bulk_cur_loc = 0; bulk_off16 = 1; bulk_err = 0; bulk_slave = 7'h50; bulk_offs = 16'h0010; bulk_len = 16'd0; bulk_payload = '0; ack_payload = '0; bulk_fmt = I2C_BULK_WRITE;
    cfg_enc = 0; cfg_dec = 0; cfg_ack_ok = 1; cfg_cmd = I2C_CFG_WRITE; cfg_clk_rate = 6'h04; cfg_addr_count = 4'd2; cfg_entries = '0;
    cfg_entries = i2c_addr_cfg_set(cfg_entries, 0, i2c_addr_cfg_entry_pack(1'b0, 7'h08));
    cfg_entries = i2c_addr_cfg_set(cfg_entries, 1, i2c_addr_cfg_entry_pack(1'b1, 7'h09));
    startup_sync = 0; cfg_reg_wr = 0; tx_build_byte = 0; tx_build_bulk_wr = 0; tx_build_bulk_rd = 0; tx_build_cfg_wr = 0; tx_build_cfg_rd = 0;
    watchdog_cycles = 16'd3; root_rx_valid = 0; root_rx_pkt = '0; root_rx_pkt_len = '0; asd_rx_valid = 0;
    asd_rx_pkt = '0; asd_rx_pkt_len = '0;
    asd_resp_bulk_ack_valid = 0; asd_resp_bulk_ack_len = 0; asd_resp_bulk_ack_payload = '0; asd_resp_bulk_read_valid = 0; asd_resp_bulk_read_len = 0; asd_resp_bulk_rdata = '0;
    asd_resp_cfg_ack_valid = 0; asd_resp_cfg_ack_ok = 0; asd_resp_cfg_read_valid = 0; asd_resp_cfg_clk = 6'h04; asd_resp_cfg_count = 4'd2; asd_resp_cfg_entries = cfg_entries;
    pass_count = 0; fail_count = 0;

    tick(2); rst = 0; tick(1);

    check("T1 cmd id reset", cmd_id == 8'h01);
    alloc = 1; tick(1); alloc = 0;
    check("T1 cmd id increment", cmd_id == 8'h02);

    // T2 byte encode/decode
    byte_start = 1; byte_dv = 1; byte_data = 8'hA5; byte_ack = 1; byte_enc = 1; #1;
    tmpb = asep_get_byte(byte_pkt_enc,0);
    check("T2 byte stream", tmpb[7:1] == ASEP_STREAM_I2C);
    byte_pkt_dec = byte_pkt_enc; byte_pkt_len_dec = byte_pkt_len_enc;
    byte_enc = 0; byte_dec = 1; #1;
    check("T2 byte seen", byte_seen);
    check("T2 byte start", dec_byte_start);
    check("T2 byte ack", dec_byte_ack);
    check("T2 byte data", dec_byte_data == 8'hA5);
    byte_dec = 0; byte_start = 0; byte_dv = 0; byte_ack = 0;

    // T3 bulk write
    bulk_fmt = I2C_BULK_WRITE; bulk_len = 16'd3;
    bulk_payload = asep_set_byte('0, 0, 8'h11);
    bulk_payload = asep_set_byte(bulk_payload, 1, 8'h22);
    bulk_payload = asep_set_byte(bulk_payload, 2, 8'h33);
    bulk_enc = 1; #1;
    check("T3 bulk write len", bulk_pkt_len_enc == 12'd16);
    bulk_pkt_dec = bulk_pkt_enc; bulk_pkt_len_dec = bulk_pkt_len_enc;
    bulk_enc = 0; bulk_dec = 1; #1;
    check("T3 bulk seen", bulk_seen);
    check("T3 bulk fmt", dec_bulk_fmt == I2C_BULK_WRITE);
    check("T3 bulk slave", dec_bulk_slave == 7'h50);
    check("T3 bulk payload1", asep_get_byte(dec_bulk_payload,1) == 8'h22);
    bulk_dec = 0;

    // T4 bulk ack/nack payload sizing
    bulk_fmt = I2C_BULK_ACK_NACK; bulk_len = 16'd5;
    ack_payload = i2c_ack_payload_set('0, 0, 8'hA8);
    bulk_enc = 1; #1;
    check("T4 ack payload bytes", bulk_pkt_len_enc == 12'd12);
    bulk_pkt_dec = bulk_pkt_enc; bulk_pkt_len_dec = bulk_pkt_len_enc;
    bulk_enc = 0; bulk_dec = 1; #1;
    check("T4 ack fmt", dec_bulk_fmt == I2C_BULK_ACK_NACK);
    check("T4 ack data", i2c_ack_payload_get(dec_ack_payload,0) == 8'hA8);
    bulk_dec = 0;

    // T5 cfg write/readresp
    cfg_cmd = I2C_CFG_WRITE; cfg_enc = 1; #1;
    check("T5 cfg len", cfg_pkt_len_enc == 12'd12);
    cfg_pkt_dec = cfg_pkt_enc; cfg_pkt_len_dec = cfg_pkt_len_enc;
    cfg_enc = 0; cfg_dec = 1; #1;
    check("T5 cfg seen", cfg_seen);
    check("T5 cfg count", dec_cfg_count == 4'd2);
    check("T5 cfg clock", dec_cfg_clk == 6'h04);
    check("T5 cfg addr1", i2c_addr_cfg_get(dec_cfg_entries,1) == i2c_addr_cfg_entry_pack(1'b1, 7'h09));
    cfg_dec = 0;

    // T6 cfg ack decode
    cfg_cmd = I2C_CFG_ACK_NACK; cfg_ack_ok = 1'b1; cfg_enc = 1; #1;
    cfg_pkt_dec = cfg_pkt_enc; cfg_pkt_len_dec = cfg_pkt_len_enc;
    cfg_enc = 0; cfg_dec = 1; #1;
    check("T6 cfg ack seen", cfg_seen);
    check("T6 cfg ack ok", dec_cfg_ack_ok);
    cfg_dec = 0;

    // T7 CRC error detect
    bulk_fmt = I2C_BULK_WRITE; bulk_len = 16'd1; bulk_payload = asep_set_byte('0, 0, 8'h44); bulk_enc = 1; #1; bulk_enc = 0;
    bulk_pkt_dec = bulk_pkt_enc;
    bulk_pkt_len_dec = bulk_pkt_len_enc;
    bulk_pkt_dec = asep_set_byte(bulk_pkt_dec, bulk_pkt_len_dec - 1, 8'h00);
    bulk_dec = 1; #1;
    check("T7 bulk crc err", bulk_crc_err);
    bulk_dec = 0;

    // T8 root auto config after startup
    startup_sync = 1; #1; snap_pkt = root_tx_pkt; snap_len = root_tx_pkt_len; tick(1); startup_sync = 0;
    asd_rx_pkt = snap_pkt; asd_rx_pkt_len = snap_len;
    check("T8 root tx valid", root_tx_valid);
    check("T8 root pending", root_pending);

    // T9 ASD config decode and config ack response
    asd_rx_valid = 1; root_rx_pkt = '0; root_rx_pkt_len = '0; tick(1); asd_rx_valid = 0;
    check("T9 asd cfg write seen", asd_req_cfg_write_seen);
    check("T9 asd cfg clock", asd_req_cfg_clk == 6'h04);
    asd_resp_cfg_ack_ok = 1; asd_resp_cfg_ack_valid = 1; tick(1); snap_pkt = asd_tx_pkt; snap_len = asd_tx_pkt_len; asd_resp_cfg_ack_valid = 0;
    check("T9 asd cfg ack tx", asd_tx_valid);
    root_rx_pkt = snap_pkt; root_rx_pkt_len = snap_len; root_rx_valid = 1; tick(1); root_rx_valid = 0;
    check("T9 root cfg ack seen", root_resp_cfg_ack_seen);
    check("T9 root cfg ack ok", root_resp_ack_ok);

    // T10 end-to-end bulk write + ack
    bulk_cur_loc = 0; bulk_off16 = 1; bulk_slave = 7'h51; bulk_offs = 16'h0020; bulk_len = 16'd2;
    bulk_payload = asep_set_byte('0, 0, 8'h55);
    bulk_payload = asep_set_byte(bulk_payload, 1, 8'h66);
    tx_build_bulk_wr = 1; #1; snap_pkt = root_tx_pkt; snap_len = root_tx_pkt_len; tick(1); tx_build_bulk_wr = 0;
    asd_rx_pkt = snap_pkt; asd_rx_pkt_len = snap_len;
    check("T10 root tx bulk valid", root_tx_valid);
    asd_rx_valid = 1; tick(1); asd_rx_valid = 0;
    check("T10 asd bulk write seen", asd_req_bulk_write_seen);
    check("T10 asd bulk data", asep_get_byte(asd_req_bulk_wdata,1) == 8'h66);
    asd_resp_bulk_ack_len = 16'd2;
    asd_resp_bulk_ack_payload = i2c_ack_payload_set('0, 0, 8'h00);
    asd_resp_bulk_ack_valid = 1; tick(1); snap_pkt = asd_tx_pkt; snap_len = asd_tx_pkt_len; asd_resp_bulk_ack_valid = 0;
    root_rx_pkt = snap_pkt; root_rx_pkt_len = snap_len; root_rx_valid = 1; tick(1); root_rx_valid = 0;
    check("T10 root bulk ack seen", root_resp_bulk_ack_seen);
    check("T10 root bulk ack ok", root_resp_ack_ok);

    // T11 end-to-end bulk read + read response
    bulk_cur_loc = 1; bulk_len = 16'd3;
    tx_build_bulk_rd = 1; #1; snap_pkt = root_tx_pkt; snap_len = root_tx_pkt_len; tick(1); tx_build_bulk_rd = 0;
    asd_rx_pkt = snap_pkt; asd_rx_pkt_len = snap_len;
    asd_rx_valid = 1; tick(1); asd_rx_valid = 0;
    check("T11 asd bulk read seen", asd_req_bulk_read_seen);
    asd_resp_bulk_read_len = 16'd3;
    asd_resp_bulk_rdata = asep_set_byte('0, 0, 8'hDE);
    asd_resp_bulk_rdata = asep_set_byte(asd_resp_bulk_rdata, 1, 8'hAD);
    asd_resp_bulk_rdata = asep_set_byte(asd_resp_bulk_rdata, 2, 8'hBE);
    asd_resp_bulk_read_valid = 1; tick(1); snap_pkt = asd_tx_pkt; snap_len = asd_tx_pkt_len; asd_resp_bulk_read_valid = 0;
    root_rx_pkt = snap_pkt; root_rx_pkt_len = snap_len; root_rx_valid = 1; tick(1); root_rx_valid = 0;
    check("T11 root bulk read seen", root_resp_bulk_read_seen);
    check("T11 root rdata1", asep_get_byte(root_resp_rdata,1) == 8'hAD);

    // T12 timeout path
    begin
      logic timeout_seen;
      timeout_seen = 1'b0;
      tx_build_cfg_rd = 1; #1; tick(1); tx_build_cfg_rd = 0;
      repeat (5) begin
        timeout_seen |= root_timeout;
        tick(1);
      end
      timeout_seen |= root_timeout;
      check("T12 timeout", timeout_seen);
    end

    // T13 config count zero rejected
    cfg_cmd = I2C_CFG_READ; cfg_addr_count = 4'd0; cfg_enc = 1; #1; cfg_pkt_dec = cfg_pkt_enc; cfg_pkt_len_dec = cfg_pkt_len_enc; cfg_enc = 0;
    cfg_dec = 1; #1;
    check("T13 cfg zero count fmt err", cfg_fmt_err);
    cfg_dec = 0;
    cfg_addr_count = 4'd2;

    $display("asep_i2c_tb: %0d passed, %0d failed", pass_count, fail_count);
    if (fail_count != 0) $fatal(1);
    $finish;
  end
endmodule

`default_nettype wire
