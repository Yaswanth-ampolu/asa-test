# Micro-Architecture: ASA Node State Machine

## 1. Purpose and Scope

The ASA Node State Machine governs the lifecycle of each ASA node from power-on
through startup, configuration, normal operation, test modes, sleep, and failure.
It is the top-level controller that coordinates PHY startup, OAM configuration,
mapper initialization, PTB clock lock, Light Sleep transitions, and error handling.

This document defines the micro-architecture for RTL/golden-model implementation
based on ASA Technical Specification v2.0 Section 2.4 (Figure 2-3) and supporting
sections.

Scope boundaries:
- IN SCOPE: State encoding, transitions, timing constraints, reset behavior,
  startup interaction, OAM config phase, Normal Mode entry via StartTDD, link loss
  detection, Test Mode, Light Sleep entry/exit, Deep Sleep, Fail state, interrupt
  generation, register interface
- OUT OF SCOPE: PHY PMA/PCS internal training FSMs (4.3.3.1 details), OAM CAD
  processing (see micro-architecture-oam-control-plane.md), Register file
  implementation (see micro-architecture-register-model.md), DLL mapper internals

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 2.4 | ASA Transceiver State Diagram | 27-28 | Figure 2-3: overall state diagram |
| 3.2.6 | ASAnodeState (1.0006) | 35 | State register encoding |
| 3.2.7 | SoftReset (1.0007) | 36 | Reset behavior |
| 3.2.8 | ASAnodeIRQ (1.0008) | 36 | Interrupt flags |
| 3.2.12 | LinkTraining (1.0100) | 39 | COMready, training time |
| 3.2.13 | LinkQuality (1.0101) | 39 | Link loss counter, Fail entry |
| 3.3.28 | LightSleepCapability (2.2250) | 62 | LS support flag |
| 3.3.29 | LightSleepStatus1 (2.2251) | 62 | LS status encoding |
| 4.2.7 | Startup and PMA Training Sequence | 109-115 | Phase1G/SGA/SGB/SGC patterns |
| 4.2.7.5 | PhaseSGA/SGB/SGC info field | 115 | OAMconfigSkip bit |
| 4.3.3.1 | Startup State Diagrams | 122-134 | PHY startup FSM details |
| 4.3.3.1.2 | Constants | 122 | ph1G_RTRY_CNT_LIMIT=255 |
| 4.3.3.1.4 | Timers | 123-124 | All startup timers |
| 4.3.3.1.8 | Diagrams | 126-134 | Figures 4-16 through 4-25 |
| 5.5.3.9 | StartTDD | 181 | Normal mode trigger |
| 5.5.4 | Startup Enumeration Procedure | 183-184 | Enumeration in OAM config |
| 5.8 | Light Sleep | 189-192 | LS negotiation/FSM |
| 5.8.3 | Light Sleep State Diagrams | 191-192 | LS FSM constants/timers |
| 5.9 | DLL Startup, OAM config | 193 | OAM config -> Normal |
| 8.3.3 | MLE State Diagrams | 295 | "See equivalent in section 4" |

Image references (docpdfmd/images/):
- Figure 2-3 (PDF p28): Overall ASA Transceiver state diagram
- Figure 4-16 (PDF p126): Root node Phase1G state diagram
- Figure 4-17 (PDF p127): Leaf node Phase1G state diagram
- Figure 4-18 (PDF p128): Root node PhaseSGA state diagram

---

## 3. State List and Encoding

### 3.1 ASAnodeState Register (1.0006, bits 3:0)

SPEC FACT (Section 3.2.6, p35):

| Value | State Name | Description |
|-------|-----------|-------------|
| 0 | PowerOn / Init | Power supply stable, volatile memory persistent |
| 1 | Startup | Initial startup or returning from Light Sleep |
| 2 | OAM Config | DLL/ASEP configuration via OAM from root |
| 3 | Normal Mode | PHY at speed, streaming, OAM monitoring |
| 4 | Test Mode | TX/RX compliance testing |
| 5 | Light Sleep | PHY disabled, further refined in 2.2251 |
| 6 | Fail | Link loss detected |
| 7 | Deep Sleep | Full power-down mode |
| 8-15 | Reserved | - |

