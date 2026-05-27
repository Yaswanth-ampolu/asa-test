`default_nettype none

// OAM Header Check
// Validates RX header (frameID sequence check), generates error events.
// Spec: Section 5.5.2.5

module oam_header_check
  import asa_oam_pkg::*;
  import asa_error_pkg::*;
(
  input  logic          clk,
  input  logic          rst,
  input  logic          soft_reset_i,

  // RX frame input (packed: byte N = bits[N*8+7:N*8])
  input  logic          rx_valid_i,
  input  oam_frame_t    rx_frame_i,

  // Expected frame ID (from session state)
  input  logic [31:0]   expected_frame_id_i,

  // Outputs
  output logic          header_valid_o,       // Frame ID is correct (expected+1)
  output oam_error_code_e header_error_o,     // Error code if invalid
  output logic [31:0]   rx_frame_id_o,        // Extracted frame ID
  output logic          cad_next_o,           // CADnext bit from byte 4
  output logic [47:0]   ptb_clk_o,           // Extracted PTBclk
  output logic          ptb_clk_valid_o,
  output logic [8:0]    ptb_status_o,
  output logic          header_status_valid_o,
  output err_event_t    err_event_o           // Error event output
);

  // Registered frame capture (Verilator doesn't propagate changes through
  // unpacked array ports combinationally — must register on rx_valid_i edge)
  logic [31:0] frame_id_q;
  logic        cad_next_q;
  logic [47:0] ptb_clk_q;
  logic [8:0]  ptb_status_q;
  logic        status_valid_q;
  logic        captured_q;
  logic        hdr_valid_q;
  oam_error_code_e hdr_error_q;

  assign rx_frame_id_o = frame_id_q;
  assign cad_next_o    = cad_next_q;
  assign ptb_clk_o     = ptb_clk_q;
  assign ptb_status_o  = ptb_status_q;
  assign header_valid_o  = hdr_valid_q;
  assign header_error_o  = hdr_error_q;
  assign header_status_valid_o = status_valid_q;
  assign ptb_clk_valid_o = hdr_valid_q && status_valid_q;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      frame_id_q  <= 32'd0;
      cad_next_q  <= 1'b0;
      ptb_clk_q   <= 48'd0;
      ptb_status_q <= 9'd0;
      status_valid_q <= 1'b0;
      captured_q  <= 1'b0;
      hdr_valid_q <= 1'b0;
      hdr_error_q <= OAM_HDRFLD_NONE;
    end else if (soft_reset_i) begin
      captured_q  <= 1'b0;
      hdr_valid_q <= 1'b0;
      hdr_error_q <= OAM_HDRFLD_NONE;
      status_valid_q <= 1'b0;
    end else begin
      hdr_valid_q <= 1'b0;
      hdr_error_q <= OAM_HDRFLD_NONE;

      if (rx_valid_i && !captured_q) begin : capture_block
        logic [7:0] b0, b1, b2, b3, b4, b6, b7, b8, b9, b10, b11;
        logic [31:0] fid;
        b0  = oam_get_byte(rx_frame_i, 0);
        b1  = oam_get_byte(rx_frame_i, 1);
        b2  = oam_get_byte(rx_frame_i, 2);
        b3  = oam_get_byte(rx_frame_i, 3);
        b4  = oam_get_byte(rx_frame_i, 4);
        b6  = oam_get_byte(rx_frame_i, 6);
        b7  = oam_get_byte(rx_frame_i, 7);
        b8  = oam_get_byte(rx_frame_i, 8);
        b9  = oam_get_byte(rx_frame_i, 9);
        b10 = oam_get_byte(rx_frame_i, 10);
        b11 = oam_get_byte(rx_frame_i, 11);
        fid = {b3, b2, b1, b0};
        frame_id_q <= fid;
        cad_next_q <= b4[0];
        status_valid_q <= b4[6];
        ptb_status_q <= {oam_get_byte(rx_frame_i, 5), b4[7]};
        ptb_clk_q  <= {b11, b10, b9, b8, b7, b6};
        captured_q <= 1'b1;
        if (fid == expected_frame_id_i + 32'd1) begin
          hdr_valid_q <= 1'b1;
        end else if (fid <= expected_frame_id_i) begin
          hdr_error_q <= OAM_HDRFLD_DUPL_ID;
        end else begin
          hdr_error_q <= OAM_HDRFLD_MISS_ID;
        end
      end else if (!rx_valid_i) begin
        captured_q <= 1'b0;
      end
    end
  end

  // Error event generation
  always_comb begin
    err_event_o.valid    = 1'b0;
    err_event_o.source   = ERR_SRC_OAM;
    err_event_o.severity = ERR_SEV_DROP;
    err_event_o.code     = 4'd0;

    if (rx_valid_i && header_error_o != OAM_HDRFLD_NONE) begin
      err_event_o.valid = 1'b1;
      case (header_error_o)
        OAM_HDRFLD_DUPL_ID: err_event_o.code = OAM_ERR_DUPL_FRAME_ID;
        OAM_HDRFLD_MISS_ID: err_event_o.code = OAM_ERR_HDR_DECODE;
        default:             err_event_o.code = OAM_ERR_HDR_DECODE;
      endcase
    end
  end

endmodule

`default_nettype wire
