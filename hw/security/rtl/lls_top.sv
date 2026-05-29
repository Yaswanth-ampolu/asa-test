`timescale 1ns/1ps
`default_nettype none

// LLS Top-Level (Link Layer Security)
// Spec: Section 6.3, PDF pp196-203

module lls_top
  import asa_lls_pkg::*;
(
  input  logic              clk,
  input  logic              rst,
  input  logic              soft_reset_i,

  input  lls_policy_e       policy_i,
  input  logic              is_downstream_i,

  input  logic              install_key_valid_i,
  input  logic              install_slot_i,
  input  logic [127:0]      install_key_i,
  input  logic [29:0]       install_salt_i,

  // TX interface
  input  logic              tx_req_valid_i,
  input  logic [47:0]       tx_hdr_i,
  input  logic [7:0]        tx_dll_payload_i [0:637],
  input  logic [9:0]        tx_payload_len_i,
  input  logic              tx_is_keyex_oam_i,
  input  logic              tx_is_node_discover_i,
  input  logic              tx_is_self_announce_i,
  input  logic              tx_is_empty_oam_i,

  output logic              tx_resp_valid_o,
  output logic              tx_resp_bypass_o,
  output logic              tx_resp_error_o,
  output lls_error_e        tx_resp_error_code_o,
  output logic [47:0]       tx_resp_hdr_o,
  output logic [7:0]        tx_resp_sec_payload_o [0:655],
  output logic [9:0]        tx_resp_sec_payload_len_o,
  output logic              tx_dropped_inc_o,

  // RX interface
  input  logic              rx_req_valid_i,
  input  logic [47:0]       rx_hdr_i,
  input  logic [7:0]        rx_sec_payload_i [0:655],
  input  logic [9:0]        rx_sec_payload_len_i,
  input  logic              rx_is_keyex_oam_i,
  input  logic              rx_is_node_discover_i,
  input  logic              rx_is_self_announce_i,
  input  logic              rx_is_empty_oam_i,

  output logic              rx_resp_valid_o,
  output logic              rx_resp_bypass_o,
  output logic              rx_resp_error_o,
  output lls_error_e        rx_resp_error_code_o,
  output logic [7:0]        rx_resp_dll_payload_o [0:637],
  output logic [9:0]        rx_resp_dll_payload_len_o,
  output logic              rx_dropped_inc_o,

  output logic              keyex_report_10pct_o,
  output logic              keyex_report_5pct_o,
  output logic              keyex_overflow_o
);

  // =========================================================================
  // Shared signals
  // =========================================================================
  logic any_lk_installed;

  // TX slot
  logic        tx_slot, tx_slot_ready, tx_use;
  logic [127:0] tx_key;
  logic [29:0]  tx_salt;
  logic [63:0]  tx_ctr;

  // RX slot (keyed by header KeySwitch bit)
  logic rx_keysw;
  assign rx_keysw = rx_hdr_i[1];

  logic        rx_slot_ready, rx_other_slot_ready;
  logic [127:0] rx_key, rx_other_key;
  logic [29:0]  rx_salt, rx_other_salt;
  logic [63:0]  rx_last_ctr, rx_other_last_ctr;

  logic rx_ctr_update, rx_ctr_slot_w;
  logic [63:0]  rx_ctr_new;
  logic rx_key_switch, rx_switch_new_slot;

  // =========================================================================
  // Single Key Slot Controller
  // =========================================================================
  lls_keyslot_ctrl u_slots (
    .clk, .rst, .soft_reset_i,
    .install_key_valid_i, .install_slot_i, .install_key_i, .install_salt_i,
    .tx_use_i(tx_use),
    .tx_slot_o(tx_slot), .tx_key_o(tx_key), .tx_salt_o(tx_salt),
    .tx_ctr_o(tx_ctr), .tx_slot_ready_o(tx_slot_ready),
    .rx_slot_i(rx_keysw),
    .rx_key_o(rx_key), .rx_salt_o(rx_salt),
    .rx_last_ctr_o(rx_last_ctr), .rx_slot_ready_o(rx_slot_ready),
    .rx_other_key_o(rx_other_key), .rx_other_salt_o(rx_other_salt),
    .rx_other_last_ctr_o(rx_other_last_ctr),
    .rx_other_slot_ready_o(rx_other_slot_ready),
    .rx_ctr_update_i(rx_ctr_update), .rx_ctr_slot_i(rx_ctr_slot_w),
    .rx_ctr_new_i(rx_ctr_new),
    .rx_key_switch_trigger_i(rx_key_switch),
    .rx_switch_new_slot_i(rx_switch_new_slot),
    .keyex_report_10pct_o, .keyex_report_5pct_o, .keyex_overflow_o,
    .any_lk_installed_o(any_lk_installed)
  );

  // =========================================================================
  // Bypass classification
  // =========================================================================
  lls_bypass_reason_e tx_bypass_reason, rx_bypass_reason;

  always_comb begin
    // TX bypass
    if      (tx_is_keyex_oam_i)     tx_bypass_reason = BYPASS_KEYEX_OAM;
    else if (tx_is_node_discover_i) tx_bypass_reason = BYPASS_NODE_DISCOVER;
    else if (tx_is_self_announce_i) tx_bypass_reason = BYPASS_SELF_ANNOUNCE;
    else if (tx_is_empty_oam_i && !any_lk_installed) tx_bypass_reason = BYPASS_EMPTY_OAM_PRELK;
    else if (policy_i == SEC_POLICY_NONE) tx_bypass_reason = BYPASS_NO_POLICY;
    else    tx_bypass_reason = BYPASS_NONE;

    // RX bypass
    if      (rx_is_keyex_oam_i)     rx_bypass_reason = BYPASS_KEYEX_OAM;
    else if (rx_is_node_discover_i) rx_bypass_reason = BYPASS_NODE_DISCOVER;
    else if (rx_is_self_announce_i) rx_bypass_reason = BYPASS_SELF_ANNOUNCE;
    else if (rx_is_empty_oam_i && !any_lk_installed) rx_bypass_reason = BYPASS_EMPTY_OAM_PRELK;
    else if (policy_i == SEC_POLICY_NONE) rx_bypass_reason = BYPASS_NO_POLICY;
    else    rx_bypass_reason = BYPASS_NONE;
  end

  // =========================================================================
  // TX Protection
  // =========================================================================
  lls_tx_protect u_tx (
    .clk, .rst,
    .policy_i, .is_downstream_i,
    .req_valid_i(tx_req_valid_i), .hdr_i(tx_hdr_i),
    .dll_payload_i(tx_dll_payload_i), .payload_len_i(tx_payload_len_i),
    .bypass_reason_i(tx_bypass_reason), .any_lk_installed_i(any_lk_installed),
    .tx_slot_i(tx_slot), .tx_key_i(tx_key), .tx_salt_i(tx_salt),
    .tx_ctr_i(tx_ctr), .tx_slot_ready_i(tx_slot_ready),
    .tx_use_o(tx_use),
    .resp_valid_o(tx_resp_valid_o), .resp_is_bypass_o(tx_resp_bypass_o),
    .resp_error_o(tx_resp_error_o), .resp_error_code_o(tx_resp_error_code_o),
    .resp_hdr_o(tx_resp_hdr_o),
    .resp_sec_payload_o(tx_resp_sec_payload_o),
    .resp_sec_payload_len_o(tx_resp_sec_payload_len_o),
    .dropped_tx_inc_o(tx_dropped_inc_o)
  );

  // =========================================================================
  // RX Verification
  // =========================================================================
  lls_rx_verify u_rx (
    .clk, .rst,
    .policy_i, .is_downstream_i,
    .req_valid_i(rx_req_valid_i), .hdr_i(rx_hdr_i),
    .sec_payload_i(rx_sec_payload_i), .sec_payload_len_i(rx_sec_payload_len_i),
    .bypass_reason_i(rx_bypass_reason), .any_lk_installed_i(any_lk_installed),
    .keysw_i(rx_keysw),
    .rx_key_i(rx_key), .rx_salt_i(rx_salt),
    .rx_last_ctr_i(rx_last_ctr), .rx_slot_ready_i(rx_slot_ready),
    .rx_other_key_i(rx_other_key), .rx_other_salt_i(rx_other_salt),
    .rx_other_last_ctr_i(rx_other_last_ctr),
    .rx_other_slot_ready_i(rx_other_slot_ready),
    .rx_ctr_update_o(rx_ctr_update), .rx_ctr_slot_o(rx_ctr_slot_w),
    .rx_ctr_new_o(rx_ctr_new),
    .rx_key_switch_o(rx_key_switch), .rx_switch_new_slot_o(rx_switch_new_slot),
    .resp_valid_o(rx_resp_valid_o), .resp_is_bypass_o(rx_resp_bypass_o),
    .resp_error_o(rx_resp_error_o), .resp_error_code_o(rx_resp_error_code_o),
    .resp_dll_payload_o(rx_resp_dll_payload_o),
    .resp_dll_payload_len_o(rx_resp_dll_payload_len_o),
    .dropped_rx_inc_o(rx_dropped_inc_o)
  );

endmodule

`default_nettype wire
