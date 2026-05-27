# ASA Register Model — Micro Architecture

## Document Information
- **Source**: ASA Technical Specification v2.0 (30 April 2024)
- **Sections**: 3.1–3.8, pages 28–92
- **Review applied**: micro-architecture-register-model-review.md

---

## 1. Overview

Every ASA node maintains its own independent 16-bit register map. An ASA Device containing multiple nodes has one complete register map per node.

### 1.1 Register Width and Reset
- All registers are **16 bits wide**
- Default reset value is **0** unless otherwise specified in the register definition
- **SoftReset (1.0007)** resets state machines and status registers only; **configuration registers are preserved**

### 1.2 Address Format

```
d.a          — whole register (domain d, register a)
d.a.(m:l)    — bit field m downto l of register a
d.i.a        — ASE/ASD register (domain d, subdomain i, register a)
d.i.a.(m:l)  — bit field of ASE/ASD register
```

| Field | Range | Description |
|-------|-------|-------------|
| d | 0–5 (6–8 reserved) | Register domain |
| i | 1–63 (0 reserved) | DLP Port ID — ASE/ASD only |
| a | 1–32767 | Register number within domain |
| m | 0–15 | MSB of bit field |
| l | 0–14 | LSB of bit field |

---

## 2. Register Domains

| Domain (d) | Name | Description |
|------------|------|-------------|
| 0 | User | Implementer-defined; OAM-accessible |
| 1 | Physical Layer | PMA/PMD/PCS + MLE registers |
| 2 | Data Link Layer | DLL, PTB, mapper, demux, Light Sleep |
| 3 | Security | Policy, dropped container counters |
| 4 | ASE | Application Stream Encapsulator (subdomain = DLP_TX_ID) |
| 5 | ASD | Application Stream Decapsulator (subdomain = DLP_RX_ID) |

> **Note on sizes:** Domain 0 is implementer-defined. Domain 2 extends to at least 2.2256. Domain 3 contains only the three registers defined in Section 3.4. ASE/ASD storage depends on implemented DLP ports and stream types.

---

## 3. Access Encoding

Each register defines three orthogonal attributes:

### 3.1 R/W Type

| Code | Name | Behavior |
|------|------|----------|
| RW | Read/Write | Normal read and write |
| RO | Read-Only | Writes ignored |
| SC | Self-Clearing | Read returns current value; clears to 0 after read |

### 3.2 Access Channel

| Code | Meaning |
|------|---------|
| L | Local register bus only |
| O | OAM channel and local (O implies L) |

### 3.3 Privilege Level

| Code | Meaning |
|------|---------|
| RID | Root NodeID only — only the root node may access via OAM |
| A | Authenticated — only accessible when link is secured |

> **Access control is per-register (and sometimes per-field), not per-domain.** For example, `3.0001 securityPolicy` is `RO L RID` (local-only, not OAM-accessible), while most DLL registers are `O RID`. RTL implementation must derive access rules from the per-register metadata table, not from domain alone.

---

## 4. Domain 1 — Physical Layer Registers

### 4.1 Register Map

| Address | Name | Section |
|---------|------|---------|
| 1.0001 | PMA/PMD/PCS capability | 3.2.1 |
| 1.0002 | SGconfig | 3.2.2 |
| 1.0003 | PMA/PMD/PCS capability 2 | 3.2.3 |
| 1.0004 | ConnectivityIdentification | 3.2.4 |
| 1.0005 | ASAversionCapability | 3.2.5 |
| 1.0006 | ASAnodeState | 3.2.6 |
| 1.0007 | SoftReset | 3.2.7 |
| 1.0008 | ASAnodeIRQ | 3.2.8 |
| 1.0020 | MLEcapability1 | 3.2.9 |
| 1.0021 | MLEcapability2 | 3.2.10 |
| 1.0022 | MLEconfig | 3.2.11 |
| 1.0100 | LinkTraining | 3.2.12 |
| 1.0101 | LinkQuality | 3.2.13 |
| 1.0102 | SQI | 3.2.14 |
| 1.0103 | MSE | 3.2.15 |
| 1.0104 | FECstat | 3.2.16 |
| 1.0105 | HarnessDiagnostics | 3.2.17 |
| 1.0106 | DiagnosticsTestCtrl | 3.2.18 |
| 1.0107 | LinkIdentification | 3.2.19 |
| 1.0108 | ExtendedLinkTrainingStatus | 3.2.20 |
| 1.0200–1.0299 | Lane 1 (Link Aggregation) | 4.8 |
| 1.0300–1.0399 | Lane 2 (Link Aggregation) | 4.8 |
| 1.0400–1.0499 | Lane 3 (Link Aggregation) | 4.8 |

