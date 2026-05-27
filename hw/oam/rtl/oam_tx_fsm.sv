`default_nettype none

// OAM TX FSM (Non-root)
// Packs header + CADrespFIFO contents + padding into frame.
// Spec: Section 5.5.2 — Non-root TX

module oam_tx_fsm
  import asa_oam_pkg::*;
(
  input  logic          clk,
  input  logic          rst,
  input  logic          soft_reset_i,

  // DLP_TX interface
  input  logic          indicate_valid_i,
  output logic          oam_valid_o,
  output oam_frame_t    frame_o,           // 1504-bit packed frame

  // Header input (packed 192-bit / 24 bytes)
  input  oam_header_t   header_bytes_i,

  // Response FIFO read port
  input  oam_cad_resp_t fifo_rd_data_i,
  input  logic          fifo_empty_i,
  input  logic [7:0]    fifo_count_i,
  output logic          fifo_rd_en_o,

  // KeyEx response (sole CAD, terminates frame)
  input  logic          keyex_resp_pending_i,
  input  logic [7:0]    keyex_resp_len_i,
  input  oam_cad_bytes_t keyex_resp_payload_i,
  output logic          keyex_resp_consumed_o,

  // Session state
  output logic          frame_sent_o
);

  typedef enum logic [2:0] {
    S_IDLE,
    S_HEADER,
    S_CADS,
    S_KEYEX,
    S_PAD,
    S_DONE
  } state_e;

  state_e     state_q, state_d;
  logic [7:0] byte_idx_q, byte_idx_d;

  // Frame buffer as packed vector
  oam_frame_t frame_buf_q;
  logic       frame_valid_q;

  assign oam_valid_o  = frame_valid_q;
  assign frame_sent_o = (state_q == S_DONE);
  assign frame_o      = frame_buf_q;

  // CAD response bytes
  logic [7:0] cb0, cb1, cb2, cb3, cb4, cb5;
  always_comb begin
    cb0 = 8'd0; cb1 = 8'd0; cb2 = 8'd0;
    cb3 = 8'd0; cb4 = 8'd0; cb5 = 8'd0;
    if (!fifo_empty_i) begin
      cb0 = {(fifo_count_i > 8'd1), fifo_rd_data_i.cmd};
      cb1 = {fifo_rd_data_i.addr.domain, fifo_rd_data_i.addr.dlp_id[5:1]};
      cb2 = {fifo_rd_data_i.addr.dlp_id[0], fifo_rd_data_i.addr.addr[14:8]};
      cb3 = fifo_rd_data_i.addr.addr[7:0];
      cb4 = fifo_rd_data_i.data[15:8];
      cb5 = fifo_rd_data_i.data[7:0];
    end
  end

  function automatic logic [3:0] resp_cad_size(oam_cmd_code_e cmd);
    case (cmd)
      OAM_CMD_RETURN:     return 4'd6;
      OAM_CMD_READ_ERROR: return 4'd6;
      OAM_CMD_WRITE_ACK:  return 4'd6;
      OAM_CMD_LS_CONFIRM: return 4'd4;
      OAM_CMD_LS_DENY:    return 4'd2;
      default:            return 4'd6;
    endcase
  endfunction

  // FSM next-state
  always_comb begin
    state_d               = state_q;
    byte_idx_d            = byte_idx_q;
    fifo_rd_en_o          = 1'b0;
    keyex_resp_consumed_o = 1'b0;

    case (state_q)
      S_IDLE: begin
        if (indicate_valid_i) begin
          state_d    = S_HEADER;
          byte_idx_d = 8'd0;
        end
      end
      S_HEADER: begin
        byte_idx_d = 8'd24;
        state_d    = keyex_resp_pending_i ? S_KEYEX : S_CADS;
      end
      S_CADS: begin
        if (fifo_empty_i || byte_idx_q >= 8'd182) begin
          state_d = S_PAD;
        end else begin
          fifo_rd_en_o = 1'b1;
          byte_idx_d   = byte_idx_q + {4'd0, resp_cad_size(fifo_rd_data_i.cmd)};
        end
      end
      S_KEYEX: begin
        keyex_resp_consumed_o = 1'b1;
        byte_idx_d = 8'd25 + keyex_resp_len_i;
        state_d    = S_PAD;
      end
      S_PAD:  state_d = S_DONE;
      S_DONE: state_d = S_IDLE;
      default: state_d = S_IDLE;
    endcase
  end

  // Frame buffer update (registered)
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_q       <= S_IDLE;
      byte_idx_q    <= 8'd0;
      frame_valid_q <= 1'b0;
      frame_buf_q   <= 1504'd0;
    end else if (soft_reset_i) begin
      state_q       <= S_IDLE;
      byte_idx_q    <= 8'd0;
      frame_valid_q <= 1'b0;
      frame_buf_q   <= 1504'd0;
    end else begin
      state_q    <= state_d;
      byte_idx_q <= byte_idx_d;

      case (state_q)
        S_IDLE: frame_valid_q <= 1'b0;

        S_HEADER: begin
          // Copy 24-byte header into frame bytes 0-23 (bits 191:0)
          frame_buf_q[191:0] <= header_bytes_i;
        end

        S_CADS: begin
          if (!fifo_empty_i && byte_idx_q < 8'd182) begin
            frame_buf_q[byte_idx_q*8     +: 8] <= cb0;
            frame_buf_q[(byte_idx_q+1)*8 +: 8] <= cb1;
            frame_buf_q[(byte_idx_q+2)*8 +: 8] <= cb2;
            frame_buf_q[(byte_idx_q+3)*8 +: 8] <= cb3;
            frame_buf_q[(byte_idx_q+4)*8 +: 8] <= cb4;
            frame_buf_q[(byte_idx_q+5)*8 +: 8] <= cb5;
          end
        end

        S_KEYEX: begin
          frame_buf_q[199:192] <= {1'b0, OAM_CMD_KEYEX_RESP}; // byte 24
          for (int i = 0; i < OAM_KEYEX_MAX_BYTES; i++) begin
            frame_buf_q[(25+i)*8 +: 8] <= (i < keyex_resp_len_i) ?
              keyex_resp_payload_i[i*8 +: 8] : 8'd0;
          end
        end

        S_PAD: begin
          // Zero padding from byte_idx_q to end
          for (int i = 0; i < 188; i++) begin
            if (i[7:0] >= byte_idx_q)
              frame_buf_q[i*8 +: 8] <= 8'd0;
          end
          frame_valid_q <= 1'b1;
        end

        S_DONE: frame_valid_q <= 1'b0;

        default: begin end
      endcase
    end
  end

endmodule

`default_nettype wire
