# Micro-Architecture: OAM Control Plane

## 1. Purpose and Scope

The OAM (Operation, Administration, Management) entity is the ASA-internal control
plane. It provides the root node with register read/write access to every non-root node,
carries the Precision Time Base clock, facilitates Light Sleep negotiation, routes Key
Exchange messages for the optional Security feature, and drives startup enumeration.

This document defines the micro-architecture of the OAM entity for RTL or golden-model
implementation, derived directly from ASA Technical Specification v2.0.

Scope boundaries:
- IN SCOPE: OAM frame assembly/disassembly, CAD parsing and response generation,
  TX/RX FSMs for root and non-root nodes, register access bridge, enumeration flow,
  LongAtom buffering, Light Sleep CAD routing, KeyExMsg routing, PTB header capture,
  error counters, OAM-related registers
- OUT OF SCOPE: DLL mapper/demux scheduling (separate doc), PHY startup state machines,
  Security AES-GCM engine, ASEP stream encapsulation, register file implementation
  (covered in micro-architecture-register-model.md)

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 5.5 | OAM | 171 | Top-level purpose, session model |
| 5.5.1 | Frame Structure | 171-172 | 24-byte header format (Table 5-2) |
| 5.5.2 | Transmit/Receive State Diagrams | 173-176 | FSM definitions, variables, functions |
| 5.5.2.1 | Constants | 173 | longAtom_LIMIT = 32 |
| 5.5.2.2 | Variables | 173 | OAMframeID counters, FIFO levels |
| 5.5.2.3 | Counters | 173 | OAMframeLen, CNT_longatom |
| 5.5.2.4 | Functions | 173-174 | createOAMheader, fillCADresponseFIFO, etc. |
| 5.5.2.5 | Messages/Events | 174 | Error events |
| 5.5.2.6 | Diagrams | 175-176 | Figures 5-7 through 5-10 |
| 5.5.3 | Command-Address-Data | 176-183 | All 14+ CAD command types |
| 5.5.3.1 | Read | 178 | Register read command format |
| 5.5.3.2 | Return | 178 | Register read response |
| 5.5.3.3 | ReadError | 179 | Error response codes |
| 5.5.3.4 | Write | 179 | Register write command format |
| 5.5.3.5 | WriteAck | 179 | Write response codes |
| 5.5.3.6 | StartEnum | 179 | Enumeration trigger |
| 5.5.3.7 | LongAtom | 180 | Atomic write batching |
| 5.5.3.8 | LongAtomClose | 180 | Atomic write commit |
| 5.5.3.9 | StartTDD | 181 | Normal mode transition |
| 5.5.3.10 | LSannounce | 181-182 | Light Sleep request |
| 5.5.3.11 | LSconfirm | 182 | Light Sleep accept |
| 5.5.3.12 | LSdeny | 182 | Light Sleep reject |
| 5.5.3.13 | LSsleep | 182 | Light Sleep execute |
| 5.5.3.14 | KeyExMsg | 183 | Security key exchange |
| 5.5.4 | Startup Enumeration Procedure | 183-184 | Node-Discover / Self-Announce |
| 5.6.1.1.1 | DLP_TX.indicateSlot | 185 | OAM TX trigger |
| 5.6.1.3.1 | DLP_TX.oamUnit | 186 | OAM frame output to DLL |
| 5.7.1.3.1 | DLP_RX.oamUnit | 188 | OAM frame input from DLL |
| 5.8 | Light Sleep | 189-192 | LS negotiation state diagrams |
| 5.9 | DLL Startup, OAM config | 193 | OAM config -> Normal transition |
| 6.3.5 | Mapping Primitives to OAM (LLS) | 203 | NOT accessible via OAM |
| 6.4.2 | Mapping of Primitives to OAM (KeyEx) | 205-206 | KeyExMsg format |
| 6.4.2.1 | Key Exchange Requests | 205 | Cmd 0x7C format |
| 6.4.2.2 | Key Exchange Responses | 206 | Cmd 0x7D format |
| 8.6.2 | OAM (MLE) | 300 | MLE OAM fragmentation |
| 3.3.23 | OAMerrors1 (2.2208) | 61 | Header decode/duplicate errors |
| 3.3.24 | OAMerrors2 (2.2209) | 61 | Missing ID/payload errors |

Image references (docpdfmd/images/):
- 28_OAM_external_root_device_sequence.png: External->RootSW->RootDevice->Device flow
- 30_OAM_Root_Device_BC_sequence.png: Root SW orchestrating enumeration to B and C
- 31_OAM_multidevice_sequence.png: Multi-device OAM config sequence

---

## 3. OAM Frame Format

### 3.1 Frame Structure (Section 5.5.1, Table 5-2, p172)

```
+----------------------------------------------------------+
| DLL payload (container)                                   |
+----------------------------------------------------------+
| OAM frame:                                               |
| +--------+------+-----+------+-----------+               |
| | Header | CAD  | ... | CAD  | Adaptive  |               |
| | 24B    | #1   |     | #n   | Padding   |               |
| +--------+------+-----+------+-----------+               |
+----------------------------------------------------------+
```

OAM frame size is always 188 bytes (OAM_frame slot size per 5.6.1.1.1).

### 3.2 Header Layout (24 bytes)

```
Byte  Bit(s)  Field                   Description
----  ------  -----                   -----------
0     7:0     OAMframeID[7:0]         32-bit frame counter (low byte)
1     7:0     OAMframeID[15:8]        lower 5 bits = packetID
2     7:0     OAMframeID[23:16]       root keeps per-session counter
3     7:0     OAMframeID[31:24]
4     0       CADnext                 1=CAD present after header, 0=none
4     5:3     OAMerror                Decode result of PREVIOUS frame
                                       000=no error
                                       001=duplicate OAMframeID
                                       010=omitted OAMframeID
                                       011=header decode error
                                       100=payload/CAD decode error
                                       101-111=reserved
4     6       OAMheaderStatusValid    1=bytes 12..17 valid
4     2:1     Reserved                Set to 0
4     7       PTBstatus[0]            Identical to 2.2203[8:0] (bit 0)
5     7:0     PTBstatus[8:1]
6     7:0     PTBclk[7:0]            Identical to register 2.2200-2.2202
7     7:0     PTBclk[15:8]           48-bit PTB clock value
8     7:0     PTBclk[23:16]          If PTB unlocked or invalid: set to 0
9     7:0     PTBclk[31:24]
10    7:0     PTBclk[39:32]
11    7:0     PTBclk[47:40]
12    7:0     LinkHealthStatus1[7:0]  = LinkQuality (1.0101) low byte
13    7:0     LinkHealthStatus1[15:8] = LinkQuality (1.0101) high byte
14    7:0     LinkHealthStatus2[7:0]  = SQI (1.0102) low byte
15    7:0     LinkHealthStatus2[15:8] = SQI (1.0102) high byte
16    7:0     LinkHealthStatus3[7:0]  = FECstat (1.0104) low byte
17    7:0     LinkHealthStatus3[15:8] = FECstat (1.0104) high byte
18    7:0     LinkHealthStatus4       Vendor-defined
19    7:0     LinkHealthStatus5       Vendor-defined
20    7:0     LinkHealthStatus6       Vendor-defined
21    7:0     LinkHealthStatus7       Vendor-defined
22    7:0     LinkHealthStatus8       Vendor-defined
23    7:0     LinkHealthStatus9       Vendor-defined
```

