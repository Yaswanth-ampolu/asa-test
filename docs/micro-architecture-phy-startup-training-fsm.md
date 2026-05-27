# Micro-Architecture: PHY Startup and PMA Training FSM

## 1. Purpose and Scope

The PHY Startup and PMA Training FSM controls the lifecycle of an ASA node from
Power-On through physical layer training to Normal Mode readiness. It orchestrates
Phase1G (link detection, speed negotiation, polarity check) followed by
PhaseSGA/SGB/SGC (speed-grade training, equalizer convergence) before transitioning
to OAM Config or Normal Mode.

This document defines the micro-architecture for RTL/golden-model implementation.

Scope:
- IN SCOPE: Root/leaf startup FSMs, Phase1G/SGA/SGB/SGC control, info field
  encoding/decoding, CRC32 for info fields, timer/counter management, test mode
  entry/control, PMA reset/disable interaction, transition triggers
- OUT OF SCOPE: PCS digital datapath internals (see micro-architecture-phy-pcs-datapath.md),
  OAM CAD processing, DLL mapper, PTB follower lock FSM, analog PMA circuits

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 2.4 | ASA Transceiver State Diagram | 27-28 | Overall transitions Y/Z/T/G/H |
| 3.2.2 | SGconfig (1.0002) | 32-33 | Speed grade, direction, GroupID |
| 3.2.4 | ConnectivityIdentification (1.0004) | 34 | GroupID mismatch, LP GroupID |
| 3.2.6 | ASAnodeState (1.0006) | 35 | State encoding |
| 3.2.7 | SoftReset (1.0007) | 36 | Reset behavior |
| 3.2.12 | LinkTraining (1.0100) | 39 | COMready, polarity, training time |
| 3.2.18 | DiagnosticsTestCtrl (1.0106) | 44 | Test type/enable |
| 3.2.19 | LinkIdentification (1.0107) | 44 | LinkID for aggregation |
| 3.2.20 | ExtendedLinkTrainingStatus (1.0108) | 44 | Timeouts, RetryCounter |
| 4.2.7 | Startup and PMA Training Sequence | 109 | Figure 4-14 |
| 4.2.7.1 | Startup Phase1G | 109-111 | Phase1G pattern definition |
| 4.2.7.1.1 | Phase1G m_ptb semantics | 110 | ph1G_retry_count in resync |
| 4.2.7.1.2 | Phase1G info field | 111 | Table 4-15, 40-bit field |
| 4.2.7.2 | PhaseSGA | 112-113 | SGA burst definition |
| 4.2.7.3 | PhaseSGB | 114 | SGB burst definition |
| 4.2.7.4 | PhaseSGC | 115 | SGC burst definition |
| 4.2.7.5 | PhaseSGA/SGB/SGC info field | 115 | Table 4-20, 512-bit field |
| 4.3.1 | Interburst Gap | 121 | 104ns nominal |
| 4.3.2 | PMA Reset/Transmit/Receive/Clock | 121-122 | PMA control interface |
| 4.3.3.1 | Startup State Diagrams | 122-134 | FSMs, Figures 4-16 to 4-25 |
| 4.3.3.1.2 | Constants | 122 | ph1G_RTRY_CNT_LIMIT=255 |
| 4.3.3.1.3 | Variables | 122-123 | self_good, lp_stat, test_req |
| 4.3.3.1.4 | Timers | 123-124 | All startup timers |
| 4.3.3.1.5 | Counters | 125 | ph1G_retry_count, phSGABC_count |
| 4.3.3.1.6 | Functions | 125 | start1Gstat, startSGAstat, etc |
| 4.3.3.1.8 | Diagrams | 126-134 | Figures 4-16 through 4-25 |
| 4.4.1 | Test Modes | 135 | Register vs startup-triggered |
| 4.4.1.1 | Transmitter Tests | 135-138 | Linearity/jitter/droop/PSD/BER |
| 4.4.1.2 | Receiver Tests | 139 | Noise immunity, BER |
| 4.4.1.3 | S11 Termination Test | 139 | Register-only activation |
| 5.9 | DLL Startup, OAM Config | 193 | OAMconfigSkip fast path |