### 4.2 Bit-Field Definitions

**1.0001 PMA/PMD/PCS capability** — `RO O RID`
```
15:14  Reserved
13     CapableUpRX2   1: SG2 Up receiver capable
12     CapableUpRX1   1: SG1 Up receiver capable
11     CapableUpTX2   1: SG2 Up transmitter capable
10     CapableUpTX1   1: SG1 Up transmitter capable
9      CapableDnRX5   1: SG5 Dn receiver capable
8      CapableDnRX4   1: SG4 Dn receiver capable
7      CapableDnRX3   1: SG3 Dn receiver capable
6      CapableDnRX2   1: SG2 Dn receiver capable
5      CapableDnRX1   1: SG1 Dn receiver capable
4      CapableDnTX5   1: SG5 Dn transmitter capable
3      CapableDnTX4   1: SG4 Dn transmitter capable
2      CapableDnTX3   1: SG3 Dn transmitter capable
1      CapableDnTX2   1: SG2 Dn transmitter capable
0      CapableDnTX1   1: SG1 Dn transmitter capable
```

**1.0002 SGconfig** — `RW O RID`
```
15:13  Reserved (set to 0)
12:9   ASA Version     0=ASA 1.01 | 1=ASA 1.1 | 2=ASA 2.0 | others reserved
8:7    Aggregated Links  number of links in aggregation; 0 if not supported
6:5    MDI GroupID     uint identifier for port/MDI; checked during startup (4.2.7.1)
4:3    Up SG           0=SG1 | 1=SG2 | others reserved; upstream speed grade
2:1    Dn SG           0=SG1 | 1=SG2 | 2=SG3 | 3=SG4 | 4=SG5; downstream speed grade
0      Reserved
```

**1.0003 PMA/PMD/PCS capability 2** — `RO O RID`
```
15:2   Reserved
1:0    Number of Links   0=single | 1=dual | 2=triple | 3=quad link capable
```

**1.0004 ConnectivityIdentification** — `RO O RID`
```
15:3   Reserved
2      MDI GroupID mismatch error  set if own vs partner GroupID mismatch; clears at PowerOn
1:0    LinkPartner MDI GroupID     0–3: MDI GroupID received during startup
```

**1.0005 ASAversionCapability** — `RO O RID`
```
15:3   Reserved
2      CapableASA2.0    1: capable of ASA 2.0
1      CapableASA1.1    1: capable of ASA 1.1
0      CapableASA1.01   1: capable of ASA 1.01
```

**1.0006 ASAnodeState** — `RO O RID`
```
15:4   Reserved
3:0    ASA Node State
         0: PowerOn / Init
         1: Startup (initial or returning from Light Sleep)
         2: OAM Config
         3: Normal Mode
         4: Test Mode
         5: Light Sleep  (further refined in 3.3.29)
         6: Fail
         7: Deep Sleep
         others: reserved
```

**1.0007 SoftReset** — `RW O RID`
```
15:1   Reserved
0      Soft Reset    High active, self-clearing on write.
                     Resets all state machines and status registers.
                     Configuration registers are KEPT.
                     Applies to the entire ASA node.
```

**1.0008 ASAnodeIRQ** — `SC O RID`
```
15:14  Reserved
13     ASD flag          detected locally
12     ASE flag          detected locally
11     OAM flag          detected locally
10     DLL Receive flag  detected locally
9      DLL Transmit flag detected locally
8      PTB flag          detected locally
7      Security flag     detected locally
6      Remote nodeID flag         (from remote OAM)
5      Remote PMA/PMD/PCS flag    (from remote OAM)
4      Local PMA/PMD/PCS flag
3:0    Reserved
Additional implementation-specific conditions may be tied into the above flags.
```

**1.0020 MLEcapability1** — `RO O RID`
```
15     MLES_sym1G0 capability   1: capable of symmetric 1G0 mode
14     MLES_sym2G5 capability   1: capable of symmetric 2G5 mode
13     MLES_sym5G0 capability   1: capable of symmetric 5G0 mode
12:0   Reserved (set to 0)
```

