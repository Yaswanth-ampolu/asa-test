`default_nettype none

// OAM CAD Parser
// Iterates payload bytes, decodes each CAD command+fields, dispatches.
// Spec: Section 5.5.3

module oam_cad_parser
  import asa_oam_pkg::*;
(
  input  logic          clk,
  input  logic          rst,

  // Control
  input  logic          start_i,          // Begin parsing (header valid, CADnext=1)
  input  oam_payload_t  payload_i,          // 164-byte packed payload
  output logic          done_o,           // All CADs parsed
  output logic          busy_o,

  // Decoded CAD output (one per cycle during parsing)
  output oam_decoded_cad_t cad_o,
  output logic          cad_valid_o,
  output logic [7:0]    cad_offset_o,
  output logic [7:0]    cad_size_o,

  // Error output
  output logic          parse_error_o     // Invalid command encountered
);

  typedef enum logic [1:0] {
    S_IDLE,
    S_DECODE,
    S_DONE
  } state_e;

  state_e state_q, state_d;
  logic [7:0] offset_q, offset_d;

  logic [6:0] cmd_code;
  logic       cad_next_bit;
  logic [7:0] b0, b1, b2, b3, b4;

  assign busy_o = (state_q != S_IDLE);
  assign cad_offset_o = offset_q;
  assign cad_size_o   = current_cad_size;

  always_comb begin
    b0 = (offset_q < 8'd164) ? oam_pay_get_byte(payload_i, offset_q)     : 8'd0;
    b1 = (offset_q < 8'd163) ? oam_pay_get_byte(payload_i, offset_q + 1) : 8'd0;
    b2 = (offset_q < 8'd162) ? oam_pay_get_byte(payload_i, offset_q + 2) : 8'd0;
    b3 = (offset_q < 8'd161) ? oam_pay_get_byte(payload_i, offset_q + 3) : 8'd0;
    b4 = (offset_q < 8'd160) ? oam_pay_get_byte(payload_i, offset_q + 4) : 8'd0;
  end

  assign cad_next_bit = b0[7];
  assign cmd_code     = b0[6:0];

  // Compute CAD size from command code
  logic [7:0] current_cad_size;
  always_comb begin
    case (oam_cmd_code_e'(cmd_code))
      OAM_CMD_READ:            current_cad_size = 8'd4;
      OAM_CMD_RETURN:          current_cad_size = 8'd6;
      OAM_CMD_READ_ERROR:      current_cad_size = 8'd6;
      OAM_CMD_WRITE:           current_cad_size = 8'd6;
      OAM_CMD_WRITE_ACK:       current_cad_size = 8'd6;
      OAM_CMD_START_ENUM:      current_cad_size = 8'd6;
      OAM_CMD_LONG_ATOM:       current_cad_size = 8'd2;
      OAM_CMD_LONG_ATOM_CLOSE: current_cad_size = 8'd2;
      OAM_CMD_START_TDD:       current_cad_size = 8'd12;
      OAM_CMD_LS_ANNOUNCE:     current_cad_size = 8'd12;
      OAM_CMD_LS_CONFIRM:      current_cad_size = 8'd4;
      OAM_CMD_LS_DENY:         current_cad_size = 8'd2;
      OAM_CMD_LS_SLEEP:        current_cad_size = 8'd10;
      OAM_CMD_KEYEX_REQ:       current_cad_size = 8'd164 - offset_q; // fills rest
      OAM_CMD_KEYEX_RESP:      current_cad_size = 8'd164 - offset_q; // fills rest
      default:                 current_cad_size = 8'd0;
    endcase
  end

  always_comb begin
    state_d      = state_q;
    offset_d     = offset_q;
    cad_o        = '0;
    cad_valid_o  = 1'b0;
    done_o       = 1'b0;
    parse_error_o = 1'b0;

    case (state_q)
      S_IDLE: begin
        if (start_i) begin
          state_d  = S_DECODE;
          offset_d = 8'd0;
        end
      end

      S_DECODE: begin
        if (offset_q >= 8'd164 || b0 == 8'd0) begin
          // End of payload (padding)
          state_d = S_DONE;
        end else if (current_cad_size == 8'd0) begin
          // Unknown command
          parse_error_o = 1'b1;
          state_d = S_DONE;
        end else begin
          cad_valid_o     = 1'b1;
          cad_o.valid     = 1'b1;
          cad_o.cmd       = oam_cmd_code_e'(cmd_code);

          // Decode address for commands that have it (bytes 1-3 of CAD)
          cad_o.addr.domain  = b1[7:5];
          cad_o.addr.dlp_id  = {b1[4:0], b2[7]};
          cad_o.addr.addr    = {b2[6:0], b3};

          case (oam_cmd_code_e'(cmd_code))
            OAM_CMD_READ: begin
              // 4 bytes: cmd + 3 addr bytes
            end
            OAM_CMD_WRITE: begin
              // 6 bytes: cmd + 3 addr + 2 data
              cad_o.data = {b4, oam_pay_get_byte(payload_i, offset_q + 5)};
            end
            OAM_CMD_RETURN: begin
              // 6 bytes: cmd + 3 addr + 2 data
              cad_o.data = {b4, oam_pay_get_byte(payload_i, offset_q + 5)};
            end
            OAM_CMD_READ_ERROR: begin
              // 6 bytes: cmd + 3 addr + 1 errcode + 1 rsvd
              cad_o.error_code = oam_pay_get_byte(payload_i, offset_q + 5);
            end
            OAM_CMD_WRITE_ACK: begin
              // 6 bytes: cmd + 3 addr + 1 ackcode + 1 rsvd
              cad_o.error_code = oam_pay_get_byte(payload_i, offset_q + 5);
            end
            OAM_CMD_START_ENUM: begin
              // 6 bytes: cmd + 5 data bytes
              cad_o.free_node_id = b4[4:0];
            end
            OAM_CMD_LONG_ATOM: begin
              // 2 bytes: cmd + count
              cad_o.longatom_cnt = b1[4:0];
              cad_o.addr = '0;
            end
            OAM_CMD_LONG_ATOM_CLOSE: begin
              // 2 bytes
              cad_o.addr = '0;
            end
            OAM_CMD_START_TDD: begin
              // 12 bytes: cmd + 11 data bytes (params decoded externally)
              cad_o.addr = '0;
            end
            OAM_CMD_LS_ANNOUNCE,
            OAM_CMD_LS_CONFIRM,
            OAM_CMD_LS_DENY,
            OAM_CMD_LS_SLEEP: begin
              cad_o.addr = '0;
            end
            OAM_CMD_KEYEX_REQ,
            OAM_CMD_KEYEX_RESP: begin
              cad_o.addr = '0;
            end
            default: begin
              parse_error_o = 1'b1;
            end
          endcase

          // Advance offset
          offset_d = offset_q + current_cad_size;

          // If CADnext=0, this is the last CAD
          if (!cad_next_bit) begin
            state_d = S_DONE;
          end
        end
      end

      S_DONE: begin
        done_o  = 1'b1;
        state_d = S_IDLE;
      end

      default: state_d = S_IDLE;
    endcase
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q  <= S_IDLE;
      offset_q <= 8'd0;
    end else begin
      state_q  <= state_d;
      offset_q <= offset_d;
    end
  end

endmodule

`default_nettype wire
