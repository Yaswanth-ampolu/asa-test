`default_nettype none

package asa_node_pkg;

  // ASAnodeState register (1.0006) bits 3:0
  // Spec Section 3.2.6, p35
  typedef enum logic [3:0] {
    ASA_STATE_POWER_ON_INIT = 4'd0,
    ASA_STATE_STARTUP       = 4'd1,
    ASA_STATE_OAM_CONFIG    = 4'd2,
    ASA_STATE_NORMAL        = 4'd3,
    ASA_STATE_TEST          = 4'd4,
    ASA_STATE_LIGHT_SLEEP   = 4'd5,
    ASA_STATE_FAIL          = 4'd6,
    ASA_STATE_DEEP_SLEEP    = 4'd7
  } asa_node_state_e;

  // LightSleepStatus1 register (2.2251) bits 1:0
  // Spec Section 3.3.29, p62
  typedef enum logic [1:0] {
    ASA_LS_STATUS_NORMAL     = 2'd0,
    ASA_LS_STATUS_MEDIATING  = 2'd1,
    ASA_LS_STATUS_SLEEPING   = 2'd2,
    ASA_LS_STATUS_RESTARTING = 2'd3
  } asa_light_sleep_status_e;

  // Spec Section 2.4, p28: "Link Loss spans 3 consecutive TDD bursts"
  localparam int unsigned ASA_LINK_LOSS_FAIL_THRESHOLD = 3;

  // LinkQuality register (1.0101) bits 15:10 saturation
  // Spec Section 3.2.13: "saturates to 0x3F"
  localparam int unsigned ASA_LINK_LOSS_SAT = 63;

  // ASAnodeIRQ bit positions (1.0008)
  // Spec Section 3.2.8, p36
  localparam int unsigned ASA_IRQ_LOCAL_PHY_BIT  = 0;
  localparam int unsigned ASA_IRQ_REMOTE_PHY_BIT = 1;
  localparam int unsigned ASA_IRQ_SECURITY_BIT   = 7;
  localparam int unsigned ASA_IRQ_PTB_BIT        = 8;
  localparam int unsigned ASA_IRQ_DLL_TX_BIT     = 9;
  localparam int unsigned ASA_IRQ_DLL_RX_BIT     = 10;
  localparam int unsigned ASA_IRQ_OAM_BIT        = 11;
  localparam int unsigned ASA_IRQ_ASE_BIT        = 12;
  localparam int unsigned ASA_IRQ_ASD_BIT        = 13;

endpackage

`default_nettype wire
