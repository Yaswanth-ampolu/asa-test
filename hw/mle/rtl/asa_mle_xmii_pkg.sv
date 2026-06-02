`default_nettype none

package asa_mle_xmii_pkg;
  import asa_mle_pcs_pkg::*;

  typedef enum logic [1:0] {
    XMII_MII   = 2'd0,
    XMII_GMII  = 2'd1,
    XMII_XGMII = 2'd2
  } xmii_type_e;

  localparam logic [7:0] XGMII_CTRL_IDLE = 8'h07;
  localparam logic [7:0] XGMII_SKIP_CODE = 8'h1C;
  localparam logic [7:0] XGMII_SKIP_BT   = 8'h1E;

  function automatic logic [64:0] make_data_block(input logic [63:0] data64);
    logic [64:0] blk;
    blk = '0;
    blk[0] = 1'b0;
    for (int i = 0; i < 8; i++) blk[1 + 8*i +: 8] = data64[8*i +: 8];
    return blk;
  endfunction

  // Simplified Clause-49-compatible subset for this repo:
  // sync=1 and eight control bytes stored directly in the payload field.
  function automatic logic [64:0] make_control_block(input logic [63:0] ctrl64);
    logic [64:0] blk;
    blk = '0;
    blk[0] = 1'b1;
    for (int i = 0; i < 8; i++) blk[1 + 8*i +: 8] = ctrl64[8*i +: 8];
    return blk;
  endfunction

  function automatic logic is_skip_block(input logic [64:0] blk);
    logic all_skip;
    all_skip = blk[0];
    for (int i = 0; i < 8; i++) all_skip &= (blk[1 + 8*i +: 8] == XGMII_SKIP_CODE);
    return all_skip;
  endfunction

  function automatic logic [64:0] make_skip_block();
    logic [63:0] ctrl64;
    ctrl64 = {8{XGMII_SKIP_CODE}};
    return make_control_block(ctrl64);
  endfunction

endpackage

`default_nettype wire
