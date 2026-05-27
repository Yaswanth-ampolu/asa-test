# Micro-Architecture: PTB Clock Service

## 1. Purpose and Scope

The Precision Time Base (PTB) is a mandatory 48-bit logical clock that provides a
common time reference across all nodes in an ASA SerDes Branch. It has 4ns resolution
(one "PTB tic") and is used for:

- TDD cycle synchronization (mapper start alignment)
- OAM frame header timestamps (coarse sync, diagnostics)
- StartTDD scheduling (absolute time to begin normal mode)
- Light Sleep bedtime/alarm-clock timers
- ASEP ingress/presentation timestamps (video, I2S audio clock recovery)
- Follow/DelayRequest/DelayReply fine synchronization protocol

This document defines the micro-architecture for RTL/golden-model implementation.

Scope boundaries:
- IN SCOPE: PTB counter, leader/follower roles, lock FSM, OAM header PTB fields,
  offset/delay calculations, register interface, TDD sync, StartTDD timing, Light
  Sleep timer interaction, ASEP timestamp capture, I2S clock recovery principle
- OUT OF SCOPE: PCS burst formatting (4.2.2), OAM CAD processing, mapper internals,
  PHY analog circuits

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 3.3.19 | PTBclk (2.2200-2.2202) | 59 | 48-bit clock register |
| 3.3.20 | PTBstatus (2.2203) | 60 | Offset, locked, delay |
| 3.3.21 | PTBoamClk (2.2204-2.2206) | 60 | Last received OAM PTBclk |
| 3.3.22 | PTBoamDly (2.2207) | 60 | OAM delay diagnostic |
| 3.3.27 | ExtendedPTBstatus (2.2212) | 61 | Follow/DelayReply counters |
| 4.2.2.2.1 | Synchronization to PTB | 97 | TDD cycle = 6844 PTB tics |
| 4.2.2.3.5 | PTB Message Vector | 101 | m_ptb field encoding |
| 4.2.8 | Precision Time Base | 116 | Top-level PTB description |
| 4.2.8.1 | Clock Leader Messages | 117 | Follow, Delay Reply |
| 4.2.8.2 | Clock Follower Messages | 117 | Delay Request |
| 4.2.8.3 | PTB Updates and Calculations | 117-118 | Offset/delay equations |
| 4.2.8.3.1 | OAM frame from root node | 117 | Initial copy, diagnostics |
| 4.2.8.4 | PTB Follower State Diagram | 118-120 | Lock FSM |
| 5.5.1 | OAM Frame Structure (Table 5-2) | 171-172 | PTBclk/PTBstatus in header |
| 5.5.3.9 | StartTDD | 181 | PTBtime for normal mode |
| 5.8 | Light Sleep | 189-192 | Bedtime/alarmclock timers |
| 5.8.3.1 | LS Constants | 191 | ph1G_TIME=820, phSGx_TIME=6844 |
| 7.3.2.1 | ASEP PTB Time Stamps | 235 | Ingress/presentation stamps |
| 7.10.1.1 | Audio Sampling Rate to PTB | 276 | I2S clock recovery |
| 8.2.2.2.1 | Synchronization to PTB (MLE) | 288 | MLE TDD cycle periods |
| 8.2.8 | Precision Time Base (MLE) | 295 | "See section 4" |
| 8.6.2.2 | PTB time stamping (MLE) | 300 | MLE OAM timestamp point |
| Appendix F | I2S Audio Sampling relative to PTB | 349 | Clock recovery principle |

Image references:
- 10_PTB_leader_follower_sync.png: I2S PTB capture/reconstruction block diagram
- 19_PTB_clock_sync_I2S_nodes.png: Detailed follower/leader I2S clock recovery

---

## 3. PTB Role in the Full ASA System

