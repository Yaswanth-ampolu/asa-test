# Micro-Architecture: ASEP eDP (VESA embedded DisplayPort)

## 1. Purpose and Scope

This document defines the micro-architecture of the ASEP eDP encoder/decoder module
(ASE and ASD) for RTL or golden-model implementation. It is derived directly from ASA
Technical Specification v2.0, Section 7.9 (pages 264-276).

The eDP ASEP transports VESA DisplayPort and embedded DisplayPort traffic over an ASA
Motion Link, acting as a physical-layer substitute for the DP link between a DPTX (ECU)
and a DPRX (Display Unit) or Branch device. It provides the ASA transceiver with the
ability to carry unidirectional Main Link video data and bidirectional AUX channel
transactions without requiring an actual DP PHY between the two nodes.

Scope boundaries:
- IN SCOPE: eDP ASEP packet encoding and decoding, all six packet types (Main Link VB,
  Main Link Data EDM, AUX, Stream Clock, 8b10b PLM, 128b/132b PLM), Komma symbol
  handling, VB-ID/Mvid/Maud multiplicity, AUX HPD state encoding, stream clock
  M_vid,ptb / N_vid,ptb formula, footer CRC32, interface to ASEP common framing
- OUT OF SCOPE: VESA DP PHY (scrambler, 8b10b encoder, FEC, lane skew) -- those are
  external DP IP; HDCP AES cipher engine; DSC compression/decompression; ASEP common
  framing byte 0/1 container format (covered in micro-architecture-asep-common-framing.md);
  PTB clock service (covered in micro-architecture-ptb-clock-service.md); DP Link Policy
  Maker and Stream Policy Maker logic

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 7.9 | ASEP Format: VESA embedded Display Port (eDP) | 264 | Top-level scope |
| 7.9.1.1 | References to Non-ASA Standards | 264 | External standard refs |
| 7.9.1.2.1 | Terms from Non-ASA Standards -- Display Port | 264 | Glossary |
| 7.9.2 | Overview | 264-265 | Channel model, Fig 7-4 |
| 7.9.2.1 | Encapsulated Features | 265 | EDM vs PLM feature sets |
| 7.9.2.2 | Relation of ASEP to Display Port Stack | 265-266 | Layer boundary, Fig 7-5 |
| 7.9.2.3 | Relation of ASEP Coding to DP Coding | 266-267 | Komma/VB-ID semantics, Fig 7-6 |
| 7.9.2.4 | Plain Lane Encapsulation Modes | 267 | PLM reference points |
| 7.9.3.1 | eDP ASEP Packet Header | 267 | Table 7-56: packet type field |
| 7.9.3.2 | VESA Mapping | 267 | Overview |
| 7.9.3.2.1 | Main Link VB Packet -- EDM | 267-268 | Tables 7-57, 7-58 |
| 7.9.3.2.2 | Main Link Data Packet -- EDM | 268-271 | Tables 7-59 to 7-63 |
| 7.9.3.2.3 | AUX Packet | 271-272 | Tables 7-64, 7-65 |
| 7.9.3.2.4 | Main Link -- 8b10b PLM | 272-273 | Tables 7-66 to 7-69 |
| 7.9.3.2.5 | Main Link -- 128b/132b PLM | 273-275 | Tables 7-70 to 7-73 |
| 7.9.3.3.1 | Stream Clock Packet | 275-276 | Table 7-74 |
| 7.9.3.4 | eDP ASEP Packet Footer | 276-277 | Table 7-75 |
| 7.3 | Common ASEP Format Basics | 231-236 | Container framing, stream type |
| 7.3.2 | Common ASEP Format Basics per Header | 235 | Table 7-4: byte 0 stream type |
| 7.3.2.1 | ASEP PTB Time Stamps | 235-236 | Tables 7-5, 7-6, 7-7 |
| 3.5.7 | ASEP (e)DP Specific Registers | 83-84 | No eDP-specific registers defined |
| 3.5.1.2 | ASEP Stream Type (4/5.i.0004) | 68 | Stream type 0x06 = (e)DP |
| 4.2.9 | CRC32 definition | 104 | Footer CRC polynomial |

Non-ASA standards references (Section 7.9.1.1):
- [asep_dp_01] VESA DisplayPort Standard Version 2.1, 10 October 2022
- [asep_dp_02] VESA Embedded DisplayPort Standard v1.5, 26 August 2021
- [asep_dp_03] Mapping HDCP to DisplayPort Revision 2.3, 22 January 2019

Image references (docpdfmd/images/):
- 76_Figure_7-4_Encapsulated_channels_DP.png  -- Figure 7-4: DPTX/DPRX channel model
- 77_Figure_7-5_Logical_stream_mapping_DP_ASEP.png -- Figure 7-5: DP stack layer boundary
- 78_Figure_7-6_Frame_composition_DP.png -- Figure 7-6: DP frame composition
- img-273.png -- page 273 128b/132b payload tables (4-lane)

---

## 3. eDP Encapsulation Model

### 3.1 Channel Model (Section 7.9.2, Figure 7-4)

SPEC FACT: The eDP ASEP provides encapsulation formats for the unidirectional Main
Link and bidirectional AUX channel (Section 7.9.2, p264).

SPEC FACT: The AUX channel is transmitted bidirectional always completing a transaction
(Section 7.9.2, p264).

SPEC FACT: VESA DP defined mechanisms of the Stream Policy Maker and Link Policy Maker
(see [asep_dp_01] section 2.1) are untouched by this specification (Section 7.9.2, p264).

```
       +-----------+   AUX+HPD (bidirectional)   +-----------+
       |           |<===========================>|           |
       |   DPTX    |                             |   DPRX    |
       |           |===========================> |           |
       +-----------+   Main Link (unidirectional) +-----------+
             |                    ^                    |
        [ASEP eDP encoder]   [ASA Motion Link]  [ASEP eDP decoder]
             |                                         |
        [ASA Transceiver DnTX/UpRX]            [ASA Transceiver DnRX/UpTX]
```

The ASA Motion Link substitutes the DP Physical Layer between two DP nodes.

### 3.2 DP Stack Layer Boundary (Section 7.9.2.2, Figure 7-5)

SPEC FACT: ASEP packets for the Main Link encapsulate the data stream at the Link/PHY
Layer Boundary, after (optional) HDCP encoder and before the skew insertion / scrambler
(see [asep_dp_01] Figure 2-8) (Section 7.9.2.2, p265).

This means the ASEP eDP encoder receives:
- For EDM: pre-scrambler, pre-8b10b-encoding data symbols plus Komma control symbols
- For 8b10b PLM: post-8b10b-encoder (output of "Encoder" in [asep_dp_01] Figure 2-8)
- For 128b/132b PLM: post-pre-coding (output of "Pre-Coding" in [asep_dp_01] Figure 3-29)

SPEC FACT: The DPTX blocks from lane skew insertion, scrambler, 8b10b encoder, FEC
encoder + interleaving, and TX driver are NOT present on the ASA ECU side when using
eDP ASEP -- they are present only on the Display Unit side (Section 7.9.2.2, p266).

references non-ASA standards: The DP stack layer boundary is defined in VESA DP Standard
v2.1 Figure 2-8 [asep_dp_01].

### 3.3 Encapsulated Features (Section 7.9.2.1, p265)

SPEC FACT: In Essential Data Mode (EDM), the ASEP supports encapsulation of:
- SST Stream Source with 8-bit symbol size (8b/10b mapping), including:
  - MSA (Main Stream Attributes)
  - SDP (Secondary Data Packets)
  - VB-ID
  - Mvid
  - Maud
  - Dummy bytes
- DSC-compressed Stream Source
- HDCP-encrypted Stream Source

SPEC FACT: In Plain Lane Mode (PLM), the complete lane-allocated PHY Layer coded stream
is encapsulated. The spec notes this as a fail-safe mode with full DP compatibility
(informative) (Section 7.9.2.1, p265).

SPEC FACT: The AUX_CH is separate from the Main Link and always encapsulated the same
way (Section 7.9.2.1, p265).

