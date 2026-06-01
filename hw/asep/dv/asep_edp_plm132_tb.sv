`timescale 1ns/1ps
`default_nettype none

module asep_edp_plm132_tb;
  import asa_asep_pkg::*;
  import asa_edp_asep_pkg::*;

  localparam int unsigned TB_MAX_SYMBOLS = 4;

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
  logic enc, dec, seen, crc_err, fmt_err;
  logic [15:0] count_i, count_o;
  logic [(TB_MAX_SYMBOLS*132)-1:0] syms_i, syms_o;
  asep_packet_t pkt_enc, pkt_dec;
  logic [11:0] pkt_len_enc, pkt_len_dec;

  edp_plm_128b132b_codec #(
    .MAX_SYMBOLS(TB_MAX_SYMBOLS)
  ) dut(
    .encode_i(enc), .decode_i(dec), .ts_mode_i(ts_mode), .ts_value_i(ts_value), .symbol_count_i(count_i),
    .symbols_i(syms_i), .packet_i(pkt_dec), .packet_len_i(pkt_len_dec), .packet_o(pkt_enc),
    .packet_len_o(pkt_len_enc), .seen_o(seen), .symbol_count_o(count_o), .symbols_o(syms_o),
    .crc_error_o(crc_err), .format_error_o(fmt_err)
  );

  initial begin
    pass_count = 0; fail_count = 0;
    ts_mode = ASEP_TS_INGRESS; ts_value = 32'h55667788;
    enc = 0; dec = 0; count_i = 16'd2; syms_i = '0;
    syms_i[0*132 +: 132] = 132'h1234_5678_9ABC_DEF0_1357_9BDF_2468_ACEF_0;
    syms_i[1*132 +: 132] = 132'hFEDC_BA98_7654_3210_0123_4567_89AB_CDEF_F;
    #1;

    enc = 1; #1;
    pkt_dec = pkt_enc; pkt_len_dec = pkt_len_enc; enc = 0; dec = 1; #1;
    check("T1 plm132 roundtrip", seen && count_o == 2 &&
      syms_o[0*132 +: 132] == syms_i[0*132 +: 132] &&
      syms_o[1*132 +: 132] == syms_i[1*132 +: 132]);
    dec = 0;

    if (fail_count == 0) $display("asep_edp_plm132_tb: %0d passed, 0 failed", pass_count);
    else $display("asep_edp_plm132_tb: %0d passed, %0d failed", pass_count, fail_count);
    $finish;
  end

endmodule

`default_nettype wire
