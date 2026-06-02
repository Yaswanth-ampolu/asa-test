`timescale 1ns/1ps
`default_nettype none

module mle_pcs_tb;
  import asa_pcs_pkg::*;
  import asa_mle_pcs_pkg::*;

  logic clk, rst;
  initial begin clk = 0; forever #5 clk = ~clk; end

  int pass_count, fail_count;
  task automatic check(string name, logic cond);
    if (cond) pass_count++;
    else begin
      $display("FAIL: %s", name);
      fail_count++;
    end
  endtask

  logic          is_data;
  logic [7:0]    data_byte;
  oam_slot_kind_e ctrl_kind;
  logic [9:0]    slot;
  logic          dec_is_data;
  logic [7:0]    dec_data_byte;
  oam_slot_kind_e dec_ctrl_kind;
  logic          dec_valid;

  mle_4b5b_codec u_4b5b (
    .is_data_i      (is_data),
    .data_byte_i    (data_byte),
    .ctrl_kind_i    (ctrl_kind),
    .slot_o         (slot),
    .slot_i         (slot),
    .dec_is_data_o  (dec_is_data),
    .dec_data_byte_o(dec_data_byte),
    .dec_ctrl_kind_o(dec_ctrl_kind),
    .dec_valid_o    (dec_valid)
  );

  logic       crc_init, crc_valid;
  logic [7:0] crc_data;
  logic [7:0] crc_cur, crc_final;
  mle_crc8 u_crc8 (
    .clk(clk), .rst(rst), .init_i(crc_init), .valid_i(crc_valid), .data_i(crc_data),
    .crc_o(crc_cur), .crc_final_o(crc_final)
  );

  mle_mode_e                       mle_mode;
  logic [15:0]                     mlecap1, mlecap2, mlecfg;
  logic [1:0]                      ph1g_status;
  logic [2:0]                      txtest;
  logic [MLE_XMII_STREAM_BITS-1:0] xmii_tx, xmii_rx;
  logic [9:0]                      oam_tx, oam_rx, sec_tx, sec_rx;
  logic                            sec_valid_tx, sec_valid_rx;
  logic [MLE_PLB_BITS-1:0]         tx_plb, rx_plb;
  logic [39:0]                     inf_1g;
  speed_grade_e                    sg_map;
  logic                            sg45_scr;
  logic                            fec_mand;
  logic [12:0]                     tdd_cycle;
  logic [7:0]                      dn_plbs, up_plbs;
  logic [17:0]                     qg_dn, qg_up;
  logic                            parity_ok;

  mle_pcs_top u_top (
    .clk(clk), .rst(rst),
    .mle_mode_i(mle_mode),
    .mlecapability1_i(mlecap1),
    .mlecapability2_i(mlecap2),
    .mleconfig_i(mlecfg),
    .ph1g_status_i(ph1g_status),
    .txtest_i(txtest),
    .xmii_blocks_tx_i(xmii_tx),
    .oam_slot_tx_i(oam_tx),
    .secondary_ctrl_tx_i(sec_tx),
    .secondary_valid_tx_i(sec_valid_tx),
    .tx_phy_blockE_o(tx_plb),
    .inf_1g_o(inf_1g),
    .mapped_sg_o(sg_map),
    .use_sg45_scrambler_o(sg45_scr),
    .fec_correction_mandatory_o(fec_mand),
    .tdd_cycle_ptb_o(tdd_cycle),
    .dn_plbs_o(dn_plbs),
    .up_plbs_o(up_plbs),
    .qg_dn_o(qg_dn),
    .qg_up_o(qg_up),
    .rx_phy_blockE_i(rx_plb),
    .xmii_blocks_rx_o(xmii_rx),
    .oam_slot_rx_o(oam_rx),
    .secondary_ctrl_rx_o(sec_rx),
    .secondary_valid_rx_o(sec_valid_rx),
    .rx_parity_ok_o(parity_ok)
  );

  initial begin
    pass_count = 0;
    fail_count = 0;
    rst = 1;
    crc_init = 0;
    crc_valid = 0;
    crc_data = 8'h00;
    is_data = 0;
    data_byte = 8'h00;
    ctrl_kind = OAM_CTL_IDLE;
    mle_mode = MLES_SYM1G0;
    mlecap1 = 16'hE000;
    mlecap2 = 16'hFC00;
    mlecfg = 16'h9800;
    ph1g_status = PH1G_PROCEED;
    txtest = 3'b101;
    xmii_tx = '0;
    for (int i = 0; i < MLE_XMII_STREAM_BITS; i++) xmii_tx[i] = i[0];
    oam_tx = 10'h155;
    sec_tx = 10'h2A5;
    sec_valid_tx = 1'b1;
    rx_plb = '0;

    repeat (3) @(posedge clk);
    rst = 0;
    @(posedge clk);

    // Mode table checks
    check("Mode SG map sym1G0->SG2", mle_mode_to_sg(MLES_SYM1G0) == SG2);
    check("Mode SG map 10G_M->SG4", mle_mode_to_sg(MLES_10G_M) == SG4);
    check("Mode TDD 10G_M=6708", mle_tdd_cycle_ptb(MLES_10G_M) == 6708);
    check("Mode Dn PLBs 10G_G=18", mle_dn_plbs(MLES_10G_G) == 18);
    check("Mode Up PLBs 2G5_M=1", mle_up_plbs(MLES_2G5_M) == 1);
    check("Mode SG45 scrambler sym5G0", mle_mode_uses_sg45_scrambler(MLES_SYM5G0));
    check("Mode FEC mandatory 10G_G", mle_fec_correction_mandatory(MLES_10G_G));

    // 4b/5b data + control
    is_data = 1'b1;
    data_byte = 8'hA5;
    #1;
    check("4b5b data decode valid", dec_valid && dec_is_data);
    check("4b5b data roundtrip", dec_data_byte == 8'hA5);
    is_data = 1'b0;
    ctrl_kind = OAM_CTL_JK;
    #1;
    check("4b5b JK decode valid", dec_valid && !dec_is_data);
    check("4b5b JK decode kind", dec_ctrl_kind == OAM_CTL_JK);

    // CRC8 reset / step determinism
    crc_init = 1;
    @(posedge clk);
    crc_init = 0;
    crc_data = 8'h12; crc_valid = 1; @(posedge clk);
    crc_data = 8'h34; crc_valid = 1; @(posedge clk);
    crc_valid = 0; @(posedge clk);
    check("CRC8 changed from init", crc_cur != 8'hFF);
    crc_init = 1; @(posedge clk); crc_init = 0; @(posedge clk);
    check("CRC8 reset reloads 0xFF", crc_cur == 8'hFF);

    // Phase1G field
    #1;
    check("Phase1G mode bit is MLE", inf_1g[0] == 1'b1);
    check("Phase1G status", inf_1g[31:30] == ph1g_status);
    check("Phase1G txtest", inf_1g[10:8] == txtest);
    check("Phase1G config copied", inf_1g[15:11] == mlecfg[15:11]);

    // PLB roundtrip and parity
    rx_plb = tx_plb;
    #1;
    check("PLB parity passes", parity_ok);
    check("PLB xMII roundtrip", xmii_rx == xmii_tx);
    check("PLB OAM roundtrip", oam_rx == oam_tx);
    check("PLB sec ctrl roundtrip", sec_rx == sec_tx);
    check("PLB sec valid roundtrip", sec_valid_rx == sec_valid_tx);

    rx_plb[0] = ~rx_plb[0];
    #1;
    check("PLB parity fails on corruption", !parity_ok);

    $display("========================================");
    $display("Results: %0d passed, %0d failed", pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0) $display("mle_pcs_tb: ALL TESTS PASSED");
    else                 $display("mle_pcs_tb: SOME TESTS FAILED");
    $finish;
  end

  initial begin
    #500000;
    $display("TIMEOUT");
    $finish;
  end
endmodule

`default_nettype wire
