# Micro-Architecture: Light Sleep Controller FSM

## 1. Purpose and Scope

The Light Sleep controller manages the optional duty-cycling feature of the ASA
Physical Layer, allowing all nodes on a link to suspend transmission for a
coordinated period and restart together. It handles negotiation via OAM CAD
commands, feasibility evaluation, PTB-based timer management, and handoff to the
PHY Startup FSM for wake-up.

Scope:
- IN SCOPE: Light Sleep negotiation FSMs (root/non-root), OAM CAD routing,
  feasibility conditions, PTB timer interface, PMA.disable control, mapper halt/
  resume gate, all Light Sleep registers (2.2250-2.2256), status counter updates
- OUT OF SCOPE: OAM CAD parsing internals (see micro-architecture-oam-control-plane.md),
  PTB lock FSM (see micro-architecture-ptb-clock-service.md), PHY startup training
  (see micro-architecture-phy-startup-training-fsm.md), DLL mapper table content

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 3.2.6 | ASAnodeState (1.0006) | 35 | State 5 = Light Sleep |
| 3.3.28 | LightSleepCapability (2.2250) | 62 | CapableLS bit |
| 3.3.29 | LightSleepStatus1 (2.2251) | 62-63 | Table 3-66 |
| 3.3.30 | LightSleepStatus2 (2.2252) | 63 | Table 3-67 |
| 3.3.31 | LightSleepTest1 (2.2253) | 63-64 | Table 3-68 |
| 3.3.32 | LightSleepTest2 (2.2254-2.2256) | 64 | Table 3-69 |
| 5.5.3.13 (fused) | LSannounce payload | 181-182 | Table 5-15 |
| 5.5.3.11 (fused) | LSconfirm payload | 182 | Table 5-16 |
| 5.5.3.12 (fused) | LSdeny payload | 182 | Table 5-17 |
| 5.5.3.13 | LSsleep payload | 182 | Table 5-18 |
| 5.8 | Light Sleep | 189 | Top-level description |
| 5.8.1 | Entering Light Sleep | 189 | Root mediator role |
| 5.8.1.1 | Check by Non-Root | 190 | 4 mandatory conditions |
| 5.8.1.2 | Check by Root | 190 | Root feasibility + alarm |
| 5.8.2 | Light-Sleep Wake Up | 191 | Reuses startup sequence |
| 5.8.3 | Light Sleep State Diagrams | 191-192 | Full FSM specs |
| 5.8.3.1 | Constants | 191 | ph1G_TIME, phSGx_TIME |
| 5.8.3.2-6 | Variables/Timers/Counters/Functions/Events | 191 | Complete FSM elements |
| 5.8.3.7 | Diagrams | 192 | Figures 5-12, 5-13 |
| 5.9 | DLL Startup, OAM Config | 193 | Figure 5-13 non-root FSM |
| 4.2.7 | Startup and PMA Training | 109 | Wake-up reuses startup |
| 4.3.2.2.1 | PMA.disable | 121 | PHY disable during sleep |

---

## 3. Light Sleep Role and Mandatory/Optional Status

SPEC FACT (Section 5.8, p189): Light Sleep is OPTIONAL. "The support of Light Sleep
feature is optional." (from DLL section in 5.7.1.3.3 informative text)

SPEC FACT: Nodes report Light Sleep support via register 2.2250 bit 0 (CapableLS).
Root must check this before initiating Light Sleep with any non-root node.

SPEC FACT: "Light Sleep enables duty cycling of the traffic of the link on a time
scale of a sensor or display cycle, it can stop traffic on the link for up to 4096
TDD cycles."

SPEC FACT (Section 5.8.3, p191): During Light Sleep:
- Mapper is halted, quiet gap extended
- PMA TX and RX are disabled
- PTBclk continues running on local reference
- PTBclk drift allowed up to 140 PTB tics during sleep

---

## 4. Light Sleep Registers

### 4.1 LightSleepCapability (2.2250) -- Table 3-65, PDF p62

```
Bit(s)  Name       Type  Access  Privilege  Description
15:1    Reserved
0       CapableLS  RO    O       RID        0=no support, 1=node supports LightSleep
```

### 4.2 LightSleepStatus1 (2.2251) -- Table 3-66, PDF p63

