`timescale 1ns/1ps
`default_nettype none

module ptb_oam_header_if (
  input  logic        clk,
  input  logic        rst,
  input  logic        soft_reset_i,
  input  logic [47:0] ptb_clk_i,
  input  logic [15:0] ptb_status_i,
  input  logic        ptb_locked_i,
  input  logic        ptb_valid_i,
  input  logic        oam_tx_snapshot_req_i,
  input  logic        oam_rx_valid_i,
  input  logic [47:0] oam_rx_ptbclk_i,
  output logic [47:0] oam_tx_ptbclk_o,
  output logic [8:0]  oam_tx_ptbstatus_o,
  output logic [7:0]  oam_tx_header_byte4_o,
  output logic [7:0]  oam_tx_header_byte5_o,
  output logic        copy_oam_en_o,
  output logic [47:0] copy_oam_value_o,
  output logic [47:0] ptb_oam_clk_o,
  output logic [15:0] ptb_oam_dly_o
);

  logic [47:0] oam_tx_ptbclk_q;
  logic [8:0]  oam_tx_ptbstatus_q;
  logic [47:0] ptb_oam_clk_q;
  logic [15:0] ptb_oam_dly_q;

  function automatic logic [15:0] sat_oam_delay(input logic [47:0] now_value,
                                                input logic [47:0] rx_value);
    logic [47:0] diff;
    if (now_value < rx_value) begin
      return 16'd0;
    end
    diff = now_value - rx_value;
    if (diff > 48'h0000_0000_FFFF) begin
      return 16'hFFFF;
    end
    return diff[15:0];
  endfunction

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      oam_tx_ptbclk_q <= 48'd0;
      oam_tx_ptbstatus_q <= 9'd0;
      ptb_oam_clk_q <= 48'd0;
      ptb_oam_dly_q <= 16'd0;
    end else if (soft_reset_i) begin
      oam_tx_ptbclk_q <= 48'd0;
      oam_tx_ptbstatus_q <= 9'd0;
      ptb_oam_clk_q <= 48'd0;
      ptb_oam_dly_q <= 16'd0;
    end else begin
      if (oam_tx_snapshot_req_i) begin
        oam_tx_ptbstatus_q <= {ptb_status_i[7:0], ptb_status_i[8]};
        oam_tx_ptbclk_q <= (ptb_valid_i && ptb_locked_i) ? ptb_clk_i : 48'd0;
      end

      if (oam_rx_valid_i) begin
        ptb_oam_clk_q <= oam_rx_ptbclk_i;
        if (ptb_locked_i) begin
          ptb_oam_dly_q <= sat_oam_delay(ptb_clk_i, oam_rx_ptbclk_i);
        end else begin
          ptb_oam_dly_q <= 16'd0;
        end
      end else if (!ptb_locked_i) begin
        ptb_oam_dly_q <= 16'd0;
      end
    end
  end

  assign copy_oam_en_o = oam_rx_valid_i && !ptb_locked_i;
  assign copy_oam_value_o = oam_rx_ptbclk_i;
  assign oam_tx_ptbclk_o = oam_tx_ptbclk_q;
  assign oam_tx_ptbstatus_o = oam_tx_ptbstatus_q;
  assign oam_tx_header_byte4_o = {oam_tx_ptbstatus_q[0], 6'd0, 1'b0};
  assign oam_tx_header_byte5_o = oam_tx_ptbstatus_q[8:1];
  assign ptb_oam_clk_o = ptb_oam_clk_q;
  assign ptb_oam_dly_o = ptb_oam_dly_q;

endmodule

`default_nettype wire
