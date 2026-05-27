`default_nettype none

// OAM Register Bridge
// Converts Read/Write CADs into reg_req_t, generates Return/ReadError/WriteAck responses.
// Spec: Section 5.5.3.1-5.5.3.5

module oam_reg_bridge
  import asa_oam_pkg::*;
  import asa_reg_pkg::*;
(
  input  logic          clk,
  input  logic          rst,

  // CAD input (from parser)
  input  oam_decoded_cad_t cad_i,
  input  logic          cad_valid_i,

  // Configuration
  input  logic [4:0]    src_node_id_i,
  input  logic          authenticated_i,

  // Register bus interface
  output reg_req_t      reg_req_o,
  output logic          reg_req_valid_o,
  input  reg_resp_t     reg_resp_i,
  input  logic          reg_resp_valid_i,

  // Response output (to FIFO)
  output oam_cad_resp_t resp_o,
  output logic          resp_valid_o,

  // Status
  output logic          busy_o
);

  typedef enum logic [1:0] {
    S_IDLE,
    S_WAIT_RESP,
    S_RESP_OUT
  } state_e;

  state_e state_q;
  oam_decoded_cad_t saved_cad_q;
  logic is_write_q;

  assign busy_o = (state_q != S_IDLE);

  // Register request formation
  always_comb begin
    reg_req_o = '0;
    reg_req_valid_o = 1'b0;

    if (state_q == S_IDLE && cad_valid_i &&
        (cad_i.cmd == OAM_CMD_READ || cad_i.cmd == OAM_CMD_WRITE)) begin
      reg_req_valid_o            = 1'b1;
      reg_req_o.addr.domain      = reg_domain_e'(cad_i.addr.domain);
      reg_req_o.addr.subdomain   = cad_i.addr.dlp_id;
      reg_req_o.addr.addr        = cad_i.addr.addr;
      reg_req_o.bitsel.valid     = 1'b0;
      reg_req_o.bitsel.msb       = 4'd0;
      reg_req_o.bitsel.lsb       = 4'd0;
      reg_req_o.wr_data          = cad_i.data;
      reg_req_o.wr_en            = (cad_i.cmd == OAM_CMD_WRITE);
      reg_req_o.rd_en            = (cad_i.cmd == OAM_CMD_READ);
      reg_req_o.oam_path         = 1'b1;
      reg_req_o.src_node_id      = src_node_id_i;
      reg_req_o.authenticated    = authenticated_i;
    end
  end

  // Response formation
  always_comb begin
    resp_o       = '0;
    resp_valid_o = 1'b0;

    if (state_q == S_WAIT_RESP && reg_resp_valid_i) begin
      resp_valid_o    = 1'b1;
      resp_o.valid    = 1'b1;
      resp_o.addr     = saved_cad_q.addr;

      if (!is_write_q) begin
        // Read response
        if (reg_resp_i.err_addr || reg_resp_i.err_access) begin
          resp_o.cmd  = OAM_CMD_READ_ERROR;
          resp_o.data = {8'd0, reg_resp_i.err_addr ? 8'h00 : 8'h01};
        end else begin
          resp_o.cmd  = OAM_CMD_RETURN;
          resp_o.data = reg_resp_i.rd_data;
        end
      end else begin
        // Write response
        resp_o.cmd = OAM_CMD_WRITE_ACK;
        if (reg_resp_i.err_addr)
          resp_o.data = {8'd0, WRITE_ACK_ADDR_MISSING};
        else if (reg_resp_i.err_access)
          resp_o.data = {8'd0, WRITE_ACK_RO_ONLY};
        else if (reg_resp_i.ack)
          resp_o.data = {8'd0, WRITE_ACK_SUCCESS};
        else
          resp_o.data = {8'd0, WRITE_ACK_FAIL};
      end
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q     <= S_IDLE;
      saved_cad_q <= '0;
      is_write_q  <= 1'b0;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (cad_valid_i && (cad_i.cmd == OAM_CMD_READ || cad_i.cmd == OAM_CMD_WRITE)) begin
            state_q     <= S_WAIT_RESP;
            saved_cad_q <= cad_i;
            is_write_q  <= (cad_i.cmd == OAM_CMD_WRITE);
          end
        end
        S_WAIT_RESP: begin
          if (reg_resp_valid_i) begin
            state_q <= S_IDLE;
          end
        end
        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule

`default_nettype wire
