# Micro-Architecture: DLL Mapper/Demux Core

## 1. Purpose and Scope

The Data Link Layer (DLL) Mapper/Demux Core is the scheduling and routing engine at
the heart of ASA packet transport. It provides:

- TX: Deterministic time-division multiplexing of up to 64 DLP_TX ports onto a
  single PLP_TX (Physical Layer) using a programmable cyclic Mapper
- TX: Container header generation (HeaderType, nodeID, streamID, targetID, packetID)
- RX: Header decode and demultiplexing to the correct DLP_RX port (local sink,
  forward, OAM, enumeration)
- RX: PacketID sequence tracking and duplicate/missing detection
- Error counting for DLL header decode failures and demux lookup misses

This document defines the micro-architecture for RTL/golden-model implementation.

Scope:
- IN SCOPE: Mapper table, mapper counter, mapper evaluation step, mapper init,
  DLP_TX.indicateSlot generation, container header assembly, address table, demux
  table 1 and 2, OAMdmxTX, packetID tracking, error counters, all DLL registers,
  DLP_TX and DLP_RX primitive interfaces
- OUT OF SCOPE: OAM CAD processing (see micro-architecture-oam-control-plane.md),
  PTB clock internals (see micro-architecture-ptb-clock-service.md), Security
  AES-GCM engine, Branch Forwarding Fabric implementation details (Section 5.4),
  ASEP packet formatting (Section 7)

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 3.3 | DLL Registers (overview table) | 45-46 | Register address map |
| 3.3.1 | NodeID (2.0001) | 47 | Own node address |
| 3.3.2 | DLLconfig1 (2.0002) | 47 | Nr_DLP_TX, Nr_DLP_RX |
| 3.3.3 | DLLconfig2 (2.0003) | 48 | Security capabilities |
| 3.3.6 | DLLaddrtable (2.0008-2.0133) | 49-51 | targetID0-3 per DLP_TX |
| 3.3.7 | DLLtransmitErr (2.0140) | 52 | Mapper/address error |
| 3.3.8 | DLLcounter (2.0141) | 52 | Current mapper counter |
| 3.3.9 | DLLcountermin (2.0142) | 52 | Mapper counter min/reset |
| 3.3.10 | DLLcountermax (2.0143) | 52 | Mapper counter max |
| 3.3.11 | DLLlinemin (2.0144) | 52 | Mapper table lower index |
| 3.3.12 | DLLlinemax (2.0145) | 52 | Mapper table upper index |
| 3.3.13 | DLLmappertable (2.0146-2.2065) | 53-54 | 1920 registers, 640 lines |
| 3.3.14 | DLLmtablelen (2.2066) | 54 | Implemented table size |
| 3.3.15 | DLLdmxtable1 (2.2067-2.2130) | 55-57 | 64 DLP_RX nodeID.streamID |
| 3.3.16 | DLLdmxtable2 (2.2131-2.2146) | 58 | 16 regs, targetID->DLP_RX |
| 3.3.17 | DLLdmxstatus (2.2147) | 59 | Demux error counters |
| 3.3.18 | OAMdmxTX (2.2148) | 59 | OAM far-side connection |
| 3.3.25 | DLLerrors1 (2.2210) | 61 | Header decode + dup pkt |
| 3.3.26 | DLLerrors2 (2.2211) | 61 | Missing packet ID |
| 5.1 | Data Link Layer Overview | 162 | Figure 5-1, port counts |
| 5.2 | DLL Transmit Functions | 163 | Figure 5-2, 5-3 |
| 5.2.1 | DLL Transmit Process | 163 | 6-step TX sequence |
| 5.2.2 | Header Generation & Addressing | 164 | Table 5-1 header fields |
| 5.2.3 | Mapping/Multiplexing | 165 | Mapper description |
| 5.2.3.1 | Configurability | 165 | Objects, cycle length |
| 5.2.3.2 | Mapper Initialization | 166 | Counter=CounterMin |
| 5.2.3.3 | Mapper Evaluation Step | 166 | Figure 5-4 pseudocode |
| 5.3 | DLL Receive Functions | 167 | Figure 5-4 |
| 5.3.1 | DLL Receive Process | 167 | RX 2-step process |
| 5.3.2 | Header Decoding & Demultiplexing | 167-168 | 6 decode cases |
| 5.4 | Forwarding Fabric | 169 | Figure 5-5, FoFa interface |
| 5.6 | DLP_TX Interface Primitives | 185-187 | All TX primitives |
| 5.7 | DLP_RX Interface Primitives | 187-188 | All RX primitives |
| 5.9 | DLL Startup, OAM Config | 193 | Default table values |
| 7.1 | ASEP Stream Types | 231 | Table 7-1 stream types |

Image references (from PDF pages 162-169):
- Figure 5-1 (p162): DLL block with DLP_TX/DLP_RX, OAM entity, Security entity,
  PLP_TX/PLP_RX interfaces
- Figure 5-2 (p163): Container header fields (Extended ID, nodeID, streamID, targetID,
  packetID, Header Extension for multicast)
- Figure 5-3 (p163): Container payload for unsecured vs secured links (PPF+Counter+
  DLL Payload+ICV)
- Figure 5-4 (p167): Mapper initialization and evaluation step pseudocode
- Figure 5-5 (p169): Forwarding Fabric with DataForwardingQueue and OAMreturnQueue

---

