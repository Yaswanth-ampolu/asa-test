`timescale 1ns/1ps
`default_nettype none

module i2c_asd_rx
  import asa_asep_pkg::*;
  import asa_i2c_asep_pkg::*;
(
  input  logic                                   clk,
  input  logic                                   rst,
  input  logic                                   soft_reset_i,
  input  asep_ts_mode_e                          ts_mode_i,
  input  logic [31:0]                            ts_value_i,
  input  logic                                   rx_packet_valid_i,
  input  asep_packet_t                           rx_packet_i,
  input  logic [11:0]                            rx_packet_len_i,
  input  logic                                   resp_bulk_ack_valid_i,
  input  logic [15:0]                            resp_bulk_ack_len_i,
  input  logic [(ASEP_MAX_PACKET_BYTES*8)-1:0]   resp_bulk_ack_payload_i,
  input  logic                                   resp_bulk_read_valid_i,
  input  logic [15:0]                            resp_bulk_read_len_i,
  input  asep_packet_t                           resp_bulk_rdata_i,
  input  logic                                   resp_cfg_ack_valid_i,
  input  logic                                   resp_cfg_ack_ok_i,
  input  logic                                   resp_cfg_read_valid_i,
  input  logic [5:0]                             resp_cfg_clock_rate_i,
  input  logic [3:0]                             resp_cfg_addr_count_i,
  input  i2c_addr_cfg_vec_t                      resp_cfg_addr_cfg_i,
  output logic                                   tx_packet_valid_o,
  output asep_packet_t                           tx_packet_o,
  output logic [11:0]                            tx_packet_len_o,
  output logic                                   req_byte_seen_o,
  output logic                                   req_bulk_write_seen_o,
  output logic                                   req_bulk_read_seen_o,
  output logic                                   req_cfg_write_seen_o,
  output logic                                   req_cfg_read_seen_o,
  output logic [7:0]                             req_cmd_id_o,
  output logic                                   req_i2c_error_o,
  output logic                                   req_byte_start_o,
  output logic                                   req_byte_stop_o,
  output logic                                   req_byte_ack_o,
  output logic                                   req_byte_nack_o,
  output logic                                   req_byte_data_valid_o,
  output logic [7:0]                             req_byte_data_o,
  output logic                                   req_bulk_current_loc_o,
  output logic [6:0]                             req_bulk_slave_addr_o,
  output logic [15:0]                            req_bulk_offset_addr_o,
  output logic [15:0]                            req_bulk_length_o,
  output asep_packet_t                           req_bulk_wdata_o,
  output logic [5:0]                             req_cfg_clock_rate_o,
  output logic [3:0]                             req_cfg_addr_count_o,
  output i2c_addr_cfg_vec_t                      req_cfg_addr_cfg_o,
  output logic                                   req_crc_error_o,
  output logic                                   req_format_error_o
);
  logic byte_seen, byte_fmt_err;
  logic [7:0] byte_cmd_id, byte_data;
  logic byte_err, byte_start, byte_stop, byte_ack, byte_nack, byte_dv;
  logic bulk_seen, bulk_crc_err, bulk_fmt_err, bulk_cur_loc;
  logic [7:0] bulk_cmd_id;
  logic bulk_err;
  logic [6:0] bulk_slave;
  logic [15:0] bulk_offs, bulk_len;
  i2c_bulk_fmt_e bulk_fmt;
  asep_packet_t bulk_payload;
  logic [(ASEP_MAX_PACKET_BYTES*8)-1:0] bulk_ack_payload;
  logic cfg_seen, cfg_crc_err, cfg_fmt_err, cfg_ack_ok, cfg_err;
  logic [7:0] cfg_cmd_id;
  logic [3:0] cfg_addr_count;
  logic [5:0] cfg_clk;
  i2c_cfg_cmd_e cfg_cmd_dec;
  i2c_addr_cfg_vec_t cfg_entries;

  logic [7:0] last_cmd_id_q;
  logic [6:0] last_slave_q;
  logic [15:0] last_len_q;
  logic last_cur_loc_q;
  logic [15:0] last_offs_q;
  logic last_is_cfg_q;

  asep_packet_t ack_pkt, rd_pkt, cfg_ack_pkt, cfg_rd_pkt;
  logic [11:0] ack_len, rd_len, cfg_ack_len, cfg_rd_len;

  i2c_byte_codec u_byte_dec(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .cmd_id_i('0), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0),
    .i2c_error_i('0), .start_i('0), .stop_i('0), .ack_i('0), .nack_i('0), .data_valid_i('0), .data_i('0),
    .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i), .packet_o(), .packet_len_o(), .seen_o(byte_seen), .cmd_id_o(byte_cmd_id),
    .i2c_error_o(byte_err), .start_o(byte_start), .stop_o(byte_stop), .ack_o(byte_ack), .nack_o(byte_nack),
    .data_valid_o(byte_dv), .data_o(byte_data), .format_error_o(byte_fmt_err)
  );

  i2c_bulk_codec u_bulk_dec(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .cmd_id_i('0), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0),
    .i2c_error_i('0), .current_loc_i('0), .fmt_i(I2C_BULK_WRITE), .slave_addr_i('0), .offset_addr_i('0), .length_i('0),
    .offset_16b_i('0), .payload_i('0), .ack_payload_i('0), .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i),
    .packet_o(), .packet_len_o(), .seen_o(bulk_seen), .cmd_id_o(bulk_cmd_id), .i2c_error_o(bulk_err), .current_loc_o(bulk_cur_loc),
    .fmt_o(bulk_fmt), .slave_addr_o(bulk_slave), .offset_addr_o(bulk_offs), .length_o(bulk_len), .payload_o(bulk_payload),
    .ack_payload_o(bulk_ack_payload), .crc_error_o(bulk_crc_err), .format_error_o(bulk_fmt_err)
  );

  i2c_cfg_codec u_cfg_dec(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .cmd_id_i('0), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0),
    .i2c_error_i('0), .cmd_i(I2C_CFG_WRITE), .addr_count_i('0), .clock_rate_i('0), .addr_cfg_i('0), .ack_ok_i('0),
    .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i), .packet_o(), .packet_len_o(), .seen_o(cfg_seen), .cmd_id_o(cfg_cmd_id),
    .i2c_error_o(cfg_err), .cmd_o(cfg_cmd_dec), .addr_count_o(cfg_addr_count), .clock_rate_o(cfg_clk), .addr_cfg_o(cfg_entries),
    .ack_ok_o(cfg_ack_ok), .crc_error_o(cfg_crc_err), .format_error_o(cfg_fmt_err)
  );

  i2c_bulk_codec u_ack_enc(
    .encode_i(1'b1), .decode_i(1'b0), .cmd_id_i(last_cmd_id_q), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .i2c_error_i(1'b0), .current_loc_i(last_cur_loc_q), .fmt_i(I2C_BULK_ACK_NACK), .slave_addr_i(last_slave_q),
    .offset_addr_i(last_offs_q), .length_i(resp_bulk_ack_len_i), .offset_16b_i(1'b1), .payload_i('0), .ack_payload_i(resp_bulk_ack_payload_i),
    .packet_i('0), .packet_len_i('0), .packet_o(ack_pkt), .packet_len_o(ack_len), .seen_o(), .cmd_id_o(), .i2c_error_o(), .current_loc_o(),
    .fmt_o(), .slave_addr_o(), .offset_addr_o(), .length_o(), .payload_o(), .ack_payload_o(), .crc_error_o(), .format_error_o()
  );

  i2c_bulk_codec u_rd_enc(
    .encode_i(1'b1), .decode_i(1'b0), .cmd_id_i(last_cmd_id_q), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .i2c_error_i(1'b0), .current_loc_i(last_cur_loc_q), .fmt_i(I2C_BULK_READ_RESP), .slave_addr_i(last_slave_q),
    .offset_addr_i(last_offs_q), .length_i(resp_bulk_read_len_i), .offset_16b_i(1'b1), .payload_i(resp_bulk_rdata_i), .ack_payload_i('0),
    .packet_i('0), .packet_len_i('0), .packet_o(rd_pkt), .packet_len_o(rd_len), .seen_o(), .cmd_id_o(), .i2c_error_o(), .current_loc_o(),
    .fmt_o(), .slave_addr_o(), .offset_addr_o(), .length_o(), .payload_o(), .ack_payload_o(), .crc_error_o(), .format_error_o()
  );

  i2c_cfg_codec u_cfg_ack_enc(
    .encode_i(1'b1), .decode_i(1'b0), .cmd_id_i(last_cmd_id_q), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .i2c_error_i(1'b0), .cmd_i(I2C_CFG_ACK_NACK), .addr_count_i(req_cfg_addr_count_o), .clock_rate_i(resp_cfg_clock_rate_i),
    .addr_cfg_i(resp_cfg_addr_cfg_i), .ack_ok_i(resp_cfg_ack_ok_i), .packet_i('0), .packet_len_i('0),
    .packet_o(cfg_ack_pkt), .packet_len_o(cfg_ack_len), .seen_o(), .cmd_id_o(), .i2c_error_o(), .cmd_o(), .addr_count_o(),
    .clock_rate_o(), .addr_cfg_o(), .ack_ok_o(), .crc_error_o(), .format_error_o()
  );

  i2c_cfg_codec u_cfg_rd_enc(
    .encode_i(1'b1), .decode_i(1'b0), .cmd_id_i(last_cmd_id_q), .ts_mode_i(ts_mode_i), .ts_value_i(ts_value_i),
    .i2c_error_i(1'b0), .cmd_i(I2C_CFG_READ_RESP), .addr_count_i(resp_cfg_addr_count_i), .clock_rate_i(resp_cfg_clock_rate_i),
    .addr_cfg_i(resp_cfg_addr_cfg_i), .ack_ok_i(1'b1), .packet_i('0), .packet_len_i('0),
    .packet_o(cfg_rd_pkt), .packet_len_o(cfg_rd_len), .seen_o(), .cmd_id_o(), .i2c_error_o(), .cmd_o(), .addr_count_o(),
    .clock_rate_o(), .addr_cfg_o(), .ack_ok_o(), .crc_error_o(), .format_error_o()
  );

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      last_cmd_id_q   <= 8'h00;
      last_slave_q    <= 7'h00;
      last_len_q      <= 16'h0000;
      last_cur_loc_q  <= 1'b0;
      last_offs_q     <= 16'h0000;
      last_is_cfg_q   <= 1'b0;
      req_byte_seen_o <= 1'b0;
      req_bulk_write_seen_o <= 1'b0;
      req_bulk_read_seen_o  <= 1'b0;
      req_cfg_write_seen_o  <= 1'b0;
      req_cfg_read_seen_o   <= 1'b0;
      req_cmd_id_o    <= 8'h00;
      req_i2c_error_o <= 1'b0;
      req_byte_start_o <= 1'b0;
      req_byte_stop_o <= 1'b0;
      req_byte_ack_o  <= 1'b0;
      req_byte_nack_o <= 1'b0;
      req_byte_data_valid_o <= 1'b0;
      req_byte_data_o <= 8'h00;
      req_bulk_current_loc_o <= 1'b0;
      req_bulk_slave_addr_o <= 7'h00;
      req_bulk_offset_addr_o <= 16'h0000;
      req_bulk_length_o <= 16'h0000;
      req_bulk_wdata_o <= '0;
      req_cfg_clock_rate_o <= 6'h00;
      req_cfg_addr_count_o <= 4'h0;
      req_cfg_addr_cfg_o <= '0;
      req_crc_error_o <= 1'b0;
      req_format_error_o <= 1'b0;
    end else begin
      req_byte_seen_o <= 1'b0;
      req_bulk_write_seen_o <= 1'b0;
      req_bulk_read_seen_o  <= 1'b0;
      req_cfg_write_seen_o  <= 1'b0;
      req_cfg_read_seen_o   <= 1'b0;
      req_crc_error_o       <= 1'b0;
      req_format_error_o    <= 1'b0;
      if (soft_reset_i) begin
        last_cmd_id_q <= 8'h00;
        last_is_cfg_q <= 1'b0;
      end else if (rx_packet_valid_i) begin
        if (bulk_crc_err || cfg_crc_err) req_crc_error_o <= 1'b1;
        if (byte_fmt_err || bulk_fmt_err || cfg_fmt_err) req_format_error_o <= 1'b1;
        if (byte_seen) begin
          req_byte_seen_o       <= 1'b1;
          req_cmd_id_o          <= byte_cmd_id;
          req_i2c_error_o       <= byte_err;
          req_byte_start_o      <= byte_start;
          req_byte_stop_o       <= byte_stop;
          req_byte_ack_o        <= byte_ack;
          req_byte_nack_o       <= byte_nack;
          req_byte_data_valid_o <= byte_dv;
          req_byte_data_o       <= byte_data;
          last_cmd_id_q         <= byte_cmd_id;
          last_is_cfg_q         <= 1'b0;
        end
        if (bulk_seen) begin
          req_cmd_id_o           <= bulk_cmd_id;
          req_i2c_error_o        <= bulk_err;
          req_bulk_current_loc_o <= bulk_cur_loc;
          req_bulk_slave_addr_o  <= bulk_slave;
          req_bulk_offset_addr_o <= bulk_offs;
          req_bulk_length_o      <= bulk_len;
          req_bulk_wdata_o       <= bulk_payload;
          last_cmd_id_q          <= bulk_cmd_id;
          last_slave_q           <= bulk_slave;
          last_len_q             <= bulk_len;
          last_cur_loc_q         <= bulk_cur_loc;
          last_offs_q            <= bulk_offs;
          last_is_cfg_q          <= 1'b0;
          if (bulk_fmt == I2C_BULK_WRITE) req_bulk_write_seen_o <= 1'b1;
          if (bulk_fmt == I2C_BULK_READ)  req_bulk_read_seen_o  <= 1'b1;
        end
        if (cfg_seen) begin
          req_cmd_id_o         <= cfg_cmd_id;
          req_i2c_error_o      <= cfg_err;
          req_cfg_clock_rate_o <= cfg_clk;
          req_cfg_addr_count_o <= cfg_addr_count;
          req_cfg_addr_cfg_o   <= cfg_entries;
          last_cmd_id_q        <= cfg_cmd_id;
          last_is_cfg_q        <= 1'b1;
          if (cfg_cmd_dec == I2C_CFG_WRITE) req_cfg_write_seen_o <= 1'b1;
          if (cfg_cmd_dec == I2C_CFG_READ)  req_cfg_read_seen_o  <= 1'b1;
        end
      end
    end
  end

  always_comb begin
    tx_packet_valid_o = 1'b0;
    tx_packet_o       = '0;
    tx_packet_len_o   = '0;
    if (resp_bulk_ack_valid_i && !last_is_cfg_q) begin
      tx_packet_valid_o = 1'b1;
      tx_packet_o       = ack_pkt;
      tx_packet_len_o   = ack_len;
    end else if (resp_bulk_read_valid_i && !last_is_cfg_q) begin
      tx_packet_valid_o = 1'b1;
      tx_packet_o       = rd_pkt;
      tx_packet_len_o   = rd_len;
    end else if (resp_cfg_ack_valid_i && last_is_cfg_q) begin
      tx_packet_valid_o = 1'b1;
      tx_packet_o       = cfg_ack_pkt;
      tx_packet_len_o   = cfg_ack_len;
    end else if (resp_cfg_read_valid_i && last_is_cfg_q) begin
      tx_packet_valid_o = 1'b1;
      tx_packet_o       = cfg_rd_pkt;
      tx_packet_len_o   = cfg_rd_len;
    end
  end

endmodule

`default_nettype wire
