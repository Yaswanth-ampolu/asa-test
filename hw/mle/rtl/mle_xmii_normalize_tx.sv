`timescale 1ns/1ps
`default_nettype none

module mle_xmii_normalize_tx
  import asa_mle_xmii_pkg::*;
(
  input  logic        clk,
  input  logic        rst,
  input  xmii_type_e  xmii_type_i,
  input  logic        host_valid_i,
  input  logic [31:0] host_data_i,
  input  logic [3:0]  host_ctrl_i,
  output logic        host_ready_o,
  output logic        word_valid_o,
  output logic [63:0] word_data_o,
  output logic [7:0]  word_ctrl_o
);
  logic [63:0] data_q;
  logic [7:0]  ctrl_q;
  logic [4:0]  byte_cnt_q;
  logic        word_valid_q;

  assign host_ready_o = !word_valid_q;
  assign word_valid_o = word_valid_q;
  assign word_data_o  = data_q;
  assign word_ctrl_o  = ctrl_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      data_q <= '0;
      ctrl_q <= '0;
      byte_cnt_q <= '0;
      word_valid_q <= 1'b0;
    end else begin
      if (word_valid_q) begin
        word_valid_q <= 1'b0;
        byte_cnt_q   <= '0;
      end else if (host_valid_i) begin
        case (xmii_type_i)
          XMII_XGMII: begin
            for (int i = 0; i < 4; i++) begin
              data_q[8*(byte_cnt_q+i) +: 8] <= host_data_i[8*i +: 8];
              ctrl_q[byte_cnt_q+i] <= host_ctrl_i[i];
            end
            if (byte_cnt_q == 4) begin
              word_valid_q <= 1'b1;
              byte_cnt_q   <= '0;
            end else begin
              byte_cnt_q <= byte_cnt_q + 4;
            end
          end
          XMII_GMII: begin
            data_q[8*byte_cnt_q +: 8] <= host_data_i[7:0];
            ctrl_q[byte_cnt_q] <= host_ctrl_i[0];
            if (byte_cnt_q == 7) begin
              word_valid_q <= 1'b1;
              byte_cnt_q   <= '0;
            end else begin
              byte_cnt_q <= byte_cnt_q + 1;
            end
          end
          default: begin
            if (!byte_cnt_q[0]) begin
              data_q[8*(byte_cnt_q>>1) +: 4] <= host_data_i[3:0];
              ctrl_q[byte_cnt_q>>1] <= host_ctrl_i[0];
            end else begin
              data_q[8*(byte_cnt_q>>1)+4 +: 4] <= host_data_i[3:0];
            end
            if (byte_cnt_q == 15) begin
              word_valid_q <= 1'b1;
              byte_cnt_q   <= '0;
            end else begin
              byte_cnt_q <= byte_cnt_q + 1;
            end
          end
        endcase
      end
    end
  end
endmodule

`default_nettype wire