### 2.1 Recovered Figure Images

The PDF is the normative source for Figures 4-16 through 4-25. Figures 4-16
through 4-21 were not present in the original `docpdfmd/images` extraction and
were recovered as PDF page renders:

| Figure | Image Reference |
|--------|-----------------|
| 4-16 Root startup Phase1G | `docpdfmd/images/45_Figure_4-16_Root_node_startup_Phase1G_pdf_page.png` |
| 4-17 Leaf startup Phase1G | `docpdfmd/images/46_Figure_4-17_Leaf_node_startup_Phase1G_pdf_page.png` |
| 4-18 Root startup PhaseSGA | `docpdfmd/images/47_Figure_4-18_Root_node_startup_PhaseSGA_pdf_page.png` |
| 4-19 Leaf startup PhaseSGA | `docpdfmd/images/48_Figure_4-19_Leaf_node_startup_PhaseSGA_pdf_page.png` |
| 4-20 Root startup PhaseSGB | `docpdfmd/images/49_Figure_4-20_Root_node_startup_PhaseSGB_pdf_page.png` |
| 4-21 Leaf startup PhaseSGB | `docpdfmd/images/50_Figure_4-21_Leaf_node_startup_PhaseSGB_pdf_page.png` |
| 4-22 Root startup PhaseSGC | `docpdfmd/images/51_Figure_4-22_Root_node_startup_PhaseSGC.png` |
| 4-23 Leaf startup PhaseSGC | `docpdfmd/images/52_Figure_4-23_Leaf_node_startup_PhaseSGC.png` |
| 4-24 Leaf startup transmitter test | `docpdfmd/images/53_Figure_4-24_Leaf_node_startup_transmitter_test.png` |
| 4-25 Leaf startup receiver test | `docpdfmd/images/54_Figure_4-25_Leaf_node_startup_receiver_test.png` |

---

## 3. Startup Phase Summary

SPEC FACT (Section 4.3.3.1): "Every ASA node goes through startup Phase1G, PhaseSGA
and PhaseSGB. Speed Grades 4 and 5 also go through startup PhaseSGC."

```
startup_INIT
     |
     v
+----------+     retry (max 255)     +-------------+
| Phase1G  |<------------------------| FAIL_start1G|---> Z (Fail state)
|          |------------------------->|             |
+----+-----+                          +-------------+
     | ph1G_self_good & lp_stat=PROCEED & !test_req
     |
     v  (transition A for root, B for leaf)
+----------+     timer_done | lp_stat=ERROR    +-------------+
| PhaseSGA |<---------------------------------| FAIL_startSGA|---> Y (retry)
|          |---------------------------------->|              |
+----+-----+                                   +--------------+
     | phSGA_self_good & lp_stat=PROCEED
     v  (transition C for root, D for leaf)
+----------+
| PhaseSGB |  (same structure as SGA)
+----+-----+
     | phSGB_self_good & lp_stat=PROCEED
     v  (transition E for root, F for leaf)
+----------+     (only SG4/5)
| PhaseSGC |
+----+-----+
     | phSGC_self_good & lp_stat=PROCEED
     v
Transition G (root) / H (leaf) --> OAM Config state (or Normal if OAMconfigSkip)
```

---

## 4. Phase1G Info Field (Table 4-15, p111)

SPEC FACT: 40-bit field `inf_1G<39:0>`:

```
Bits   Name             Description
39:32  ParityByte       XOR of bytes: inf[32+k] = inf[k] ^ inf[8+k] ^ inf[16+k] ^ inf[24+k]
31:30  Phase1Gstatus    00=TRAINING, 01=PREPARED, 10=PROCEED, 11=ERROR
29:16  SGcapability     = register 1.0001 bits [13:0]
15:11  SGconfig         Root/far-side: write to 1.0002[4:0] of leaf; '11111'=don't write
                        Non-root/near-side: contains own 1.0002[4:0] (info only)
10:8   TXtest           000=no test; 001=linearity; 010=jitter; 011=droop; 100=PSD; 101=BER
7:3    Reserved         Set to 0
2:1    SecurityPolicy   Setting in 3.4.1 for this power cycle
0      PhysLayerMode    0=ASA Motion Link (SerDes); 1=ASA Motion Link Ethernet (MLE)
```