```
+------------------------------------------------------------------+
|                       ASA SerDes Branch                            |
|                                                                    |
|  Root Node              Link              Non-Root Node            |
|  (Global Clock          <--->            (Clock Follower)          |
|   Leader)                                                          |
|                                                                    |
|  PTBclk runs            Follow/          PTBclk synced to          |
|  from local             DelayReply       root via protocol         |
|  reference              in resync                                  |
|  (250 MHz)              header           OAM header gives          |
|                                          coarse copy               |
|  OAM header       OAM frames            Follow/DelayReply          |
|  carries PTBclk   (every TDD)           give fine sync             |
|                                                                    |
|  StartTDD uses     <--- PTBtime --->    Non-root waits for         |
|  absolute PTB                            PTBtime to start           |
|  time                                    mapper                    |
|                                                                    |
|  Light Sleep       <--- PTBbedtime -->  Both use PTB timers        |
|  uses PTB          <--- PTBalarmclk ->                             |
|  timers                                                            |
|                                                                    |
|  ASEP timestamps   ingress/presentation captured from PTBclk       |
+------------------------------------------------------------------+
```

---

## 4. 48-bit PTB Clock Behavior

### 4.1 PTBclk Register (2.2200-2.2202, Section 3.3.19)

SPEC FACT: PTBclk[47:0] is a 48-bit unsigned integer counter.
- Register 2.2200: PTBclk[15:0]
- Register 2.2201: PTBclk[31:16]
- Register 2.2202: PTBclk[47:32]
- Type: RW, Access: O, Privilege: RID
- Resolution: 4ns per tic (one PTB tic)
- Rollover period: 2^48 * 4ns = ~1125 seconds (~18.8 minutes)

SPEC FACT (Section 4.2.8.4.5): "PTBclk holds 0 after reset; the state of a running
PTBclk is not changed by a repeated call of startPTBclk()."

### 4.2 Counter Operation

```
After reset: PTBclk = 0 (not running)
After startPTBclk(): PTBclk increments by 1 every 4ns (250 MHz tick rate)
After copyOAM(): PTBclk overwritten from OAM header (coarse sync)
After calcOffset(): PTBclk += PTBoffset (fine correction)
```

SPEC FACT (Section 4.2.8): "Every ASA node has a logical clock PTBclk with a
resolution of 4 ns (called a PTB tic)."

---

## 5. PTB Leader vs Follower Roles

### 5.1 Global Clock Leader

SPEC FACT (Section 4.2.8): "There is only one SerDes Branch global clock leader,
which is always the root node."

The root node:
- Runs PTBclk from its own local oscillator (nominally 250 MHz)
- Sends Follow and Delay Reply messages in the resync header
- Places PTBclk in OAM frame headers
- Controls message sequence (min 1 DelayReply per 15 Follow messages)
- Recommended ratio: 7 Follow : 1 Delay Reply

### 5.2 Clock Follower

Non-root nodes:
- Receive Follow/DelayReply from leader via resync header
- Send Delay Request (only message type from follower)
- Compute PTBoffset and PTBdelay from received timestamps
- Achieve lock within 100 TDD cycles after initial copy

### 5.3 Local Clock Leader (Branch Devices)

SPEC FACT (Section 4.2.8): "Local clock leaders copy the PTBclk of the clock follower
in the same ASA device once the clock follower is locked."

In a branch device with multiple links:
- Near-side port is clock follower (syncs to upstream root)
- Far-side port(s) act as local clock leader (provide Follow/DelayReply downstream)
- Local leader copies PTBclk from follower once follower is locked
- Deviation between leader and follower in same device: max 1 PTB tic when locked

---

## 6. PTB Message Encoding (Section 4.2.2.3.5)

### 6.1 Clock Leader -> Follower (m_ptb[15:0], Table 4-8)

```
Bit   Name          Description
15    PTB command   0=Follow, 1=Delay Reply
14    PTB status    0=not valid, 1=valid (usable for calculation)
13:0  TDDstamp      Lower 14 bits of PTBclk at MDI instant
```

### 6.2 Clock Follower -> Leader (m_ptb[15:0], Table 4-9)

```
Bit   Name          Description
15    Reserved      Set to 0
14    PTB status    0=not valid, 1=valid (follower locked)
13:0  TDDstamp      Lower 14 bits of PTBclk at MDI TX instant
```

### 6.3 Timestamp Capture Point