## 3. System Overview ASCII Block Diagram

```
                +------------------------------------------------+
                |              dll_core_top                        |
                |                                                  |
                |   TX PATH                                        |
PCS trigger  -->| +----------+   +----------+   +-------------+   |
(per phy block) | |dll_tx_   |   |dll_mapper|   |dll_counter_ |   |
                | |scheduler |<->|_eval     |<->|ctrl         |   |
                | +----+-----+   +----------+   +-------------+   |
                |      | DLP_TX_ID_select                         |
                |      v                                           |
                | +----+--------+   +--------------------+        |
                | |dll_header   |<--|dll_addr_table      |        |
                | |_gen         |   |(DLLaddrtable 2.003)|        |
                | +----+--------+   +--------------------+        |
                |      | container (hdr + payload)                |
                |      v                                           |
                |   PLP_TX (to PHY)                               |
                |                                                  |
                |   RX PATH                                        |
PLP_RX      --->| +----+--------+   +--------------------+        |
(per container) | |dll_rx_      |-->|dll_demux_table1    |        |
                | |header_decode|   |(nodeID.streamID)   |        |
                | +----+--------+   +--------------------+        |
                |      |            +--------------------+        |
                |      +---------->|dll_demux_table2    |        |
                |      |            |(targetID->DLP_RX_ID)|       |
                |      |            +--------------------+        |
                |      |                                          |
                | +----+------------+   +--------------------+    |
                | |dll_packet_id_   |   |dll_error_counters  |    |
                | |tracker          |   |(2.2210, 2.2211,    |    |
                | +----------------+    | 2.2147, 2.0140)    |    |
                |                      +--------------------+    |
                |   COMMON                                        |
                | +-------------------------------+               |
                | |dll_register_adapter           |<-- OAM Writes|
                | |(all DLL registers via domain 2)|              |
                | +-------------------------------+               |
                +------------------------------------------------+

DLP_TX[0..63] <--> indicateSlot / dataUnit / oamUnit / yield / forwardUnit
DLP_RX[0..63] <--> dataUnit / forwardUnit / oamUnit
```

---

## 4. DLL Register Map

SPEC FACT (Section 3.3, p45-46):

```
Address      Register Name       Section  Type
2.0001       NodeID              3.3.1    RW O RID
2.0002       DLLconfig1          3.3.2    RO O RID
2.0003       DLLconfig2          3.3.3    RO O RID
2.0004-5     VendorID            3.3.4    RO O RID
2.0006-7     DeviceID            3.3.5    RO O RID
2.0008-0133  DLLaddrtable        3.3.6    RW O RID  (63 regs, 2 per DLP_TX)
2.0134-0139  reserved
2.0140       DLLtransmitErr      3.3.7    SC O RID
2.0141       DLLcounter          3.3.8    RO O RID
2.0142       DLLcountermin       3.3.9    RW O RID
2.0143       DLLcountermax       3.3.10   RW O RID
2.0144       DLLlinemin          3.3.11   RW O RID
2.0145       DLLlinemax          3.3.12   RW O RID
2.0146-2065  DLLmappertable      3.3.13   RW O RID  (1920 regs, 640 lines)
2.2066       DLLmtablelen        3.3.14   RO O RID
2.2067-2130  DLLdmxtable1        3.3.15   RW O RID  (64 regs, 1 per DLP_RX)
2.2131-2146  DLLdmxtable2        3.3.16   RW O RID  (16 regs, 2 targetIDs each)
2.2147       DLLdmxstatus        3.3.17   SC O RID
2.2148       OAMdmxTX            3.3.18   RW O RID
```

### 4.1 NodeID (2.0001)

```
Bits 15:5  Reserved
Bits 4:0   nodeID  RW
  0 = nodeID unset
  1 = root node
  2-31 = leaf/branch nodes
```

### 4.2 DLLconfig1 (2.0002)

```
Bits 15:10  Nr_DLP_TX  RO  Number of supported DLP_TX ports
Bits 9:4    Nr_DLP_RX  RO  Number of supported DLP_RX ports
Bits 3:0    Reserved
```

### 4.3 DLLcounter, DLLcountermin, DLLcountermax

```
2.0141 DLLcounter[15:0]   RO  Current counter; changes only on mapper evaluation
2.0142 DLLcountermin[15:0] RW  Min/Reset value; resets to 0x0000
2.0143 DLLcountermax[15:0] RW  Max/Rollover value; resets to 0x0000
```

Mapper cycle length = CounterMax - CounterMin + 1

### 4.4 DLLlinemin, DLLlinemax (2.0144, 2.0145)

```
2.0144 DLLlinemin[15:0]  RW  Lower index into mapper table; resets to 0
2.0145 DLLlinemax[15:0]  RW  Upper index into mapper table; resets to 0
                              Cannot exceed DLLmtablelen (2.2066)
```

### 4.5 DLLmtablelen (2.2066)

```
Bits 15:10  Reserved
Bits 9:0    DLLmtablelen  RO  Implemented number of mapper table lines (max 640)
```

DLLlinemax must not exceed DLLmtablelen. This is a hardware constraint on the
physical table depth.

### 4.6 DLLtransmitErr (2.0140)

```
Bits 15:12  Reserved
Bits 11:6   DLPaddrErr   SC  DLP_TX_ID selected for TX but has no entry in addr table
Bits 5:0    DLPmapperErr SC  DLP_TX_ID evaluated by mapper but not implemented in node
```