### 4.1 Phase1G m_ptb Semantics (Section 4.2.7.1.1)

SPEC FACT: During Phase1G, the m_ptb[15:0] field in the resync header carries:
```
Bits 15:12  ph1G_retry_count<3:0>   Lower 4 bits
Bits 11:10  ph1G_groupID<1:0>       MDI group identification
Bits 9:8    ph1G_linkID<1:0>        MDI/link within group
Bits 7:0    ph1G_retry_count<7:0>   Full 8 bits of counter
```

INFORMATIVE: Lower nibble of retry_count padded to avoid stationary patterns.

---

## 5. PhaseSGA/SGB/SGC Info Field (Table 4-20, p115)

SPEC FACT: 512-bit field `inf_SG<511:0>` (60 bytes + 4 bytes CRC):

```
Bits     Name             Description
511:480  CRC32            32-bit CRC over inf_SG<479:0> (polynomial per 4.2.9)
479:43   Reserved         Set to 0
42:19    Info field counter  Consecutive counter of info fields sent (24 bits)
18       OAMconfigSkip    0=cannot skip OAM config; 1=request skip (see 5.9)
17:16    PhaseSGstatus    00=TRAINING, 01=PREPARED, 10=PROCEED, 11=ERROR
15:11    Reserved         Set to 0
10:8     RXtest           000=no test; 110=noise immunity; 111=BER
7:0      Reserved         Set to 0
```

### 5.1 CRC32 Usage

SPEC FACT: CRC32 protects bits 479:0 of the PhaseSGA/SGB/SGC info field. Section
4.2.9 defines the full algorithm:
- Polynomial: `0xF4ACFB13`
- Starting value: `0xFFFFFFFF`
- Appendix/final XOR value: `0xFFFFFFFF`
- Input data: byte-wise reflected
- Result data: reflected

The receiver verifies CRC before trusting the info field content. Image
`32_CRC32_calculation_table.png` gives the published 15-byte check sequence whose
final CRC is `0xB843C1B8`.

---

## 6. Root Node Startup FSM (Figure 4-16, p126)

```
         (Y) -- from Power-On / SoftReset / Light Sleep wake
          |
          v
    +-----------+
    |startup_INIT|
    | ph1G_retry_cnt = 0        |
    | reset PRBS23, PRBS11, PRBS9|
    +-----+-----+
          |
          | ph1G_retry_cnt < 255
          v
    +-----------+                    +-----------+
    |TX_start1G_1|                   |FAIL_start1G_1|
    |             |                  |               |
    | if(self_good):                 | after retry increment:
    |   start1Gstat(PREPARED)        | ph1G_retry_cnt >= 255
    | else:                          |               |
    |   start1Gstat(TRAINING)        +-------+-------+
    +-----+-----+                            |
          |                                  v  --> Z (fail)
          v
    +-----------+
    |WAIT_start1G_2|
    | start ph1G_root_rx_timer|
    +-----+-----+
          |
     +----+--------+-------------------+
     |             |                   |
 timer_done   !test_req &          self_good &
 OR lp=ERROR  (lp=TRAINING|        lp=PROCEED &
     |         lp=PREPARED)        !test_req
     v             |                   |
 RETRY_start1G_1   v                   v
 ph1G_retry_cnt++  (loop to TX_1,      (A) --> PhaseSGA
                    or fail if >=255)
     |
     v (loop back)

  --- Test Mode Branch ---
  ph1G_test_req:
    TX_testTransmitterCmd -> start1Gtestcmd() + start1Gstat(PROCEED) + txDisable()
    WAIT_TXtest_2 -> start ph1G_root_tx_test_timer
    ph1G_root_tx_test_timer_done -> (Y) restart
```

