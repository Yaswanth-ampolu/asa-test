`default_nettype none

package asa_i2c_asep_pkg;
  import asa_asep_pkg::*;

  localparam int unsigned I2C_ADDR_CFG_COUNT = 15;
  typedef logic [(I2C_ADDR_CFG_COUNT*8)-1:0] i2c_addr_cfg_vec_t;

  typedef enum logic [2:0] {
    I2C_BULK_WRITE      = 3'b000,
    I2C_BULK_READ       = 3'b001,
    I2C_BULK_ACK_NACK   = 3'b010,
    I2C_BULK_READ_RESP  = 3'b011
  } i2c_bulk_fmt_e;

  typedef enum logic [2:0] {
    I2C_CFG_WRITE       = 3'b000,
    I2C_CFG_READ        = 3'b001,
    I2C_CFG_ACK_NACK    = 3'b010,
    I2C_CFG_READ_RESP   = 3'b011
  } i2c_cfg_cmd_e;

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

  function automatic logic [31:0] asep_i2c_crc32(
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

  function automatic int unsigned i2c_ts_start_idx(input asep_ts_mode_e mode);
    return (mode == ASEP_TS_NONE) ? 2 : 6;
  endfunction

  function automatic logic [7:0] i2c_common_cmd_byte(
    input logic mode1,
    input logic i2c_error,
    input logic mode0,
    input logic [4:0] low_bits
  );
    return {mode1, i2c_error, mode0, low_bits};
  endfunction

  function automatic logic [7:0] i2c_byte_cmd_byte(
    input logic i2c_error,
    input logic data_valid,
    input logic nack,
    input logic ack,
    input logic stop,
    input logic start_restart
  );
    return i2c_common_cmd_byte(1'b1, i2c_error, 1'b0,
                               {data_valid, nack, ack, stop, start_restart});
  endfunction

  function automatic logic [7:0] i2c_bulk_cmd_byte(
    input logic         i2c_error,
    input logic         current_loc,
    input i2c_bulk_fmt_e fmt
  );
    return i2c_common_cmd_byte(1'b0, i2c_error, 1'b0,
                               {1'b0, current_loc, fmt});
  endfunction

  function automatic logic [7:0] i2c_cfg_cmd_hdr_byte(
    input logic         i2c_error,
    input i2c_cfg_cmd_e cmd
  );
    return i2c_common_cmd_byte(1'b0, i2c_error, 1'b1,
                               {2'b00, cmd});
  endfunction

  function automatic logic [7:0] i2c_cfg_count_byte(input logic [3:0] addr_count);
    return {4'h0, addr_count};
  endfunction

  function automatic logic [7:0] i2c_addr_cfg_entry_pack(
    input logic       offset_16b,
    input logic [6:0] slave_addr
  );
    return {offset_16b, slave_addr};
  endfunction

  function automatic logic i2c_addr_cfg_offset_16b(input logic [7:0] entry);
    return entry[7];
  endfunction

  function automatic logic [6:0] i2c_addr_cfg_slave_addr(input logic [7:0] entry);
    return entry[6:0];
  endfunction

  function automatic logic [7:0] i2c_addr_cfg_get(
    input i2c_addr_cfg_vec_t entries,
    input int unsigned       idx
  );
    return entries[idx*8 +: 8];
  endfunction

  function automatic i2c_addr_cfg_vec_t i2c_addr_cfg_set(
    input i2c_addr_cfg_vec_t entries,
    input int unsigned       idx,
    input logic [7:0]        value
  );
    i2c_addr_cfg_vec_t tmp;
    tmp = entries;
    tmp[idx*8 +: 8] = value;
    return tmp;
  endfunction

  function automatic int unsigned i2c_bulk_ack_payload_bytes(input logic [15:0] ack_len);
    return (ack_len + 16'd10) >> 3;
  endfunction

  function automatic logic [7:0] i2c_ack_payload_get(
    input logic [(ASEP_MAX_PACKET_BYTES*8)-1:0] bytes,
    input int unsigned                          idx
  );
    return bytes[idx*8 +: 8];
  endfunction

  function automatic logic [(ASEP_MAX_PACKET_BYTES*8)-1:0] i2c_ack_payload_set(
    input logic [(ASEP_MAX_PACKET_BYTES*8)-1:0] bytes,
    input int unsigned                          idx,
    input logic [7:0]                           value
  );
    logic [(ASEP_MAX_PACKET_BYTES*8)-1:0] tmp;
    tmp = bytes;
    tmp[idx*8 +: 8] = value;
    return tmp;
  endfunction

  function automatic logic [7:0] i2c_next_cmd_id(input logic [7:0] cur);
    return cur + 8'd1;
  endfunction

endpackage

`default_nettype wire
