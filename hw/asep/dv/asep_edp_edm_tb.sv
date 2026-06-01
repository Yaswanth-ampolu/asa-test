`timescale 1ns/1ps
`default_nettype none

module asep_edp_edm_tb;
  import asa_asep_pkg::*;
  import asa_edp_asep_pkg::*;

  localparam int unsigned TB_PAYLOAD_BYTES = 16;

  int pass_count, fail_count;
  task automatic check(input string name, input logic cond);
    if (cond) pass_count++;
    else begin
      $display("FAIL: %s", name);
      fail_count++;
    end
  endtask

  asep_ts_mode_e ts_mode;
  logic [31:0] ts_value;
  logic enc, dec, seen, crc_err, fmt_err, dummy_i, dummy_o;
  edp_lane_count_e lane_i, lane_o;
  logic [15:0] len_per_lane_i, len_per_lane_o;
  logic [7:0] k01_i, k23_i, k45_i, k67_i, k01_o, k23_o, k45_o, k67_o;
  logic [(TB_PAYLOAD_BYTES*8)-1:0] payload_i, payload_o;
  logic [11:0] payload_len_i, payload_len_o;
  asep_packet_t pkt_enc, pkt_dec;
  logic [11:0] pkt_len_enc, pkt_len_dec;

  edp_edm_data_codec #(
    .PAYLOAD_BYTES(TB_PAYLOAD_BYTES)
  ) dut(
    .encode_i(enc), .decode_i(dec), .ts_mode_i(ts_mode), .ts_value_i(ts_value), .dummy_sw_i(dummy_i),
    .lane_count_i(lane_i), .length_per_lane_i(len_per_lane_i), .komma01_i(k01_i), .komma23_i(k23_i),
    .payload_i(payload_i), .payload_len_i(payload_len_i), .komma45_i(k45_i), .komma67_i(k67_i),
    .packet_i(pkt_dec), .packet_len_i(pkt_len_dec), .packet_o(pkt_enc), .packet_len_o(pkt_len_enc),
    .seen_o(seen), .dummy_sw_o(dummy_o), .lane_count_o(lane_o), .length_per_lane_o(len_per_lane_o),
    .komma01_o(k01_o), .komma23_o(k23_o), .payload_o(payload_o), .payload_len_o(payload_len_o),
    .komma45_o(k45_o), .komma67_o(k67_o), .crc_error_o(crc_err), .format_error_o(fmt_err)
  );

  initial begin
    pass_count = 0; fail_count = 0;
    ts_mode = ASEP_TS_INGRESS; ts_value = 32'h89ABCDEF;
    enc = 0; dec = 0; dummy_i = 0; lane_i = EDP_LANES_2; len_per_lane_i = 16'd2;
    k01_i = 8'h31; k23_i = 8'h42; k45_i = 8'h50; k67_i = 8'h0D;
    payload_i = '0; payload_len_i = 12'd4;
    payload_i[0*8 +: 8] = 8'h11;
    payload_i[1*8 +: 8] = 8'h22;
    payload_i[2*8 +: 8] = 8'h33;
    payload_i[3*8 +: 8] = 8'h44;
    #1;

    enc = 1; #1;
    check("T1 edm len", pkt_len_enc == (asep_common_hdr_bytes(ts_mode) + 12'd15));
    pkt_dec = pkt_enc; pkt_len_dec = pkt_len_enc; enc = 0; dec = 1; #1;
    check("T2 edm fields", seen && lane_o == EDP_LANES_2 && payload_len_o == 4 &&
      payload_o[0*8 +: 8] == 8'h11 && payload_o[3*8 +: 8] == 8'h44);
    dec = 0;

    if (fail_count == 0) $display("asep_edp_edm_tb: %0d passed, 0 failed", pass_count);
    else $display("asep_edp_edm_tb: %0d passed, %0d failed", pass_count, fail_count);
    $finish;
  end

endmodule

`default_nettype wire
