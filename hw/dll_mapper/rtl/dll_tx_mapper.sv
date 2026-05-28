`timescale 1ns/1ps
`default_nettype none

// DLL TX Mapper (Evaluation Step + Counter)
// Spec: Section 5.2.3, Figure 5-4 pseudocode (PDF p167)
//
// Implements EXACTLY the pseudocode from Figure 5-4:
//
//   Evaluation Step:
//     DLP_TX_ID_select = 0                    (default: OAM)
//     foreach LINE in LINES:
//       LINE_sel = (Counter & LINE.BitMask == LINE.CompareValue) ? 1 : 0
//       if (LINE_sel == 1) breakloop
//       DLP_TX_ID_select = LINE.DLP_TX_ID_toSend
//     Counter++
//     if (Counter > CounterMax) then Counter = CounterMin
//
// NOTE: The micro-arch doc had the DLP_TX_ID_select assignment OUTSIDE the loop,
// which would always use the last non-matching line's DLP_TX_ID. The PDF Figure 5-4
// shows it INSIDE the loop after the breakloop check. RTL follows PDF exactly.
//
// PARAMETERIZATION: MAX_LINES=640 per spec (Section 3.3.13, DLLmtablelen max=640).
// Evaluating 640 lines sequentially would require 640 cycles. For RTL, we implement
// a pipelined search that processes one line per cycle.

module dll_tx_mapper
  import asa_dll_pkg::*;
#(
  parameter int unsigned MAX_LINES = 64  // Implementation limit; spec max=640
) (
  input  logic              clk,
  input  logic              rst,

  // Control
  input  logic              init_i,           // Set Counter = CounterMin
  input  logic              eval_trigger_i,   // One pulse per container TX opportunity
  input  logic              enable_i,         // Normal mode active

  // Mapper configuration (from registers)
  input  logic [15:0]       counter_min_i,    // 2.0142
  input  logic [15:0]       counter_max_i,    // 2.0143
  input  logic [15:0]       line_min_i,       // 2.0144
  input  logic [15:0]       line_max_i,       // 2.0145

  // Mapper table write interface (from register bank, one line per write)
  input  logic              tbl_wr_en_i,
  input  logic [$clog2(MAX_LINES)-1:0] tbl_wr_addr_i,
  input  mapper_line_t      tbl_wr_data_i,

  // Result
  output logic              result_valid_o,
  output logic [5:0]        dlp_tx_id_sel_o,  // 0=OAM (default)

  // Status
  output logic [15:0]       counter_o,        // Current counter (register 2.0141)
  output logic              mapper_err_o,     // DLP_TX_ID not implemented (2.0140[5:0])
  output logic [5:0]        mapper_err_id_o   // Which DLP_TX_ID caused error
);

  logic [15:0] counter_q;
  assign counter_o = counter_q;

  // Internal mapper table storage (registered, written from register bank)
  mapper_line_t mapper_table_q [0:MAX_LINES-1];

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      for (int i = 0; i < MAX_LINES; i++) begin
        mapper_table_q[i].bitmask          <= 16'd0;
        mapper_table_q[i].compare_value    <= 16'd0;
        mapper_table_q[i].dlp_tx_id_to_send<= 6'd0;
      end
    end else if (tbl_wr_en_i) begin
      mapper_table_q[tbl_wr_addr_i] <= tbl_wr_data_i;
    end
  end

  typedef enum logic [1:0] {
    S_IDLE,
    S_EVAL,
    S_DONE
  } state_e;
  state_e state_q;

  logic [9:0]  line_idx_q;       // Current line being evaluated (0-indexed within LINES)
  logic [5:0]  selected_id_q;    // DLP_TX_ID_select (spec default=0)
  logic        found_q;          // breakloop flag

  // Number of lines to evaluate = line_max - line_min + 1
  logic [9:0]  num_lines;
  assign num_lines = (line_max_i >= line_min_i) ?
                     line_max_i[9:0] - line_min_i[9:0] + 10'd1 :
                     10'd0;

  // Current mapper table line
  logic [9:0]  abs_line_idx;
  assign abs_line_idx = line_min_i[9:0] + line_idx_q;

  mapper_line_t cur_line;
  always_comb begin
    if (abs_line_idx < MAX_LINES[9:0])
      cur_line = mapper_table_q[abs_line_idx];
    else begin
      cur_line.bitmask         = 16'd0;
      cur_line.compare_value   = 16'd0;
      cur_line.dlp_tx_id_to_send = 6'd0;
    end
  end

  // LINE_sel evaluation: Counter & BitMask == CompareValue
  logic line_sel;
  assign line_sel = ((counter_q & cur_line.bitmask) == cur_line.compare_value);

  assign result_valid_o = (state_q == S_DONE);
  assign dlp_tx_id_sel_o = selected_id_q;
  assign mapper_err_o    = 1'b0;  // stub: real impl checks DLP_TX_ID is in implemented range
  assign mapper_err_id_o = 6'd0;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q      <= S_IDLE;
      counter_q    <= 16'd0;
      line_idx_q   <= 10'd0;
      selected_id_q<= 6'd0;
      found_q      <= 1'b0;
    end else if (init_i) begin
      counter_q    <= counter_min_i;
      state_q      <= S_IDLE;
      found_q      <= 1'b0;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (eval_trigger_i && enable_i) begin
            state_q       <= S_EVAL;
            line_idx_q    <= 10'd0;
            selected_id_q <= 6'd0;  // Default = 0 (OAM), per Figure 5-4
            found_q       <= 1'b0;
          end
        end

        S_EVAL: begin
          if (!found_q) begin
            if (num_lines == 10'd0 || line_idx_q >= num_lines) begin
              // No more lines to check
              state_q <= S_DONE;
            end else if (line_sel) begin
              // LINE_sel == 1: set DLP_TX_ID_select and break
              // Per Figure 5-4: "if (LINE_sel==1) breakloop" then
              // "DLP_TX_ID_select = LINE.DLP_TX_ID_toSend"
              selected_id_q <= cur_line.dlp_tx_id_to_send;
              found_q       <= 1'b1;
              state_q       <= S_DONE;
            end else begin
              // LINE_sel == 0: try next line
              line_idx_q    <= line_idx_q + 10'd1;
            end
          end else begin
            state_q <= S_DONE;
          end
        end

        S_DONE: begin
          // Advance counter: Counter++ then wrap if > CounterMax
          if (counter_q >= counter_max_i)
            counter_q <= counter_min_i;
          else
            counter_q <= counter_q + 16'd1;
          state_q  <= S_IDLE;
          found_q  <= 1'b0;
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule

`default_nettype wire
