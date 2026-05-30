`timescale 1ns/1ps
`default_nettype none

module spi_data_codec
  import asa_asep_pkg::*;
  import asa_spi_asep_pkg::*;
(
  input  logic            encode_i,
  input  logic            decode_i,
  input  logic            is_interrupt_i,
  input  logic [6:0]      pkt_id_i,
  input  logic [7:0]      irq_count_i,
  input  asep_ts_mode_e   ts_mode_i,
  input  logic [31:0]     ts_value_i,
  input  logic            reduce_latency_i,
  input  logic [3:0]      csn_i,
  input  spi_pkt_status_e pkt_status_i,
  input  logic [7:0]      spi_len_i,
  input  logic [29:0]     last_cs_pos_i,
  input  spi_op_status_e  op_status_i,
  input  logic            irq_flag_i,
  input  logic            reset_req_i,
  input  spi_symbol_vec_t symbols_i,
  input  asep_packet_t    packet_i,
  input  logic [11:0]     packet_len_i,
  output asep_packet_t    packet_o,
  output logic [11:0]     packet_len_o,
  output logic            is_interrupt_o,
  output logic [6:0]      pkt_id_o,
  output logic [7:0]      irq_count_o,
  output logic            reduce_latency_o,
  output logic [3:0]      csn_o,
  output spi_pkt_status_e pkt_status_o,
  output logic [7:0]      spi_len_o,
  output logic [29:0]     last_cs_pos_o,
  output spi_op_status_e  op_status_o,
  output logic            irq_flag_o,
  output logic            reset_req_o,
  output spi_symbol_vec_t symbols_o,
  output logic            crc_error_o,
  output logic            format_error_o
);

  function automatic logic [7:0] get_flat_bit(
    input spi_symbol_vec_t syms,
    input int unsigned     sym_count,
    input int unsigned     byte_idx
  );
    logic [7:0] b;
    int unsigned bit_idx;
    spi_symbol_t s;
    b = 8'h00;
    for (int k = 0; k < 8; k++) begin
      bit_idx = byte_idx*8 + k;
      if (bit_idx < sym_count*10) begin
        s = spi_symbol_get(syms, bit_idx / 10);
        case (bit_idx % 10)
          0: b[7-k] = s.cs1;
          1: b[7-k] = s.cs0;
          default: b[7-k] = s.data[9 - (bit_idx % 10)];
        endcase
      end else begin
        b[7-k] = 1'b0;
      end
    end
    return b;
  endfunction

  function automatic spi_symbol_vec_t decode_flat(
    input asep_packet_t packet,
    input int unsigned  start_idx,
    input int unsigned  sym_count
  );
    spi_symbol_vec_t outv;
    spi_symbol_t s;
    int unsigned bit_idx;
    logic bitv;
    logic [7:0] pkt_byte;
    outv = '0;
    for (int sym = 0; sym < sym_count; sym++) begin
      s = '0;
      for (int j = 0; j < 10; j++) begin
        bit_idx = sym*10 + j;
        pkt_byte = asep_get_byte(packet, start_idx + (bit_idx / 8));
        bitv = pkt_byte[7 - (bit_idx % 8)];
        case (j)
          0: s.cs1 = bitv;
          1: s.cs0 = bitv;
          default: s.data[9-j] = bitv;
        endcase
      end
      outv = spi_symbol_set(outv, sym, s);
    end
    return outv;
  endfunction

  always_comb begin
    packet_o         = '0;
    packet_len_o     = '0;
    is_interrupt_o   = 1'b0;
    pkt_id_o         = 7'd0;
    irq_count_o      = 8'd0;
    reduce_latency_o = 1'b0;
    csn_o            = 4'd0;
    pkt_status_o     = SPI_PKT_VOID;
    spi_len_o        = 8'd0;
    last_cs_pos_o    = 30'd0;
    op_status_o      = SPI_OP_NORMAL;
    irq_flag_o       = 1'b0;
    reset_req_o      = 1'b0;
    symbols_o        = '0;
    crc_error_o      = 1'b0;
    format_error_o   = 1'b0;

    if (encode_i) begin
      asep_packet_t pkt;
      logic [31:0] crc;
      int unsigned idx;
      int unsigned coded_len;
      logic [7:0] pkt_byte;
      pkt = '0;
      pkt = asep_set_byte(pkt, 0, asep_hdr_byte0(ASEP_STREAM_SPI, 1'b0));
      pkt = asep_set_byte(pkt, 1, asep_hdr_byte1(ts_mode_i));
      if (ts_mode_i == ASEP_TS_NONE) begin
        idx = 2;
      end else begin
        pkt = asep_set_byte(pkt, 2, ts_value_i[31:24]);
        pkt = asep_set_byte(pkt, 3, ts_value_i[23:16]);
        pkt = asep_set_byte(pkt, 4, ts_value_i[15:8]);
        pkt = asep_set_byte(pkt, 5, ts_value_i[7:0]);
        idx = 6;
      end

      pkt = asep_set_byte(pkt, idx + 0, spi_pkt_header_byte(!is_interrupt_i, is_interrupt_i ? 7'd127 : pkt_id_i));
      if (is_interrupt_i) begin
        pkt = asep_set_byte(pkt, idx + 1, {2'b00, csn_i, 2'b00});
        pkt = asep_set_byte(pkt, idx + 2, irq_count_i);
        pkt = asep_set_byte(pkt, idx + 3, {irq_flag_i, 1'b0, op_status_i, 1'b0, reset_req_i});
        idx = idx + 4;
      end else begin
        coded_len = spi_coded_len(spi_len_i);
        pkt = asep_set_byte(pkt, idx + 1, {1'b0, reduce_latency_i, csn_i, pkt_status_i});
        pkt = asep_set_byte(pkt, idx + 2, spi_len_i);
        pkt = asep_set_byte(pkt, idx + 3, {2'b00, last_cs_pos_i[29:24]});
        pkt = asep_set_byte(pkt, idx + 4, last_cs_pos_i[23:16]);
        pkt = asep_set_byte(pkt, idx + 5, last_cs_pos_i[15:8]);
        pkt = asep_set_byte(pkt, idx + 6, last_cs_pos_i[7:0]);
        pkt = asep_set_byte(pkt, idx + 7, {3'b000, op_status_i, irq_flag_i, reset_req_i});
        for (int i = 0; i < coded_len; i++) begin
          pkt = asep_set_byte(pkt, idx + 8 + i, get_flat_bit(symbols_i, spi_len_i, i));
        end
        idx = idx + 8 + coded_len;
      end
      crc = asep_crc32(pkt, idx);
      pkt = asep_set_byte(pkt, idx + 0, crc[31:24]);
      pkt = asep_set_byte(pkt, idx + 1, crc[23:16]);
      pkt = asep_set_byte(pkt, idx + 2, crc[15:8]);
      pkt = asep_set_byte(pkt, idx + 3, crc[7:0]);
      packet_o     = pkt;
      packet_len_o = idx + 4;
    end

    if (decode_i) begin
      logic [7:0] b0, b1, hdr;
      logic [31:0] crc_calc, crc_seen;
      int unsigned idx;
      logic [7:0] pkt_byte;
      b0 = asep_get_byte(packet_i, 0);
      b1 = asep_get_byte(packet_i, 1);
      if (b0[7:1] != ASEP_STREAM_SPI) begin
        format_error_o = 1'b1;
      end else begin
        idx = (asep_ts_mode_e'(b1[1:0]) == ASEP_TS_NONE) ? 2 : 6;
        if (packet_len_i < (idx + 4 + 4)) begin
          format_error_o = 1'b1;
        end else begin
          crc_calc = asep_crc32(packet_i, packet_len_i - 4);
          crc_seen = {asep_get_byte(packet_i, packet_len_i - 4),
                      asep_get_byte(packet_i, packet_len_i - 3),
                      asep_get_byte(packet_i, packet_len_i - 2),
                      asep_get_byte(packet_i, packet_len_i - 1)};
          if (crc_calc != crc_seen) begin
            crc_error_o = 1'b1;
          end else begin
            hdr = asep_get_byte(packet_i, idx + 0);
            pkt_id_o       = hdr[6:0];
            is_interrupt_o = spi_is_interrupt_pkt(hdr[6:0]);
            if (is_interrupt_o) begin
              pkt_byte     = asep_get_byte(packet_i, idx + 1);
              csn_o        = pkt_byte[5:2];
              irq_count_o  = asep_get_byte(packet_i, idx + 2);
              pkt_byte     = asep_get_byte(packet_i, idx + 3);
              irq_flag_o   = pkt_byte[7];
              op_status_o  = spi_op_status_e'(pkt_byte[4:2]);
              reset_req_o  = pkt_byte[0];
            end else begin
              logic [7:0] ctrl;
              int unsigned coded_len;
              ctrl = asep_get_byte(packet_i, idx + 1);
              reduce_latency_o = ctrl[6];
              csn_o            = ctrl[5:2];
              pkt_status_o     = spi_pkt_status_e'(ctrl[1:0]);
              spi_len_o        = asep_get_byte(packet_i, idx + 2);
              pkt_byte         = asep_get_byte(packet_i, idx + 3);
              last_cs_pos_o    = {pkt_byte[5:0],
                                  asep_get_byte(packet_i, idx + 4),
                                  asep_get_byte(packet_i, idx + 5),
                                  asep_get_byte(packet_i, idx + 6)};
              pkt_byte         = asep_get_byte(packet_i, idx + 7);
              op_status_o      = spi_op_status_e'(pkt_byte[4:2]);
              irq_flag_o       = pkt_byte[1];
              reset_req_o      = pkt_byte[0];
              coded_len        = spi_coded_len(spi_len_o);
              if (packet_len_i != idx + 8 + coded_len + 4) begin
                format_error_o = 1'b1;
              end else begin
                symbols_o = decode_flat(packet_i, idx + 8, spi_len_o);
              end
            end
          end
        end
      end
    end
  end

endmodule

`default_nettype wire
