`default_nettype none

// OAM RX FSM (Non-root)
// Orchestrates header check -> CAD parse -> dispatch.
// Spec: Section 5.5.2

module oam_rx_fsm
  import asa_oam_pkg::*;
  import asa_error_pkg::*;
(
  input  logic          clk,
  input  logic          rst,
  input  logic          soft_reset_i,

  // DLP_RX interface (packed: byte N = bits[N*8+7:N*8])
  input  logic          rx_valid_i,
  input  oam_frame_t    rx_frame_i,

  // Header check interface
  output logic          hdr_check_valid_o,
  input  logic          hdr_valid_i,
  input  oam_error_code_e hdr_error_i,
  input  logic          cad_next_i,

  // CAD parser interface
  output logic          parser_start_o,
  output oam_payload_t  parser_payload_o,  // 164-byte payload packed
  input  logic          parser_done_i,
  input  logic          parser_busy_i,

  // Status
  output logic          frame_accepted_o,  // Frame was valid and processed
  output logic          frame_rejected_o,  // Frame had error
  output logic          busy_o
);

  typedef enum logic [2:0] {
    S_IDLE,
    S_CHECK,
    S_START_PARSE,
    S_PARSE,
    S_DONE
  } state_e;

  state_e state_q, state_d;

  assign busy_o = (state_q != S_IDLE);

  // Pass payload region to parser: bytes 24-187 = bits[1503:192]
  assign parser_payload_o = rx_frame_i[1503:192];

  always_comb begin
    state_d           = state_q;
    hdr_check_valid_o = 1'b0;
    parser_start_o    = 1'b0;
    frame_accepted_o  = 1'b0;
    frame_rejected_o  = 1'b0;

    case (state_q)
      S_IDLE: begin
        if (rx_valid_i) begin
          state_d = S_CHECK;
        end
      end

      S_CHECK: begin
        // Header check is registered (1-cycle latency). Keep hdr_check_valid
        // asserted and wait for response.
        hdr_check_valid_o = 1'b1;
        if (hdr_valid_i) begin
          if (cad_next_i) begin
            state_d = S_START_PARSE;
          end else begin
            frame_accepted_o = 1'b1;
            state_d = S_DONE;
          end
        end else if (hdr_error_i != OAM_HDRFLD_NONE) begin
          frame_rejected_o = 1'b1;
          state_d = S_DONE;
        end
        // else: stay in S_CHECK waiting for header check result
      end

      S_START_PARSE: begin
        parser_start_o = 1'b1;
        state_d = S_PARSE;
      end

      S_PARSE: begin
        if (parser_done_i) begin
          frame_accepted_o = 1'b1;
          state_d = S_DONE;
        end
      end

      S_DONE: begin
        state_d = S_IDLE;
      end

      default: state_d = S_IDLE;
    endcase
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q <= S_IDLE;
    end else if (soft_reset_i) begin
      state_q <= S_IDLE;
    end else begin
      state_q <= state_d;
    end
  end

endmodule

`default_nettype wire