SPEC FACT: "This register only exists, when (optional) LightSleep is implemented."

```
Bit(s)  Name                  Type  Access  Privilege  Description
15      LSstatus1_valid        RO    O       RID        0=not valid, 1=register content valid
14:9    LightSleep_denied      SC    O       RID        Accumulated LSdeny received (sat 0x3F)
8:3     LightSleep_announced   SC    O       RID        Accumulated LSannounce received (sat 0x3F)
2       Reserved
1:0     LightSleep_status      RO    O       RID        0=normal mode
                                                        1=LS mediation ongoing (any LS state
                                                          except LS_dreaming_*)
                                                        2=Light Sleep ongoing (in LS_dreaming_*)
                                                        3=restarting (exited through point "b")
```

### 4.3 LightSleepStatus2 (2.2252) -- Table 3-67, PDF p63

SPEC FACT: "This register only exists, when (optional) LightSleep is implemented."

```
Bit(s)  Name                   Type  Access  Privilege  Description
15      LSstatus2_valid         RO    O       RID        0=not valid, 1=register content valid
14:11   LightSleep_impossible   SC    O       RID        Accumulated LSpossible=FALSE count
                                                         (sat 0x0F)
10:6    Impossible_node         RO    O       RID        nodeID that caused last LSpossible=FALSE
5:1     LightSleep_executed     SC    O       RID        Number of LS cycles executed (sat 0x1F)
0       LightSleep_fail         SC    O       RID        Link failed to come back (sat 1)
```

### 4.4 LightSleepTest1 (2.2253) -- Table 3-68, PDF p63-64

SPEC FACT: "Intended for test purposes only. Triggers a root node to mediate and
execute LightSleep with the link partner."

```
Bit(s)  Name                       Type  Access  Privilege  Description
15:13   Reserved
12      LightSleep_test_trigger    SC    L       RID        Test triggered by writing a 1
11:0    LightSleep_test_SleepCycles RW   L       RID        Number of TDD cycles to sleep
```

Note: Access = L (local only), not accessible via OAM.

### 4.5 LightSleepTest2 (2.2254-2.2256) -- Table 3-69, PDF p64

SPEC FACT: "Intended for test purposes only in conjunction with LightSleepTest1."

```
Register  Name              Type  Access  Privilege
2.2254    PTBbedtime[15:0]  RW    L       RID
2.2255    PTBbedtime[31:16] RW    L       RID
2.2256    PTBbedtime[47:32] RW    L       RID
```

Combined: 48-bit PTBbedtime value to use for Light Sleep test.

---

## 5. OAM CAD Command Formats

All LS CAD commands carry no register address (only command byte + data).

### 5.1 LSannounce (Section 5.5.3.10) -- Table 5-15

Sent by either root or non-root to announce desired sleep.

```
Byte  Bits   Field                  Description
n+1   7:0    PTBbedtime[47:40]      48-bit absolute PTB time to enter sleep
n+2   7:0    PTBbedtime[39:32]
n+3   7:0    PTBbedtime[31:24]
n+4   7:0    PTBbedtime[23:16]
n+5   7:0    PTBbedtime[15:8]
n+6   7:0    PTBbedtime[7:0]
n+7   7:4    Reserved
n+7   3:0    SleepCycles[11:8]      Total TDD cycles to sleep (includes restart time)
n+8   7:0    SleepCycles[7:0]
n+9   7:0    RestartCycles1G[7:0]   Phase1G patterns required to restart
n+10  7:0    RestartCyclesSGx[7:0]  PhaseSGA/B/C patterns required to restart
n+11         Reserved
```

### 5.2 LSconfirm (Section 5.5.3.11) -- Table 5-16

Sent by non-root to accept Light Sleep with its own restart requirements.

```
Byte  Bits   Field                    Description
n+1   7:0    RestartCycles1G_a[7:0]   Own Phase1G restart count
n+2   7:0    RestartCyclesSGx_a[7:0]  Own PhaseSGA/B/C restart count
n+3          Reserved
```

### 5.3 LSdeny (Section 5.5.3.12) -- Table 5-17

Sent to reject Light Sleep. No parameters.

```
Byte  Field
n+1   Reserved
```

### 5.4 LSsleep (Section 5.5.3.13) -- Table 5-18