SPEC FACT (Section 4.2.8.1.2): "The time stamp is identical to the lower 14 bits of
PTBclk at the instant when the first symbol of the first physical layer block of this
TDD burst being sent will pass the local MDI."

For MLE (Section 8.6.2.2): "The PTB time stamp in the header of the OAM frame is
taken when the group of two control characters JK of the SOP passes the transmitting
MDI."

---

## 7. PTB Registers

### 7.1 PTBstatus (2.2203, Section 3.3.20)

```
Bit(s)  Name        Type  Description
15:13   Reserved    -     -
12:9    PTBoffset   RO    int3 sign-magnitude, calculated offset
                          Range: -7 (0x0F) .. +7 (0x07)
                          0x08: PTB update error / invalid
8       PTBlocked   RO    0: follower not locked / leader without valid ref
                          1: follower locked / leader has valid ref
7:0     PTBdelay    RO    uint8, cable latency in PTB tics (diagnostic)
```

### 7.2 PTBoamClk (2.2204-2.2206, Section 3.3.21)

```
PTBoamClk[47:0]: Last valid PTB clock counter received by OAM.
Type: RW, Access: O, Privilege: RID
Diagnostic: stores the last received OAM header PTBclk for debug.
```

### 7.3 PTBoamDly (2.2207, Section 3.3.22)

```
PTBoamDly[15:0]: Unsigned integer, calculated delay between local PTBclk
                 and last received OAM time stamp in PTB tics.
Type: RO, Access: O, Privilege: RID
Updated when OAM frame received (if PTB locked).
Resets to 0 (if PTB not locked, value must be 0).
```

### 7.4 ExtendedPTBstatus (2.2212, Section 3.3.27)

```
Bit(s)  Name            Type  Description
15:10   Reserved        -     -
9:5     DelayReplies    RO    = cnt_dlyRply_received from PTB state machine
4:0     Follows         RO    = cnt_follow_received from PTB state machine
```

---

## 8. OAM Header PTB Fields and Snapshot Timing

### 8.1 Header Layout (Table 5-2, bytes 4-11)

```
Byte 4, bit 6:    OAMheaderStatusValid
Byte 4, bit 7:    PTBstatus[0]
Byte 5:           PTBstatus[8:1]
Bytes 6-11:       PTBclk[47:0]        (6 bytes, LSB first)
```

SPEC FACT (Table 5-2): OAM header PTBstatus is "identical to 2.2203.8:0". It
therefore carries PTBlocked and PTBdelay only:
- header PTBstatus[0] = register 2.2203 bit 8, PTBlocked
- header PTBstatus[8:1] = register 2.2203 bits 7:0, PTBdelay
- register PTBoffset bits 12:9 are not carried in the OAM frame header and must be
  read through the PTBstatus register if needed.

SPEC FACT (Section 5.5.1, p173): "PTBclk, PTBstatus and all LinkHealthStatus
registers in the OAM frame header are copied at the time, when the OAM frame is
being created (between DLP_TX.indicateSlot and DLP_TX.oamUnit)."

SPEC FACT: "If local PTB is unlocked or no valid PTBclk can be sent, must be set to 0."

### 8.2 PTB Initial Copy (Section 4.2.8.3.1.1)

SPEC FACT: "On the reception of an OAM frame, if the local PTB is unlocked, the
PTBclk register is overwritten with the entire PTBclk value of the received OAM
header."

This provides coarse synchronization before fine sync (Follow/DelayReply) takes over.

### 8.3 PTB Diagnostics (Section 4.2.8.3.1.2)

SPEC FACT: "If the local PTB is locked, the time stamp in the OAM header is used to
calculate PTBoamDly. Whenever the local PTBclock is not locked, PTBoamDly must be
set to 0."

---

## 9. Follow / Delay Request / Delay Reply Protocol

### 9.1 Message Flow