---

## 5. Container Header Format

### 5.1 Header Structure (Table 5-1, Figure 5-2, p163-164)

SPEC FACT: Basic header (HeaderType=0) = 4 bytes. Extended header (HeaderType=1) = 6 bytes.

```
Byte  d_plp_tx  Bit(s)  Field       Description
0     <0><0>    0       HeaderType  0=basic, 1=extended (multicast)
0     <0><1>    1       KeySwitch   0 if no security; security entity provides value
0     <0><6:2>  6:2     nodeID      Equal to own nodeID
0     <0><7>    7       streamID    Equal to sending DLP_TX_ID

1     <1><4:0>  12:8    targetID[   For HeaderType=0: unicast target address
      <1><7:5>  15:13    12:0]      For HeaderType=1: first multicast target address
2     <2><1:0>  17:16

2     <2><6:2>  22:18   packetID    Lower 5 bits of fullPacketID (3.5.1.1) for DLP_TX_ID
2     <2><7>    23      Reserved

3     <3><7:0>  31:24   Reserved

--- Extended header only (HeaderType=1): ---
4     <4><0>    32      Reserved
4     <4><5:1>  37:33   targetID1   Second multicast address
4     <4><7:6>  39:38   targetID2   Third multicast address (bits 1:0)
5     <5><2:0>  42:40   targetID2   (bits 4:2)
5     <5><7:3>  47:43   targetID3   Fourth multicast address
```

### 5.2 ExtendedID

SPEC FACT (Section 5.2.2.2): "The combination of nodeID.streamID is also called
extendedID. It is unique in the SerDes Branch by construction."

### 5.3 HeaderType Selection Rules

SPEC FACT (Section 5.2.2.1):
- If only targetID0 is set in DLLaddrtable (3.3.6): use basic header (HeaderType=0)
- If more than targetID0 is set in DLLaddrtable: use extended header (HeaderType=1)
- For OAM: targetID or targetIDs supplied by primitive 5.6.1.3 (ndEn flag)

### 5.4 Secured vs Unsecured Container Payload (Figure 5-3)

```
Unsecured:
  [Container Header][DLL Payload]

Secured:
  [Container Header][P=1][reserved 6:0][Counter (lower byte)][DLL Payload (secured)][ICV]
                                        ^-- Security overhead reduces usable payload
```

SPEC FACT: Secured payloads are smaller. DLP_TX.indicateSlot size values reflect this:
- Dn_P2P = 638 bytes (unsecured), Dn_P2P_Sec = 620 bytes (secured)
- Up_P2P = 208 bytes (unsecured), Up_P2P_Sec = 190 bytes (secured)

---

## 6. TX Path: Mapper Architecture

### 6.1 Mapper Table Structure (3.3.13, 2.0146-2.2065)

SPEC FACT (Section 3.3.13, p53): "The mapper table at its maximum size for 64 DLP_TX
is distributed over 1920 registers, three per mapper table line."

Each LINE occupies 3 consecutive registers:

```
Register 1: BitMask[15:0]       -- RW O RID
Register 2: CompareValue[15:0]  -- RW O RID
Register 3: DLP_TX_ID_toSend[5:0] (bits 5:0, rest reserved) -- RW O RID
```

Address calculation for LINE n (0-indexed):
```
First register of LINE n = 2.0146 + (n * 3)
Maximum n = 639 (DLLmtablelen max = 640)
```

### 6.2 Mapper Counter

Counter is a 16-bit unsigned value maintained internally and exposed read-only via
register 2.0141 (DLLcounter).

Counter range: [CounterMin .. CounterMax] inclusive.
Cycle length = CounterMax - CounterMin + 1.

### 6.3 Mapper Initialization (Section 5.2.3.2)

SPEC FACT (p166): "At initialization, the Counter is set to CounterMin."

Triggered by:
- StartTDD command (OAM CAD, see 5.5.3.9)
- SoftReset (resets mapper state, counter returns to CounterMin)
- Node entering Normal Mode state

```
LINES = MapperTable[LineMin : LineMax]
Counter = CounterMin
```

### 6.4 Mapper Evaluation Step (Section 5.2.3.3, Figure 5-4)

SPEC FACT: Evaluation is triggered by each container transmit opportunity (each
physical layer block in PCS Transmit Process, via primitive 4.6.1.2).

```
-- Pseudocode (Figure 5-4, p167) --

Initialization:
  counter = counter_min
  LINES = MapperTable[LineMin:LineMax]

Evaluation Step:
  DLP_TX_ID_select = 0                        // default: OAM

  foreach LINE in LINES:
    LINE_sel = (Counter & LINE.BitMask == LINE.CompareValue) ? 1 : 0
    if (LINE_sel == 1) breakloop
    DLP_TX_ID_select = LINE.DLP_TX_ID_toSend

  Counter++
  if (Counter > CounterMax) then Counter = CounterMin
```

SPEC FACT: "If no LINE has evaluated TRUE, the default value DLP_TX_ID=0 (OAM) is used."
SPEC FACT: "This section is a description of a mandatory functional behavior based on
the configured register values. However, it does not mandate an implementation."

### 6.5 DLP_TX.indicateSlot Generation

After evaluation yields DLP_TX_ID_select, the DLL polls that port:

SPEC FACT (Section 5.2.1, step b): "That DLP_TX_ID is polled with primitive
DLP_TX.indicateSlot (see 5.6.1.1)"

