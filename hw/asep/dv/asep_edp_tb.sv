`timescale 1ns/1ps
`default_nettype none

module asep_edp_tb;
  import asa_asep_pkg::*;
  import asa_edp_asep_pkg::*;

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

  logic vb_enc, vb_dec, vb_seen, vb_crc_err, vb_fmt_err;
  logic [31:0] vb_vbid_i, vb_mvid_i, vb_maud_i, vb_vbid_o, vb_mvid_o, vb_maud_o;
  asep_packet_t vb_pkt_enc, vb_pkt_dec;
  logic [11:0] vb_pkt_len_enc, vb_pkt_len_dec;
  edp_vb_codec u_vb(
    .encode_i(vb_enc), .decode_i(vb_dec), .ts_mode_i(ts_mode), .ts_value_i(ts_value), .vbid_i(vb_vbid_i),
    .mvid_i(vb_mvid_i), .maud_i(vb_maud_i), .packet_i(vb_pkt_dec), .packet_len_i(vb_pkt_len_dec),
    .packet_o(vb_pkt_enc), .packet_len_o(vb_pkt_len_enc), .seen_o(vb_seen), .vbid_o(vb_vbid_o),
    .mvid_o(vb_mvid_o), .maud_o(vb_maud_o), .crc_error_o(vb_crc_err), .format_error_o(vb_fmt_err)
  );

  logic aux_enc, aux_dec, aux_seen, aux_crc_err, aux_fmt_err;
  edp_hpd_state_e aux_hpd_i, aux_hpd_o;
  edp_payload_t aux_payload_i, aux_payload_o;
  logic [4:0] aux_len_i, aux_len_o;
  asep_packet_t aux_pkt_enc, aux_pkt_dec;
  logic [11:0] aux_pkt_len_enc, aux_pkt_len_dec;
  edp_aux_codec u_aux(
    .encode_i(aux_enc), .decode_i(aux_dec), .ts_mode_i(ts_mode), .ts_value_i(ts_value), .hpd_state_i(aux_hpd_i),
    .payload_i(aux_payload_i), .payload_len_i(aux_len_i), .packet_i(aux_pkt_dec), .packet_len_i(aux_pkt_len_dec),
    .packet_o(aux_pkt_enc), .packet_len_o(aux_pkt_len_enc), .seen_o(aux_seen), .hpd_state_o(aux_hpd_o),
    .payload_o(aux_payload_o), .payload_len_o(aux_len_o), .crc_error_o(aux_crc_err), .format_error_o(aux_fmt_err)
  );

  logic clk_enc, clk_dec, clk_seen, clk_crc_err, clk_fmt_err;
  logic [23:0] clk_mvid_i, clk_nvid_i, clk_mvid_o, clk_nvid_o;
  asep_packet_t clk_pkt_enc, clk_pkt_dec;
  logic [11:0] clk_pkt_len_enc, clk_pkt_len_dec;
  edp_stream_clock_codec u_clk(
    .encode_i(clk_enc), .decode_i(clk_dec), .ts_mode_i(ts_mode), .ts_value_i(ts_value), .mvid_ptb_i(clk_mvid_i),
    .nvid_ptb_i(clk_nvid_i), .packet_i(clk_pkt_dec), .packet_len_i(clk_pkt_len_dec), .packet_o(clk_pkt_enc),
    .packet_len_o(clk_pkt_len_enc), .seen_o(clk_seen), .mvid_ptb_o(clk_mvid_o), .nvid_ptb_o(clk_nvid_o),
    .crc_error_o(clk_crc_err), .format_error_o(clk_fmt_err)
  );

  initial begin
    pass_count = 0; fail_count = 0;
    ts_mode = ASEP_TS_INGRESS; ts_value = 32'h89ABCDEF;
    vb_enc = 0; vb_dec = 0; aux_enc = 0; aux_dec = 0; clk_enc = 0; clk_dec = 0;
    vb_vbid_i = 32'h44332211; vb_mvid_i = 32'h88776655; vb_maud_i = 32'hCCBBAA99;
    aux_hpd_i = EDP_HPD_IRQ; aux_payload_i = '0; aux_len_i = 0;
    clk_mvid_i = 24'h012345; clk_nvid_i = 24'h06789A;
    #1;

    vb_enc = 1; #1;
    check("T1 vb len", vb_pkt_len_enc == (asep_common_hdr_bytes(ts_mode) + 12'd17));
    vb_pkt_dec = vb_pkt_enc; vb_pkt_len_dec = vb_pkt_len_enc; vb_enc = 0; vb_dec = 1; #1;
    check("T1 vb fields", vb_seen && vb_vbid_o == vb_vbid_i && vb_mvid_o == vb_mvid_i && vb_maud_o == vb_maud_i);
    vb_dec = 0;

    aux_hpd_i = EDP_HPD_HOTPLUG; aux_len_i = 0; aux_enc = 1; #1;
    aux_pkt_dec = aux_pkt_enc; aux_pkt_len_dec = aux_pkt_len_enc; aux_enc = 0; aux_dec = 1; #1;
    check("T2 aux hpd only", aux_seen && aux_hpd_o == EDP_HPD_HOTPLUG && aux_len_o == 0);
    aux_dec = 0;

    aux_hpd_i = EDP_HPD_IRQ; aux_len_i = 3;
    aux_payload_i = '0;
    aux_payload_i = edp_payload_set_byte(aux_payload_i, 0, 8'hAA);
    aux_payload_i = edp_payload_set_byte(aux_payload_i, 1, 8'hBB);
    aux_payload_i = edp_payload_set_byte(aux_payload_i, 2, 8'hCC);
    aux_enc = 1; #1;
    aux_pkt_dec = aux_pkt_enc; aux_pkt_len_dec = aux_pkt_len_enc; aux_enc = 0; aux_dec = 1; #1;
    check("T3 aux payload", aux_seen && aux_hpd_o == EDP_HPD_IRQ && aux_len_o == 3 &&
      edp_payload_get_byte(aux_payload_o,0) == 8'hAA && edp_payload_get_byte(aux_payload_o,2) == 8'hCC);
    aux_dec = 0;

    clk_enc = 1; #1;
    clk_pkt_dec = clk_pkt_enc; clk_pkt_len_dec = clk_pkt_len_enc; clk_enc = 0; clk_dec = 1; #1;
    check("T4 stream clock", clk_seen && clk_mvid_o == clk_mvid_i && clk_nvid_o == clk_nvid_i);
    clk_dec = 0;

    if (fail_count == 0) $display("asep_edp_tb: %0d passed, 0 failed", pass_count);
    else $display("asep_edp_tb: %0d passed, %0d failed", pass_count, fail_count);
    $finish;
  end

endmodule

`default_nettype wire