```
Leader (Root/Local)                    Follower (Non-Root/Near-Side)
       |                                        |
       |--- Follow (TDDstamp=PTBclk[13:0]) ---->|
       |                                        | t_PTB_rx = local PTBclk at MDI RX
       |                                        | FOLLOWstamp = received TDDstamp
       |                                        |
       |<-- DelayRequest (TDDstamp) ------------|
       |    (t_PTB_tx = local PTBclk at MDI TX) |
       |                                        |
       |--- Follow --------------------------->|  (repeat ~7x)
       |                                        |
       |--- DelayReply (TDDstamp=PTBclk[13:0])->|
       |    (stamp = PTBclk when last RX burst  |
       |     first symbol passed local MDI)     |
       |                                        | DREPLYstamp = received TDDstamp
       |                                        | calcOffset()
       |                                        | calcDelay()
```

### 9.2 Offset Calculation (Equation 4-15)

```
PTBoffset = (t_PTB_rx - FOLLOWstamp - DREPLYstamp + t_PTB_tx) / 2
```

The follower applies PTBoffset to update its local PTBclk.
If |PTBoffset| <= ptb_LOCK_tol (2 tics), the update is "in sync".

### 9.3 Delay Calculation (Equation 4-16)

```
PTBdelay = t_PTB_rx - FOLLOWstamp - PTBoffset
     OR  = DREPLYstamp - t_PTB_tx + PTBoffset
```

PTBdelay is written to register 2.2203 bits 7:0.

### 9.4 Message Sequencing Rules

SPEC FACT:
- Leader sends min 1 Delay Reply per 15 Follow messages
- Leader sends min 1 Follow between two Delay Replies
- Recommended ratio: 7 Follow : 1 Delay Reply
- Local leader invalidates status when follower in same device is not locked

---

## 10. PTB Follower State Diagram (Section 4.2.8.4)

### 10.1 Constants

| Constant | Value | Description |
|----------|-------|-------------|
| ptb_ACQ_window | 16 | Follow messages to evaluate per acquisition window |
| ptb_LOCK_thresh | 14 | Min in-sync updates needed within window to lock |
| ptb_LOCK_tol | 2 | Max PTBoffset deviation (PTB tics) to be "in sync" |

### 10.2 Variables

| Variable | Description |
|----------|-------------|
| PTBint_state | "unlocked", "acquisition", or "locked" |
| PTBint_syncedUpdates | Count of in-sync Follow updates in last window |
| t_PTB_rx | Local PTBclk when RX burst first symbol passes MDI |
| t_PTB_tx | Local PTBclk when TX burst first symbol passes MDI |
| FOLLOWstamp | Saved TDDstamp from last Follow |
| DREPLYstamp | TDDstamp from DelayReply |
| cnt_follow_received | Saturates at ptb_ACQ_window |
| cnt_dlyRply_received | Saturates at ptb_ACQ_window |

### 10.2.1 Timers

SPEC FACT (Section 4.2.8.4.3): The PTB follower state diagram uses no timers. Lock
qualification is driven by received Follow/DelayReply/OAM events and the
`cnt_follow_received` / `cnt_dlyRply_received` acquisition counters.

### 10.3 State Machine (Figure 4-15)

```
                    reset
                      |
                      v
              +---------------+
              |   PTB_INIT    |
              |               |
              | PTBdelay=0    |
              | PTBclk=0      |
              | cnt_dly=0     |
              | cnt_fol=0     |
              | state=unlocked|
              +-------+-------+
                      |
                      v
              +---------------+
              |  PTB_WAIT_1   |<---------------------------+
              +---+---+---+---+                            |
                  |   |   |                                |
       PTB_OAM   | PTB_FOLLOW  PTB_DLYRPLY                |
                  |   |   |                                |
                  v   |   v                                |
   +--------------+   |   +----------------+              |
   |PTB_oamReceived|  |   |PTB_SaveStamps  |              |
   |               |  |   |                |              |
   |if(unlocked):  |  |   |cnt_dly++       |              |
   | copyOAM()    |  |   +--------+-------+              |
   | startPTBclk()|  |            |                       |
   |               |  |            v                       |
   |if(locked):    |  |   +--PTB_UpdatePTBclk--+          |
   | infoOAM()    |  |   |                     |          |
   |               |  +-->| if(PTBclk!=0 &      |          |
   |else:          |      |   cnt_dly>=1):      |          |
   | PTBoamDly=0  |      |  cnt_fol++          |          |
   +--------------+      |  calcOffset()       |          |
                          |  calcDelay()        |          |
                          |                     |          |
                          |  state=acquisition  |          |
                          |                     |          |
                          |  if(cnt_fol >=      |          |
                          |   ptb_ACQ_window):  |          |
                          |    if(synced >=     |          |
                          |     ptb_LOCK_thresh)|          |
                          |      state=locked   |          |
                          |    else             |          |
                          |      state=unlocked |          |
                          |      cnt_dly=0      |          |
                          |      cnt_fol=0      |--------->+
                          +---------------------+
```