SPEC FACT: PTBclk, PTBstatus, and all LinkHealthStatus registers are captured at the
instant between DLP_TX.indicateSlot and DLP_TX.oamUnit (5.5.1, p173 line 1-2).

SPEC FACT: OAMerror reports the decode result of the PREVIOUS frame received FROM the
addressee of THIS frame (Table 5-2). Errors are cleared only once reported in a sent
OAM frame.

### 3.3 CAD Chaining

Each CAD starts with a command byte:
```
Byte n:  Bit 7 = CADnext (1=more CADs follow, 0=last CAD)
         Bits 6:0 = Command code (7 bits)
```

Multiple CADs are packed sequentially after the header until the frame is full or all
pending commands/responses are written.

---

## 4. CAD Command Set

### 4.1 Command Codes (Table 5-4, p177)

```
Code  Command         Direction        Response        Size (bytes)
----  -------         ---------        --------        ----
0x00  Reserved        -                -               -
0x01  Read            Root->Non-Root   Return/ReadErr  4
0x02  Return          Non-Root->Root   -               6
0x03  ReadError       Non-Root->Root   -               6
0x04  Write           Root->Non-Root   WriteAck        6
0x05  WriteAck        Non-Root->Root   -               6
0x06  StartEnum       Root->Non-Root   Return(s)       6
0x07  LongAtom        Root->Non-Root   -               2
0x08  LongAtomClose   Root->Non-Root   -               2
0x09  StartTDD        Root->Non-Root   -               12
0x0A  LSannounce      Either           LSconfirm/deny  12
0x0B  LSconfirm       Either           -               4
0x0C  LSdeny          Either           -               2
0x0D  LSsleep         Root->Non-Root   -               10
0x7C  KeyExMsg Req    Root->Non-Root   KeyExMsg Resp   variable
0x7D  KeyExMsg Resp   Non-Root->Root   -               variable
```

### 4.2 Read Command (Section 5.5.3.1, p178)

```
Byte  Bit(s)  Field
n+1   7:5     AddressDomain[2:0]   (0-5)
n+1   4:0     DLP_ID[5:1]          (ignored if domain != 4 or 5)
n+2   7       DLP_ID[0]
n+2   6:0     Address[14:8]
n+3   7:0     Address[7:0]
```
Total: 4 bytes (command byte + 3 address bytes). No data field.

### 4.3 Return Command (Section 5.5.3.2, p178)

Same address format as Read (bytes n+1..n+3), plus:
```
n+4   7:0     RegisterValue[15:8]
n+5   7:0     RegisterValue[7:0]
```
Total: 6 bytes.

### 4.4 ReadError Command (Section 5.5.3.3, p179)

Same address format as Read (bytes n+1..n+3), plus:
```
n+4   7:0     Reserved
n+5   7:0     ErrorCode
                0x00 = Address does not exist
                0x01 = Access not allowed
                0x02-0xFF = Reserved
```
Total: 6 bytes.

### 4.5 Write Command (Section 5.5.3.4, p179)

Same address format as Read (bytes n+1..n+3), plus:
```
n+4   7:0     RegisterValue[15:8]
n+5   7:0     RegisterValue[7:0]
```
Total: 6 bytes.

### 4.6 WriteAck Command (Section 5.5.3.5, p179)

Same address format as Read (bytes n+1..n+3), plus:
```
n+4   7:0     Reserved
n+5   7:0     ReturnCode
                0x00 = Reserved
                0x01 = Write successful
                0x02 = Write fail
                0x04 = Access not allowed (RO only)
                0x06 = Access not allowed (Authentication)
                0x08 = Address does not exist
```
Total: 6 bytes.

### 4.7 StartEnum Command (Section 5.5.3.6, p179)

No address field. Only in NodeDiscover OAM frames (see 5.5.4.1).
```
n+1   7:0     Reserved
n+2   7:0     Reserved
n+3   7:0     Reserved
n+4   7:0     Reserved
n+5   7:5     Reserved
n+5   4:0     freeNodeID[4:0]    Next nodeID to enumerate
```
Total: 6 bytes.

### 4.8 LongAtom Command (Section 5.5.3.7, p180)

```
n+1   7:5     Reserved
n+1   4:0     LongAtom_counter   Starts 0, increments per frame
```
Total: 2 bytes.

Constraints:
- Only Write commands allowed between LongAtom and LongAtomClose
- Maximum 31 consecutive LongAtom frames (32nd MUST be LongAtomClose)
- Empty OAM frames (header only) may be interspersed
- If LongAtomClose not received by 32nd frame OR any frame corrupted/missing:
  all WriteAck = "Write fail"

### 4.9 LongAtomClose Command (Section 5.5.3.8, p180)

```
n+1   7:0     Reserved
```
Total: 2 bytes. Triggers execution of all buffered Writes after end of current TDD burst.

### 4.10 StartTDD Command (Section 5.5.3.9, p181)

```
n+1   7:0     PTBtime[47:40]
n+2   7:0     PTBtime[39:32]     PTB timestamp at which to start
n+3   7:0     PTBtime[31:24]     normal mode
n+4   7:0     PTBtime[23:16]
n+5   7:0     PTBtime[15:8]
n+6   7:0     PTBtime[7:0]
n+7   7:0     DLLlinemin[15:8]   Mapper start pointer
n+8   7:0     DLLlinemin[7:0]
n+9   7:0     DLLlinemax[15:8]   Mapper end pointer
n+10  7:0     DLLlinemax[7:0]
n+11  7:0     Reserved
```
Total: 12 bytes. Triggers Mapper Initialization (5.2.3.2).

### 4.11 Light Sleep Commands (Section 5.5.3.10-13, p181-182)

