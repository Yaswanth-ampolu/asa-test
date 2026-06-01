`timescale 1ns/1ps
`default_nettype none

module video_payload_codec
  import asa_asep_pkg::*;
  import asa_video_asep_pkg::*;
(
  input  logic                 encode_i,
  input  logic                 decode_i,
  input  video_pix_fmt_e       pix_fmt_i,
  input  video_pix_depth_e     pix_depth_i,
  input  video_alpha_depth_e   alpha_depth_i,
  input  logic [13:0]          pixel_count_i,
  input  video_component_vec_t components_i,
  input  video_payload_t       payload_i,
  input  logic [11:0]          payload_len_i,
  output video_payload_t       payload_o,
  output logic [11:0]          payload_len_o,
  output video_component_vec_t components_o,
  output logic [12:0]          component_count_o,
  output logic                 seen_o,
  output logic                 format_error_o,
  output logic                 length_error_o
);

  function automatic logic [31:0] comp_value_at(
    input video_component_vec_t comps,
    input int unsigned          idx
  );
    return video_comp_get(comps, idx);
  endfunction

  always_comb begin
    payload_o         = '0;
    payload_len_o     = '0;
    components_o      = '0;
    component_count_o = '0;
    seen_o            = 1'b0;
    format_error_o    = 1'b0;
    length_error_o    = 1'b0;

    if (encode_i || decode_i) begin
      int unsigned bits_per_base;
      int unsigned base_pixels;
      int unsigned exp_len;
      int unsigned comp_count;
      bits_per_base = video_base_group_bits(pix_fmt_i, pix_depth_i, alpha_depth_i);
      base_pixels   = video_base_pixels(pix_fmt_i);
      exp_len       = video_expected_payload_bytes(pix_fmt_i, pix_depth_i, alpha_depth_i, pixel_count_i);
      comp_count    = video_component_count_for_pixels(pix_fmt_i, pixel_count_i);
      component_count_o = comp_count[12:0];

      if (!video_depth_valid(pix_fmt_i, pix_depth_i) || !video_alpha_valid(pix_fmt_i, alpha_depth_i)) begin
        format_error_o = 1'b1;
      end else if (!video_pixel_count_valid(pix_fmt_i, pixel_count_i)) begin
        length_error_o = 1'b1;
      end else if (encode_i) begin
        video_payload_t payload_tmp;
        int unsigned bit_pos;
        int unsigned comp_idx;
        int unsigned pixels_done;
        payload_tmp = '0;
        bit_pos     = 0;
        comp_idx    = 0;
        pixels_done = 0;
        while (pixels_done < pixel_count_i) begin
          for (int base = 0; base < video_base_components(pix_fmt_i); base++) begin
            int unsigned width;
            logic [31:0] value;
            width = video_component_width(pix_fmt_i, pix_depth_i, alpha_depth_i, base);
            value = comp_value_at(components_i, comp_idx);
            for (int b = 0; b < width; b++) begin
              payload_tmp[bit_pos + b] = value[b];
            end
            bit_pos += width;
            comp_idx++;
          end
          pixels_done += base_pixels;
        end
        payload_o     = payload_tmp;
        payload_len_o = exp_len[11:0];
        seen_o        = 1'b1;
      end else if (decode_i) begin
        video_component_vec_t comps_tmp;
        int unsigned bit_pos;
        int unsigned comp_idx;
        int unsigned pixels_done;
        if (payload_len_i != exp_len[11:0]) begin
          length_error_o = 1'b1;
        end else begin
          comps_tmp   = '0;
          bit_pos     = 0;
          comp_idx    = 0;
          pixels_done = 0;
          while (pixels_done < pixel_count_i) begin
            for (int base = 0; base < video_base_components(pix_fmt_i); base++) begin
              int unsigned width;
              logic [31:0] value;
              width = video_component_width(pix_fmt_i, pix_depth_i, alpha_depth_i, base);
              value = 32'd0;
              for (int b = 0; b < width; b++) begin
                value[b] = payload_i[bit_pos + b];
              end
              comps_tmp = video_comp_set(comps_tmp, comp_idx, value);
              bit_pos  += width;
              comp_idx++;
            end
            pixels_done += base_pixels;
          end
          components_o = comps_tmp;
          seen_o       = 1'b1;
        end
      end
    end
  end

endmodule

`default_nettype wire