Register properties: RO, Access=O, Privilege=RID.

### 3.2 Light Sleep Sub-States (Register 2.2251, bits 1:0)

SPEC FACT (Section 3.3.29, p62):

| Value | LightSleep status | Description |
|-------|------------------|-------------|
| 0 | Normal Mode | Not in any LS state |
| 1 | Mediation ongoing | Any LS state except LS_dreaming_* |
| 2 | Sleeping | In LS_dreaming_* state |
| 3 | Restarting | Exited LS through point "b" |

---

## 4. ASCII State Diagram

Derived from Figure 2-3 (PDF p28) with transition labels:

```
                   Power Off / Reset Asserted
                            |
                            v
                  +------------------+
                  | PowerOn / Init   |  (state 0)
                  | max 30ms         |
                  +--------+---------+
                           |
              +------------+------------+
              |                         |
              v                         v
    +---------+------+        +---------+------+
    |   Startup      |        |   Test Mode    |
    |   (state 1)    |<---Y---|   (state 4)    |
    +--------+-------+   Z    +--------+-------+
             |                         ^
             | G/H                     | T
             v                         |
    +---------+------+                 |
    |  OAM Config *  |                 |
    |   (state 2)    |-----------------+
    +--------+-------+
             | startTDD()
             v
    +---------+------+       +---------+------+
    |  Normal Mode   |<--b---|  Light Sleep   |
    |   (state 3)    |---a-->|   (state 5)    |
    +--------+-------+       +----------------+
             |
             | Link loss (3+ TDD bursts)
             v
    +---------+------+
    |     Fail       |
    |   (state 6)    |
    +--------+-------+
             |
             v
    +------------------+        +------------------+
    | Restart (back    |        | Disable /        |
    | to Startup)      |        | Deep Sleep       |
    +------------------+        | (state 7)        |
                                +------------------+
```

Transition labels from Figure 2-3:
- Y: PowerOn -> Startup (normal boot)
- Z: Startup/OAMConfig -> Fail (startup failure, retry exhausted)
- G: Startup completion (root, exit Phase SGA/SGB/SGC)
- H: Startup completion (leaf, exit Phase SGA/SGB/SGC)
- T: Test Mode entry (from Startup Phase1G via ph1G_test_req)
- R: Test Mode -> Startup (test complete, restart)
- a: Normal -> Light Sleep (negotiated via OAM LS CADs)
- b: Light Sleep -> Startup (wake-up at PTBalarmclock)
- startTDD(): OAM Config -> Normal Mode

---

## 5. State Transitions

### 5.1 Transition Table

| From | To | Trigger / Condition | Spec Reference |
|------|-----|--------------------|----|
| (any) | PowerOn/Init | Power-on or hard reset asserted | 2.4, p28 |
| PowerOn/Init | Startup | Power stable, init complete (max 30ms in PowerOn) | 2.4, p28 |
| Startup | OAM Config | PHY training complete (transition G/H in 4.3.3.1) | 4.3.3.1.8 |
| Startup | OAM Config (skip) | OAMconfigSkip=1 confirmed by both sides | 4.2.7.5 |
| Startup | Test Mode | ph1G_test_req during Phase1G (transition T) | 4.3.3.1.8, Fig 4-17 |
| Startup | Fail | ph1G_retry_cnt >= ph1G_RTRY_CNT_LIMIT (255) | 4.3.3.1.8, Fig 4-16 |
| OAM Config | Normal Mode | StartTDD CAD received from root | 5.5.3.9, 5.9 |
| OAM Config | Fail | Link loss during config | 2.4 (Z transition) |
| Normal Mode | Light Sleep | LS negotiation complete, timer_LSbedtime triggers | 5.8.3.7 |
| Normal Mode | Fail | Link loss spans 3+ consecutive TDD bursts | 2.4, p28; 3.2.13 |
| Light Sleep | Startup | timer_LSalarmClock triggers (wake-up) | 5.8.3.7 (transition b) |
| Fail | Startup | Restart initiated (implementation-defined) | 2.4 |
| Fail | Deep Sleep | Disable command | 2.4 |
| Test Mode | Startup | Test complete (transition R) | 4.3.3.1.8, Fig 4-24/25 |
| Deep Sleep | PowerOn/Init | Wake-up event (implementation-defined) | 2.4 |