IMPLEMENTATION ASSUMPTION: An eDP ASE instantiation will typically operate in either
EDM or PLM, not both simultaneously. Mode selection is implementation-defined and
likely configured via OAM register write during startup.

### 3.4 Relation of ASEP Coding to DP Coding (Section 7.9.2.3, p266)

SPEC FACT: The eDP ASEP packets for the Main Link pack Data Symbols, Komma Symbols,
and Stuffed Data Symbols without the coding overhead of the VESA DP physical layer
(Section 7.9.2.3, p266).

SPEC FACT: The eDP ASEP builds on the VESA defined lane byte order mapping (including
zero padding), see [asep_dp_01] section 2.2.1.3 (Section 7.9.2.3, p266).

SPEC FACT: Komma characters are only transmitted once per occurrence (regardless of the
number of lanes coded), but VB-ID, Mvid, and Maud are transmitted duplicated 4 times
to fulfill VESA specification (see [asep_dp_01] Figure 2-12) (Section 7.9.2.3, p266).

SPEC FACT: Komma Symbols are present as delimiters of data in all supported scenarios
(EDM, HDCP, DSC) and are therefore used as start and end markers of eDP ASEP packets
(Section 7.9.2.3, p267).

SPEC FACT: When no HDCP is used, Stuffed Data Symbols between FS and FE can be dropped
(not encapsulated). Valid data of consecutive Transfer Units is then transmitted combined
in one Main Link ASEP packet, i.e., one video line (Section 7.9.2.3, p267).

SPEC FACT: The ASA physical layer FEC provides at least the same integrity protection as
the mandatory DP FEC for DSC compressed streams, and applies to all data. Therefore the
DP FEC is not required on the ASA link (Section 7.9.2.3, p266).

SPEC FACT: For HDCP: in SST mode, all data symbols (including video data, secondary
data, and dummy symbols) must be encrypted and K-codes must not be encrypted (see
[asep_dp_03] section 3.1). The HDCP cipher does not advance in cycles carrying DP FEC
control codes (Section 7.9.2.3, p267).

references non-ASA standards: Komma symbol encoding, VB-ID/Mvid/Maud lane mapping, and
the DP frame composition diagram (Figure 7-6) are defined in [asep_dp_01] sections
2.2.1.3 and Figure 2-12.

### 3.5 Plain Lane Encapsulation Modes (Section 7.9.2.4, p267)

SPEC FACT: Plain lane encapsulation modes are defined for the DP 8b/10b Link Layer and
for the DP 128b/132b Link Layer. In these modes, the fully coded output of the Main-Link
PHY Logical Sublayer is encapsulated:
- 8b/10b PLM: reference point is output of "Encoder" per [asep_dp_01] Figure 2-8
- 128b/132b PLM: reference point is output of "Pre-Coding" per [asep_dp_01] Figure 3-29

references non-ASA standards: PHY Logical Sublayer encoder output definitions per VESA
DP Standard v2.1 [asep_dp_01] Figures 2-8 and 3-29.

---

## 4. ASEP Stream Type Registration

SPEC FACT: The ASEP stream type value for (e)DP is 0x06 (Table 7-1, Section 7.3, p233).

SPEC FACT: Register 4/5.i.0004 (ASEP Stream Type, bits 6:0) is set to 0x06 for an eDP
ASE/ASD port (Section 3.5.1.2, p68).

SPEC FACT: Section 3.5.7 "ASEP (e)DP Specific" explicitly states "None" -- there are no
eDP-specific registers beyond the common ASEP register set (Section 3.5.7, p83).

---

## 5. Common ASEP Framing Wrapper

The eDP ASEP packet is transported inside the common ASEP framing defined in Section 7.3.
The eDP-specific header described in Sections 7.9.3.1-7.9.3.3 sits between the common
ASEP header and the footer.

### 5.1 Common ASEP Container Bytes (Section 7.3.1)

Each DLL container payload starts with 1-2 framing bytes:
```
Byte 0:
  7:6  ASEP packet fragmentation
         00: no packet boundary in this container
         01: packet ends on last byte of container
         10: packet end then padding from boundary position
         11: packet end then new ASEP header at boundary position
  5:0  ASEP packet boundary position [9:4]

Byte 1 (if fragmentation[7]=1):
  7:4  ASEP packet boundary position [3:0]
  3:0  reserved
```

### 5.2 Common ASEP Header -- Byte 0 (Section 7.3.2, Table 7-4)

```
Byte  Bit(s)  Name                     Description
----  ------  ----                     -----------
 0    7:1     ASEP stream type         0x06 = (e)DP (Table 7-1)
 0    0       Same container follow    0: no further ASEP header in container
                                       1: another ASEP header follows
```

### 5.3 Common ASEP Header -- Byte 1 and PTB Timestamp (Section 7.3.2.1, Tables 7-5/7-6/7-7)

```
Byte  Bit(s)  Name              Description
----  ------  ----              -----------
 1    7:2     reserved
 1    1:0     PTB time stamp    00: none
                                01: ingress time stamp (4 bytes follow)
                                10: presentation time stamp (4 bytes follow)
                                11: user defined (4 bytes follow)
 2    7:0     PTBstamp[31:24]   Lower 32 bits of PTBclk (if stamp != 00)
 3    7:0     PTBstamp[23:16]
 4    7:0     PTBstamp[15:8]
 5    7:0     PTBstamp[7:0]
```

IMPLEMENTATION ASSUMPTION: For eDP, ingress time stamp (01) may be used on the ASE
side to mark the capture time of the first symbol of a VB packet or video line. The
precise timestamp mode to use is not specified by Section 7.9 and is
implementation-defined.

The common header ends at byte 1 (no PTB stamp) or byte 5 (with PTB stamp). The eDP-
specific header begins at the next byte (m_HB + 0 in 7.9.3 notation, where m_HB is the
first byte after the common header).

---

## 6. eDP ASEP Packet Header (Section 7.9.3.1, Table 7-56)

SPEC FACT: The eDP ASEP packet header is shared among all modes and packet types
(Section 7.9.3.1, p267).

```
Byte       Bit(s)  Name                   Description
--------   ------  ----                   -----------
m_HB+1     7:5     ASEP (e)DP pkt type    000: EDM, Main Link VB packet
                                          001: EDM, Main Link data packet
                                          010: AUX packet
                                          011: Stream clock packet
                                          100: PLM, 8b/10b Link Layer
                                          101: PLM, 128b/132b Link Layer
                                          110: reserved
                                          111: reserved
m_HB+1     4:0     (type-specific)        See packet-specific tables below
```

The 3-bit type field is the exclusive discriminator for all six eDP ASEP packet formats.
There is no separate "mode" register; the type field in each packet self-identifies the
encapsulation mode.

---

## 7. VESA Mapping Packets

### 7.1 Main Link VB Packet -- Essential Data Mode (Section 7.9.3.2.1, Tables 7-57/7-58)

SPEC FACT: The Main Link VB Packet implies the Blanking Start Komma Symbol (or its
Enhanced Framing Mode equivalent) and this Komma Symbol is NOT sent in the packet
(Section 7.9.3.2.1, p267).

The VB packet carries four repetitions of VB-ID, Mvid, and Maud, corresponding to the
four DP lane occurrences mandated by VESA DP ([asep_dp_01] Figure 2-12).

#### 7.1.1 Header Extension

```
Byte       Bit(s)  Name     Description
--------   ------  ----     -----------
m_HB+1     4:0     Reserved
```

Total header: 1 byte (after common eDP header byte).

#### 7.1.2 Payload (12 bytes fixed)