Sent by root after feasibility confirmed. Carries final wake-up timing.

```
Byte  Bits   Field                    Description
n+1   7:0    PTBalarmclock[47:40]     48-bit PTB time to start restart (wake-up)
n+2   7:0    PTBalarmclock[39:32]
n+3   7:0    PTBalarmclock[31:24]
n+4   7:0    PTBalarmclock[23:16]
n+5   7:0    PTBalarmclock[15:8]
n+6   7:0    PTBalarmclock[7:0]
n+7   7:0    RestartCycles1G_f[7:0]   Final Phase1G restart count (max of all confirms)
n+8   7:0    RestartCyclesSGx_f[7:0]  Final PhaseSGA/B/C restart count
n+9          Reserved
```

---

## 6. Feasibility Conditions

### 6.1 Non-Root Check (Section 5.8.1.1, p190)

SPEC FACT: A non-root sends LSconfirm only if ALL four conditions hold:

1. PTB is locked
2. Net sleep time > 100µs:
   ```
   SleepCycles*phSGx_TIME - (RestartCycles1G_a*ph1G_TIME
     + RestartCyclesSGx_a*phSGx_TIME) > 25,000 PTB tics
   ```
   (25,000 tics * 4ns = 100µs)
3. Sufficient lead time:
   ```
   PTBbedtime - PTBclk > 12,500 PTB tics
   ```
   (12,500 tics * 4ns = 50µs)
4. PTB drift during net sleep < 140 PTB tics

SPEC FACT: "Light Sleep is allowed to be denied any time." A non-root may always
send LSdeny regardless of conditions.

### 6.2 Root Check (Section 5.8.1.2, p190)

SPEC FACT: Root collects all LSconfirm messages, computes worst-case restart:
```
RestartCycles1G_f  = max(RestartCycles1G_a_1, ..., RestartCycles1G_a_n)
RestartCyclesSGx_f = max(RestartCyclesSGx_a_1, ..., RestartCyclesSGx_a_n)
```

Root evaluates LSpossible = TRUE if ALL three conditions hold:

1. PTB is locked
2. Net sleep time > 100µs:
   ```
   SleepCycles*phSGx_TIME - (RestartCycles1G_f*ph1G_TIME
     + RestartCyclesSGx_f*phSGx_TIME) > 25,000 PTB tics
   ```
3. Sufficient lead time:
   ```
   PTBbedtime - PTBclk > 12,500 PTB tics
   ```

SPEC FACT: Alarm clock calculation:
```
PTBalarmclock = PTBbedtime + SleepCycles*phSGx_TIME
              - (RestartCycles1G_f*ph1G_TIME + RestartCyclesSGx_f*phSGx_TIME)
```

### 6.3 FSM Constants (Section 5.8.3.1, p191)

| Constant | Value | Units | Description |
|----------|-------|-------|-------------|
| ph1G_TIME | 820 | PTB tics | Nominal Phase1G cycle duration |
| phSGx_TIME | 6844 | PTB tics | Nominal PhaseSGA/B/C cycle duration |

---

## 7. Root Node Light Sleep FSM (Figure 5-12)

### 7.1 Root-Initiated Flow

```
  (Normal Mode)
      |
      | Application or LightSleepTest1 trigger
      v
  LS_mediate_1
  +--------------------------+
  | Issue LSannounce to all  |
  | affected n nodes via OAM |
  | Check own parameters     |
  +--------------------------+
      |
  +---+---+
  |       |
LSpossible  LSpossible
 = FALSE    = TRUE
  |              |
  v              v
LS_deny_1    LS_confirm_1
sendDeny()   sendConfirm()
  |              |
  v              v
(abort)     LS_check_2
            (collect all
             LSconfirm/LSdeny
             from n nodes;
             check own params)
                 |
           +-----+------+
           |            |
       LSpossible    LSpossible
        = FALSE       = TRUE
           |            |
           v            v
       LS_deny_1    LS_issue_sleep_1
       sendDeny()   sendSleep() to all
                    affected nodes
                        |
                        v
                   LS_lightsOut_1  -- (a) to ASAnodeState=5
                   set timer_LSalarmClock
                        |
                        v
                   LS_dreaming_1
                   (PHY/mapper disabled)
                        |
                   timer_LSalarmClock_trigger
                        |
                        v
                   (b) --> PHY Startup FSM (restart)
```

