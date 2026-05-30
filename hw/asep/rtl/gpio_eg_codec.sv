`timescale 1ns/1ps
`default_nettype none

module gpio_eg_codec
  import asa_asep_pkg::*;
  import asa_gpio_asep_pkg::*;
(
  input  logic         encode_i,
  input  logic         decode_i,
  input  logic [9:0]   edge_count_i,
  input  gpio_edge_vec_t edges_i,
  input  asep_packet_t payload_i,
  input  logic [10:0]  payload_len_i,
  output asep_packet_t payload_o,
  output logic [10:0]  payload_len_o,
  output gpio_edge_vec_t edges_o,
  output logic [9:0]   edge_count_o,
  output logic         error_o
);

  always_comb begin
    asep_packet_t out_payload;
    gpio_edge_vec_t out_edges;
    logic [10:0] out_len;
    logic [9:0] out_count;
    logic err;

    out_payload = '0;
    out_edges   = '0;
    out_len     = 11'd0;
    out_count   = 10'd0;
    err         = 1'b0;

    if (encode_i) begin
      for (int i = 0; i < edge_count_i; i++) begin
        gpio_edge_t e;
        e = gpio_edge_get(edges_i, i);
        out_payload = asep_set_byte(out_payload, i*3 + 0, {e.initial_state, e.pin_id, e.section[5:3]});
        out_payload = asep_set_byte(out_payload, i*3 + 1, {e.section[2:0], e.position[12:8]});
        out_payload = asep_set_byte(out_payload, i*3 + 2, e.position[7:0]);
      end
      out_len = edge_count_i * 3;
    end

    if (decode_i) begin
      if ((payload_len_i % 3) != 0) begin
        err = 1'b1;
      end else begin
        out_count = payload_len_i / 3;
        if (out_count > GPIO_ASEP_MAX_EDGES) begin
          err = 1'b1;
        end else begin
          for (int i = 0; i < out_count; i++) begin
            gpio_edge_t e;
            logic [7:0] b0, b1, b2;
            b0 = asep_get_byte(payload_i, i*3 + 0);
            b1 = asep_get_byte(payload_i, i*3 + 1);
            b2 = asep_get_byte(payload_i, i*3 + 2);
            e.initial_state = b0[7];
            e.pin_id   = b0[6:3];
            e.section  = {b0[2:0], b1[7:5]};
            e.position = {b1[4:0], b2};
            out_edges = gpio_edge_set(out_edges, i, e);
          end
        end
      end
    end

    payload_o    = out_payload;
    payload_len_o= out_len;
    edges_o      = out_edges;
    edge_count_o = out_count;
    error_o      = err;
  end

endmodule

`default_nettype wire