---

## 7. Leaf Node Startup FSM (Figure 4-17, p127)

```
         (Z) -- from Power-On / SoftReset
          |
          v
    +-----------+
    |startup_INIT|  (same as root init)
    +-----+-----+
          |
          | ph1G_retry_cnt < 255
          v
    +-----------+                    +-----------+
    |WAIT_start1G_1|                 |FAIL_start1G_2|
    | start ph1G_leaf_rx_timer|      | ph1G_retry_cnt++|
    +-----+-----+                   +-------+-------+
          |                                 |
     +----+---------+---------+             v --> Z (fail)
     |              |         |
 timer_done    !test_req &    lp=PROCEED &
 OR lp=ERROR   !(lp=ERROR)&  test_req
     |          !(self_good & |
     v           lp=PREPARED) v --> (T) Test Mode
 (retry)           |
                   v
    +-----------+              +-----------+
    |TX_start1G_2|             |TX_start1G_2b|
    | if(self_good):           | start1Gstat(PROCEED)|
    |   start1Gstat(PREPARED)  +-------+-------+
    | else:                            |
    |   start1Gstat(TRAINING)          v --> (B) PhaseSGA
    +-----+-----+
          | (loop back to WAIT)

  --- Conditions for (B) transition ---
  ph1G_all_self_good & ph1G_all_lp_stat=PREPARED & !test_req
```

---

## 8. PhaseSGA/SGB/SGC FSMs (Figures 4-18 to 4-23)

The SGA/SGB/SGC phases follow the same pattern as Phase1G but with these differences:
- Use the 512-bit info field with CRC32 instead of 40-bit Phase1G field
- Timer values: 312ns (vs 200us for Phase1G)
- No retry counter loop (FAIL goes back to startup_INIT via Y transition)
- Counter `phSGABC_count` tracks info fields sent
- SG4/5 only: PhaseSGC adds an additional phase after SGB

### 8.1 Root PhaseSGA (Figure 4-18, p128)

```
    (A) -- from Phase1G
     |
     v
   SGA_INIT
   | if(SGconfig[3]=0): tx_phy_block = tx_blockSGA_Up
   | else if(SGconfig[2:1]=0): tx_phy_block = tx_blockSGA_Dn12
   | else: tx_phy_block = tx_blockSGA_Dn345
   | phSGABC_count = 0
     |
     v
   TX_startSGA_1
   | if(self_good): startSGAstat(PREPARED)
   | else: startSGAstat(TRAINING)
   | phSGABC_count++
     |
     v
   WAIT_startSGA_2 (start phSGA_root_rx_timer)
     |
   +---+---+
   |       |
 timer_done/ERROR    self_good & lp=PROCEED & !test
   |       |
   v       v --> (C) PhaseSGB
 FAIL_startSGA_1 --> (Y) restart
```

### 8.2 Test Mode via SGA (Root, Figure 4-18)

```
  phSGA_test_req & (lp=TRAINING | lp=PREPARED):
    TX_testReceiver -> startSGAtestcmd() + startSGAstat(PROCEED) + txDisable()
    WAIT_RXtest_3 -> start phSGA_root_rx_test_timer
    phSGA_root_rx_test_timer_done -> WAIT_start1G_3
    RXtest_result_1 or RXtest_fail_1 -> (Y) restart
```

### 8.3 Test Mode via SGA (Leaf, Figures 4-19 and 4-25)

```
  phSGA_lp_stat = PREPARED & phSGA_test_req:
    (R) -> WAIT_RXtest_1 -> RXtest_run_1 -> WAIT_RXtest_2 -> RXtest_reply_1
    RXtest_reply_1 sends a Startup Phase1G burst with the RX-test result
    info field described by Table 4-23, then exits through (Z).
```

Leaf SGA must not enter the RX-test path for a test request unless the received
PhaseSGA status is `PREPARED`.

---

## 9. Constants, Timers, and Counters

### 9.1 Constants (Section 4.3.3.1.2)

