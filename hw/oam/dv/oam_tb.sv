`default_nettype none

module oam_tb;
  import asa_oam_pkg::*;
  import asa_reg_pkg::*;
  import asa_error_pkg::*;

  logic clk, rst, soft_reset;
  initial begin clk = 1'b0; forever #5 clk = ~clk; end

  // ---------------------------------------------------------------------------
  // Non-root DUT
  // ---------------------------------------------------------------------------
  logic              nr_dlp_tx_indicate_valid, nr_dlp_tx_oam_valid;
  oam_frame_t        nr_dlp_tx_oam_data;
  oam_tx_meta_t      nr_dlp_tx_meta;
  logic              nr_dlp_rx_oam_valid;
  oam_frame_t        nr_dlp_rx_oam_data;
  oam_rx_status_t    nr_dlp_rx_status;
  reg_req_t          nr_reg_req;
  logic              nr_reg_req_valid;
  reg_resp_t         nr_reg_resp;
  logic              nr_reg_resp_valid;
  err_event_t        nr_err_event;
  logic [3:0]        nr_node_state;
  logic              nr_start_tdd;
  start_tdd_params_t nr_start_tdd_params;
  logic              nr_enum_complete;
  logic [4:0]        nr_assigned_node_id;
  logic [47:0]       nr_ptb_clk;
  logic [8:0]        nr_ptb_status;
  logic              nr_ptb_locked;
  logic [47:0]       nr_oam_rx_ptb_clk;
  logic              nr_oam_rx_ptb_valid;
  logic              nr_ls_announce_valid, nr_ls_confirm_valid, nr_ls_deny_valid, nr_ls_sleep_valid;
  ls_announce_params_t nr_ls_announce_params;
  ls_confirm_params_t  nr_ls_confirm_params;
  ls_sleep_params_t    nr_ls_sleep_params;
  logic              nr_ls_resp_valid;
  oam_cad_resp_t     nr_ls_resp_cad;
  logic              nr_keyex_msg_valid;
  logic [4:0]        nr_keyex_msg_src;
  oam_keyex_msg_t    nr_keyex_msg;
  logic              nr_keyex_tx_valid;
  oam_keyex_msg_t    nr_keyex_tx_msg;
  logic [15:0]       nr_link_quality, nr_sqi, nr_fec_stat;
  logic [4:0]        nr_local_node_id;
  logic              nr_link_authenticated;
  logic              nr_read_errors1, nr_read_errors2;
  logic [15:0]       nr_oam_errors1, nr_oam_errors2;
  logic              nr_root_cmd_valid, nr_root_cmd_ready, nr_root_rx_valid;
  logic [4:0]        nr_root_rx_src_node_id;
  oam_decoded_cad_t  nr_root_rx_cad;
  oam_tx_cmd_t       nr_root_cmd;

  oam_top #(.IS_ROOT(1'b0)) u_nonroot (
    .clk(clk), .rst(rst), .soft_reset(soft_reset),
    .dlp_tx_indicate_valid(nr_dlp_tx_indicate_valid),
    .dlp_tx_oam_valid(nr_dlp_tx_oam_valid),
    .dlp_tx_oam_data(nr_dlp_tx_oam_data),
    .dlp_tx_meta(nr_dlp_tx_meta),
    .dlp_rx_oam_valid(nr_dlp_rx_oam_valid),
    .dlp_rx_oam_data(nr_dlp_rx_oam_data),
    .dlp_rx_status(nr_dlp_rx_status),
    .reg_req_o(nr_reg_req),
    .reg_req_valid_o(nr_reg_req_valid),
    .reg_resp_i(nr_reg_resp),
    .reg_resp_valid_i(nr_reg_resp_valid),
    .err_event_o(nr_err_event),
    .node_state_i(nr_node_state),
    .start_tdd_o(nr_start_tdd),
    .start_tdd_params_o(nr_start_tdd_params),
    .enum_complete_o(nr_enum_complete),
    .assigned_node_id_o(nr_assigned_node_id),
    .ptb_clk_i(nr_ptb_clk),
    .ptb_status_i(nr_ptb_status),
    .ptb_locked_i(nr_ptb_locked),
    .oam_rx_ptb_clk_o(nr_oam_rx_ptb_clk),
    .oam_rx_ptb_valid_o(nr_oam_rx_ptb_valid),
    .ls_announce_valid_o(nr_ls_announce_valid),
    .ls_announce_params_o(nr_ls_announce_params),
    .ls_confirm_valid_o(nr_ls_confirm_valid),
    .ls_confirm_params_o(nr_ls_confirm_params),
    .ls_deny_valid_o(nr_ls_deny_valid),
    .ls_sleep_valid_o(nr_ls_sleep_valid),
    .ls_sleep_params_o(nr_ls_sleep_params),
    .ls_resp_valid_i(nr_ls_resp_valid),
    .ls_resp_cad_i(nr_ls_resp_cad),
    .keyex_msg_valid_o(nr_keyex_msg_valid),
    .keyex_msg_src_node_id_o(nr_keyex_msg_src),
    .keyex_msg_o(nr_keyex_msg),
    .keyex_tx_valid_i(nr_keyex_tx_valid),
    .keyex_tx_msg_i(nr_keyex_tx_msg),
    .link_quality_i(nr_link_quality),
    .sqi_i(nr_sqi),
    .fec_stat_i(nr_fec_stat),
    .local_node_id_i(nr_local_node_id),
    .link_authenticated_i(nr_link_authenticated),
    .read_errors1_i(nr_read_errors1),
    .read_errors2_i(nr_read_errors2),
    .oam_errors1_o(nr_oam_errors1),
    .oam_errors2_o(nr_oam_errors2),
    .root_cmd_valid_i(nr_root_cmd_valid),
    .root_cmd_i(nr_root_cmd),
    .root_cmd_ready_o(nr_root_cmd_ready),
    .root_rx_valid_o(nr_root_rx_valid),
    .root_rx_src_node_id_o(nr_root_rx_src_node_id),
    .root_rx_cad_o(nr_root_rx_cad)
  );

  // ---------------------------------------------------------------------------
  // Root DUT
  // ---------------------------------------------------------------------------
  logic              rt_dlp_tx_indicate_valid, rt_dlp_tx_oam_valid;
  oam_frame_t        rt_dlp_tx_oam_data;
  oam_tx_meta_t      rt_dlp_tx_meta;
  logic              rt_dlp_rx_oam_valid;
  oam_frame_t        rt_dlp_rx_oam_data;
  oam_rx_status_t    rt_dlp_rx_status;
  reg_req_t          rt_reg_req;
  logic              rt_reg_req_valid;
  reg_resp_t         rt_reg_resp;
  logic              rt_reg_resp_valid;
  err_event_t        rt_err_event;
  logic [3:0]        rt_node_state;
  logic              rt_start_tdd;
  start_tdd_params_t rt_start_tdd_params;
  logic              rt_enum_complete;
  logic [4:0]        rt_assigned_node_id;
  logic [47:0]       rt_ptb_clk;
  logic [8:0]        rt_ptb_status;
  logic              rt_ptb_locked;
  logic [47:0]       rt_oam_rx_ptb_clk;
  logic              rt_oam_rx_ptb_valid;
  logic              rt_ls_announce_valid, rt_ls_confirm_valid, rt_ls_deny_valid, rt_ls_sleep_valid;
  ls_announce_params_t rt_ls_announce_params;
  ls_confirm_params_t  rt_ls_confirm_params;
  ls_sleep_params_t    rt_ls_sleep_params;
  logic              rt_ls_resp_valid;
  oam_cad_resp_t     rt_ls_resp_cad;
  logic              rt_keyex_msg_valid;
  logic [4:0]        rt_keyex_msg_src;
  oam_keyex_msg_t    rt_keyex_msg;
  logic              rt_keyex_tx_valid;
  oam_keyex_msg_t    rt_keyex_tx_msg;
  logic [15:0]       rt_link_quality, rt_sqi, rt_fec_stat;
  logic [4:0]        rt_local_node_id;
  logic              rt_link_authenticated;
  logic              rt_read_errors1, rt_read_errors2;
  logic [15:0]       rt_oam_errors1, rt_oam_errors2;
  logic              rt_root_cmd_valid, rt_root_cmd_ready, rt_root_rx_valid;
  logic [4:0]        rt_root_rx_src_node_id;
  oam_decoded_cad_t  rt_root_rx_cad;
  oam_tx_cmd_t       rt_root_cmd;

  oam_top #(.IS_ROOT(1'b1)) u_root (
    .clk(clk), .rst(rst), .soft_reset(soft_reset),
    .dlp_tx_indicate_valid(rt_dlp_tx_indicate_valid),
    .dlp_tx_oam_valid(rt_dlp_tx_oam_valid),
    .dlp_tx_oam_data(rt_dlp_tx_oam_data),
    .dlp_tx_meta(rt_dlp_tx_meta),
    .dlp_rx_oam_valid(rt_dlp_rx_oam_valid),
    .dlp_rx_oam_data(rt_dlp_rx_oam_data),
    .dlp_rx_status(rt_dlp_rx_status),
    .reg_req_o(rt_reg_req),
    .reg_req_valid_o(rt_reg_req_valid),
    .reg_resp_i(rt_reg_resp),
    .reg_resp_valid_i(rt_reg_resp_valid),
    .err_event_o(rt_err_event),
    .node_state_i(rt_node_state),
    .start_tdd_o(rt_start_tdd),
    .start_tdd_params_o(rt_start_tdd_params),
    .enum_complete_o(rt_enum_complete),
    .assigned_node_id_o(rt_assigned_node_id),
    .ptb_clk_i(rt_ptb_clk),
    .ptb_status_i(rt_ptb_status),
    .ptb_locked_i(rt_ptb_locked),
    .oam_rx_ptb_clk_o(rt_oam_rx_ptb_clk),
    .oam_rx_ptb_valid_o(rt_oam_rx_ptb_valid),
    .ls_announce_valid_o(rt_ls_announce_valid),
    .ls_announce_params_o(rt_ls_announce_params),
    .ls_confirm_valid_o(rt_ls_confirm_valid),
    .ls_confirm_params_o(rt_ls_confirm_params),
    .ls_deny_valid_o(rt_ls_deny_valid),
    .ls_sleep_valid_o(rt_ls_sleep_valid),
    .ls_sleep_params_o(rt_ls_sleep_params),
    .ls_resp_valid_i(rt_ls_resp_valid),
    .ls_resp_cad_i(rt_ls_resp_cad),
    .keyex_msg_valid_o(rt_keyex_msg_valid),
    .keyex_msg_src_node_id_o(rt_keyex_msg_src),
    .keyex_msg_o(rt_keyex_msg),
    .keyex_tx_valid_i(rt_keyex_tx_valid),
    .keyex_tx_msg_i(rt_keyex_tx_msg),
    .link_quality_i(rt_link_quality),
    .sqi_i(rt_sqi),
    .fec_stat_i(rt_fec_stat),
    .local_node_id_i(rt_local_node_id),
    .link_authenticated_i(rt_link_authenticated),
    .read_errors1_i(rt_read_errors1),
    .read_errors2_i(rt_read_errors2),
    .oam_errors1_o(rt_oam_errors1),
    .oam_errors2_o(rt_oam_errors2),
    .root_cmd_valid_i(rt_root_cmd_valid),
    .root_cmd_i(rt_root_cmd),
    .root_cmd_ready_o(rt_root_cmd_ready),
    .root_rx_valid_o(rt_root_rx_valid),
    .root_rx_src_node_id_o(rt_root_rx_src_node_id),
    .root_rx_cad_o(rt_root_rx_cad)
  );

  int pass_count, fail_count;
  oam_frame_t nr_last_tx_frame, rt_last_tx_frame;
  logic nr_saw_tx, rt_saw_tx;
  logic rt_saw_keyex;
  logic [7:0] rt_keyex_first_id;
  logic nr_saw_ls_announce;
  logic rt_saw_root_rx;
  ls_announce_params_t nr_captured_ls_announce;
  oam_decoded_cad_t rt_captured_root_rx_cad;

  logic [15:0] nr_reg_mem [0:255];
  logic [7:0]  nr_reg_meta [0:255];

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      nr_last_tx_frame <= '0;
      rt_last_tx_frame <= '0;
      nr_saw_tx <= 1'b0;
      rt_saw_tx <= 1'b0;
      rt_saw_keyex <= 1'b0;
      rt_keyex_first_id <= 8'd0;
      nr_saw_ls_announce <= 1'b0;
      rt_saw_root_rx <= 1'b0;
      nr_captured_ls_announce <= '0;
      rt_captured_root_rx_cad <= '0;
    end else begin
      if (nr_dlp_tx_oam_valid) begin
        nr_last_tx_frame <= nr_dlp_tx_oam_data;
        nr_saw_tx <= 1'b1;
      end
      if (rt_dlp_tx_oam_valid) begin
        rt_last_tx_frame <= rt_dlp_tx_oam_data;
        rt_saw_tx <= 1'b1;
      end
      if (rt_keyex_msg_valid) begin
        rt_saw_keyex <= 1'b1;
        rt_keyex_first_id <= rt_keyex_msg.payload[7:0];
      end
      if (nr_ls_announce_valid) begin
        nr_saw_ls_announce <= 1'b1;
        nr_captured_ls_announce <= nr_ls_announce_params;
      end
      if (rt_root_rx_valid) begin
        rt_saw_root_rx <= 1'b1;
        rt_captured_root_rx_cad <= rt_root_rx_cad;
      end
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      nr_reg_resp_valid <= 1'b0;
      nr_reg_resp <= '0;
    end else begin
      nr_reg_resp_valid <= 1'b0;
      nr_reg_resp <= '0;
      if (nr_reg_req_valid) begin
        nr_reg_resp_valid <= 1'b1;
        if (nr_reg_req.addr.addr > 15'd255) begin
          nr_reg_resp.err_addr <= 1'b1;
        end else if (nr_reg_req.wr_en && nr_reg_meta[nr_reg_req.addr.addr[7:0]] == 8'd1) begin
          nr_reg_resp.err_access <= 1'b1;
        end else if (nr_reg_req.rd_en) begin
          nr_reg_resp.rd_data <= nr_reg_mem[nr_reg_req.addr.addr[7:0]];
          nr_reg_resp.ack <= 1'b1;
        end else if (nr_reg_req.wr_en) begin
          nr_reg_mem[nr_reg_req.addr.addr[7:0]] <= nr_reg_req.wr_data;
          nr_reg_resp.ack <= 1'b1;
        end
      end
    end
  end

  task automatic check(input string name, input logic cond);
    if (cond) pass_count++; else begin
      $display("FAIL: %s", name);
      fail_count++;
    end
  endtask

  task automatic init_state();
    begin
      soft_reset = 1'b0;
      nr_dlp_tx_indicate_valid = 1'b0;
      nr_dlp_rx_oam_valid = 1'b0;
      nr_dlp_rx_oam_data = '0;
      nr_dlp_rx_status = '{valid:1'b1, src_node_id:5'd1, phy_err:1'b0, dll_err:1'b0, sec_err:1'b0};
      nr_node_state = 4'd2;
      nr_ptb_clk = 48'h010203040506;
      nr_ptb_status = 9'h101;
      nr_ptb_locked = 1'b1;
      nr_ls_resp_valid = 1'b0;
      nr_ls_resp_cad = '0;
      nr_keyex_tx_valid = 1'b0;
      nr_keyex_tx_msg = '0;
      nr_link_quality = 16'hABCD;
      nr_sqi = 16'h1234;
      nr_fec_stat = 16'h5678;
      nr_local_node_id = 5'd2;
      nr_link_authenticated = 1'b1;
      nr_read_errors1 = 1'b0;
      nr_read_errors2 = 1'b0;
      nr_root_cmd_valid = 1'b0;
      nr_root_cmd = '0;

      rt_dlp_tx_indicate_valid = 1'b0;
      rt_dlp_rx_oam_valid = 1'b0;
      rt_dlp_rx_oam_data = '0;
      rt_dlp_rx_status = '{valid:1'b1, src_node_id:5'd3, phy_err:1'b0, dll_err:1'b0, sec_err:1'b0};
      rt_node_state = 4'd2;
      rt_ptb_clk = 48'h111213141516;
      rt_ptb_status = 9'h055;
      rt_ptb_locked = 1'b1;
      rt_ls_resp_valid = 1'b0;
      rt_ls_resp_cad = '0;
      rt_keyex_tx_valid = 1'b0;
      rt_keyex_tx_msg = '0;
      rt_link_quality = 16'h0A0B;
      rt_sqi = 16'h0C0D;
      rt_fec_stat = 16'h0E0F;
      rt_local_node_id = 5'd1;
      rt_link_authenticated = 1'b1;
      rt_read_errors1 = 1'b0;
      rt_read_errors2 = 1'b0;
      rt_root_cmd_valid = 1'b0;
      rt_root_cmd = '0;

      for (int i = 0; i < 256; i++) begin
        nr_reg_mem[i] = 16'd0;
        nr_reg_meta[i] = 8'd0;
      end
      nr_reg_mem[10] = 16'hCAFE;
    nr_reg_mem[11] = 16'h1234;
    nr_reg_meta[20] = 8'd1;
    nr_saw_ls_announce = 1'b0;
    rt_saw_root_rx = 1'b0;
    nr_captured_ls_announce = '0;
    rt_captured_root_rx_cad = '0;
  end
  endtask

  task automatic build_rx_frame(
    input logic [31:0] frame_id,
    input logic [7:0]  cad_bytes[],
    input logic [47:0] ptb_clk,
    input logic [8:0]  ptb_status,
    output oam_frame_t frame
  );
    frame = '0;
    frame[7:0]   = frame_id[7:0];
    frame[15:8]  = frame_id[15:8];
    frame[23:16] = frame_id[23:16];
    frame[31:24] = frame_id[31:24];
    frame[39:32] = {ptb_status[0], 1'b1, 3'd0, 2'b00, (cad_bytes.size() != 0)};
    frame[47:40] = ptb_status[8:1];
    frame[55:48] = ptb_clk[7:0];
    frame[63:56] = ptb_clk[15:8];
    frame[71:64] = ptb_clk[23:16];
    frame[79:72] = ptb_clk[31:24];
    frame[87:80] = ptb_clk[39:32];
    frame[95:88] = ptb_clk[47:40];
    for (int i = 0; i < cad_bytes.size(); i++) begin
      frame[(24+i)*8 +: 8] = cad_bytes[i];
    end
  endtask

  task automatic send_nr_frame(input oam_frame_t frame, input logic [4:0] src_node_id);
    nr_dlp_rx_status.src_node_id = src_node_id;
    nr_dlp_rx_oam_data = frame;
    nr_dlp_rx_oam_valid = 1'b1;
    @(posedge clk);
    nr_dlp_rx_oam_valid = 1'b0;
    repeat (30) @(posedge clk);
  endtask

  task automatic trigger_nr_tx();
    nr_saw_tx = 1'b0;
    nr_dlp_tx_indicate_valid = 1'b1;
    @(posedge clk);
    nr_dlp_tx_indicate_valid = 1'b0;
    repeat (30) @(posedge clk);
  endtask

  task automatic send_rt_frame(input oam_frame_t frame, input logic [4:0] src_node_id);
    rt_dlp_rx_status.src_node_id = src_node_id;
    rt_dlp_rx_oam_data = frame;
    rt_dlp_rx_oam_valid = 1'b1;
    @(posedge clk);
    rt_dlp_rx_oam_valid = 1'b0;
    repeat (20) @(posedge clk);
  endtask

  initial begin
    pass_count = 0;
    fail_count = 0;
    rst = 1'b1;
    init_state();
    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3) @(posedge clk);

    // 1. Non-root header mapping after a read response.
    begin
      logic [7:0] cad[];
      oam_frame_t frame;
      cad = new[4];
      cad[0] = 8'h01;
      cad[1] = 8'h40;
      cad[2] = 8'h00;
      cad[3] = 8'h0A;
      build_rx_frame(32'd1, cad, 48'h102030405060, 9'h101, frame);
      send_nr_frame(frame, 5'd1);
      trigger_nr_tx();
      check("header byte4 bit0 is CADnext", nr_last_tx_frame[32] == 1'b1);
      check("header byte4 bit7 is PTBstatus[0]", nr_last_tx_frame[39] == nr_ptb_status[0]);
      check("header byte5 holds PTBstatus[8:1]", nr_last_tx_frame[47:40] == nr_ptb_status[8:1]);
    end

    // 2. Read response still returns register data.
    check("read response cmd", nr_last_tx_frame[198:192] == 7'h02);
    check("read response data MSB", nr_last_tx_frame[231:224] == 8'hCA);
    check("read response data LSB", nr_last_tx_frame[239:232] == 8'hFE);

    // 3. Multi-CAD frame: two reads yield CADnext on first response and second return data.
    begin
      logic [7:0] cad[];
      oam_frame_t frame;
      cad = new[8];
      cad[0] = 8'h81;
      cad[1] = 8'h40;
      cad[2] = 8'h00;
      cad[3] = 8'h0A;
      cad[4] = 8'h01;
      cad[5] = 8'h40;
      cad[6] = 8'h00;
      cad[7] = 8'h0B;
      build_rx_frame(32'd2, cad, 48'h0, 9'h0, frame);
      send_nr_frame(frame, 5'd1);
      trigger_nr_tx();
      check("multi-cad first response CADnext=1", nr_last_tx_frame[199] == 1'b1);
      check("multi-cad second response cmd", nr_last_tx_frame[247:240] == 8'h02);
      check("multi-cad second response data MSB", nr_last_tx_frame[279:272] == 8'h12);
      check("multi-cad second response data LSB", nr_last_tx_frame[287:280] == 8'h34);
    end

    // 4. ReadError code must appear in n+5, not n+4.
    begin
      logic [7:0] cad[];
      oam_frame_t frame;
      cad = new[4];
      cad[0] = 8'h01;
      cad[1] = 8'h40;
      cad[2] = 8'h01;
      cad[3] = 8'h2C;
      build_rx_frame(32'd3, cad, 48'h0, 9'h0, frame);
      send_nr_frame(frame, 5'd1);
      trigger_nr_tx();
      check("readerror reserved byte n+4", nr_last_tx_frame[231:224] == 8'h00);
      check("readerror code byte n+5", nr_last_tx_frame[239:232] == 8'h00);
    end

    $display("========================================");
    $display("Results: %0d passed, %0d failed", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) $display("oam_tb: ALL TESTS PASSED");
    else $display("oam_tb: SOME TESTS FAILED");
    $finish;
  end

  initial begin
    #500000;
    $display("ERROR: timeout");
    $finish;
  end

endmodule

`default_nettype wire