### 5.2 Timing Constraints

SPEC FACT (Section 2.4, p28):
- "The duration from entering the Power-On state to entering Normal Mode state shall
  be 100ms or less."
- "A maximum of up to 30ms can be spent in Power-On state."

Therefore: Startup + OAM Config must complete within 70ms (100ms - 30ms max PowerOn).

---

## 6. Reset Behavior

### 6.1 Hard Reset

Trigger: Power-off/on or external reset assertion.
Effect: ALL registers reset to defaults. State -> PowerOn/Init (0).

### 6.2 SoftReset (Register 1.0007)

SPEC FACT (Section 3.2.7, p36):
- Bit 0: "High active, self-clearing on write"
- "Applies to the entire ASA node"
- "Resets all state machines and status registers"
- "Keeps configuration"

Properties: RW, Access=O, Privilege=RID (root can issue via OAM).

SoftReset behavior:
```
On SoftReset assertion:
  1. State machines reset:
     - Node state -> Startup (1) [re-enter startup sequence]
     - PHY startup FSM -> startup_INIT
     - OAM TX/RX FSMs -> initial state
     - PTB -> unlocked
     - Light Sleep FSM -> idle
  2. Status registers cleared:
     - LinkQuality (1.0101) -> 0
     - OAMerrors1/2 (2.2208/2.2209) -> 0
     - DLLerrors1/2 (2.2210/2.2211) -> 0
     - ASAnodeIRQ (1.0008) -> 0
  3. Configuration registers PRESERVED:
     - SGconfig (1.0002)
     - DLLconfig1/2 (2.0002/2.0003)
     - DLLaddrtable (2.0008-2.0133)
     - DLLmappertable (2.0146-2.2065)
     - All ASEP config registers (4/5.i.xxxx)
     - NodeID (2.0001)
  4. Bit self-clears (reads as 0 after write)
```

IMPLEMENTATION ASSUMPTION: SoftReset triggers re-entry to Startup with preserved
configuration, allowing OAMconfigSkip if config is still valid.

---

## 7. Startup Sequence Interaction with PHY/PMA

### 7.1 Startup Phase Overview (Section 4.3.3.1)

SPEC FACT: "Every ASA node goes through startup Phase1G, PhaseSGA and PhaseSGB.
Speed Grades 4 and 5 also go through startup PhaseSGC."

```
PowerOn/Init
     |
     v
startup_INIT (ph1G_retry_cnt=0, reset PRBS)
     |
     v
Phase1G  ----> [if ph1G_retry_cnt >= 255: FAIL]
     |              |
     |              v (ph1G_test_req)
     |          Test Mode (T)
     |
     | (ph1G_self_good & ph1G_lp_stat=PROCEED)
     v
PhaseSGA (A/B entry)
     |
     | (phSGA_self_good & phSGA_lp_stat=PROCEED)
     v
PhaseSGB (C/D entry)
     |
     | (phSGB_self_good & phSGB_lp_stat=PROCEED)
     v
[If SG4/5: PhaseSGC -> then G/H]
[If SG1/2/3: -> G/H directly]
     |
     v
Transition G (root) or H (leaf) --> OAM Config (state 2)
```

### 7.2 Key Constants (Section 4.3.3.1.2, p122)