| Constant | Value | Description |
|----------|-------|-------------|
| ph1G_RTRY_CNT_LIMIT | 255 | Max Phase1G retries before Fail |

### 9.2 Timers (Section 4.3.3.1.4)

| Timer | Timeout | Description |
|-------|---------|-------------|
| ph1G_root_rx_timer | 200us | Root waits for leaf Phase1G |
| ph1G_leaf_rx_timer | 200us | Leaf waits for root Phase1G |
| phSGA_root_rx_timer | 312ns | Root waits for PhaseSGA from leaf |
| phSGA_leaf_rx_timer | 312ns | Leaf waits for PhaseSGA from root |
| phSGB_root_rx_timer | 312ns | Root waits for PhaseSGB from leaf |
| phSGB_leaf_rx_timer | 312ns | Leaf waits for PhaseSGB from root |
| phSGC_root_rx_timer | 312ns | Root waits for PhaseSGC from leaf |
| phSGC_leaf_rx_timer | 312ns | Leaf waits for PhaseSGC from root |
| ph1G_leaf_tx_test_timer | 20ms | TX test pattern duration (leaf) |
| ph1G_root_tx_test_timer | 20ms + runtime | TX test total (root) |
| phSGA_leaf_rx_test_timer1 | 20ms | RX test run duration |
| phSGA_leaf_rx_test_timer2 | 20ms | RX test result wait |
| phSGA_root_rx_test_timer | sum of above + inline | Root RX test total |

### 9.3 Counters (Section 4.3.3.1.5)

| Counter | Description |
|---------|-------------|
| ph1G_retry_count | Retries of Phase1G (root sends, leaf detects) |
| phSGABC_count | Consecutive info fields sent in PhaseSGA/B/C |

### 9.4 Functions (Section 4.3.3.1.6)

| Function | Description |
|----------|-------------|
| start1Gstat() | Set Phase1G status in info field, transmit burst |
| start1Gtestcmd() | Set test command in Phase1G info field, transmit |
| startSGAstat() | Set PhaseSGA status, transmit burst |
| startSGAtestcmd() | Set SGA test command, transmit burst |
| startSGBstat() | Set PhaseSGB status, transmit burst |
| startSGCstat() | Set PhaseSGC status, transmit burst |
| txDisable() | Put transmitter in disable state (4.4.2.7) |

---

## 10. SGconfig and Speed Grade Selection (Section 3.2.2)

SPEC FACT (Table 3-5, register 1.0002):
```
Bits 15:13  Reserved
Bits 12:9   ASA Version (0=1.01, 1=1.1, 2=2.0)
Bits 8:7    Aggregated Links (0-3, for Link Aggregation)
Bits 6:5    MDI GroupID (uint, checked during startup)
Bit  4      Up SG (0=SG1, 1=SG2)
Bit  3      Direction (0=Up TX / Dn RX, 1=Dn TX / Up RX)
Bits 2:0    Dn SG (000=SG1, 001=SG2, 010=SG3, 011=SG4, 100=SG5)
```

Speed grade determines:
- Which FEC encoder is used (RS(108,106) or RS(216,214) or RS(240,214))
- Whether PhaseSGC is required (SG4/5 only)
- PAM2 vs PAM4 symbol mapping
- Burst timing and quiet gap duration

---

## 11. LinkTraining Register (1.0100, Section 3.2.12)

SPEC FACT:
```
Bits 15:11  LPerrors       RO  Number of ERROR states from LP during last startup (sat 0x1F)
Bit  10     COMready       RO  0=communication not possible, 1=ready
                               Goes high after startup; low on link loss during normal mode
Bits 9:8    Polarity       RO  00=not evaluated; 01=normal; 10=inverted; 11=detection failed
Bits 7:0    LinkTrainingTime RO  uint8 in ms from startup_INIT to G/H transition (sat 0xFB)
                               0xFC-0xFE reserved; 0xFF=measurement error
```

---

## 12. ExtendedLinkTrainingStatus (1.0108, Section 3.2.20)