### 7.2 Root Handling Non-Root-Initiated Announce

```
  LSannounce(PTBbedtime, SleepCycles,
             RestartCycles1G, RestartCyclesSGx) received
      |
      v
  LS_announce_1 / LS_announce_2
  Issue LSannounce to other n affected nodes
  Check own parameters
      |
   (same flow as root-initiated from LS_check_2 onward)
```

---

## 8. Non-Root Node Light Sleep FSM (Figure 5-13)

### 8.1 Non-Root Receiving Announce (Root-Initiated)

```
  (Normal Mode)
      |
  LSannounce received
      v
  LS_check_3
  (evaluate 4 conditions)
      |
  +---+---+
  |       |
LSpossible  LSpossible
 = FALSE    = TRUE
  |              |
  v              v
LS_deny_3     LS_confirm_3
sendDeny()    sendConfirm(RestartCycles1G_a, RestartCyclesSGx_a)
  |              |
  (end)          v
             LS_pyjamaOn_4
             set timer_LSbedtime
                 |
             LS_wait_3
                 |
             LSsleep(PTBalarmclock, R1G_f, RSGx_f) received
                 |
             LS_lightsOut_3  -- (a) to ASAnodeState=5
             set timer_LSalarmClock
                 |
             LS_dreaming_3
             (PHY/mapper disabled, PTBclk on local ref)
                 |
             timer_LSalarmClock_trigger
                 |
             (b) --> PHY Startup FSM (restart)
```

### 8.2 Non-Root-Initiated Flow

```
  (Normal Mode)
      |
  Application trigger
      v
  LS_announce_2
  sendAnnounce(PTBbedtime, SleepCycles, R1G, RSGx)
      |
  LSconfirm() / LSdeny() received from root
      |
  LS_confirm_3 / LS_deny_3
  (then proceeds same as receiving announce above)
```

---

## 9. ASAnodeState Interaction

SPEC FACT (Section 3.2.6, p35): State 5 = "Light Sleep (further refined in 3.3.29)"

The LightSleep_status field in 2.2251 (bits 1:0) provides finer granularity:

| LightSleep_status | Node state | ASAnodeState |
|-------------------|-----------|-------------|
| 0 | Normal mode (no LS) | 3 (Normal Mode) |
| 1 | LS mediation ongoing | 5 (Light Sleep) |
| 2 | LS_dreaming_* (sleeping) | 5 (Light Sleep) |
| 3 | Restarting (exited through b) | 1 (Startup) |

Transitions:
- Normal Mode (3) -> Light Sleep (5): at timer_LSbedtime trigger, point "a"
- Light Sleep (5) -> Startup (1): at timer_LSalarmClock trigger, point "b"

---

## 10. PTB Timer Interface

SPEC FACT (Section 5.8.3.3, p191):

| Timer | Trigger | Description |
|-------|---------|-------------|
| timer_LSbedtime | Set to PTBbedtime; fires when PTBclk >= PTBbedtime | Enter sleep |
| timer_LSalarmClock | Set to PTBalarmclock; fires when PTBclk >= PTBalarmclock | Wake up |

SPEC FACT: PTBclk continues running during sleep from local reference. Maximum
allowed drift during sleep: 140 PTB tics (= 560ns).

---

## 11. PMA.disable Interaction (Section 4.3.2.2.1)

SPEC FACT: "PMA.disable is controlled by the PCS according to startup state, TDD
state or Light Sleep state."

When entering sleep (point "a"):
1. Light Sleep FSM signals PMA.disable assert
2. Physical Layer holds all PCS registers (Section 5.7.1.3.3 informative)
3. Oscillator continues running; PTBclk maintained on local reference
4. Equalizer settings frozen

On wake-up (point "b"):
1. timer_LSalarmClock fires
2. Light Sleep FSM hands off to PHY Startup FSM
3. PLP_TX.startup(PTBstamp=PTBalarmclock) triggered
4. PMA.disable released, startup sequence begins

---

## 12. Mapper Halt/Resume Interaction (Section 5.7.1.3.3 informative)

SPEC FACT: "Stops Mapper, extends the quiet gap" during Light Sleep.