**LSannounce** (12 bytes):
```
n+1..n+6    PTBbedtime[47:0]      When to go to sleep
n+7   7:4   Reserved
n+7   3:0   SleepCycles[11:8]     TDD cycles to sleep (includes restart)
n+8   7:0   SleepCycles[7:0]
n+9   7:0   RestartCycles1G[7:0]  Phase1G patterns for restart
n+10  7:0   RestartCyclesSGx[7:0] PhaseSGA/B/C patterns for restart
n+11  7:0   Reserved
```

**LSconfirm** (4 bytes):
```
n+1   7:0   RestartCycles1G_a[7:0]
n+2   7:0   RestartCyclesSGx_a[7:0]
n+3   7:0   Reserved
```

**LSdeny** (2 bytes):
```
n+1   7:0   Reserved
```

**LSsleep** (10 bytes):
```
n+1..n+6    PTBalarmclock[47:0]    PTB time for restart
n+7   7:0   RestartCycles1G_f[7:0]
n+8   7:0   RestartCyclesSGx_f[7:0]
n+9   7:0   Reserved
```

### 4.12 KeyExMsg Command (Section 5.5.3.14, p183; Section 6.4.2, p205-206)

SPEC FACT: KeyExMsg is always the ONLY command in an OAM frame. Bit 7 (CADnext) in
the first CAD byte is always 0.

**Request** (Root -> Non-Root, cmd 0x7C):
```
n     7     CADnext = 0 (always)
n     6:0   Command = 0x7C
n+1   7:0   Primitive ID
n+2   7:0   Reserved (0x00)
n+3..       Parameters (variable length)
```

**Response** (Non-Root -> Root, cmd 0x7D):
```
n     7     CADnext = 0 (always)
n     6:0   Command = 0x7D
n+1   7:0   Primitive ID
n+2..       Parameters (variable length, includes status code at byte 0)
```

SPEC FACT: All KeyEx OAM fields are Big Endian. Reserved bytes = 0x00 on send,
ignored on receive. (Section 6.4.2)

SPEC FACT: Link Layer Security primitives are NOT accessible through OAM (6.3.5).
Only KeyEx primitives use OAM transport.

---

## 5. OAM TX/RX FSM Architecture

### 5.1 Root Node TX FSM (Figure 5-7, p175)

```
                DLP_TX.indicateSlot(size)
                         |
                         v
              +---------------------+
              | OAM_createHeader_1  |
              |                     |
              | nID.txOAMframeID++  |
              | createOAMheader()   |
              +---------------------+
                         |
                         v
              +---------------------+
              | OAM_createCAD_1     |
              |                     |
              | [command sequence   |
              |  depends on app]    |
              +--------|------------+
                       |
            +----------+----------+
            |                     |
    CADcmdFIFOlvl!=empty    CADcmdFIFOlvl==empty
    AND OAMframeLen<<size       OR OAMframeLen>=size
            |                     |
            v (loop)              v
              +---------------------+
              | DLP_TX.oamUnit      |
              +---------------------+
```

SPEC FACT: The root node maintains a separate nID.txOAMframeID counter per non-root
node session. Which nID to communicate with "depends on application" (informative).

### 5.2 Root Node RX FSM (Figure 5-8, p175)

```
    DLP_RX.oamUnit(size, header, data, phylStat, dllStat, secStat)
                         |
                         v
              +------------------------+
              | OAM_decodeHeader_1     |
              |                        |
              | nID = decodeNodeID(hdr)|
              | checkOAMheader(nID)    |
              +----------|-------------+
                         |
            +------------+------------+
            |                         |
        no error              OAMHEADER_DECODE_ERR |
            |                 OAMHEADER_DUPLID_ERR |
            v                 OAMHEADER_MISSID_ERR
    +--------------------+            |
    | OAM_decodePayload_1|            v (record error)
    +----------|----------+
               |
        +------+------+
        |             |
    no error    OAMPAYLOAD_DECODE_ERR
        |             |
        v             v (record error)
    +--------------------+
    | OAM_evalCADs_1     |
    | [reaction/response |
    |  depends on app]   |
    +--------------------+
```

### 5.3 Non-Root Node TX FSM (Figure 5-9, p176)

```
                DLP_TX.indicateSlot(size)
                         |
                         v
              +---------------------+
              | OAM_createHeader_2  |
              |                     |
              | txOAMframeID++      |
              | OAMframeLen = 0     |
              | createOAMheader()   |
              +---------------------+
                         |
              CADrespFIFO != empty?
              /                    \
          yes /                      \ no (empty)
             v                        v
    +----------------------+    DLP_TX.oamUnit
    | OAM_createCAD_2      |    (header only)
    |                      |
    | lastCADcmd =         |
    |   readCADrespFIFO()  |
    | OAMframeLen +=       |
    |   lastCADcmd.size    |
    +----------|----------+
               |
    +----------+-----------+
    |          |           |
    |   CADrespFIFO!=empty |  lastCADcmd==KeyExMsg
    |   AND OAMframeLen    |  OR CADrespFIFO==empty
    |   << size            |  OR OAMframeLen>=size
    |          |           |
    v (loop)   v           v
               +---------------------+
               | DLP_TX.oamUnit      |
               +---------------------+
```

SPEC FACT: If lastCADcmd is KeyExMsg, the frame terminates immediately (no further
CADs allowed in same frame).

### 5.4 Non-Root Node RX FSM (Figure 5-10, p176)

```
    DLP_RX.oamUnit(size, header, data, phylStat, dllStat, secStat)
                         |
                         v
              +------------------------+
              | OAM_decodeHeader_2     |
              | checkOAMheader()       |
              +----------|-------------+
                         |
            +------------+-------------------+
            |                                |
        no error                   OAMHEADER_DECODE_ERR |
            |                      OAMHEADER_DUPLID_ERR |
            v                      OAMHEADER_MISSID_ERR
    +---------------------+                  |
    | OAM_decodePayload_2 |                  v
    +----------|----------+       +------------------+
               |                  | OAM_flushFIFO_1  |
        +------+------+          | flushLongAtomFIFO |
        |      |      |          | CNT_longatom=0   |
        |      |      |          +------------------+
    LONGATOM   |  LONGATOMCLOSE
        |      |      |
        v      |      v
  +-----------+|  +-------------------------+
  |OAM_put    || |OAM_evalLongAtomFIFO_1   |
  |LongAtom   || |                          |
  |FIFO_1     || | CNT_longatom=0           |
  |            || | evalLongAtomFIFO()       |
  |CNT_longat || | fillCADresponseFIFO()    |
  |om++        || +-------------------------+
  |fillLongAt ||
  |omFIFO()   ||   no error (normal CADs)
  |            ||         |
  |if(CNT >=  ||         v
  |LIMIT):    ||  +------------------+
  | flush     ||  | OAM_evalCADs_2   |
  | CNT=0     ||  |                  |
  +-----------+|  |fillCADresponse   |
               |  |FIFO()            |
               |  +------------------+
               |
               v
        DLP_TX.indicateSlot(size)
        [TX FSM triggered on next slot]
```

