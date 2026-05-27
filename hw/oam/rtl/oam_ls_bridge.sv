`default_nettype none

// OAM Light Sleep Bridge
// Routes LS CADs (announce/confirm/deny/sleep) to/from LS FSM.
// Spec: Sections 5.5.3.10-13

module oam_ls_bridge
  import asa_oam_pkg::*;
(
  input  logic          clk,
  input  logic          rst,

  // CAD input (from parser)
  input  oam_decoded_cad_t cad_i,
  input  logic          cad_valid_i,

  // Payload access for LS parameter extraction (packed)
  input  oam_payload_t  payload_i,
  input  logic [7:0]    cad_offset_i,   // Byte offset of current CAD in payload

  // LS FSM interface - outputs
  output logic              ls_announce_valid_o,
  output ls_announce_params_t ls_announce_params_o,
  output logic              ls_confirm_valid_o,
  output ls_confirm_params_t ls_confirm_params_o,
  output logic              ls_deny_valid_o,
  output logic              ls_sleep_valid_o,
  output ls_sleep_params_t  ls_sleep_params_o,

  // LS FSM interface - response input
  input  logic              ls_resp_valid_i,
  input  oam_cad_resp_t     ls_resp_cad_i,

  // Response output (to FIFO)
  output oam_cad_resp_t     resp_o,
  output logic              resp_valid_o
);

  // Extract LS parameters from payload based on CAD offset
  // byte0 = command byte, bytes 1+ = parameters

  always_comb begin
    ls_announce_valid_o = 1'b0;
    ls_announce_params_o = '0;
    ls_confirm_valid_o  = 1'b0;
    ls_confirm_params_o = '0;
    ls_deny_valid_o     = 1'b0;
    ls_sleep_valid_o    = 1'b0;
    ls_sleep_params_o   = '0;

    if (cad_valid_i) begin
      case (cad_i.cmd)
        OAM_CMD_LS_ANNOUNCE: begin
          ls_announce_valid_o = 1'b1;
          ls_announce_params_o.ptb_bedtime = {
            oam_pay_get_byte(payload_i, cad_offset_i + 1),
            oam_pay_get_byte(payload_i, cad_offset_i + 2),
            oam_pay_get_byte(payload_i, cad_offset_i + 3),
            oam_pay_get_byte(payload_i, cad_offset_i + 4),
            oam_pay_get_byte(payload_i, cad_offset_i + 5),
            oam_pay_get_byte(payload_i, cad_offset_i + 6)};
          ls_announce_params_o.sleep_cycles = {
            payload_i[(cad_offset_i+7)*8+3 -: 4],
            oam_pay_get_byte(payload_i, cad_offset_i + 8)};
          ls_announce_params_o.restart_cycles_1g  = oam_pay_get_byte(payload_i, cad_offset_i + 9);
          ls_announce_params_o.restart_cycles_sgx = oam_pay_get_byte(payload_i, cad_offset_i + 10);
        end
        OAM_CMD_LS_CONFIRM: begin
          ls_confirm_valid_o = 1'b1;
          ls_confirm_params_o.restart_cycles_1g_a  = oam_pay_get_byte(payload_i, cad_offset_i + 1);
          ls_confirm_params_o.restart_cycles_sgx_a = oam_pay_get_byte(payload_i, cad_offset_i + 2);
        end
        OAM_CMD_LS_DENY: begin
          ls_deny_valid_o = 1'b1;
        end
        OAM_CMD_LS_SLEEP: begin
          ls_sleep_valid_o = 1'b1;
          ls_sleep_params_o.ptb_alarmclock = {
            oam_pay_get_byte(payload_i, cad_offset_i + 1),
            oam_pay_get_byte(payload_i, cad_offset_i + 2),
            oam_pay_get_byte(payload_i, cad_offset_i + 3),
            oam_pay_get_byte(payload_i, cad_offset_i + 4),
            oam_pay_get_byte(payload_i, cad_offset_i + 5),
            oam_pay_get_byte(payload_i, cad_offset_i + 6)};
          ls_sleep_params_o.restart_cycles_1g_f  = oam_pay_get_byte(payload_i, cad_offset_i + 7);
          ls_sleep_params_o.restart_cycles_sgx_f = oam_pay_get_byte(payload_i, cad_offset_i + 8);
        end
        default: begin end
      endcase
    end
  end

  // Pass through LS FSM response to FIFO
  assign resp_valid_o = ls_resp_valid_i;
  assign resp_o       = ls_resp_cad_i;

endmodule

`default_nettype wire
