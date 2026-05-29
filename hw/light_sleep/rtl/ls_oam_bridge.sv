`timescale 1ns/1ps
`default_nettype none

// Light Sleep OAM Bridge
// Spec: Section 5.8.3.5/5.8.3.6 (Functions and Events)
// Routes OAM LS CAD events from OAM module → LS FSM
// Routes LS FSM send commands → OAM module
//
// The OAM module (oam_top/oam_ls_bridge) already decodes LSannounce/confirm/
// deny/sleep CADs. This module is the interface between those signals and the
// LS control FSM. It does NOT parse OAM CADs itself.

module ls_oam_bridge
  import asa_ls_pkg::*;
(
  input  logic        clk,
  input  logic        rst,

  // === FROM OAM module (decoded LS CADs) ===
  // LSannounce received (OAM CAD 5.5.3.10)
  input  logic              oam_announce_valid_i,
  input  logic [47:0]       oam_announce_bedtime_i,
  input  logic [11:0]       oam_announce_sleep_cycles_i,
  input  logic [7:0]        oam_announce_r1g_i,
  input  logic [7:0]        oam_announce_rsgx_i,

  // LSconfirm received (OAM CAD 5.5.3.11)
  input  logic              oam_confirm_valid_i,
  input  logic [7:0]        oam_confirm_r1g_a_i,
  input  logic [7:0]        oam_confirm_rsgx_a_i,

  // LSdeny received (OAM CAD 5.5.3.12)
  input  logic              oam_deny_valid_i,

  // LSsleep received (OAM CAD 5.5.3.13)
  input  logic              oam_sleep_valid_i,
  input  logic [47:0]       oam_sleep_alarmclock_i,
  input  logic [7:0]        oam_sleep_r1g_f_i,
  input  logic [7:0]        oam_sleep_rsgx_f_i,

  // === TO LS FSM ===
  output logic              ls_announce_valid_o,
  output logic [47:0]       ls_announce_bedtime_o,
  output logic [11:0]       ls_announce_sleep_cycles_o,
  output logic [7:0]        ls_announce_r1g_o,
  output logic [7:0]        ls_announce_rsgx_o,

  output logic              ls_confirm_valid_o,
  output logic [7:0]        ls_confirm_r1g_a_o,
  output logic [7:0]        ls_confirm_rsgx_a_o,

  output logic              ls_deny_valid_o,

  output logic              ls_sleep_valid_o,
  output logic [47:0]       ls_sleep_alarmclock_o,
  output logic [7:0]        ls_sleep_r1g_f_o,
  output logic [7:0]        ls_sleep_rsgx_f_o,

  // === FROM LS FSM — commands to OAM ===
  input  logic              ls_send_announce_i,
  input  logic [47:0]       ls_send_announce_bedtime_i,
  input  logic [11:0]       ls_send_announce_sleep_cycles_i,
  input  logic [7:0]        ls_send_announce_r1g_i,
  input  logic [7:0]        ls_send_announce_rsgx_i,

  input  logic              ls_send_confirm_i,
  input  logic [7:0]        ls_send_confirm_r1g_a_i,
  input  logic [7:0]        ls_send_confirm_rsgx_a_i,

  input  logic              ls_send_deny_i,

  input  logic              ls_send_sleep_i,
  input  logic [47:0]       ls_send_sleep_alarmclock_i,
  input  logic [7:0]        ls_send_sleep_r1g_f_i,
  input  logic [7:0]        ls_send_sleep_rsgx_f_i,

  // === TO OAM module — commands to send ===
  output logic              oam_send_announce_o,
  output logic [47:0]       oam_send_announce_bedtime_o,
  output logic [11:0]       oam_send_announce_sleep_cycles_o,
  output logic [7:0]        oam_send_announce_r1g_o,
  output logic [7:0]        oam_send_announce_rsgx_o,

  output logic              oam_send_confirm_o,
  output logic [7:0]        oam_send_confirm_r1g_a_o,
  output logic [7:0]        oam_send_confirm_rsgx_a_o,

  output logic              oam_send_deny_o,

  output logic              oam_send_sleep_o,
  output logic [47:0]       oam_send_sleep_alarmclock_o,
  output logic [7:0]        oam_send_sleep_r1g_f_o,
  output logic [7:0]        oam_send_sleep_rsgx_f_o
);

  // Direct pass-through with registered single-cycle pulses
  // Incoming OAM events → LS FSM
  assign ls_announce_valid_o         = oam_announce_valid_i;
  assign ls_announce_bedtime_o       = oam_announce_bedtime_i;
  assign ls_announce_sleep_cycles_o  = oam_announce_sleep_cycles_i;
  assign ls_announce_r1g_o           = oam_announce_r1g_i;
  assign ls_announce_rsgx_o          = oam_announce_rsgx_i;

  assign ls_confirm_valid_o   = oam_confirm_valid_i;
  assign ls_confirm_r1g_a_o   = oam_confirm_r1g_a_i;
  assign ls_confirm_rsgx_a_o  = oam_confirm_rsgx_a_i;

  assign ls_deny_valid_o      = oam_deny_valid_i;

  assign ls_sleep_valid_o         = oam_sleep_valid_i;
  assign ls_sleep_alarmclock_o    = oam_sleep_alarmclock_i;
  assign ls_sleep_r1g_f_o         = oam_sleep_r1g_f_i;
  assign ls_sleep_rsgx_f_o        = oam_sleep_rsgx_f_i;

  // LS FSM commands → OAM
  assign oam_send_announce_o                = ls_send_announce_i;
  assign oam_send_announce_bedtime_o        = ls_send_announce_bedtime_i;
  assign oam_send_announce_sleep_cycles_o   = ls_send_announce_sleep_cycles_i;
  assign oam_send_announce_r1g_o            = ls_send_announce_r1g_i;
  assign oam_send_announce_rsgx_o           = ls_send_announce_rsgx_i;

  assign oam_send_confirm_o       = ls_send_confirm_i;
  assign oam_send_confirm_r1g_a_o = ls_send_confirm_r1g_a_i;
  assign oam_send_confirm_rsgx_a_o= ls_send_confirm_rsgx_a_i;

  assign oam_send_deny_o          = ls_send_deny_i;

  assign oam_send_sleep_o             = ls_send_sleep_i;
  assign oam_send_sleep_alarmclock_o  = ls_send_sleep_alarmclock_i;
  assign oam_send_sleep_r1g_f_o       = ls_send_sleep_r1g_f_i;
  assign oam_send_sleep_rsgx_f_o      = ls_send_sleep_rsgx_f_i;

endmodule

`default_nettype wire
