`timescale 1ns/1ps
`default_nettype none

module gpio_fs_codec
  import asa_asep_pkg::*;
  import asa_gpio_asep_pkg::*;
(
  input  logic            encode_i,
  input  logic            decode_i,
  input  logic [15:0]     active_mask_i,
  input  logic [9:0]      sample_count_i,
  input  gpio_sample_vec_t samples_i,
  input  asep_packet_t    payload_i,
  input  logic [10:0]     payload_len_i,
  output asep_packet_t    payload_o,
  output logic [10:0]     payload_len_o,
  output gpio_sample_vec_t samples_o,
  output logic [9:0]      sample_count_o,
  output logic            error_o
);

  always_comb begin
    asep_packet_t out_payload;
    gpio_sample_vec_t out_samples;
    logic [10:0] out_len;
    logic [9:0] out_count;
    logic err;
    logic [4:0] pin_count;

    out_payload = '0;
    out_samples = '0;
    out_len     = 11'd0;
    out_count   = 10'd0;
    err         = 1'b0;
    pin_count   = gpio_popcount16(active_mask_i);

    if (encode_i) begin
      int unsigned wr_idx;
      wr_idx = 0;
      if (pin_count == 5'd0) begin
        out_len = 11'd0;
      end else if (pin_count >= 5'd9) begin
        for (int s = 0; s < sample_count_i; s++) begin
          logic [7:0] hi_b, lo_b;
          logic [15:0] sample;
          sample = gpio_sample_get(samples_i, s);
          hi_b = 8'h00;
          lo_b = 8'h00;
          for (int p = 0; p < pin_count; p++) begin
            if (p < 8) hi_b[7-p] = sample[gpio_active_pin_at(active_mask_i, p)];
            else       lo_b[15-p] = sample[gpio_active_pin_at(active_mask_i, p)];
          end
          out_payload = asep_set_byte(out_payload, wr_idx + 0, hi_b);
          out_payload = asep_set_byte(out_payload, wr_idx + 1, lo_b);
          wr_idx += 2;
        end
      end else if (pin_count >= 5'd5) begin
        for (int s = 0; s < sample_count_i; s++) begin
          logic [7:0] b;
          logic [15:0] sample;
          sample = gpio_sample_get(samples_i, s);
          b = 8'h00;
          for (int p = 0; p < pin_count; p++) begin
            b[7-p] = sample[gpio_active_pin_at(active_mask_i, p)];
          end
          out_payload = asep_set_byte(out_payload, wr_idx, b);
          wr_idx++;
        end
      end else if (pin_count >= 5'd3) begin
        for (int s = 0; s < sample_count_i; s += 2) begin
          logic [7:0] b;
          logic [15:0] samp0, samp1;
          samp0 = gpio_sample_get(samples_i, s);
          samp1 = (s + 1 < sample_count_i) ? gpio_sample_get(samples_i, s+1) : 16'h0000;
          b = 8'h00;
          for (int p = 0; p < pin_count; p++) begin
            b[7-p] = samp0[gpio_active_pin_at(active_mask_i, p)];
            b[3-p] = samp1[gpio_active_pin_at(active_mask_i, p)];
          end
          out_payload = asep_set_byte(out_payload, wr_idx, b);
          wr_idx++;
        end
      end else if (pin_count == 5'd2) begin
        for (int s = 0; s < sample_count_i; s += 4) begin
          logic [7:0] b;
          b = 8'h00;
          for (int k = 0; k < 4; k++) begin
            logic [15:0] sampk;
            sampk = (s + k < sample_count_i) ? gpio_sample_get(samples_i, s+k) : 16'h0000;
            b[7-(k*2)] = sampk[gpio_active_pin_at(active_mask_i, 0)];
            b[6-(k*2)] = sampk[gpio_active_pin_at(active_mask_i, 1)];
          end
          out_payload = asep_set_byte(out_payload, wr_idx, b);
          wr_idx++;
        end
      end else begin
        for (int s = 0; s < sample_count_i; s += 8) begin
          logic [7:0] b;
          b = 8'h00;
          for (int k = 0; k < 8; k++) begin
            logic [15:0] sampk;
            sampk = (s + k < sample_count_i) ? gpio_sample_get(samples_i, s+k) : 16'h0000;
            b[7-k] = sampk[gpio_active_pin_at(active_mask_i, 0)];
          end
          out_payload = asep_set_byte(out_payload, wr_idx, b);
          wr_idx++;
        end
      end
      out_len = wr_idx[10:0];
    end

    if (decode_i) begin
      int unsigned rd_idx;
      rd_idx = 0;
      if (pin_count == 5'd0) begin
        out_count = 10'd0;
      end else if (pin_count >= 5'd9) begin
        out_count = payload_len_i >> 1;
        for (int s = 0; s < out_count; s++) begin
          logic [15:0] sample;
          logic [7:0] hi_b, lo_b;
          hi_b = asep_get_byte(payload_i, rd_idx + 0);
          lo_b = asep_get_byte(payload_i, rd_idx + 1);
          sample = 16'h0000;
          for (int p = 0; p < pin_count; p++) begin
            if (p < 8) sample[gpio_active_pin_at(active_mask_i, p)] = hi_b[7-p];
            else       sample[gpio_active_pin_at(active_mask_i, p)] = lo_b[15-p];
          end
          out_samples = gpio_sample_set(out_samples, s, sample);
          rd_idx += 2;
        end
      end else if (pin_count >= 5'd5) begin
        out_count = payload_len_i[9:0];
        for (int s = 0; s < out_count; s++) begin
          logic [7:0] b;
          logic [15:0] sample;
          b = asep_get_byte(payload_i, rd_idx);
          sample = 16'h0000;
          for (int p = 0; p < pin_count; p++) begin
            sample[gpio_active_pin_at(active_mask_i, p)] = b[7-p];
          end
          out_samples = gpio_sample_set(out_samples, s, sample);
          rd_idx++;
        end
      end else if (pin_count >= 5'd3) begin
        out_count = payload_len_i[9:0] * 2;
        for (int idx = 0; idx < payload_len_i; idx++) begin
          logic [7:0] b;
          logic [15:0] samp0, samp1;
          b = asep_get_byte(payload_i, idx);
          samp0 = 16'h0000;
          samp1 = 16'h0000;
          for (int p = 0; p < pin_count; p++) begin
            samp0[gpio_active_pin_at(active_mask_i, p)] = b[7-p];
            samp1[gpio_active_pin_at(active_mask_i, p)] = b[3-p];
          end
          out_samples = gpio_sample_set(out_samples, idx*2,   samp0);
          out_samples = gpio_sample_set(out_samples, idx*2+1, samp1);
        end
      end else if (pin_count == 5'd2) begin
        out_count = payload_len_i[9:0] * 4;
        for (int idx = 0; idx < payload_len_i; idx++) begin
          logic [7:0] b;
          b = asep_get_byte(payload_i, idx);
          for (int k = 0; k < 4; k++) begin
            logic [15:0] sample;
            sample = 16'h0000;
            sample[gpio_active_pin_at(active_mask_i, 0)] = b[7-(k*2)];
            sample[gpio_active_pin_at(active_mask_i, 1)] = b[6-(k*2)];
            out_samples = gpio_sample_set(out_samples, idx*4+k, sample);
          end
        end
      end else begin
        out_count = payload_len_i[9:0] * 8;
        for (int idx = 0; idx < payload_len_i; idx++) begin
          logic [7:0] b;
          b = asep_get_byte(payload_i, idx);
          for (int k = 0; k < 8; k++) begin
            logic [15:0] sample;
            sample = 16'h0000;
            sample[gpio_active_pin_at(active_mask_i, 0)] = b[7-k];
            out_samples = gpio_sample_set(out_samples, idx*8+k, sample);
          end
        end
      end
      if (out_count > GPIO_ASEP_MAX_SAMPLES) err = 1'b1;
    end

    payload_o      = out_payload;
    payload_len_o  = out_len;
    samples_o      = out_samples;
    sample_count_o = out_count;
    error_o        = err;
  end

endmodule

`default_nettype wire