SPEC FACT:
```
Bits 15:13  Reserved
Bits 12:8   Timeouts       RO  Number of timeouts during last startup (sat 0x1F)
Bits 7:0    RetryCounter   RO  = ph1G_retry_cnt of Phase1G state machine
```

---

## 13. DiagnosticsTestCtrl (1.0106, Section 3.2.18)

SPEC FACT (Table 3-24):
```
Bits 15:5   Reserved
Bits 4:1    TestType  RW L RID
              0000 = HarnessDiagnostics
              0001 = TX Linearity Test
              0010 = TX Jitter Test
              0011 = TX Droop Test
              0100 = TX PSD Test
              0101 = TX BER Test
              0110 = RX Noise Immunity Test
              0111 = RX BER Test
              1000 = S11 Termination Test
              1001 = Phase1G Loopback Test
Bit  0      Enable    RW L RID
              Setting active immediately disrupts data communication
              and starts the test/diagnostic mode
```

SPEC FACT (Section 4.4.1): "A test initiated by writing the register is active until
the register value is changed; a test initiated through the startup info field is only
active and non-interactive for a limited time."

SPEC FACT: "The S11 Termination test can only be activated by (locally) writing the
register."

---

## 14. Test Mode Entry and Duration

### 14.1 Startup-Triggered Tests

| Test | TXtest/RXtest code | Duration |
|------|-------------------|----------|
| TX Linearity (PRBS13Q for SG4/5, PRBS9 for SG1/2/3) | TXtest=001 | Pattern x128 repetitions |
| TX Jitter (square wave) | TXtest=010 | 100ms |
| TX Droop (160xS pattern) | TXtest=011 | 10ms |
| TX PSD (normal mode pattern) | TXtest=100 | 500ms |
| TX BER (normal mode pattern) | TXtest=101 | (not specified in extraction) |
| RX Noise Immunity | RXtest=110 | 20ms per phase |
| RX BER | RXtest=111 | 20ms per phase |

### 14.2 Test Mode FSMs (Figures 4-24, 4-25)

**TX Test (leaf, Figure 4-24):**
```
(T) -> TXtest_INIT (load test pattern) -> WAIT_TXtest_1
    -> start ph1G_leaf_tx_test_timer -> TXtest_run_1
    -> run pattern -> (Z) back to startup_INIT
```

**RX Test (leaf, Figure 4-25):**
```
(R) -> WAIT_RXtest_1 (start timer1) -> RXtest_run_1 (run BER counter)
    -> WAIT_RXtest_2 (start timer2) -> RXtest_reply_1 (send 1G with results)
    -> (Z) back to startup_INIT
```

---

## 15. PMA Control Interface

### 15.1 PMA Reset (Section 4.3.2.1)

SPEC FACT: "Resets all PAM functions and puts PMA transmit into PMA.disable.
PMA reset is triggered in Power-On state."

### 15.2 PMA.disable (Section 4.3.2.2.1)

SPEC FACT: "PMA.disable is controlled by PCS according to startup state, TDD state
or Light Sleep state."

### 15.3 Interburst Gap (Section 4.3.1)

SPEC FACT: "The nominal Interburst Gap, where neither Upstream nor Downstream
transmitter is driving the line, is equal to 104 ns."

### 15.4 Half-Duplex Rule

SPEC FACT (Section 4.3.3.1): "Each node during startup shall not start transmission
of a startup burst while a startup burst from the other side is still being received."

---

## 16. Transition to OAM Config / Normal Mode

### 16.1 Normal Transition (G/H)

After final phase completes (PhaseSGB for SG1/2/3, PhaseSGC for SG4/5):
- Root: transition G
- Leaf: transition H
- ASAnodeState transitions to 2 (OAM Config)
- COMready (1.0100 bit 10) goes high
- LinkTrainingTime written with elapsed ms

### 16.2 OAMconfigSkip (Section 4.2.7.5, 5.9)

SPEC FACT: If both sides set OAMconfigSkip=1 in PhaseSGA/B/C info field and both
confirm, transition G/H goes directly to Normal Mode (state 3), bypassing state 2.

