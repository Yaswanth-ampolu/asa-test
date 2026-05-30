`timescale 1ns/1ps
`default_nettype none

module asep_common_top
  import asa_intf_pkg::*;
  import asa_asep_pkg::*;
(
  input  logic            clk,
  input  logic            rst,
  input  logic            soft_reset_i,

  input  logic            tx_build_req_i,
  input  slot_size_e      tx_slot_size_i,
  input  logic            tx_pkt0_valid_i,
  input  logic [6:0]      tx_pkt0_stream_type_i,
  input  asep_ts_mode_e   tx_pkt0_ts_mode_i,
  input  logic [31:0]     tx_pkt0_ts_value_i,
  input  asep_packet_t    tx_pkt0_body_i,
  input  logic [11:0]     tx_pkt0_body_len_i,
  input  logic [11:0]     tx_pkt0_offset_i,
  input  logic            tx_pkt1_valid_i,
  input  logic [6:0]      tx_pkt1_stream_type_i,
  input  asep_ts_mode_e   tx_pkt1_ts_mode_i,
  input  logic [31:0]     tx_pkt1_ts_value_i,
  input  asep_packet_t    tx_pkt1_body_i,
  input  logic [11:0]     tx_pkt1_body_len_i,
  input  logic [11:0]     tx_pkt1_offset_i,

  output logic            tx_ptb_capture_req_o,
  output logic            tx_data_valid_o,
  output logic            tx_yield_o,
  output asep_frag_code_e tx_frag_code_o,
  output logic [9:0]      tx_boundary_pos_o,
  output asep_container_t tx_dll_payload_o,
  output logic [10:0]     tx_dll_payload_len_o,
  output logic [11:0]     tx_used_pkt0_bytes_o,
  output logic [11:0]     tx_used_pkt1_bytes_o,
  output logic            tx_overflow_o,

  input  logic            rx_container_valid_i,
  input  logic            rx_packet_id_ok_i,
  input  asep_container_t rx_dll_payload_i,
  input  logic [10:0]     rx_dll_payload_len_i,
  output logic            rx_packet_valid_o,
  output asep_packet_t    rx_packet_o,
  output logic [11:0]     rx_packet_len_o,
  output logic [6:0]      rx_stream_type_o,
  output logic            rx_follow_flag_o,
  output asep_ts_mode_e   rx_ts_mode_o,
  output logic [31:0]     rx_ts_value_o,
  output asep_frag_code_e rx_frag_code_o,
  output logic [9:0]      rx_boundary_pos_o,
  output logic            rx_error_o,
  output logic            rx_assembling_o
);

  asep_tx_common u_tx (
    .build_req_i        (tx_build_req_i),
    .slot_size_i        (tx_slot_size_i),
    .pkt0_valid_i       (tx_pkt0_valid_i),
    .pkt0_stream_type_i (tx_pkt0_stream_type_i),
    .pkt0_ts_mode_i     (tx_pkt0_ts_mode_i),
    .pkt0_ts_value_i    (tx_pkt0_ts_value_i),
    .pkt0_body_i        (tx_pkt0_body_i),
    .pkt0_body_len_i    (tx_pkt0_body_len_i),
    .pkt0_offset_i      (tx_pkt0_offset_i),
    .pkt1_valid_i       (tx_pkt1_valid_i),
    .pkt1_stream_type_i (tx_pkt1_stream_type_i),
    .pkt1_ts_mode_i     (tx_pkt1_ts_mode_i),
    .pkt1_ts_value_i    (tx_pkt1_ts_value_i),
    .pkt1_body_i        (tx_pkt1_body_i),
    .pkt1_body_len_i    (tx_pkt1_body_len_i),
    .pkt1_offset_i      (tx_pkt1_offset_i),
    .ptb_capture_req_o  (tx_ptb_capture_req_o),
    .data_valid_o       (tx_data_valid_o),
    .yield_o            (tx_yield_o),
    .frag_code_o        (tx_frag_code_o),
    .boundary_pos_o     (tx_boundary_pos_o),
    .dll_payload_o      (tx_dll_payload_o),
    .dll_payload_len_o  (tx_dll_payload_len_o),
    .used_pkt0_bytes_o  (tx_used_pkt0_bytes_o),
    .used_pkt1_bytes_o  (tx_used_pkt1_bytes_o),
    .overflow_o         (tx_overflow_o)
  );

  asep_rx_common u_rx (
    .clk              (clk),
    .rst              (rst),
    .soft_reset_i     (soft_reset_i),
    .container_valid_i(rx_container_valid_i),
    .packet_id_ok_i   (rx_packet_id_ok_i),
    .dll_payload_i    (rx_dll_payload_i),
    .dll_payload_len_i(rx_dll_payload_len_i),
    .packet_valid_o   (rx_packet_valid_o),
    .packet_o         (rx_packet_o),
    .packet_len_o     (rx_packet_len_o),
    .stream_type_o    (rx_stream_type_o),
    .follow_flag_o    (rx_follow_flag_o),
    .ts_mode_o        (rx_ts_mode_o),
    .ts_value_o       (rx_ts_value_o),
    .frag_code_o      (rx_frag_code_o),
    .boundary_pos_o   (rx_boundary_pos_o),
    .error_o          (rx_error_o),
    .assembling_o     (rx_assembling_o)
  );

endmodule

