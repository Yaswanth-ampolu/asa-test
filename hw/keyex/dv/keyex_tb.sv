`timescale 1ns/1ps
`default_nettype none

module keyex_tb;
  import asa_oam_pkg::*;
  import asa_keyex_pkg::*;

  logic clk, rst, soft_reset;
  initial begin clk = 0; forever #5 clk = ~clk; end

  logic [4:0] local_node_id;
  logic [127:0] root_uuid;
  logic keyex_msg_valid;
  logic [4:0] keyex_msg_src;
  oam_keyex_msg_t keyex_msg;
  logic keyex_tx_valid;
  oam_keyex_msg_t keyex_tx_msg;
  logic install_key_valid, install_slot;
  logic [127:0] install_key;
  logic [29:0] install_salt;
  logic switch_keyslot_valid, switch_keyslot;
  logic [1:0] policy;
  logic rep10, rep5, repovf;
  logic mon_tx_seen;
  oam_keyex_msg_t mon_tx_msg;
  int install_seen_count;
  logic first_install_slot, second_install_slot;
  logic [127:0] first_install_key, second_install_key;
  logic [29:0] first_install_salt, second_install_salt;
  logic mon_switch_seen, mon_switch_slot;

  int pass_count, fail_count;
  task automatic check(input string name, input logic cond);
    if (cond) pass_count++;
    else begin $display("FAIL: %s", name); fail_count++; end
  endtask
  task automatic tick(input int n = 1); repeat (n) @(posedge clk); #1; endtask

  keyex_top dut (
    .clk, .rst, .soft_reset_i(soft_reset),
    .local_node_id_i(local_node_id),
    .root_uuid_i(root_uuid),
    .keyex_msg_valid_i(keyex_msg_valid),
    .keyex_msg_src_node_id_i(keyex_msg_src),
    .keyex_msg_i(keyex_msg),
    .keyex_tx_valid_o(keyex_tx_valid),
    .keyex_tx_msg_o(keyex_tx_msg),
    .install_key_valid_o(install_key_valid),
    .install_slot_o(install_slot),
    .install_key_o(install_key),
    .install_salt_o(install_salt),
    .switch_keyslot_valid_o(switch_keyslot_valid),
    .switch_keyslot_o(switch_keyslot),
    .policy_o(policy),
    .keyex_report_10pct_i(rep10),
    .keyex_report_5pct_i(rep5),
    .keyex_overflow_i(repovf)
  );

  task automatic clear_req();
    keyex_msg_valid = 1'b0;
    keyex_msg = '0;
  endtask

  task automatic clear_monitors();
    mon_tx_seen = 1'b0;
    mon_tx_msg = '0;
    install_seen_count = 0;
    first_install_slot = '0;
    second_install_slot = '0;
    first_install_key = '0;
    second_install_key = '0;
    first_install_salt = '0;
    second_install_salt = '0;
    mon_switch_seen = 1'b0;
    mon_switch_slot = 1'b0;
  endtask

  task automatic send_req(input oam_keyex_msg_t msg);
    clear_monitors();
    keyex_msg = msg;
    keyex_msg.valid = 1'b1;
    keyex_msg.is_response = 1'b0;
    keyex_msg_valid = 1'b1;
    @(posedge clk); #1;
    if (keyex_tx_valid) begin
      mon_tx_seen = 1'b1;
      mon_tx_msg = keyex_tx_msg;
    end
    if (install_key_valid) begin
      if (install_seen_count == 0) begin
        first_install_slot = install_slot;
        first_install_key = install_key;
        first_install_salt = install_salt;
      end else if (install_seen_count == 1) begin
        second_install_slot = install_slot;
        second_install_key = install_key;
        second_install_salt = install_salt;
      end
      install_seen_count = install_seen_count + 1;
    end
    if (switch_keyslot_valid) begin
      mon_switch_seen = 1'b1;
      mon_switch_slot = switch_keyslot;
    end
    keyex_msg_valid = 1'b0;
    keyex_msg = '0;
    @(posedge clk); #1;
    if (keyex_tx_valid) begin
      mon_tx_seen = 1'b1;
      mon_tx_msg = keyex_tx_msg;
    end
    if (install_key_valid) begin
      if (install_seen_count == 0) begin
        first_install_slot = install_slot;
        first_install_key = install_key;
        first_install_salt = install_salt;
      end else if (install_seen_count == 1) begin
        second_install_slot = install_slot;
        second_install_key = install_key;
        second_install_salt = install_salt;
      end
      install_seen_count = install_seen_count + 1;
    end
    if (switch_keyslot_valid) begin
      mon_switch_seen = 1'b1;
      mon_switch_slot = switch_keyslot;
    end
  endtask

  function automatic oam_keyex_msg_t build_install_uuid(input logic [127:0] uuid);
    oam_keyex_msg_t m;
    m = '0;
    m.valid = 1'b1;
    m.payload[7:0] = KEYEX_ID_INSTALL_UUID;
    m.payload = keyex_put_u128_be(m.payload, 1, uuid);
    m.payload_len = 8'd17;
    return m;
  endfunction

  function automatic oam_keyex_msg_t build_plain_key(
    input logic [7:0] prim,
    input logic [127:0] keyv
  );
    oam_keyex_msg_t m;
    m = '0;
    m.valid = 1'b1;
    m.payload[7:0] = prim;
    m.payload = keyex_put_u128_be(m.payload, 1, keyv);
    m.payload_len = 8'd17;
    return m;
  endfunction

  function automatic oam_keyex_msg_t build_simple_req(input logic [7:0] prim);
    oam_keyex_msg_t m;
    m = '0;
    m.valid = 1'b1;
    m.payload[7:0] = prim;
    m.payload_len = 8'd1;
    return m;
  endfunction

  function automatic oam_keyex_msg_t build_setup_policy(
    input logic [31:0] pcn,
    input logic persist,
    input logic [4:0] node_id,
    input logic [1:0] pol
  );
    oam_keyex_msg_t m;
    m = '0;
    m.valid = 1'b1;
    m.payload[7:0] = KEYEX_ID_SETUP_POLICY;
    m.payload = keyex_put_u32_be(m.payload, 1, pcn);
    m.payload[5*8 +: 8] = {7'd0, persist};
    m.payload[6*8 +: 8] = 8'd1;
    m.payload[7*8 +: 8] = {node_id, 3'b000};
    m.payload[8*8 +: 8] = {6'd0, pol};
    m.payload_len = 8'd9;
    return m;
  endfunction

  function automatic oam_keyex_msg_t build_protected_key_req(
    input logic [7:0] prim,
    input logic [127:0] auth_key128,
    input logic [29:0] salt,
    input logic [31:0] pcn,
    input logic [31:0] ctr,
    input logic [31:0] nonce,
    input logic [127:0] uuid,
    input logic [127:0] key_plain
  );
    oam_keyex_msg_t m;
    logic [95:0] iv;
    oam_cad_bytes_t aad, crypt;
    logic [127:0] icv;
    m = '0;
    aad = '0;
    crypt = '0;
    iv = keyex_build_iv(1'b0, salt, pcn, ctr);
    aad = keyex_put_u32_be(aad, 0, nonce);
    aad = keyex_put_u128_be(aad, 4, uuid);
    aad[20*8 +: 8] = 8'd16;
    crypt = keyex_put_u128_be(crypt, 0, key_plain);
    crypt = keyex_crypt_bytes(keyex_expand_key128(auth_key128), 16, iv, crypt, 16);
    icv = keyex_compute_icv(keyex_expand_key128(auth_key128), 16, iv, prim, aad, 21, crypt, 16);
    m.valid = 1'b1;
    m.payload[7:0] = prim;
    m.payload = keyex_put_u96_be(m.payload, 1, iv);
    m.payload = keyex_put_u32_be(m.payload, 13, nonce);
    m.payload = keyex_put_u128_be(m.payload, 17, uuid);
    m.payload[33*8 +: 8] = 8'd16;
    for (int i = 0; i < 16; i++) m.payload[(34+i)*8 +: 8] = crypt[i*8 +: 8];
    m.payload = keyex_put_u128_be(m.payload, 50, icv);
    m.payload_len = 8'd66;
    return m;
  endfunction

  function automatic oam_keyex_msg_t build_install_lks_req(
    input logic [127:0] bk,
    input logic [29:0] salt,
    input logic [31:0] pcn,
    input logic [31:0] ctr,
    input logic [31:0] nonce,
    input logic [127:0] uuid,
    input logic [4:0] node_id,
    input logic [127:0] key0,
    input logic [31:0] salt0,
    input logic [127:0] key1,
    input logic [31:0] salt1
  );
    oam_keyex_msg_t m;
    logic [95:0] iv;
    oam_cad_bytes_t aad, lks, crypt;
    logic [127:0] icv;
    m = '0;
    aad = '0;
    lks = '0;
    crypt = '0;
    iv = keyex_build_iv(1'b0, salt, pcn, ctr);
    lks[0*8 +: 8] = 8'd2;
    lks[1*8 +: 8] = 8'd16;
    lks[2*8 +: 8] = 8'd4;
    lks[3*8 +: 8] = 8'd0;
    lks[4*8 +: 8] = {node_id, 2'b00, 1'b0};
    lks = keyex_put_u128_be(lks, 5, key0);
    lks = keyex_put_u32_be(lks, 21, salt0);
    lks[25*8 +: 8] = {node_id, 2'b00, 1'b1};
    lks = keyex_put_u128_be(lks, 26, key1);
    lks = keyex_put_u32_be(lks, 42, salt1);
    crypt = keyex_crypt_bytes(keyex_expand_key128(bk), 16, iv, lks, 46);
    aad = keyex_put_u32_be(aad, 0, nonce);
    aad = keyex_put_u128_be(aad, 4, uuid);
    aad[20*8 +: 8] = 8'd16;
    aad = keyex_put_u16_be(aad, 21, 16'd46);
    icv = keyex_compute_icv(keyex_expand_key128(bk), 16, iv, KEYEX_ID_INSTALL_LKS_ENC, aad, 23, crypt, 46);
    m.valid = 1'b1;
    m.payload[7:0] = KEYEX_ID_INSTALL_LKS_ENC;
    m.payload = keyex_put_u96_be(m.payload, 1, iv);
    m.payload = keyex_put_u32_be(m.payload, 13, nonce);
    m.payload = keyex_put_u128_be(m.payload, 17, uuid);
    m.payload[33*8 +: 8] = 8'd16;
    m.payload = keyex_put_u16_be(m.payload, 34, 16'd46);
    for (int i = 0; i < 46; i++) m.payload[(36+i)*8 +: 8] = crypt[i*8 +: 8];
    m.payload = keyex_put_u128_be(m.payload, 82, icv);
    m.payload_len = 8'd98;
    return m;
  endfunction

  function automatic oam_keyex_msg_t build_change_slot_req(
    input logic [127:0] bk,
    input logic [29:0] salt,
    input logic [31:0] pcn,
    input logic [31:0] ctr,
    input logic [31:0] nonce,
    input logic [127:0] uuid,
    input logic slot
  );
    oam_keyex_msg_t m;
    logic [95:0] iv;
    oam_cad_bytes_t aad;
    logic [127:0] icv;
    m = '0;
    aad = '0;
    iv = keyex_build_iv(1'b0, salt, pcn, ctr);
    aad = keyex_put_u32_be(aad, 0, nonce);
    aad = keyex_put_u128_be(aad, 4, uuid);
    aad[20*8 +: 8] = {7'd0, slot};
    icv = keyex_compute_icv(keyex_expand_key128(bk), 16, iv, KEYEX_ID_CHANGE_LK_SLOT, aad, 21, '0, 0);
    m.valid = 1'b1;
    m.payload[7:0] = KEYEX_ID_CHANGE_LK_SLOT;
    m.payload = keyex_put_u96_be(m.payload, 1, iv);
    m.payload = keyex_put_u32_be(m.payload, 13, nonce);
    m.payload = keyex_put_u128_be(m.payload, 17, uuid);
    m.payload[33*8 +: 8] = {7'd0, slot};
    m.payload = keyex_put_u128_be(m.payload, 34, icv);
    m.payload_len = 8'd50;
    return m;
  endfunction

  initial begin
    pass_count = 0;
    fail_count = 0;
    rst = 1;
    soft_reset = 0;
    local_node_id = 5'd3;
    root_uuid = 128'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_1111_2222;
    keyex_msg_valid = 0;
    keyex_msg_src = 5'd1;
    keyex_msg = '0;
    rep10 = 0;
    rep5 = 0;
    repovf = 0;
    tick(3);
    rst = 0;
    tick();

    $display("T1: install_UUID");
    send_req(build_install_uuid(128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210));
    check("T1a status ok", mon_tx_seen && mon_tx_msg.payload[15:8] == KEYEX_ST_OK);

    $display("T2: second install_UUID rejected");
    send_req(build_install_uuid(128'h0));
    check("T2a already written", mon_tx_msg.payload[15:8] == KEYEX_ST_ALREADY_WRITTEN);

    $display("T3: read_UUID");
    send_req(build_simple_req(KEYEX_ID_READ_UUID));
    check("T3a read uuid ok", mon_tx_msg.payload[15:8] == KEYEX_ST_OK);
    check("T3b uuid echoes", keyex_get_u128_be(mon_tx_msg.payload, 2) == 128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210);

    $display("T4: read_current_nonce");
    send_req(build_simple_req(KEYEX_ID_READ_NONCE));
    check("T4a nonce resp ok", mon_tx_msg.payload[15:8] == KEYEX_ST_OK);
    check("T4b nonce value", keyex_get_u32_be(mon_tx_msg.payload, 2) == 32'h1ACE_B00C);

    $display("T5: setup_policy");
    send_req(build_setup_policy(32'h1ACE_B00C, 1'b0, local_node_id, 2'b11));
    check("T5a policy ok", mon_tx_msg.payload[15:8] == KEYEX_ST_OK);
    check("T5b policy latched", policy == 2'b11);

    $display("T6: install DK0 / DK1");
    send_req(build_plain_key(KEYEX_ID_INSTALL_DK0, 128'h0011_2233_4455_6677_8899_AABB_CCDD_EEFF));
    check("T6a dk0 ok", mon_tx_msg.payload[15:8] == KEYEX_ST_OK);
    send_req(build_plain_key(KEYEX_ID_INSTALL_DK1_PLAIN, 128'h1021_3243_5465_7687_98A9_BACB_DCED_FE0F));
    check("T6b dk1 ok", mon_tx_msg.payload[15:8] == KEYEX_ST_OK);

    $display("T7: install BK encrypted");
    send_req(build_protected_key_req(
      KEYEX_ID_INSTALL_BK_ENC,
      128'h1030_1070_1030_10F0_1030_1070_1030_10F0,
      30'h01234567,
      32'h1ACE_B00C,
      32'd1,
      32'hDEAD_BEEF,
      128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210,
      128'hCAFE_BABE_0123_4567_89AB_CDEF_1357_2468
    ));
    check("T7a bk install ok", mon_tx_msg.payload[15:8] == KEYEX_ST_OK);

    $display("T8: read_status_keys");
    send_req(build_simple_req(KEYEX_ID_READ_STATUS_KEYS));
    check("T8a status keys ok", mon_tx_msg.payload[15:8] == KEYEX_ST_OK);
    check("T8b dk/bk bits set", mon_tx_msg.payload[23:16] == 8'h07);

    $display("T9: install LKs encrypted");
    send_req(build_install_lks_req(
      128'hCAFE_BABE_0123_4567_89AB_CDEF_1357_2468,
      30'h01234567,
      32'h1ACE_B00C,
      32'd2,
      32'h0BAD_F00D,
      128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210,
      local_node_id,
      128'h1111_2222_3333_4444_5555_6666_7777_8888,
      32'h0000_0011,
      128'h9999_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0001,
      32'h0000_0022
    ));
    check("T9a lk install ok", mon_tx_msg.payload[15:8] == KEYEX_ST_OK);
    tick();
    check("T9b first install pulse", install_seen_count >= 1 && first_install_slot == 1'b0);
    check("T9c first key value", first_install_key == 128'h1111_2222_3333_4444_5555_6666_7777_8888);
    check("T9d second install pulse", install_seen_count >= 2 && second_install_slot == 1'b1);
    check("T9e second key value", second_install_key == 128'h9999_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0001);

    $display("T10: change key slot");
    send_req(build_change_slot_req(
      128'hCAFE_BABE_0123_4567_89AB_CDEF_1357_2468,
      30'h0000_0011,
      32'h1ACE_B00C,
      32'd3,
      32'hABCD_0123,
      128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210,
      1'b1
    ));
    check("T10a change slot ok", mon_tx_msg.payload[15:8] == KEYEX_ST_OK);
    check("T10b switch pulse", mon_switch_seen && mon_switch_slot == 1'b1);

    $display("T11: replay IV rejected");
    send_req(build_change_slot_req(
      128'hCAFE_BABE_0123_4567_89AB_CDEF_1357_2468,
      30'h0000_0011,
      32'h1ACE_B00C,
      32'd3,
      32'hABCD_0123,
      128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210,
      1'b0
    ));
    check("T11a replay auth fail", mon_tx_msg.payload[15:8] == KEYEX_ST_AUTH_FAILED);

    $display("T12: wrong UUID on protected request");
    send_req(build_change_slot_req(
      128'hCAFE_BABE_0123_4567_89AB_CDEF_1357_2468,
      30'h0000_0011,
      32'h1ACE_B00C,
      32'd4,
      32'hABCD_9999,
      128'h0000_0000_0000_0000_0000_0000_0000_0001,
      1'b0
    ));
    check("T12a wrong uuid", mon_tx_msg.payload[15:8] == KEYEX_ST_WRONG_UUID);

    $display("T13: read_status_keys_ext");
    begin
      oam_keyex_msg_t m;
      m = '0;
      m.valid = 1'b1;
      m.payload[7:0] = KEYEX_ID_READ_STATUS_KEYS_EXT;
      m.payload = keyex_put_u128_be(m.payload, 1, 128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210);
      m.payload = keyex_put_u32_be(m.payload, 17, 32'h1111_2222);
      m.payload_len = 8'd21;
      send_req(m);
      $display("T13 debug: seen=%0d prim=0x%02x status=0x%02x len=%0d",
               mon_tx_seen, mon_tx_msg.payload[7:0], mon_tx_msg.payload[15:8], mon_tx_msg.payload_len);
      check("T13a0 primitive", mon_tx_msg.payload[7:0] == KEYEX_ID_READ_STATUS_KEYS_EXT);
      check("T13a status ext ok", mon_tx_msg.payload[15:8] == KEYEX_ST_OK);
      check("T13b response is protected", mon_tx_msg.payload_len > 8'd30);
      check("T13c response length", mon_tx_msg.payload_len == 8'd50);
      check("T13d status_dk_bk", mon_tx_msg.payload[14*8 +: 8] == 8'h07);
      check("T13e status node count", mon_tx_msg.payload[15*8 +: 8] == 8'd1);
    end

    $display("T14: spontaneous report_status_LK");
    clear_monitors();
    rep10 = 1'b1;
    @(posedge clk); #1;
    if (keyex_tx_valid) begin
      mon_tx_seen = 1'b1;
      mon_tx_msg = keyex_tx_msg;
    end
    rep10 = 1'b0;
    check("T14a report emitted", mon_tx_seen);
    check("T14b report primitive", mon_tx_msg.payload[7:0] == KEYEX_ID_REPORT_STATUS_LK);
    check("T14c report request, not response", !mon_tx_msg.is_response);

    tick(2);
    $display("");
    $display("========================================");
    $display("Results: %0d passed, %0d failed", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) $display("keyex_tb: ALL TESTS PASSED");
    else                 $display("keyex_tb: SOME TESTS FAILED");
    $finish;
  end

  initial begin
    #500000;
    $display("TIMEOUT");
    $finish;
  end

endmodule

`default_nettype wire
