`timescale 1ns/1ps
`default_nettype none

module mle_xmii_denormalize_rx
  import asa_mle_xmii_pkg::*;
(
  input  logic        clk,
  input  logic        rst,
  input  xmii_type_e  xmii_type_i,
  input  logic        word_valid_i,
  input  logic [63:0] word_data_i,
  input  logic [7:0]  word_ctrl_i,
  output logic        host_valid_o,
  output logic [31:0] host_data_o,
  output logic [3:0]  host_ctrl_o
);
  logic [63:0] hold_data_q;
  logic [7:0]  hold_ctrl_q;
  logic [4:0]  idx_q;
  logic        active_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      hold_data_q <= '0;
      hold_ctrl_q <= '0;
      idx_q       <= '0;
      active_q    <= 1'b0;
      host_valid_o <= 1'b0;
      host_data_o  <= '0;
      host_ctrl_o  <= '0;
    end else begin
      host_valid_o <= 1'b0;
      if (word_valid_i && !active_q) begin
        hold_data_q <= word_data_i;
        hold_ctrl_q <= word_ctrl_i;
        idx_q       <= '0;
        active_q    <= 1'b1;
      end else if (active_q) begin
        host_valid_o <= 1'b1;
        case (xmii_type_i)
          XMII_XGMII: begin
            for (int i = 0; i < 4; i++) begin
              host_data_o[8*i +: 8] <= hold_data_q[8*(idx_q+i) +: 8];
              host_ctrl_o[i] <= hold_ctrl_q[idx_q+i];
            end
            if (idx_q == 4) active_q <= 1'b0;
            idx_q <= idx_q + 4;
          end
          XMII_GMII: begin
            host_data_o[7:0] <= hold_data_q[8*idx_q +: 8];
            host_ctrl_o[0] <= hold_ctrl_q[idx_q];
            if (idx_q == 7) active_q <= 1'b0;
            idx_q <= idx_q + 1;
          end
          default: begin
            host_data_o[3:0] <= hold_data_q[4*idx_q +: 4];
            host_ctrl_o[0] <= hold_ctrl_q[idx_q>>1];
            if (idx_q == 15) active_q <= 1'b0;
            idx_q <= idx_q + 1;
          end
        endcase
      end
    end
  end
endmodule

`default_nettype wire