| Constant | Value | Description |
|----------|-------|-------------|
| ph1G_RTRY_CNT_LIMIT | 255 | Max Phase1G retries before Fail |

### 7.3 Key Timers (Section 4.3.3.1.4, p123-124)

| Timer | Timeout | Description |
|-------|---------|-------------|
| ph1G_root_rx_timer | 200us | Root waits for leaf Phase1G pattern |
| ph1G_leaf_rx_timer | 200us | Leaf waits for root Phase1G pattern |
| phSGA_root_rx_timer | 312ns | Root waits for leaf PhaseSGA burst |
| phSGA_leaf_rx_timer | 312ns | Leaf waits for root PhaseSGA burst |
| phSGB_root_rx_timer | 312ns | Root waits for leaf PhaseSGB burst |
| phSGB_leaf_rx_timer | 312ns | Leaf waits for root PhaseSGB burst |
| phSGC_root_rx_timer | 312ns | Root waits for leaf PhaseSGC burst |
| phSGC_leaf_rx_timer | 312ns | Leaf waits for root PhaseSGC burst |
| ph1G_leaf_tx_test_timer | 20ms | TX test pattern duration |
| ph1G_root_tx_test_timer | 20ms + test runtime | TX test total |

### 7.4 Startup Status Exchange (Info Field)

Phase1G info field (Section 4.2.7.1.2, Table 4-15):
```
Bits 31:30  Phase1Gstatus:
  00 = TRAINING (still acquiring)
  01 = PREPARED (self ready, waiting for partner)
  10 = PROCEED  (both ready, advance to next phase)
  11 = ERROR    (abort, restart)

Bits 29:16  SGcapability (matches 1.0001[13:0])
Bits 15:11  SGconfig (root sets speed grade for leaf)
Bits 10:8   TXtest (000=no test, else test type 1-5)
Bits 2:1    SecurityPolicy
Bit  0      Physical Layer Mode (0=SerDes, 1=MLE)
```

PhaseSGA/SGB/SGC info field (Section 4.2.7.5, Table 4-20):
```
Bit  18     OAMconfigSkip:
  0 = cannot skip OAM config phase
  1 = request to skip (if config persistently stored)
  Must be confirmed by BOTH sides (root and leaf set to 1)

Bits 17:16  PhaseSGstatus:
  00 = TRAINING
  01 = PREPARED
  10 = PROCEED
  11 = ERROR

Bits 10:8   RXtest (000=no test, else test type)
```

### 7.5 OAMconfigSkip (Section 4.2.7.5, 5.9)

SPEC FACT (Section 5.9, p193): "If the required ASA nodes/devices configurations for
Normal Mode are persistently stored beyond a power cycle (or the device come back from
Light Sleep), Normal Mode can be initiated by setting the appropriate bit in the startup
info field (see 4.2.7.5)."

When OAMconfigSkip=1 is confirmed by both root and leaf:
- Transition G/H goes directly from Startup to Normal Mode
- State 2 (OAM Config) is bypassed
- Used on return from Light Sleep when config is preserved

---

## 8. OAM Config Phase

### 8.1 Entry

After PHY startup completes (transition G/H), the node enters OAM Config (state 2).
SPEC FACT (Section 5.9, p193): "After Physical Layer Startup, communication between
the root nodes DLL/OAM and the non-root nodes DLL/OAM can take place."

### 8.2 Activities During OAM Config

1. **Enumeration** (Section 5.5.4): Root sends Node-Discover, receives Self-Announce
2. **Register configuration** via OAM Read/Write:
   - DLL addressing table (2.0008-2.0133)
   - DLL mapper table (2.0146-2.2065)
   - DLL demux tables (2.2067-2.2146)
   - ASEP stream type registers
   - DLLlinemin/DLLlinemax
3. **PTB clock synchronization**: First OAM frames carry PTBclk for coarse sync
4. **Security KeyEx** (optional): Key installation via KeyExMsg CADs