```
Byte       Bit(s)  Name     Description
--------   ------  ----     -----------
m_HB+2     7:0     VB-ID0   VB-ID Lane0 / first occurrence
m_HB+3     7:0     Mvid0    Mvid Lane0 / first occurrence
m_HB+4     7:0     Maud0    Maud Lane0 / first occurrence
m_HB+5     7:0     VB-ID1   VB-ID Lane1 / second occurrence
m_HB+6     7:0     Mvid1    Mvid Lane1 / second occurrence
m_HB+7     7:0     Maud1    Maud Lane1 / second occurrence
m_HB+8     7:0     VB-ID2   VB-ID Lane2 / third occurrence
m_HB+9     7:0     Mvid2    Mvid Lane2 / third occurrence
m_HB+10    7:0     Maud2    Maud Lane2 / third occurrence
m_HB+11    7:0     VB-ID3   VB-ID Lane3 / fourth occurrence
m_HB+12    7:0     Mvid3    Mvid Lane3 / fourth occurrence
m_HB+13    7:0     Maud3    Maud Lane3 / fourth occurrence
```

Total packet size: 1 (common eDP header) + 1 (VB header ext) + 12 (payload) + 4 (footer
CRC32) = 18 bytes.

references non-ASA standards: VB-ID, Mvid, and Maud are VESA DP symbols defined in
[asep_dp_01]. The four-occurrence transmission requirement references [asep_dp_01]
Figure 2-12.

### 7.2 Main Link Data Packet -- Essential Data Mode (Section 7.9.3.2.2, Tables 7-59 to 7-63)

SPEC FACT: The Main Link Data Packet encapsulates pixel data, secondary data packets
(SDP), and stuffed data (in case of HDCP) (Section 7.9.3.2.2, p268).

SPEC FACT: Either the 1-, 2-, or 4-lane mapping of DP can be encapsulated. The four
Komma slots at the start and end allow compatibility with Enhanced Framing Mode
(Section 7.9.3.2.2, p268).

SPEC FACT: When a series of Transfer Units is encapsulated into a Main Link Data Packet,
it shall be broken at a Komma Symbol. It may also be broken arbitrarily, where all four
Komma Symbols are set to "No Komma" (Section 7.9.3.2.2, p268).

#### 7.2.1 Header Extension (4 bytes from m_HB+1 to m_HB+3)

```
Byte       Bit(s)  Name         Description
--------   ------  ----         -----------
m_HB+1     4       Dummy_sw     0: payload transmitted (recommended)
                                1: lengths and Komma only
                                   (shall NOT be used when HDCP enabled in DP)
m_HB+1     3:2     Reserved
m_HB+1     1:0     Lane Count   0: 1 lane
                                1: 2 lanes
                                2: 4 lanes
m_HB+2     7:0     Length[15:8] Length of payload in bytes (between Komma
m_HB+3     7:0     Length[7:0]  characters) per lane
```

#### 7.2.2 Payload -- 1-Lane (Table 7-60)

```
Byte         Bit(s)  Name          Description
----------   ------  ----          -----------
m_HB+4       7:0     Komma01       [7:4]=Komma0, [3:0]=Komma1
m_HB+5       7:0     Komma23       [7:4]=Komma2, [3:0]=Komma3
m_HB+6       7:0     Payload_0     First payload byte within framing
...
m_END-2      7:0     Payload_L-1   "Length-1"th payload byte within framing
m_END-1      7:0     Komma45       [7:4]=Komma4, [3:0]=Komma5
m_END        7:0     Komma67       [7:4]=Komma6, [3:0]=Komma7
```

#### 7.2.3 Payload -- 2-Lane (Table 7-61)

```
Byte         Bit(s)  Name            Description
----------   ------  ----            -----------
m_HB+4       7:0     Komma01         [7:4]=Komma0, [3:0]=Komma1
m_HB+5       7:0     Komma23         [7:4]=Komma2, [3:0]=Komma3
m_HB+6       7:0     Payload_0       First payload byte Lane0 within framing
m_HB+7       7:0     Payload_1       First payload byte Lane1 within framing
m_HB+8       7:0     Payload_2       Second payload byte Lane0 within framing
...
m_END-2      7:0     Payload_L*2-1   "Length-1"th payload byte Lane1
m_END-1      7:0     Komma45         [7:4]=Komma4, [3:0]=Komma5
m_END        7:0     Komma67         [7:4]=Komma6, [3:0]=Komma7
```

SPEC FACT: In the case of 2-Lane and 4-Lane payload, the DP zero-padding for equal
number of payload bytes on each lane is transmitted as well (Section 7.9.3.2.2, p268).

#### 7.2.4 Payload -- 4-Lane (Table 7-62)

```
Byte         Bit(s)  Name            Description
----------   ------  ----            -----------
m_HB+4       7:0     Komma01         [7:4]=Komma0, [3:0]=Komma1
m_HB+5       7:0     Komma23         [7:4]=Komma2, [3:0]=Komma3
m_HB+6       7:0     Payload_0       First payload byte Lane0 within framing
m_HB+7       7:0     Payload_1       First payload byte Lane1 within framing
m_HB+8       7:0     Payload_2       First payload byte Lane2 within framing
m_HB+9       7:0     Payload_3       First payload byte Lane3 within framing
m_HB+10      7:0     Payload_4       Second payload byte Lane0 within framing
...
m_END-2      7:0     Payload_L*4-1   "Length-1"th payload byte Lane3
m_END-1      7:0     Komma45         [7:4]=Komma4, [3:0]=Komma5
m_END        7:0     Komma67         [7:4]=Komma6, [3:0]=Komma7
```

#### 7.2.5 Komma Codes (Table 7-63)

SPEC FACT: The following table lists the 4-bit Komma field codes used in all EDM Data
Packets. Left column maps DP Control Link Symbols; right column defines ASA-specific
codes (Section 7.9.3.2.2, p271).

```
Komma Code[3:0]   DP Control Link Symbol   |  Komma Code[3:0]   Meaning
---------------   ----------------------   |  ---------------   -------
0001              BS                       |  1101              SDPsplit (SDP continues
0010              BE                       |                    in next Data Packet)
0011              FS                       |  0000              No Komma
0100              FE                       |  others            Reserved
0101              SS                       |
0110              SE                       |
0111              SR                       |
1000              CP                       |
1001              CPBS                     |
1010              CPSR                     |
1011              BF                       |
1100              EOC                      |
```

references non-ASA standards: BS (Blanking Start), BE (Blanking End), FS (Fill Start),
FE (Fill End), SS (Stream Start), SE (Stream End), SR (Stream Resume), CP
(Content Protection), CPBS, CPSR, BF (Buffer Flush), EOC (End of Content) are VESA DP
Control Link Symbols defined in [asep_dp_01].

### 7.3 AUX Packet (Section 7.9.3.2.3, Tables 7-64/7-65)

SPEC FACT: The AUX packet payload is one AUX transaction per [asep_dp_01] section 2.11
(Section 7.9.3.2.3, p271).

SPEC FACT: The eDP ASEP packet for AUX encapsulates one transaction per packet
(Section 7.9.2.3, p267).

#### 7.3.1 Header Extension

```
Byte       Bit(s)  Name      Description
--------   ------  ----      -----------
m_HB+1     4:3     HPDstate  00: low (not connected)
                             01: normal high
                             10: Interrupt request
                             11: hot plug detect
m_HB+1     2:0     Reserved
m_HB+2     7:5     Reserved
m_HB+2     4:0     Length    Number of bytes in payload;
                             can be zero for HPD state transmission only
```

#### 7.3.2 Payload (Table 7-65)

```
Byte       Bit(s)  Name          Description
--------   ------  ----          -----------
m_HB+3     7:0     Payload_0     First payload byte
...
m_END      7:0     Payload_L-1   "Length-1"th payload byte
```

Total header: 1 (common eDP hdr) + 2 (AUX hdr ext) = 3 bytes.
Maximum payload: 31 bytes (5-bit Length field, value 0x1F).

IMPLEMENTATION ASSUMPTION: The AUX packet covers both the downstream (DPTX->DPRX AUX
REQUEST) and upstream (DPRX->DPTX AUX REPLY) directions. Since ASA supports
bidirectional DLP ports, the ASE at the DPTX side sends requests and the ASD at the
DPRX side delivers replies via the return path. Coordinating the bidirectional AUX
channel over a unidirectional ASEP stream requires an AUX ASE/ASD pair in opposite
directions or an ASEP transceiver arrangement.

