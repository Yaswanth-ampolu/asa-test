`timescale 1ns/1ps
`default_nettype none

module spi_asd_rx
  import asa_asep_pkg::*;
  import asa_spi_asep_pkg::*;
(
  input  logic            clk,
  input  logic            rst,
  input  logic            soft_reset_i,
  input  logic            rx_valid_i,
  input  asep_packet_t    rx_packet_i,
  input  logic [11:0]     rx_packet_len_i,
  input  logic [7:0]      spi_stc_i,
  output logic [15:0]     spi_cfg_shadow_o,
  output logic [15:0]     spi_min_idle_shadow_o,
  output logic            cfg_packet_seen_o,
  output logic            data_packet_seen_o,
  output logic            irq_packet_seen_o,
  output spi_cfg_cmd_e    cfg_cmd_o,
  output logic            reduce_latency_o,
  output logic [3:0]      csn_o,
  output spi_pkt_status_e pkt_status_o,
  output logic [7:0]      spi_len_o,
  output logic [29:0]     last_cs_pos_o,
  output spi_op_status_e  op_status_o,
  output logic            irq_flag_o,
  output logic            reset_req_o,
  output logic [7:0]      irq_count_o,
  output spi_symbol_vec_t symbols_o,
  output logic            crc_error_o,
  output logic            pkt_id_gap_o,
  output logic            format_error_o,
  output logic            stc_rx_err_o
);

  logic [6:0] last_pkt_id_q;
  logic       seen_pkt_id_q;
  logic [7:0] miss_count_q;

  logic dec_is_irq, dec_reduce, dec_irq_flag, dec_reset;
  logic [6:0] dec_pkt_id;
  logic [7:0] dec_irq_count, dec_spi_len;
  logic [3:0] dec_csn;
  logic [29:0] dec_last_cs;
  spi_pkt_status_e dec_pkt_status;
  spi_op_status_e  dec_op_status;
  spi_symbol_vec_t dec_symbols;
  logic dec_crc_error, dec_format_error;
  spi_data_codec u_dec(
    .encode_i(1'b0), .decode_i(rx_valid_i), .is_interrupt_i(1'b0),
    .pkt_id_i('0), .irq_count_i('0), .ts_mode_i(ASEP_TS_NONE), .ts_value_i('0),
    .reduce_latency_i('0), .csn_i('0), .pkt_status_i(SPI_PKT_VOID), .spi_len_i('0),
    .last_cs_pos_i('0), .op_status_i(SPI_OP_NORMAL), .irq_flag_i('0), .reset_req_i('0),
    .symbols_i('0), .packet_i(rx_packet_i), .packet_len_i(rx_packet_len_i),
    .packet_o(), .packet_len_o(), .is_interrupt_o(dec_is_irq), .pkt_id_o(dec_pkt_id),
    .irq_count_o(dec_irq_count), .reduce_latency_o(dec_reduce), .csn_o(dec_csn),
    .pkt_status_o(dec_pkt_status), .spi_len_o(dec_spi_len), .last_cs_pos_o(dec_last_cs),
    .op_status_o(dec_op_status), .irq_flag_o(dec_irq_flag), .reset_req_o(dec_reset),
    .symbols_o(dec_symbols), .crc_error_o(dec_crc_error), .format_error_o(dec_format_error)
  );

  always_ff @(posedge clk) begin
    if (rst || soft_reset_i) begin
      spi_cfg_shadow_o      <= 16'd0;
      spi_min_idle_shadow_o <= 16'd0;
      cfg_packet_seen_o     <= 1'b0;
      data_packet_seen_o    <= 1'b0;
      irq_packet_seen_o     <= 1'b0;
      cfg_cmd_o             <= SPI_CFG_WRITE;
      reduce_latency_o      <= 1'b0;
      csn_o                 <= 4'd0;
      pkt_status_o          <= SPI_PKT_VOID;
      spi_len_o             <= 8'd0;
      last_cs_pos_o         <= 30'd0;
      op_status_o           <= SPI_OP_NORMAL;
      irq_flag_o            <= 1'b0;
      reset_req_o           <= 1'b0;
      irq_count_o           <= 8'd0;
      symbols_o             <= '0;
      crc_error_o           <= 1'b0;
      pkt_id_gap_o          <= 1'b0;
      format_error_o        <= 1'b0;
      stc_rx_err_o          <= 1'b0;
      last_pkt_id_q         <= 7'd0;
      seen_pkt_id_q         <= 1'b0;
      miss_count_q          <= 8'd0;
    end else begin
      cfg_packet_seen_o  <= 1'b0;
      data_packet_seen_o <= 1'b0;
      irq_packet_seen_o  <= 1'b0;
      crc_error_o        <= 1'b0;
      pkt_id_gap_o       <= 1'b0;
      format_error_o     <= 1'b0;
      stc_rx_err_o       <= 1'b0;

      if (!rx_valid_i && seen_pkt_id_q && (spi_stc_i != 8'd0)) begin
        if (miss_count_q >= spi_stc_i) stc_rx_err_o <= 1'b1;
        else miss_count_q <= miss_count_q + 8'd1;
      end

      if (rx_valid_i) begin
        logic [7:0] rx_b1;
        logic [7:0] rx_hdr;
        logic [6:0] rx_pkt_id;
        int unsigned hdr_idx;
        logic [31:0] crc_calc;
        logic [31:0] crc_seen;
        miss_count_q <= 8'd0;
        rx_b1  = asep_get_byte(rx_packet_i, 1);
        hdr_idx = (asep_ts_mode_e'(rx_b1[1:0]) == ASEP_TS_NONE) ? 2 : 6;
        rx_hdr = asep_get_byte(rx_packet_i, hdr_idx);
        rx_pkt_id = rx_hdr[6:0];
        crc_calc = asep_crc32(rx_packet_i, rx_packet_len_i - 4);
        crc_seen = {asep_get_byte(rx_packet_i, rx_packet_len_i - 4),
                    asep_get_byte(rx_packet_i, rx_packet_len_i - 3),
                    asep_get_byte(rx_packet_i, rx_packet_len_i - 2),
                    asep_get_byte(rx_packet_i, rx_packet_len_i - 1)};
        if (crc_calc != crc_seen) begin
          crc_error_o <= 1'b1;
        end else if (!rx_hdr[7] && (rx_pkt_id != 7'd127)) begin
          logic [7:0] cmd_byte;
          logic [7:0] cfg_b4;
          if ((rx_pkt_id == 7'd0) || (rx_pkt_id > 7'd120)) begin
            format_error_o <= 1'b1;
          end else begin
            if (seen_pkt_id_q && (rx_pkt_id != spi_next_pkt_id(last_pkt_id_q))) pkt_id_gap_o <= 1'b1;
            last_pkt_id_q <= rx_pkt_id;
            seen_pkt_id_q <= 1'b1;
            cfg_packet_seen_o <= 1'b1;
            cmd_byte = asep_get_byte(rx_packet_i, hdr_idx + 1);
            cfg_cmd_o <= spi_cfg_cmd_e'(cmd_byte[7:6]);
            if (spi_cfg_cmd_e'(cmd_byte[7:6]) != SPI_CFG_READ) begin
              spi_min_idle_shadow_o[7:0] <= asep_get_byte(rx_packet_i, hdr_idx + 2);
              cfg_b4 = asep_get_byte(rx_packet_i, hdr_idx + 3);
              spi_cfg_shadow_o[13:12] <= cfg_b4[1:0];
              spi_cfg_shadow_o[11:4]  <= asep_get_byte(rx_packet_i, hdr_idx + 4);
            end
          end
        end else if (dec_format_error) begin
          format_error_o <= 1'b1;
        end else begin
          if (dec_is_irq) begin
            irq_packet_seen_o <= 1'b1;
            csn_o             <= dec_csn;
            irq_count_o       <= dec_irq_count;
            op_status_o       <= dec_op_status;
            irq_flag_o        <= dec_irq_flag;
            reset_req_o       <= dec_reset;
          end else if (dec_pkt_id == 7'd0 || dec_pkt_id > 7'd120) begin
            format_error_o <= 1'b1;
          end else begin
            if (seen_pkt_id_q && (dec_pkt_id != spi_next_pkt_id(last_pkt_id_q))) pkt_id_gap_o <= 1'b1;
            last_pkt_id_q <= dec_pkt_id;
            seen_pkt_id_q <= 1'b1;
            reduce_latency_o <= dec_reduce;
            csn_o            <= dec_csn;
            pkt_status_o     <= dec_pkt_status;
            spi_len_o        <= dec_spi_len;
            last_cs_pos_o    <= dec_last_cs;
            op_status_o      <= dec_op_status;
            irq_flag_o       <= dec_irq_flag;
            reset_req_o      <= dec_reset;
            symbols_o        <= dec_symbols;
            data_packet_seen_o <= 1'b1;
          end
        end
      end
    end
  end

endmodule

`default_nettype wire