**1.0021 MLEcapability2** — `RO O RID`  *(per Section 3.2.10)*
```
Contains capability bits for asymmetric MLE modes:
MLES_2G5_M, MLES_5G0_M, MLES_10G_M, MLES_10G_G
(exact layout matches Table 3-13 in the specification)
```

**1.0022 MLEconfig** — `RW O RID`
```
15     MLE asym config   1=DnTX/UpRX | 0=DnRX/UpTX (not applicable for symmetric modes)
14:11  MLE config
         0000: MLES_sym1G0
         0001: MLES_sym2G5
         0010: MLES_sym5G0
         0011–0100: reserved
         0101: MLES_2G5_M
         0110: MLES_5G0_M
         0111: MLES_10G_M
         1000: MLES_10G_G
         1001–1110: reserved
         1111: do not use (startup info compatibility)
10:0   Reserved (set to 0)
```

**1.0100 LinkTraining** — `RO O RID`
```
15:11  LPerrors          Number of ERROR states from link partner during last startup; saturates 0x1F
10     COMready          1: comm ready (after startup); goes low on link loss (see 3.2.13)
9:8    Polarity Detected 00=not evaluated | 01=normal | 10=inverted | 11=failed
7:0    Link Training Time  measured in TDD cycles
```

**1.0101 LinkQuality** — `RO O RID`
```
(see Table 3-16; contains quality indicators for the active link)
```

**1.0102 SQI (Signal Quality Indicator)** — mixed `SC/RO O RID`
```
15:8   Reserved
7:5    Worst case SQI    SC: lowest SQI since last read or last completed startup
4      Reserved
3:1    Current SQI       RO: 0x00 (link loss) to 0x07 (best); BER <10⁻¹² at ≥3 values
0      Reserved
SQI 0x00 ≡ Link Loss condition
```

**1.0103 MSE** — `RO O RID`
```
15:10  Reserved
9      MSEvalid          0=not valid | 1=valid
8:0    MSE               unsigned; mean square error at slicer, scaled 0..511;
                         refreshed every 3–8 TDD cycles
```

**1.0104 FECstat** — `RO O RID`
```
(Table 3-20; FEC correction statistics per TDD cycle interval)
NOTE: Expected to be non-zero in the vast majority of installations.
```

**1.0105 HarnessDiagnostics** — `RO O RID`
```
(Table 3-22; harness diagnostic results — open/short/impedance indicators)
```

**1.0106 DiagnosticsTestCtrl** — `RW L RID`
```
15:5   Reserved
4:1    TestType
         0000: HarnessDiagnostics
         0001: TX Linearity Test
         0010: TX Jitter Test
         0011: TX Droop Test
         0100: TX PSD Test
         0101: TX BER Test
         0110: RX Noise Immunity Test
         0111: RX BER Test
         1000: S11 Termination Test
         1001: Phase1G Loopback Test
         1010–1111: reserved
0      Enable            1=active (immediately disrupts data; starts test/diagnostic mode)
Access: L only (not OAM-accessible)
```

**1.0107 LinkIdentification** — `RO O RID`
```
(Table 3-23; link partner identification received during startup)
```

**1.0108 ExtendedLinkTrainingStatus** — `RO O RID`
```
(Table 3-24; extended link training status fields)
```

---

## 5. Domain 2 — Data Link Layer Registers

### 5.1 Register Map