references non-ASA standards: AUX transaction format, HPD state semantics, and AUX
channel protocol per [asep_dp_01] section 2.11.

---

## 8. Plain Lane Mode Packets

### 8.1 Main Link -- 8b10b Plain Lane Mode (Section 7.9.3.2.4, Tables 7-66 to 7-69)

SPEC FACT: It is recommended that the payload of one packet contains all data of a
single line of the full frame (Section 7.9.3.2.4, p272).

#### 8.1.1 Header Extension

```
Byte       Bit(s)  Name         Description
--------   ------  ----         -----------
m_HB+1     4:2     Reserved
m_HB+1     1:0     Lane Count   0: 1 lane
                                1: 2 lanes
                                2: 4 lanes
m_HB+2     7:0     Length[15:8] Length of payload in 10-bit symbols
m_HB+3     7:0     Length[7:0]
```

SPEC FACT: 8b10b PLM -- in 1-Lane payload, a multiple of four 10-bit payload symbols
are coded. If the fragment of DP data is not divisible by 4, it is padded with zeros
(Section 7.9.3.2.4, p272).

SPEC FACT: 8b10b PLM -- in 2-Lane payload, a multiple of two 10-bit payload symbols per
lane are coded. If the fragment is not divisible by 2, it is padded with zeros
(Section 7.9.3.2.4, p272).

#### 8.1.2 Payload -- 1-Lane (Table 7-67)

The 10-bit symbols are packed MSB-first across bytes with no padding between symbols
within a group of 4:

```
Byte         Bit(s)  Name                 Description
----------   ------  ----                 -----------
m_HB+4       7:0     Payload_0[9:2]       First 10-bit symbol, bits 9:2
m_HB+5       7:6     Payload_0[1:0]       First 10-bit symbol, bits 1:0
m_HB+5       5:0     Payload_1[9:4]       Second 10-bit symbol, bits 9:4
m_HB+6       7:4     Payload_1[3:0]       Second 10-bit symbol, bits 3:0
m_HB+6       3:0     Payload_2[9:6]       Third 10-bit symbol, bits 9:6
m_HB+7       7:2     Payload_2[5:0]       Third 10-bit symbol, bits 5:0
m_HB+7       1:0     Payload_3[9:8]       Fourth 10-bit symbol, bits 9:8
m_HB+8       7:0     Payload_3[7:0]       Fourth 10-bit symbol, bits 7:0
...
m_END-1      1:0     Payload_L-1[9:8]     Last symbol or zero-padding
m_END        7:0     Payload_L-1[7:0]
```

4 symbols packed into 5 bytes (10*4 = 40 bits = 5 bytes). No intra-group padding.

#### 8.1.3 Payload -- 2-Lane (Table 7-68)

Symbols are interleaved lane-by-lane: Lane0 symbol N, Lane1 symbol N, Lane0 symbol N+1, ...

```
Byte         Description
----------   -----------
m_HB+4..5    Payload_0[9:2]/[1:0] -- First symbol Lane0
m_HB+5..6    Payload_1[9:4]/[3:0] -- First symbol Lane1
m_HB+6..7    Payload_2[9:6]/[5:0] -- Second symbol Lane0
m_HB+7..8    Payload_3[9:8]/[7:0] -- Second symbol Lane1
...
m_END-1/END  Last symbol Lane1 or zero-padding
```

#### 8.1.4 Payload -- 4-Lane (Table 7-69)

Symbols interleaved: L0_N, L1_N, L2_N, L3_N, L0_N+1, ...

```
Byte         Description
----------   -----------
m_HB+4..5    Payload_0[9:2]/[1:0] -- First symbol Lane0
m_HB+5..6    Payload_1[9:4]/[3:0] -- First symbol Lane1
m_HB+6..7    Payload_2[9:6]/[5:0] -- First symbol Lane2
m_HB+7..8    Payload_3[9:8]/[7:0] -- First symbol Lane3
...
m_END-1/END  Last symbol Lane3
```

IMPLEMENTATION ASSUMPTION: The 10-bit symbol packing across byte boundaries requires a
bit-shift/barrel-rotate operation. A 5-byte shift register or 40-bit accumulator is the
natural implementation unit for packing 4 symbols per group.

### 8.2 Main Link -- 128b/132b Plain Lane Mode (Section 7.9.3.2.5, Tables 7-70 to 7-73)

SPEC FACT: It is recommended that the payload of one packet contains all data of a
single line of the full frame (Section 7.9.3.2.5, p273).

#### 8.2.1 Header Extension

```
Byte       Bit(s)  Name         Description
--------   ------  ----         -----------
m_HB+1     4:0     Reserved
m_HB+2     7:0     Length[15:8] Length of payload in 132-bit symbols
m_HB+3     7:0     Length[7:0]
```

Note: no Lane Count field. The 128b/132b mode uses a single lane per DP spec.
References are to the single-lane encoded stream; 2-lane and 4-lane variants pack
multiple lane streams into the same packet.

SPEC FACT: 128b/132b PLM -- in 1-Lane payload, a multiple of two 132-bit payload symbols
are coded. If not divisible by 2, the last byte is padded with zeros
(Section 7.9.3.2.5, p273).

SPEC FACT: 128b/132b PLM -- in 2-Lane payload, a multiple of two 132-bit payload symbols
are coded (Section 7.9.3.2.5, p274).

SPEC FACT: 128b/132b PLM -- in 4-Lane payload, a multiple of four 132-bit payload symbols
are coded (Section 7.9.3.2.5, p274).

#### 8.2.2 Payload -- 1-Lane (Table 7-71)

Each 132-bit symbol spans 16 bytes + 4 bits (132 / 8 = 16.5 bytes). Two symbols are
packed together into 33 bytes exactly:

```
Byte               Bit(s)  Name                     Description
---------          ------  ----                     -----------
m_HB+4             7:0     Payload_0[131:124]        First 132-bit symbol Lane0
m_HB+5 .. m_HB+19  all     Payload_0[123:4]
m_HB+20            7:4     Payload_0[3:0]
m_HB+20            3:0     Payload_1[131:128]        Second 132-bit symbol Lane0
m_HB+21 .. m_HB+36 all     Payload_1[127:0]
...
m_END              7:0     Payload_L-1[7:0]          Last byte, nibble+4-bit zero-padding
                                                      if not divisible by 2
```

Two 132-bit symbols = 264 bits = 33 bytes. The half-byte boundary is handled by
splitting the 4 high bits of the second symbol into the lower nibble of the 17th byte
and the upper nibble of the 18th byte relative to the start of the first symbol.

#### 8.2.3 Payload -- 2-Lane (Table 7-72)

Two 132-bit symbols per lane packed sequentially: L0_0, L1_0, L0_1, L1_1, ...

```
m_HB+4  .. m_HB+20  Payload_0  -- First 132-bit symbol Lane0
m_HB+20 .. m_HB+36  Payload_1  -- First 132-bit symbol Lane1 (shared nibble at m_HB+20)
m_HB+37 .. m_HB+53  Payload_2  -- Second 132-bit symbol Lane0
...
m_END               Payload_L-1[7:0]  -- Last payload byte of Lane1
```

#### 8.2.4 Payload -- 4-Lane (Table 7-73)

Four 132-bit symbols packed per group: L0_0, L1_0, L2_0, L3_0, L0_1, ...

```
m_HB+4  .. m_HB+20  Payload_0  -- First 132-bit symbol Lane0
m_HB+20 .. m_HB+36  Payload_1  -- First 132-bit symbol Lane1 (shared nibble m_HB+20)
m_HB+37 .. m_HB+53  Payload_2  -- First 132-bit symbol Lane2
m_HB+53 .. m_HB+69  Payload_3  -- First 132-bit symbol Lane3 (shared nibble m_HB+53)
m_HB+70 .. m_HB+86  Payload_4  -- Second 132-bit symbol Lane0
m_HB+86 ..          Payload_5  -- (continues pattern)
...
m_END               Payload_L-1[7:0]  -- Last payload byte of Lane3
```

