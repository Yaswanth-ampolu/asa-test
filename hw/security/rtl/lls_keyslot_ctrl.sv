`timescale 1ns/1ps
`default_nettype none

// LLS Key Slot Controller
// Spec: Section 6.3.3.1 (DeviceInternal.install_key), Section 6.3.4.1/6.3.4.2
//
// Manages two key slots for seamless key rotation.
// - install_key: sets up slot (LK, Salt, TX counter=1, RX counter=0) → READY
// - TX side selects active slot, increments TX counter
// - RX side: on valid ICV from other slot → switch active, deactivate old
// - Counter overflow thresholds trigger KeyEx notification outputs

module lls_keyslot_ctrl
  import asa_lls_pkg::*;
(
  input  logic              clk,
  input  logic              rst,
  input  logic              soft_reset_i,  // Clears all key state (power cycle implied)

  // Key installation (DeviceInternal.install_key per 6.3.3.1)
  // SPEC: callable ONLY by KeyEx entity
  input  logic              install_key_valid_i,
  input  logic              install_slot_i,          // 0=slot0, 1=slot1
  input  logic [127:0]      install_key_i,           // 128-bit Link Key
  input  logic [29:0]       install_salt_i,          // 30-bit Salt (Table 6-1)

  // TX slot access
  input  logic              tx_use_i,       // Pulse when TX uses a slot (for counter)
  output logic              tx_slot_o,      // Currently active TX slot
  output logic [127:0]      tx_key_o,
  output logic [29:0]       tx_salt_o,
  output logic [63:0]       tx_ctr_o,       // Next TX AEAD Invocation Counter
  output logic              tx_slot_ready_o,// Active slot is ready/active

  // RX slot access (primary queried slot)
  input  logic              rx_slot_i,      // Slot from KeySwitch header bit
  output logic [127:0]      rx_key_o,
  output logic [29:0]       rx_salt_o,
  output logic [63:0]       rx_last_ctr_o,  // Last RX AEAD Invocation Counter
  output logic              rx_slot_ready_o,// Queried slot is ready/active

  // RX OTHER slot access (for rotation detection — always the other slot)
  output logic [127:0]      rx_other_key_o,
  output logic [29:0]       rx_other_salt_o,
  output logic [63:0]       rx_other_last_ctr_o,
  output logic              rx_other_slot_ready_o,

  // RX counter update (Section 6.3.4.1: update after valid ICV)
  input  logic              rx_ctr_update_i,
  input  logic              rx_ctr_slot_i,
  input  logic [63:0]       rx_ctr_new_i,

  // RX key rotation trigger (valid ICV from OTHER slot → switch active slot)
  input  logic              rx_key_switch_trigger_i, // Valid ICV from other slot
  input  logic              rx_switch_new_slot_i,    // Which slot to make active

  // KeyEx notification outputs
  output logic              keyex_report_10pct_o,   // TX margin < 10%
  output logic              keyex_report_5pct_o,    // TX margin < 5%
  output logic              keyex_overflow_o,        // TX counter at max

  // Status
  output logic              any_lk_installed_o  // At least one LK in READY/ACTIVE state
);

  // =========================================================================
  // Key slot storage
  // =========================================================================
  logic [127:0]       key_q    [0:1];
  logic [29:0]        salt_q   [0:1];
  logic [63:0]        tx_ctr_q [0:1];   // Next TX AEAD Invocation Counter
  logic [63:0]        rx_ctr_q [0:1];   // Last RX AEAD Invocation Counter
  lls_slot_state_e    state_q  [0:1];

  // Active slot selection (TX and RX can differ briefly during rotation)
  logic active_tx_slot_q;

  // =========================================================================
  // Reset and install
  // =========================================================================
  always_ff @(posedge clk or posedge rst) begin
    if (rst || soft_reset_i) begin
      for (int i = 0; i < 2; i++) begin
        key_q[i]    <= 128'd0;
        salt_q[i]   <= 30'd0;
        tx_ctr_q[i] <= 64'd0;
        rx_ctr_q[i] <= 64'd0;
        state_q[i]  <= SLOT_EMPTY;
      end
      active_tx_slot_q <= 1'b0;
    end else begin
      // Key installation (Section 6.3.3.1)
      if (install_key_valid_i) begin
        key_q[install_slot_i]    <= install_key_i;
        salt_q[install_slot_i]   <= install_salt_i;
        tx_ctr_q[install_slot_i] <= 64'd1;  // starts at 1 per spec
        rx_ctr_q[install_slot_i] <= 64'd0;  // starts at 0 per spec
        state_q[install_slot_i]  <= SLOT_READY;
      end

      // TX counter increment after each protected container
      if (tx_use_i && tx_slot_ready_o) begin
        if (tx_ctr_q[active_tx_slot_q] == CTR_MAX) begin
          // Counter at max — deactivate this slot (overflow)
          state_q[active_tx_slot_q] <= SLOT_DEACTIVATED;
        end else begin
          tx_ctr_q[active_tx_slot_q] <= tx_ctr_q[active_tx_slot_q] + 64'd1;
          // Transition READY → ACTIVE on first use
          if (state_q[active_tx_slot_q] == SLOT_READY)
            state_q[active_tx_slot_q] <= SLOT_ACTIVE;
        end
      end

      // RX counter update after valid ICV
      if (rx_ctr_update_i) begin
        rx_ctr_q[rx_ctr_slot_i] <= rx_ctr_new_i;
        if (state_q[rx_ctr_slot_i] == SLOT_READY)
          state_q[rx_ctr_slot_i] <= SLOT_ACTIVE;
      end

      // RX key rotation: valid ICV from OTHER slot → switch active, deactivate old
      // (Section 6.3.4.1, PDF p201)
      if (rx_key_switch_trigger_i) begin
        state_q[rx_switch_new_slot_i]  <= SLOT_ACTIVE;
        state_q[~rx_switch_new_slot_i] <= SLOT_DEACTIVATED;
        active_tx_slot_q               <= rx_switch_new_slot_i;
      end
    end
  end

  // =========================================================================
  // Outputs
  // =========================================================================
  assign tx_slot_o        = active_tx_slot_q;
  assign tx_key_o         = key_q[active_tx_slot_q];
  assign tx_salt_o        = salt_q[active_tx_slot_q];
  assign tx_ctr_o         = tx_ctr_q[active_tx_slot_q];
  assign tx_slot_ready_o  = (state_q[active_tx_slot_q] == SLOT_READY) ||
                             (state_q[active_tx_slot_q] == SLOT_ACTIVE);

  assign rx_key_o         = key_q[rx_slot_i];
  assign rx_salt_o        = salt_q[rx_slot_i];
  assign rx_last_ctr_o    = rx_ctr_q[rx_slot_i];
  assign rx_slot_ready_o  = (state_q[rx_slot_i] == SLOT_READY) ||
                             (state_q[rx_slot_i] == SLOT_ACTIVE);

  // Other slot (always the inverse of queried slot)
  assign rx_other_key_o         = key_q[~rx_slot_i];
  assign rx_other_salt_o        = salt_q[~rx_slot_i];
  assign rx_other_last_ctr_o    = rx_ctr_q[~rx_slot_i];
  assign rx_other_slot_ready_o  = (state_q[~rx_slot_i] == SLOT_READY) ||
                                   (state_q[~rx_slot_i] == SLOT_ACTIVE);

  assign any_lk_installed_o = (state_q[0] != SLOT_EMPTY) || (state_q[1] != SLOT_EMPTY);

  // Counter overflow notification (PDF p202, Section 6.3.4.2)
  logic [63:0] tx_remaining;
  assign tx_remaining = CTR_MAX - tx_ctr_q[active_tx_slot_q];
  assign keyex_report_10pct_o = tx_slot_ready_o && (tx_remaining < CTR_THRESHOLD_10PCT);
  assign keyex_report_5pct_o  = tx_slot_ready_o && (tx_remaining < CTR_THRESHOLD_5PCT);
  assign keyex_overflow_o     = tx_slot_ready_o && (tx_ctr_q[active_tx_slot_q] == CTR_MAX);

endmodule

`default_nettype wire