---

## 17. Interfaces

### 17.1 Interface to Node State Machine

| Signal | Dir | Description |
|--------|-----|-------------|
| startup_complete | FSM->NSM | Transition G/H reached |
| startup_fail | FSM->NSM | ph1G_retry_cnt >= 255 |
| test_mode_entry | FSM->NSM | Transition T |
| test_mode_exit | FSM->NSM | Test done (return to startup) |
| soft_reset | NSM->FSM | Re-enter startup_INIT |
| ptb_stamp_for_startup | NSM->FSM | PTBstamp from PLP_TX.startup |

### 17.2 Interface to PCS Datapath

| Signal | Dir | Description |
|--------|-----|-------------|
| startup_phase | FSM->PCS | Phase1G/SGA/SGB/SGC/Normal |
| tx_info_field | FSM->PCS | Info field content to encode |
| rx_info_field | PCS->FSM | Decoded info field from RX |
| rx_info_valid | PCS->FSM | Info field CRC OK (SGA/B/C) |
| tx_pattern_sel | FSM->PCS | Training/test/normal |

### 17.3 Interface to PTB Clock Service

| Signal | Dir | Description |
|--------|-----|-------------|
| ptb_stamp | PTB->FSM | Current PTBclk for timing |
| startup_ptb_init | FSM->PTB | Signal startup entry (PTB=0) |

### 17.4 Interface to Register Model

| Signal | Dir | Description |
|--------|-----|-------------|
| sg_config[15:0] | Reg->FSM | SGconfig register (1.0002) |
| link_training[15:0] | FSM->Reg | Write LinkTraining (1.0100) |
| ext_link_status[15:0] | FSM->Reg | Write ExtLinkTrainingStatus (1.0108) |
| diag_test_ctrl[15:0] | Reg->FSM | Read DiagnosticsTestCtrl (1.0106) |
| connectivity_id[15:0] | FSM->Reg | Write ConnectivityIdent (1.0004) |

### 17.5 Interface to PMA/PMD Analog

| Signal | Dir | Description |
|--------|-----|-------------|
| pma_disable | FSM->PMA | Assert PMA.disable |
| pma_enable | FSM->PMA | Release PMA.disable |
| pma_reset | FSM->PMA | PMA reset in Power-On |
| rx_signal_detect | PMA->FSM | Signal presence on MDI |
| polarity_status[1:0] | PMA->FSM | Detected polarity |

---

## 18. Suggested RTL Module Boundaries

```
+================================================================+
|                   phy_startup_top                                |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | startup_root_fsm    |    | startup_leaf_fsm    |             |
|  |                     |    |                     |             |
|  | Phase1G root states |    | Phase1G leaf states |             |
|  | SGA/SGB/SGC root    |    | SGA/SGB/SGC leaf    |             |
|  | Test mode root      |    | Test mode leaf      |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | phase1g_ctrl        |    | phasesg_ctrl        |             |
|  |                     |    |                     |             |
|  | 40-bit info encode  |    | 512-bit info encode |             |
|  | 40-bit info decode  |    | 512-bit info decode |             |
|  | Status/test mux     |    | CRC32 check/gen     |             |
|  +---------------------+    | OAMconfigSkip logic |             |
|                             +---------------------+             |
|  +---------------------+    +---------------------+             |
|  | startup_info_encoder|    | startup_info_decoder|             |
|  |                     |    |                     |             |
|  | Phase1G field pack  |    | Phase1G field unpack|             |
|  | PhaseSG field pack  |    | PhaseSG field unpack|             |
|  +---------------------+    | CRC32 verify        |             |
|                             +---------------------+             |
|  +---------------------+    +---------------------+             |
|  | startup_crc32_checker|   | pma_training_ctrl   |             |
|  |                     |    |                     |             |
|  | Poly 0xF4ACFB13     |    | PMA.disable control |             |
|  | Verify/generate     |    | Half-duplex enforce |             |
|  | For PhaseSG fields  |    | IBG timing          |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | polarity_detect     |    | comready_monitor    |             |
|  |                     |    |                     |             |
|  | Detect/correct pol  |    | Set on G/H trans    |             |
|  | Write 1.0100[9:8]   |    | Clear on link loss  |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | link_training_status|    | diagnostics_test_ctrl|            |
|  |                     |    |                     |             |
|  | Training time msec  |    | TestType decode     |             |
|  | LP error count      |    | Enable monitoring   |             |
|  | Timeout count       |    | Immediate interrupt |             |
|  | RetryCounter mirror |    +---------------------+             |
|  +---------------------+                                        |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | startup_timer_       |    | phy_startup_        |             |
|  | counter_bank        |    | register_adapter    |             |
|  |                     |    |                     |             |
|  | All 12+ timers      |    | SGconfig, LinkTrain |             |
|  | ph1G_retry_count    |    | ExtStatus, DiagCtrl |             |
|  | phSGABC_count       |    | ConnectivityID      |             |
|  +---------------------+    +---------------------+             |
+================================================================+
```