### 8.3 Transition to Normal Mode

SPEC FACT (Section 5.9, p193): "The transition to Normal Mode is initiated by the
StartTDD CAD (see 5.5.3.9)."

StartTDD provides:
- PTBtime[47:0]: absolute time to start normal mode
- DLLlinemin[15:0]: mapper start pointer
- DLLlinemax[15:0]: mapper end pointer

On receipt:
1. Store PTBtime, DLLlinemin, DLLlinemax
2. Wait until the local/current PTB clock reaches PTBtime
3. At PTBtime: Mapper Initialization (5.2.3.2) executes
4. Root starts resync header of first data burst
5. Leaf waits one IBG into quiet gap
6. ASAnodeState transitions to 3 (Normal Mode)

---

## 9. Link Loss and Fail State

### 9.1 Fail State Entry

SPEC FACT (Section 2.4, p28): "Fail State is entered when Link Loss spans 3 consecutive
TDD bursts or more (see also 3.2.13)."

SPEC FACT (Section 3.2.13, p39, LinkQuality register):
- Bits 15:10: "Link Losses - Counts the number of entirely lost TDD burst (or
  consecutive bursts) since completion of last startup, resets to 0 on Power-On state,
  saturates to 0x3F"

### 9.2 Link Loss Detection Logic

```
On each TDD cycle:
  if (no valid burst received):
    consecutive_loss_count++
  else:
    consecutive_loss_count = 0
    
  if (consecutive_loss_count >= 3):
    ASAnodeState = 6 (Fail)
    LinkQuality[15:10]++ (saturate at 0x3F)
    COMready (1.0100 bit 10) = 0
    ASAnodeIRQ.LocalPMA/PMD/PCS = 1
```

### 9.3 Fail State Behavior

- PHY transmitter disabled
- OAM communication lost (no upstream/downstream bursts)
- Recovery: either restart (back to Startup) or enter Deep Sleep/Disable
- COMready flag cleared (Section 3.2.12)

---

## 10. Test Mode

### 10.1 Entry (from Startup Phase1G)

SPEC FACT (Figure 4-16/4-17, p126-127): Test Mode is entered via transition "T"
when ph1G_test_req is asserted during Phase1G.

Root node: sends TXtest field in Phase1G info (bits 10:8 != 000)
Leaf node: detects ph1G_test_req, transitions to Test Mode

TX test types (Table 4-15):
- 001: Linearity test
- 010: Jitter test
- 011: Droop test
- 100: PSD test
- 101: BER test

RX test types (Table 4-20, PhaseSGA info bits 10:8):
- 110: Noise immunity test
- 111: BER test

### 10.2 Test Mode FSMs (Figures 4-24, 4-25, p134)

**TX Test (leaf, Figure 4-24):**
```
TXtest_INIT -> load test pattern
WAIT_TXtest_1 -> start ph1G_leaf_tx_test_timer (20ms)
TXtest_run_1 -> run defined pattern for defined time
-> transition Z (back to startup_INIT)
```

**RX Test (leaf, Figure 4-25):**
```
WAIT_RXtest_1 -> start phSGA_leaf_rx_test_timer1
RXtest_run_1 -> run BER counter for defined time
WAIT_RXtest_2 -> start phSGA_leaf_rx_test_timer2
RXtest_reply_1 -> Send 1G pattern with info field of results
-> transition Z (back to startup_INIT)
```

### 10.3 Exit

Test Mode always exits back through transition Z (-> Startup) then R path.
ASAnodeState returns to 1 (Startup) after test completion.

---

## 11. Light Sleep Entry/Exit

### 11.1 Entry (Normal Mode -> Light Sleep)

Trigger: LS negotiation complete via OAM CADs (LSannounce, LSconfirm, LSsleep).
SPEC FACT (Section 5.8.3.7): timer_LSbedtime triggers -> transition "a" to Light Sleep.