SPEC FACT: On header error, the LongAtomFIFO is flushed and CNT_longatom reset.
This prevents partially received atomic writes from executing.

---

## 6. CAD Parser Architecture

### 6.1 Command Decoder

```
                    +------------------+
                    |  CAD Byte Stream |
                    |  (from payload)  |
                    +--------+---------+
                             |
                             v
                    +------------------+
                    | Command Decoder  |
                    |                  |
                    | Extract:         |
                    |  cmd[6:0]        |
                    |  cadnext (bit 7) |
                    +--------+---------+
                             |
              +--------------+--------------+
              |    |    |    |    |    |    |
              v    v    v    v    v    v    v
           Read Write Start Start LS  LS  KeyEx
                  Enum  TDD   Ann Slp  Msg
              |    |    |    |    |    |    |
              v    v    v    v    v    v    v
         +---------+---------+---------+---------+
         | Address | Address | No Addr | No Addr |
         | Parser  | Parser  | (fixed) | (var)   |
         | 3 bytes | 3 bytes |         |         |
         +---------+---------+---------+---------+
              |         |         |         |
              v         v         v         v
         +----------+  +----------+  +-----------+
         | Register |  | NodeState|  | Security  |
         | Access   |  | Machine  |  | Entity    |
         | Engine   |  | / PTB /  |  | (KeyEx)   |
         |          |  | LS FSM   |  |           |
         +----------+  +----------+  +-----------+
```

### 6.2 Address Decoding (from Read/Write/Return/ReadError/WriteAck)

All register-access CADs share the same 3-byte address format:
```
Input bits:         Decoded fields:
  n+1[7:5]    -->   AddressDomain[2:0]     (maps to domain 0-5)
  n+1[4:0]    -->   DLP_ID[5:1]            (only for domain 4/5)
  n+2[7]      -->   DLP_ID[0]
  n+2[6:0]    -->   Address[14:8]
  n+3[7:0]    -->   Address[7:0]
```

The decoded address is passed to the Register Access Engine with:
- domain[2:0]
- dlp_id[5:0] (valid only when domain==4 or domain==5)
- address[14:0]

---

## 7. Read/Write Register Access Flow

### 7.1 Read Flow (Non-Root Node Processing)

```
Root sends Read CAD
         |
         v
[Non-root OAM_evalCADs_2]
         |
         v
+-------------------+
| Decode address    |
| domain, dlp_id,  |
| register_addr     |
+--------+----------+
         |
         v
+-------------------+
| Access Control    |
| Check:            |
|  - Does address   |
|    exist?         |
|  - Is OAM access  |
|    allowed? (O)   |
|  - Privilege:     |
|    RID? A?        |
+--------+----------+
         |
    +----+----+
    |         |
  PASS      FAIL
    |         |
    v         v
+--------+ +-------------+
| Read   | | Generate    |
| Register| | ReadError   |
| File    | | CAD:        |
+----+---+ | 0x00=no addr|
     |     | 0x01=denied |
     v     +------+------+
+--------+        |
|Generate|        |
|Return  |        |
|CAD     |        |
+----+---+        |
     |            |
     +------+-----+
            |
            v
     +-------------+
     | Push to     |
     |CADrespFIFO  |
     +-------------+
```

### 7.2 Write Flow (Non-Root Node Processing)

```
Root sends Write CAD
         |
         v
[Non-root OAM_evalCADs_2]
         |
         v
+-------------------+
| Decode address    |
+--------+----------+
         |
         v
+-------------------+
| Access Control    |
| Check:            |
|  - Exists?        |
|  - O allowed?     |
|  - RW (not RO)?   |
|  - Privilege?     |
+--------+----------+
         |
    +----+-----+-----+
    |          |     |
  PASS      RO Only  No Addr / Auth Fail
    |          |     |
    v          v     v
+--------+ +------+ +------+
|Write   | |WAck  | |WAck  |
|Register| |0x04  | |0x08/ |
|Execute | |      | |0x06  |
|side-fx | +--+---+ +--+---+
+----+---+    |         |
     |        |         |
     v        |         |
+--------+    |         |
|Generate|    |         |
|WriteAck|    |         |
|0x01    |    |         |
+----+---+    |         |
     |        |         |
     +--------+---------+
              |
              v
       +-------------+
       | Push to     |
       |CADrespFIFO  |
       +-------------+
```

### 7.3 Access Control Rules (per micro-architecture-register-model.md)

Each register has metadata:
- rw_type: RO, RW, SC (self-clearing)
- access: L (local only) or O (OAM and local)
- privilege: RID (root ID only) or A (authenticated)

OAM Read/Write checks:
1. Does register address exist? -> No: ReadError(0x00) / WriteAck(0x08)
2. Is access == O? -> No (L only): ReadError(0x01) / WriteAck(0x04)
3. For Write: Is rw_type == RO? -> Yes: WriteAck(0x04)
4. Is privilege == A and not authenticated? -> WriteAck(0x06)
5. Is source nodeID == root (privilege RID check)? -> Always true for OAM from root

SPEC FACT: Register 3.0001 (securityPolicy) is L-only, NOT OAM accessible (6.3.5).
SPEC FACT: Register 1.0106 (DiagnosticsTestCtrl) is L-only (review doc correction).

---

## 8. StartEnum and Enumeration Flow

### 8.1 Node-Discover Message (Section 5.5.4.1, p184)

Sent by root node:
- HeaderType = 1 (extended header)
- targetID0 = 0
- targetID1 = near-side nodeID (behind which to discover)
- CADnext = 1
- OAMerror = 0
- Contains single StartEnum CAD with freeNodeID

### 8.2 Self-Announce Response (Section 5.5.4.2, p184)

Reply from newly discovered node:
- HeaderType = 1
- targetID0 = 1, all other targetIDs = 0
- Contains Return CADs for: DLLconfig1, DLLconfig2, VendorID, DeviceID,
  ASEP Stream Type for all supported/enabled DLPs

### 8.3 Enumeration Sequence