| Address | Name | Section |
|---------|------|---------|
| 2.0001 | nodeID | 3.3.1 |
| 2.0002 | DLLconfig1 | 3.3.2 |
| 2.0003 | DLLconfig2 | 3.3.3 |
| 2.0004–2.0005 | VendorID | 3.3.4 |
| 2.0006–2.0007 | DeviceID | 3.3.5 |
| 2.0008–2.0133 | DLLaddrtable (63 registers) | 3.3.6 |
| 2.0140 | DLLtransmitErr | 3.3.7 |
| 2.0141 | DLLcounter | 3.3.8 |
| 2.0142 | DLLcountermin | 3.3.9 |
| 2.0143 | DLLcountermax | 3.3.10 |
| 2.0144 | DLLlinemin | 3.3.11 |
| 2.0145 | DLLlinemax | 3.3.12 |
| 2.0146–2.2065 | DLLmappertable | 3.3.13 |
| 2.2066 | DLLmtablelen | 3.3.14 |
| 2.2067–2.2130 | DLLdmxtable1 (64 registers) | 3.3.15 |
| 2.2131–2.2146 | DLLdmxtable2 (16 registers) | 3.3.16 |
| 2.2147 | DLLdmxstatus | 3.3.17 |
| 2.2148 | OAMdmxTX | 3.3.18 |
| 2.2200–2.2202 | PTBclk (48-bit) | 3.3.19 |
| 2.2203 | PTBstatus | 3.3.20 |
| 2.2204–2.2206 | PTBoamClk (48-bit) | 3.3.21 |
| 2.2207 | PTBoamDly | 3.3.22 |
| 2.2208 | OAMerrors1 | 3.3.23 |
| 2.2209 | OAMerrors2 | 3.3.24 |
| 2.2210 | DLLerrors1 | 3.3.25 |
| 2.2211 | DLLerrors2 | 3.3.26 |
| 2.2212 | ExtendedPTBstatus | 3.3.27 |
| 2.2250 | LightSleepCapability | 3.3.28 |
| 2.2251 | LightSleepStatus1 | 3.3.29 |
| 2.2252 | LightSleepStatus2 | 3.3.30 |
| 2.2253 | LightSleepTest1 | 3.3.31 |
| 2.2254–2.2256 | LightSleepTest2 | 3.3.32 |

### 5.2 Bit-Field Definitions

**2.0001 nodeID** — `RW O RID`
```
15:5   Reserved
4:0    nodeID   unsigned integer
                0 = nodeID unset
                1 = root node
                2–31 = leaf or branch device nodes
```

**2.0002 DLLconfig1** — `RO O RID`
```
15:10  Nr_DLP_TX   unsigned; number of supported DLP_TX
9:4    Nr_DLP_RX   unsigned; number of supported DLP_RX
3:0    Reserved
```

**2.0003 DLLconfig2** — `RO O RID`
```
15:4   Reserved
3      CapableKey256    1: 256-bit keys supported
2      CapableKey128    1: 128-bit keys supported
1      CapableSecEnc    1: security encryption capable
0      CapableSecAuth   1: security authentication capable
```

**2.0004–2.0005 VendorID** — `RO O RID`
```
2.0004  vendorID[15:0]   implementer-defined
2.0005  vendorID[31:16]
```

**2.0006–2.0007 DeviceID** — `RO O RID`
```
2.0006  deviceID[15:0]   implementer-defined
2.0007  deviceID[31:16]
```

**2.0008–2.0133 DLLaddrtable** — `RW O RID`
```
63 registers, two per DLP_TX/streamID.
First register per streamID:
  15:14  Reserved
  13     valid_targetID0   1: targetID0 set
  12:8   targetID0         targetID0 for this DLP_TX
  7:6    Reserved
  5      valid_targetID1   1: targetID1 set
  4:0    targetID1         targetID1 for this DLP_TX
```

**2.0140 DLLtransmitErr** — `SC O RID`
```
15:12  Reserved
11:6   DLPaddrErr    DLP_TX_ID selected for TX but has no address table entry
5:0    DLPmapperErr  DLP_TX_ID evaluated by Mapper but not implemented in node
```

**2.0141 DLLcounter** — `RO O RID`
```
15:0   DLLcounter   current mapper counter value; only changes when mapper is evaluated
```

**2.0142 DLLcountermin** — `RW O RID`
```
15:0   DLLcountermin   minimum/reset value of DLLcounter; resets to 0x0000
```

**2.0143 DLLcountermax** — `RW O RID`
```
15:0   DLLcountermax   maximum/rollover value of DLLcounter; resets to 0x0000
```

**2.0144 DLLlinemin** — `RW O RID`
```
15:0   DLLlinemin   lower index pointer into mapper table; resets to 0
```

**2.0145 DLLlinemax** — `RW O RID`
```
15:0   DLLlinemax   upper index pointer into mapper table; resets to 0
```

**2.0146–2.2065 DLLmappertable** — `RW O RID`
```
Mapper table entries; format per Table 3-43/3-44.
Bit 15: valid  1: entry valid
Bits 14:9: DLP_TX_ID  (per entry)
Bits 8:0: counter value for this entry
```