When entering sleep:
1. Light Sleep FSM signals DLL mapper gate to halt
2. DLP_TX.indicateSlot no longer generated
3. No containers transmitted or received

On restart (entering Startup state):
1. DLL mapper remains halted until StartTDD CAD received
2. OAMconfigSkip=1 fast-path used (configuration preserved across sleep)
3. StartTDD restores DLLlinemin/max and triggers mapper initialization

SPEC FACT (Section 5.9, p193): "If the required ASA nodes/devices configurations
for Normal Mode are persistently stored beyond a power cycle (or the device come
back from Light Sleep), Normal Mode can be initiated by setting the appropriate bit
in the startup info field (see 4.2.7.5)."

---

## 13. Wake-Up and Startup Restart

SPEC FACT (Section 5.8.2, p191): "Light Sleep reuses the normal Startup sequence,
which is entered at the negotiated point in time. See 4.2.7 and 4.3.3.1."

Wake-up sequence:
1. timer_LSalarmClock triggers (point "b")
2. ASAnodeState -> 1 (Startup)
3. LightSleep_status -> 3 (restarting)
4. PHY Startup FSM begins Phase1G at PTBalarmclock time
5. Both sides run Phase1G with `RestartCycles1G_f` Phase1G patterns
6. Both sides run PhaseSGA/B/C with `RestartCyclesSGx_f` patterns
7. OAMconfigSkip=1 used (both sides have persistent config)
8. Transition G/H -> Normal Mode
9. LightSleep_status -> 0
10. LightSleep_executed counter (2.2252 bits 5:1) incremented

On failure to restart:
1. LightSleep_fail (2.2252 bit 0) set
2. ASAnodeState -> 6 (Fail) per startup FSM rules

---

## 14. Status Counter Side Effects

| Event | Register | Field Updated |
|-------|----------|---------------|
| LSannounce received | 2.2251 | LightSleep_announced [8:3] SC, sat 0x3F |
| LSdeny received | 2.2251 | LightSleep_denied [14:9] SC, sat 0x3F |
| LSpossible=FALSE evaluated | 2.2252 | LightSleep_impossible [14:11] SC, sat 0x0F |
| LSpossible=FALSE node | 2.2252 | Impossible_node [10:6] RO (nodeID) |
| Light Sleep cycle completed | 2.2252 | LightSleep_executed [5:1] SC, sat 0x1F |
| Link fails to restart | 2.2252 | LightSleep_fail [0] SC, sat 1 |

---

## 15. ASCII Overall Flow Diagram

```
Root Node                              Non-Root Node
    |                                       |
    |---- LSannounce(bed,cyc,R1G,RSGx) ---->|
    |                                       | evaluate 4 conditions
    |<--- LSconfirm(R1G_a, RSGx_a) ---------|  OR
    |<--- LSdeny() -------------------------|
    |
    | collect all confirms
    | compute R1G_f = max(all R1G_a)
    | compute RSGx_f = max(all RSGx_a)
    | compute PTBalarmclock
    | check own conditions -> LSpossible
    |
    |---- LSsleep(alarmclk, R1G_f, RSGx_f) ->|
    |                                          | set timer_LSbedtime
    | set timer_LSbedtime                      |
    |                                          |
timer_LSbedtime ---> SLEEP <-- timer_LSbedtime|
    | (PMA disabled, mapper halted)            |
    | (PTBclk on local ref)                    |
    |                                          |
timer_LSalarmClock -> RESTART <- timer_LSalarmClock
    | Phase1G (R1G_f patterns)                 |
    | PhaseSGA/B/C (RSGx_f patterns)           |
    | OAMconfigSkip=1                          |
    |-------- Normal Mode ------------------>  |
```

---

## 16. Interfaces

### 16.1 Interface to OAM Control Plane

| Signal | Dir | Description |
|--------|-----|-------------|
| ls_cad_rx(type, params) | OAM->LS | Decoded LSannounce/confirm/deny/sleep |
| ls_cad_tx(type, params) | LS->OAM | Generate sendAnnounce/Confirm/Deny/Sleep |
| ls_status[1:0] | LS->OAM | LightSleep_status for OAM header context |

### 16.2 Interface to PTB Clock Service

