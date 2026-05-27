`default_nettype none

// OAM Response FIFO
// Simple synchronous FIFO for CAD response entries.
// Depth: 32 entries (one frame's worth of responses).

module oam_resp_fifo
  import asa_oam_pkg::*;
#(
  parameter int unsigned DEPTH = 32
) (
  input  logic          clk,
  input  logic          rst,
  input  logic          flush_i,

  // Write port
  input  oam_cad_resp_t wr_data_i,
  input  logic          wr_en_i,
  output logic          full_o,

  // Read port
  output oam_cad_resp_t rd_data_o,
  input  logic          rd_en_i,
  output logic          empty_o,

  // Status
  output logic [$clog2(DEPTH+1)-1:0] count_o
);

  localparam int unsigned ADDR_W = $clog2(DEPTH);

  oam_cad_resp_t mem [0:DEPTH-1];
  logic [ADDR_W:0] wr_ptr_q, rd_ptr_q;

  assign full_o  = (wr_ptr_q[ADDR_W] != rd_ptr_q[ADDR_W]) &&
                   (wr_ptr_q[ADDR_W-1:0] == rd_ptr_q[ADDR_W-1:0]);
  assign empty_o = (wr_ptr_q == rd_ptr_q);
  assign count_o = wr_ptr_q - rd_ptr_q;

  assign rd_data_o = mem[rd_ptr_q[ADDR_W-1:0]];

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
    end else if (flush_i) begin
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
    end else begin
      if (wr_en_i && !full_o) begin
        mem[wr_ptr_q[ADDR_W-1:0]] <= wr_data_i;
        wr_ptr_q <= wr_ptr_q + 1;
      end
      if (rd_en_i && !empty_o) begin
        rd_ptr_q <= rd_ptr_q + 1;
      end
    end
  end

endmodule

`default_nettype wire