Sequence:
1. LSannounce exchanged (either side initiates)
2. LSconfirm / LSdeny responses collected
3. Root sends LSsleep with PTBalarmclock and restart parameters
4. Both sides set timer_LSbedtime
5. At bedtime: PHY disabled, ASAnodeState = 5 (Light Sleep)
6. timer_LSalarmClock set for wake-up

### 11.2 During Light Sleep

- PHY transmitter and receiver disabled (power saved)
- PTB continues running from local oscillator (with drift)
- Registers preserved (config intact)
- LightSleepStatus1 (2.2251) bits 1:0 = 2 ("sleeping")

### 11.3 Exit (Light Sleep -> Startup)

SPEC FACT (Section 5.8.2, p191): "Light Sleep reuses the normal Startup sequence,
which is entered at the negotiated point in time."

Sequence:
1. timer_LSalarmClock triggers (transition "b")
2. ASAnodeState = 1 (Startup)
3. PHY startup re-executes (Phase1G -> PhaseSGA -> PhaseSGB [-> PhaseSGC])
4. OAMconfigSkip=1 used because config is preserved
5. Transition directly to Normal Mode (state 3)

### 11.4 Timing Constants (Section 5.8.3.1, p191)

| Constant | Value | Description |
|----------|-------|-------------|
| ph1G_TIME | 820 PTB tics | Nominal Phase1G cycle duration |
| phSGx_TIME | 6844 PTB tics | Nominal PhaseSGA/B/C cycle duration |

---

## 12. Deep Sleep

### 12.1 Spec Coverage

SPEC FACT: Deep Sleep is state 7 in ASAnodeState (3.2.6). Figure 2-3 shows it as
"Disable / Deep Sleep" reachable from Fail state.

The spec provides minimal detail on Deep Sleep behavior beyond:
- It is a separate state from Light Sleep
- Entry from Fail or via explicit disable
- Exit returns to PowerOn/Init

IMPLEMENTATION ASSUMPTION: Deep Sleep implies full power-down of analog/PHY circuits.
Wake-up mechanism is implementation-defined (e.g., pin assertion, timer, power cycle).

---

## 13. Interrupt Generation (ASAnodeIRQ)

### 13.1 Register Layout (1.0008, Section 3.2.8, p36)

SPEC FACT:
```
Bit   Name                  Source          Type  Access  Privilege
13    ASD flag              Detected locally  SC    O       RID
12    ASE flag              Detected locally  SC    O       RID
11    OAM flag              Detected locally  SC    O       RID
10    DLL Receive flag      Detected locally  SC    O       RID
9     DLL Transmit flag     Detected locally  SC    O       RID
8     PTB flag              Detected locally  SC    O       RID
7     Security flag         Detected locally  SC    O       RID
6:2   Remote nodeID         Via OAM           RO    O       RID
1     Remote PMA/PMD/PCS    Received via OAM  SC    O       RID
0     Local PMA/PMD/PCS     Detected locally  SC    O       RID
```

### 13.2 IRQ Sources per State Transition

| State Change | IRQ Flag Set |
|-------------|--------------|
| Normal -> Fail (link loss) | Local PMA/PMD/PCS (bit 0) |
| OAM header error | OAM flag (bit 11) |
| DLL header decode error | DLL Receive flag (bit 10) |
| DLL transmit error | DLL Transmit flag (bit 9) |
| PTB unlock | PTB flag (bit 8) |
| Security dropped container | Security flag (bit 7) |
| Remote node reports PHY error | Remote PMA/PMD/PCS (bit 1) |

### 13.3 IRQ Propagation

SPEC FACT: "ASA defined error conditions in the different parts shall also lead to
the issuing of a flag here." The IRQ register is read via OAM by root (RID privilege).

The Remote nodeID field (bits 6:2) stores the nodeID of a remote node reporting an
error through OAM, allowing the root to identify which node raised the interrupt.

---

