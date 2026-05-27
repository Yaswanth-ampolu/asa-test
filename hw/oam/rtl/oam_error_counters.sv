`default_nettype none

// OAM Error Counters
// 4x 8-bit saturating SC counters for OAMerrors1/2.
// Spec: OAMerrors1 (2.2208) bits15:8=decode_err, bits7:0=dupl_id.
//        OAMerrors2 (2.2209) bits15:8=miss_id, bits7:0=payload_err.
// All SC (self-clearing on read), saturate at 0xFF.

module oam_error_counters
  import asa_oam_pkg::*;
  import asa_reg_pkg::*;
(
  input  logic          clk,
  input  logic          rst,
  input  logic          soft_reset_i,

  // Increment requests
  input  logic          inc_decode_err_i,
  input  logic          inc_dupl_id_i,
  input  logic          inc_miss_id_i,
  input  logic          inc_payload_err_i,

  // Register read interface (SC behavior)
  input  logic          read_errors1_i,   // Read of OAMerrors1 register
  input  logic          read_errors2_i,   // Read of OAMerrors2 register

  // Register values
  output logic [15:0]   oam_errors1_o,    // {decode_err[7:0], dupl_id[7:0]}
  output logic [15:0]   oam_errors2_o     // {miss_id[7:0], payload_err[7:0]}
);

  logic [7:0] decode_err_q;
  logic [7:0] dupl_id_q;
  logic [7:0] miss_id_q;
  logic [7:0] payload_err_q;

  assign oam_errors1_o = {decode_err_q, dupl_id_q};
  assign oam_errors2_o = {miss_id_q, payload_err_q};

  // Saturating increment helper
  function automatic logic [7:0] sat_inc8(logic [7:0] val);
    if (val == 8'hFF) return 8'hFF;
    else              return val + 8'd1;
  endfunction

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      decode_err_q  <= 8'd0;
      dupl_id_q     <= 8'd0;
      miss_id_q     <= 8'd0;
      payload_err_q <= 8'd0;
    end else if (soft_reset_i) begin
      decode_err_q  <= 8'd0;
      dupl_id_q     <= 8'd0;
      miss_id_q     <= 8'd0;
      payload_err_q <= 8'd0;
    end else begin
      // SC: clear on read, but increment takes priority if simultaneous
      if (read_errors1_i) begin
        decode_err_q <= inc_decode_err_i ? 8'd1 : 8'd0;
        dupl_id_q    <= inc_dupl_id_i    ? 8'd1 : 8'd0;
      end else begin
        if (inc_decode_err_i) decode_err_q <= sat_inc8(decode_err_q);
        if (inc_dupl_id_i)    dupl_id_q    <= sat_inc8(dupl_id_q);
      end

      if (read_errors2_i) begin
        miss_id_q     <= inc_miss_id_i      ? 8'd1 : 8'd0;
        payload_err_q <= inc_payload_err_i  ? 8'd1 : 8'd0;
      end else begin
        if (inc_miss_id_i)      miss_id_q     <= sat_inc8(miss_id_q);
        if (inc_payload_err_i)  payload_err_q <= sat_inc8(payload_err_q);
      end
    end
  end

endmodule

`default_nettype wire