```
1. Root sends NodeDiscover (targetID0=0, targetID1=near_nID)
   with StartEnum(freeNodeID=N)
         |
         v
2. Near-side DLL forwards to undiscovered node (via FoFa enumerate mode)
         |
         v
3. New node writes N to local NodeID register (2.0001)
         |
         v
4. New node replies with Self-Announce containing:
   - Return(DLLconfig1)   [3.3.2]
   - Return(DLLconfig2)   [3.3.3]
   - Return(VendorID)     [3.3.4]
   - Return(DeviceID)     [3.3.5]
   - Return(ASEP Stream Type) for each DLP  [3.5.1.2]
         |
         v
5. Root receives Self-Announce, configures DLP_TX mapper slots
   and addressing table via normal OAM Write commands
         |
         v
6. Root updates DmxTable2 in previously enumerated nodes
         |
         v
7. Root sends next NodeDiscover with targetID1=new_nID, freeNodeID=N+1
```

SPEC FACT: Deterministic one-by-one forwarding of Node-Discover is ensured by the
DLL Receive Process (5.3). Far-side nodes can be directly addressed after near-side
DmxTable2 is updated.

---

## 9. StartTDD Flow

### 9.1 OAM Config -> Normal Mode Transition (Section 5.9, p193)

```
Root sends StartTDD CAD:
  - PTBtime: absolute PTB timestamp for normal mode start
  - DLLlinemin: mapper start pointer
  - DLLlinemax: mapper end pointer
         |
         v
Non-root receives StartTDD:
  - Stores PTBtime, DLLlinemin, DLLlinemax
  - At PTBtime: Root starts with resync header of data burst
  - Leaf starts one IBG into quiet gap and waits for data
  - Mapper Initialization executes (5.2.3.2)
         |
         v
Normal Mode begins
```

SPEC FACT: If configuration is persistently stored (beyond power cycle or returning
from Light Sleep), Normal Mode can be initiated via the startup info field bit
(4.2.7.5) without requiring OAM Config phase.

---

## 10. LongAtom/LongAtomClose Flow

### 10.1 Purpose

Atomic batch-write of multiple registers. Use case: programming the entire Mapper
table (1920 entries at 2.0146-2.2065) atomically so the scheduler does not observe a
partially configured state.

### 10.2 Sequence

```
Frame 1: [Write, Write, ..., LongAtom(counter=0)]
Frame 2: [Write, Write, ..., LongAtom(counter=1)]
...
Frame K: [Write, Write, ..., LongAtomClose]     (K <= 32)
```

### 10.3 Non-Root Processing

```
State: NORMAL (no active LongAtom)
  |
  | Receive OAM frame with LONGATOM CAD
  v
State: BUFFERING
  CNT_longatom++
  fillLongAtomFIFO()  -- buffer Writes, do NOT execute yet
  |
  | if CNT_longatom >= longAtom_LIMIT (32):
  |   flushLongAtomFIFO()
  |   CNT_longatom = 0
  |   all WriteAck = "Write fail" (0x02)
  |   -> State: NORMAL
  |
  | Receive frame with LONGATOMCLOSE:
  v
State: COMMIT
  CNT_longatom = 0
  evalLongAtomFIFO()  -- execute all buffered Writes IN ORDER
  fillCADresponseFIFO()  -- generate WriteAcks
  -> State: NORMAL
```

### 10.4 Error Handling

- Header decode error during BUFFERING: flushLongAtomFIFO, CNT=0 (Fig 5-10)
- Frame missing (OAMframeID gap): header check fails -> flush
- 32nd frame without LongAtomClose: overflow -> flush, all Writes fail
- Empty OAM frames (header only, no CADs) MAY be interspersed without
  affecting the LongAtom sequence

---

## 11. Light Sleep Command Routing

### 11.1 Overview (Section 5.8, p189-192)

Light Sleep is negotiated via OAM CAD exchange. Either root or non-root may initiate.
The root node mediates the final decision.

### 11.2 Flow (Root Initiating)

```
Root                              Non-Root
  |                                  |
  |--- LSannounce(PTBbedtime,       |
  |    SleepCycles, Restart1G,       |
  |    RestartSGx) ----------------->|
  |                                  |
  |                        [Check conditions:
  |                         - PTB locked?
  |                         - Sleep time > 100us?
  |                         - Bedtime > 50us future?
  |                         - PTB drift acceptable?]
  |                                  |
  |<-- LSconfirm(Restart1G_a,       |  (or LSdeny)
  |    RestartSGx_a) <---------------|
  |                                  |
  |[Root checks all nodes]           |
  |                                  |
  |--- LSsleep(PTBalarmclock,        |
  |    Restart1G_f, RestartSGx_f) -->|
  |                                  |
  |    [Both set timer_LSbedtime]    |
  |    [At bedtime: enter sleep]     |
  |    [At alarmclock: wake up]      |
  |                                  |
```

### 11.3 Non-Root Check Conditions (Section 5.8.1.1, p190)

Mandatory checks before sending LSconfirm:
1. PTB is locked
2. SleepCycles*phSGx_TIME - (RestartCycles1G_a*ph1G_TIME + RestartCyclesSGx_a*phSGx_TIME) > 25000 PTB tics (100us minimum sleep)
3. PTBbedtime - PTBclk > 12500 PTB tics (50us minimum future)
4. PTB drift during estimated sleep < 140 PTB tics

If ANY condition fails: MUST deny. Light Sleep MAY be denied at any time regardless.

### 11.4 OAM Entity Responsibility

The OAM entity routes LS CADs to/from the Light Sleep FSM:
- On RX: decode LS CAD type, pass parameters to LS state machine
- On TX: LS state machine generates response CAD, pushed to CADrespFIFO

IMPLEMENTATION NOTE: The LS FSM is a separate state machine (Section 5.8.3) that
interfaces with OAM via the CAD response FIFO. OAM does not evaluate LS conditions
itself.

---

## 12. KeyExMsg Routing to Security Entity

### 12.1 Architecture

```
+-------------------+     +-------------------+     +-------------------+
|   OAM Entity      |     | KeyEx Bridge      |     | Key Exchange      |
|                   |     |                   |     | Entity            |
| RX: decode        |---->| Extract:          |---->| Process primitive |
|  cmd 0x7C/0x7D   |     |  Primitive ID     |     | Generate response |
|                   |     |  Parameters       |     |                   |
| TX: read from     |<----| Format response   |<----| Return result     |
|  CADrespFIFO      |     |  as 0x7D CAD      |     |                   |
+-------------------+     +-------------------+     +-------------------+
```

### 12.2 Constraints