### 10.4 Lock Achievement Requirement

SPEC FACT (Section 4.2.8): "The clock follower shall achieve a PTBlock condition within
100 TDD cycles after the 'PTB initial copy' and the recommended ratio of 7 Follow
messages to 1 Delay Reply message."

At 7:1 ratio with ptb_ACQ_window=16: lock achieved within 16 Follow messages
(~16 TDD cycles at ~6844 tics each = ~1.1ms nominal).

---

## 11. TDD Cycle Synchronization

### 11.1 Gen2020 (Section 4.2.2.2.1)

SPEC FACT: "The PCS in the root node (i.e. clock leader) or node which is link-local
clock leader, therefore starts a new TDD cycle every 6844 PTB tics (with a tolerance
of +/-1)."

6844 PTB tics * 4ns = 27.376us per TDD cycle.

### 11.2 MLE Modes (Section 8.2.2.2.1, Table 8-4)

| MLE Mode | TDD cycle (PTB tics) |
|----------|---------------------|
| MLES_sym1G0 | (same as Gen2020 SG1) |
| MLES_sym2G5 | (same as Gen2020 SG2) |
| MLES_sym5G0 | (same as Gen2020 SG3) |
| MLES_2G5_M | (per Table 8-4) |
| MLES_5G0_M | (per Table 8-4) |
| MLES_10G_M | (per Table 8-4) |
| MLES_10G_G | (per Table 8-4) |

IMPLEMENTATION NOTE: The extraction does not render Table 8-4 values clearly. Verify
exact TDD cycle durations per MLE mode from PDF p288.

---

## 12. StartTDD Interaction (Section 5.5.3.9)

SPEC FACT: StartTDD CAD contains PTBtime[47:0] -- the absolute PTB timestamp at
which to start normal mode.

```
Root sends StartTDD:
  PTBtime = absolute PTBclk value for normal mode start
  DLLlinemin, DLLlinemax = mapper pointers

Non-root receives StartTDD:
  1. Store PTBtime
  2. Compare local PTBclk against PTBtime continuously
  3. When PTBclk >= PTBtime:
     - Root: starts with resync header of first data burst
     - Leaf: starts one IBG into quiet gap and waits for data
  4. Mapper Initialization executes
  5. Normal Mode begins
```

PTB must be locked before StartTDD execution makes sense (otherwise PTBtime
comparison is meaningless).

---

## 13. Light Sleep Timer Interaction (Section 5.8.3)

### 13.1 Constants

| Constant | Value | Description |
|----------|-------|-------------|
| ph1G_TIME | 820 PTB tics | Phase1G cycle duration |
| phSGx_TIME | 6844 PTB tics | PhaseSGA/B/C cycle duration |

### 13.2 Timers

| Timer | Trigger | PTB-based |
|-------|---------|-----------|
| timer_LSbedtime | Set to PTBbedtime; triggers when PTBclk >= PTBbedtime | Yes |
| timer_LSalarmClock | Set to PTBalarmclock; triggers when PTBclk >= PTBalarmclock | Yes |

### 13.3 PTB During Light Sleep

- PTBclk continues running from local oscillator during sleep
- PTB is NOT locked during sleep (no Follow/DelayReply exchange)
- Drift accumulates during sleep (bounded by oscillator spec)
- On wake-up: PTB re-locks via normal startup sequence

SPEC FACT (Section 5.8.1.1): "PTB drift during sleep time is less than 140 PTB tics"
is a mandatory check condition for LSconfirm.

---

## 14. ASEP Timestamp Interaction (Section 7.3.2.1)