Size selection for indicateSlot depends on:
- Direction (Dn/Up): determined by topology configuration
- Stream type: P2P or MC (multicast, if targetID1/2/3 set)
- Security: secured or unsecured (from security entity state)
- OAM slot: always OAM_frame (188 bytes) regardless of direction

```
Size encoding (Section 5.6.1.1.1):
  Dn_P2P     = 638 bytes  (downstream point-to-point, unsecured)
  Dn_P2P_Sec = 620 bytes  (downstream P2P, secured)
  Dn_MC      = 636 bytes  (downstream multicast, unsecured)
  Dn_MC_Sec  = 618 bytes  (downstream multicast, secured)
  Up_P2P     = 208 bytes  (upstream P2P, unsecured)
  Up_P2P_Sec = 190 bytes  (upstream P2P, secured)
  Up_MC      = 206 bytes  (upstream multicast, unsecured)
  Up_MC_Sec  = 188 bytes  (upstream multicast, secured)
  OAM_frame  = 188 bytes  (any direction)
```

### 6.6 Response Handling After indicateSlot

SPEC FACT (Section 5.6.1.1.3): "ASE replies with 5.6.1.2 [dataUnit] or 5.6.1.4
[yield]. OAM always replies with 5.6.1.3 [oamUnit]."

```
DLP_TX_ID polled
        |
        +---> ASEP / FoFa
        |         |
        |    [has data?]
        |         |
        |    YES: DLP_TX.dataUnit(ase_payload)   --> TX continues
        |    NO:  DLP_TX.yield()                 --> fallback to OAM
        |
        +---> OAM (DLP_TX_ID=0)
                  |
             DLP_TX.oamUnit(payload, targetID, packetID, ndEn, targetIDs)
             (always responds, at minimum with OAM header only)

        +---> FoFa
                  |
             DLP_TX.forwardUnit(size, header, payload)
             (DLL uses supplied header unchanged, not constructed)
```

SPEC FACT: If yield is received from ASE, OAM is polled with DLP_TX.indicateSlot
as fallback (Section 5.6.1.4.3: "Instead, OAM is polled with 5.6.1.1").

### 6.7 TX Process Full Pipeline (Section 5.2.1)

SPEC FACT (p163, steps a-f):
```
a) Mapper evaluation step -> DLP_TX_ID_toSend
b) Poll DLP_TX_ID with DLP_TX.indicateSlot(size)
c) Wait for response on that DLP port
d) Construct container header (depends on primitive replied):
   - ASEP: take fields from DLLaddrtable (3.3.6)
   - OAM: take targetID, packetID from oamUnit primitive
   - FoFa: header supplied in full by forwardUnit primitive
e) If security enabled:
   1. Call LinkLayerSec.process_transmit_container (6.3.2.1)
   2. Wait for LLS response:
      i.  LLS.return_processed_tx_container (6.3.2.2) -> continue to f)
      ii. LLS.error_handler (6.3.2.5) -> send all-zeros container
f) Put DLL container to PLP_TX (MSB of first header byte = d_plp_tx<0><7>)
```

---

## 7. TX Path: Address Table and Header Construction

### 7.1 DLLaddrtable Layout (3.3.6, 2.0008-2.0133)

SPEC FACT (Section 3.3.6, p49): 63 registers, 2 per DLP_TX/streamID.

DLP_TX_ID=0 is permanently assigned to OAM (not in address table).
DLP_TX_ID 1-31 map to register addresses per Table 3-35.

For DLP_TX_ID n (1-31):
```
1st register: base = 2.0008 + (n-1)*2
  Bits 15:14  Reserved
  Bit  13     valid_targetID0  (1=set)
  Bits 12:8   targetID0
  Bits 7:6    Reserved
  Bit  5      valid_targetID1  (1=set)
  Bits 4:0    targetID1

2nd register: base + 1
  Bits 15:14  Reserved
  Bit  13     valid_targetID2  (1=set)
  Bits 12:8   targetID2
  Bits 7:6    Reserved
  Bit  5      valid_targetID3  (1=set)
  Bits 4:0    targetID3
```

### 7.2 Header Construction Rules

For ASEP sources (Section 5.2.2):
```
nodeID    = own nodeID (register 2.0001 bits 4:0)
streamID  = DLP_TX_ID (from mapper evaluation)
targetID  = targetID0 from DLLaddrtable[DLP_TX_ID]
packetID  = lower 5 bits of fullPacketID (3.5.1.1) for this DLP_TX_ID;
            increment fullPacketID before using
HeaderType = 0 if only targetID0 valid
           = 1 if any of targetID1/2/3 also valid (multicast)
KeySwitch  = 0 if no security; value from Security entity if present
targetID1/2/3 = from DLLaddrtable 2nd register if valid, else 0
```

For OAM (Section 5.2.2.3, 5.2.2.4, 5.6.1.3):
```
targetID  = from oamUnit primitive
packetID  = from oamUnit primitive (= OAMframeID[4:0])
ndEn      = TRUE for Node-Discover (triggers extended header with targetIDs)
HeaderType = 1 if ndEn=TRUE, else 0
```

For FoFa (Section 5.2.2, 5.6.1.6):
```
Header supplied in full by DLP_TX.forwardUnit -- DLL does not construct it
```

### 7.3 DLLtransmitErr Error Reporting

