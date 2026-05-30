`timescale 1ns/1ps
`default_nettype none

module gpio_cfg_codec
  import asa_asep_pkg::*;
  import asa_gpio_asep_pkg::*;
(
  input  logic          mode2_i,
  input  gpio_cfg_cmd_e cmd_i,
  input  logic          ack_ok_i,
  input  logic [6:0]    pkt_id_i,
  input  asep_ts_mode_e ts_mode_i,
  input  logic [31:0]   ts_value_i,
  input  logic [12:0]   sampling_period_i,
  input  logic          sampling_mode_eg_i,
  input  logic [15:0]   pin_avail_i,
  input  logic [15:0]   pin_dir_i,
  input  logic [15:0]   pin_enable_i,
  input  logic [47:0]   pin_default_i,
  input  logic [31:0]   pin_drv_mode_i,
  input  logic [3:0]    pin_count_i,
  input  logic [15:0]   pin_select_mask_i,
  output asep_packet_t  packet_o,
  output logic [11:0]   packet_len_o
);

  always_comb begin
    asep_packet_t pkt;
    logic [11:0] idx;
    logic [31:0] crc;
    logic [3:0] m_hb;
    logic [3:0] pin_count_eff;

    pkt = '0;
    idx = 12'd0;
    begin
      logic [4:0] popc;
      popc = gpio_popcount16(pin_select_mask_i);
      pin_count_eff = (pin_count_i == 4'd0) ? popc[3:0] : pin_count_i;
    end

    pkt = asep_set_byte(pkt, 0, asep_hdr_byte0(ASEP_STREAM_GPIO, 1'b0));
    pkt = asep_set_byte(pkt, 1, asep_hdr_byte1(ts_mode_i));
    if (ts_mode_i == ASEP_TS_NONE) begin
      m_hb = 4'd1;
      idx  = 12'd2;
    end else begin
      pkt = asep_set_byte(pkt, 2, ts_value_i[31:24]);
      pkt = asep_set_byte(pkt, 3, ts_value_i[23:16]);
      pkt = asep_set_byte(pkt, 4, ts_value_i[15:8]);
      pkt = asep_set_byte(pkt, 5, ts_value_i[7:0]);
      m_hb = 4'd5;
      idx  = 12'd6;
    end

    pkt = asep_set_byte(pkt, idx + 0, gpio_pkt_header_byte(1'b0, pkt_id_i));
    pkt = asep_set_byte(pkt, idx + 1, gpio_cfg_cmd_byte(mode2_i, cmd_i, ack_ok_i, sampling_period_i, pin_count_eff));
    idx = idx + 2;

    if (mode2_i) begin
      pkt = asep_set_byte(pkt, idx + 0, sampling_period_i[7:0]);
      pkt = asep_set_byte(pkt, idx + 1, {(cmd_i == GPIO_CFG_ACK) ? ack_ok_i : sampling_mode_eg_i, 7'd0});
      idx = idx + 2;
    end else if (cmd_i != GPIO_CFG_READ) begin
      int unsigned emitted;
      emitted = 0;
      for (int pin = 0; pin < 16; pin++) begin
        if (pin_select_mask_i[pin] && (emitted < pin_count_eff)) begin
          pkt = asep_set_byte(pkt, idx + 0, {4'h0, pin[3:0]});
          pkt = asep_set_byte(pkt, idx + 1,
            {1'b0,
             pin_dir_i[pin],
             pin_default_i[(pin*3) +: 3],
             pin_drv_mode_i[(pin*2) +: 2],
             pin_enable_i[pin]});
          idx = idx + 2;
          emitted++;
        end
      end
    end

    crc = asep_crc32(pkt, idx);
    pkt = asep_set_byte(pkt, idx + 0, crc[31:24]);
    pkt = asep_set_byte(pkt, idx + 1, crc[23:16]);
    pkt = asep_set_byte(pkt, idx + 2, crc[15:8]);
    pkt = asep_set_byte(pkt, idx + 3, crc[7:0]);
    idx = idx + 4;

    packet_o     = pkt;
    packet_len_o = idx;
  end

endmodule

`default_nettype wire
