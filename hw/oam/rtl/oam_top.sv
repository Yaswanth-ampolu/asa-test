`default_nettype none

module oam_top
  import asa_oam_pkg::*;
  import asa_reg_pkg::*;
  import asa_intf_pkg::*;
  import asa_error_pkg::*;
#(
  parameter bit IS_ROOT = 1'b0,
  parameter int unsigned LONGATOM_MAX_WRITES = 128
) (
  input  logic                clk,
  input  logic                rst,
  input  logic                soft_reset,

  input  logic                dlp_tx_indicate_valid,
  output logic                dlp_tx_oam_valid,
  output oam_frame_t          dlp_tx_oam_data,
  output oam_tx_meta_t        dlp_tx_meta,

  input  logic                dlp_rx_oam_valid,
  input  oam_frame_t          dlp_rx_oam_data,
  input  oam_rx_status_t      dlp_rx_status,

  output reg_req_t            reg_req_o,
  output logic                reg_req_valid_o,
  input  reg_resp_t           reg_resp_i,
  input  logic                reg_resp_valid_i,

  output err_event_t          err_event_o,

  input  logic [3:0]          node_state_i,
  output logic                start_tdd_o,
  output start_tdd_params_t   start_tdd_params_o,
  output logic                enum_complete_o,
  output logic [4:0]          assigned_node_id_o,

  input  logic [47:0]         ptb_clk_i,
  input  logic [8:0]          ptb_status_i,
  input  logic                ptb_locked_i,
  output logic [47:0]         oam_rx_ptb_clk_o,
  output logic                oam_rx_ptb_valid_o,

  output logic                ls_announce_valid_o,
  output ls_announce_params_t ls_announce_params_o,
  output logic                ls_confirm_valid_o,
  output ls_confirm_params_t  ls_confirm_params_o,
  output logic                ls_deny_valid_o,
  output logic                ls_sleep_valid_o,
  output ls_sleep_params_t    ls_sleep_params_o,
  input  logic                ls_resp_valid_i,
  input  oam_cad_resp_t       ls_resp_cad_i,

  output logic                keyex_msg_valid_o,
  output logic [4:0]          keyex_msg_src_node_id_o,
  output oam_keyex_msg_t      keyex_msg_o,
  input  logic                keyex_tx_valid_i,
  input  oam_keyex_msg_t      keyex_tx_msg_i,

  input  logic [15:0]         link_quality_i,
  input  logic [15:0]         sqi_i,
  input  logic [15:0]         fec_stat_i,

  input  logic [4:0]          local_node_id_i,
  input  logic                link_authenticated_i,

  input  logic                read_errors1_i,
  input  logic                read_errors2_i,
  output logic [15:0]         oam_errors1_o,
  output logic [15:0]         oam_errors2_o,

  input  logic                root_cmd_valid_i,
  input  oam_tx_cmd_t         root_cmd_i,
  output logic                root_cmd_ready_o,
  output logic                root_rx_valid_o,
  output logic [4:0]          root_rx_src_node_id_o,
  output oam_decoded_cad_t    root_rx_cad_o
);

  localparam int unsigned MAX_ROOT_SESSIONS = 32;
  localparam int unsigned RESP_FIFO_DEPTH   = 128;

  typedef enum logic [3:0] {
    PROC_IDLE,
    PROC_CLASSIFY,
    PROC_DISPATCH,
    PROC_WAIT_REG,
    PROC_REPLAY_DISPATCH,
    PROC_REPLAY_WAIT_REG,
    PROC_FAIL_ACK
  } proc_state_e;

  logic [31:0] root_tx_frame_id_q [0:MAX_ROOT_SESSIONS-1];
  logic [31:0] root_rx_frame_id_q [0:MAX_ROOT_SESSIONS-1];
  oam_error_code_e root_pending_error_q [0:MAX_ROOT_SESSIONS-1];

  logic [31:0] tx_frame_id_q;
  logic [31:0] rx_frame_id_q;
  oam_error_code_e pending_error_q;

  logic [31:0] selected_tx_frame_id;
  oam_error_code_e selected_pending_error;
  logic            selected_cad_next;
  logic [4:0]      selected_tx_target;

  oam_header_t tx_header_bytes;
  logic [7:0]  tx_fifo_count;

  logic                hdr_req_q;
  oam_frame_t          rx_frame_q;
  oam_payload_t        rx_payload_q;
  oam_rx_status_t      rx_status_q;
  logic [31:0]         expected_rx_frame_id;
  logic                hdr_valid;
  oam_error_code_e     hdr_error;
  logic [31:0]         rx_frame_id;
  logic                hdr_cad_next;
  logic [47:0]         rx_ptb_clk;
  logic                rx_ptb_clk_valid;
  logic [8:0]          rx_ptb_status;
  logic                hdr_status_valid;
  err_event_t          hdr_err_event;

  logic                parser_start_q;
  logic                parser_done;
  logic                parser_busy;
  logic                parse_error;
  oam_decoded_cad_t    parsed_cad;
  logic                parsed_cad_valid;
  logic [7:0]          parsed_cad_offset;
  logic [7:0]          parsed_cad_size;

  oam_decoded_cad_t    frame_cads_q [0:OAM_MAX_FRAME_CADS-1];
  logic [7:0]          frame_offsets_q [0:OAM_MAX_FRAME_CADS-1];
  logic [5:0]          frame_cad_count_q;
  logic                frame_parse_error_q;

  proc_state_e         proc_state_q;
  logic [5:0]          proc_idx_q;
  logic [5:0]          replay_idx_q;
  logic [5:0]          fail_ack_idx_q;
  logic [4:0]          proc_src_node_q;
  logic                proc_has_longatom_q;
  logic                proc_has_longatom_close_q;
  logic                proc_invalid_longatom_q;
  logic [5:0]          proc_marker_idx_q;
  logic                frame_has_longatom_c;
  logic                frame_has_longatom_close_c;
  logic                frame_invalid_longatom_c;
  logic [5:0]          frame_marker_idx_c;

  oam_decoded_cad_t    dispatch_cad;
  logic [7:0]          dispatch_offset;
  logic                reg_dispatch_fire;
  logic                dispatch_is_replay;

  oam_cad_resp_t       reg_resp;
  logic                reg_resp_valid;

  oam_cad_resp_t       manual_resp;
  logic                manual_resp_valid;
  logic                longatom_overflow_q;
  logic                longatom_active_q;
  logic [5:0]          longatom_frame_count_q;
  oam_decoded_cad_t    longatom_buf_q [0:LONGATOM_MAX_WRITES-1];
  logic [7:0]          longatom_buf_count_q;

  oam_cad_resp_t       fifo_wr_data;
  logic                fifo_wr_en;
  oam_cad_resp_t       fifo_rd_data;
  logic                fifo_rd_en;
  logic                fifo_empty;
  logic                fifo_full;

  logic                tx_frame_sent;
  logic                tx_fifo_rd_en;
  logic                tx_nonroot_valid;
  oam_frame_t          tx_nonroot_frame;
  logic                tx_root_valid_q;
  oam_frame_t          tx_root_frame_q;
  oam_tx_meta_t        tx_root_meta_q;
  logic [4:0]          tx_root_target_q;

  oam_cad_resp_t       ls_resp;
  logic                ls_resp_valid;

  logic                ls_dispatch_valid;
  logic                keyex_dispatch_valid;
  logic [7:0]          ls_dispatch_offset;
  oam_decoded_cad_t    ls_dispatch_cad;

  logic                inc_decode_err;
  logic                inc_dupl_id;
  logic                inc_miss_id;
  logic                inc_payload_err;

  assign selected_tx_target = IS_ROOT ? root_cmd_i.target_id : 5'd1;
  assign selected_tx_frame_id = IS_ROOT ? root_tx_frame_id_q[selected_tx_target] : tx_frame_id_q;
  assign selected_pending_error = IS_ROOT ? root_pending_error_q[selected_tx_target] : pending_error_q;
  assign selected_cad_next = IS_ROOT ? root_cmd_valid_i : (!fifo_empty || keyex_tx_valid_i);

  oam_header_gen u_header_gen (
    .frame_id_i      (selected_tx_frame_id),
    .cad_next_i      (selected_cad_next),
    .oam_error_i     (selected_pending_error),
    .ptb_status_i    (ptb_status_i),
    .ptb_clk_i       (ptb_locked_i ? ptb_clk_i : 48'd0),
    .link_health_1_i (link_quality_i),
    .link_health_2_i (sqi_i),
    .link_health_3_i (fec_stat_i),
    .header_bytes_o  (tx_header_bytes)
  );

  assign expected_rx_frame_id = IS_ROOT ? root_rx_frame_id_q[rx_status_q.src_node_id] : rx_frame_id_q;

  oam_header_check u_header_check (
    .clk                 (clk),
    .rst                 (rst),
    .soft_reset_i        (soft_reset),
    .rx_valid_i          (hdr_req_q),
    .rx_frame_i          (rx_frame_q),
    .expected_frame_id_i (expected_rx_frame_id),
    .header_valid_o      (hdr_valid),
    .header_error_o      (hdr_error),
    .rx_frame_id_o       (rx_frame_id),
    .cad_next_o          (hdr_cad_next),
    .ptb_clk_o           (rx_ptb_clk),
    .ptb_clk_valid_o     (rx_ptb_clk_valid),
    .ptb_status_o        (rx_ptb_status),
    .header_status_valid_o(hdr_status_valid),
    .err_event_o         (hdr_err_event)
  );

  assign oam_rx_ptb_clk_o = rx_ptb_clk;
  assign oam_rx_ptb_valid_o = rx_ptb_clk_valid;

  oam_cad_parser u_cad_parser (
    .clk          (clk),
    .rst          (rst),
    .start_i      (parser_start_q),
    .payload_i    (rx_payload_q),
    .done_o       (parser_done),
    .busy_o       (parser_busy),
    .cad_o        (parsed_cad),
    .cad_valid_o  (parsed_cad_valid),
    .cad_offset_o (parsed_cad_offset),
    .cad_size_o   (parsed_cad_size),
    .parse_error_o(parse_error)
  );

  assign dispatch_is_replay = (proc_state_q == PROC_REPLAY_DISPATCH) || (proc_state_q == PROC_REPLAY_WAIT_REG);
  assign dispatch_cad = dispatch_is_replay ? longatom_buf_q[replay_idx_q] : frame_cads_q[proc_idx_q];
  assign dispatch_offset = dispatch_is_replay ? 8'd0 : frame_offsets_q[proc_idx_q];
  assign reg_dispatch_fire =
    ((proc_state_q == PROC_DISPATCH) || (proc_state_q == PROC_REPLAY_DISPATCH)) &&
    ((dispatch_cad.cmd == OAM_CMD_READ) || (dispatch_cad.cmd == OAM_CMD_WRITE));

  oam_reg_bridge u_reg_bridge (
    .clk             (clk),
    .rst             (rst),
    .cad_i           (dispatch_cad),
    .cad_valid_i     (reg_dispatch_fire),
    .src_node_id_i   (IS_ROOT ? proc_src_node_q : 5'd1),
    .authenticated_i (link_authenticated_i),
    .reg_req_o       (reg_req_o),
    .reg_req_valid_o (reg_req_valid_o),
    .reg_resp_i      (reg_resp_i),
    .reg_resp_valid_i(reg_resp_valid_i),
    .resp_o          (reg_resp),
    .resp_valid_o    (reg_resp_valid),
    .busy_o          ()
  );

  assign ls_dispatch_valid = (proc_state_q == PROC_DISPATCH) &&
                             !IS_ROOT &&
                             ((dispatch_cad.cmd == OAM_CMD_LS_ANNOUNCE) ||
                              (dispatch_cad.cmd == OAM_CMD_LS_CONFIRM) ||
                              (dispatch_cad.cmd == OAM_CMD_LS_DENY) ||
                              (dispatch_cad.cmd == OAM_CMD_LS_SLEEP));
  assign ls_dispatch_cad = dispatch_cad;
  assign ls_dispatch_offset = dispatch_offset;

  oam_ls_bridge u_ls_bridge (
    .clk                 (clk),
    .rst                 (rst),
    .cad_i               (ls_dispatch_cad),
    .cad_valid_i         (ls_dispatch_valid),
    .payload_i           (rx_payload_q),
    .cad_offset_i        (ls_dispatch_offset),
    .ls_announce_valid_o (ls_announce_valid_o),
    .ls_announce_params_o(ls_announce_params_o),
    .ls_confirm_valid_o  (ls_confirm_valid_o),
    .ls_confirm_params_o (ls_confirm_params_o),
    .ls_deny_valid_o     (ls_deny_valid_o),
    .ls_sleep_valid_o    (ls_sleep_valid_o),
    .ls_sleep_params_o   (ls_sleep_params_o),
    .ls_resp_valid_i     (ls_resp_valid_i),
    .ls_resp_cad_i       (ls_resp_cad_i),
    .resp_o              (ls_resp),
    .resp_valid_o        (ls_resp_valid)
  );

  assign keyex_dispatch_valid = (proc_state_q == PROC_DISPATCH) &&
                                ((dispatch_cad.cmd == OAM_CMD_KEYEX_REQ) ||
                                 (dispatch_cad.cmd == OAM_CMD_KEYEX_RESP));

  oam_keyex_bridge u_keyex_bridge (
    .clk                  (clk),
    .rst                  (rst),
    .cad_i                (dispatch_cad),
    .cad_valid_i          (keyex_dispatch_valid),
    .payload_i            (rx_payload_q),
    .cad_offset_i         (dispatch_offset),
    .src_node_id_i        (proc_src_node_q),
    .keyex_msg_valid_o    (keyex_msg_valid_o),
    .keyex_msg_src_node_id_o(keyex_msg_src_node_id_o),
    .keyex_msg_o          (keyex_msg_o)
  );

  always_comb begin
    fifo_wr_data = '0;
    fifo_wr_en   = 1'b0;
    if (manual_resp_valid) begin
      fifo_wr_data = manual_resp;
      fifo_wr_en   = 1'b1;
    end else if (reg_resp_valid) begin
      fifo_wr_data = reg_resp;
      fifo_wr_en   = 1'b1;
    end else if (ls_resp_valid) begin
      fifo_wr_data = ls_resp;
      fifo_wr_en   = 1'b1;
    end
  end

  oam_resp_fifo #(.DEPTH(RESP_FIFO_DEPTH)) u_resp_fifo (
    .clk      (clk),
    .rst      (rst),
    .flush_i  (soft_reset),
    .wr_data_i(fifo_wr_data),
    .wr_en_i  (fifo_wr_en),
    .full_o   (fifo_full),
    .rd_data_o(fifo_rd_data),
    .rd_en_i  (tx_fifo_rd_en),
    .empty_o  (fifo_empty),
    .count_o  (tx_fifo_count)
  );

  oam_tx_fsm u_tx_fsm (
    .clk                  (clk),
    .rst                  (rst),
    .soft_reset_i         (soft_reset),
    .indicate_valid_i     (dlp_tx_indicate_valid && !IS_ROOT),
    .oam_valid_o          (tx_nonroot_valid),
    .frame_o              (tx_nonroot_frame),
    .header_bytes_i       (tx_header_bytes),
    .fifo_rd_data_i       (fifo_rd_data),
    .fifo_empty_i         (fifo_empty),
    .fifo_count_i         (tx_fifo_count),
    .fifo_rd_en_o         (tx_fifo_rd_en),
    .keyex_resp_pending_i (keyex_tx_valid_i && keyex_tx_msg_i.valid && !IS_ROOT),
    .keyex_resp_len_i     (keyex_tx_msg_i.payload_len),
    .keyex_resp_payload_i (keyex_tx_msg_i.payload),
    .keyex_resp_consumed_o(),
    .frame_sent_o         (tx_frame_sent)
  );

  oam_error_counters u_error_counters (
    .clk               (clk),
    .rst               (rst),
    .soft_reset_i      (soft_reset),
    .inc_decode_err_i  (inc_decode_err),
    .inc_dupl_id_i     (inc_dupl_id),
    .inc_miss_id_i     (inc_miss_id),
    .inc_payload_err_i (inc_payload_err),
    .read_errors1_i    (read_errors1_i),
    .read_errors2_i    (read_errors2_i),
    .oam_errors1_o     (oam_errors1_o),
    .oam_errors2_o     (oam_errors2_o)
  );

  always_comb begin
    manual_resp = '0;
    manual_resp_valid = 1'b0;
    if (proc_state_q == PROC_FAIL_ACK && fail_ack_idx_q < longatom_buf_count_q) begin
      manual_resp_valid = 1'b1;
      manual_resp.valid = 1'b1;
      manual_resp.cmd   = OAM_CMD_WRITE_ACK;
      manual_resp.addr  = longatom_buf_q[fail_ack_idx_q].addr;
      manual_resp.data  = {8'd0, WRITE_ACK_FAIL};
    end
  end

  always_comb begin
    root_rx_valid_o = 1'b0;
    root_rx_src_node_id_o = proc_src_node_q;
    root_rx_cad_o = '0;

    start_tdd_o = 1'b0;
    start_tdd_params_o = '0;
    enum_complete_o = 1'b0;
    assigned_node_id_o = '0;

    if (IS_ROOT && (proc_state_q == PROC_DISPATCH)) begin
      root_rx_valid_o = 1'b1;
      root_rx_cad_o = dispatch_cad;
    end else if (!IS_ROOT && (proc_state_q == PROC_DISPATCH)) begin
      unique case (dispatch_cad.cmd)
        OAM_CMD_START_TDD: begin
          start_tdd_o = 1'b1;
          start_tdd_params_o.ptb_time = {
            oam_pay_get_byte(rx_payload_q, dispatch_offset + 1),
            oam_pay_get_byte(rx_payload_q, dispatch_offset + 2),
            oam_pay_get_byte(rx_payload_q, dispatch_offset + 3),
            oam_pay_get_byte(rx_payload_q, dispatch_offset + 4),
            oam_pay_get_byte(rx_payload_q, dispatch_offset + 5),
            oam_pay_get_byte(rx_payload_q, dispatch_offset + 6)};
          start_tdd_params_o.dll_line_min = {
            oam_pay_get_byte(rx_payload_q, dispatch_offset + 7),
            oam_pay_get_byte(rx_payload_q, dispatch_offset + 8)};
          start_tdd_params_o.dll_line_max = {
            oam_pay_get_byte(rx_payload_q, dispatch_offset + 9),
            oam_pay_get_byte(rx_payload_q, dispatch_offset + 10)};
        end
        OAM_CMD_START_ENUM: begin
          enum_complete_o = 1'b1;
          assigned_node_id_o = dispatch_cad.free_node_id;
        end
        default: begin end
      endcase
    end
  end

  always_comb begin
    inc_decode_err  = hdr_err_event.valid && (hdr_err_event.code == OAM_ERR_HDR_DECODE);
    inc_dupl_id     = hdr_err_event.valid && (hdr_err_event.code == OAM_ERR_DUPL_FRAME_ID);
    inc_miss_id     = hdr_error == OAM_HDRFLD_MISS_ID;
    inc_payload_err = frame_parse_error_q;
    err_event_o     = hdr_err_event;
  end

  always_comb begin
    frame_has_longatom_c = 1'b0;
    frame_has_longatom_close_c = 1'b0;
    frame_invalid_longatom_c = frame_parse_error_q;
    frame_marker_idx_c = 6'd0;
    for (int j = 0; j < frame_cad_count_q; j++) begin
      if (frame_cads_q[j].cmd == OAM_CMD_LONG_ATOM) begin
        frame_has_longatom_c = 1'b1;
        frame_marker_idx_c = j[5:0];
        if (j != frame_cad_count_q - 1)
          frame_invalid_longatom_c = 1'b1;
      end
      if (frame_cads_q[j].cmd == OAM_CMD_LONG_ATOM_CLOSE) begin
        frame_has_longatom_close_c = 1'b1;
        frame_marker_idx_c = j[5:0];
        if (j != frame_cad_count_q - 1)
          frame_invalid_longatom_c = 1'b1;
      end
    end
    if (!IS_ROOT && (frame_has_longatom_c || frame_has_longatom_close_c)) begin
      for (int j = 0; j < frame_marker_idx_c; j++) begin
        if (frame_cads_q[j].cmd != OAM_CMD_WRITE)
          frame_invalid_longatom_c = 1'b1;
      end
    end
  end

  integer i;
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      tx_frame_id_q <= 32'd0;
      rx_frame_id_q <= 32'd0;
      pending_error_q <= OAM_HDRFLD_NONE;
      hdr_req_q <= 1'b0;
      parser_start_q <= 1'b0;
      frame_cad_count_q <= 6'd0;
      frame_parse_error_q <= 1'b0;
      proc_state_q <= PROC_IDLE;
      proc_idx_q <= 6'd0;
      replay_idx_q <= 6'd0;
      fail_ack_idx_q <= 6'd0;
      proc_src_node_q <= 5'd0;
      proc_has_longatom_q <= 1'b0;
      proc_has_longatom_close_q <= 1'b0;
      proc_invalid_longatom_q <= 1'b0;
      proc_marker_idx_q <= 6'd0;
      longatom_active_q <= 1'b0;
      longatom_overflow_q <= 1'b0;
      longatom_frame_count_q <= 6'd0;
      longatom_buf_count_q <= 8'd0;
      if (tx_root_valid_q)
        tx_root_valid_q <= 1'b0;
      tx_root_frame_q <= '0;
      tx_root_meta_q <= '0;
      tx_root_target_q <= 5'd0;
      for (i = 0; i < MAX_ROOT_SESSIONS; i++) begin
        root_tx_frame_id_q[i] <= 32'd0;
        root_rx_frame_id_q[i] <= 32'd0;
        root_pending_error_q[i] <= OAM_HDRFLD_NONE;
      end
    end else if (soft_reset) begin
      tx_frame_id_q <= 32'd0;
      rx_frame_id_q <= 32'd0;
      pending_error_q <= OAM_HDRFLD_NONE;
      hdr_req_q <= 1'b0;
      parser_start_q <= 1'b0;
      frame_cad_count_q <= 6'd0;
      frame_parse_error_q <= 1'b0;
      proc_state_q <= PROC_IDLE;
      proc_idx_q <= 6'd0;
      replay_idx_q <= 6'd0;
      fail_ack_idx_q <= 6'd0;
      proc_src_node_q <= 5'd0;
      proc_has_longatom_q <= 1'b0;
      proc_has_longatom_close_q <= 1'b0;
      proc_invalid_longatom_q <= 1'b0;
      proc_marker_idx_q <= 6'd0;
      longatom_active_q <= 1'b0;
      longatom_overflow_q <= 1'b0;
      longatom_frame_count_q <= 6'd0;
      longatom_buf_count_q <= 8'd0;
      if (tx_root_valid_q)
        tx_root_valid_q <= 1'b0;
      tx_root_frame_q <= '0;
      tx_root_meta_q <= '0;
      tx_root_target_q <= 5'd0;
      for (i = 0; i < MAX_ROOT_SESSIONS; i++) begin
        root_tx_frame_id_q[i] <= 32'd0;
        root_rx_frame_id_q[i] <= 32'd0;
        root_pending_error_q[i] <= OAM_HDRFLD_NONE;
      end
    end else begin
      hdr_req_q <= 1'b0;
      parser_start_q <= 1'b0;
      tx_root_valid_q <= 1'b0;

      if (IS_ROOT && dlp_tx_indicate_valid && root_cmd_valid_i) begin
        tx_root_frame_q <= 1504'd0;
        tx_root_frame_q[191:0] <= tx_header_bytes;
        tx_root_frame_q[199:192] <= {(root_cmd_i.payload_len != 8'd0), root_cmd_i.cmd};
        for (i = 0; i < OAM_KEYEX_MAX_BYTES; i++) begin
          tx_root_frame_q[(25+i)*8 +: 8] <= (i < root_cmd_i.payload_len) ?
            root_cmd_i.payload[i*8 +: 8] : 8'd0;
        end
        tx_root_valid_q <= 1'b1;
        tx_root_meta_q.target_id <= root_cmd_i.target_id;
        tx_root_meta_q.packet_id <= root_tx_frame_id_q[root_cmd_i.target_id][4:0];
        tx_root_meta_q.nd_en <= root_cmd_i.nd_en;
        tx_root_meta_q.target_id1 <= root_cmd_i.target_id1;
        tx_root_meta_q.target_id2 <= root_cmd_i.target_id2;
        tx_root_meta_q.target_id3 <= root_cmd_i.target_id3;
        tx_root_target_q <= root_cmd_i.target_id;
        root_tx_frame_id_q[root_cmd_i.target_id] <= root_tx_frame_id_q[root_cmd_i.target_id] + 32'd1;
        root_pending_error_q[root_cmd_i.target_id] <= OAM_HDRFLD_NONE;
      end

      if (dlp_rx_oam_valid && (proc_state_q == PROC_IDLE) && !hdr_req_q && !parser_busy) begin
        rx_frame_q <= dlp_rx_oam_data;
        rx_payload_q <= oam_frame_payload(dlp_rx_oam_data);
        rx_status_q <= dlp_rx_status;
        proc_src_node_q <= dlp_rx_status.src_node_id;
        hdr_req_q <= 1'b1;
        frame_cad_count_q <= 6'd0;
        frame_parse_error_q <= 1'b0;
      end

      if (hdr_valid) begin
        if (hdr_cad_next) begin
          parser_start_q <= 1'b1;
        end else begin
          if (IS_ROOT) begin
            root_rx_frame_id_q[proc_src_node_q] <= rx_frame_id;
          end else begin
            rx_frame_id_q <= rx_frame_id;
          end
        end
      end else if (hdr_error != OAM_HDRFLD_NONE) begin
        if (IS_ROOT) begin
          root_pending_error_q[proc_src_node_q] <= hdr_error;
        end else begin
          pending_error_q <= hdr_error;
        end
        if (longatom_active_q) begin
          longatom_active_q <= 1'b0;
          longatom_buf_count_q <= 8'd0;
          longatom_frame_count_q <= 6'd0;
        end
      end

      if (parsed_cad_valid && (frame_cad_count_q < OAM_MAX_FRAME_CADS)) begin
        frame_cads_q[frame_cad_count_q] <= parsed_cad;
        frame_offsets_q[frame_cad_count_q] <= parsed_cad_offset;
        frame_cad_count_q <= frame_cad_count_q + 6'd1;
      end
      if (parse_error) begin
        frame_parse_error_q <= 1'b1;
      end

      case (proc_state_q)
        PROC_IDLE: begin
          if (parser_done) begin
            proc_state_q <= PROC_CLASSIFY;
            proc_idx_q <= 6'd0;
            proc_has_longatom_q <= 1'b0;
            proc_has_longatom_close_q <= 1'b0;
            proc_invalid_longatom_q <= 1'b0;
            proc_marker_idx_q <= 6'd0;
            if (IS_ROOT) begin
              root_rx_frame_id_q[proc_src_node_q] <= rx_frame_id;
            end else begin
              rx_frame_id_q <= rx_frame_id;
            end
          end
        end

        PROC_CLASSIFY: begin
          proc_has_longatom_q <= frame_has_longatom_c;
          proc_has_longatom_close_q <= frame_has_longatom_close_c;
          proc_invalid_longatom_q <= frame_invalid_longatom_c;
          proc_marker_idx_q <= frame_marker_idx_c;
          proc_state_q <= PROC_DISPATCH;
          proc_idx_q <= 6'd0;
          if (!IS_ROOT && frame_has_longatom_c && !frame_invalid_longatom_c) begin
            if ((longatom_frame_count_q + 6'd1) >= LONGATOM_LIMIT[5:0]) begin
              longatom_overflow_q <= 1'b1;
              proc_state_q <= PROC_FAIL_ACK;
              fail_ack_idx_q <= 6'd0;
            end else begin
              /* verilator lint_off BLKSEQ */
              for (i = 0; i < frame_marker_idx_c; i++) begin
                if (longatom_buf_count_q < LONGATOM_MAX_WRITES) begin
                  longatom_buf_q[longatom_buf_count_q + i] = frame_cads_q[i];
                end
              end
              /* verilator lint_on BLKSEQ */
              longatom_buf_count_q <= longatom_buf_count_q + frame_marker_idx_c;
              longatom_active_q <= 1'b1;
              longatom_frame_count_q <= longatom_frame_count_q + 6'd1;
              proc_state_q <= PROC_IDLE;
            end
          end else if (!IS_ROOT && frame_has_longatom_close_c) begin
            if (!longatom_active_q || frame_invalid_longatom_c) begin
              proc_state_q <= PROC_FAIL_ACK;
              fail_ack_idx_q <= 6'd0;
            end else begin
              /* verilator lint_off BLKSEQ */
              for (i = 0; i < frame_marker_idx_c; i++) begin
                if (longatom_buf_count_q < LONGATOM_MAX_WRITES) begin
                  longatom_buf_q[longatom_buf_count_q + i] = frame_cads_q[i];
                end
              end
              /* verilator lint_on BLKSEQ */
              longatom_buf_count_q <= longatom_buf_count_q + frame_marker_idx_c;
              replay_idx_q <= 6'd0;
              proc_state_q <= PROC_REPLAY_DISPATCH;
            end
          end else if (!IS_ROOT && longatom_active_q && (frame_cad_count_q != 6'd0)) begin
            proc_state_q <= PROC_FAIL_ACK;
            fail_ack_idx_q <= 6'd0;
          end
        end

        PROC_DISPATCH: begin
          if (proc_idx_q >= frame_cad_count_q) begin
            proc_state_q <= PROC_IDLE;
          end else if ((dispatch_cad.cmd == OAM_CMD_READ) || (dispatch_cad.cmd == OAM_CMD_WRITE)) begin
            if (!IS_ROOT)
              proc_state_q <= PROC_WAIT_REG;
            else
              proc_idx_q <= proc_idx_q + 6'd1;
          end else begin
            proc_idx_q <= proc_idx_q + 6'd1;
          end
        end

        PROC_WAIT_REG: begin
          if (reg_resp_valid) begin
            proc_idx_q <= proc_idx_q + 6'd1;
            proc_state_q <= PROC_DISPATCH;
          end
        end

        PROC_REPLAY_DISPATCH: begin
          if (replay_idx_q >= longatom_buf_count_q) begin
            longatom_active_q <= 1'b0;
            longatom_frame_count_q <= 6'd0;
            longatom_buf_count_q <= 8'd0;
            proc_state_q <= PROC_IDLE;
          end else begin
            proc_state_q <= PROC_REPLAY_WAIT_REG;
          end
        end

        PROC_REPLAY_WAIT_REG: begin
          if (reg_resp_valid) begin
            replay_idx_q <= replay_idx_q + 6'd1;
            proc_state_q <= PROC_REPLAY_DISPATCH;
          end
        end

        PROC_FAIL_ACK: begin
          if (fail_ack_idx_q >= longatom_buf_count_q) begin
            longatom_active_q <= 1'b0;
            longatom_frame_count_q <= 6'd0;
            longatom_buf_count_q <= 8'd0;
            proc_state_q <= PROC_IDLE;
          end else if (manual_resp_valid && !fifo_full) begin
            fail_ack_idx_q <= fail_ack_idx_q + 6'd1;
          end
        end

        default: proc_state_q <= PROC_IDLE;
      endcase

      if (reg_resp_valid || manual_resp_valid) begin
        if (!fifo_full) begin
          if (!IS_ROOT)
            pending_error_q <= OAM_HDRFLD_NONE;
        end
      end

      if (!IS_ROOT && tx_frame_sent) begin
        tx_frame_id_q <= tx_frame_id_q + 32'd1;
        pending_error_q <= OAM_HDRFLD_NONE;
      end
    end
  end

  assign root_cmd_ready_o = IS_ROOT && dlp_tx_indicate_valid;
  assign dlp_tx_oam_valid = IS_ROOT ? tx_root_valid_q : tx_nonroot_valid;
  assign dlp_tx_oam_data  = IS_ROOT ? tx_root_frame_q : tx_nonroot_frame;
  assign dlp_tx_meta      = IS_ROOT ? tx_root_meta_q : '{target_id:5'd1, packet_id:tx_frame_id_q[4:0], nd_en:1'b0, target_id1:5'd0, target_id2:5'd0, target_id3:5'd0};

endmodule

`default_nettype wire