- KeyExMsg is ALWAYS the only CAD in an OAM frame (CADnext=0)
- Non-root TX: if lastCADcmd == KeyExMsg, frame terminates immediately (Fig 5-9)
- KeyEx Request (0x7C): root -> non-root, contains Primitive ID + Parameters
- KeyEx Response (0x7D): non-root -> root, contains Primitive ID + Parameters
  (first byte of Parameters is status code)
- All fields Big Endian
- Reserved bytes = 0x00 on send, ignored on receive

### 12.3 KeyEx Primitives Transported (Section 6.4.3)

| ID | Primitive | Direction |
|----|-----------|-----------|
| 0x00 | install_UUID | Req |
| 0x02 | read_UUID | Req/Resp |
| 0x04 | read_current_nonce | Req/Resp |
| 0x06 | read_status_keys | Req/Resp |
| 0x07 | read_status_keys_ext | Req/Resp |
| 0x08 | setup_policy | Req |
| 0x10 | install_DK_0_unencrypted | Req |
| 0x12 | install_DK_1_unencrypted | Req |
| 0x13 | install_DK_1_encrypted | Req |
| 0x21 | install_BK_encrypted | Req |
| 0x23 | install_BK_encrypted_by_DK_1_only | Req |
| 0x31 | install_LKs_encrypted | Req |
| 0x33 | change_LKs_KeySlot | Req |
| 0x81 | report_status_LK | Req/Resp |

---

## 13. OAM Queues and Buffers

### 13.1 Root Node

```
+------------------------+
| CADcmdFIFO             |  Commands to send to non-root nodes
| (application fills)    |  Read, Write, StartEnum, StartTDD,
|                        |  LongAtom, LongAtomClose, LS*, KeyExMsg
+------------------------+

+------------------------+
| Per-session state      |  One set per non-root nodeID:
| nID.txOAMframeID       |    - TX frame counter
| nID.rxOAMframeID       |    - RX frame counter
+------------------------+
```

### 13.2 Non-Root Node

```
+------------------------+
| CADrespFIFO            |  Responses to send back to root
| (Return, ReadError,    |  Ordered: responses generated in
|  WriteAck, LSconfirm,  |  same order as commands received
|  LSdeny, KeyExMsg Resp)|
+------------------------+

+------------------------+
| LongAtomFIFO           |  Buffered Write commands during
|                        |  LongAtom sequence
| Max depth: 32 frames   |  (longAtom_LIMIT)
| worth of Write CADs    |
+------------------------+

+------------------------+
| State variables        |
| txOAMframeID           |  TX counter (single session with root)
| rxOAMframeID           |  RX counter
| lastCADcmd             |  Last CAD written to current frame
| CADrespFIFOlvl         |  "empty" or "not empty"
| OAMframeLen            |  Bytes filled in current frame
| CNT_longatom           |  LongAtom frame counter
+------------------------+
```

### 13.3 Buffer Sizing (IMPLEMENTATION ASSUMPTION)

The spec does not define exact FIFO depths for CADcmdFIFO or CADrespFIFO.
Minimum sizing considerations:
- OAM frame payload = 188 - 24 = 164 bytes
- Max CADs per frame (6-byte commands): floor(164/6) = 27 CADs
- LongAtomFIFO: must hold up to 32 frames * 27 CADs = 864 Write commands
  (worst case for full mapper table atomic update)

---

## 14. PTB Timestamp Capture Interaction

### 14.1 Capture Timing (Section 5.5.1, p173)

SPEC FACT: PTBclk, PTBstatus, and all LinkHealthStatus registers are copied "at the
time when the OAM frame is being created (between DLP_TX.indicateSlot and
DLP_TX.oamUnit)."

### 14.2 Implementation

```
DLP_TX.indicateSlot(OAM_frame)
         |
         v
+-------------------+
| Snapshot PTBclk   |  <- capture current 48-bit PTBclk register
| Snapshot PTBstatus|  <- capture 2.2203[8:0]
| Snapshot LH1-LH3  |  <- capture 1.0101, 1.0102, 1.0104
| Snapshot LH4-LH9  |  <- capture vendor registers
+-------------------+
         |
         v
+-------------------+
| Assemble header   |  <- place snapshots into bytes 4-23
| Increment frameID |
| Set OAMerror      |  <- based on last RX decode result
| Set CADnext       |
+-------------------+
         |
         v
+-------------------+
| Append CADs       |  <- from CADcmdFIFO (root) or CADrespFIFO (non-root)
| Pad to size       |
+-------------------+
         |
         v
DLP_TX.oamUnit(payload, targetID, packetID, ndEn, targetIDs)
```

### 14.3 PTB Initial Copy (Section 4.2.8.3.1.1, p117)

On receiving an OAM frame, if local PTB is unlocked, PTBclk register (2.2200-2.2202)
is overwritten with the PTBclk value from the OAM header. This provides coarse
synchronization to the root node's clock.

### 14.4 PTB Diagnostics (Section 4.2.8.3.1.2, p118)

If local PTB IS locked, the OAM header PTBclk is used to calculate PTBoamDly (2.2207).
If not locked, PTBoamDly = 0.

---

## 15. Error Counters and Related Registers

### 15.1 OAMerrors1 (2.2208) -- Section 3.3.23, p61

```
Bit(s)  Name                        Type   Access  Privilege
15:8    OAM header decode error     SC     O       RID
        (accumulated OAMHEADER_DECODE_ERR count, saturates 0xFF)
7:0     OAM header duplicate        SC     O       RID
        frame ID error
        (accumulated OAMHEADER_DUPLID_ERR count, saturates 0xFF)
```

### 15.2 OAMerrors2 (2.2209) -- Section 3.3.24, p61

```
Bit(s)  Name                        Type   Access  Privilege
15:8    OAM header missing          SC     O       RID
        frame ID error
        (accumulated OAMHEADER_MISSID_ERR count, saturates 0xFF)
7:0     OAM payload decode error    SC     O       RID
        (accumulated OAMPAYLOAD_DECODE_ERR count, saturates 0xFF)
```

### 15.3 Error Generation Rules (Section 5.5.2.5, p174)

| Event | Condition |
|-------|-----------|
| OAMHEADER_DECODE_ERR | OAMframeID not as expected OR header cannot be decoded |
| OAMHEADER_DUPLID_ERR | Received OAMframeID < rxOAMframeID+1 (or nID.rx...+1 for root) |
| OAMHEADER_MISSID_ERR | Received OAMframeID > rxOAMframeID+1 (or nID.rx...+1 for root) |
| OAMPAYLOAD_DECODE_ERR | One or more CADs in payload could not be decoded |

### 15.4 Error Reporting via OAMerror Field

