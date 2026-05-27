`default_nettype none

// OAM LongAtom Handler
// Buffers Write commands during LongAtom sequence, flushes on error/overflow.
// Spec: Section 5.5.3.7-8 — longAtom_LIMIT = 32 frames max.

module oam_longatom
  import asa_oam_pkg::*;
(
  input  logic          clk,
  input  logic          rst,
  input  logic          soft_reset_i,

  // CAD input
  input  oam_decoded_cad_t cad_i,
  input  logic          cad_valid_i,

  // Header error indication (forces flush)
  input  logic          header_error_i,

  // Outputs
  output logic          active_o,         // LongAtom sequence is active
  output logic          overflow_o,       // Overflow detected (>32 frames)
  output logic          flush_o,          // Flush event (error or overflow)
  output logic [5:0]    frame_count_o,    // Current frame count in sequence

  // Write pass-through control
  output logic          write_hold_o,     // Hold writes (buffering for atomic commit)
  output logic          write_release_o   // Release all buffered writes
);

  logic [5:0] frame_cnt_q;
  logic       active_q;
  logic       overflow_q;
  logic       overflow_sticky_q; // holds until sequence ends or reset

  assign active_o      = active_q;
  assign overflow_o    = overflow_sticky_q;
  assign frame_count_o = frame_cnt_q;

  // Flush on header error during active sequence or overflow
  assign flush_o = active_q && (header_error_i || overflow_q);

  // Hold writes while LongAtom is active (atomic semantics)
  assign write_hold_o    = active_q && !overflow_q;
  assign write_release_o = active_q && cad_valid_i &&
                           (cad_i.cmd == OAM_CMD_LONG_ATOM_CLOSE) && !overflow_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      frame_cnt_q      <= 6'd0;
      active_q         <= 1'b0;
      overflow_q       <= 1'b0;
      overflow_sticky_q <= 1'b0;
    end else if (soft_reset_i || flush_o) begin
      frame_cnt_q      <= 6'd0;
      active_q         <= 1'b0;
      overflow_q       <= 1'b0;
      overflow_sticky_q <= 1'b0;
    end else begin
      if (cad_valid_i) begin
        case (cad_i.cmd)
          OAM_CMD_LONG_ATOM: begin
            if (!active_q) begin
              active_q         <= 1'b1;
              frame_cnt_q      <= 6'd1;
              overflow_q       <= 1'b0;
              overflow_sticky_q <= 1'b0;
            end else begin
              frame_cnt_q <= frame_cnt_q + 6'd1;
              if ((frame_cnt_q + 6'd1) >= LONGATOM_LIMIT[5:0]) begin
                overflow_q        <= 1'b1;
                overflow_sticky_q <= 1'b1;
              end
            end
          end
          OAM_CMD_LONG_ATOM_CLOSE: begin
            active_q         <= 1'b0;
            frame_cnt_q      <= 6'd0;
            overflow_q       <= 1'b0;
            overflow_sticky_q <= 1'b0;
          end
          default: begin end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
