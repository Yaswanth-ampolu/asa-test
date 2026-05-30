`timescale 1ns/1ps
`default_nettype none

module spi_cfg_codec
  import asa_asep_pkg::*;
  import asa_spi_asep_pkg::*;
(
  input  spi_cfg_cmd_e  cmd_i,
  input  logic          ack_ok_i,
  input  logic [6:0]    pkt_id_i,
  input  asep_ts_mode_e ts_mode_i,
  input  logic [31:0]   ts_value_i,
  input  logic [15:0]   spi_cfg_reg_i,
  input  logic [15:0]   spi_min_idle_reg_i,
  output asep_packet_t  packet_o,
  output logic [11:0]   packet_len_o
);

  always_comb begin
    asep_packet_t pkt;
    logic [31:0] crc;
    int unsigned idx;

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

    pkt = asep_set_byte(pkt, idx + 0, spi_pkt_header_byte(1'b0, pkt_id_i));
    pkt = asep_set_byte(pkt, idx + 1, {cmd_i, 4'd0});

    if (cmd_i == SPI_CFG_READ) begin
      idx = idx + 2;
    end else begin
      logic [7:0] b4;
      b4 = {5'd0, ack_ok_i && (cmd_i == SPI_CFG_ACK), spi_cfg_reg_i[13:12]};
      pkt = asep_set_byte(pkt, idx + 2, spi_min_idle_reg_i[7:0]);
      pkt = asep_set_byte(pkt, idx + 3, b4);
      pkt = asep_set_byte(pkt, idx + 4, spi_cfg_reg_i[11:4]);
      idx = idx + 5;
    end

    crc = asep_crc32(pkt, idx);
    pkt = asep_set_byte(pkt, idx + 0, crc[31:24]);
    pkt = asep_set_byte(pkt, idx + 1, crc[23:16]);
    pkt = asep_set_byte(pkt, idx + 2, crc[15:8]);
    pkt = asep_set_byte(pkt, idx + 3, crc[7:0]);
    packet_o = pkt;
    packet_len_o = idx + 4;
  end

endmodule

`default_nettype wire
