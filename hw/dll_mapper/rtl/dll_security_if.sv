`timescale 1ns/1ps
`default_nettype none

// DLL Security Interface
// Spec: Sections 5.2.1e, 5.3.1a, 6.3.2 (SecCoP/SIF interfaces from Figure 5-1)
//
// The DLL hands containers to the security entity via SecCoP/SIF.
// This module is the DLL-side boundary: it passes the container payload to/from
// the security entity and waits for the response.
//
// TX: DLL calls LLS.process_transmit_container (6.3.2.1)
//   - Security entity returns via 6.3.2.2 (success) or 6.3.2.5 (error → all zeros)
//
// RX: DLL calls LLS.process_receive_container (6.3.2.3)
//   - Security entity returns via 6.3.2.4 (success) or 6.3.2.5 (error → discard)
//
// This module provides stub interfaces. Full AES-GCM is in the security module.

module dll_security_if (
  input  logic        clk,
  input  logic        rst,

  // TX path: request security processing
  input  logic        tx_req_valid_i,     // Container ready for security processing
  input  logic        tx_req_key_switch_i,// 1=use security
  output logic        tx_req_ready_o,     // Security entity can accept

  // TX path: response from security
  output logic        tx_resp_valid_o,    // Security-processed container ready
  output logic        tx_resp_error_o,    // Error: send all-zeros container
  input  logic        tx_resp_read_i,     // DLL consumed the response

  // RX path: request security processing
  input  logic        rx_req_valid_i,
  output logic        rx_req_ready_o,

  // RX path: response from security
  output logic        rx_resp_valid_o,    // Decrypted container ready
  output logic        rx_resp_discard_o,  // Error: discard container
  input  logic        rx_resp_read_i
);

  // IMPLEMENTATION STUB: When security entity is not implemented, pass-through.
  // TX: if no security (key_switch=0), immediately pass through with no error.
  // RX: same.

  assign tx_req_ready_o   = 1'b1;
  assign rx_req_ready_o   = 1'b1;

  // Pass-through: one cycle latency
  logic tx_pend_q, rx_pend_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      tx_pend_q <= 1'b0;
      rx_pend_q <= 1'b0;
    end else begin
      if (tx_req_valid_i && !tx_pend_q) tx_pend_q <= 1'b1;
      else if (tx_resp_read_i) tx_pend_q <= 1'b0;

      if (rx_req_valid_i && !rx_pend_q) rx_pend_q <= 1'b1;
      else if (rx_resp_read_i) rx_pend_q <= 1'b0;
    end
  end

  assign tx_resp_valid_o   = tx_pend_q;
  assign tx_resp_error_o   = 1'b0;  // stub: never errors
  assign rx_resp_valid_o   = rx_pend_q;
  assign rx_resp_discard_o = 1'b0;  // stub: never discards

endmodule

`default_nettype wire