IMPLEMENTATION ASSUMPTION: The 128b/132b packing requires nibble-level byte splitting
at every other symbol boundary. An implementation may use a 17-byte (136-bit) shift
register with a half-byte pointer to handle the 132-bit / 16.5-byte alignment.

---

## 9. Meta-Information Packets

### 9.1 Stream Clock Packet (Section 7.9.3.3.1, Table 7-74)

SPEC FACT: The DP stream clock information is coded relative to ASA PTB. This information
provides a similar reference to the DPRX for reconstructing the stream clock
(Section 7.9.3.3.1, p275).

SPEC FACT: The stream clock formula is:

    f_StrmClk = M_vid,ptb / N_vid,ptb * f_PTB

where 24-bit resolution allows 14.9 Hz resolution for stream clock values < 250 MHz
(Section 7.9.3.3.1, p276).

#### 9.1.1 Header Extension (1 byte)

```
Byte       Bit(s)  Name     Description
--------   ------  ----     -----------
m_HB+1     4:0     Reserved
```

#### 9.1.2 Payload (6 bytes)

```
Byte       Bit(s)  Name              Description
--------   ------  ----              -----------
m_HB+2     7:0     M_vid,ptb[23:16]  Unsigned integer, MSB first
m_HB+3     7:0     M_vid,ptb[15:8]
m_HB+4     7:0     M_vid,ptb[7:0]
m_HB+5     7:0     N_vid,ptb[23:16]  Unsigned integer, MSB first
m_HB+6     7:0     N_vid,ptb[15:8]
m_HB+7     7:0     N_vid,ptb[7:0]
```

Total packet: 1 (common eDP hdr) + 1 (stream clock hdr ext) + 6 (payload) +
              4 (footer CRC32) = 12 bytes.

#### 9.1.3 PTB Context and Relation to I2S / Section 7.10.1.1

The M/N ratio pattern for stream clock derivation is analogous to the I2S Audio Sampling
Rate to PTB Synchronization method defined in Section 7.10.1.1. In both cases:
- A numerator value (M_vid,ptb or M_aud,ptb) counts PTB ticks per media clock cycle
- A denominator value (N_vid,ptb or N_aud,ptb) provides the normalization factor
- The ratio M/N multiplied by f_PTB gives the reconstructed media clock frequency

SPEC FACT: f_PTB is the ASA Precision Time Base clock frequency distributed via the
PTB service (Section 4.2.8, p116). The PTB clock registers are at 2.2200-2.2202 (48-bit)
and PTBstatus at 2.2203.

IMPLEMENTATION ASSUMPTION: The stream clock packet is sent periodically by the ASE at a
rate sufficient for the DPRX to maintain DP clock recovery without a DP PHY PLL. The
transmission interval is not specified in Section 7.9; a reasonable implementation
sends this packet once per video frame or at a fixed sub-frame rate (e.g., every
horizontal blanking period). This is a needs-verification item.

IMPLEMENTATION ASSUMPTION: The DPRX side ASE reconstructs the DP pixel clock using a
PLL or NCO driven by the M/N ratio and f_PTB. The PTB clock at the DPRX node must be
synchronized to the same PTB master (established via the OAM header per Section 5.5.1).

references non-ASA standards: The Mvid and Maud fields in DP MSA (Main Stream Attributes)
carry the DP stream clock ratio relative to the link symbol clock, per [asep_dp_01].
The M_vid,ptb / N_vid,ptb ratio in this ASEP packet serves the same function but
relative to PTB instead of the DP link clock.

---

## 10. eDP ASEP Packet Footer (Section 7.9.3.4, Table 7-75)

SPEC FACT: The footer applies to ALL eDP ASEP packets (Section 7.9.3.4, p276).

```
Byte       Bit(s)  Name          Description
--------   ------  ----          -----------
m_END-3    7:0     CRC32[31:24]  Checksum over ASEP packet byte 0 to m_END-4
m_END-2    7:0     CRC32[23:16]  See Section 4.2.9
m_END-1    7:0     CRC32[15:8]
m_END      7:0     CRC32[7:0]
```

SPEC FACT: The CRC32 covers all bytes from byte 0 (start of the ASEP packet including
the common ASEP header byte 0) to m_END-4 inclusive (Section 7.9.3.4, p276).

SPEC FACT: The CRC32 polynomial and algorithm are defined in Section 4.2.9 (p104).

IMPLEMENTATION ASSUMPTION: The CRC32 accumulator starts at packet byte 0 (the common
ASEP stream type byte) and terminates at the byte immediately before CRC32[31:24].
The ASD checks the CRC32 after reassembly of all fragments and increments the ASD error
counter at register 3.7.1 on failure.

---

## 11. Complete Packet Size Summary

```
Packet Type          Fixed/Variable  Min size  Max size
-----------          --------------  --------  --------
VB Packet (EDM)      Fixed           18B       18B
                     (1 + 1 + 12 + 4 bytes)

Data Packet (EDM)    Variable        10B       varies
  1-lane             Variable        10 + L    10 + L
  2-lane             Variable        10 + 2L   10 + 2L
  4-lane             Variable        10 + 4L   10 + 4L
  (where header=4B, Komma=4B, payload=n*L, footer=4B)

AUX Packet           Variable        8B        36B
  (hdr=3B + payload 0..31B + footer=4B)
  (zero payload = HPD-only = 7B minimum but 8B with footer)

Stream Clock Packet  Fixed           12B       12B
  (1 + 1 + 6 + 4 bytes)

8b10b PLM Packet     Variable        8B        varies
  1-lane             Variable        8 + ceil(10*L/8)
  2-lane             Variable        8 + ceil(10*2L/8)
  4-lane             Variable        8 + ceil(10*4L/8)
  (header=4B, payload = 10-bit packed, footer=4B)

128b/132b PLM Packet Variable        8B        varies
  1-lane             Variable        8 + ceil(132*L/8)
  (header=4B, payload = 132-bit packed, footer=4B)
```

---

## 12. TX and RX Data Flow

### 12.1 TX Flow: DP Source -> ASEP eDP Encoder -> ASEP Common Framing -> DLL

```
   DP TX Side (ECU)
   +---------------------------------------------------------------+
   |                                                               |
   |  Main Stream Input Capture                                    |
   |       |                                                       |
   |  DSC / Stream Layer Blocks (optional)                         |
   |       |                                                       |
   |  Main Link Mapping                                            |
   |       |                                                       |
   |  HDCP Encoder (optional)                                      |
   |       |                                                       |
   |       v                                                       |
   |  +-----------------------+                                    |
   |  | ASEP eDP Encoder      |   <-- Capture point (Link/PHY bdy)|
   |  |                       |                                    |
   |  | EDM mode:             |                                    |
   |  |  - detect Komma sym   |                                    |
   |  |  - emit VB pkt at BS  |                                    |
   |  |  - emit Data pkt w/   |                                    |
   |  |    Komma codes        |                                    |
   |  |                       |                                    |
   |  | PLM mode:             |                                    |
   |  |  - pack 10b/132b syms |                                    |
   |  |  - emit PLM pkt       |                                    |
   |  |                       |                                    |
   |  | AUX side path:        |                                    |
   |  |  - capture AUX trans. |                                    |
   |  |  - pack HPD+payload   |                                    |
   |  |  - emit AUX pkt       |                                    |
   |  |                       |                                    |
   |  | PTB side path:        |                                    |
   |  |  - compute M_vid,ptb  |                                    |
   |  |  - compute N_vid,ptb  |                                    |
   |  |  - emit Stream Clk pkt|                                    |
   |  +-----------+-----------+                                    |
   |              |                                                |
   |              v                                                |
   |  +-----------------------+                                    |
   |  | ASEP Common Framing   |                                    |
   |  | (byte 0 = 0x06 | flg) |                                    |
   |  | (byte 1 = PTB stamp)  |                                    |
   |  | (CRC32 in footer)     |                                    |
   |  +-----------+-----------+                                    |
   |              |                                                |
   |              v                                                |
   |  DLP_TX.dataUnit() --> DLL Mapper --> PHY                     |
   +---------------------------------------------------------------+
```

