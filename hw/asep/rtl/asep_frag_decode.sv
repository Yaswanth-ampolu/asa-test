`timescale 1ns/1ps
`default_nettype none

module asep_frag_decode
  import asa_asep_pkg::*;
(
  input  asep_container_t dll_payload_i,
  input  logic [10:0]     dll_payload_len_i,
  output asep_frag_code_e frag_code_o,
  output logic [9:0]      boundary_pos_o,
  output logic            byte1_present_o,
  output logic [10:0]     data_start_idx_o,
  output logic            malformed_o
);

  logic [7:0] byte0, byte1;
  logic malformed_d;
  logic [9:0] boundary_d;
  logic [10:0] start_idx_d;

  always_comb begin
    byte0 = dll_payload_i[7:0];
    byte1 = dll_payload_i[15:8];
    frag_code_o = asep_frag_code_e'(byte0[7:6]);
    byte1_present_o = byte0[7];
    start_idx_d = byte1_present_o ? 11'd2 : 11'd1;
    boundary_d = asep_boundary_pos(byte0, byte1);
    malformed_d = 1'b0;

    if (dll_payload_len_i < start_idx_d) begin
      malformed_d = 1'b1;
    end

    if (byte1_present_o) begin
      if (boundary_d < start_idx_d) malformed_d = 1'b1;
      if (boundary_d > dll_payload_len_i) malformed_d = 1'b1;
    end
  end

  assign boundary_pos_o = boundary_d;
  assign data_start_idx_o = start_idx_d;
  assign malformed_o = malformed_d;

endmodule