SPEC FACT (Section 3.3.7):
- `DLPmapperErr[5:0]` (SC): DLP_TX_ID from mapper is not implemented in node
- `DLPaddrErr[11:6]` (SC): DLP_TX_ID has no entry in address table

Both are self-clearing counters -- hardware sets, read clears.

---

## 8. RX Path: Receive Process and Header Decode

### 8.1 RX Process (Section 5.3.1)

SPEC FACT: "When PLP_RX is active, the DLL takes received data container by container
triggered by 4.7.1.1."

```
For each received container:
  a) If security enabled:
     1. Call LinkLayerSec.process_receive_container (6.3.2.3)
     2. Wait for LLS response:
        i.  LLS.return_processed_rx_payload (6.3.2.4) -> execute b)
        ii. LLS.error_handler (6.3.2.5) -> discard, wait for next container
  b) Execute header decode cases (5.3.2)
```

### 8.2 Header Decode and Demultiplexing (Section 5.3.2)

SPEC FACT: "For header decoding, both cases 5.3.2.1 and 5.3.2.2 need to be checked
for all targetID in the header."

"If the header cannot be decoded or does not match any of the cases, 2.2210.15:8
(DLL header decode error) shall be incremented and the container discarded."

#### Case 5.3.2.1 -- Local Sink

```
Condition: targetIDx == NodeID (2.0001) AND targetIDx != 0
Action:    For all DLP_RX_ID in DmxTable1 that match nodeID.streamID of header:
             invoke DLP_RX.dataUnit (5.7.1.1)
PacketID check:
  expected = fullPacketID[4:0]+1 (from 3.5.1.1 for this DLP_RX_ID)
  match:     increment fullPacketID
  too low:   duplicate_packetID -> signal in primitive, increment 2.2210.7:0
  too high:  missing_packetID  -> signal in primitive, increment 2.2211.15:8
Error:     nodeID.streamID not in DmxTable1 -> increment 2.2147.15:8, discard
```

#### Case 5.3.2.2 -- Forward

```
Condition: targetIDx != NodeID AND targetIDx != 0
Action:    Look up DLP_RX_ID for targetID in DmxTable2 (3.3.16)
           invoke DLP_RX.forwardUnit (5.7.1.2)
Error:     targetID unset in DmxTable2 -> increment 2.2147.7:0, discard
```

#### Case 5.3.2.3 -- Receive Node-Discover (Enumeration RX)

```
Condition: HeaderType=1 AND streamID=0 AND targetIDx=0 AND own nodeID=0
Action:    invoke DLP_RX.dataUnit on DLP_RX_ID=0 (OAM)
```

#### Case 5.3.2.4 -- Distribute Node-Discover (Enumeration Forward)

```
Condition: HeaderType=1 AND streamID=0 AND targetIDx=0 AND
           none of targetIDx in header is set in DmxTable2
Action:    For the first DLP_RX_ID with stream type "Data Forward" not in DmxTable2:
           invoke DLP_RX.forwardUnit (5.7.1.2)
```

#### Case 5.3.2.5 -- Receive Self-Announce

```
Condition: HeaderType=1 AND streamID=0 AND targetID0=1
Action:    invoke DLP_RX.dataUnit on DLP_RX_ID=0 (OAM)
```

#### Case 5.3.2.6 -- Forward Self-Announce

```
Condition: HeaderType=1 AND streamID=0 AND targetIDx=1
Action:    Look up DLP_RX_ID for targetID in DmxTable2, invoke DLP_RX.forwardUnit
Error:     targetID unset in DmxTable2 -> increment 2.2147.7:0, discard
```

---

## 9. Demux Table Architecture

### 9.1 DmxTable1 (3.3.15, 2.2067-2.2130)

SPEC FACT (Section 3.3.15, p55): 64 registers, one per DLP_RX_ID.

```
Each register (for DLP_RX_ID i):
  Bits 15:11  Reserved
  Bits 10:6   nodeID   (RW O RID)
  Bits 5:0    streamID (RW O RID)
```

Purpose: map incoming container source (nodeID.streamID from header) to local
DLP_RX_ID. This handles the LOCAL SINK case (5.3.2.1).

Default for register 2.2067 (DLP_RX_ID=0, OAM):
- Root node: nodeID=0, streamID=0 (all-nodes OAM to local OAM)
- Non-root node: nodeID=1, streamID=0 (root OAM to local OAM)

### 9.2 DmxTable2 (3.3.16, 2.2131-2.2146)

SPEC FACT (Section 3.3.16, p58): 16 registers, 2 targetIDs per register.

```
Each register covers two targetIDs:
  Bits 15:14  Reserved
  Bit  13     IDvalid (targetID_high)  (RW O RID)
  Bits 13:8   DLP_RX_ID (targetID_high) (RW O RID)
  Bits 7:6    Reserved
  Bit  5      IDvalid (targetID_low)   (RW O RID)
  Bits 5:0    DLP_RX_ID (targetID_low) (RW O RID)
```

Purpose: map targetID from incoming container to DLP_RX_ID for FORWARD case (5.3.2.2).
Contains all far-side nodes reachable through this DLL.

Register 2.2131 covers targetIDs 2 and 3 (targetID 0 and 1 are reserved/special).
Full mapping: Table 3-53 (p58), targetIDs 2-31 -> registers 2.2131-2.2146.

### 9.3 OAMdmxTX (2.2148)