**2.2066 DLLmtablelen** — `RO O RID`
```
15:10  Reserved
9:0    DLLmtablelen   unsigned; number of implemented mapper table lines; max 640
```

**2.2067–2.2130 DLLdmxtable1** — `RW O RID`
```
64 registers, one per DLP_TX_ID/streamID.
Bit 15: valid  1: entry valid
Bits 14:9: DLP_RX_ID to demultiplex to (local sink)
Bits 8:3: reserved
Bit 2: forward  1: forward this container
Bits 1:0: reserved
```

**2.2131–2.2146 DLLdmxtable2** — `RW O RID`
```
16 registers, two targetIDs per register.
Bits 15:14: Reserved
Bit 13: IDvalid (upper)   1: upper targetID set
Bits 13:8: DLP_RX_ID (upper)
Bits 7:6: Reserved
Bit 5: IDvalid (lower)    1: lower targetID set
Bits 5:0: DLP_RX_ID (lower)
```

**2.2147 DLLdmxstatus** — `SC O RID`
```
15:8   LocalError    uint8; demux errors for local sinks since last read; saturates 0xFF; resets 0
7:0    ForwardError  uint8; demux errors for forwarding since last read; saturates 0xFF; resets 0
```

**2.2148 OAMdmxTX** — `RW O RID`
```
(Table 3-56; OAM demux transmit configuration)
```

**2.2200–2.2202 PTBclk** — `RW O RID`
```
2.2200  PTBclk[15:0]   48-bit Precision Time Base clock counter
2.2201  PTBclk[31:16]
2.2202  PTBclk[47:32]
```

**2.2203 PTBstatus** — `RO O RID`
```
15:13  Reserved
12:9   PTBoffset   int3 sign-magnitude; calculated follower clock offset; range −7..+7;
                   0x08 = PTB update error / invalid
8      PTBlocked   0: not locked / leader without valid reference
                   1: locked to leader / leader has valid timing reference
7:0    PTBdelay    uint8; calculated cable latency in PTB ticks
```

**2.2204–2.2206 PTBoamClk** — `RO O RID`
```
2.2204  PTBoamClk[15:0]   48-bit timestamp from last received OAM frame
2.2205  PTBoamClk[31:16]
2.2206  PTBoamClk[47:32]
```

**2.2207 PTBoamDly** — `RO O RID`
```
15:0   PTBoamDly   calculated cable delay from OAM exchange
```

**2.2208 OAMerrors1** — `SC O RID`
```
15:8   OAM header decode error    accumulated OAMHEADER_DECODE_ERR since reset/readout; sat 0xFF
7:0    OAM header duplicate frame ID error   accumulated OAMHEADER_DUPLID_ERR; sat 0xFF
```

**2.2209 OAMerrors2** — `SC O RID`
```
(Table 3-59; additional OAM error counters)
```

**2.2210 DLLerrors1** — `SC O RID`
```
(Table 3-61; DLL receive error counters — CRC errors, packetID errors)
```

**2.2211 DLLerrors2** — `SC O RID`
```
15:8   DLL header missing packetID error   accumulated missing_packetID since reset; sat 0xFF
7:0    Reserved
```

**2.2212 ExtendedPTBstatus** — `RO O RID`
```
(Table 3-64; extended PTB status — additional timing diagnostics)
```

**2.2250 LightSleepCapability** — `RO O RID`
```
(Table 3-65; indicates which Light Sleep features the node supports)
```

**2.2251 LightSleepStatus1** — mixed `RO/SC O RID`
```
15     LSstatus1 valid         0=not valid | 1=register content valid
14:9   LightSleep denied       SC: accumulated LSdeny received since reset; sat 0x3F
8:3    LightSleep announced    SC: accumulated LSannounce received since reset; sat 0x3F
2      Reserved
1:0    LightSleep status       0=normal mode | 1=Light Sleep | 2=entering | 3=exiting
```

**2.2252 LightSleepStatus2** — mixed `RO/SC O RID`
```
(Table 3-67; additional Light Sleep phase counters and status)
```

**2.2253 LightSleepTest1** — `RW O RID`
```
(Table 3-68; Light Sleep test control register)
```

