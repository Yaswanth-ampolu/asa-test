`timescale 1ns/1ps
`default_nettype none

// ASA Error Aggregator
// Spec: Sections 3.2.8 (ASAnodeIRQ), 3.3.23-26 (OAM/DLL errors), 3.4.2-3 (Security)
//
// Collects error events from all subsystems and:
//   1. Sets the appropriate IRQ flag bits in register 1.0008
//   2. Issues saturating counter increment requests to register banks
//   3. Provides a status snapshot for diagnostic readback
//
// Parameterized by number of error input ports for scalability.

module asa_error_aggregator
  import asa_error_pkg::*;
#(
  parameter int unsigned NUM_ERR_PORTS = 8
) (
  input  logic                          clk,
  input  logic                          rst,
  input  logic                          soft_reset,

  // Error event inputs (one per subsystem)
  input  err_event_t [NUM_ERR_PORTS-1:0] err_events_i,

  // IRQ flag output (directly drives register 1.0008 set bits)
  output logic [13:0]                   irq_set_o,

  // Counter increment requests (one per cycle max, priority-encoded)
  output cnt_inc_req_t                  cnt_inc_o,

  // Status snapshot (always valid)
  input  logic [3:0]                    node_state_i,
  input  logic                          com_ready_i,
  input  logic                          ptb_locked_i,
  input  logic [1:0]                    sec_policy_i,
  input  logic [5:0]                    link_losses_i,
  input  logic [4:0]                    node_id_i,
  output status_snapshot_t              status_o
);

  // =========================================================================
  // IRQ flag accumulation (sticky until cleared by SC read)
  // =========================================================================
  logic [13:0] irq_flags_q;
  logic [13:0] irq_flags_next;

  always_comb begin
    irq_flags_next = irq_flags_q;

    if (soft_reset) begin
      irq_flags_next = '0;
    end else begin
      for (int i = 0; i < NUM_ERR_PORTS; i++) begin
        if (err_events_i[i].valid) begin
          irq_flags_next[irq_bit_for_source(err_events_i[i].source)] = 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      irq_flags_q <= '0;
    end else begin
      irq_flags_q <= irq_flags_next;
    end
  end

  assign irq_set_o = irq_flags_q;

  // =========================================================================
  // Counter increment priority encoder
  // Processes one increment per cycle; events are latched until serviced
  // =========================================================================
  // Map error source+code to a counter increment request
  function automatic cnt_inc_req_t map_error_to_counter(err_event_t ev);
    cnt_inc_req_t req;
    req.valid = 1'b0;
    req.reg_addr = '0;
    req.field_msb = '0;
    req.field_lsb = '0;
    req.width = CNT_WIDTH_8;

    if (!ev.valid) return req;

    case (ev.source)
      ERR_SRC_OAM: begin
        req.valid = 1'b1;
        case (ev.code)
          OAM_ERR_HDR_DECODE: begin
            req.reg_addr  = 15'd2208; // OAMerrors1
            req.field_msb = 4'd15;
            req.field_lsb = 4'd8;
            req.width     = CNT_WIDTH_8;
          end
          OAM_ERR_DUPL_FRAME_ID: begin
            req.reg_addr  = 15'd2208; // OAMerrors1
            req.field_msb = 4'd7;
            req.field_lsb = 4'd0;
            req.width     = CNT_WIDTH_8;
          end
          default: req.valid = 1'b0;
        endcase
      end

      ERR_SRC_DLL_RX: begin
        req.valid = 1'b1;
        case (ev.code)
          DLL_RX_ERR_CRC: begin
            req.reg_addr  = 15'd2210; // DLLerrors1
            req.field_msb = 4'd15;
            req.field_lsb = 4'd8;
            req.width     = CNT_WIDTH_8;
          end
          DLL_RX_ERR_PKT_ID: begin
            req.reg_addr  = 15'd2211; // DLLerrors2
            req.field_msb = 4'd15;
            req.field_lsb = 4'd8;
            req.width     = CNT_WIDTH_8;
          end
          default: req.valid = 1'b0;
        endcase
      end

      ERR_SRC_SECURITY: begin
        req.valid = 1'b1;
        case (ev.code)
          SEC_ERR_DROP_RX: begin
            req.reg_addr  = 15'd2;    // 3.0002
            req.field_msb = 4'd15;
            req.field_lsb = 4'd0;
            req.width     = CNT_WIDTH_16;
          end
          SEC_ERR_DROP_TX: begin
            req.reg_addr  = 15'd3;    // 3.0003
            req.field_msb = 4'd15;
            req.field_lsb = 4'd0;
            req.width     = CNT_WIDTH_16;
          end
          default: req.valid = 1'b0;
        endcase
      end

      ERR_SRC_LOCAL_PHY: begin
        req.valid = 1'b1;
        case (ev.code)
          PHY_ERR_FEC_UNCORR: begin
            req.reg_addr  = 15'd101;  // LinkQuality (1.0101)
            req.field_msb = 4'd9;
            req.field_lsb = 4'd0;
            req.width     = CNT_WIDTH_10;
          end
          default: req.valid = 1'b0;
        endcase
      end

      default: req.valid = 1'b0;
    endcase

    return req;
  endfunction

  // Priority-encode: first valid event wins this cycle
  always_comb begin
    cnt_inc_o.valid     = 1'b0;
    cnt_inc_o.reg_addr  = 15'd0;
    cnt_inc_o.field_msb = 4'd0;
    cnt_inc_o.field_lsb = 4'd0;
    cnt_inc_o.width     = CNT_WIDTH_8;
    for (int i = 0; i < NUM_ERR_PORTS; i++) begin
      if (err_events_i[i].valid && cnt_inc_o.valid == 1'b0) begin
        cnt_inc_o = map_error_to_counter(err_events_i[i]);
      end
    end
  end

  // =========================================================================
  // Status snapshot
  // =========================================================================
  assign status_o.node_state  = node_state_i;
  assign status_o.com_ready   = com_ready_i;
  assign status_o.ptb_locked  = ptb_locked_i;
  assign status_o.sec_policy  = sec_policy_i;
  assign status_o.link_losses = link_losses_i;
  assign status_o.node_id     = node_id_i;

endmodule

`default_nettype wire