## 14. Interfaces

### 14.1 Interface to Register Model

| Signal | Direction | Description |
|--------|-----------|-------------|
| node_state[3:0] | NSM->Reg | Written to 1.0006[3:0] |
| soft_reset_wr | Reg->NSM | SoftReset write pulse (1.0007 bit 0) |
| irq_flags[13:0] | NSM->Reg | Written to 1.0008 |
| com_ready | NSM->Reg | Written to 1.0100 bit 10 |

### 14.2 Interface to OAM Control Plane

| Signal | Direction | Description |
|--------|-----------|-------------|
| start_tdd(ptb_time, linemin, linemax) | OAM->NSM | StartTDD CAD received |
| enum_complete(node_id) | OAM->NSM | StartEnum assigned nodeID |
| oam_config_active | NSM->OAM | Node is in OAM Config state |
| ls_cad_event | OAM->NSM | Light Sleep CAD decoded |

### 14.3 Interface to PTB Clock Service

| Signal | Direction | Description |
|--------|-----------|-------------|
| ptb_locked | PTB->NSM | PTB clock is locked |
| ptb_clk[47:0] | PTB->NSM | Current PTB value (for LS timers and StartTDD compare) |
| ptb_timer_trigger | PTB->NSM | Timer expired (bedtime/alarmclock) |

### 14.4 Interface to PHY/PCS/PMA Startup Engine

| Signal | Direction | Description |
|--------|-----------|-------------|
| phy_startup_complete | PHY->NSM | Transition G/H reached |
| phy_startup_fail | PHY->NSM | Retry limit or ERROR |
| phy_test_mode_req | PHY->NSM | Test mode requested (T) |
| phy_test_complete | PHY->NSM | Test done, return to startup (R) |
| phy_link_loss | PHY->NSM | 3+ consecutive TDD bursts lost |
| phy_disable | NSM->PHY | Disable TX/RX (for LS/Deep Sleep) |
| phy_enable | NSM->PHY | Re-enable TX/RX (wake from LS) |
| oam_config_skip | PHY->NSM | Both sides confirmed OAMconfigSkip |

### 14.5 Interface to DLL Mapper/Demux

| Signal | Direction | Description |
|--------|-----------|-------------|
| mapper_init(linemin, linemax) | NSM->DLL | Trigger mapper initialization when PTBtime is reached |
| mapper_ptb_start[47:0] | NSM->DLL | PTB time to start mapper |

### 14.6 Interface to Light Sleep Controller

| Signal | Direction | Description |
|--------|-----------|-------------|
| ls_enter | LS->NSM | Light Sleep bedtime reached |
| ls_wake | LS->NSM | Alarm clock triggered |
| ls_capable | LS->NSM | LightSleepCapability (2.2250) |

### 14.7 Interface to Security (if present)

| Signal | Direction | Description |
|--------|-----------|-------------|
| sec_irq | Sec->NSM | Security error (dropped container) |
| sec_policy[1:0] | Sec->NSM | Active security policy for Phase1G info |

---

## 15. Suggested RTL Module Boundaries

```
+================================================================+
|                   node_state_machine_top                         |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | power_on_init_ctrl  |    | startup_supervisor   |             |
|  |                     |    |                     |             |
|  | 30ms max timer      |    | Monitors PHY FSM    |             |
|  | Init sequence       |    | G/H/Z/T transitions |             |
|  | Config load check   |    | Retry count check   |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | oam_config_ctrl     |    | normal_mode_ctrl    |             |
|  |                     |    |                     |             |
|  | Wait for StartTDD   |    | Link loss monitor   |             |
|  | PTBtime comparison  |    | 3-burst counter     |             |
|  | Mapper init trigger |    | IRQ generation      |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | light_sleep_intf    |    | fail_handler        |             |
|  |                     |    |                     |             |
|  | Bedtime timer       |    | Disable PHY         |             |
|  | Alarmclock timer    |    | Recovery decision   |             |
|  | State 5 management  |    | Deep Sleep entry    |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | test_mode_ctrl      |    | irq_aggregator      |             |
|  |                     |    |                     |             |
|  | TX/RX test entry    |    | Collect flags from  |             |
|  | Timer monitoring    |    | all subsystems      |             |
|  | Result reporting    |    | Write to 1.0008     |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+                                        |
|  | state_register      |                                        |
|  |                     |                                        |
|  | ASAnodeState[3:0]   |                                        |
|  | Read-only output    |                                        |
|  | Drives OAM header   |                                        |
|  +---------------------+                                        |
+================================================================+
```

