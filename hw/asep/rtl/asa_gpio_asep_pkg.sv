`default_nettype none

package asa_gpio_asep_pkg;
  import asa_asep_pkg::*;

  localparam int unsigned GPIO_ASEP_MAX_PINS    = 16;
  localparam int unsigned GPIO_ASEP_MAX_SAMPLES = 256;
  localparam int unsigned GPIO_ASEP_MAX_EDGES   = 128;

  typedef enum logic [1:0] {
    GPIO_CFG_WRITE = 2'b00,
    GPIO_CFG_READ  = 2'b01,
    GPIO_CFG_ACK   = 2'b10,
    GPIO_CFG_RRESP = 2'b11
  } gpio_cfg_cmd_e;

  typedef struct packed {
    logic        mode2;
    gpio_cfg_cmd_e cmd;
    logic        ack_ok;
    logic [3:0]  pin_count_m1;
  } gpio_cfg_meta_t;

  typedef struct packed {
    logic        initial_state;
    logic [3:0]  pin_id;
    logic [5:0]  section;
    logic [12:0] position;
  } gpio_edge_t;

  typedef logic [(GPIO_ASEP_MAX_SAMPLES*16)-1:0] gpio_sample_vec_t;
  typedef logic [(GPIO_ASEP_MAX_EDGES*24)-1:0]   gpio_edge_vec_t;

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

  function automatic logic [6:0] gpio_next_pkt_id(input logic [6:0] cur);
    if ((cur == 7'd0) || (cur == 7'd127)) return 7'd1;
    return cur + 7'd1;
  endfunction

  function automatic logic [4:0] gpio_popcount16(input logic [15:0] mask);
    logic [4:0] count;
    count = 5'd0;
    for (int i = 0; i < 16; i++) count = count + mask[i];
    return count;
  endfunction

  function automatic logic [3:0] gpio_active_pin_at(
    input logic [15:0] mask,
    input int unsigned idx
  );
    int found;
    logic [3:0] pin;
    found = 0;
    pin   = 4'd0;
    for (int i = 0; i < 16; i++) begin
      if (mask[i]) begin
        if (found == idx) pin = i[3:0];
        found++;
      end
    end
    return pin;
  endfunction

  function automatic logic [15:0] gpio_sample_get(
    input gpio_sample_vec_t samples,
    input int unsigned      idx
  );
    return samples[idx*16 +: 16];
  endfunction

  function automatic gpio_sample_vec_t gpio_sample_set(
    input gpio_sample_vec_t samples,
    input int unsigned      idx,
    input logic [15:0]      value
  );
    gpio_sample_vec_t tmp;
    tmp = samples;
    tmp[idx*16 +: 16] = value;
    return tmp;
  endfunction

  function automatic gpio_edge_t gpio_edge_get(
    input gpio_edge_vec_t edges,
    input int unsigned    idx
  );
    return gpio_edge_t'(edges[idx*24 +: 24]);
  endfunction

  function automatic gpio_edge_vec_t gpio_edge_set(
    input gpio_edge_vec_t edges,
    input int unsigned    idx,
    input gpio_edge_t     value
  );
    gpio_edge_vec_t tmp;
    tmp = edges;
    tmp[idx*24 +: 24] = value;
    return tmp;
  endfunction

  function automatic logic [7:0] gpio_pkt_header_byte(input logic is_data_mode, input logic [6:0] pkt_id);
    return {is_data_mode, pkt_id};
  endfunction

  function automatic logic [7:0] gpio_cfg_cmd_byte(
    input logic          mode2,
    input gpio_cfg_cmd_e cmd,
    input logic          ack_ok,
    input logic [12:0]   sampling_period,
    input logic [3:0]    pin_count_m1
  );
    logic [7:0] b;
    b = 8'h00;
    b[7]   = mode2;
    b[6:5] = cmd;
    if (!mode2) begin
      b[4]   = (cmd == GPIO_CFG_ACK) ? ack_ok : 1'b0;
      b[3:0] = pin_count_m1;
    end else begin
      b[4:0] = sampling_period[12:8];
    end
    return b;
  endfunction

  function automatic logic [15:0] gpio_pin_cfg_pack(
    input logic        avail,
    input logic        dir,
    input logic [2:0]  deflt,
    input logic [1:0]  drv,
    input logic        en
  );
    return {8'h00, avail, dir, deflt, drv, en};
  endfunction

endpackage

`default_nettype wire