### 14.1 Common ASEP Header PTB Stamp Types

SPEC FACT (Table 7-5):
```
Bits 1:0 of second header byte:
  00 = no time stamp
  01 = ingress time stamp
  10 = presentation time stamp
  11 = user defined (4 bytes)
```

### 14.2 Ingress Time Stamp (Table 7-6)

```
PTBingress[31:0]: Lower 32 bits of PTBclk of the ASA node containing the ASE,
captured when the first payload symbol of this ASEP packet passed the application
interface.
```

4 bytes, stored in header bytes 2-5 (big-endian [31:24],[23:16],[15:8],[7:0]).

### 14.3 Presentation Time Stamp

Same format as ingress but indicates when the ASD should present the data at the
application interface. Used for end-to-end latency control.

---

## 15. I2S / Audio Clock Recovery (Images 10, 19; Appendix F)

### 15.1 Principle (from images 10_PTB_leader_follower_sync.png and 19_PTB_clock_sync_I2S_nodes.png)

```
ASA Node 2 (Follower/Source)         ASA Node 1 (Leader/Sink)
+---------------------------+        +---------------------------+
|                           |        |                           |
| MCK/SCK ---> Count N      |        |   M(n) = S(n) - S(n-1)   |
| from I2S     with MCK     |        |                           |
| master       or SCK       | S(n)   |   Count M PTB ticks       |
|              |            |------->|   regenerated             |
|              v            |        |           |               |
|     Capture PTB timestamp |        |           v               |
|     S when counting N     |        |   Multiply by N --------> MCK/SCK
|     starts each time      |        |                    to I2S |
|              |            |        |                    slave  |
|     PTB Follower CLK      |        |   PTB Leader CLK          |
|     250+delta MHz         |        |   250 MHz                 |
|              ^            |        |           ^               |
|     Synchronized by       |<-------|   PTB messages            |
|     PTB messages          |        |                           |
+---------------------------+        +---------------------------+
```

SPEC FACT (Appendix F, p349): "The following figure shows a principle implementation
of the capture and reconstruction of I2S timing information."

The source node captures the MCK/SCK period as S(n) PTB timestamps. The sink node
reconstructs the clock by counting M = S(n)-S(n-1) PTB ticks then multiplying by N
to regenerate the audio clock at the same rate.

### 15.2 Audio Rate Formula

From Section 7.10.1.1 / eDP Stream Clock Packet:
```
f_StrmClk = M_vid,ptb / N_vid,ptb * f_PTB
```
where f_PTB = 250 MHz (= 1 / 4ns per tic).

---

## 16. MLE Considerations (Section 8.2.8)

SPEC FACT (Section 8.2.8, p295): "See equivalent subsection in section 4."

PTB protocol is identical for MLE. Differences are only in:
- TDD cycle duration per MLE mode (Table 8-4)
- OAM PTB timestamp capture point: "when JK of SOP passes transmitting MDI" (8.6.2.2)
  vs Gen2020 which captures when first symbol of first physical layer block passes MDI

---

## 17. Error / Status / IRQ Interaction

### 17.1 PTB Flag in ASAnodeIRQ (1.0008, bit 8)

SPEC FACT: PTB flag is SC, detected locally, Access O, RID.
Set when a PTB-related error or status change occurs.

Conditions that may set PTB flag (IMPLEMENTATION ASSUMPTION):
- PTB loses lock (state transitions from locked to unlocked)
- PTBoffset exceeds range (0x08 = PTB update error)
- timer_LSbedtime or timer_LSalarmClock triggers

### 17.2 PTBstatus PTBoffset Error Code

When PTBoffset field = 0x08 (4-bit value): indicates "PTB update error / invalid"
rather than a numeric offset.

---

## 18. Interfaces

### 18.1 Interface to Register Model