| Signal | Dir | Description |
|--------|-----|-------------|
| ptb_clk[47:0] | PTB->LS | Current PTBclk for condition checks |
| ptb_locked | PTB->LS | Required for feasibility checks |
| ls_bedtime[47:0] | LS->PTB | Set timer_LSbedtime target |
| ls_alarmclock[47:0] | LS->PTB | Set timer_LSalarmClock target |
| ls_bedtime_trigger | PTB->LS | timer_LSbedtime fired |
| ls_alarm_trigger | PTB->LS | timer_LSalarmClock fired |

### 16.3 Interface to Node State Machine

| Signal | Dir | Description |
|--------|-----|-------------|
| ls_enter | LS->NSM | Enter Light Sleep (point "a") |
| ls_exit_to_startup | LS->NSM | Wake-up (point "b") |
| ls_fail | LS->NSM | Link failed to restart |
| nsm_state[3:0] | NSM->LS | Gate LS entry to Normal Mode only |

### 16.4 Interface to PHY Startup FSM

| Signal | Dir | Description |
|--------|-----|-------------|
| ls_restart_trigger | LS->PHY | Trigger restart at alarm time |
| ls_r1g_f[7:0] | LS->PHY | RestartCycles1G_f for startup |
| ls_rsgx_f[7:0] | LS->PHY | RestartCyclesSGx_f for startup |
| ls_ptb_alarm[47:0] | LS->PHY | PTBalarmclock as PTBstamp |
| phy_restart_done | PHY->LS | Startup complete (G/H reached) |
| phy_restart_fail | PHY->LS | Startup failed |

### 16.5 Interface to PCS/PMA

| Signal | Dir | Description |
|--------|-----|-------------|
| ls_pma_disable | LS->PMA | Assert PMA.disable at bedtime |
| ls_pma_release | LS->PHY | Release at alarm (via PHY Startup) |

### 16.6 Interface to DLL Mapper/Demux

| Signal | Dir | Description |
|--------|-----|-------------|
| ls_mapper_halt | LS->DLL | Stop mapper at bedtime |
| ls_mapper_resume | LS->DLL | Resume after StartTDD (via startup) |

### 16.7 Interface to Register Model

| Signal | Dir | Description |
|--------|-----|-------------|
| ls_capable[0] | Reg->LS | LightSleepCapability bit 0 |
| ls_status1_wr[15:0] | LS->Reg | Update 2.2251 |
| ls_status2_wr[15:0] | LS->Reg | Update 2.2252 |
| ls_test1_rd[15:0] | Reg->LS | Read 2.2253 for test trigger |
| ls_test2_rd[47:0] | Reg->LS | Read 2.2254-2.2256 for PTBbedtime |

---

## 17. Suggested RTL Module Boundaries

```
+================================================================+
|                    light_sleep_top                               |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | ls_root_fsm         |    | ls_nonroot_fsm      |             |
|  |                     |    |                     |             |
|  | LS_mediate_1        |    | LS_check_3          |             |
|  | LS_announce_1/2     |    | LS_announce_2       |             |
|  | LS_confirm_1        |    | LS_deny_3           |             |
|  | LS_deny_1           |    | LS_confirm_3        |             |
|  | LS_check_2          |    | LS_pyjamaOn_4       |             |
|  | LS_issue_sleep_1/2  |    | LS_wait_3           |             |
|  | LS_lightsOut_1/2    |    | LS_lightsOut_3/4    |             |
|  | LS_dreaming_1/2     |    | LS_dreaming_3/4     |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | ls_oam_cad_bridge   |    | ls_feasibility_eval |             |
|  |                     |    |                     |             |
|  | Encode/decode all   |    | Check 4 non-root    |             |
|  | LS CAD formats      |    | conditions          |             |
|  | Route to FSMs       |    | Check 3 root        |             |
|  +---------------------+    | conditions          |             |
|                             | Compute PTBalarmclk |             |
|                             | LSpossible bool     |             |
|                             +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | ls_ptb_timer        |    | ls_restart_param_   |             |
|  |                     |    | calc                |             |
|  | PTB comparators for |    |                     |             |
|  | bedtime and alarm   |    | Track per-node      |             |
|  | clock               |    | R1G_a / RSGx_a      |             |
|  +---------------------+    | Compute max finals  |             |
|                             +---------------------+             |
|  +---------------------+    +---------------------+             |
|  | ls_pma_control      |    | ls_mapper_gate      |             |
|  |                     |    |                     |             |
|  | Assert PMA.disable  |    | Halt/resume mapper  |             |
|  | at bedtime          |    | indicateSlot gate   |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | ls_status_counters  |    | ls_register_adapter |             |
|  |                     |    |                     |             |
|  | Update 2.2251/2252  |    | Map all LS regs to  |             |
|  | SC counter logic    |    | domain-2 bus        |             |
|  | LSpossible_node ID  |    | Test reg interface  |             |
|  +---------------------+    +---------------------+             |
+================================================================+
```