SPEC FACT (Section 3.3.18, p59):
```
Bits 15:6  Reserved
Bits 5:0   DLP_TX_dmx  RW
  Identifies DLP_RX_ID that OAM is statically connected to (far-side config).
  0 = DLP_TX of OAM is part of this node's mapper operation (near-side).
  Register resets to 0.
```

Used for far-side node OAM routing. Also updated by FoFa:
SPEC FACT (Section 5.6.1.5.3): "If nodeID=0, DLL copies FoFa ReturnPath (3.6.1)
onto register OAMdmxTX."

---

## 10. Error Counters

### 10.1 DLLdmxstatus (2.2147)

```
Bits 15:8  LocalError   SC O RID  Demux errors for local sinks (saturates 0xFF)
Bits 7:0   ForwardError SC O RID  Demux errors for forwarding (saturates 0xFF)
```

Incremented by:
- LocalError (15:8): when nodeID.streamID not found in DmxTable1 (5.3.2.1 error)
  AND when targetID unset in DmxTable2 for forward self-announce (5.3.2.6 error)
- ForwardError (7:0): when targetID unset in DmxTable2 (5.3.2.2 error)

### 10.2 DLLerrors1 (2.2210)

```
Bits 15:8  DLL header decode error   SC O RID  (saturates 0xFF)
Bits 7:0   DLL header duplicate pkt  SC O RID  (saturates 0xFF)
```

- Bits 15:8: incremented when header cannot be decoded or no case matches (5.3.2)
- Bits 7:0: incremented on duplicate_packetID detection (5.3.2.1)

### 10.3 DLLerrors2 (2.2211)

```
Bits 15:8  DLL header missing packetID  SC O RID  (saturates 0xFF)
Bits 7:0   Reserved
```

- Bits 15:8: incremented on missing_packetID detection (5.3.2.1)

---

## 11. PacketID Tracking (Section 3.5.1.1)

SPEC FACT (Section 5.2.2.4): "For ASE: Increment 3.5.1.1 for i=DLP_TX_ID and then
use lower 5 bits fullPacketID[4:0] in the header."

SPEC FACT (Section 5.3.2.1): "Check packetID in received header versus
fullPacketID[4:0]+1 in 3.5.1.1."

PacketID tracking is per DLP_TX_ID on TX side and per DLP_RX_ID on RX side.

```
TX side:
  Per DLP_TX_ID[i]:
    fullPacketID[i][39:0]  (register 4/5.i.0001-0003, 40 bits)
    On each TX: fullPacketID[i]++; header packetID = fullPacketID[i][4:0]

RX side:
  Per DLP_RX_ID[j] (from 3.5.1.1 for the associated stream):
    expected = fullPacketID[j][4:0] + 1 (mod 32)
    received = header.packetID
    if received == expected:   OK, fullPacketID[j]++
    if received < expected:    duplicate_packetID -> signal + DLLerrors1.7:0++
    if received > expected:    missing_packetID   -> signal + DLLerrors2.15:8++
```

---

## 12. Default Table Values for OAM Config

SPEC FACT (Section 5.9, p193): "The default values of Addressing Table, Mapper and
Demultiplexing allow establishing communication via the OAM channel with the link
partner."

After reset, the default configuration allows exactly OAM communication:
- DLLaddrtable: OAM slot (DLP_TX_ID=0) needs no entry (OAM is default)
- DmxTable1[0] (2.2067): root defaults to nodeID=0/streamID=0; non-root to nodeID=1/streamID=0
- DmxTable2: all entries invalid (no forwarding by default)
- Mapper: DLLcountermin=0, DLLcountermax=0 -> single slot -> Counter always 0
  -> all LINES iterate, no match -> DLP_TX_ID=0 (OAM) always selected
- OAMdmxTX: resets to 0 (near-side OAM is part of mapper)

This means immediately after startup, OAM-only communication is operational.

---

## 13. Light Sleep Interaction with Mapper

SPEC FACT (from Light Sleep section in Section 5.7.1.3.3 and 5.8):
"Stops Mapper, extends the quiet gap. PMA TX and RX are disabled."

During Light Sleep:
- Mapper halted: DLP_TX.indicateSlot no longer generated
- Demux inactive: no containers received from PLP_RX
- On wake-up: mapper resumes from current Counter state (unless SoftReset)

IMPLEMENTATION NOTE: The start_tdd_trigger from PTB (when PTBclk >= PTBtime in
StartTDD command) re-arms the mapper after Light Sleep, reusing the same
CounterMin/Max/linemin/linemax configuration.

---

## 14. Forwarding Fabric Interface (Section 5.4)

The Forwarding Fabric is a separate entity connecting two DLL nodes. DLL exposes:

TX side (DLL receives from FoFa):
- `DLP_TX.forwardUnit(size, header, payload)` -- FoFa provides full header+payload
- `DLP_TX.oamFrameLocal(container, phyLerrStat)` -- FoFa signals OAM frame for local

RX side (DLL delivers to FoFa):
- `DLP_RX.forwardUnit(size, header, payload, phyLStat, dllStat)` -- DLL delivers to
  FoFa DataForwardQueue

SPEC FACT (Section 5.4): "The DLP_RX with the stream type 'Data Forward' is always
listed in the DemuxTable2 (3.3.16) of nodeA. The DLP_TX with stream type 'Data
Forward' is always listed in the Mapping Table (3.3.13) of nodeB."

