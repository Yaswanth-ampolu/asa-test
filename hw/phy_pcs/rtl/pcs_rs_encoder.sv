`timescale 1ns/1ps
`default_nettype none

// PCS Reed-Solomon FEC Encoder
// Spec: Section 4.2.4.1-4.2.4.3, Figures 4-9/4-10/4-11
//
// Supports three modes:
//   RS(108,106): k=106 message bytes → 2 parity bytes → n=108 codeword
//   RS(216,214): k=214 message bytes → 2 parity bytes → n=216 codeword
//   RS(240,214): k=214 message bytes → 26 parity bytes → n=240 codeword
//
// All operate over GF(2^8) with primitive polynomial x^8+x^4+x^3+x^2+1.
//
// Interface: byte-serial input, byte-serial output.
// Feed k message bytes (MSB byte first per spec), then read 2t parity bytes.

module pcs_rs_encoder
  import asa_pcs_pkg::*;
#(
  parameter int unsigned K_BYTES = 106,   // Message length
  parameter int unsigned T_PARITY = 2     // Parity bytes (2t)
) (
  input  logic        clk,
  input  logic        rst,

  // Control
  input  logic        init_i,          // Reset encoder state
  input  logic        msg_valid_i,     // Input message byte valid
  input  logic [7:0]  msg_byte_i,      // Message byte (MSB byte first: m_k-1, m_k-2, ..., m_0)
  output logic        msg_ready_o,     // Can accept message byte

  // Parity output
  output logic        parity_valid_o,  // Parity byte available
  output logic [7:0]  parity_byte_o,   // Parity byte (p_2t-1, p_2t-2, ..., p_0)
  input  logic        parity_read_i,   // Advance to next parity byte

  // Status
  output logic        busy_o,
  output logic        done_o           // All parity bytes read
);

  // Encoder state
  localparam int unsigned N_PARITY = T_PARITY;
  logic [7:0] parity_regs [0:N_PARITY-1];  // Shift register
  logic [$clog2(K_BYTES+1)-1:0] msg_cnt_q;
  logic [$clog2(N_PARITY+1)-1:0] par_cnt_q;

  typedef enum logic [1:0] {
    S_IDLE,
    S_MSG,
    S_PARITY,
    S_DONE
  } state_e;
  state_e state_q;

  assign busy_o      = (state_q != S_IDLE) && (state_q != S_DONE);
  assign msg_ready_o = (state_q == S_MSG);
  assign parity_valid_o = (state_q == S_PARITY);
  assign done_o      = (state_q == S_DONE);

  // Parity output: read from last register down
  assign parity_byte_o = parity_regs[N_PARITY - 1 - par_cnt_q];

  // Generator polynomial coefficients (only RS(108,106) / RS(216,214) for t=1)
  // For t=1: g(x) = x^2 + g1*x + g0 = (x - alpha^0)(x - alpha^1)
  // g0=0x02, g1=0x03, g2=0x01 (leading coeff)
  //
  // For RS(240,214) t=13: use RS240_G array from package
  //
  // The shift register computes: feedback = input XOR p[N_PARITY-1]
  //                              p[i] = p[i-1] XOR (feedback * g[i]) for i>0
  //                              p[0] = feedback * g[0]

  // Select generator coefficients based on parameter
  logic [7:0] g_coeff [0:N_PARITY-1];
  generate
    if (T_PARITY == 2) begin : gen_t1
      assign g_coeff[0] = 8'h02;  // g0
      assign g_coeff[1] = 8'h03;  // g1
    end else if (T_PARITY == 26) begin : gen_t13
      genvar gi;
      for (gi = 0; gi < 26; gi++) begin : gen_g
        assign g_coeff[gi] = RS240_G[gi];
      end
    end
  endgenerate

  // Encoder datapath
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q <= S_IDLE;
      msg_cnt_q <= '0;
      par_cnt_q <= '0;
      for (int i = 0; i < N_PARITY; i++) parity_regs[i] <= 8'd0;
    end else if (init_i) begin
      state_q <= S_MSG;
      msg_cnt_q <= '0;
      par_cnt_q <= '0;
      for (int i = 0; i < N_PARITY; i++) parity_regs[i] <= 8'd0;
    end else begin
      case (state_q)
        S_IDLE: begin
          // Wait for init
        end

        S_MSG: begin
          if (msg_valid_i) begin
            // Feedback = input XOR parity_regs[N_PARITY-1]
            automatic logic [7:0] feedback;
            feedback = msg_byte_i ^ parity_regs[N_PARITY-1];

            // Shift and multiply
            for (int i = N_PARITY-1; i > 0; i--) begin
              parity_regs[i] <= parity_regs[i-1] ^ gf_mul(feedback, g_coeff[i]);
            end
            parity_regs[0] <= gf_mul(feedback, g_coeff[0]);

            msg_cnt_q <= msg_cnt_q + 1;
            if (msg_cnt_q == K_BYTES - 1) begin
              state_q <= S_PARITY;
            end
          end
        end

        S_PARITY: begin
          if (parity_read_i) begin
            par_cnt_q <= par_cnt_q + 1;
            if (par_cnt_q == N_PARITY - 1) begin
              state_q <= S_DONE;
            end
          end
        end

        S_DONE: begin
          state_q <= S_IDLE;
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule

`default_nettype wire
