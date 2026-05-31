`timescale 1ns/1ps
`default_nettype none

module i2c_ase_tx
  import asa_asep_pkg::*;
  import asa_i2c_asep_pkg::*;
(
  input  logic                                    clk,
  input  logic                                    rst,
  input  logic                                    soft_reset_i,
  input  logic                                    startup_sync_i,
  input  logic                                    cfg_reg_write_i,
  input  logic                                    tx_build_byte_i,
  input  logic                                    tx_build_bulk_write_i,
  input  logic                                    tx_build_bulk_read_i,
  input  logic                                    tx_build_cfg_write_i,
  input  logic                                    tx_build_cfg_read_i,
  input  asep_ts_mode_e                           ts_mode_i,
  input  logic [31:0]                             ts_value_i,
  input  logic                                    tx_i2c_error_i,
  input  logic                                    tx_byte_start_i,
  input  logic                                    tx_byte_stop_i,
  input  logic                                    tx_byte_ack_i,
  input  logic                                    tx_byte_nack_i,
  input  logic                                    tx_byte_data_valid_i,
  input  logic [7:0]                              tx_byte_data_i,
  input  logic                                    tx_bulk_current_loc_i,
  input  logic                                    tx_bulk_offset_16b_i,
  input  logic [6:0]                              tx_bulk_slave_addr_i,
  input  logic [15:0]                             tx_bulk_offset_addr_i,
  input  logic [15:0]                             tx_bulk_len_i,
  input  asep_packet_t                            tx_bulk_wdata_i,
  input  logic [5:0]                              cfg_clock_rate_i,
  input  logic [3:0]                              cfg_addr_count_i,
  input  i2c_addr_cfg_vec_t                       cfg_addr_cfg_i,
  input  logic [15:0]                             watchdog_cycles_i,
  input  logic                                    rx_packet_valid_i,
  input  asep_packet_t                            rx_packet_i,
  input  logic [11:0]                             rx_packet_len_i,
  output logic                                    tx_packet_valid_o,
  output asep_packet_t                            tx_packet_o,
  output logic [11:0]                             tx_packet_len_o,
  output logic [7:0]                              tx_cmd_id_o,
  output logic                                    pending_o,
  output logic                                    timeout_o,
  output logic                                    resp_bulk_ack_seen_o,
  output logic                                    resp_bulk_read_seen_o,
  output logic                                    resp_cfg_ack_seen_o,
  output logic                                    resp_cfg_read_seen_o,
  output logic [7:0]                              resp_cmd_id_o,
  output logic                                    resp_ack_ok_o,
  output logic [15:0]                             resp_length_o,
  output logic [(ASEP_MAX_PACKET_BYTES*8)-1:0]    resp_ack_payload_o,
  output asep_packet_t                            resp_rdata_o,
  output logic [5:0]                              resp_cfg_clock_rate_o,
  output i2c_addr_cfg_vec_t                       resp_cfg_addr_cfg_o,
  output logic                                    resp_crc_error_o,
  output logic                                    resp_format_error_o
);
  logic [7:0] cmd_id_cur;
  logic       alloc_cmd_id;

  asep_packet_t byte_pkt, bulk_wr_pkt, bulk_rd_pkt, cfg_wr_pkt, cfg_rd_pkt;
  logic [11:0] byte_len, bulk_wr_len, bulk_rd_len, cfg_wr_len, cfg_rd_len;

  logic bulk_seen, cfg_seen;
  logic [7:0] bulk_cmd_id, cfg_cmd_id;
  logic bulk_i2c_err, cfg_i2c_err;
  logic bulk_cur_loc;
  logic [6:0] bulk_slave;
  logic [15:0] bulk_offs, bulk_len;
  i2c_bulk_fmt_e bulk_fmt;
  asep_packet_t bulk_payload;
  logic [(ASEP_MAX_PACKET_BYTES*8)-1:0] bulk_ack_payload;
  logic bulk_crc_err, bulk_fmt_err;
  logic [3:0] cfg_addr_count;
  logic [5:0] cfg_clk;
  i2c_addr_cfg_vec_t cfg_entries;
  logic cfg_ack_ok;
  i2c_cfg_cmd_e cfg_cmd_dec;
  logic cfg_crc_err, cfg_fmt_err;

  logic        pending_q;
  logic [7:0]  pending_cmd_id_q;
  logic [1:0]  pending_kind_q; // 1 bulk ack, 2 bulk read, 3 cfg
  logic [15:0] watchdog_q;
  logic        auto_cfg_pulse;

  i2c_cmd_id_mgr u_cmd_mgr(
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset_i), .alloc_i(alloc_cmd_id), .cmd_id_o(cmd_id_cur)
  );

  i2c_byte_codec u_byte_enc(
    .encode_i(1'b1), .decode_i(1'b0), .cmd_id_i(cmd_id_cur), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .i2c_error_i(tx_i2c_error_i), .start_i(tx_byte_start_i), .stop_i(tx_byte_stop_i), .ack_i(tx_byte_ack_i),
    .nack_i(tx_byte_nack_i), .data_valid_i(tx_byte_data_valid_i), .data_i(tx_byte_data_i),
    .packet_i('0), .packet_len_i('0), .packet_o(byte_pkt), .packet_len_o(byte_len),
    .seen_o(), .cmd_id_o(), .i2c_error_o(), .start_o(), .stop_o(), .ack_o(), .nack_o(), .data_valid_o(), .data_o(), .format_error_o()
  );

  i2c_bulk_codec u_bulk_wr_enc(
    .encode_i(1'b1), .decode_i(1'b0), .cmd_id_i(cmd_id_cur), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .i2c_error_i(tx_i2c_error_i), .current_loc_i(tx_bulk_current_loc_i), .fmt_i(I2C_BULK_WRITE),
    .slave_addr_i(tx_bulk_slave_addr_i), .offset_addr_i(tx_bulk_offset_addr_i), .length_i(tx_bulk_len_i),
    .offset_16b_i(tx_bulk_offset_16b_i), .payload_i(tx_bulk_wdata_i), .ack_payload_i('0),
    .packet_i('0), .packet_len_i('0), .packet_o(bulk_wr_pkt), .packet_len_o(bulk_wr_len),
    .seen_o(), .cmd_id_o(), .i2c_error_o(), .current_loc_o(), .fmt_o(), .slave_addr_o(), .offset_addr_o(), .length_o(),
    .payload_o(), .ack_payload_o(), .crc_error_o(), .format_error_o()
  );

  i2c_bulk_codec u_bulk_rd_enc(
    .encode_i(1'b1), .decode_i(1'b0), .cmd_id_i(cmd_id_cur), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .i2c_error_i(tx_i2c_error_i), .current_loc_i(tx_bulk_current_loc_i), .fmt_i(I2C_BULK_READ),
    .slave_addr_i(tx_bulk_slave_addr_i), .offset_addr_i(tx_bulk_offset_addr_i), .length_i(tx_bulk_len_i),
    .offset_16b_i(tx_bulk_offset_16b_i), .payload_i('0), .ack_payload_i('0),
    .packet_i('0), .packet_len_i('0), .packet_o(bulk_rd_pkt), .packet_len_o(bulk_rd_len),
    .seen_o(), .cmd_id_o(), .i2c_error_o(), .current_loc_o(), .fmt_o(), .slave_addr_o(), .offset_addr_o(), .length_o(),
    .payload_o(), .ack_payload_o(), .crc_error_o(), .format_error_o()
  );

  i2c_cfg_codec u_cfg_wr_enc(
    .encode_i(1'b1), .decode_i(1'b0), .cmd_id_i(cmd_id_cur), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .i2c_error_i(tx_i2c_error_i), .cmd_i(I2C_CFG_WRITE), .addr_count_i(cfg_addr_count_i), .clock_rate_i(cfg_clock_rate_i),
    .addr_cfg_i(cfg_addr_cfg_i), .ack_ok_i(1'b1), .packet_i('0), .packet_len_i('0),
    .packet_o(cfg_wr_pkt), .packet_len_o(cfg_wr_len), .seen_o(), .cmd_id_o(), .i2c_error_o(), .cmd_o(),
    .addr_count_o(), .clock_rate_o(), .addr_cfg_o(), .ack_ok_o(), .crc_error_o(), .format_error_o()
  );

  i2c_cfg_codec u_cfg_rd_enc(
    .encode_i(1'b1), .decode_i(1'b0), .cmd_id_i(cmd_id_cur), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .i2c_error_i(tx_i2c_error_i), .cmd_i(I2C_CFG_READ), .addr_count_i(cfg_addr_count_i), .clock_rate_i(cfg_clock_rate_i),
    .addr_cfg_i(cfg_addr_cfg_i), .ack_ok_i(1'b1), .packet_i('0), .packet_len_i('0),
    .packet_o(cfg_rd_pkt), .packet_len_o(cfg_rd_len), .seen_o(), .cmd_id_o(), .i2c_error_o(), .cmd_o(),
    .addr_count_o(), .clock_rate_o(), .addr_cfg_o(), .ack_ok_o(), .crc_error_o(), .format_error_o()
  );

  i2c_bulk_codec u_bulk_dec(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .cmd_id_i('0), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0),
    .i2c_error_i('0), .current_loc_i('0), .fmt_i(I2C_BULK_WRITE), .slave_addr_i('0), .offset_addr_i('0), .length_i('0),
    .offset_16b_i('0), .payload_i('0), .ack_payload_i('0), .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i),
    .packet_o(), .packet_len_o(), .seen_o(bulk_seen), .cmd_id_o(bulk_cmd_id), .i2c_error_o(bulk_i2c_err),
    .current_loc_o(bulk_cur_loc), .fmt_o(bulk_fmt), .slave_addr_o(bulk_slave), .offset_addr_o(bulk_offs), .length_o(bulk_len),
    .payload_o(bulk_payload), .ack_payload_o(bulk_ack_payload), .crc_error_o(bulk_crc_err), .format_error_o(bulk_fmt_err)
  );

  i2c_cfg_codec u_cfg_dec(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .cmd_id_i('0), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0),
    .i2c_error_i('0), .cmd_i(I2C_CFG_WRITE), .addr_count_i('0), .clock_rate_i('0), .addr_cfg_i('0), .ack_ok_i('0),
    .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i), .packet_o(), .packet_len_o(), .seen_o(cfg_seen), .cmd_id_o(cfg_cmd_id),
    .i2c_error_o(cfg_i2c_err), .cmd_o(cfg_cmd_dec), .addr_count_o(cfg_addr_count), .clock_rate_o(cfg_clk), .addr_cfg_o(cfg_entries),
    .ack_ok_o(cfg_ack_ok), .crc_error_o(cfg_crc_err), .format_error_o(cfg_fmt_err)
  );

  assign auto_cfg_pulse = startup_sync_i | cfg_reg_write_i;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      pending_q            <= 1'b0;
      pending_cmd_id_q     <= 8'h00;
      pending_kind_q       <= 2'b00;
      watchdog_q           <= 16'h0000;
      timeout_o            <= 1'b0;
      resp_bulk_ack_seen_o <= 1'b0;
      resp_bulk_read_seen_o<= 1'b0;
      resp_cfg_ack_seen_o  <= 1'b0;
      resp_cfg_read_seen_o <= 1'b0;
      resp_cmd_id_o        <= 8'h00;
      resp_ack_ok_o        <= 1'b0;
      resp_length_o        <= 16'h0000;
      resp_ack_payload_o   <= '0;
      resp_rdata_o         <= '0;
      resp_cfg_clock_rate_o<= 6'h00;
      resp_cfg_addr_cfg_o  <= '0;
      resp_crc_error_o     <= 1'b0;
      resp_format_error_o  <= 1'b0;
    end else begin
      timeout_o             <= 1'b0;
      resp_bulk_ack_seen_o  <= 1'b0;
      resp_bulk_read_seen_o <= 1'b0;
      resp_cfg_ack_seen_o   <= 1'b0;
      resp_cfg_read_seen_o  <= 1'b0;
      resp_crc_error_o      <= 1'b0;
      resp_format_error_o   <= 1'b0;

      if (soft_reset_i) begin
        pending_q        <= 1'b0;
        watchdog_q       <= 16'h0000;
      end else begin
        if (pending_q) begin
          if (watchdog_q != 16'h0000) watchdog_q <= watchdog_q - 16'd1;
          else begin
            pending_q <= 1'b0;
            timeout_o <= 1'b1;
          end
        end

        if (rx_packet_valid_i && (bulk_crc_err || cfg_crc_err)) resp_crc_error_o <= 1'b1;
        if (rx_packet_valid_i && (bulk_fmt_err || cfg_fmt_err)) resp_format_error_o <= 1'b1;

        if (bulk_seen && pending_q && (bulk_cmd_id == pending_cmd_id_q)) begin
          resp_cmd_id_o      <= bulk_cmd_id;
          resp_length_o      <= bulk_len;
          resp_ack_payload_o <= bulk_ack_payload;
          resp_rdata_o       <= bulk_payload;
          pending_q          <= 1'b0;
          if (bulk_fmt == I2C_BULK_ACK_NACK && pending_kind_q == 2'b01) begin
            resp_bulk_ack_seen_o <= 1'b1;
            resp_ack_ok_o        <= ~bulk_ack_payload[7];
          end
          if (bulk_fmt == I2C_BULK_READ_RESP && pending_kind_q == 2'b10) begin
            resp_bulk_read_seen_o <= 1'b1;
            resp_ack_ok_o         <= ~bulk_ack_payload[7];
          end
        end

        if (cfg_seen && pending_q && (cfg_cmd_id == pending_cmd_id_q)) begin
          resp_cmd_id_o       <= cfg_cmd_id;
          resp_cfg_clock_rate_o <= cfg_clk;
          resp_cfg_addr_cfg_o <= cfg_entries;
          pending_q           <= 1'b0;
          if (cfg_cmd_dec == I2C_CFG_ACK_NACK && pending_kind_q == 2'b11) begin
            resp_cfg_ack_seen_o <= 1'b1;
            resp_ack_ok_o       <= cfg_ack_ok;
          end
          if (cfg_cmd_dec == I2C_CFG_READ_RESP && pending_kind_q == 2'b11) begin
            resp_cfg_read_seen_o <= 1'b1;
          end
        end

        if (!pending_q) begin
          if (tx_build_bulk_write_i) begin
            pending_q        <= 1'b1;
            pending_cmd_id_q <= cmd_id_cur;
            pending_kind_q   <= 2'b01;
            watchdog_q       <= watchdog_cycles_i;
          end else if (tx_build_bulk_read_i) begin
            pending_q        <= 1'b1;
            pending_cmd_id_q <= cmd_id_cur;
            pending_kind_q   <= 2'b10;
            watchdog_q       <= watchdog_cycles_i;
          end else if (tx_build_cfg_write_i || auto_cfg_pulse || tx_build_cfg_read_i) begin
            pending_q        <= 1'b1;
            pending_cmd_id_q <= cmd_id_cur;
            pending_kind_q   <= 2'b11;
            watchdog_q       <= watchdog_cycles_i;
          end
        end
      end
    end
  end

  always_comb begin
    tx_packet_valid_o = 1'b0;
    tx_packet_o       = '0;
    tx_packet_len_o   = '0;
    tx_cmd_id_o       = cmd_id_cur;
    alloc_cmd_id      = 1'b0;
    if (tx_build_byte_i) begin
      tx_packet_valid_o = 1'b1;
      tx_packet_o       = byte_pkt;
      tx_packet_len_o   = byte_len;
      alloc_cmd_id      = 1'b1;
    end else if (tx_build_bulk_write_i) begin
      tx_packet_valid_o = 1'b1;
      tx_packet_o       = bulk_wr_pkt;
      tx_packet_len_o   = bulk_wr_len;
      alloc_cmd_id      = 1'b1;
    end else if (tx_build_bulk_read_i) begin
      tx_packet_valid_o = 1'b1;
      tx_packet_o       = bulk_rd_pkt;
      tx_packet_len_o   = bulk_rd_len;
      alloc_cmd_id      = 1'b1;
    end else if (tx_build_cfg_write_i || auto_cfg_pulse) begin
      tx_packet_valid_o = 1'b1;
      tx_packet_o       = cfg_wr_pkt;
      tx_packet_len_o   = cfg_wr_len;
      alloc_cmd_id      = 1'b1;
    end else if (tx_build_cfg_read_i) begin
      tx_packet_valid_o = 1'b1;
      tx_packet_o       = cfg_rd_pkt;
      tx_packet_len_o   = cfg_rd_len;
      alloc_cmd_id      = 1'b1;
    end
  end

  assign pending_o = pending_q;

endmodule

`default_nettype wire
