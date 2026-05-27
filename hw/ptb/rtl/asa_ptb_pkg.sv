`default_nettype none

// ASA Precision Time Base package
// Spec: ASA v2.0 Sections 3.3.19-3.3.22, 4.2.2.3.5, 4.2.8.

package asa_ptb_pkg;

  localparam int unsigned PTB_ACQ_WINDOW      = 16;
  localparam int unsigned PTB_LOCK_THRESH     = 14;
  localparam int signed   PTB_LOCK_TOL        = 2;
  localparam int unsigned PTB_TDD_CYCLE_TICS  = 6844;

  typedef enum logic [0:0] {
    PTB_CMD_FOLLOW      = 1'b0,
    PTB_CMD_DELAY_REPLY = 1'b1
  } ptb_cmd_e;

  typedef enum logic [1:0] {
    PTB_STATE_UNLOCKED    = 2'd0,
    PTB_STATE_ACQUISITION = 2'd1,
    PTB_STATE_LOCKED      = 2'd2
  } ptb_lock_state_e;

  typedef struct packed {
    logic signed [15:0] offset;
    logic [7:0]         delay;
    logic               in_sync;
    logic               invalid;
  } ptb_calc_result_t;

  function automatic logic [4:0] sat_inc_acq(input logic [4:0] value);
    return (value >= PTB_ACQ_WINDOW[4:0]) ? PTB_ACQ_WINDOW[4:0] : value + 5'd1;
  endfunction

  function automatic logic [7:0] sat_u8_from_s16(input logic signed [15:0] value);
    if (value <= 16'sd0) return 8'd0;
    if (value > 16'sd255) return 8'hFF;
    return value[7:0];
  endfunction

  function automatic logic [3:0] offset_to_signmag(input logic signed [15:0] offset,
                                                   input logic invalid);
    logic signed [15:0] clipped;
    logic signed [15:0] abs_value;
    logic [2:0]         magnitude;
    if (invalid) begin
      return 4'h8;
    end
    if (offset > 16'sd7) begin
      clipped = 16'sd7;
    end else if (offset < -16'sd7) begin
      clipped = -16'sd7;
    end else begin
      clipped = offset;
    end

    if (clipped < 16'sd0) begin
      abs_value = -clipped;
      magnitude = abs_value[2:0];
      return {1'b1, magnitude};
    end
    magnitude = clipped[2:0];
    return {1'b0, magnitude};
  endfunction

  function automatic logic [15:0] pack_ptb_status(input logic signed [15:0] offset,
                                                  input logic               offset_invalid,
                                                  input logic               locked,
                                                  input logic [7:0]         delay);
    return {3'b000, offset_to_signmag(offset, offset_invalid), locked, delay};
  endfunction

  // Signed modular 14-bit difference, expanded to a signed 16-bit value.
  function automatic logic signed [15:0] delta14(input logic [13:0] a,
                                                 input logic [13:0] b);
    logic signed [15:0] raw;
    raw = $signed({2'b00, a}) - $signed({2'b00, b});
    if (raw > 16'sd8191) begin
      return raw - 16'sd16384;
    end
    if (raw < -16'sd8192) begin
      return raw + 16'sd16384;
    end
    return raw;
  endfunction

  function automatic logic signed [15:0] abs_s16(input logic signed [15:0] value);
    return (value < 16'sd0) ? -value : value;
  endfunction

endpackage

`default_nettype wire