**2.2254–2.2256 LightSleepTest2** — mixed `RO/SC O RID`
```
2.2254:
  15     LSstatus2 valid         0=not valid | 1=register content valid
  14:11  LightSleep impossible   SC: accumulated LSpossible=FALSE since reset; sat 0x0F
  10:6   Impossible node         nodeID causing last LSpossible=FALSE
  5:1    LightSleep executed     SC: number of LS cycles since reset; sat 0x1F
  0      Reserved
2.2255–2.2256: additional test timing fields (Table 3-70/71)
```

---

## 6. Domain 3 — Security Registers

| Address | Name | R/W | Access | Priv |
|---------|------|-----|--------|------|
| 3.0001 | securityPolicy | RO | **L** | RID |
| 3.0002 | droppedContainersSecRX | SC | O | RID |
| 3.0003 | droppedContainersSecTX | SC | O | RID |

**3.0001 securityPolicy** — `RO L RID`  *(local-only — not OAM-accessible)*
```
15:2   Reserved
1:0    securityPolicy
         0b00: No Security
         0b01: Authentication only
         0b11: Authentication and Encryption
         0b10: Reserved
```

**3.0002 droppedContainersSecRX** — `SC O RID`
```
15:0   droppedContainersSecRX   saturating count of RX containers dropped/rejected by security
```

**3.0003 droppedContainersSecTX** — `SC O RID`
```
15:0   droppedContainersSecTX   saturating count of TX containers dropped/rejected by security
```

---

## 7. Domain 4 & 5 — ASE / ASD Registers

### 7.1 Address Format
- Domain 4 = ASE (Application Stream Encapsulator), domain 5 = ASD (Decapsulator)
- Subdomain `i` = DLP port ID, range 1–63
- Address `4.i.a` or `5.i.a`

### 7.2 Common ASEP Registers (all stream types)

| Address | Name | R/W | Access | Priv |
|---------|------|-----|--------|------|
| 4/5.i.0001–0003 | fullPacketID[47:0] | RO | O | RID |
| 4/5.i.0004 | ASEP Stream Type | RO | O | RID |
| 4/5.i.0005 | ASEP Stream VendorID | RO | O | RID |
| 4/5.i.0006 | ASEP Test | RW | **L** | RID |
| 4/5.i.0051 | Quad-Pin Capability | RO | O | RID |
| 4/5.i.0052 | Trio-Pin Capability | RO | O | RID |
| 4/5.i.0053–0054 | Duo-Pin Capability | RO | O | RID |
| 4/5.i.0055–0058 | Single-Pin Capability | RO | O | RID |
| 4/5.i.0059–0062 | Pin Config | RW | O | RID |

**4/5.i.0001–0003 fullPacketID[47:0]**
```
Three 16-bit registers forming a 48-bit counter.
Incremented per DLP_TX container sent; lower 5 bits copied to container header (5.2.2.4).
At receiver: incremented per correctly received container (5.3.2.1).
```

**4/5.i.0004 ASEP Stream Type** — `RO O RID`
```
15:7   Reserved
6:0    streamType   as listed in Table 7-1
```

**4/5.i.0005 ASEP Stream VendorID** — `RO O RID`
```
15:0   streamVendorID   vendor-defined; further identifies stream among same types
```

**4/5.i.0006 ASEP Test** — `RW L RID`  *(local-only)*
```
15:1   Reserved
0      ASEP Test enable   1=test mode on (see 3.6.3 for ASE sub-modes; TestDummy in 7.11)
```

**4/5.i.0059–0062 Pin Config** — `RW O RID`
```
4 registers, one for each group of 4 pins.
Bits 15:8  Pin active select  1xxx_xxxx=quad | 01xx_xxx0=trio | 01xx_xxx1=trio+single |
                              0010_xx00=upper duo | etc.
Bits 7:0   Pin function assignment per group
```

### 7.3 Stream-Specific Registers (address 4/5.i.0200+)

These registers exist only when the stream type supports them:

**I2C (streamType=I2C)**

| Address | Name | Description |
|---------|------|-------------|
| 4/5.i.0200 | I2C clock rate | `RW O RID`; bits 5:0 = rate in multiples of 100kHz; 0x00 resets I2C |
| 4/5.i.0201–0208 | I2C slave addresses | 8 registers; two 7-bit slave addresses per register with 8/16-bit offset flag |

**SPI (streamType=SPI)**

| Address | Name | Description |
|---------|------|-------------|
| 4/5.i.0200 | SPI Configuration | `RW O RID`; bits 13:4=SCK freq (100kHz units); bits 3:2=Tx mode; bits 1:0=SPI mode (CPOL/CPHA) |
| 4/5.i.0201 | SPI Minimum Idle | `RW O RID`; bits 7:0=idle period lower bound in 16ns units |