The OAMerror field (byte 4, bits 5:3) in the NEXT transmitted OAM frame reports the
decode result back to the sender. Error is cleared only once reported. Mapping:
- 000 = no error
- 001 = duplicate OAMframeID
- 010 = omitted OAMframeID
- 011 = decoding error in OAM header
- 100 = decoding error in CAD or CADs

---

## 16. Interfaces

### 16.1 Interface to DLL (Data Link Layer)

| Signal/Primitive | Direction | Description |
|-----------------|-----------|-------------|
| DLP_TX.indicateSlot(OAM_frame) | DLL->OAM | Requests 188-byte OAM frame |
| DLP_TX.oamUnit(payload, targetID, packetID, ndEn, targetIDs) | OAM->DLL | Provides assembled frame |
| DLP_RX.oamUnit(size, header, payload, phylStat, dllStat, secStat) | DLL->OAM | Delivers received frame |

OAM is always connected to DLP_TX_ID=0 and DLP_RX_ID=0 (Section 5.1, p162).

### 16.2 Interface to Register Model

| Signal | Direction | Description |
|--------|-----------|-------------|
| reg_read(domain, dlp_id, addr) | OAM->RegFile | Read register |
| reg_read_data(value, error) | RegFile->OAM | Read response |
| reg_write(domain, dlp_id, addr, data) | OAM->RegFile | Write register |
| reg_write_ack(status) | RegFile->OAM | Write response (ok/RO/noaddr/auth) |

### 16.3 Interface to PTB

| Signal | Direction | Description |
|--------|-----------|-------------|
| ptb_clk[47:0] | PTB->OAM | Current PTBclk for header |
| ptb_status[8:0] | PTB->OAM | PTBstatus register |
| ptb_locked | PTB->OAM | Lock state |
| oam_rx_ptbclk[47:0] | OAM->PTB | Received PTBclk from header |
| oam_rx_valid | OAM->PTB | Header valid signal |

### 16.4 Interface to Security (KeyEx)

| Signal | Direction | Description |
|--------|-----------|-------------|
| keyex_request(id, params) | OAM->KeyEx | Decoded KeyExMsg request |
| keyex_response(id, params) | KeyEx->OAM | KeyEx response for CADrespFIFO |
| keyex_busy | KeyEx->OAM | KeyEx processing in progress |

### 16.5 Interface to Light Sleep FSM

| Signal | Direction | Description |
|--------|-----------|-------------|
| ls_announce(ptb_bedtime, sleep_cycles, restart_1g, restart_sgx) | OAM->LS | Decoded LSannounce |
| ls_confirm(restart_1g_a, restart_sgx_a) | OAM->LS or LS->OAM | Confirm params |
| ls_deny | OAM->LS or LS->OAM | Deny signal |
| ls_sleep(ptb_alarm, restart_1g_f, restart_sgx_f) | OAM->LS | Execute sleep |
| ls_cad_response | LS->OAM | Response CAD for CADrespFIFO |

### 16.6 Interface to Node State Machine

| Signal | Direction | Description |
|--------|-----------|-------------|
| node_state[2:0] | NodeFSM->OAM | Current ASAnodeState for header |
| start_tdd_event | OAM->NodeFSM | StartTDD received, transition to Normal |
| enum_complete | OAM->NodeFSM | NodeID assigned via StartEnum |

---

## 17. Suggested RTL Module Boundaries

```
+=========================================================+
|                    oam_top                                |
|                                                          |
|  +------------------+    +------------------+            |
|  | oam_tx_fsm       |    | oam_rx_fsm       |            |
|  |                  |    |                  |            |
|  | Root: Fig 5-7    |    | Root: Fig 5-8    |            |
|  | NonRoot: Fig 5-9 |    | NonRoot: Fig 5-10|            |
|  |                  |    |                  |            |
|  | createOAMheader  |    | checkOAMheader   |            |
|  | CAD packing      |    | CAD unpacking    |            |
|  +--------+---------+    +--------+---------+            |
|           |                       |                      |
|           v                       v                      |
|  +------------------+    +------------------+            |
|  | oam_header_gen   |    | oam_header_check |            |
|  |                  |    |                  |            |
|  | PTB snapshot     |    | frameID check    |            |
|  | LH register snap |    | Error event gen  |            |
|  | OAMerror encode  |    | PTB extract      |            |
|  +------------------+    +------------------+            |
|                                                          |
|  +------------------+    +------------------+            |
|  | cad_cmd_fifo     |    | cad_resp_fifo    |            |
|  | (root only)      |    | (non-root only)  |            |
|  +------------------+    +------------------+            |
|                                                          |
|  +------------------+    +------------------+            |
|  | cad_parser       |    | longatom_fifo    |            |
|  |                  |    |                  |            |
|  | Decode cmd[6:0]  |    | Buffer Writes    |            |
|  | Route to handler |    | Flush on error   |            |
|  +------------------+    | Eval on Close    |            |
|                          +------------------+            |
|  +------------------+                                    |
|  | reg_access_bridge|    +------------------+            |
|  |                  |    | error_counters   |            |
|  | Read/Write       |    |                  |            |
|  | Access control   |    | 2.2208, 2.2209   |            |
|  | Return/Error gen |    | Saturating 8-bit |            |
|  +------------------+    | SC on read       |            |
|                          +------------------+            |
|  +------------------+                                    |
|  | keyex_bridge     |    +------------------+            |
|  |                  |    | ls_cad_bridge    |            |
|  | Route 0x7C/0x7D  |    |                  |            |
|  | Format response  |    | Route LS CADs    |            |
|  +------------------+    +------------------+            |
|                                                          |
+=========================================================+
```

### 17.1 Module Descriptions

| Module | Function | Root/Non-Root |
|--------|----------|---------------|
| oam_top | Top-level instantiation, mux root/non-root mode | Both |
| oam_tx_fsm | TX state machine per Figs 5-7/5-9 | Both (parameterized) |
| oam_rx_fsm | RX state machine per Figs 5-8/5-10 | Both (parameterized) |
| oam_header_gen | Assemble 24-byte header, snapshot registers | Both |
| oam_header_check | Validate received header, generate error events | Both |
| cad_cmd_fifo | Application command queue (root sends commands) | Root only |
| cad_resp_fifo | Response queue (non-root sends responses) | Non-root only |
| cad_parser | Decode command byte, extract fields, dispatch | Both |
| longatom_fifo | Buffer Write CADs during LongAtom sequence | Non-root only |
| reg_access_bridge | Issue read/write to register file, check access | Non-root |
| error_counters | 4x 8-bit saturating SC counters (2.2208-2.2209) | Both |
| keyex_bridge | Extract/format KeyExMsg, interface to KeyEx entity | Non-root |
| ls_cad_bridge | Route Light Sleep CADs to/from LS FSM | Both |

