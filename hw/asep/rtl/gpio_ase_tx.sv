`timescale 1ns/1ps
`default_nettype none

module gpio_ase_tx
  import asa_asep_pkg::*;
  import asa_gpio_asep_pkg::*;
(
  input  logic            clk,
  input  logic            rst,
  input  logic            soft_reset_i,
  input  logic            sample_tick_i,
  input  logic            tdd_boundary_i,
  input  logic            build_cfg_i,
  input  logic            build_data_i,
  input  logic            cfg_mode2_i,
  input  gpio_cfg_cmd_e   cfg_cmd_i,
  input  logic            cfg_ack_ok_i,
  input  asep_ts_mode_e   ts_mode_i,
  input  logic [31:0]     ts_value_i,
  input  logic [12:0]     sampling_period_i,
  input  logic            sampling_mode_eg_i,
  input  logic [15:0]     tx_active_mask_i,
  input  logic [15:0]     pin_avail_i,
  input  logic [15:0]     pin_dir_i,
  input  logic [15:0]     pin_enable_i,
  input  logic [47:0]     pin_default_i,
  input  logic [31:0]     pin_drv_mode_i,
  input  logic [3:0]      cfg_pin_count_i,
  input  logic [15:0]     cfg_pin_select_mask_i,
  input  logic [15:0]     gpio_pin_in_i,
  output logic            packet_valid_o,
  output asep_packet_t    packet_o,
  output logic [11:0]     packet_len_o,
  output logic [6:0]      packet_id_o,
  output logic [9:0]      sample_count_o,
  output logic [9:0]      edge_count_o,
  output logic            data_build_error_o
);

  logic [6:0] pkt_id_q;
  logic advance_pkt_id;
  gpio_sample_vec_t fs_samples_q, fs_samples_n;
  gpio_edge_vec_t eg_edges_q, eg_edges_n;
  logic [9:0] fs_count_q, fs_count_n, eg_count_q, eg_count_n;
  logic [15:0] prev_sample_q, prev_sample_n;
  logic        prev_valid_q, prev_valid_n;
  logic [5:0]  section_q, section_n;
  logic [12:0] position_q, position_n;

  asep_packet_t cfg_packet;
  logic [11:0]  cfg_packet_len;
  asep_packet_t fs_payload;
  logic [10:0]  fs_payload_len;
  gpio_sample_vec_t fs_decode_unused;
  logic [9:0]   fs_decode_cnt_unused;
  logic         fs_codec_err;
  asep_packet_t eg_payload;
  logic [10:0]  eg_payload_len;
  gpio_edge_vec_t eg_decode_unused;
  logic [9:0]   eg_decode_cnt_unused;
  logic         eg_codec_err;

  gpio_pkt_id_counter u_pkt_id (
    .clk(clk),
    .rst(rst),
    .soft_reset_i(soft_reset_i),
    .advance_i(advance_pkt_id),
    .pkt_id_o(pkt_id_q)
  );

  gpio_cfg_codec u_cfg (
    .mode2_i(cfg_mode2_i),
    .cmd_i(cfg_cmd_i),
    .ack_ok_i(cfg_ack_ok_i),
    .pkt_id_i(pkt_id_q),
    .ts_mode_i(ts_mode_i),
    .ts_value_i(ts_value_i),
    .sampling_period_i(sampling_period_i),
    .sampling_mode_eg_i(sampling_mode_eg_i),
    .pin_avail_i(pin_avail_i),
    .pin_dir_i(pin_dir_i),
    .pin_enable_i(pin_enable_i),
    .pin_default_i(pin_default_i),
    .pin_drv_mode_i(pin_drv_mode_i),
    .pin_count_i(cfg_pin_count_i),
    .pin_select_mask_i(cfg_pin_select_mask_i),
    .packet_o(cfg_packet),
    .packet_len_o(cfg_packet_len)
  );

  gpio_fs_codec u_fs (
    .encode_i(1'b1),
    .decode_i(1'b0),
    .active_mask_i(tx_active_mask_i),
    .sample_count_i(fs_count_q),
    .samples_i(fs_samples_q),
    .payload_i('0),
    .payload_len_i('0),
    .payload_o(fs_payload),
    .payload_len_o(fs_payload_len),
    .samples_o(fs_decode_unused),
    .sample_count_o(fs_decode_cnt_unused),
    .error_o(fs_codec_err)
  );

  gpio_eg_codec u_eg (
    .encode_i(1'b1),
    .decode_i(1'b0),
    .edge_count_i(eg_count_q),
    .edges_i(eg_edges_q),
    .payload_i('0),
    .payload_len_i('0),
    .payload_o(eg_payload),
    .payload_len_o(eg_payload_len),
    .edges_o(eg_decode_unused),
    .edge_count_o(eg_decode_cnt_unused),
    .error_o(eg_codec_err)
  );

  always_comb begin
    fs_samples_n = fs_samples_q;
    eg_edges_n   = eg_edges_q;
    fs_count_n   = fs_count_q;
    eg_count_n   = eg_count_q;
    prev_sample_n= prev_sample_q;
    prev_valid_n = prev_valid_q;
    section_n    = section_q;
    position_n   = position_q;

    if (tdd_boundary_i) begin
      section_n  = section_q + 6'd1;
      position_n = 13'd0;
    end

    if (sample_tick_i && (sampling_period_i != 13'd0)) begin
      logic [15:0] sample_masked;
      sample_masked = gpio_pin_in_i & tx_active_mask_i;
      if (sampling_mode_eg_i) begin
        if (prev_valid_q) begin
          logic [15:0] delta;
          delta = sample_masked ^ prev_sample_q;
          for (int pin = 0; pin < 16; pin++) begin
            if (delta[pin] && tx_active_mask_i[pin] && (eg_count_n < GPIO_ASEP_MAX_EDGES)) begin
              gpio_edge_t e;
              e.initial_state = prev_sample_q[pin];
              e.pin_id   = pin[3:0];
              e.section  = section_q;
              e.position = position_q;
              eg_edges_n = gpio_edge_set(eg_edges_n, eg_count_n, e);
              eg_count_n = eg_count_n + 10'd1;
            end
          end
        end
      end else begin
        if (fs_count_n < GPIO_ASEP_MAX_SAMPLES) begin
          fs_samples_n = gpio_sample_set(fs_samples_n, fs_count_n, sample_masked);
          fs_count_n   = fs_count_n + 10'd1;
        end
      end
      prev_sample_n = sample_masked;
      prev_valid_n  = 1'b1;
      position_n    = position_q + sampling_period_i;
    end

    if (build_data_i) begin
      fs_samples_n = '0;
      eg_edges_n   = '0;
      fs_count_n   = 10'd0;
      eg_count_n   = 10'd0;
      prev_valid_n = 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (rst || soft_reset_i) begin
      fs_samples_q <= '0;
      eg_edges_q   <= '0;
      fs_count_q   <= 10'd0;
      eg_count_q   <= 10'd0;
      prev_sample_q<= 16'h0000;
      prev_valid_q <= 1'b0;
      section_q    <= 6'd0;
      position_q   <= 13'd0;
    end else begin
      fs_samples_q <= fs_samples_n;
      eg_edges_q   <= eg_edges_n;
      fs_count_q   <= fs_count_n;
      eg_count_q   <= eg_count_n;
      prev_sample_q<= prev_sample_n;
      prev_valid_q <= prev_valid_n;
      section_q    <= section_n;
      position_q   <= position_n;
    end
  end

  always_comb begin
    asep_packet_t pkt;
    logic [11:0] idx;
    logic [31:0] crc;
    logic [3:0]  m_hb;
    logic [9:0]  data_count;
    logic [10:0] payload_len;
    asep_packet_t payload;

    pkt = '0;
    idx = 12'd0;
    data_count = sampling_mode_eg_i ? eg_count_q : fs_count_q;
    payload_len = sampling_mode_eg_i ? eg_payload_len : fs_payload_len;
    payload = sampling_mode_eg_i ? eg_payload : fs_payload;

    packet_valid_o = 1'b0;
    packet_len_o   = 12'd0;
    packet_o       = '0;
    advance_pkt_id = 1'b0;
    data_build_error_o = 1'b0;

    if (build_cfg_i) begin
      packet_valid_o = 1'b1;
      packet_o       = cfg_packet;
      packet_len_o   = cfg_packet_len;
      advance_pkt_id = 1'b1;
    end else if (build_data_i) begin
      if ((sampling_period_i == 13'd0) || (data_count == 10'd0)) begin
        data_build_error_o = 1'b1;
      end else begin
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
        pkt = asep_set_byte(pkt, idx + 0, gpio_pkt_header_byte(1'b1, pkt_id_q));
        pkt = asep_set_byte(pkt, idx + 1, {sampling_mode_eg_i, 5'd0, data_count[9:8]});
        pkt = asep_set_byte(pkt, idx + 2, data_count[7:0]);
        pkt = asep_set_byte(pkt, idx + 3, tx_active_mask_i[15:8]);
        pkt = asep_set_byte(pkt, idx + 4, tx_active_mask_i[7:0]);
        idx = idx + 5;
        for (int i = 0; i < payload_len; i++) begin
          pkt = asep_set_byte(pkt, idx + i, asep_get_byte(payload, i));
        end
        idx = idx + payload_len;
        crc = asep_crc32(pkt, idx);
        pkt = asep_set_byte(pkt, idx + 0, crc[31:24]);
        pkt = asep_set_byte(pkt, idx + 1, crc[23:16]);
        pkt = asep_set_byte(pkt, idx + 2, crc[15:8]);
        pkt = asep_set_byte(pkt, idx + 3, crc[7:0]);
        idx = idx + 4;
        packet_valid_o = 1'b1;
        packet_o       = pkt;
        packet_len_o   = idx;
        advance_pkt_id = 1'b1;
      end
    end

    packet_id_o    = pkt_id_q;
    sample_count_o = fs_count_q;
    edge_count_o   = eg_count_q;
  end

endmodule

`default_nettype wire
