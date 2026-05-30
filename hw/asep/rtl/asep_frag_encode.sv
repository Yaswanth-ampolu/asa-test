`timescale 1ns/1ps
`default_nettype none

module asep_frag_encode
  import asa_intf_pkg::*;
  import asa_asep_pkg::*;
(
  input  slot_size_e        slot_size_i,
  input  asep_frag_code_e   frag_code_i,
  input  logic [9:0]        boundary_pos_i,
  input  asep_container_t   frag_bytes_i,
  input  logic [10:0]       frag_bytes_len_i,
  output asep_container_t   dll_payload_o,
  output logic [10:0]       dll_payload_len_o,
  output logic              byte1_present_o,
  output logic              overflow_o
);

  integer i;
  int unsigned slot_bytes;
  int unsigned start_idx;
  asep_container_t payload_d;
  logic overflow_d;

  always_comb begin
    payload_d = '0;
    overflow_d = 1'b0;
    slot_bytes = asep_slot_bytes(slot_size_i);
    byte1_present_o = frag_code_i[1];
    start_idx = byte1_present_o ? 2 : 1;

    payload_d[7:0] = asep_frag_byte0(frag_code_i, boundary_pos_i);
    if (byte1_present_o) begin
      payload_d[15:8] = asep_frag_byte1(boundary_pos_i);
    end

    for (i = 0; i < ASEP_MAX_CONTAINER_BYTES; i++) begin
      if (i < frag_bytes_len_i) begin
        if ((start_idx + i) < slot_bytes) begin
          payload_d[(start_idx + i)*8 +: 8] = frag_bytes_i[i*8 +: 8];
        end else begin
          overflow_d = 1'b1;
        end
      end
    end
  end

  assign dll_payload_o = payload_d;
  assign dll_payload_len_o = 11'(asep_slot_bytes(slot_size_i));
  assign overflow_o = overflow_d;

endmodule

