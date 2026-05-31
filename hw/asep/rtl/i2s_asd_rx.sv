`timescale 1ns/1ps
`default_nettype none

module i2s_asd_rx
  import asa_asep_pkg::*;
  import asa_i2s_asep_pkg::*;
(
  input  logic            clk,
  input  logic            rst,
  input  logic            soft_reset_i,
  input  asep_ts_mode_e   cfg_ts_mode_i,
  input  logic [31:0]     cfg_ts_value_i,
  input  logic            rx_packet_valid_i,
  input  asep_packet_t    rx_packet_i,
  input  logic [11:0]     rx_packet_len_i,
  input  logic            tx_build_cfg_resp_i,
  input  i2s_cfg_cmd_e    tx_cfg_resp_cmd_i,
  input  logic            tx_cfg_ack_ok_i,
  output logic            tx_packet_valid_o,
  output asep_packet_t    tx_packet_o,
  output logic [11:0]     tx_packet_len_o,
  output logic            cfg_seen_o,
  output logic            data_seen_o,
  output logic [6:0]      cfg_pkt_id_o,
  output logic [6:0]      data_pkt_id_o,
  output i2s_cfg_cmd_e    cfg_cmd_o,
  output logic            cfg_ack_ok_o,
  output i2s_bit_depth_e  bit_depth_o,
  output i2s_data_fmt_e   data_fmt_o,
  output logic [2:0]      num_channels_o,
  output logic [4:0]      sample_rate_o,
  output logic            timing_host_rx_o,
  output logic            target_clk_mck_o,
  output logic [9:0]      coeff_k_o,
  output logic [15:0]     divisor_n_o,
  output logic [23:0]     start_ptb_stamp_o,
  output logic            timestamps_only_o,
  output logic [8:0]      word_count_o,
  output i2s_word_vec_t   words_o,
  output logic            cfg_crc_error_o,
  output logic            data_crc_error_o,
  output logic            cfg_format_error_o,
  output logic            data_format_error_o,
  output logic            cfg_pkt_id_gap_o,
  output logic            data_pkt_id_gap_o
);

  logic cfg_seen, data_seen;
  logic [6:0] cfg_pkt_id, data_pkt_id;
  i2s_cfg_cmd_e cfg_cmd;
  logic cfg_ack_ok;
  i2s_bit_depth_e cfg_bit_depth;
  i2s_data_fmt_e cfg_data_fmt;
  logic [2:0] cfg_num_channels;
  logic [4:0] cfg_sample_rate;
  logic cfg_timing_host_rx, cfg_target_clk_mck;
  logic [9:0] cfg_coeff_k;
  logic [15:0] cfg_div_n;
  logic data_ts_only;
  logic [9:0] data_len_unused;
  logic [23:0] data_start_stamp;
  logic [8:0] data_word_count;
  i2s_word_vec_t data_words;
  logic cfg_crc_err, cfg_fmt_err, data_crc_err, data_fmt_err;

  logic [6:0] last_cfg_pkt_id_q, last_data_pkt_id_q;
  logic       have_cfg_q, have_data_q;

  asep_packet_t cfg_resp_pkt;
  logic [11:0]  cfg_resp_len;

  i2s_cfg_codec u_cfg_dec(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .pkt_id_i('0), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0),
    .cmd_i(I2S_CFG_WRITE), .ack_ok_i(1'b0), .bit_depth_i(I2S_DEPTH_8), .data_fmt_i(I2S_FMT_I2S),
    .num_channels_i('0), .sample_rate_i('0), .timing_host_rx_i('0), .target_clk_mck_i('0), .coeff_k_i('0), .divisor_n_i('0),
    .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i), .packet_o(), .packet_len_o(), .seen_o(cfg_seen), .pkt_id_o(cfg_pkt_id),
    .cmd_o(cfg_cmd), .ack_ok_o(cfg_ack_ok), .bit_depth_o(cfg_bit_depth), .data_fmt_o(cfg_data_fmt), .num_channels_o(cfg_num_channels),
    .sample_rate_o(cfg_sample_rate), .timing_host_rx_o(cfg_timing_host_rx), .target_clk_mck_o(cfg_target_clk_mck),
    .coeff_k_o(cfg_coeff_k), .divisor_n_o(cfg_div_n), .crc_error_o(cfg_crc_err), .format_error_o(cfg_fmt_err)
  );

  i2s_data_codec u_data_dec(
    .encode_i(1'b0), .decode_i(rx_packet_valid_i), .pkt_id_i('0), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0),
    .start_ptb_stamp_i('0), .bit_depth_i(bit_depth_o), .timestamps_only_i('0), .data_len_i('0), .word_count_i('0), .words_i('0),
    .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i), .packet_o(), .packet_len_o(), .seen_o(data_seen), .pkt_id_o(data_pkt_id),
    .data_len_o(data_len_unused), .start_ptb_stamp_o(data_start_stamp), .timestamps_only_o(data_ts_only),
    .word_count_o(data_word_count), .words_o(data_words), .crc_error_o(data_crc_err), .format_error_o(data_fmt_err)
  );

  i2s_cfg_codec u_cfg_resp_enc(
    .encode_i(1'b1), .decode_i(1'b0), .pkt_id_i(cfg_pkt_id_o), .ts_mode_i(cfg_ts_mode_i), .ts_value_i(cfg_ts_value_i),
    .cmd_i(tx_cfg_resp_cmd_i), .ack_ok_i(tx_cfg_ack_ok_i), .bit_depth_i(bit_depth_o), .data_fmt_i(data_fmt_o),
    .num_channels_i(num_channels_o), .sample_rate_i(sample_rate_o), .timing_host_rx_i(timing_host_rx_o), .target_clk_mck_i(target_clk_mck_o),
    .coeff_k_i(coeff_k_o), .divisor_n_i(divisor_n_o), .packet_i('0), .packet_len_i('0), .packet_o(cfg_resp_pkt),
    .packet_len_o(cfg_resp_len), .seen_o(), .pkt_id_o(), .cmd_o(), .ack_ok_o(), .bit_depth_o(), .data_fmt_o(), .num_channels_o(),
    .sample_rate_o(), .timing_host_rx_o(), .target_clk_mck_o(), .coeff_k_o(), .divisor_n_o(), .crc_error_o(), .format_error_o()
  );

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      bit_depth_o        <= I2S_DEPTH_8;
      data_fmt_o         <= I2S_FMT_I2S;
      num_channels_o     <= 3'd0;
      sample_rate_o      <= 5'd0;
      timing_host_rx_o   <= 1'b0;
      target_clk_mck_o   <= 1'b0;
      coeff_k_o          <= 10'd0;
      divisor_n_o        <= 16'd0;
      cfg_pkt_id_o       <= 7'd0;
      data_pkt_id_o      <= 7'd0;
      cfg_cmd_o          <= I2S_CFG_WRITE;
      cfg_ack_ok_o       <= 1'b0;
      start_ptb_stamp_o  <= 24'd0;
      timestamps_only_o  <= 1'b0;
      word_count_o       <= 9'd0;
      words_o            <= '0;
      cfg_crc_error_o    <= 1'b0;
      data_crc_error_o   <= 1'b0;
      cfg_format_error_o <= 1'b0;
      data_format_error_o<= 1'b0;
      cfg_pkt_id_gap_o   <= 1'b0;
      data_pkt_id_gap_o  <= 1'b0;
      cfg_seen_o         <= 1'b0;
      data_seen_o        <= 1'b0;
      last_cfg_pkt_id_q  <= 7'd0;
      last_data_pkt_id_q <= 7'd0;
      have_cfg_q         <= 1'b0;
      have_data_q        <= 1'b0;
    end else begin
      cfg_crc_error_o    <= 1'b0;
      data_crc_error_o   <= 1'b0;
      cfg_format_error_o <= 1'b0;
      data_format_error_o<= 1'b0;
      cfg_pkt_id_gap_o   <= 1'b0;
      data_pkt_id_gap_o  <= 1'b0;
      cfg_seen_o         <= 1'b0;
      data_seen_o        <= 1'b0;
      if (soft_reset_i) begin
        have_cfg_q        <= 1'b0;
        have_data_q       <= 1'b0;
        last_cfg_pkt_id_q <= 7'd0;
        last_data_pkt_id_q<= 7'd0;
      end else if (rx_packet_valid_i) begin
        if (cfg_crc_err) cfg_crc_error_o <= 1'b1;
        if (data_crc_err) data_crc_error_o <= 1'b1;
        if (cfg_fmt_err) cfg_format_error_o <= 1'b1;
        if (data_fmt_err) data_format_error_o <= 1'b1;
        if (cfg_seen) begin
          cfg_seen_o       <= 1'b1;
          cfg_pkt_id_o     <= cfg_pkt_id;
          cfg_cmd_o        <= cfg_cmd;
          cfg_ack_ok_o     <= cfg_ack_ok;
          bit_depth_o      <= cfg_bit_depth;
          data_fmt_o       <= cfg_data_fmt;
          num_channels_o   <= cfg_num_channels;
          sample_rate_o    <= cfg_sample_rate;
          timing_host_rx_o <= cfg_timing_host_rx;
          target_clk_mck_o <= cfg_target_clk_mck;
          coeff_k_o        <= cfg_coeff_k;
          divisor_n_o      <= cfg_div_n;
          if (have_cfg_q && (cfg_pkt_id != last_cfg_pkt_id_q) &&
              (cfg_pkt_id != i2s_next_pkt_id(last_cfg_pkt_id_q))) begin
            cfg_pkt_id_gap_o <= 1'b1;
          end
          have_cfg_q        <= 1'b1;
          last_cfg_pkt_id_q <= cfg_pkt_id;
        end
        if (data_seen) begin
          data_seen_o       <= 1'b1;
          data_pkt_id_o     <= data_pkt_id;
          start_ptb_stamp_o <= data_start_stamp;
          timestamps_only_o <= data_ts_only;
          word_count_o      <= data_word_count;
          words_o           <= data_words;
          if (have_data_q && (data_pkt_id != last_data_pkt_id_q) &&
              (data_pkt_id != i2s_next_pkt_id(last_data_pkt_id_q))) begin
            data_pkt_id_gap_o <= 1'b1;
          end
          have_data_q        <= 1'b1;
          last_data_pkt_id_q <= data_pkt_id;
        end
      end
    end
  end

  assign tx_packet_valid_o = tx_build_cfg_resp_i;
  assign tx_packet_o       = cfg_resp_pkt;
  assign tx_packet_len_o   = cfg_resp_len;

endmodule

`default_nettype wire