### 17.2 Configuration Parameter

The OAM entity must be parameterizable for root vs non-root mode. In a typical
implementation:
- Root mode: has CADcmdFIFO, per-nID state, no CADrespFIFO/LongAtomFIFO
- Non-root mode: has CADrespFIFO, LongAtomFIFO, no CADcmdFIFO

IMPLEMENTATION ASSUMPTION: A single RTL can support both modes with a configuration
register or synthesis parameter.

---

## 18. MLE OAM Adaptation (Section 8.6.2, p300)

For MLE (Multi-Link Extension) physical layer modes, OAM uses the same frame format
from Section 5.5 but with additional encoding:

- OAM frame is 4b/5b encoded character-by-character
- SOP: two control character groups (JJ, then JK)
- EOP: control character group TI
- IDLE: II groups between OAM frames
- CRC8 appended after last OAM frame byte (before EOP)
- CRC8 resets per OAM frame

The OAM entity itself does not change. The MLE adaptation layer (Section 8.6.2)
handles encoding/fragmentation below the OAM entity.

---

## 19. OAM Session Model

### 19.1 Root Node Sessions

SPEC FACT: "The root node runs an OAM session with each non-root node" (5.5, p171).

- One independent OAMframeID counter per non-root node (nID.txOAMframeID)
- One independent receive counter per non-root node (nID.rxOAMframeID)
- Root decides which nID to address in each OAM slot ("depends on application")

### 19.2 Non-Root Node Session

SPEC FACT: "Each non-root node only runs a single OAM session with the root node."

- Single txOAMframeID counter
- Single rxOAMframeID counter
- Responds only to root, no peer-to-peer OAM

---

## 20. Open Issues and Assumptions

### 20.1 Implementation Assumptions (NOT in spec)

1. CADcmdFIFO depth: spec does not define. Must be sized for application.
   Minimum = one OAM frame worth of commands (27 CADs at 6 bytes each).

2. CADrespFIFO depth: spec does not define. Minimum = responses to one frame
   of Read/Write commands (27 responses at 6 bytes each).

3. LongAtomFIFO depth: spec implies up to 32 frames * ~27 Writes = 864 Writes.
   Each Write stores 6 bytes (domain, dlp_id, addr, data). Total ~5KB.
   INFORMATIVE NOTE in spec: "allows atomic programming of Mapper table including
   some headroom through the upstream channel."

4. Root node scheduling policy (which nID to talk to when) is application-defined.
   Spec does not specify round-robin, priority, or other policy.

5. The spec does not define latency requirements for register access. It is
   assumed reads/writes complete within one OAM frame cycle.

6. Vendor-defined LinkHealthStatus4-9 (bytes 18-23) are not specified.
   Implementation may leave as 0x00 or map to application-specific registers.

### 20.2 Missing / Needs Verification

1. **LSannounce/LSconfirm/LSdeny/LSsleep command codes**: The extraction fuses
   sections 5.5.3.10-5.5.3.13 into a single chunk. The exact 7-bit command codes
   for LSannounce (0x0A), LSconfirm (0x0B), LSdeny (0x0C), LSsleep (0x0D) are
   inferred from Table 5-4 ordering but the extraction does not render the table
   clearly enough to confirm exact hex values. VERIFY against PDF Table 5-4, p177.

2. **KeyExMsg exact command codes**: VERIFIED against PDF Table 5-4 and Tables 6-3/6-4.
   Request command = 0x7C, response command = 0x7D. The "0x7D/0x7E reserved"
   informational text in Section 6.4.2 is treated as a spec typo because the formal
   mapping tables are unambiguous.

3. **OAM frame maximum CAD capacity**: 188 - 24 = 164 bytes available for CADs +
   padding. Spec says "adaptive padding is added by the OAM to the end of
   oam_payload to provide the requested payload size independent of OAM frame
   length." This means unused bytes are zero-padded. Confirm that CAD parser stops
   at CADnext=0, not at end of 164 bytes.

4. **Extended header for Node-Discover**: Section 5.5.4.1.1 says HeaderType=1 and
   uses three targetIDs (targetID1, targetID2, targetID3 via DLP_TX.oamUnit ndEn
   parameter). The OAM entity must support extended header generation for enumeration.
   Exact header format for extended mode is defined in DLL (Section 5.2.2.5) not OAM.
   VERIFY interaction between OAM ndEn flag and DLL header extension.

5. **OAMerror encoding completeness**: Table 5-2 shows OAMerror field (3 bits) with
   codes 000-100 defined and 101-111 reserved. The structured extraction shows a
   slightly different encoding ("011: decoding error in OAM header" vs "100: decoding
   error in CAD or CADs"). The spec uses the same field to report OAMHEADER_DECODE_ERR
   (code 011) and OAMPAYLOAD_DECODE_ERR (code 100) but it is unclear how
   OAMHEADER_DUPLID_ERR (code 001) and OAMHEADER_MISSID_ERR (code 010) map when
   both occur simultaneously. VERIFY priority/precedence.

6. **secStat parameter in DLP_RX.oamUnit**: The primitive carries secStat but
   the OAM processing description does not reference it. Likely indicates whether
   the container was security-processed. VERIFY whether OAM should check secStat.

7. **Image 28/30/31 sequence diagrams**: These show External SW -> Root SW ->
   Root Device -> Device interaction but are low resolution in extracted form.
   The key architectural insight is that Root SW (external host) drives the
   OAM command sequence -- the OAM entity in the Root Device acts as a bridge
   between the external interface and the ASA OAM protocol.
   VERIFY whether the spec defines a local host interface to OAM or leaves it
   as implementation-defined.

---

## 21. Summary

The OAM control plane is a mandatory sub-block of the Data Link Layer that:

1. Assembles/disassembles 188-byte OAM frames with a 24-byte header containing
   PTBclk, PTBstatus, link health, OAMframeID, and error reporting
2. Parses/generates 14+ CAD command types for register access, enumeration,
   normal mode transition, Light Sleep, and Key Exchange
3. Implements 4 distinct FSMs (root TX, root RX, non-root TX, non-root RX)
4. Provides atomic register batch-write via LongAtom/LongAtomClose buffering
5. Routes KeyExMsg exclusively to/from the Security entity
6. Captures PTBclk at frame assembly time for clock synchronization
7. Maintains per-session OAMframeID counters and 4 error counters (SC registers)
8. Is always DLP_TX_ID=0 / DLP_RX_ID=0 (dedicated mapper slot)