### 12.2 RX Flow: DLL -> ASEP eDP Decoder -> DP Sink

```
   DP RX Side (Display Unit)
   +---------------------------------------------------------------+
   |                                                               |
   |  PHY --> DLL Demux --> DLP_RX.dataUnit()                      |
   |                                                               |
   |              |                                                |
   |              v                                                |
   |  +-----------------------+                                    |
   |  | ASEP Common Framing   |                                    |
   |  | (check stream type)   |                                    |
   |  | (check PTB stamp)     |                                    |
   |  | (reassemble fragments)|                                    |
   |  +-----------+-----------+                                    |
   |              |                                                |
   |              v                                                |
   |  +-----------------------+                                    |
   |  | ASEP eDP Decoder      |                                    |
   |  |                       |                                    |
   |  | Dispatch on type[7:5]:|                                    |
   |  |  000 -> VB pkt:       |                                    |
   |  |    reconstruct BS Kom |                                    |
   |  |    deliver VB-ID/M/M  |                                    |
   |  |  001 -> Data pkt:     |                                    |
   |  |    decode Komma codes |                                    |
   |  |    deliver data syms  |                                    |
   |  |  010 -> AUX pkt:      |                                    |
   |  |    deliver HPD state  |                                    |
   |  |    deliver AUX trans  |                                    |
   |  |  011 -> Stream Clk:   |                                    |
   |  |    update DP clk PLL  |                                    |
   |  |  100 -> 8b10b PLM:    |                                    |
   |  |    unpack 10b syms    |                                    |
   |  |    deliver to 8b10b dec|                                   |
   |  |  101 -> 128b/132b PLM:|                                    |
   |  |    unpack 132b syms   |                                    |
   |  |    deliver to pre-cod |                                    |
   |  +-----------+-----------+                                    |
   |              |                                                |
   |              v                                                |
   |  Bus Desteering                                               |
   |       |                                                       |
   |  HDCP Decoder (optional)                                      |
   |       |                                                       |
   |  DSC Decompress (optional)                                    |
   |       |                                                       |
   |  Main Stream Sink                                             |
   +---------------------------------------------------------------+
```

### 12.3 Branch Repeater Model

SPEC FACT: When the ASA node is a Branch (Repeater in DP terminology), the DPRX in
the branch receives the ASEP eDP stream on the upstream DLP_RX, decodes it, and the
DPTX in the branch re-encodes it (optionally with re-encryption via HDCP) onto the
downstream DLP_TX (Section 7.9.2.2, Figure 7-5, p266).

IMPLEMENTATION ASSUMPTION: At a branch, the AUX channel direction is reversed: upstream
AUX requests from the downstream DPRX are forwarded as new AUX packets on the upstream
ASA link, and responses flow back downstream. The branch must implement a full AUX
transaction buffer.

---

## 13. Interface to ASEP Common Framing

### 13.1 ASE Interface (TX)

```
Signal                    Direction    Width   Description
------                    ---------    -----   -----------
pkt_type_out[2:0]         out          3       eDP pkt type (000-101)
pkt_data_valid            out          1       eDP hdr/payload byte valid
pkt_data[7:0]             out          8       eDP hdr/payload byte stream
pkt_eop                   out          1       End of eDP packet (before footer)
pkt_sop                   out          1       Start of eDP packet
lane_count[1:0]           cfg-in       2       0=1L, 1=2L, 2=4L
edm_plm_sel               cfg-in       1       0=EDM, 1=PLM
plm_width_sel             cfg-in       1       0=8b10b, 1=128b/132b
ptb_clk[47:0]             in           48      PTB clock for stream clock pkt
ptb_valid                 in           1       PTB synchronized
```

### 13.2 ASD Interface (RX)

```
Signal                    Direction    Width   Description
------                    ---------    -----   -----------
pkt_type_in[2:0]          in           3       eDP pkt type from decoder
pkt_data[7:0]             in           8       Decoded payload byte stream
pkt_data_valid            in           1       Payload byte valid
pkt_eop                   in           1       End of packet
crc_ok                    in           1       Footer CRC32 passed
hpd_state[1:0]            out          2       HPD state from AUX pkt
aux_payload[7:0]          out          8       AUX transaction bytes
aux_payload_valid         out          1       AUX byte valid
stream_clk_m[23:0]        out          24      M_vid,ptb from stream clk pkt
stream_clk_n[23:0]        out          24      N_vid,ptb from stream clk pkt
stream_clk_valid          out          1       Stream clock packet received
```

### 13.3 DLP_TX Interface (from ASEP common framing to DLL)

Per Section 5.6.1:
- DLP_TX.indicateSlot: DLL signals slot is available
- DLP_TX.dataUnit(payload[7:0], byte_valid): ASE delivers container bytes
- DLP_TX.yield: ASE yields slot if no data ready

### 13.4 DLP_RX Interface (from DLL to ASEP common framing)

Per Section 5.7.1:
- DLP_RX.dataUnit(payload[7:0], byte_valid, eoc): DLL delivers container bytes

---

## 14. RTL Submodules

### 14.1 Overview Block Diagram

```
+----------------------------------------------------------+
|  ASEP eDP Module                                         |
|                                                          |
|  +--------------------+   +--------------------------+   |
|  | eDP ASE (Encoder)  |   | eDP ASD (Decoder)        |   |
|  |                    |   |                          |   |
|  | +--------------+   |   | +--------------+         |   |
|  | | VB Pkt Gen   |   |   | | VB Pkt Parse |         |   |
|  | +--------------+   |   | +--------------+         |   |
|  |                    |   |                          |   |
|  | +--------------+   |   | +--------------+         |   |
|  | | Data Pkt Gen |   |   | | Data Pkt Parse|         |  |
|  | | (EDM)        |   |   | | (EDM)         |        |   |
|  | +--------------+   |   | +--------------+         |   |
|  |                    |   |                          |   |
|  | +--------------+   |   | +--------------+         |   |
|  | | AUX Pkt Gen  |   |   | | AUX Pkt Parse|         |   |
|  | +--------------+   |   | +--------------+         |   |
|  |                    |   |                          |   |
|  | +--------------+   |   | +--------------+         |   |
|  | | Stream Clk   |   |   | | Stream Clk   |         |   |
|  | | Pkt Gen      |   |   | | Pkt Parse    |         |   |
|  | +--------------+   |   | +--------------+         |   |
|  |                    |   |                          |   |
|  | +--------------+   |   | +--------------+         |   |
|  | | PLM 8b10b    |   |   | | PLM 8b10b    |         |   |
|  | | Pkt Gen      |   |   | | Pkt Parse    |         |   |
|  | +--------------+   |   | +--------------+         |   |
|  |                    |   |                          |   |
|  | +--------------+   |   | +--------------+         |   |
|  | | PLM 128b132b |   |   | | PLM 128b132b |         |   |
|  | | Pkt Gen      |   |   | | Pkt Parse    |         |   |
|  | +--------------+   |   | +--------------+         |   |
|  |                    |   |                          |   |
|  | +--------------+   |   | +--------------+         |   |
|  | | Komma Encoder|   |   | | Komma Decoder|         |   |
|  | +--------------+   |   | +--------------+         |   |
|  |                    |   |                          |   |
|  | +--------------+   |   | +--------------+         |   |
|  | | CRC32 Calc   |   |   | | CRC32 Check  |         |   |
|  | +--------------+   |   | +--------------+         |   |
|  +--------------------+   +--------------------------+   |
|                                                          |
|  +----------------------------------------------------+  |
|  | Stream Clock M/N Ratio Calculator                  |  |
|  | (PTB tick counter / symbol clock counter)          |  |
|  +----------------------------------------------------+  |
+----------------------------------------------------------+
```

### 14.2 Submodule Descriptions

#### edp_vb_pkt_gen
- Inputs: VB-ID[7:0], Mvid[7:0], Maud[7:0] (from DP link layer)
- Function: emits the 12-byte VB payload with four repetitions of each field
- Trigger: BS (Blanking Start) Komma detected at input