**GPIO (streamType=GPIO)**

| Address | Name | Description |
|---------|------|-------------|
| 4/5.i.0200 | GPIO Sampling | `RW O RID`; bit 13=mode (0=full sampling, 1=edge); bits 12:0=sampling period in PTB ticks |
| 4/5.i.0201–0216 | GPIO Pin Config | `RO/RW O RID`; 16 registers, one per GPIO pin; availability, direction, default behavior |

**I2S (streamType=I2S)**

| Address | Name | Description |
|---------|------|-------------|
| 4/5.i.0200 | I2S Data Format | `RW O RID`; bits 11:8=bit depth (0=8b..5=32b); bits 6:4=format (I2S/left-justified/right-justified/TDM) |
| 4/5.i.0201 | I2S Audio Sample Rate | `RW O RID` |
| 4/5.i.0202–0203 | I2S Sampling Sync | `RW O RID` |

---

## 8. RTL Micro-Architecture

### 8.1 Internal Address Bus (decoded)

The local/OAM address must be decoded into structured fields before routing. A 16-bit flat bus is insufficient to represent ASE/ASD addresses.

```
domain[2:0]           — which register bank
subdomain_dlp_id[5:0] — ASE/ASD only (0 for d=0..3)
register_addr[14:0]   — register number within domain
bit_m[3:0]            — MSB for bit-field access (optional)
bit_l[3:0]            — LSB for bit-field access (optional)
has_bit_select        — 1 if bit-field access
write_data[15:0]
wr_en
rd_en
src_nodeID[4:0]       — OAM path only; checked against RID privilege
authenticated         — OAM path only; checked for A-privileged registers
```

### 8.2 Block Diagram

```
                      OAM CAD Read/Write
                       (from DLL 5.5.3)
                             │
              ┌──────────────▼──────────────┐
              │       OAM Register Bridge    │
              │  - decodes OAM CAD encoding  │
              │  - extracts domain/addr/data │
              │  - passes src_nodeID         │
              └──────────────┬──────────────┘
                             │
         Local Register Bus  │
         (I2C/MDIO or        │
          proprietary)        │
              │               │
              └───────┬───────┘
                      ▼
          ┌───────────────────────┐
          │    Address Decoder    │
          │  d.a / d.i.a / bitsel │
          └───────────┬───────────┘
                      │
          ┌───────────▼───────────┐
          │   Access Control Unit │
          │  - L vs O channel     │
          │  - RID privilege      │
          │  - A privilege        │
          │  - per-register rules │
          └───────────┬───────────┘
                      │
     ┌────────────────┼────────────────┐
     │                │                │
     ▼                ▼                ▼
┌─────────┐    ┌─────────────┐   ┌─────────────────────┐
│Domain 0 │    │  Domain 1   │   │ Domain 2            │
│  User   │    │  PHY/MLE    │   │ DLL + PTB + LS      │
│ 0.0001+ │    │ 1.0001–1.04xx│  │ 2.0001–2.2256       │
└─────────┘    └─────────────┘   └─────────────────────┘
                                         │
                           ┌─────────────┼──────────────┐
                           ▼             ▼              ▼
                    ┌──────────┐  ┌──────────┐  ┌──────────────┐
                    │Domain 3  │  │Domain 4  │  │Domain 5      │
                    │Security  │  │  ASE ×63 │  │  ASD ×63     │
                    │3.0001–3  │  │4.i.xxxx  │  │5.i.xxxx      │
                    └──────────┘  └──────────┘  └──────────────┘
                           │
                           ▼
               ┌───────────────────────┐
               │    Side-Effect Engine │
               │  SC: clear-on-read    │
               │  SoftReset: selective │
               │  counter saturate     │
               │  write-one-trigger    │
               └───────────────────────┘
```

### 8.3 Sub-Module Descriptions

**Address Decoder**
- Parses `d.a.(m:l)` or `d.i.a.(m:l)` format
- Validates domain (0–5), subdomain (1–63 for d=4/5)
- Extracts bit-field select for partial register access
- Routes to the correct domain register bank