---

## 19. Spec Facts vs Implementation Assumptions

### Spec Facts (normative)
- Phase1G retry limit: 255
- Phase1G timer: 200us; PhaseSGA/B/C timer: 312ns
- Half-duplex: no TX while RX burst in progress
- Interburst gap: 104ns nominal
- Phase1G info field: 40 bits with parity byte
- PhaseSGA/B/C info field: 512 bits with CRC32
- CRC32 algorithm: polynomial 0xF4ACFB13, start 0xFFFFFFFF, final XOR
  0xFFFFFFFF, byte-wise reflected input, reflected output (Section 4.2.9)
- COMready goes high at G/H transition
- LinkTrainingTime measured from startup_INIT to G/H in ms
- DiagnosticsTestCtrl is L-only (local access), not OAM-accessible
- S11 Termination test: register-only activation
- OAMconfigSkip requires mutual confirmation

### Implementation Assumptions (not in spec)
- Root/leaf FSM selection is based on SGconfig.Direction bit
- Timer precision: PCS clock-derived (not PTB-derived during Phase1G since PTB=0)
- CRC32 computation for the 480-bit field may be pipelined across multiple cycles,
  but must preserve the Section 4.2.9 reflection and final-XOR semantics
- Test pattern loading may share PCS scrambler infrastructure
- Polarity detection implemented in PMA analog with digital status output

---

## 20. Missing / Needs Verification

1. **Exact timer start/stop points**: Timers start "on the last symbol of pattern
   transmission" and stop "on the first symbol of a successfully received pattern."
   The precise cycle-count implementation depends on PCS symbol rate. VERIFY against
   PCS datapath timing at each speed grade.

2. **phSGABC_count saturation/rollover**: The counter counts info fields sent but
   the spec does not define a maximum or rollover behavior. VERIFY if there is a
   practical limit or if it runs until transition occurs.

3. **PhaseSGA/B/C FAIL behavior**: The spec shows FAIL states go back to (Y) which
   is startup_INIT. But the extraction does not clearly show whether retry_count is
   reset on re-entry or accumulated. VERIFY from PDF Figures 4-18 to 4-23.

4. **RX test result source wiring**: Figure 4-25 sends the result with a Startup
   Phase1G result field, and Section 4.4.1.2.1/Table 4-23 defines the field as
   LinkQuality_RXtest and FECstat_RXtest. VERIFY the final RTL source ports for
   those two result registers when PCS/FEC status RTL is integrated.

5. **Test mode duration for TX BER**: Duration not specified in extraction for
   TX BER test (TXtest=101). VERIFY from PDF Section 4.4.1.1.6.

6. **MLE startup differences**: Section 8.2.7 defines MLE Phase1G info field
   (Section 8.2.7.1.2). This doc covers Gen2020 only. MLE differences need
   separate verification.

7. **PCS numeric tables**: Tables 4-2/4-3/4-4/4-5 have been resolved in the PCS
   datapath doc but the resync header construction equations should still be
   verified against PDF before RTL implementation (noted in PCS doc Section 6.4).