#### edp_data_pkt_gen_edm
- Inputs: DP data symbol stream, Komma symbols, lane count, HDCP enable
- Function: packs data bytes with Komma4-bit codes at head and tail; manages
  Dummy_sw suppression (EDM only); implements SDPsplit on SDP spanning packets
- Length counter counts bytes per lane between consecutive Komma events

#### edp_aux_pkt_gen
- Inputs: AUX transaction byte stream, HPD state [1:0]
- Function: packs HPD state and 5-bit length into header; forwards payload bytes
- One packet per AUX transaction

#### edp_stream_clk_gen
- Inputs: PTB clock counter, DP symbol clock edge
- Function: counts PTB ticks per N DP symbol clock periods; computes M_vid,ptb and
  N_vid,ptb; emits stream clock packet

#### edp_plm_8b10b_pkt_gen
- Inputs: 10-bit encoded DP symbols from 8b10b encoder output
- Function: packs 4 symbols per 5 bytes (1-lane); handles 2-lane and 4-lane
  interleaving; zero-pads final group if not divisible by 4 (1-lane) or 2 (2-lane)

#### edp_plm_128b132b_pkt_gen
- Inputs: 132-bit coded symbols from DP 128b/132b pre-coder output
- Function: packs 2 symbols per 33 bytes (1-lane); handles nibble boundary splits;
  pads with zeros if final symbol group is incomplete

#### edp_komma_enc / edp_komma_dec
- Encodes/decodes the 4-bit Komma code values per Table 7-63
- Handles SDPsplit (code 1101) and No Komma (code 0000) cases

#### edp_crc32
- Standard CRC32 per Section 4.2.9
- Covers bytes from ASEP packet byte 0 through byte before CRC32 field
- Shared between all eDP packet types

#### edp_pkt_type_mux (ASE)
- Arbitrates between VB, Data, AUX, Stream Clock, and PLM generators
- Output: serialized byte stream with prepended eDP header byte (type[7:5])

#### edp_pkt_type_demux (ASD)
- Reads eDP header type[7:5] field
- Routes received packet bytes to appropriate sub-parser

---

## 15. Register Map

SPEC FACT: Section 3.5.7 "ASEP (e)DP Specific" explicitly states "None" -- there are
no eDP-specific registers defined beyond the common ASEP register set
(Section 3.5.7, p83-84).

The eDP ASEP relies entirely on the common ASEP registers:

```
Register         Address       Description
--------         -------       -----------
fullPacketID     4/5.i.0001-3  48-bit packet sequence counter (DLL-managed)
streamType       4/5.i.0004    Read-only; value = 0x06 for eDP (Table 7-1)
streamVendorID   4/5.i.0005    Vendor-defined sub-identifier
ASEPtest         4/5.i.0006    Test mode enable (bit 0)
Pin Capability   4/5.i.0051-58 DP lane pin capability (if eDP pins on ASA device)
Pin Config       4/5.i.0059-62 DP lane pin configuration
ASEStatus        4.i.0101      ASE status / data starve event
ASDerrors        5.i.0100      Reassembly error counter (CRC32 fail, etc.)
```

IMPLEMENTATION ASSUMPTION: eDP lane signals (Main Link lanes 0-3, AUX+, AUX-, HPD)
are mapped to ASA device pins via the quad-pin or single-pin capability registers.
The spec does not define which pin group maps to DP lanes; this is implementation-defined.

---

## 16. Spec Facts vs Implementation Assumptions Summary

### 16.1 Confirmed Spec Facts

| ID    | Section | Fact |
|-------|---------|------|
| SF-01 | 7.9.2   | Main Link is unidirectional; AUX+HPD is bidirectional |
| SF-02 | 7.9.2   | AUX channel always completes one transaction per packet |
| SF-03 | 7.9.2.1 | EDM supports SST, DSC, HDCP stream sources |
| SF-04 | 7.9.2.1 | PLM is a fail-safe mode with full DP compatibility |
| SF-05 | 7.9.2.2 | Encapsulation point is at Link/PHY boundary, after HDCP, before scrambler |
| SF-06 | 7.9.2.3 | Komma symbols transmitted once per occurrence, not per lane |
| SF-07 | 7.9.2.3 | VB-ID, Mvid, Maud transmitted 4 times (one per DP lane occurrence) |
| SF-08 | 7.9.2.3 | Stuffed data between FS and FE may be dropped when HDCP is not active |
| SF-09 | 7.9.2.3 | ASA FEC replaces mandatory DP FEC for DSC streams |
| SF-10 | 7.9.3.1 | 3-bit type field in eDP common header identifies packet type (000-101) |
| SF-11 | 7.9.3.2.1 | BS Komma Symbol is NOT sent in VB packet; it is implied |
| SF-12 | 7.9.3.2.2 | Dummy_sw=1 must NOT be used when HDCP is enabled |
| SF-13 | 7.9.3.2.2 | Lane Count 0=1L, 1=2L, 2=4L; DP zero-padding for equal bytes per lane transmitted |
| SF-14 | 7.9.3.2.2 | SDPsplit Komma code (1101) marks SDP continuing in next packet |
| SF-15 | 7.9.3.2.3 | AUX Length field is 5 bits; zero length = HPD-only packet |
| SF-16 | 7.9.3.2.4 | 8b10b PLM: Length in 10-bit symbols; 1-lane groups of 4, 2-lane groups of 2 |
| SF-17 | 7.9.3.2.5 | 128b/132b PLM: Length in 132-bit symbols; 1-lane groups of 2 |
| SF-18 | 7.9.3.3.1 | f_StrmClk = M_vid,ptb / N_vid,ptb * f_PTB; 24-bit M and N values |
| SF-19 | 7.9.3.4   | Footer CRC32 applies to ALL eDP packet types; covers byte 0 to m_END-4 |
| SF-20 | 3.5.7     | No eDP-specific registers defined |
| SF-21 | 7.3/Table 7-1 | Stream type code 0x06 = (e)DP |

### 16.2 Implementation Assumptions

| ID    | Assumption |
|-------|------------|
| IA-01 | EDM and PLM modes are mutually exclusive per ASE instance; mode selection via OAM config |
| IA-02 | PTB timestamp mode for eDP packets (ingress vs. presentation) is implementation-defined |
| IA-03 | Stream clock packet transmission rate is implementation-defined; once per frame recommended |
| IA-04 | M_vid,ptb / N_vid,ptb ratio is computed by counting PTB ticks per N DP symbol clock periods |
| IA-05 | AUX channel uses separate ASE/ASD DLP port pair for bidirectionality |
| IA-06 | At a branch node, AUX transaction forwarding requires a full transaction buffer |
| IA-07 | eDP lane-to-ASA-pin mapping uses quad-pin or single-pin capability registers |
| IA-08 | 10-bit symbol packing in 8b10b PLM uses 40-bit shift register (4 symbols/5 bytes) |
| IA-09 | 132-bit symbol packing in 128b/132b PLM uses 136-bit shift register with nibble pointer |
| IA-10 | CRC32 error at ASD increments ASD error register 5.i.0100 per Section 3.7.1 |

---

## 17. Verification Plan

### 17.1 Directed Tests