---

## 15. Interfaces

### 15.1 Interface to OAM Control Plane

| Signal | Dir | Description |
|--------|-----|-------------|
| dlp_tx_indicate_oam(size) | DLL->OAM | indicateSlot for OAM slot |
| dlp_tx_oam_unit(payload, targetID, packetID, ndEn, targetIDs) | OAM->DLL | OAM response |
| dlp_rx_oam_unit(size, hdr, payload, phyStat, dllStat) | DLL->OAM | Received OAM container |
| oam_dmx_tx[5:0] | DLL->OAM | Current OAMdmxTX value |

### 15.2 Interface to PTB / StartTDD

| Signal | Dir | Description |
|--------|-----|-------------|
| start_tdd_trigger | PTB->DLL | PTBclk reached StartTDD PTBtime |
| dll_linemin[15:0] | OAM->DLL | LineMin from StartTDD CAD |
| dll_linemax[15:0] | OAM->DLL | LineMax from StartTDD CAD |
| mapper_enable | NSM->DLL | Enable/disable mapper (Light Sleep) |

### 15.3 Interface to Node State Machine

| Signal | Dir | Description |
|--------|-----|-------------|
| normal_mode_active | NSM->DLL | Enable TX/RX processing |
| soft_reset | NSM->DLL | Reset Counter to CounterMin |
| dll_irq | DLL->NSM | DLL error flag for ASAnodeIRQ |

### 15.4 Interface to ASEP Common Layer

| Signal | Dir | Description |
|--------|-----|-------------|
| dlp_tx_indicate(dlp_id, size) | DLL->ASEP | indicateSlot per DLP port |
| dlp_tx_data_unit(dlp_id, payload) | ASEP->DLL | dataUnit response |
| dlp_tx_yield(dlp_id) | ASEP->DLL | yield (no data) |
| dlp_rx_data_unit(dlp_id, size, payload, phyStat, dllStat) | DLL->ASEP | delivered container |

### 15.5 Interface to Branch Forwarding Fabric

| Signal | Dir | Description |
|--------|-----|-------------|
| dlp_tx_forward_unit(size, hdr, payload) | FoFa->DLL | Forward TX data |
| dlp_tx_oam_frame_local(container, phyStat) | FoFa->DLL | Local OAM from FoFa |
| dlp_rx_forward_unit(size, hdr, payload, phyStat, dllStat) | DLL->FoFa | Forward RX data |

### 15.6 Interface to PCS/PHY

| Signal | Dir | Description |
|--------|-----|-------------|
| phy_tx_trigger | PCS->DLL | Physical layer block ready (4.6.1.2) |
| d_plp_tx[7:0] | DLL->PCS | Container bytes (MSB = d_plp_tx<0><7>) |
| plp_rx_container | PCS->DLL | Received container trigger (4.7.1.1) |
| rx_container_bytes | PCS->DLL | Received container bytes |

### 15.7 Interface to Security Entity

| Signal | Dir | Description |
|--------|-----|-------------|
| lls_process_tx(payload) | DLL->Sec | TX container for encryption |
| lls_tx_done(payload) | Sec->DLL | Processed TX payload |
| lls_tx_error | Sec->DLL | TX security error -> send zeros |
| lls_process_rx(container) | DLL->Sec | RX container for decryption |
| lls_rx_done(payload) | Sec->DLL | Decrypted RX payload |
| lls_rx_error | Sec->DLL | RX security error -> discard |
| key_switch | Sec->DLL | KeySwitch bit for container header |

---

## 16. Suggested RTL Module Boundaries

```
+================================================================+
|                       dll_core_top                               |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | dll_tx_scheduler    |    | dll_rx_header_decode|             |
|  |                     |    |                     |             |
|  | Ties mapper eval to |    | Parses container hdr|             |
|  | PHY TX trigger      |    | Routes to dmx tables|             |
|  | Yields-to-OAM logic |    | Handles 6 decode    |             |
|  +---------------------+    | cases (5.3.2.1-6)   |             |
|                             +---------------------+             |
|  +---------------------+                                        |
|  | dll_mapper_eval     |    +---------------------+             |
|  |                     |    | dll_addr_table      |             |
|  | foreach LINE eval:  |    |                     |             |
|  | Counter & BitMask   |    | 63 regs, 2 per port |             |
|  | == CompareValue?    |    | targetID0-3 lookup  |             |
|  | select DLP_TX_ID    |    | header type decision|             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | dll_mapper_table    |    | dll_counter_ctrl    |             |
|  |                     |    |                     |             |
|  | 1920 regs (max)     |    | Counter[15:0]       |             |
|  | 640 lines * 3 regs  |    | CounterMin/Max/     |             |
|  | BitMask/Compare/ID  |    | LineMin/LineMax      |             |
|  | LongAtom safe write |    | Reset on init       |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | dll_header_gen      |    | dll_demux_table1    |             |
|  |                     |    |                     |             |
|  | nodeID/streamID/    |    | 64 regs             |             |
|  | targetID/packetID   |    | nodeID.streamID map |             |
|  | HeaderType/KeySwitch|    | -> DLP_RX_ID        |             |
|  | ExtendedID assembly |    +---------------------+             |
|  +---------------------+                                        |
|                             +---------------------+             |
|  +---------------------+    | dll_demux_table2    |             |
|  | dll_packet_id_      |    |                     |             |
|  | tracker             |    | 16 regs, 2 per reg  |             |
|  |                     |    | targetID -> DLP_RX  |             |
|  | Per-port fullPktID  |    | IDvalid check       |             |
|  | TX: inc before use  |    +---------------------+             |
|  | RX: check expected  |                                        |
|  +---------------------+    +---------------------+             |
|                             | dll_error_counters  |             |
|  +---------------------+    |                     |             |
|  | dll_oam_path        |    | 2.2147 dmx status   |             |
|  |                     |    | 2.2210 errors1      |             |
|  | OAM DLP_TX_ID=0     |    | 2.2211 errors2      |             |
|  | OAMdmxTX routing    |    | 2.0140 transmitErr  |             |
|  | oamFrameLocal handle|    | All SC, saturating  |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | dll_forward_if      |    | dll_register_adapter|             |
|  |                     |    |                     |             |
|  | FoFa queue mgmt     |    | Domain 2 reg bus    |             |
|  | DataForwardQueue    |    | All DLL registers   |             |
|  | OAMreturnQueue      |    | OAM Write/Read      |             |
|  +---------------------+    +---------------------+             |
+================================================================+
```

