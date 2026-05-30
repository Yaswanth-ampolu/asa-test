`default_nettype none

package asa_spi_asep_pkg;
  import asa_asep_pkg::*;

  localparam int unsigned SPI_ASEP_MAX_BYTES       = 128;
  localparam int unsigned SPI_ASEP_MAX_CODED_BYTES = 160;
  localparam int unsigned SPI_ASEP_MAX_BITS        = SPI_ASEP_MAX_BYTES * 10;

  typedef enum logic [1:0] {
    SPI_CFG_WRITE = 2'b00,
    SPI_CFG_READ  = 2'b01,
    SPI_CFG_ACK   = 2'b10,
    SPI_CFG_RRESP = 2'b11
  } spi_cfg_cmd_e;

  typedef enum logic [1:0] {
    SPI_PKT_VOID  = 2'b00,
    SPI_PKT_DUMMY = 2'b01,
    SPI_PKT_VALID = 2'b10
  } spi_pkt_status_e;

  typedef enum logic [2:0] {
    SPI_OP_NORMAL = 3'd0,
    SPI_OP_BUSY   = 3'd1,
    SPI_OP_ERROR  = 3'd2
  } spi_op_status_e;

  typedef struct packed {
    logic       cs1;
    logic       cs0;
    logic [7:0] data;
  } spi_symbol_t;

  typedef logic [(SPI_ASEP_MAX_BYTES*10)-1:0] spi_symbol_vec_t;

  localparam logic [31:0] CRC32_POLY = 32'hF4ACFB13;
  localparam logic [31:0] CRC32_INIT = 32'hFFFFFFFF;
  localparam logic [31:0] CRC32_XOR  = 32'hFFFFFFFF;

  function automatic logic [7:0] reflect_byte(input logic [7:0] b);
    logic [7:0] r;
    for (int i = 0; i < 8; i++) r[i] = b[7-i];
    return r;
  endfunction

  function automatic logic [31:0] reflect32(input logic [31:0] v);
    logic [31:0] r;
    for (int i = 0; i < 32; i++) r[i] = v[31-i];
    return r;
  endfunction

  function automatic logic [31:0] crc32_byte(input logic [31:0] crc, input logic [7:0] data);
    logic [31:0] c;
    logic [7:0] d;
    d = reflect_byte(data);
    c = crc ^ {d, 24'd0};
    for (int i = 0; i < 8; i++) begin
      if (c[31]) c = {c[30:0], 1'b0} ^ CRC32_POLY;
      else       c = {c[30:0], 1'b0};
    end
    return c;
  endfunction

  function automatic logic [31:0] crc32_finalize(input logic [31:0] crc);
    return reflect32(crc) ^ CRC32_XOR;
  endfunction

  function automatic logic [31:0] asep_crc32(
    input asep_packet_t bytes,
    input int unsigned  num_bytes
  );
    logic [31:0] crc;
    crc = CRC32_INIT;
    for (int i = 0; i < num_bytes; i++) begin
      crc = crc32_byte(crc, asep_get_byte(bytes, i));
    end
    return crc32_finalize(crc);
  endfunction

  function automatic logic [6:0] spi_next_pkt_id(input logic [6:0] cur);
    if ((cur == 7'd0) || (cur >= 7'd120) || (cur == 7'd127)) return 7'd1;
    return cur + 7'd1;
  endfunction

  function automatic logic [7:0] spi_next_irq_count(input logic [7:0] cur);
    if ((cur == 8'd0) || (cur >= 8'd127)) return 8'd1;
    return cur + 8'd1;
  endfunction

  function automatic logic [7:0] spi_pkt_header_byte(
    input logic       is_data_mode,
    input logic [6:0] pkt_id
  );
    return {is_data_mode, pkt_id};
  endfunction

  function automatic logic spi_is_interrupt_pkt(input logic [6:0] pkt_id);
    return (pkt_id == 7'd127);
  endfunction

  function automatic int unsigned spi_coded_len(input int unsigned raw_len);
    return (raw_len * 10 + 7) / 8;
  endfunction

  function automatic spi_symbol_t spi_symbol_get(
    input spi_symbol_vec_t symbols,
    input int unsigned     idx
  );
    return spi_symbol_t'(symbols[idx*10 +: 10]);
  endfunction

  function automatic spi_symbol_vec_t spi_symbol_set(
    input spi_symbol_vec_t symbols,
    input int unsigned     idx,
    input spi_symbol_t     value
  );
    spi_symbol_vec_t tmp;
    tmp = symbols;
    tmp[idx*10 +: 10] = value;
    return tmp;
  endfunction

endpackage

`default_nettype wire
