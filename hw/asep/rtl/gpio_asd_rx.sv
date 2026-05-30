`timescale 1ns/1ps
`default_nettype none

module gpio_asd_rx
  import asa_asep_pkg::*;
  import asa_gpio_asep_pkg::*;
(
  input  logic            clk,
  input  logic            rst,
  input  logic            soft_reset_i,
  input  logic            rx_valid_i,
  input  asep_packet_t    rx_packet_i,
  input  logic [11:0]     rx_packet_len_i,
  input  logic [15:0]     pin_avail_i,
  output logic [12:0]     sampling_period_o,
  output logic            sampling_mode_eg_o,
  output logic [15:0]     pin_dir_o,
  output logic [15:0]     pin_enable_o,
  output logic [47:0]     pin_default_o,
  output logic [31:0]     pin_drv_mode_o,
  output logic [15:0]     gpio_pin_out_o,
  output logic            cfg_packet_seen_o,
  output logic            data_packet_seen_o,
  output logic            cfg_mode2_o,
  output gpio_cfg_cmd_e   cfg_cmd_o,
  output logic            crc_error_o,
  output logic            pkt_id_gap_o,
  output logic            format_error_o
);

  logic [6:0] last_pkt_id_q;
  logic       seen_pkt_id_q;

  always_ff @(posedge clk) begin
    if (rst || soft_reset_i) begin
      sampling_period_o  <= 13'd0;
      sampling_mode_eg_o <= 1'b0;
      pin_dir_o          <= 16'h0000;
      pin_enable_o       <= 16'h0000;
      pin_default_o      <= '0;
      pin_drv_mode_o     <= '0;
      gpio_pin_out_o     <= 16'h0000;
      cfg_packet_seen_o  <= 1'b0;
      data_packet_seen_o <= 1'b0;
      cfg_mode2_o        <= 1'b0;
      cfg_cmd_o          <= GPIO_CFG_WRITE;
      crc_error_o        <= 1'b0;
      pkt_id_gap_o       <= 1'b0;
      format_error_o     <= 1'b0;
      last_pkt_id_q      <= 7'd0;
      seen_pkt_id_q      <= 1'b0;
    end else begin
      cfg_packet_seen_o  <= 1'b0;
      data_packet_seen_o <= 1'b0;
      crc_error_o        <= 1'b0;
      pkt_id_gap_o       <= 1'b0;
      format_error_o     <= 1'b0;

      if (rx_valid_i) begin
        logic [3:0] m_hb;
        logic [11:0] idx;
        logic [7:0] b0, b1, hdrb;
        logic [6:0] stream_type;
        logic [31:0] crc_calc, crc_seen;
        logic [6:0] pkt_id;
        logic data_mode;

        b0 = asep_get_byte(rx_packet_i, 0);
        b1 = asep_get_byte(rx_packet_i, 1);
        stream_type = b0[7:1];
        m_hb = (asep_ts_mode_e'(b1[1:0]) == ASEP_TS_NONE) ? 4'd1 : 4'd5;
        idx = m_hb + 12'd1;

        if ((stream_type != ASEP_STREAM_GPIO) || (rx_packet_len_i < (idx + 5))) begin
          format_error_o <= 1'b1;
        end else begin
          crc_calc = asep_crc32(rx_packet_i, rx_packet_len_i - 4);
          crc_seen = {asep_get_byte(rx_packet_i, rx_packet_len_i - 4),
                      asep_get_byte(rx_packet_i, rx_packet_len_i - 3),
                      asep_get_byte(rx_packet_i, rx_packet_len_i - 2),
                      asep_get_byte(rx_packet_i, rx_packet_len_i - 1)};
          if (crc_calc != crc_seen) begin
            crc_error_o <= 1'b1;
          end else begin
            hdrb      = asep_get_byte(rx_packet_i, idx);
            data_mode = hdrb[7];
            pkt_id    = hdrb[6:0];
            if (seen_pkt_id_q && (pkt_id != gpio_next_pkt_id(last_pkt_id_q))) begin
              pkt_id_gap_o <= 1'b1;
            end
            last_pkt_id_q <= pkt_id;
            seen_pkt_id_q <= 1'b1;

            if (!data_mode) begin
              logic [7:0] cmd_byte;
              cfg_packet_seen_o <= 1'b1;
              cmd_byte = asep_get_byte(rx_packet_i, idx + 1);
              cfg_mode2_o <= cmd_byte[7];
              cfg_cmd_o   <= gpio_cfg_cmd_e'(cmd_byte[6:5]);
              if (cmd_byte[7]) begin
                if (gpio_cfg_cmd_e'(cmd_byte[6:5]) != GPIO_CFG_READ) begin
                  logic [7:0] mode2_b1;
                  mode2_b1 = asep_get_byte(rx_packet_i, idx + 3);
                  sampling_period_o  <= {cmd_byte[4:0], asep_get_byte(rx_packet_i, idx + 2)};
                  sampling_mode_eg_o <= mode2_b1[7];
                end
              end else begin
                int pin_pairs;
                pin_pairs = cmd_byte[3:0];
                if (gpio_cfg_cmd_e'(cmd_byte[6:5]) != GPIO_CFG_READ) begin
                  for (int i = 0; i < pin_pairs; i++) begin
                    logic [3:0] pin_id;
                    logic [7:0] b0, b1;
                    b0 = asep_get_byte(rx_packet_i, idx + 2 + i*2);
                    b1 = asep_get_byte(rx_packet_i, idx + 3 + i*2);
                    pin_id = b0[3:0];
                    pin_dir_o[pin_id]                        <= b1[6];
                    pin_default_o[(pin_id*3) +: 3]          <= b1[5:3];
                    pin_drv_mode_o[(pin_id*2) +: 2]         <= b1[2:1];
                    pin_enable_o[pin_id]                    <= b1[0];
                  end
                end
              end
            end else begin
              logic eg_mode;
              logic [9:0] data_len;
              logic [11:0] payload_start;
              logic [11:0] payload_bytes;
              logic [15:0] active_mask;
              data_packet_seen_o <= 1'b1;
              b0            = asep_get_byte(rx_packet_i, idx + 1);
              eg_mode       = b0[7];
              data_len      = {b0[1:0], asep_get_byte(rx_packet_i, idx + 2)};
              active_mask   = {asep_get_byte(rx_packet_i, idx + 3), asep_get_byte(rx_packet_i, idx + 4)};
              payload_start = idx + 5;
              payload_bytes = rx_packet_len_i - payload_start - 4;
              if (eg_mode) begin
                logic [15:0] pin_state;
                logic [9:0] edge_count;
                if ((payload_bytes % 3) != 0) begin
                  format_error_o <= 1'b1;
                end else begin
                  edge_count = payload_bytes / 3;
                  if (data_len != edge_count) begin
                    format_error_o <= 1'b1;
                  end
                  pin_state = gpio_pin_out_o;
                  for (int i = 0; i < edge_count; i++) begin
                    gpio_edge_t e;
                    logic [7:0] eb0, eb1, eb2;
                    eb0 = asep_get_byte(rx_packet_i, payload_start + i*3 + 0);
                    eb1 = asep_get_byte(rx_packet_i, payload_start + i*3 + 1);
                    eb2 = asep_get_byte(rx_packet_i, payload_start + i*3 + 2);
                    e.initial_state = eb0[7];
                    e.pin_id        = eb0[6:3];
                    e.section       = {eb0[2:0], eb1[7:5]};
                    e.position      = {eb1[4:0], eb2};
                    pin_state[e.pin_id] = ~e.initial_state;
                  end
                  if (!format_error_o) gpio_pin_out_o <= pin_state;
                end
              end else begin
                logic [4:0] pin_count;
                logic [9:0] decoded_count;
                logic [15:0] last_sample;
                pin_count = gpio_popcount16(active_mask);
                decoded_count = 10'd0;
                last_sample = gpio_pin_out_o;
                if (pin_count == 5'd0) begin
                  format_error_o <= 1'b1;
                end else begin
                  if (pin_count >= 5'd9)      decoded_count = payload_bytes >> 1;
                  else if (pin_count >= 5'd5) decoded_count = payload_bytes;
                  else if (pin_count >= 5'd3) decoded_count = payload_bytes * 2;
                  else if (pin_count == 5'd2) decoded_count = payload_bytes * 4;
                  else                        decoded_count = payload_bytes * 8;
                  if (decoded_count != data_len) begin
                    format_error_o <= 1'b1;
                  end else begin
                    int rem;
                    rem = data_len;
                    for (int byte_idx = 0; byte_idx < payload_bytes; byte_idx++) begin
                      logic [7:0] pb;
                      pb = asep_get_byte(rx_packet_i, payload_start + byte_idx);
                      if (pin_count >= 5'd9) begin
                        logic [7:0] pb2;
                        pb2 = asep_get_byte(rx_packet_i, payload_start + byte_idx + 1);
                        for (int p = 0; p < pin_count; p++) begin
                          if (p < 8) last_sample[gpio_active_pin_at(active_mask, p)] = pb[7-p];
                          else       last_sample[gpio_active_pin_at(active_mask, p)] = pb2[15-p];
                        end
                      end else if (pin_count >= 5'd5) begin
                        for (int p = 0; p < pin_count; p++) last_sample[gpio_active_pin_at(active_mask, p)] = pb[7-p];
                      end else if (pin_count >= 5'd3) begin
                        for (int p = 0; p < pin_count; p++) last_sample[gpio_active_pin_at(active_mask, p)] = (rem >= 2) ? pb[3-p] : pb[7-p];
                      end else if (pin_count == 5'd2) begin
                        last_sample[gpio_active_pin_at(active_mask, 0)] = pb[(rem > 1) ? 1 : 7];
                        last_sample[gpio_active_pin_at(active_mask, 1)] = pb[(rem > 1) ? 0 : 6];
                      end else begin
                        last_sample[gpio_active_pin_at(active_mask, 0)] = pb[(rem > 1) ? 0 : 7];
                      end
                      rem = rem - ((pin_count >= 5'd9) || (pin_count >= 5'd5)) ? 1 :
                            (pin_count >= 5'd3) ? 2 :
                            (pin_count == 5'd2) ? 4 : 8;
                    end
                    gpio_pin_out_o <= last_sample;
                  end
                end
              end
            end
          end
        end
      end

      for (int pin = 0; pin < 16; pin++) begin
        if (!pin_avail_i[pin]) begin
          pin_enable_o[pin] <= 1'b0;
        end
      end
    end
  end

endmodule

`default_nettype wire