---

## 16. MLE Considerations

SPEC FACT (Section 8.3.3, p295): "See equivalent subsection in section 4. Also see
section 8.1.2."

The MLE physical layer reuses the same startup state machines (Phase1G, PhaseSGA,
PhaseSGB, PhaseSGC) as Gen2020. The node state machine is identical regardless of
whether Gen2020 or MLE is used. The difference is in PCS encoding/scrambling, not
in state machine structure.

---

## 17. Implementation Notes

### 17.1 100ms Boot Requirement

The 100ms requirement (PowerOn to Normal) is tight. Breakdown:
- PowerOn/Init: up to 30ms (register load, PLL lock)
- Startup Phase1G: depends on retry count. Each Phase1G cycle ~820 PTB tics (3.3us).
  At 200us timeout per retry, worst case 255 retries = 51ms (exceeds budget).
  INFORMATIVE: In practice, successful link establishment occurs within a few retries.
- PhaseSGA/SGB/SGC: nominally a few hundred us each
- OAM Config: depends on topology depth and register count

### 17.2 State Persistence Across Light Sleep

When entering Light Sleep:
- Mapper table preserved
- Addressing table preserved
- ASEP config preserved
- NodeID preserved
- PTBclk continues (with drift from local oscillator)

This enables OAMconfigSkip on wake-up, avoiding full re-enumeration.

---

## 18. Missing / Needs Verification

1. **Deep Sleep entry conditions**: The spec only shows Deep Sleep as "Disable" from
   Figure 2-3. The exact trigger mechanism (register write? pin? OAM command?) is
   not specified. VERIFY if any other section defines Deep Sleep entry.

2. **Fail -> Startup recovery trigger**: Figure 2-3 shows an arrow from Fail back to
   the top but does not specify what triggers recovery. It may be automatic after a
   delay, or require external intervention. VERIFY against implementation notes.

3. **100ms timing budget validation**: The spec states 100ms max from PowerOn to Normal
   but also allows 255 Phase1G retries at 200us each. If all retries exhaust, the
   node enters Fail, not Normal, so the 100ms requirement applies only to the
   successful path. VERIFY this interpretation.

4. **State transitions visible on OAM header**: The OAM header contains
   LinkHealthStatus which includes LinkQuality. Need to verify whether a state
   transition itself triggers any immediate OAM notification beyond the IRQ register.

5. **Multiple link loss in OAM Config**: Figure 2-3 transition Z applies from both
   Startup and OAM Config to Fail. The "3 consecutive TDD bursts" rule from Section
   2.4 is stated for Normal Mode. Current RTL applies the same 3-burst threshold
   during OAM Config. Keep this as an explicit implementation assumption unless
   tighter PDF evidence is found for an immediate-fail rule during config.

6. **COMready flag behavior**: Register 3.2.12 (LinkTraining) bit 10 says "goes high
   after startup, goes low during normal operation in the event of a link loss."
   VERIFY whether COMready is cleared immediately on entering Fail or only after
   the link loss counter threshold.

7. **Test Mode from OAM Config**: Figure 2-3 does not show a direct path from OAM Config
   to Test Mode. Test Mode entry appears to be only from Startup (via Phase1G).
   VERIFY that Test Mode cannot be entered from Normal/OAM Config via register write.