---

## 17. Spec Facts vs Implementation Assumptions

### Spec Facts (normative)

- Up to 64 DLP_TX and 64 DLP_RX connected to one DLL
- OAM is always DLP_TX_ID=0 and DLP_RX_ID=0
- Mapper cycle length = CounterMax - CounterMin + 1
- Mapper default when no LINE matches: DLP_TX_ID=0 (OAM)
- Mapper initialization: Counter = CounterMin
- DLLlinemax cannot exceed DLLmtablelen
- Mapper table max: 640 lines (1920 registers)
- DLLaddrtable: 63 registers, 2 per DLP_TX_ID 1-31
- DmxTable1: 64 registers, one per DLP_RX_ID
- DmxTable2: 16 registers, 2 targetIDs each (targetIDs 2-31)
- PacketID: lower 5 bits of fullPacketID (40-bit counter in ASEP registers)
- Header decode error -> DLLerrors1[15:8]
- Duplicate packetID -> DLLerrors1[7:0]
- Missing packetID -> DLLerrors2[15:8]
- Local demux miss -> DLLdmxstatus[15:8]
- Forward demux miss -> DLLdmxstatus[7:0]
- All error counters: SC, saturate at 0xFF

### Implementation Assumptions (not in spec)

- LongAtom write sequence should be used for atomic mapper table updates (spec
  strongly implies this but does not mandate it; see OAM doc Section 10)
- DLP_TX polling is round-trip synchronous per container cycle (blocking)
- Size selection (Dn vs Up, P2P vs MC) requires knowledge of node direction
  and security state; direction is implementation-defined configuration
- DmxTable1 lookup is linear search over 64 entries per container (or can be
  implemented as CAM). Spec does not mandate hardware lookup style.
- Default table values enabling OAM communication are the hardware reset values,
  not firmware-programmed

---

## 18. Missing / Needs Verification

1. **DLLaddrtable exact address mapping for DLP_TX_ID 1-31**: The extraction fuses
   Table 3-35 and does not render the full mapping table. The base address is
   2.0008 + (DLP_TX_ID-1)*2 based on the textual description. VERIFY against PDF
   Table 3-35 for all 31 entries.

2. **DmxTable2 targetID 0-1 handling**: Table 3-53 marks targetIDs 0 and 1 as
   "reserved" in DmxTable2 but Section 5.3.2.3-6 show targetID 0 and 1 have
   special behavior. VERIFY whether registers 2.2131 bits for targetID 0 and 1
   are truly unused or have special defaults.

3. **Light Sleep mapper halt mechanism**: The spec says "Stops Mapper" during Light
   Sleep. Section 5.8 description is in Light Sleep informative figure. The exact
   signal path (PTB timer triggers DLL mapper halt) is not explicitly defined in
   5.2 or 5.3. VERIFY whether mapper halt is via StartTDD PTBtime comparison or
   a separate LS state signal.

4. **Mapper evaluation does not mandate implementation**: Spec explicitly says
   "It does not mandate an implementation." A CAM, priority encoder, or sequential
   scan are all valid. VERIFY performance requirement: the spec implies evaluation
   per physical layer block (every ~4-6ns at SG1). Sequential scan of 640 lines
   may not meet timing at SG5 without pipelining.

5. **DLP_TX_ID 32-63 address table entries**: The spec shows DLP_TX_ID 1-31 map
   to 2.0008-2.0069. For DLP_TX_IDs 32-63 (up to Nr_DLP_TX max), the address
   range 2.0070-2.0133 is implied but Table 3-35 is truncated in extraction.
   VERIFY upper address range for DLP_TX_ID > 31.

6. **OAMdmxTX copy from FoFa ReturnPath**: Section 5.6.1.5.3 says "if nodeID=0,
   DLL copies FoFa ReturnPath (3.6.1) onto OAMdmxTX." This implies a special
   bootstrap mechanism at enumeration time for nodeID=0. VERIFY the exact timing
   and conditions for this copy operation.

7. **Security KeySwitch bit source**: Spec says "the value provided by the Security
   Entity is used" for KeySwitch in the container header. The Security entity
   interface for providing this bit is not defined in Section 5. VERIFY in
   Section 6.3.2 what exactly the Security entity provides and when.
