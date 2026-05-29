`default_nettype none

package asa_keyex_pkg;
  import asa_oam_pkg::*;

  localparam int unsigned KEYEX_IV_BYTES  = 12;
  localparam int unsigned KEYEX_ICV_BYTES = 16;

  typedef enum logic [7:0] {
    KEYEX_ID_INSTALL_UUID          = 8'h00,
    KEYEX_ID_READ_UUID             = 8'h02,
    KEYEX_ID_READ_NONCE            = 8'h04,
    KEYEX_ID_READ_STATUS_KEYS      = 8'h06,
    KEYEX_ID_READ_STATUS_KEYS_EXT  = 8'h07,
    KEYEX_ID_SETUP_POLICY          = 8'h08,
    KEYEX_ID_INSTALL_DK0           = 8'h10,
    KEYEX_ID_INSTALL_DK1_PLAIN     = 8'h12,
    KEYEX_ID_INSTALL_DK1_ENC       = 8'h13,
    KEYEX_ID_INSTALL_BK_ENC        = 8'h21,
    KEYEX_ID_INSTALL_BK_DK1_ONLY   = 8'h23,
    KEYEX_ID_INSTALL_LKS_ENC       = 8'h31,
    KEYEX_ID_CHANGE_LK_SLOT        = 8'h33,
    KEYEX_ID_REPORT_STATUS_LK      = 8'h81
  } keyex_primitive_e;

  typedef enum logic [7:0] {
    KEYEX_ST_OK                = 8'h00,
    KEYEX_ST_NONCE_NOT_READY   = 8'h10,
    KEYEX_ST_AUTH_FAILED       = 8'h11,
    KEYEX_ST_WRONG_UUID        = 8'h12,
    KEYEX_ST_ALREADY_WRITTEN   = 8'h20,
    KEYEX_ST_VERIFY_FAILED     = 8'h21,
    KEYEX_ST_UUID_NOT_WRITTEN  = 8'h30,
    KEYEX_ST_DK0_MISSING       = 8'h40,
    KEYEX_ST_DK1_MISSING       = 8'h41,
    KEYEX_ST_BK_MISSING        = 8'h42,
    KEYEX_ST_MAX_WRITES        = 8'h43,
    KEYEX_ST_LK_NOT_WRITTEN    = 8'h44,
    KEYEX_ST_NOT_ENOUGH_LKS    = 8'h50,
    KEYEX_ST_TOO_MANY_LKS      = 8'h51,
    KEYEX_ST_UNSUP_LK_SIZE     = 8'h52,
    KEYEX_ST_UNSUP_SALT_SIZE   = 8'h53,
    KEYEX_ST_UNSUP_KEY_SLOT    = 8'h60,
    KEYEX_ST_KEY_SLOT_EMPTY    = 8'h61,
    KEYEX_ST_KEY_SLOT_DEACT    = 8'h62,
    KEYEX_ST_UNSPEC            = 8'hFF
  } keyex_status_e;

  typedef enum logic [1:0] {
    KEYEX_SLOT_EMPTY  = 2'b00,
    KEYEX_SLOT_READY  = 2'b01,
    KEYEX_SLOT_DEACT  = 2'b10,
    KEYEX_SLOT_ACTIVE = 2'b11
  } keyex_slot_state_e;

  function automatic logic keyex_request_protected(input logic [7:0] primitive_id);
    case (primitive_id)
      KEYEX_ID_INSTALL_DK1_ENC,
      KEYEX_ID_INSTALL_BK_ENC,
      KEYEX_ID_INSTALL_BK_DK1_ONLY,
      KEYEX_ID_INSTALL_LKS_ENC,
      KEYEX_ID_CHANGE_LK_SLOT: return 1'b1;
      default:                 return 1'b0;
    endcase
  endfunction

  function automatic logic keyex_response_protected(input logic [7:0] primitive_id);
    case (primitive_id)
      KEYEX_ID_READ_STATUS_KEYS_EXT,
      KEYEX_ID_INSTALL_DK1_ENC,
      KEYEX_ID_INSTALL_BK_ENC,
      KEYEX_ID_INSTALL_BK_DK1_ONLY,
      KEYEX_ID_INSTALL_LKS_ENC,
      KEYEX_ID_CHANGE_LK_SLOT,
      KEYEX_ID_REPORT_STATUS_LK: return 1'b1;
      default:                   return 1'b0;
    endcase
  endfunction

  function automatic logic [95:0] keyex_build_iv(
    input logic        dir,
    input logic [29:0] salt,
    input logic [31:0] pcn,
    input logic [31:0] ctr
  );
    return {1'b1, dir, salt, pcn, ctr};
  endfunction

  function automatic logic [7:0] keyex_get_byte(
    input oam_cad_bytes_t bytes,
    input int unsigned idx
  );
    return bytes[idx*8 +: 8];
  endfunction

  function automatic oam_cad_bytes_t keyex_set_byte(
    input oam_cad_bytes_t bytes,
    input int unsigned idx,
    input logic [7:0] value
  );
    oam_cad_bytes_t tmp;
    tmp = bytes;
    tmp[idx*8 +: 8] = value;
    return tmp;
  endfunction

  function automatic logic [15:0] keyex_get_u16_be(
    input oam_cad_bytes_t bytes,
    input int unsigned idx
  );
    return {keyex_get_byte(bytes, idx), keyex_get_byte(bytes, idx+1)};
  endfunction

  function automatic logic [31:0] keyex_get_u32_be(
    input oam_cad_bytes_t bytes,
    input int unsigned idx
  );
    return {keyex_get_byte(bytes, idx), keyex_get_byte(bytes, idx+1),
            keyex_get_byte(bytes, idx+2), keyex_get_byte(bytes, idx+3)};
  endfunction

  function automatic logic [63:0] keyex_get_u64_be(
    input oam_cad_bytes_t bytes,
    input int unsigned idx
  );
    logic [63:0] v;
    v = '0;
    for (int i = 0; i < 8; i++) begin
      v = {v[55:0], keyex_get_byte(bytes, idx+i)};
    end
    return v;
  endfunction

  function automatic logic [95:0] keyex_get_u96_be(
    input oam_cad_bytes_t bytes,
    input int unsigned idx
  );
    logic [95:0] v;
    v = '0;
    for (int i = 0; i < 12; i++) begin
      v = {v[87:0], keyex_get_byte(bytes, idx+i)};
    end
    return v;
  endfunction

  function automatic logic [127:0] keyex_get_u128_be(
    input oam_cad_bytes_t bytes,
    input int unsigned idx
  );
    logic [127:0] v;
    v = '0;
    for (int i = 0; i < 16; i++) begin
      v = {v[119:0], keyex_get_byte(bytes, idx+i)};
    end
    return v;
  endfunction

  function automatic oam_cad_bytes_t keyex_put_u16_be(
    input oam_cad_bytes_t bytes,
    input int unsigned idx,
    input logic [15:0] value
  );
    oam_cad_bytes_t tmp;
    tmp = bytes;
    tmp = keyex_set_byte(tmp, idx,   value[15:8]);
    tmp = keyex_set_byte(tmp, idx+1, value[7:0]);
    return tmp;
  endfunction

  function automatic oam_cad_bytes_t keyex_put_u32_be(
    input oam_cad_bytes_t bytes,
    input int unsigned idx,
    input logic [31:0] value
  );
    oam_cad_bytes_t tmp;
    tmp = bytes;
    for (int i = 0; i < 4; i++) begin
      tmp = keyex_set_byte(tmp, idx+i, value[31-(i*8) -: 8]);
    end
    return tmp;
  endfunction

  function automatic oam_cad_bytes_t keyex_put_u64_be(
    input oam_cad_bytes_t bytes,
    input int unsigned idx,
    input logic [63:0] value
  );
    oam_cad_bytes_t tmp;
    tmp = bytes;
    for (int i = 0; i < 8; i++) begin
      tmp = keyex_set_byte(tmp, idx+i, value[63-(i*8) -: 8]);
    end
    return tmp;
  endfunction

  function automatic oam_cad_bytes_t keyex_put_u96_be(
    input oam_cad_bytes_t bytes,
    input int unsigned idx,
    input logic [95:0] value
  );
    oam_cad_bytes_t tmp;
    tmp = bytes;
    for (int i = 0; i < 12; i++) begin
      tmp = keyex_set_byte(tmp, idx+i, value[95-(i*8) -: 8]);
    end
    return tmp;
  endfunction

  function automatic oam_cad_bytes_t keyex_put_u128_be(
    input oam_cad_bytes_t bytes,
    input int unsigned idx,
    input logic [127:0] value
  );
    oam_cad_bytes_t tmp;
    tmp = bytes;
    for (int i = 0; i < 16; i++) begin
      tmp = keyex_set_byte(tmp, idx+i, value[127-(i*8) -: 8]);
    end
    return tmp;
  endfunction

  function automatic logic [7:0] keyex_status_dk_bk(
    input logic dk0_written,
    input logic dk1_written,
    input logic bk_written
  );
    return {4'h0, 1'b0, bk_written, dk1_written, dk0_written};
  endfunction

  function automatic logic [7:0] keyex_status_lks_byte(
    input keyex_slot_state_e slot0_rx,
    input keyex_slot_state_e slot0_tx,
    input keyex_slot_state_e slot1_rx,
    input keyex_slot_state_e slot1_tx
  );
    return {slot0_rx, slot0_tx, slot1_rx, slot1_tx};
  endfunction

  function automatic logic [255:0] keyex_expand_key128(input logic [127:0] key128);
    return {key128, key128};
  endfunction

  function automatic oam_cad_bytes_t keyex_crypt_bytes(
    input logic [255:0] key_material,
    input int unsigned key_len_bytes,
    input logic [95:0] iv,
    input oam_cad_bytes_t data,
    input int unsigned data_len
  );
    oam_cad_bytes_t out;
    logic [7:0] ks;
    out = data;
    for (int i = 0; i < data_len; i++) begin
      ks = key_material[(i % key_len_bytes)*8 +: 8] ^
           iv[(i % KEYEX_IV_BYTES)*8 +: 8] ^
           logic'(8'(i));
      out[i*8 +: 8] = data[i*8 +: 8] ^ ks;
    end
    return out;
  endfunction

  function automatic logic [127:0] keyex_compute_icv(
    input logic [255:0] key_material,
    input int unsigned key_len_bytes,
    input logic [95:0] iv,
    input logic [7:0] primitive_id,
    input oam_cad_bytes_t aad,
    input int unsigned aad_len,
    input oam_cad_bytes_t data,
    input int unsigned data_len
  );
    logic [127:0] acc;
    acc = {iv, 24'hA55A3C, primitive_id};
    for (int i = 0; i < key_len_bytes; i++) begin
      acc[(i % 16)*8 +: 8] = acc[(i % 16)*8 +: 8] ^
                             key_material[i*8 +: 8] ^ logic'(8'((i*13)+7));
    end
    for (int i = 0; i < aad_len; i++) begin
      acc[(i % 16)*8 +: 8] = acc[(i % 16)*8 +: 8] +
                             aad[i*8 +: 8] + logic'(8'(i));
      acc[((i+5) % 16)*8 +: 8] = acc[((i+5) % 16)*8 +: 8] ^
                                  {3'b0, primitive_id[4:0]};
    end
    for (int i = 0; i < data_len; i++) begin
      acc[((i+9) % 16)*8 +: 8] = acc[((i+9) % 16)*8 +: 8] ^
                                  data[i*8 +: 8] ^ logic'(8'((i*5)+3));
    end
    return acc;
  endfunction

endpackage

`default_nettype wire