---

## 18. Spec Facts vs Implementation Assumptions

### Spec Facts
- Light Sleep is OPTIONAL
- Either root or non-root may initiate; root always executes
- No node can be forced into Light Sleep (deny always allowed)
- PTB must be locked for feasibility
- Min net sleep: 25,000 PTB tics (100µs)
- Min lead time: 12,500 PTB tics (50µs)
- Max PTB drift during sleep: 140 PTB tics
- ph1G_TIME = 820, phSGx_TIME = 6844 PTB tics
- PTBalarmclock formula: PTBbedtime + SleepCycles*phSGx_TIME - restart cost
- Wake-up reuses normal startup sequence (Phase1G + PhaseSGA/B/C)
- OAMconfigSkip=1 used for wake-up (persistent config)
- Mapper halted during sleep; PTBclk continues on local reference
- LS FSM has no counters (Section 5.8.3.4)
- LightSleepTest1/2 registers: L-only (not OAM accessible)

### Implementation Assumptions
- Root/non-root role is topology-configured, not from SGconfig.Direction
- timer_LSbedtime and timer_LSalarmClock are PTBclk comparators (>= comparison),
  not countdown timers, to handle local clock drift
- Worst-case PTB drift during sleep is bounded; implementation must track that
  the feasibility check margin covers accumulated drift
- Maximum number of affected nodes tracked in restart param calc is
  implementation-defined (spec says collect from all n affected nodes)
- LightSleep_fail increments on startup timeout after wake-up -- exact trigger
  condition (which startup failure) is implementation-defined

---

## 19. Missing / Needs Verification

1. **LightSleepStatus1 register bit 14:9 vs extraction fusing**: The extraction
   shows this as register 3.3.30 but PDF p63 Table 3-66 clarifies it belongs to
   2.2251. The extraction chunk header says "3.3.30 LightSleepStatus2 (2.2252)"
   but the table content inside is LightSleepStatus1. VERIFIED from PDF: Table
   3-66 = 2.2251, Table 3-67 = 2.2252. Use PDF tables, not extraction section
   numbers.

2. **LightSleepTest2 full definition**: PDF p64 shows only 3 registers (2.2254-
   2.2256) holding PTBbedtime[47:0]. No additional fields beyond this 48-bit
   value. Extraction chunk 3.3.32 confirms this is the complete definition.

3. **Affected-node scoping for branch topologies**: Section 5.8.1 states Light
   Sleep applies to nodes "on the same link" or "connected to root by the link
   that wants to go to sleep." For branch devices with multiple links, the exact
   scope of affected nodes is topology-dependent. VERIFY if the spec defines a
   forwarding rule for LSannounce in branch configurations.

4. **Maximum SleepCycles value**: The spec states LS can stop traffic "for up to
   4096 TDD cycles" (informative text). LightSleepTest1 bits 11:0 hold SleepCycles
   (12 bits = max 4095). VERIFY whether this 4096 limit is normative or informative.

5. **LS_pyjamaOn_4 state**: Figure 5-13 (extracted from chunk 5.9) shows a state
   LS_pyjamaOn_4 between LS_confirm_3 and timer_LSbedtime set. The extraction does
   not clarify what actions occur in this state. VERIFY from PDF Figure 5-13 what
   LS_pyjamaOn_4 does (likely a no-op holding state).

6. **LSannounce forwarding to affected n nodes by root**: The root FSM "issues
   LSannounce to other affected n nodes." The mechanism for determining and
   addressing these n nodes is not explicitly defined in Section 5.8. VERIFY
   whether this uses the normal OAM addressing table or requires broadcast.