| Signal | Dir | Description |
|--------|-----|-------------|
| ptb_clk[47:0] | PTB->Reg | Current PTBclk value for reg read (2.2200-2.2202) |
| ptb_clk_wr[47:0] | Reg->PTB | External write to PTBclk (for OAM/local override) |
| ptb_clk_wr_en | Reg->PTB | Write enable |
| ptb_status[15:0] | PTB->Reg | PTBstatus register (2.2203) |
| ptb_oam_clk[47:0] | PTB->Reg | PTBoamClk register (2.2204-2.2206) |
| ptb_oam_dly[15:0] | PTB->Reg | PTBoamDly register (2.2207) |
| ptb_ext_status[15:0] | PTB->Reg | ExtendedPTBstatus (2.2212) |

### 18.2 Interface to OAM Control Plane

| Signal | Dir | Description |
|--------|-----|-------------|
| oam_tx_ptbclk[47:0] | PTB->OAM | Snapshot for OAM header assembly |
| oam_tx_ptbstatus[8:0] | PTB->OAM | PTBstatus for header |
| oam_tx_snapshot_req | OAM->PTB | Capture request (at indicateSlot time) |
| oam_rx_ptbclk[47:0] | OAM->PTB | Received OAM header PTBclk |
| oam_rx_valid | OAM->PTB | Header received signal |
| ptb_locked | PTB->OAM | Lock status for header OAMheaderStatusValid |

### 18.3 Interface to Node State Machine

| Signal | Dir | Description |
|--------|-----|-------------|
| ptb_locked | PTB->NSM | PTB lock state |
| ptb_irq | PTB->NSM | PTB error/event for IRQ aggregation |
| soft_reset | NSM->PTB | Reset PTB to initial state |

### 18.4 Interface to DLL Mapper/Demux

| Signal | Dir | Description |
|--------|-----|-------------|
| tdd_cycle_start | PTB->DLL | Pulse every 6844 PTB tics (clock leader) |
| start_tdd_ptbtime[47:0] | OAM->PTB | StartTDD target time |
| start_tdd_trigger | PTB->DLL | PTBclk reached StartTDD time |

### 18.5 Interface to PCS/PMA (Resync Header)

| Signal | Dir | Description |
|--------|-----|-------------|
| ptb_tx_stamp[13:0] | PTB->PCS | Lower 14 bits of PTBclk at TX MDI instant |
| ptb_rx_stamp[13:0] | PCS->PTB | Received m_ptb TDDstamp field |
| ptb_rx_cmd | PCS->PTB | 0=Follow, 1=DelayReply |
| ptb_rx_status | PCS->PTB | Valid bit from received m_ptb |
| ptb_mdi_tx_event | PCS->PTB | First symbol passes TX MDI |
| ptb_mdi_rx_event | PCS->PTB | First symbol passes RX MDI |

### 18.6 Interface to Light Sleep Controller

| Signal | Dir | Description |
|--------|-----|-------------|
| ls_bedtime[47:0] | LS->PTB | Timer target for bedtime |
| ls_alarmclock[47:0] | LS->PTB | Timer target for wake-up |
| ls_timer_set | LS->PTB | Arm timer |
| ls_bedtime_trigger | PTB->LS | PTBclk >= bedtime |
| ls_alarm_trigger | PTB->LS | PTBclk >= alarmclock |

### 18.7 Interface to ASEP Common Layer

| Signal | Dir | Description |
|--------|-----|-------------|
| asep_ts_capture_req | ASEP->PTB | Request timestamp capture |
| asep_ts_value[31:0] | PTB->ASEP | Lower 32 bits of PTBclk at capture |

### 18.8 Interface to I2S ASEP

| Signal | Dir | Description |
|--------|-----|-------------|
| i2s_ptb_capture | I2S->PTB | Capture PTBclk when MCK/SCK count starts |
| i2s_ptb_value[47:0] | PTB->I2S | Full 48-bit PTBclk snapshot |

---

## 19. Suggested RTL Module Boundaries