| Test ID | Stimulus | Expected Behavior |
|---------|----------|-------------------|
| VT-01 | 1-lane EDM stream: BS Komma -> VB data -> active line | VB pkt emitted at BS; correct 12-byte payload with 4x VB-ID/Mvid/Maud |
| VT-02 | 2-lane EDM stream | Payload interleaved L0/L1 bytes; DP zero-padding present |
| VT-03 | 4-lane EDM stream | Payload interleaved L0/L1/L2/L3 bytes; Komma codes match Table 7-63 |
| VT-04 | EDM stream with HDCP | Dummy_sw=0 enforced; all data symbols encrypted; K-codes unencrypted |
| VT-05 | EDM stream with SDP spanning packet boundary | SDPsplit code (1101) in exit Komma slot; SDP reassembled at ASD |
| VT-06 | EDM stream no HDCP | Stuffed bytes between FS and FE dropped; data from consecutive TUs merged |
| VT-07 | AUX transaction (DPCD read request) | HPDstate=01 normal; Length=correct; payload matches AUX req bytes |
| VT-08 | AUX transaction with HPD only | Length=0; HPDstate changes captured |
| VT-09 | HPD interrupt (HPDstate=10) | Single AUX pkt with zero length; HPD state delivered to ASD |
| VT-10 | 8b10b PLM 1-lane | 4 symbols per 5-byte group; last group zero-padded if needed |
| VT-11 | 8b10b PLM 2-lane | 2-symbol groups per lane; correct interleaving |
| VT-12 | 8b10b PLM 4-lane | Correct 4-lane interleaving per Table 7-69 |
| VT-13 | 128b/132b PLM 1-lane | 132-bit symbols with nibble-boundary split; 33-byte pair blocks |
| VT-14 | 128b/132b PLM 2-lane | Correct L0/L1 interleaving per Table 7-72 |
| VT-15 | 128b/132b PLM 4-lane | Correct L0/L1/L2/L3 interleaving per Table 7-73 |
| VT-16 | Stream clock packet | M_vid,ptb and N_vid,ptb correctly computed; f_StrmClk within spec |
| VT-17 | CRC32 footer | CRC32 matches across all packet types; ASD detects single-bit corruption |
| VT-18 | Packet fragmentation | eDP packet > 1 DLL container; reassembly correct at ASD |
| VT-19 | Multiple ASEP packets in one container | follow flag=1; both packets correctly separated |
| VT-20 | DSC compressed stream | Compressed data packets with correct Komma delimiters |

### 17.2 Corner Cases

| Test ID | Corner Case |
|---------|-------------|
| CC-01 | Length field = 0 for AUX (HPD only) |
| CC-02 | Length field = 0x1F (maximum 31-byte AUX payload) |
| CC-03 | 8b10b PLM: payload length not divisible by 4 (1-lane) -- verify zero-pad |
| CC-04 | 128b/132b PLM: payload length = 1 symbol (half-byte boundary case) |
| CC-05 | VB pkt followed immediately by Data pkt in same container |
| CC-06 | Stream clock packet with M=0 (invalid; should not occur but verify graceful handling) |
| CC-07 | Dummy_sw=1 with HDCP enabled (forbidden; verify encoder disables or rejects) |
| CC-08 | Branch repeater: AUX request/response round trip latency |
| CC-09 | HDCP+DSC combined: verify HDCP cipher advances correctly past DP FEC control codes |

### 17.3 Protocol Compliance

- VB-ID/Mvid/Maud 4-occurrence rule must be verified against [asep_dp_01] Figure 2-12
- Komma code mapping (Table 7-63) must be verified against [asep_dp_01] control symbol list
- AUX transaction encapsulation must be verified against [asep_dp_01] section 2.11
- 8b10b PLM reference point (post-encoder) must be verified against [asep_dp_01] Figure 2-8
- 128b/132b PLM reference point (post-pre-coding) must be verified against [asep_dp_01] Figure 3-29

---

## 18. Missing / Needs Verification

### 18.1 Unresolved Spec Questions

| ID    | Question | Source of Uncertainty |
|-------|----------|-----------------------|
| MV-01 | Stream clock packet transmission rate / periodicity | Not specified in Section 7.9.3.3.1. Only "provides a similar reference for reconstructing the stream clock" stated. Analogy to I2S Section 7.10.1.1 suggests per-N-clock-cycle capture, but N is not defined for eDP. |
| MV-02 | Whether AUX bidirectionality uses two DLP ports or a single transceiver arrangement | Section 7.9.2 says "bidirectional always completing a transaction" but does not specify the port topology |
| MV-03 | Whether a branch node decodes and re-encodes ASEP eDP or tunnels it transparently | Figure 7-5 shows branch with full DP stack including HDCP Dec and HDCP Enc, implying full decode+re-encode. Not explicitly normative for ASA. |
| MV-04 | Explicit M_vid,ptb / N_vid,ptb measurement methodology | Section 7.9.3.3.1 gives only the formula f_StrmClk = M/N * f_PTB. No normative specification of how N is chosen or how many PTB ticks per measurement window. |
| MV-05 | EDM Dummy_sw=1 (lengths+Komma only) use case | The spec says it "shall not be used when HDCP is enabled" but does not state when it IS used. No test vector exists. |
| MV-06 | Whether the BS Komma implied by VB pkt must be regenerated exactly once or multiple times at the ASD | Section 7.9.3.2.1 says the BS Komma "is not sent in the packet" -- it is implied. The ASD must reconstruct it. Not specified if Enhanced Framing Mode equivalents have different regeneration rules. |
| MV-07 | DP features NOT encapsulated (requires external DP IP) | The following DP features are NOT encapsulated by eDP ASEP and require external DP IP blocks: (a) Physical layer: scrambler, 8b10b encoder, FEC encoder+interleaving, lane skew, TX driver (at DPTX); (b) Physical layer: descrambler, 8b10b decoder, FEC decoder, lane deskew, RX equalizer (at DPRX); (c) HDCP AES-128 cipher engine; (d) DSC encoder/decoder; (e) DP Link Training (LTPAT1/2/3, equalization) -- must be carried via AUX; (f) Link Policy Maker and Stream Policy Maker logic; (g) Hot Plug Detect physical signal -- only HPD state is encoded in AUX pkt |
| MV-08 | FEC handling for DSC streams | Section 7.9.2.3 states "ASA physical layer FEC provides at least the same integrity protection" and implies DP FEC is not needed. But whether DP FEC symbols are present or absent in the EDM data stream at the capture point (post-HDCP, pre-scrambler) is not explicitly confirmed. |
| MV-09 | 128b/132b mode: is Lane Count field absent by design? | Table 7-70 shows header with Reserved [4:0] and no Lane Count. Yet Tables 7-71/7-72/7-73 show 1-, 2-, and 4-lane payloads. The lane count must be known at decode time. This appears to be a spec gap -- lane count may be conveyed via OAM configuration or must be inferred from packet length. |
| MV-10 | Common ASEP PTB timestamp usage for eDP | Section 7.9 does not specify whether eDP packets should carry an ingress or presentation PTB timestamp in the common header. The PTB timestamp mode selection is not defined for eDP. |

### 18.2 DP Features Encapsulated vs External DP IP

```
Feature                     | ASA Encapsulated | External DP IP Required
----------------------------+------------------+------------------------
Main Link data symbols       | YES (EDM Data)   | No (bypassed in EDM)
VB-ID / Mvid / Maud          | YES (VB pkt)     | No
SDP (secondary data packets) | YES (EDM Data)   | No
AUX transactions             | YES (AUX pkt)    | No
HPD state                    | YES (AUX pkt)    | Only physical HPD pin
Komma symbols (EDM)          | YES (4-bit codes)| No
DP stream clock (video PLL)  | YES (Stream Clk) | DPRX NCO/PLL required
8b/10b encoded symbols       | YES (8b10b PLM)  | No (but needs 8b10b enc/dec)
128b/132b coded symbols      | YES (128b/132b)  | No (but needs pre-coder)
Scrambler/Descrambler        | NO               | Required at DP IP
8b/10b encoder (EDM mode)    | NO               | Required at DPTX
FEC encoder+interleaving     | NO               | Replaced by ASA FEC
Lane skew/deskew             | NO               | Required at DP IP
TX Driver / RX               | NO               | External PHY
HDCP AES cipher              | NO               | Required if HDCP used
DSC encoder/decoder          | NO               | Required if DSC used
DP Link Training             | INDIRECT (AUX)   | Link PM required
DP Link Policy Maker         | NO               | Not touched by ASA
DP Stream Policy Maker       | NO               | Not touched by ASA
```

---

*Spec source: ASA Technical Specification v2.0, Automotive SerDes Alliance Confidential,*
*Transceiver Specification version 2.0, 30 April 2024.*
*ASEP eDP covered in Section 7.9, pages 264-277.*
