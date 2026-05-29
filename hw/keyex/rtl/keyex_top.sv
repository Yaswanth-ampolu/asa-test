`timescale 1ns/1ps
`default_nettype none

module keyex_top
  import asa_oam_pkg::*;
  import asa_keyex_pkg::*;
(
  input  logic              clk,
  input  logic              rst,
  input  logic              soft_reset_i,
  input  logic [4:0]        local_node_id_i,
  input  logic [127:0]      root_uuid_i,

  input  logic              keyex_msg_valid_i,
  input  logic [4:0]        keyex_msg_src_node_id_i,
  input  oam_keyex_msg_t    keyex_msg_i,

  output logic              keyex_tx_valid_o,
  output oam_keyex_msg_t    keyex_tx_msg_o,

  output logic              install_key_valid_o,
  output logic              install_slot_o,
  output logic [127:0]      install_key_o,
  output logic [29:0]       install_salt_o,
  output logic              switch_keyslot_valid_o,
  output logic              switch_keyslot_o,
  output logic [1:0]        policy_o,

  input  logic              keyex_report_10pct_i,
  input  logic              keyex_report_5pct_i,
  input  logic              keyex_overflow_i
);

  logic [127:0] uuid_q, dk0_q, dk1_q, bk_q;
  logic [31:0]  pcn_q;
  logic [1:0]   policy_q;
  logic         uuid_written_q, dk0_written_q, dk1_written_q, bk_written_q;
  logic         policy_persist_q;
  logic [31:0]  keyex_tx_ctr_q, last_root_ctr_q;
  logic         session_salt_valid_q;
  logic [29:0]  session_salt_q;
  logic [127:0] lk_key_q [0:1];
  logic [29:0]  lk_salt_q [0:1];
  logic [63:0]  lk_tx_ctr_q [0:1];
  keyex_slot_state_e slot_tx_q [0:1];
  keyex_slot_state_e slot_rx_q [0:1];
  logic               pending_install_valid_q;
  logic               pending_install_slot_q;
  logic [127:0]       pending_install_key_q;
  logic [29:0]        pending_install_salt_q;
  logic               report_10_seen_q, report_5_seen_q;

  function automatic logic any_lk_present();
    return (slot_tx_q[0] != KEYEX_SLOT_EMPTY) || (slot_tx_q[1] != KEYEX_SLOT_EMPTY) ||
           (slot_rx_q[0] != KEYEX_SLOT_EMPTY) || (slot_rx_q[1] != KEYEX_SLOT_EMPTY);
  endfunction

  function automatic logic [255:0] get_key_material(input logic [7:0] primitive_id);
    logic [127:0] dk;
    dk = dk0_q ^ dk1_q;
    case (primitive_id)
      KEYEX_ID_INSTALL_DK1_ENC:     return keyex_expand_key128(dk0_q);
      KEYEX_ID_INSTALL_BK_ENC:      return keyex_expand_key128(dk);
      KEYEX_ID_INSTALL_BK_DK1_ONLY: return keyex_expand_key128(dk1_q);
      KEYEX_ID_INSTALL_LKS_ENC,
      KEYEX_ID_CHANGE_LK_SLOT,
      KEYEX_ID_READ_STATUS_KEYS_EXT,
      KEYEX_ID_REPORT_STATUS_LK:    return keyex_expand_key128(bk_q);
      default:                      return keyex_expand_key128(128'h0);
    endcase
  endfunction

  function automatic int unsigned get_key_bytes(input logic [7:0] primitive_id);
    case (primitive_id)
      KEYEX_ID_INSTALL_LKS_ENC,
      KEYEX_ID_CHANGE_LK_SLOT,
      KEYEX_ID_READ_STATUS_KEYS_EXT,
      KEYEX_ID_REPORT_STATUS_LK: return 16;
      default:                   return 16;
    endcase
  endfunction

  function automatic logic [7:0] missing_prereq_status(input logic [7:0] primitive_id);
    case (primitive_id)
      KEYEX_ID_INSTALL_DK1_ENC: begin
        if (!dk0_written_q) return KEYEX_ST_DK0_MISSING;
      end
      KEYEX_ID_INSTALL_BK_ENC: begin
        if (!dk0_written_q) return KEYEX_ST_DK0_MISSING;
        if (!dk1_written_q) return KEYEX_ST_DK1_MISSING;
      end
      KEYEX_ID_INSTALL_BK_DK1_ONLY: begin
        if (!dk1_written_q) return KEYEX_ST_DK1_MISSING;
      end
      KEYEX_ID_READ_STATUS_KEYS_EXT: begin
        if (!bk_written_q) return KEYEX_ST_BK_MISSING;
      end
      KEYEX_ID_INSTALL_LKS_ENC,
      KEYEX_ID_CHANGE_LK_SLOT,
      KEYEX_ID_REPORT_STATUS_LK: begin
        if (!dk0_written_q) return KEYEX_ST_DK0_MISSING;
        if (!dk1_written_q) return KEYEX_ST_DK1_MISSING;
        if (!bk_written_q)  return KEYEX_ST_BK_MISSING;
      end
      default: ;
    endcase
    return KEYEX_ST_OK;
  endfunction

  task automatic emit_basic_response(
    input logic [7:0] primitive_id,
    input logic [7:0] status,
    input oam_cad_bytes_t extra_payload,
    input int unsigned extra_len
  );
    oam_keyex_msg_t resp;
    resp = '0;
    resp.valid = 1'b1;
    resp.is_response = 1'b1;
    resp.payload[7:0] = primitive_id;
    resp.payload[15:8] = status;
    for (int i = 0; i < extra_len; i++) begin
      resp.payload[(i+2)*8 +: 8] = extra_payload[i*8 +: 8];
    end
    resp.payload_len = 8'(extra_len + 2);
    keyex_tx_valid_o          <= 1'b1;
    keyex_tx_msg_o            <= resp;
  endtask

  task automatic emit_secured_response(
    input logic [7:0] primitive_id,
    input logic [7:0] status,
    input logic [29:0] salt,
    input oam_cad_bytes_t aad_bytes,
    input int unsigned aad_len,
    input oam_cad_bytes_t data_bytes,
    input int unsigned data_len,
    input logic [255:0] icv_key,
    input int unsigned icv_key_len
  );
    logic [95:0] iv;
    logic [127:0] icv;
    oam_cad_bytes_t payload;
    int unsigned idx;
    iv  = keyex_build_iv(1'b1, salt, pcn_q, keyex_tx_ctr_q);
    icv = keyex_compute_icv(icv_key, icv_key_len, iv, primitive_id, aad_bytes, aad_len, data_bytes, data_len);
    payload = '0;
    payload[7:0] = primitive_id;
    payload[15:8] = status;
    payload = keyex_put_u96_be(payload, 2, iv);
    idx = 14;
    for (int i = 0; i < data_len; i++) begin
      payload[(idx+i)*8 +: 8] = data_bytes[i*8 +: 8];
    end
    idx = idx + data_len;
    payload = keyex_put_u128_be(payload, idx, icv);
    keyex_tx_msg_o.valid        <= 1'b1;
    keyex_tx_msg_o.is_response  <= 1'b1;
    keyex_tx_msg_o.payload      <= payload;
    keyex_tx_msg_o.payload_len  <= 8'(idx + 16);
    keyex_tx_valid_o            <= 1'b1;
    keyex_tx_ctr_q              <= keyex_tx_ctr_q + 32'd1;
  endtask

  always_ff @(posedge clk or posedge rst) begin : p_keyex
    logic [7:0] primitive_id, tmp_byte;
    logic [7:0] status;
    logic [7:0] key_len_b, num_entries, salt_len_b, persist_b, target_slot_b;
    logic [15:0] lks_len_b;
    logic [31:0] nonce_src, req_pcn, incoming_ctr;
    logic [95:0] iv_in;
    logic [127:0] uuid_in, tmp_key, tmp_uuid;
    logic [255:0] auth_key;
    logic [29:0]  iv_salt, salt0, salt1;
    logic [31:0]  iv_pcn;
    logic         iv_dir, iv_keyex, match_uuid, first_local_seen, second_local_seen;
    logic [127:0] icv_expected, icv_rx, decrypted_key;
    oam_cad_bytes_t aad, data_bytes, crypt_bytes, extra, report_bytes;
    int unsigned aad_len, data_len, off, report_len;
    logic found_slot;
    int slot_idx;
    oam_keyex_msg_t report_msg;

    if (rst) begin
      uuid_q <= '0;
      dk0_q <= '0;
      dk1_q <= '0;
      bk_q  <= '0;
      pcn_q <= 32'h1ACE_B00C;
      policy_q <= 2'b00;
      uuid_written_q <= 1'b0;
      dk0_written_q  <= 1'b0;
      dk1_written_q  <= 1'b0;
      bk_written_q   <= 1'b0;
      policy_persist_q <= 1'b0;
      keyex_tx_ctr_q <= 32'd1;
      last_root_ctr_q <= 32'd0;
      session_salt_valid_q <= 1'b0;
      session_salt_q <= '0;
      report_10_seen_q <= 1'b0;
      report_5_seen_q <= 1'b0;
      for (int i = 0; i < 2; i++) begin
        lk_key_q[i] <= '0;
        lk_salt_q[i] <= '0;
        lk_tx_ctr_q[i] <= (i == 0) ? 64'd1 : 64'd0;
        slot_tx_q[i] <= KEYEX_SLOT_EMPTY;
        slot_rx_q[i] <= KEYEX_SLOT_EMPTY;
      end
      pending_install_valid_q <= 1'b0;
      pending_install_slot_q <= 1'b0;
      pending_install_key_q <= '0;
      pending_install_salt_q <= '0;
      keyex_tx_valid_o <= 1'b0;
      keyex_tx_msg_o <= '0;
      install_key_valid_o <= 1'b0;
      install_slot_o <= 1'b0;
      install_key_o <= '0;
      install_salt_o <= '0;
      switch_keyslot_valid_o <= 1'b0;
      switch_keyslot_o <= 1'b0;
    end else begin
      if (soft_reset_i) begin
        policy_q <= 2'b00;
        keyex_tx_ctr_q <= 32'd1;
        last_root_ctr_q <= 32'd0;
        session_salt_valid_q <= 1'b0;
        session_salt_q <= '0;
        report_10_seen_q <= 1'b0;
        report_5_seen_q <= 1'b0;
        pending_install_valid_q <= 1'b0;
      end

      keyex_tx_valid_o <= 1'b0;
      keyex_tx_msg_o.valid <= 1'b0;
      install_key_valid_o <= 1'b0;
      switch_keyslot_valid_o <= 1'b0;

      if (pending_install_valid_q) begin
        install_key_valid_o <= 1'b1;
        install_slot_o <= pending_install_slot_q;
        install_key_o  <= pending_install_key_q;
        install_salt_o <= pending_install_salt_q;
        pending_install_valid_q <= 1'b0;
      end

      if (keyex_overflow_i || (keyex_report_5pct_i && !report_5_seen_q) || (keyex_report_10pct_i && !report_10_seen_q)) begin
        report_bytes = '0;
        report_msg = '0;
        report_bytes = keyex_set_byte(report_bytes, 0, 8'd1);
        report_bytes = keyex_set_byte(report_bytes, 1, {local_node_id_i, 3'b000});
        report_bytes = keyex_set_byte(report_bytes, 2, keyex_status_lks_byte(slot_rx_q[0], slot_tx_q[0], slot_rx_q[1], slot_tx_q[1]));
        report_bytes = keyex_put_u64_be(report_bytes, 3, lk_tx_ctr_q[0]);
        report_bytes = keyex_put_u64_be(report_bytes, 11, lk_tx_ctr_q[1]);
        iv_salt = (slot_tx_q[0] != KEYEX_SLOT_EMPTY) ? lk_salt_q[0] : lk_salt_q[1];
        iv_in = keyex_build_iv(1'b1, iv_salt, pcn_q, keyex_tx_ctr_q);
        icv_expected = keyex_compute_icv(
          keyex_expand_key128(bk_q), 16, iv_in, KEYEX_ID_REPORT_STATUS_LK,
          report_bytes, 19, '0, 0
        );
        report_msg.valid       = 1'b1;
        report_msg.is_response = 1'b0;
        report_msg.payload[7:0] = KEYEX_ID_REPORT_STATUS_LK;
        report_msg.payload      = keyex_put_u96_be(report_msg.payload, 1, iv_in);
        report_msg.payload      = keyex_put_u128_be(report_msg.payload, 13, root_uuid_i);
        for (int i = 0; i < 19; i++) begin
          report_msg.payload[(29+i)*8 +: 8] = report_bytes[i*8 +: 8];
        end
        report_msg.payload      = keyex_put_u128_be(report_msg.payload, 48, icv_expected);
        report_msg.payload_len  = 8'd64;
        keyex_tx_valid_o           <= bk_written_q;
        keyex_tx_msg_o            <= report_msg;
        if (bk_written_q) begin
          keyex_tx_ctr_q <= keyex_tx_ctr_q + 32'd1;
          if (keyex_report_10pct_i) report_10_seen_q <= 1'b1;
          if (keyex_report_5pct_i)  report_5_seen_q  <= 1'b1;
        end
      end else if (keyex_msg_valid_i && keyex_msg_i.valid && !keyex_msg_i.is_response) begin
        primitive_id = keyex_msg_i.payload[7:0];
        status       = missing_prereq_status(primitive_id);
        nonce_src    = '0;
        req_pcn      = '0;
        uuid_in      = '0;
        aad          = '0;
        aad_len      = 0;
        data_bytes   = '0;
        data_len     = 0;
        auth_key     = get_key_material(primitive_id);
        off          = 1;
        first_local_seen  = 1'b0;
        second_local_seen = 1'b0;
        salt0 = '0;
        salt1 = '0;
        match_uuid = 1'b1;

        if (keyex_request_protected(primitive_id)) begin
          iv_in       = keyex_get_u96_be(keyex_msg_i.payload, off);
          off         = off + 12;
          iv_keyex    = iv_in[95];
          iv_dir      = iv_in[94];
          iv_salt     = iv_in[93:64];
          iv_pcn      = iv_in[63:32];
          incoming_ctr= iv_in[31:0];
          if (!iv_keyex || iv_dir || (iv_pcn != pcn_q) || (incoming_ctr <= last_root_ctr_q)) begin
            status = KEYEX_ST_AUTH_FAILED;
          end
          if (session_salt_valid_q && (iv_salt != session_salt_q)) begin
            status = KEYEX_ST_AUTH_FAILED;
          end
        end

        case (primitive_id)
          KEYEX_ID_INSTALL_UUID: begin
            tmp_uuid = keyex_get_u128_be(keyex_msg_i.payload, 1);
            if (uuid_written_q) status = KEYEX_ST_ALREADY_WRITTEN;
            if (status == KEYEX_ST_OK) begin
              uuid_q <= tmp_uuid;
              uuid_written_q <= 1'b1;
            end
            emit_basic_response(primitive_id, status, '0, 0);
          end

          KEYEX_ID_READ_UUID: begin
            extra = '0;
            status = uuid_written_q ? KEYEX_ST_OK : KEYEX_ST_UUID_NOT_WRITTEN;
            extra = keyex_put_u128_be(extra, 0, uuid_q);
            emit_basic_response(primitive_id, status, extra, 16);
          end

          KEYEX_ID_READ_NONCE: begin
            extra = '0;
            extra = keyex_put_u32_be(extra, 0, pcn_q);
            emit_basic_response(primitive_id, KEYEX_ST_OK, extra, 4);
          end

          KEYEX_ID_READ_STATUS_KEYS: begin
            extra = '0;
            extra = keyex_set_byte(extra, 0, keyex_status_dk_bk(dk0_written_q, dk1_written_q, bk_written_q));
            extra = keyex_set_byte(extra, 1, 8'd1);
            extra = keyex_set_byte(extra, 2, {local_node_id_i, 3'b000});
            extra = keyex_set_byte(extra, 3, keyex_status_lks_byte(slot_rx_q[0], slot_tx_q[0], slot_rx_q[1], slot_tx_q[1]));
            emit_basic_response(primitive_id, KEYEX_ST_OK, extra, 4);
          end

          KEYEX_ID_READ_STATUS_KEYS_EXT: begin
            uuid_in = keyex_get_u128_be(keyex_msg_i.payload, 1);
            nonce_src = keyex_get_u32_be(keyex_msg_i.payload, 17);
            if (!uuid_written_q) status = KEYEX_ST_UUID_NOT_WRITTEN;
            else if (uuid_in != uuid_q) status = KEYEX_ST_WRONG_UUID;
            else if (!any_lk_present()) status = KEYEX_ST_LK_NOT_WRITTEN;
            report_bytes = '0;
            report_bytes = keyex_set_byte(report_bytes, 0, keyex_status_dk_bk(dk0_written_q, dk1_written_q, bk_written_q));
            report_bytes = keyex_set_byte(report_bytes, 1, 8'd1);
            report_bytes = keyex_set_byte(report_bytes, 2, {local_node_id_i, 3'b000});
            report_bytes = keyex_set_byte(report_bytes, 3, keyex_status_lks_byte(slot_rx_q[0], slot_tx_q[0], slot_rx_q[1], slot_tx_q[1]));
            report_bytes = keyex_put_u64_be(report_bytes, 4, lk_tx_ctr_q[0]);
            report_bytes = keyex_put_u64_be(report_bytes, 12, lk_tx_ctr_q[1]);
            aad = '0;
            aad = keyex_put_u128_be(aad, 0, uuid_in);
            aad = keyex_put_u32_be(aad, 16, nonce_src);
            aad = keyex_set_byte(aad, 20, status);
            if (status == KEYEX_ST_OK) begin
              emit_secured_response(primitive_id, status, session_salt_valid_q ? session_salt_q : 30'd0,
                                    aad, 21, report_bytes, 20, auth_key, 16);
            end else begin
              emit_basic_response(primitive_id, status, '0, 0);
            end
          end

          KEYEX_ID_SETUP_POLICY: begin
            req_pcn   = keyex_get_u32_be(keyex_msg_i.payload, 1);
            persist_b = keyex_get_byte(keyex_msg_i.payload, 5);
            num_entries = keyex_get_byte(keyex_msg_i.payload, 6);
            if (req_pcn != pcn_q) status = KEYEX_ST_UNSPEC;
            else if (policy_persist_q && persist_b[0]) status = KEYEX_ST_ALREADY_WRITTEN;
            else if (num_entries == 0) status = KEYEX_ST_UNSPEC;
            else if (status == KEYEX_ST_OK) begin
              tmp_byte = keyex_get_byte(keyex_msg_i.payload, 8);
              policy_q <= tmp_byte[1:0];
              if (persist_b[0]) policy_persist_q <= 1'b1;
            end
            emit_basic_response(primitive_id, status, '0, 0);
          end

          KEYEX_ID_INSTALL_DK0: begin
            tmp_key = keyex_get_u128_be(keyex_msg_i.payload, 1);
            if (dk0_written_q) status = KEYEX_ST_ALREADY_WRITTEN;
            if (status == KEYEX_ST_OK) begin
              dk0_q <= tmp_key;
              dk0_written_q <= 1'b1;
            end
            emit_basic_response(primitive_id, status, '0, 0);
          end

          KEYEX_ID_INSTALL_DK1_PLAIN: begin
            tmp_key = keyex_get_u128_be(keyex_msg_i.payload, 1);
            if (dk1_written_q) status = KEYEX_ST_ALREADY_WRITTEN;
            if (status == KEYEX_ST_OK) begin
              dk1_q <= tmp_key;
              dk1_written_q <= 1'b1;
            end
            emit_basic_response(primitive_id, status, '0, 0);
          end

          KEYEX_ID_INSTALL_DK1_ENC,
          KEYEX_ID_INSTALL_BK_ENC,
          KEYEX_ID_INSTALL_BK_DK1_ONLY: begin
            nonce_src = keyex_get_u32_be(keyex_msg_i.payload, off);
            uuid_in   = keyex_get_u128_be(keyex_msg_i.payload, off+4);
            key_len_b = keyex_get_byte(keyex_msg_i.payload, off+20);
            data_len  = key_len_b;
            for (int i = 0; i < data_len; i++) begin
              crypt_bytes[i*8 +: 8] = keyex_msg_i.payload[(off+21+i)*8 +: 8];
            end
            icv_rx    = keyex_get_u128_be(keyex_msg_i.payload, off+21+data_len);
            aad = '0;
            aad = keyex_put_u32_be(aad, 0, nonce_src);
            aad = keyex_put_u128_be(aad, 4, uuid_in);
            aad = keyex_set_byte(aad, 20, key_len_b);
            aad_len = 21;
            if (!uuid_written_q || (uuid_in != uuid_q)) status = KEYEX_ST_WRONG_UUID;
            icv_expected = keyex_compute_icv(auth_key, 16, iv_in, primitive_id, aad, aad_len, crypt_bytes, data_len);
            if ((status == KEYEX_ST_OK) && (icv_rx != icv_expected)) status = KEYEX_ST_AUTH_FAILED;
            decrypted_key = keyex_get_u128_be(keyex_crypt_bytes(auth_key, 16, iv_in, crypt_bytes, data_len), 0);
            if (status == KEYEX_ST_OK) begin
              if (primitive_id == KEYEX_ID_INSTALL_DK1_ENC) begin
                dk1_q <= decrypted_key;
                dk1_written_q <= 1'b1;
              end else begin
                bk_q <= decrypted_key;
                bk_written_q <= 1'b1;
                session_salt_valid_q <= 1'b1;
                session_salt_q <= iv_salt;
              end
              last_root_ctr_q <= incoming_ctr;
            end
            if (status == KEYEX_ST_OK) emit_secured_response(primitive_id, status, iv_salt, aad, aad_len, '0, 0, auth_key, 16);
            else emit_basic_response(primitive_id, status, '0, 0);
          end

          KEYEX_ID_INSTALL_LKS_ENC: begin
            nonce_src = keyex_get_u32_be(keyex_msg_i.payload, off);
            uuid_in   = keyex_get_u128_be(keyex_msg_i.payload, off+4);
            key_len_b = keyex_get_byte(keyex_msg_i.payload, off+20);
            lks_len_b = keyex_get_u16_be(keyex_msg_i.payload, off+21);
            for (int i = 0; i < lks_len_b; i++) begin
              crypt_bytes[i*8 +: 8] = keyex_msg_i.payload[(off+23+i)*8 +: 8];
            end
            icv_rx = keyex_get_u128_be(keyex_msg_i.payload, off+23+lks_len_b);
            aad = '0;
            aad = keyex_put_u32_be(aad, 0, nonce_src);
            aad = keyex_put_u128_be(aad, 4, uuid_in);
            aad = keyex_set_byte(aad, 20, key_len_b);
            aad = keyex_put_u16_be(aad, 21, lks_len_b);
            aad_len = 23;
            if (!uuid_written_q || (uuid_in != uuid_q)) status = KEYEX_ST_WRONG_UUID;
            icv_expected = keyex_compute_icv(auth_key, 16, iv_in, primitive_id, aad, aad_len, crypt_bytes, lks_len_b);
            if ((status == KEYEX_ST_OK) && (icv_rx != icv_expected)) status = KEYEX_ST_AUTH_FAILED;
            data_bytes = keyex_crypt_bytes(auth_key, 16, iv_in, crypt_bytes, lks_len_b);
            if (status == KEYEX_ST_OK) begin
              num_entries = keyex_get_byte(data_bytes, 0);
              key_len_b   = keyex_get_byte(data_bytes, 1);
              salt_len_b  = keyex_get_byte(data_bytes, 2);
              if (key_len_b != 8'd16) status = KEYEX_ST_UNSUP_LK_SIZE;
              else if (salt_len_b != 8'd4) status = KEYEX_ST_UNSUP_SALT_SIZE;
              else if (num_entries == 0) status = KEYEX_ST_NOT_ENOUGH_LKS;
              else if (num_entries > 2) status = KEYEX_ST_TOO_MANY_LKS;
            end
            if (status == KEYEX_ST_OK) begin
              if (num_entries >= 1) begin
                target_slot_b = keyex_get_byte(data_bytes, 4);
                if (target_slot_b[7:3] == local_node_id_i) begin
                  tmp_key = keyex_get_u128_be(data_bytes, 5);
                  req_pcn = keyex_get_u32_be(data_bytes, 21);
                  first_local_seen = 1'b1;
                  install_key_valid_o <= 1'b1;
                  install_slot_o      <= target_slot_b[0];
                  install_key_o       <= tmp_key;
                  install_salt_o      <= req_pcn[29:0];
                  if (target_slot_b[0] == 1'b0) begin
                    lk_key_q[0] <= tmp_key;
                    lk_salt_q[0] <= req_pcn[29:0];
                    lk_tx_ctr_q[0] <= 64'd1;
                    if ((slot_tx_q[0] == KEYEX_SLOT_EMPTY) && (slot_tx_q[1] == KEYEX_SLOT_EMPTY) && num_entries == 1) begin
                      slot_tx_q[0] <= KEYEX_SLOT_ACTIVE;
                      slot_rx_q[0] <= KEYEX_SLOT_ACTIVE;
                    end else if (num_entries > 1) begin
                      slot_tx_q[0] <= KEYEX_SLOT_ACTIVE;
                      slot_rx_q[0] <= KEYEX_SLOT_ACTIVE;
                    end else begin
                      slot_tx_q[0] <= KEYEX_SLOT_READY;
                      slot_rx_q[0] <= KEYEX_SLOT_READY;
                    end
                  end else begin
                    lk_key_q[1] <= tmp_key;
                    lk_salt_q[1] <= req_pcn[29:0];
                    lk_tx_ctr_q[1] <= 64'd1;
                    if ((slot_tx_q[0] == KEYEX_SLOT_EMPTY) && (slot_tx_q[1] == KEYEX_SLOT_EMPTY) && num_entries == 1) begin
                      slot_tx_q[1] <= KEYEX_SLOT_ACTIVE;
                      slot_rx_q[1] <= KEYEX_SLOT_ACTIVE;
                    end else begin
                      slot_tx_q[1] <= KEYEX_SLOT_READY;
                      slot_rx_q[1] <= KEYEX_SLOT_READY;
                    end
                  end
                  salt0 = req_pcn[29:0];
                end
              end
              if (num_entries >= 2) begin
                target_slot_b = keyex_get_byte(data_bytes, 25);
                if (target_slot_b[7:3] == local_node_id_i) begin
                  tmp_key = keyex_get_u128_be(data_bytes, 26);
                  req_pcn = keyex_get_u32_be(data_bytes, 42);
                  if (!first_local_seen) begin
                    first_local_seen = 1'b1;
                    install_key_valid_o <= 1'b1;
                    install_slot_o      <= target_slot_b[0];
                    install_key_o       <= tmp_key;
                    install_salt_o      <= req_pcn[29:0];
                    if (target_slot_b[0] == 1'b0) begin
                      lk_key_q[0] <= tmp_key;
                      lk_salt_q[0] <= req_pcn[29:0];
                      lk_tx_ctr_q[0] <= 64'd1;
                      slot_tx_q[0] <= KEYEX_SLOT_ACTIVE;
                      slot_rx_q[0] <= KEYEX_SLOT_ACTIVE;
                    end else begin
                      lk_key_q[1] <= tmp_key;
                      lk_salt_q[1] <= req_pcn[29:0];
                      lk_tx_ctr_q[1] <= 64'd1;
                      slot_tx_q[1] <= KEYEX_SLOT_ACTIVE;
                      slot_rx_q[1] <= KEYEX_SLOT_ACTIVE;
                    end
                    salt0 = req_pcn[29:0];
                  end else begin
                    second_local_seen = 1'b1;
                    pending_install_valid_q <= 1'b1;
                    pending_install_slot_q  <= target_slot_b[0];
                    pending_install_key_q   <= tmp_key;
                    pending_install_salt_q  <= req_pcn[29:0];
                    if (target_slot_b[0] == 1'b0) begin
                      lk_key_q[0] <= tmp_key;
                      lk_salt_q[0] <= req_pcn[29:0];
                      lk_tx_ctr_q[0] <= 64'd1;
                      slot_tx_q[0] <= KEYEX_SLOT_READY;
                      slot_rx_q[0] <= KEYEX_SLOT_READY;
                    end else begin
                      lk_key_q[1] <= tmp_key;
                      lk_salt_q[1] <= req_pcn[29:0];
                      lk_tx_ctr_q[1] <= 64'd1;
                      slot_tx_q[1] <= KEYEX_SLOT_READY;
                      slot_rx_q[1] <= KEYEX_SLOT_READY;
                    end
                    salt1 = req_pcn[29:0];
                  end
                end
              end
              if (!first_local_seen) status = KEYEX_ST_NOT_ENOUGH_LKS;
            end
            if (status == KEYEX_ST_OK) begin
              session_salt_valid_q <= 1'b1;
              session_salt_q <= first_local_seen ? salt0 : iv_salt;
              last_root_ctr_q <= incoming_ctr;
              emit_secured_response(primitive_id, status, first_local_seen ? salt0 : iv_salt, aad, aad_len, '0, 0, auth_key, 16);
            end else begin
              emit_basic_response(primitive_id, status, '0, 0);
            end
          end

          KEYEX_ID_CHANGE_LK_SLOT: begin
            nonce_src     = keyex_get_u32_be(keyex_msg_i.payload, off);
            uuid_in       = keyex_get_u128_be(keyex_msg_i.payload, off+4);
            target_slot_b = keyex_get_byte(keyex_msg_i.payload, off+20);
            icv_rx        = keyex_get_u128_be(keyex_msg_i.payload, off+21);
            aad = '0;
            aad = keyex_put_u32_be(aad, 0, nonce_src);
            aad = keyex_put_u128_be(aad, 4, uuid_in);
            aad = keyex_set_byte(aad, 20, target_slot_b);
            aad_len = 21;
            if (!uuid_written_q || (uuid_in != uuid_q)) status = KEYEX_ST_WRONG_UUID;
            icv_expected = keyex_compute_icv(auth_key, 16, iv_in, primitive_id, aad, aad_len, '0, 0);
            if ((status == KEYEX_ST_OK) && (icv_rx != icv_expected)) status = KEYEX_ST_AUTH_FAILED;
            slot_idx = target_slot_b[0];
            if ((status == KEYEX_ST_OK) && (slot_idx > 1)) status = KEYEX_ST_UNSUP_KEY_SLOT;
            else if ((status == KEYEX_ST_OK) && (slot_tx_q[slot_idx] == KEYEX_SLOT_EMPTY)) status = KEYEX_ST_KEY_SLOT_EMPTY;
            else if ((status == KEYEX_ST_OK) && (slot_tx_q[slot_idx] == KEYEX_SLOT_DEACT)) status = KEYEX_ST_KEY_SLOT_DEACT;
            if (status == KEYEX_ST_OK) begin
              if (target_slot_b[0] == 1'b0) begin
                slot_tx_q[0] <= KEYEX_SLOT_ACTIVE;
                slot_rx_q[0] <= KEYEX_SLOT_ACTIVE;
                if (slot_tx_q[1] != KEYEX_SLOT_EMPTY) begin
                  slot_tx_q[1] <= KEYEX_SLOT_DEACT;
                  slot_rx_q[1] <= KEYEX_SLOT_DEACT;
                end
              end else begin
                slot_tx_q[1] <= KEYEX_SLOT_ACTIVE;
                slot_rx_q[1] <= KEYEX_SLOT_ACTIVE;
                if (slot_tx_q[0] != KEYEX_SLOT_EMPTY) begin
                  slot_tx_q[0] <= KEYEX_SLOT_DEACT;
                  slot_rx_q[0] <= KEYEX_SLOT_DEACT;
                end
              end
              switch_keyslot_valid_o <= 1'b1;
              switch_keyslot_o       <= target_slot_b[0];
              last_root_ctr_q <= incoming_ctr;
            end
            if (status == KEYEX_ST_OK) emit_secured_response(primitive_id, status, target_slot_b[0] ? lk_salt_q[1] : lk_salt_q[0], aad, aad_len, '0, 0, auth_key, 16);
            else emit_basic_response(primitive_id, status, '0, 0);
          end

          default: begin
            emit_basic_response(primitive_id, KEYEX_ST_UNSPEC, '0, 0);
          end
        endcase
      end
    end
  end

  assign policy_o = policy_q;

endmodule

`default_nettype wire