**Access Control Unit**
- Enforces L vs O channel per register (not per domain)
- Checks RID privilege: source must be nodeID=1 (root)
- Checks A privilege: link must be in authenticated state
- Generates access-violation error for denied accesses
- Uses a per-register metadata table, not a domain lookup

**Side-Effect Engine**
- SC registers: capture value on write; return and clear on read
- SoftReset: applies to state machines and status only; skips config registers
- Counter registers (OAMerrors, DLLerrors, LightSleepStatus): saturating increment
- Write-one-trigger (SoftReset, DiagnosticsTestCtrl Enable): acts on rising edge

**Reset Controller**
- Monitors SoftReset (1.0007)
- Resets: all SC registers, all state-machine state, all status registers
- Preserves: all configuration registers (SGconfig, DLLconfig, MLEconfig, etc.)
- Updates ASAnodeState (1.0006) during and after reset sequence

**OAM CAD Bridge**
- Receives Read/Write commands from DLL OAM parser (Section 5.5.3)
- Decodes CAD address format (AddressDomain + optional DLP_ID + 15-bit address)
- Drives the internal address bus with src_nodeID and authenticated signals
- Returns read data via OAM Return command

---

## 9. Reset Values Summary

| Register | Reset value | Type |
|----------|-------------|------|
| 1.0006 ASAnodeState | 0 (PowerOn/Init) | RO |
| 1.0007 SoftReset | 0 | SC |
| 2.0001 nodeID | 0 (unset) | RW |
| 2.0142 DLLcountermin | 0x0000 | RW |
| 2.0143 DLLcountermax | 0x0000 | RW |
| 2.0144 DLLlinemin | 0 | RW |
| All SC error counters | 0 | SC |
| All PTB registers | 0 | RW/RO |
| 3.0001 securityPolicy | hardware-determined | RO |
| All ASE/ASD stream config | 0 unless specified | RW |
| All config registers | 0 unless specified | RW |

---

## 10. Interface Specifications

### 10.1 Local Register Bus
```
Inputs:
  domain[2:0]           decoded domain
  subdomain[5:0]        DLP ID for ASE/ASD; 0 for d=0..3
  reg_addr[14:0]        register number
  bit_m[3:0], bit_l[3:0], has_bit_select
  wr_data[15:0]
  wr_en, rd_en

Outputs:
  rd_data[15:0]
  ack                   operation complete
  err_access            access violation (wrong channel/privilege)
  err_addr              invalid address
```

### 10.2 OAM Register Interface
```
Inputs:
  oam_domain[2:0]       from OAM CAD AddressDomain field
  oam_dlp_id[5:0]       from OAM CAD (ASE/ASD only)
  oam_addr[14:0]        from OAM CAD address field
  oam_wr_data[15:0]     for Write commands
  oam_wr_en             for Write command
  oam_rd_en             for Read command
  src_nodeID[4:0]       nodeID of sending node (for RID check)
  authenticated         security state of OAM session

Outputs:
  oam_rd_data[15:0]     for Return command
  oam_ack
  oam_err               generates OAM ReadError response
```

---

## 11. What This Document Does Not Cover

This document is the register subsystem only. Separate micro-architecture documents are required for:

- Physical Layer Gen2020 startup state machines (Section 4.3.3)
- Physical Layer MLE modes and electrical constraints (Sections 4.4, 8)
- DLL framing, packet IDs, mapper evaluation, OAM command processor (Section 5)
- PTB clock synchronization algorithm (Section 4.2.8)
- Light Sleep negotiation state machine (Section 5.8)
- Security entity: key hierarchy, AES-128-GCM, IV construction, KeyEx primitives (Section 6)
- ASEP stream encapsulation/decapsulation logic (Section 7)
- Waveforms, timing compliance, diagnostic test flows (Section 4.4)

---

## 12. References

1. ASA Technical Specification v2.0, Section 3 (pages 28–92)
2. Section 4.2.7.1 — SGconfig use during startup (MDI GroupID check)
3. Section 4.8 — Link Aggregation register lanes (1.0200–1.0499)
4. Section 5.5.3 — OAM CAD Read/Write/Return commands
5. Section 5.8 — Light Sleep state machine (reads LightSleepStatus/Test registers)
6. Section 6 — Security entity (reads/writes securityPolicy and dropped container counters)
7. Table 7-1 — ASEP streamType enumeration
8. `pipeline/out/asa_structured_chunks.jsonl` — structured extraction source
