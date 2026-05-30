`timescale 1ns/1ps
`default_nettype none

module asep_common_tb;
  import asa_intf_pkg::*;
  import asa_asep_pkg::*;

  logic clk, rst, soft_reset;
  initial begin clk = 1'b0; forever #5 clk = ~clk; end

  logic tx_build_req;
  slot_size_e tx_slot_size;
  logic tx_pkt0_valid, tx_pkt1_valid;
  logic [6:0] tx_pkt0_stream_type, tx_pkt1_stream_type;
  asep_ts_mode_e tx_pkt0_ts_mode, tx_pkt1_ts_mode;
  logic [31:0] tx_pkt0_ts_value, tx_pkt1_ts_value;
  asep_packet_t tx_pkt0_body, tx_pkt1_body;
  logic [11:0] tx_pkt0_body_len, tx_pkt1_body_len, tx_pkt0_offset, tx_pkt1_offset;
  logic tx_ptb_capture_req, tx_data_valid, tx_yield, tx_overflow;
  asep_frag_code_e tx_frag_code;
  logic [9:0] tx_boundary_pos;
  asep_container_t tx_dll_payload;
  logic [10:0] tx_dll_payload_len;
  logic [11:0] tx_used_pkt0_bytes, tx_used_pkt1_bytes;

  logic rx_container_valid, rx_packet_id_ok, rx_packet_valid, rx_follow_flag, rx_error, rx_assembling;
  asep_container_t rx_dll_payload;
  logic [10:0] rx_dll_payload_len;
  asep_packet_t rx_packet;
  logic [11:0] rx_packet_len;
  logic [6:0] rx_stream_type;
  asep_ts_mode_e rx_ts_mode;
  logic [31:0] rx_ts_value;
  asep_frag_code_e rx_frag_code;
  logic [9:0] rx_boundary_pos;

  int pass_count, fail_count;

  /* verilator lint_off WIDTHCONCAT */
  localparam asep_packet_t ASEP_PKT_ZERO = '0;
  localparam asep_container_t ASEP_CONT_ZERO = '0;
  /* verilator lint_on WIDTHCONCAT */

  task automatic check(input string name, input logic cond);
    if (cond) pass_count++;
    else begin
      $display("FAIL: %s", name);
      fail_count++;
    end
  endtask

  task automatic tick(input int n = 1);
    repeat (n) @(posedge clk);
    #1;
  endtask

  function automatic asep_packet_t make_body(input int unsigned n, input logic [7:0] seed);
    asep_packet_t b;
    b = ASEP_PKT_ZERO;
    for (int i = 0; i < ASEP_MAX_PACKET_BYTES; i++) begin
      if (i < n) b[i*8 +: 8] = seed + i[7:0];
    end
    return b;
  endfunction

  asep_common_top dut (
    .clk(clk), .rst(rst), .soft_reset_i(soft_reset),
    .tx_build_req_i(tx_build_req),
    .tx_slot_size_i(tx_slot_size),
    .tx_pkt0_valid_i(tx_pkt0_valid),
    .tx_pkt0_stream_type_i(tx_pkt0_stream_type),
    .tx_pkt0_ts_mode_i(tx_pkt0_ts_mode),
    .tx_pkt0_ts_value_i(tx_pkt0_ts_value),
    .tx_pkt0_body_i(tx_pkt0_body),
    .tx_pkt0_body_len_i(tx_pkt0_body_len),
    .tx_pkt0_offset_i(tx_pkt0_offset),
    .tx_pkt1_valid_i(tx_pkt1_valid),
    .tx_pkt1_stream_type_i(tx_pkt1_stream_type),
    .tx_pkt1_ts_mode_i(tx_pkt1_ts_mode),
    .tx_pkt1_ts_value_i(tx_pkt1_ts_value),
    .tx_pkt1_body_i(tx_pkt1_body),
    .tx_pkt1_body_len_i(tx_pkt1_body_len),
    .tx_pkt1_offset_i(tx_pkt1_offset),
    .tx_ptb_capture_req_o(tx_ptb_capture_req),
    .tx_data_valid_o(tx_data_valid),
    .tx_yield_o(tx_yield),
    .tx_frag_code_o(tx_frag_code),
    .tx_boundary_pos_o(tx_boundary_pos),
    .tx_dll_payload_o(tx_dll_payload),
    .tx_dll_payload_len_o(tx_dll_payload_len),
    .tx_used_pkt0_bytes_o(tx_used_pkt0_bytes),
    .tx_used_pkt1_bytes_o(tx_used_pkt1_bytes),
    .tx_overflow_o(tx_overflow),
    .rx_container_valid_i(rx_container_valid),
    .rx_packet_id_ok_i(rx_packet_id_ok),
    .rx_dll_payload_i(rx_dll_payload),
    .rx_dll_payload_len_i(rx_dll_payload_len),
    .rx_packet_valid_o(rx_packet_valid),
    .rx_packet_o(rx_packet),
    .rx_packet_len_o(rx_packet_len),
    .rx_stream_type_o(rx_stream_type),
    .rx_follow_flag_o(rx_follow_flag),
    .rx_ts_mode_o(rx_ts_mode),
    .rx_ts_value_o(rx_ts_value),
    .rx_frag_code_o(rx_frag_code),
    .rx_boundary_pos_o(rx_boundary_pos),
    .rx_error_o(rx_error),
    .rx_assembling_o(rx_assembling)
  );

  initial begin
    rst = 1'b1;
    soft_reset = 1'b0;
    tx_build_req = 1'b0;
    tx_slot_size = SLOT_OAM_FRAME;
    tx_pkt0_valid = 1'b0;
    tx_pkt1_valid = 1'b0;
    tx_pkt0_stream_type = ASEP_STREAM_SPI;
    tx_pkt1_stream_type = ASEP_STREAM_GPIO;
    tx_pkt0_ts_mode = ASEP_TS_NONE;
    tx_pkt1_ts_mode = ASEP_TS_NONE;
    tx_pkt0_ts_value = 32'd0;
    tx_pkt1_ts_value = 32'd0;
    tx_pkt0_body = ASEP_PKT_ZERO;
    tx_pkt1_body = ASEP_PKT_ZERO;
    tx_pkt0_body_len = 12'd0;
    tx_pkt1_body_len = 12'd0;
    tx_pkt0_offset = 12'd0;
    tx_pkt1_offset = 12'd0;
    rx_container_valid = 1'b0;
    rx_packet_id_ok = 1'b1;
    rx_dll_payload = ASEP_CONT_ZERO;
    rx_dll_payload_len = 11'd0;
    pass_count = 0;
    fail_count = 0;

    tick(2);
    rst = 1'b0;
    tick(1);

    // T1: Yield when no packet available
    tx_build_req = 1'b1;
    tick(1);
    check("T1 yield asserted", tx_yield && !tx_data_valid);
    tx_build_req = 1'b0;

    // T2: Exact-fit single packet -> code 01
    tx_pkt0_valid = 1'b1;
    tx_slot_size = SLOT_OAM_FRAME; // 188 bytes
    tx_pkt0_stream_type = ASEP_STREAM_SPI;
    tx_pkt0_ts_mode = ASEP_TS_NONE;
    tx_pkt0_body = make_body(185, 8'h20); // 2 hdr + 185 = 187 payload bytes after Byte0
    tx_pkt0_body_len = 12'd185;
    tx_build_req = 1'b1;
    tick(1);
    check("T2 data valid", tx_data_valid && !tx_yield);
    check("T2 frag 01", tx_frag_code == ASEP_FRAG_END_LAST);
    check("T2 header byte0", tx_dll_payload[15:8] == {ASEP_STREAM_SPI, 1'b0});
    check("T2 header byte1", tx_dll_payload[23:16] == 8'h00);
    tx_build_req = 1'b0;

    // T3: Oversized packet -> code 00 continuation
    tx_pkt0_body = make_body(240, 8'h30);
    tx_pkt0_body_len = 12'd240;
    tx_build_req = 1'b1;
    tick(1);
    check("T3 frag 00", tx_frag_code == ASEP_FRAG_MID);
    check("T3 used bytes", tx_used_pkt0_bytes == 12'd187);
    tx_build_req = 1'b0;

    // T4: End + padding -> code 10 and boundary 2+rem
    tx_pkt0_body = make_body(20, 8'h40);
    tx_pkt0_body_len = 12'd20;
    tx_build_req = 1'b1;
    tick(1);
    check("T4 frag 10", tx_frag_code == ASEP_FRAG_END_PAD);
    check("T4 boundary", tx_boundary_pos == 10'd24);
    check("T4 byte1 present", tx_dll_payload[15:8] == 8'h80);
    tx_build_req = 1'b0;

    // T5: Two packets in one container -> code 11, follow set
    tx_pkt0_body = make_body(10, 8'h50);
    tx_pkt0_body_len = 12'd10;
    tx_pkt1_valid = 1'b1;
    tx_pkt1_stream_type = ASEP_STREAM_GPIO;
    tx_pkt1_body = make_body(10, 8'h60);
    tx_pkt1_body_len = 12'd10;
    tx_build_req = 1'b1;
    tick(1);
    check("T5 frag 11", tx_frag_code == ASEP_FRAG_END_HEADER);
    check("T5 follow flag set", tx_dll_payload[2*8 +: 8] == {ASEP_STREAM_SPI, 1'b1});
    check("T5 pkt1 started", tx_used_pkt1_bytes != 12'd0);
    tx_build_req = 1'b0;
    tx_pkt1_valid = 1'b0;

    // T6: ingress timestamp big-endian and capture pulse
    tx_pkt0_stream_type = ASEP_STREAM_I2C;
    tx_pkt0_ts_mode = ASEP_TS_INGRESS;
    tx_pkt0_ts_value = 32'h11223344;
    tx_pkt0_body = make_body(4, 8'h70);
    tx_pkt0_body_len = 12'd4;
    tx_build_req = 1'b1;
    tick(1);
    check("T6 capture pulse", tx_ptb_capture_req);
    check("T6 ts byte2", tx_dll_payload[39:32] == 8'h11);
    check("T6 ts byte5", tx_dll_payload[63:56] == 8'h44);
    tx_build_req = 1'b0;

    // T7: RX exact-fit packet reconstructs, decodes stream and ts
    rx_dll_payload = tx_dll_payload;
    rx_dll_payload_len = tx_dll_payload_len;
    rx_container_valid = 1'b1;
    tick(1);
    rx_container_valid = 1'b0;
    tick(1);
    check("T7 packet valid", rx_packet_valid);
    check("T7 stream type", rx_stream_type == ASEP_STREAM_I2C);
    check("T7 ts mode", rx_ts_mode == ASEP_TS_INGRESS);
    check("T7 ts value", rx_ts_value == 32'h11223344);

    // T8: RX fragmented mid + end reassembles
    tx_pkt0_ts_mode = ASEP_TS_NONE;
    tx_pkt0_body = make_body(240, 8'h80);
    tx_pkt0_body_len = 12'd240;
    tx_pkt0_offset = 12'd0;
    tx_build_req = 1'b1;
    tick(1);
    rx_dll_payload = tx_dll_payload;
    rx_dll_payload_len = tx_dll_payload_len;
    rx_container_valid = 1'b1;
    tick(1);
    rx_container_valid = 1'b0;
    tx_pkt0_offset = tx_used_pkt0_bytes;
    tx_build_req = 1'b1;
    tick(1);
    rx_dll_payload = tx_dll_payload;
    rx_dll_payload_len = tx_dll_payload_len;
    rx_container_valid = 1'b1;
    tick(1);
    rx_container_valid = 1'b0;
    tick(1);
    check("T8 packet valid", rx_packet_valid);
    check("T8 packet len", rx_packet_len == 12'd242);
    check("T8 body first byte", asep_get_byte(rx_packet, 2) == 8'h80);
    tx_build_req = 1'b0;
    tx_pkt0_offset = 12'd0;

    // T9: RX code11 seeds next packet and next container completes it
    tx_pkt0_body = make_body(8, 8'h90);
    tx_pkt0_body_len = 12'd8;
    tx_pkt1_valid = 1'b1;
    tx_pkt1_stream_type = ASEP_STREAM_GPIO;
    tx_pkt1_body = make_body(20, 8'hA0);
    tx_pkt1_body_len = 12'd20;
    tx_pkt1_offset = 12'd0;
    tx_build_req = 1'b1;
    tick(1);
    rx_dll_payload = tx_dll_payload;
    rx_dll_payload_len = tx_dll_payload_len;
    rx_container_valid = 1'b1;
    tick(1);
    rx_container_valid = 1'b0;
    tick(1);
    check("T9 first packet valid", rx_packet_valid);
    check("T9 first stream", rx_stream_type == ASEP_STREAM_I2C || rx_stream_type == ASEP_STREAM_SPI);
    // Complete second packet from the seeded bytes.
    tx_pkt0_valid = 1'b1;
    tx_pkt0_stream_type = ASEP_STREAM_GPIO;
    tx_pkt0_body = make_body(20, 8'hA0);
    tx_pkt0_body_len = 12'd20;
    tx_pkt0_offset = tx_used_pkt1_bytes;
    tx_pkt1_valid = 1'b0;
    tx_build_req = 1'b1;
    tick(1);
    rx_dll_payload = tx_dll_payload;
    rx_dll_payload_len = tx_dll_payload_len;
    rx_container_valid = 1'b1;
    tick(1);
    rx_container_valid = 1'b0;
    tick(1);
    check("T9 second packet valid", rx_packet_valid);
    check("T9 second stream", rx_stream_type == ASEP_STREAM_GPIO);
    tx_build_req = 1'b0;
    tx_pkt0_offset = 12'd0;

    // T10: malformed boundary raises error
    rx_dll_payload = ASEP_CONT_ZERO;
    rx_dll_payload[7:0] = 8'hC0; // code11, boundary upper zero
    rx_dll_payload[15:8] = 8'h00; // boundary 0
    rx_dll_payload_len = 11'd10;
    rx_container_valid = 1'b1;
    tick(1);
    check("T10 malformed error", rx_error);
    rx_container_valid = 1'b0;
    tick(1);

    // T11: packet id miss flushes reassembly
    tx_pkt0_stream_type = ASEP_STREAM_SPI;
    tx_pkt0_body = make_body(240, 8'hB0);
    tx_pkt0_body_len = 12'd240;
    tx_pkt0_offset = 12'd0;
    tx_build_req = 1'b1;
    tick(1);
    rx_dll_payload = tx_dll_payload;
    rx_dll_payload_len = tx_dll_payload_len;
    rx_packet_id_ok = 1'b1;
    rx_container_valid = 1'b1;
    tick(1);
    rx_container_valid = 1'b0;
    tx_pkt0_offset = tx_used_pkt0_bytes;
    tx_build_req = 1'b1;
    tick(1);
    rx_dll_payload = tx_dll_payload;
    rx_dll_payload_len = tx_dll_payload_len;
    rx_packet_id_ok = 1'b0;
    rx_container_valid = 1'b1;
    tick(1);
    rx_container_valid = 1'b0;
    tick(1);
    check("T11 packet-id miss error", rx_error);
    rx_packet_id_ok = 1'b1;

    // T12: boundary 0x002 encode/decode
    check("T12 boundary byte0 upper", asep_frag_byte0(ASEP_FRAG_END_HEADER, 10'd2) == 8'hC0);
    check("T12 boundary byte1 lower", asep_frag_byte1(10'd2) == 8'h20);

    if (fail_count == 0) begin
      $display("asep_common_tb: ALL TESTS PASSED (%0d checks)", pass_count);
    end else begin
      $display("asep_common_tb: %0d passed, %0d failed", pass_count, fail_count);
      $fatal(1);
    end
    $finish;
  end

endmodule