```
+================================================================+
|                       ptb_top                                    |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | ptb_counter_48      |    | ptb_role_ctrl       |             |
|  |                     |    |                     |             |
|  | 48-bit free-running |    | Leader/Follower     |             |
|  | counter @ 250MHz    |    | mode selection      |             |
|  | Offset correction   |    | Local leader copy   |             |
|  | OAM overwrite       |    | logic               |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | ptb_oam_header_rx   |    | ptb_oam_header_tx   |             |
|  |                     |    |                     |             |
|  | Extract PTBclk from |    | Snapshot PTBclk at  |             |
|  | received OAM header |    | indicateSlot time   |             |
|  | copyOAM() if unlock |    | Format for header   |             |
|  | infoOAM() if locked |    | Zero if unlocked    |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | ptb_follow_fsm      |    | ptb_delay_calc      |             |
|  |                     |    |                     |             |
|  | Follower state:     |    | calcOffset()        |             |
|  |  unlocked/acq/locked|    | calcDelay()         |             |
|  | Window counting     |    | PTBoffset, PTBdelay |             |
|  | Lock decision       |    | Sync evaluation     |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | ptb_register_adapter|    | ptb_event_irq       |             |
|  |                     |    |                     |             |
|  | Map PTBclk/status/  |    | Lock loss detection |             |
|  | oamClk/oamDly/ext   |    | Timer expiry events |             |
|  | to register bus     |    | IRQ flag generation |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+                                        |
|  | ptb_timer_compare   |                                        |
|  |                     |                                        |
|  | StartTDD comparator |                                        |
|  | LS bedtime compare  |                                        |
|  | LS alarmclock compare|                                       |
|  +---------------------+                                        |
+================================================================+
```

---

## 20. Spec Facts vs Implementation Assumptions

### Spec Facts (normative)
- PTBclk resolution = 4ns (one PTB tic)
- Global clock leader = root node (always)
- TDD cycle = 6844 PTB tics for Gen2020 (tolerance +/-1)
- Lock within 100 TDD cycles after initial copy
- ptb_ACQ_window=16, ptb_LOCK_thresh=14, ptb_LOCK_tol=2
- Follower deviation from leader max 1 PTB tic when locked
- Min 1 DelayReply per 15 Follow messages
- OAM header PTBclk set to 0 if unlocked
- PTBoamDly set to 0 if unlocked
- Local leader invalidates status when follower not locked
- ASEP ingress timestamp = lower 32 bits of PTBclk

### Implementation Assumptions (not in spec)
- ptb_counter_48 runs at 250 MHz system clock
- Offset correction applied on next clock edge after calcOffset completes
- Timer comparators use >= (not ==) to handle rollover and jitter
- ASEP timestamp capture is single-cycle (combinational snapshot)
- I2S PTB capture granularity is 4ns (sufficient for audio rates)

---

## 21. Missing / Needs Verification

1. **MLE TDD cycle table values**: Table 8-4 (p288) lists TDD cycles per MLE mode but
   extraction does not render numeric values. VERIFY exact PTB tic counts per MLE mode.

2. **OAM header PTBstatus mapping resolved**: PDF Table 5-2 maps PTBstatus[0] to
   byte 4 bit 7 and PTBstatus[8:1] to byte 5. The carried field is register
   2.2203[8:0] only: PTBlocked plus PTBdelay. PTBoffset[12:9] is register-only.

3. **PTBclk write behavior from OAM**: Register is RW from OAM (RID privilege). Writing
   PTBclk[47:0] via OAM Write CAD should overwrite the counter. VERIFY whether this
   conflicts with running counter (does write pause counter? or just set new value?).

4. **cnt_follow_received saturation**: Section 4.2.8.4.4 says "saturates at value equal
   to ptb_ACQ_window." This means once 16 is reached, it stays at 16. VERIFY whether
   this implies a sliding window or a simple threshold comparison.

5. **Local clock leader PTBclk copy timing**: Spec says "copy the PTBclk of the clock
   follower in the same ASA device once the clock follower is locked." VERIFY whether
   copy is one-time snapshot or continuous tracking.

6. **PTB IRQ trigger conditions**: The spec defines PTB flag in ASAnodeIRQ but does not
   enumerate exact trigger conditions. VERIFY whether lock loss is the only trigger or
   if timer expiry also sets the flag.

7. **I2S clock recovery implementation detail**: Images 10/19 show the principle but the
   spec text (Appendix F) only provides "recommended lowest N values." The actual
   M/N calculation logic is implementation-defined. VERIFY whether Section 7.10.1.1
   mandates specific hardware.
