# Micro-Architecture: MLE xMII Adaptation Layer

## 1. Purpose and Scope

The MLE xMII Adaptation Layer is the interface sublayer that bridges the IEEE 802.3
Media-Independent Interface (xMII) presented to the host Ethernet MAC and the ASA
MLE Physical Coding Sublayer (PCS). It performs clock-domain adaptation, data-rate
matching, 64b/65b block encoding/decoding, OAM frame fragmentation/reassembly, and
secondary control channel multiplexing -- all within a single physical layer block
pipeline that feeds or drains the MLE PCS.

This document defines the micro-architecture for RTL/golden-model implementation of
the MLE xMII Adaptation Layer for ASA Gen2020 MLE (Section 8).

Scope:
- IN SCOPE: TX Interface Adaptation (Section 8.6), RX Interface Adaptation (Section
  8.7), xMII signal mapping (MII/GMII/XGMII), rate matching block insertion and
  deletion, 64b/65b block encoding/decoding, OAM frame encoding/fragmentation and
  reassembly/integrity check, PTB timestamping for OAM, 4b/5b encoder/decoder, CRC8
  integrity engine, secondary control channel mux/demux, link aggregation sublayer
  (Section 8.8 -- inapplicable to MLE), interface to MLE PCS, interface to host MAC
- OUT OF SCOPE: MLE PCS internals (see micro-architecture-mle-pcs-datapath.md), PMA
  analog circuits, PTB clock service internals (see micro-architecture-ptb-clock-
  service.md), DLL mapper (see micro-architecture-dll-mapper-demux-core.md), OAM
  control plane (see micro-architecture-oam-control-plane.md)

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 8.1 | MLE Overview, Figure 8-1 | 284 | Layer stack position |
| 8.1.1 | MLE Features (Table 8-1) | 284-285 | Speed modes, xMII data rates |
| 8.1.2 | Organization of Section 8 | 285 | Section 4 reuse rules |
| 8.2.2.1 | PCS Transmit Process, Figure 8-2 | 285-287 | Adaptation layer in TX data flow |
| 8.2.2.4 | Physical Layer Block (Table 8-5) | 289 | tx_phy_blockE payload layout |
| 8.6 | Transmit Interface Adaptation Layer | 296 | Section overview |
| 8.6.1 | xMII (Table 8-11, Figures 8-4 to 8-8) | 296-299 | Signal mapping, interface examples |
| 8.6.1.1 | Rate Matching (Table 8-12) | 299 | Skip||R|| block insertion |
| 8.6.1.2 | 64b/65b Mapping (Table 8-13) | 299-300 | xMII_block format |
| 8.6.2 | OAM (Figure 8-9) | 300 | OAM frame structure in MLE |
| 8.6.2.1 | OAM Frame Encoding and Fragmentation | 300 | 4b/5b, SOP/EOP, CRC8 |
| 8.6.2.2 | PTB Time Stamping | 300 | JK character MDI timestamp |
| 8.6.2.3 | 4b/5b Encoder (Tables 8-14, 8-15) | 300-301 | Data and control character codes |
| 8.6.2.4 | CRC8 Definition | 301 | Polynomial 0xA6, init/XOR 0xFF |
| 8.6.3 | Secondary Control Channel | 301 | Optional, bit[1919] of tx_phy_blockE |
| 8.7 | Receive Interface Adaptation Layer | 302 | Section overview |
| 8.7.1.1 | RX Rate Matching | 302 | Skip||R|| block deletion |
| 8.7.2.1 | Synchronization to SOP and EOP | 302 | JJ/JK SOP detect, PTB MDI time |
| 8.7.2.2 | Reassembly and Integrity Check | 302-303 | CRC8 verify, discard on fail |
| 8.8 | Link Aggregation Sublayer | 302 | Does not apply to MLE |

Image references (docpdfmd/images/ -- from PDF pages 296-302):
- Figure 8-4 (PDF p297): MLE with XGMII and MII -- asymmetric mode example
- Figure 8-5 (PDF p297): MLE with XGMII and GMII -- MLES_10G_G example
- Figure 8-6 (PDF p298): MLE with GMII -- MLES_sym1G0 example
- Figure 8-7 (PDF p298): MLE with XGMII -- all modes supported
- Figure 8-8 (PDF p299): MLE with XGMII and XGMII/MII -- interop example

---

## 3. MLE Speed Modes and xMII Data Rates

SPEC FACT (Section 8.1.1, Table 8-1, PDF p284):

| Type | Short Name | DS Rate | US Rate | PMA Speed Grade |
|------|------------|---------|---------|-----------------|
| Symmetrical | MLES_sym1G0 | 1 Gbps | 1 Gbps | SG2 |
| Symmetrical | MLES_sym2G5 | 2.5 Gbps | 2.5 Gbps | SG3 |
| Symmetrical | MLES_sym5G0 | 5 Gbps | 5 Gbps | SG5 |
| Asymmetrical | MLES_2G5_M | 2.5 Gbps | 100 Mbps | SG2 |
| Asymmetrical | MLES_5G0_M | 5 Gbps | 100 Mbps | SG3 |
| Asymmetrical | MLES_10G_M | 10 Gbps | 100 Mbps | SG4 |
| Asymmetrical | MLES_10G_G | 10 Gbps | 1 Gbps | SG5 |

SPEC FACT (Section 8.1): "ASA Motion Link Ethernet defines a Physical Layer
compatible with IEEE 802.3 MAC, Reconciliation Sublayer and Media-Independent
Interface (xMII)."

SPEC FACT (Section 8.6.1): "MLE supports data rates, which fall into the speed range
of MII, GMII and XGMII."

---

## 4. Layer Stack Position

SPEC FACT (Section 8.1, Figure 8-1): The MLE xMII Adaptation Layer sits between the
IEEE 802.3 Reconciliation Sublayer (and xMII) and the MLE PCS. It is not present in
Gen2020 (Section 4) -- it is an MLE-specific sublayer.

```
+------------------------------+
|       802.3 MAC              |
+------------------------------+
|  Reconciliation Sublayer     |
+------------------------------+
|   xMII (MII / GMII / XGMII) |  <-- Host-side interface
+==============================+
|  TX Interface Adaptation     |  \
|  (Section 8.6)               |   |  MLE xMII Adaptation Layer
|  RX Interface Adaptation     |   |  (THIS DOCUMENT)
|  (Section 8.7)               |  /
+==============================+
|   MLE PCS                    |  <-- PCS-side interface (tx_phy_blockE)
|   (Section 8.2)              |
+------------------------------+
|   PMA (Section 8.3/4.3)      |
+------------------------------+
|   PMD / MDI                  |
+------------------------------+
```

SPEC FACT (Section 8.2.2.1, Figure 8-2): The TX data flow shows xMII data entering a
"Rate matching block insertion" stage, then a "4b/5b encoder / 64b/65b encoding"
stage. An OAM frame fragment path runs in parallel, also through 4b/5b encoding.
Both converge into the Physical_layer_block (RS-FEC framing + RS encoding) block that
feeds the PCS scrambler and resync header concatenation.

---

## 5. xMII Interface: Signal Definitions

### 5.1 Interface Variants

SPEC FACT (Section 8.6.1): MLE supports three xMII variants. The implementer selects
which variant(s) to use.

```
+---------------------------+-------+-------+---------+
| Interface                 | Width | Clock | Max Rate|
+---------------------------+-------+-------+---------+
| MII (Media Indep. IF)     | 4b    | 25MHz | 100Mbps |
| GMII (Gigabit MII)        | 8b    | 125MHz| 1 Gbps  |
| XGMII (10G MII)           | 32b   | 156MHz| 10 Gbps |
+---------------------------+-------+-------+---------+
```

IMPLEMENTATION ASSUMPTION: These are standard IEEE 802.3 clock and width
specifications. The spec confirms the interface names; exact clock frequencies are
standard IEEE 802.3 values not re-stated in Section 8.

### 5.2 TX Signal Set

IMPLEMENTATION ASSUMPTION: Standard IEEE 802.3 xMII TX signals presented to the
Adaptation Layer TX input port. Signal names follow IEEE 802.3 conventions; the spec
references xMII by name and requires compatibility but does not re-define pin-level
signals.

| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| TXCLK | In | 1 | TX clock from MAC (MII: 25MHz, GMII: 125MHz, XGMII: 156.25MHz) |
| TXD | In | 4/8/32 | TX data nibble/byte/quadbyte (MII/GMII/XGMII) |
| TXEN | In | 1 | TX enable: asserted during frame data (MII/GMII) |
| TXER | In | 1 | TX error: asserted to force error symbol |
| TXC | In | 4 | TX control per lane (XGMII; replaces TXEN/TXER per octet) |

### 5.3 RX Signal Set

IMPLEMENTATION ASSUMPTION: Standard IEEE 802.3 xMII RX signals presented from the
Adaptation Layer RX output port.

| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| RXCLK | Out | 1 | RX clock recovered (MII: 25MHz, GMII: 125MHz, XGMII: 156.25MHz) |
| RXD | Out | 4/8/32 | RX data nibble/byte/quadbyte (MII/GMII/XGMII) |
| RXDV | Out | 1 | RX data valid (MII/GMII) |
| RXER | Out | 1 | RX error: error symbol received |
| RXC | Out | 4 | RX control per lane (XGMII) |

### 5.4 xMII to XGMII Signal Mapping

SPEC FACT (Section 8.6.1, Table 8-11, PDF p296): MII and GMII signals are mapped to
XGMII TXD<31:0> and RXD<31:0> for the sole purpose of creating a valid 64-bit block
format used in ASA MLE. Non-data signals on GMII and MII are mapped to XGMII using
the respective XGMII octet control character.

```
TX Direction -- assembling XGMII TXD<31:0> from time-slots:

XGMII            GMII                       MII
TXD<31:0> <--  TXD_t3<7:0>, TXD_t2<7:0>  <-- TXD_t7<3:0>, TXD_t6<3:0>,
                                               TXD_t5<3:0>, TXD_t4<3:0>
               TXD_t1<7:0>, TXD_t0<7:0>  <-- TXD_t3<3:0>, TXD_t2<3:0>,
                                               TXD_t1<3:0>, TXD_t0<3:0>

RX Direction -- distributing XGMII RXD<31:0> to time-slots:

XGMII            GMII                       MII
RXD<31:0> -->  RXD_t3<7:0>, RXD_t2<7:0>  --> RXD_t7<3:0>, RXD_t6<3:0>,
                                               RXD_t5<3:0>, RXD_t4<3:0>
               RXD_t1<7:0>, RXD_t0<7:0>  --> RXD_t3<3:0>, RXD_t2<3:0>,
                                               RXD_t1<3:0>, RXD_t0<3:0>
```

SPEC FACT (Section 8.6.1, informative): "All MLE speed modes can be supported by
XGMII. It is up to the implementer to filter out (and inject) idle periods on the
XGMII to achieve the xMII payload data rate of the MLE speed mode." "Since all MLE
speed modes use the same PCS block code and mapping is implementation specific, all
combinations of xMII (which support the MLE speed mode target) can interoperate with
each other."

---

## 6. 64b/65b Block Encoding (TX)

### 6.1 xMII Block Format

SPEC FACT (Section 8.6.1): "The data received on XGMII, GMII or MII shall be grouped
for 64bit block format according to IEEE 802.3 Standard for Ethernet, Clause 49."

SPEC FACT (Section 8.6.1.2, Table 8-13, PDF p299-300): Each xMII_block[0:64] is 65
bits total (1 sync bit + 64 data/control bits).

```
xMII_block bit positions:

  [0]     [1:8]   [9:16]  [17:24]  [25:32]  [33:40]  [41:48]  [49:56]  [57:64]
+-------+-------+-------+--------+--------+--------+--------+--------+--------+
| Sync  |  D0   |  D1   |  D2    |  D3    |  D4    |  D5    |  D6    |  D7    |
|  bit  | [0:7] | [0:7] | [0:7]  | [0:7]  | [0:7]  | [0:7]  | [0:7]  | [0:7]  |
+-------+-------+-------+--------+--------+--------+--------+--------+--------+
 Data Block: Sync = 0, D0..D7 = eight data octets

  [0]     [1:8]        [9:64]
+-------+-----------+-------------------------------------------------+
| Sync  | Block Type |  See IEEE 802.3 Figure 49-7                    |
|  bit  |  [0:7]    |                                                 |
+-------+-----------+-------------------------------------------------+
 Control Block: Sync = 1, Block Type identifies control pattern
```

SPEC FACT (Section 8.6.1.2): The 65-bit xMII_block is placed into the MLE physical
layer block payload at tx_phy_blockE positions [211:1] to [8:0] per block slot k
(Table 8-5, Section 8.2.2.4).

### 6.2 Mapping into tx_phy_blockE

SPEC FACT (Section 8.2.2.4, Table 8-5, PDF p289): Each MLE physical layer block
tx_phy_blockE<1919:0> carries 26 xMII_blocks (k through k+25), along with an OAM
fragment field and optional secondary control channel. Layout (MSB first):

```
Bit [1919]      : Format indicator (1=secondary ctrl channel present, 0=absent)
Bit [1918]      : Reserved (set to 0)
Bits [1917:1908]: Secondary control channel <0:9>  (10 bits; zeros if not present)
Bits [1907:1898]: OAM_fragment<0:9>               (10 bits; two 4b/5b characters)
Bits [1897:1833]: xMII_block_k <0:64>             (65 bits, block k)
Bits [1832:1768]: xMII_block_k+1 <0:64>           (65 bits)
  ...                                               (24 more xMII_blocks)
Bits [272:208]  : xMII_block_k+25 <0:64>          (65 bits, last block)
Bits [207:0]    : RS-FEC parity (26 bytes = 208 bits)
```

PDF-VERIFIED NOTE: The usable xMII payload field is bits[1897:208] = 1690 bits, which
supports exactly 26 xMII_blocks x 65 bits. Earlier local notes that referred to 65
xMII_blocks per tx_phy_blockE were incorrect and conflicted with Figure 8-3/Table 8-5.

---

## 7. TX Interface Adaptation: Data Flow

### 7.1 Top-Level TX Flow

SPEC FACT (Section 8.2.2.1, Figure 8-2): The TX data flow for MLE is:

```
                xMII (from 802.3 MAC / Reconciliation Sublayer)
                     |
                     v
        +-----------------------------+
        | xMII Clock Domain           |
        | (MII/GMII/XGMII input)     |
        +-----------------------------+
                     |
              [Clock Domain Crossing]
                     |
                     v
        +-----------------------------+    +---------------------+
        | Rate Matching               |    | OAM Frame Source    |
        | (Section 8.6.1.1)          |    | (Section 5.5 frame) |
        | Insert Skip||R|| when idle  |    +----------+----------+
        +-------------+---------------+               |
                      |                               v
                      |                   +-----------+-----------+
                      v                   | 4b/5b Encoder         |
        +-----------------------------+   | (Section 8.6.2.3)     |
        | 64b/65b Encoder             |   | SOP(JJ,JK), Data,     |
        | (Section 8.6.1.2)          |   | CRC8, EOP(TI), IDLE   |
        | Group xMII data into        |   +-----------+-----------+
        | xMII_block[0:64] per IEEE   |               |
        | 802.3 Clause 49             |      OAM_fragment<0:9>
        +-------------+---------------+               |
                      |                               |
                      | xMII_block<0:64>              |
                      |  (65 bits per block)          |
                      v                               v
        +---------------------------------------------------+
        | xMII block stream + OAM/2nd ctrl generation       |
        | 26 xMII_blocks + OAM_fragment + 2nd_ctrl sideband |
        +---------------------------------------------------+
                      |
                      | to MLE PCS payload assembler
                      v
              To MLE PCS (PLB assembly, RS-FEC encoder, scrambler, resync header)
```

### 7.2 TX Rate Matching (Section 8.6.1.1)

SPEC FACT (Section 8.6.1.1, PDF p299): "When no data is available from the xMII, the
Adaptation Layer shall generate data for Rate Matching. The Rate Matching shall insert
control blocks of Block Type 0x1e with all control codes set to 'Skip||R||' 0x1C.
These rate matching control blocks may be inserted between or during ETH packet
transmission, and will be removed by the receiver."

SPEC FACT (Section 8.6.1.1, Table 8-12, PDF p299): Average Skip||R|| insertion rate
per mode (guidance values for nominal xMII and ASA line rates):

```
+----------+-------------+---------------------------------+-------------------------+
|          |             |  Every Physical Layer Blocks    |  Insert "Skip||R||"     |
|  Type    | Short Name  |  Downstream  |  Upstream        |  Downstream | Upstream  |
+----------+-------------+--------------+-----------------+-------------+-----------+
|          | MLES_sym1G0 |    208       |    208           |     51      |    51     |
|Symmetrical|MLES_sym2G5 |    832       |    832           |     47      |    47     |
|          | MLES_sym5G0 |    364       |    364           |      9      |     9     |
+----------+-------------+--------------+-----------------+-------------+-----------+
|          | MLES_2G5_M  |     96       |     80           |      1      |    61     |
|Asymmetrical|MLES_5G0_M |    936       |   1040           |      1      |   853     |
|          | MLES_10G_M  |   1944       |    480           |      9      |    93     |
|          | MLES_10G_G  |    936       |    208           |      1      |    21     |
+----------+-------------+--------------+-----------------+-------------+-----------+
```

Notes:
- A Skip||R|| block is a complete xMII_block with Block Type 0x1e and all control
  codes 0x1C (IEEE 802.3 IDLE/Skip ordered set).
- These are guidance averages; actual insertion is elastic (driven by FIFO fill level).
- On the upstream path for asymmetrical modes, the 100 Mbps xMII generates very few
  xMII_blocks relative to line rate, hence the high Skip||R|| insertion ratio.

IMPLEMENTATION ASSUMPTION: A shallow elastic FIFO (clock-domain crossing buffer)
between the xMII clock domain and the PCS block assembly clock domain controls the
insertion rate. When the FIFO is above a high-water mark, Skip||R|| insertion is
suppressed; when at or below the high-water mark, a Skip||R|| block is substituted
for one xMII_block slot per the guidance table cadence.

### 7.3 64b/65b TX Encoding

SPEC FACT (Section 8.6.1.2): xMII data from XGMII/GMII/MII is grouped into 65-bit
xMII_block[0:64] blocks per IEEE 802.3 Clause 49. The sync bit at position [0]
distinguishes data blocks (Sync=0) from control blocks (Sync=1).

IMPLEMENTATION ASSUMPTION: The 64b/65b encoder is standard IEEE 802.3 Clause 49
logic. In a TX pipeline:
1. XGMII TXD<31:0> and TXC<3:0> arrive every two XGMII clock cycles (64 bits total).
2. The encoder checks for Start (SFD), Terminate (EOF), Error, and Idle/Control
   ordered sets.
3. One 65-bit xMII_block is produced per 64 bits of XGMII input.
4. For GMII (8-bit) inputs: 8 time-slots are accumulated to form one 64-bit XGMII
   equivalent before encoding.
5. For MII (4-bit) inputs: 16 time-slots are accumulated.

---

## 8. OAM Frame Encoding and Fragmentation (TX)

### 8.1 OAM Frame Structure

SPEC FACT (Section 8.6.2, Figure 8-9, PDF p300): MLE uses the OAM frame of Section
5.5 with the addition of one byte for integrity checksum (CRC8). The coded frame has
the following structure:

```
Coded OAM Frame in MLE physical layer stream:

+------+-----+--------+-------+-------+-----+-----+------+
| IDLE | SOP | OAM    | CAD   |  ...  | CAD | CRC | EOP  | IDLE ...
|  II  | JJ  | header | #1    |       | #n  |8    | TI   |  II
|      | JK  |        |       |       |     |     |      |
+------+-----+--------+-------+-------+-----+-----+------+

Each cell above occupies one or more physical layer block OAM_fragment<0:9> slots.
SOP spans two physical layer blocks (JJ in block N, JK in block N+1).
```

SPEC FACT (Section 8.6.2.1): "Each physical layer block takes 10 bits of encoded
fragmented OAM data, or two 4b/5b characters."

SPEC FACT (Section 8.6.2.1): Framing sequence:
1. One group of control characters JJ (Start #1 + Start #1) transmitted to mark
   pre-SOP in one physical layer block OAM_fragment slot.
2. In the next physical layer block: one group of control characters JK (Start #1 +
   Start #2) transmitted to mark SOP.
3. Each byte of OAM frame data is 4b/5b encoded (two 5-bit symbols per block slot).
4. Each OAM frame byte is fed (ascending order) into the CRC8 calculator.
5. The 8-bit CRC8 result is also 4b/5b encoded and appended after the last OAM byte.
6. CRC8 resets for every OAM frame.
7. After the last byte: one group of TI (Terminate + Idle) marks EOP.
8. Outside SOP/data/EOP: group of II (Idle + Idle) marks IDLE.

### 8.2 4b/5b Encoding

SPEC FACT (Section 8.6.2.3, Table 8-14, PDF p300-301): Data encoding map (4 data
bits to 5 code bits):

```
Data[3:0] -> Code[4:0]    Data[3:0] -> Code[4:0]
0000       -> 11110        1000       -> 10010
0001       -> 01001        1001       -> 10011
0010       -> 10100        1010       -> 10110
0011       -> 10101        1011       -> 10111
0100       -> 01010        1100       -> 11010
0101       -> 01011        1101       -> 11011
0110       -> 01110        1110       -> 11100
0111       -> 01111        1111       -> 11101
```

SPEC FACT (Section 8.6.2.3, Table 8-15, PDF p301): Control character symbols:

```
Symbol | Code[4:0] | Description
H      | 00100     | Halt
I      | 11111     | Idle
J      | 11000     | Start #1
K      | 10001     | Start #2
L      | 00110     | Start #3
Q      | 00000     | Quiet
R      | 00111     | Reset
S      | 11001     | Set
T      | 01101     | Terminate (End)
```

### 8.3 CRC8 Definition

SPEC FACT (Section 8.6.2.4, PDF p301): OAM integrity checksum parameters:
- Polynomial: 0xA6 (binary: 1010 0110, i.e., x^7 + x^5 + x^2 + x^1)
- Initial value: 0xFF
- XOR appendix (final XOR): 0xFF
- Input reflection: byte-wise reflected (LSB first per byte)
- Output reflection: result bits reflected before final XOR

IMPLEMENTATION ASSUMPTION: The CRC8 engine processes one OAM byte per clock cycle.
It resets to 0xFF at the start of each OAM frame (JK boundary) and the checksum is
appended as the last byte before EOP. The polynomial 0xA6 is also known as CRC-8/MAXIM
or CRC-8/ROHC depending on reflection conventions; verify exact bit ordering against
Section 8.6.2.4 test vectors (none provided in spec -- a test vector must be
generated during verification).

### 8.4 PTB TX Timestamping

SPEC FACT (Section 8.6.2.2, PDF p300): "The PTB time stamp in the header of the OAM
frame is taken when the group of two control characters JK of the SOP passes the
transmitting MDI."

IMPLEMENTATION ASSUMPTION: The OAM frame header is pre-populated with a placeholder
PTB timestamp. When the JK character pair exits the TX MDI (physical transmission
point), the PTB clock service latches the current PTB value. This latched value
is written back into the OAM frame header before the frame is transmitted (or the
frame is held in a buffer until the stamp is available). The exact mechanism (pre-
latch vs. post-latch correction) depends on pipeline depth and is an implementation
choice.

---

## 9. Secondary Control Channel (TX)

SPEC FACT (Section 8.6.3, PDF p301): "The secondary control channel is optional. Its
presence is being indicated by the first bit of the physical layer block, see Table
8-5."

SPEC FACT (Section 8.2.2.4, Table 8-5): Bit [1919] of tx_phy_blockE is the format
indicator:
- 1: secondary control channel present; bits [1917:1908] = secondary ctrl channel
  <0:9> (10 bits)
- 0: no secondary control channel present; bits [1917:1908] set to 0

IMPLEMENTATION ASSUMPTION: The secondary control channel carries 10 bits per physical
layer block. At the MLE line rates this provides a low-rate side-channel (e.g.,
at MLES_sym1G0 with 208 physical layer blocks per TDD burst, the secondary channel
rate = 10 bits/block * blocks_per_second). The spec does not define the protocol
content of the secondary control channel payload -- this is reserved for future use
or implementation-specific protocols.

---

## 10. RX Interface Adaptation: Data Flow

### 10.1 Top-Level RX Flow

SPEC FACT (Section 8.7): The RX Interface Adaptation Layer inverts the TX process.

```
              From MLE PCS (RS-FEC decoded, descrambled)
                     |
                     | tx_phy_blockE<1919:0>  (received and decoded)
                     v
        +---------------------------------------------------+
        | tx_phy_blockE Decomposition (Section 8.2.2.4)     |
        | Extract: bit[1919] (2nd ctrl indicator)           |
        |          bits[1917:1908] (2nd ctrl channel)       |
        |          bits[1907:1898] (OAM_fragment<0:9>)      |
        |          bits[1897:208]  (65x xMII_block<0:64>)  |
        +-------+---------------------------+---------------+
                |                           |
                | xMII_block<0:64>          | OAM_fragment<0:9>
                v                           v
    +---------------------------+  +------------------------+
    | RX Rate Matching          |  | OAM Reassembly         |
    | (Section 8.7.1.1)        |  | (Sections 8.7.2.1/2.2) |
    | Delete Skip||R|| blocks   |  | Scan for SOP (JJ/JK)   |
    | (Block Type 0x1e,         |  | 4b/5b decode           |
    |  codes all 0x1C)          |  | CRC8 verify            |
    +-------------+-------------+  | Discard on CRC fail    |
                  |                +------------+-----------+
                  | valid xMII_blocks           |
                  v                             | reassembled OAM frame
    +---------------------------+               v
    | 64b/65b Decoder           |     To OAM Control Plane
    | (IEEE 802.3 Clause 49)    |
    | Sync bit demux            |
    | Control block decode      |
    +-------------+-------------+
                  |
              [Clock Domain Crossing]
                  |
                  v
        +-----------------------------+
        | xMII Clock Domain           |
        | RXCLK, RXD, RXDV, RXER     |
        +-----------------------------+
                  |
                  v
        Reconciliation Sublayer / 802.3 MAC
```

### 10.2 RX Rate Matching (Section 8.7.1.1)

SPEC FACT (Section 8.7.1.1, PDF p302): "The receiver shall delete all control blocks
of Block Type 0x1e with all control codes set to 'Skip||R||' 0x1C."

IMPLEMENTATION ASSUMPTION: The rate matching deletion logic inspects each received
xMII_block. If the sync bit is 1 (control block) and Block Type field equals 0x1e
and all 7 control codes in positions [9:64] are 0x1C, the block is discarded and
not passed to the 64b/65b decoder or xMII output FIFO. All other control blocks
and all data blocks pass through unmodified.

### 10.3 RX SOP/EOP Synchronization (Section 8.7.2.1)

SPEC FACT (Section 8.7.2.1, PDF p302): "The receiver shall scan for SOP character to
detect the start of a frame."

SPEC FACT (Section 8.7.2.1): "The receiver marks the time when the group of two
control characters JK of the SOP passed the receiving MDI. If the OAM message will
be used to initialize the PTB, the delta between the received time and the time the
message was processed will be added to the timestamp prior to initializing the PTB."

IMPLEMENTATION ASSUMPTION: The OAM fragment stream (10 bits per block, two 4b/5b
chars) is scanned continuously. The detector state machine:

```
States:
  IDLE_SCAN  --> waiting, see only II pairs
  JJ_SEEN    --> one group of JJ received; pre-SOP detected
  SOP_LOCK   --> JK received in next block after JJ; PTB MDI time captured
  DATA_RX    --> accumulating 4b/5b characters, decoding OAM bytes
  EOP_SEEN   --> TI group received; end of OAM frame

Transitions:
  IDLE_SCAN  --[OAM_frag = JJ pair]--> JJ_SEEN
  JJ_SEEN    --[next OAM_frag = JK pair]--> SOP_LOCK (capture PTB_mdi_rx)
  JJ_SEEN    --[other]--> IDLE_SCAN
  SOP_LOCK   --[data chars]--> DATA_RX
  DATA_RX    --[TI pair]--> EOP_SEEN
  EOP_SEEN   --[CRC pass]--> deliver OAM frame to OAM control plane
  EOP_SEEN   --[CRC fail]--> discard frame, increment error counter
  EOP_SEEN   --[II pair]--> IDLE_SCAN
```

### 10.4 OAM Reassembly and Integrity Check (Section 8.7.2.2)

SPEC FACT (Section 8.7.2.2, PDF p302-303): "The 4b/5b decoded OAM frame bytes shall
be checked versus the received integrity checksum and mismatching OAM frames shall be
discarded. The number of OAM frames failing integrity checksum will be counted in
3.3.24."

IMPLEMENTATION ASSUMPTION: The reassembly logic:
1. 4b/5b decodes each pair of 5-bit characters into one byte.
2. Feeds each byte (in ascending order) into a running CRC8 calculator using the same
   polynomial and parameters as TX (Section 8.6.2.4).
3. At EOP, compares the final two 4b/5b characters (the received CRC8 byte) against
   the locally computed CRC8.
4. On mismatch: discards the entire OAM frame and increments register 3.3.24.
5. On match: forwards the reassembled OAM frame to the OAM control plane entity.

Register 3.3.24 (SPEC FACT -- referenced from Section 8.7.2.2): OAM integrity
checksum failure counter. Exact register definition at address 3.3.24 should be
confirmed from Section 3.3 of the register model.

---

## 11. Clock Domain Considerations

### 11.1 Clock Domain Boundaries

IMPLEMENTATION ASSUMPTION: The MLE xMII Adaptation Layer spans two primary clock
domains:

```
+-------------------------------+   +----------------------------------+
| xMII Clock Domain             |   | PCS/Line Clock Domain            |
|                               |   |                                  |
| Clock source: TXCLK (TX)      |   | Clock source: PMA recovered clk  |
|               RXCLK (RX)      |   | or local PLL locked to PMA rate  |
|                               |   |                                  |
| MII:  25 MHz (4-bit)          |   | PCS block assembly clock:        |
| GMII: 125 MHz (8-bit)         |   | Rate-dependent; must produce     |
| XGMII: 156.25 MHz (32-bit)   |   | tx_phy_blockE at the correct     |
|                               |   | cadence for the MLE speed mode   |
| TX: xMII data in -> elastic   |   |                                  |
|     FIFO -> PCS side          |   | tx_phy_blockE<1919:0> assembled  |
| RX: PCS side -> elastic FIFO  |   | from 26 xMII_blocks per block    |
|     -> RXCLK domain out       |   |                                  |
+-------------------------------+   +----------------------------------+
            ^                                      ^
            |                                      |
     [Async FIFO CDC]                       [Async FIFO CDC]
```

### 11.2 TX Elastic FIFO Sizing

IMPLEMENTATION ASSUMPTION: The TX elastic FIFO must accommodate:
- xMII data burstiness (minimum 2x maximum ETH frame worth of xMII_blocks)
- Rate-matching headroom: the FIFO fill level drives Skip||R|| insertion/suppression
- Clock ppm tolerance: up to +/-100 ppm between xMII MAC clock and PCS line clock

For MLES_sym1G0 (1:1 rate, GMII at 125 MHz): FIFO depth of 16-64 xMII_blocks is
typical for ppm tolerance with <1 us latency penalty.

### 11.3 RXCLK Generation

IMPLEMENTATION ASSUMPTION: The RXCLK output to the host MAC is derived from the PMA
recovered clock (or a PLL tracking it), divided/multiplied to the appropriate xMII
rate. For asymmetric modes (e.g., MLES_10G_M, US=100 Mbps), the MII RXCLK is
generated at 25 MHz from the PMA clock chain.

---

## 12. Interface to MLE PCS

PDF-ALIGNED IMPLEMENTATION NOTE: Figure 8-2 places physical layer block assembly inside
the PCS transmit process. In this repo, the interface between the Adaptation Layer and
the MLE PCS is therefore the xMII block stream plus OAM/secondary-control sidebands,
not a preassembled tx_phy_blockE vector.

| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| xmii_blocks_tx[1689:0] | AL->PCS | 1690 | 26 xMII_blocks, 65 bits each |
| xmii_blocks_tx_valid | AL->PCS | 1 | 26-block payload group ready |
| xmii_blocks_rx[1689:0] | PCS->AL | 1690 | 26 xMII_blocks extracted from RX PLB |
| xmii_blocks_rx_valid | PCS->AL | 1 | Received block group valid |
| xmii_blocks_rx_err | PCS->AL | 1 | Uncorrectable FEC error on this group |
| ptb_mdi_tx_oam | AL->PTB | 1 | Pulse: JK character passed TX MDI |
| ptb_mdi_rx_oam | AL->PTB | 1 | Pulse: JK character passed RX MDI |
| ptb_clk_tx[47:0] | PTB->AL | 48 | PTB snapshot at TX MDI JK event |
| ptb_clk_rx[47:0] | PTB->AL | 48 | PTB snapshot at RX MDI JK event |
| sec_ctrl_tx[9:0] | Ctrl->AL | 10 | Secondary ctrl channel TX payload |
| sec_ctrl_rx[9:0] | AL->Ctrl | 10 | Secondary ctrl channel RX payload |
| sec_ctrl_present_tx | Ctrl->AL | 1 | Insert secondary ctrl channel |
| sec_ctrl_present_rx | AL->Ctrl | 1 | Secondary ctrl channel detected in RX |
| mle_mode[2:0] | Config->AL | 3 | Active MLE speed mode (from MLEconfig) |
| oam_frame_tx[*] | OAM->AL | bus | OAM frame bytes for TX fragmentation |
| oam_frame_tx_valid | OAM->AL | 1 | OAM frame ready for encoding |
| oam_frame_rx[*] | AL->OAM | bus | Reassembled OAM frame bytes |
| oam_frame_rx_valid | AL->OAM | 1 | OAM frame CRC check passed |

IMPLEMENTATION ASSUMPTION: Signal names are derived from the architectural function.
Exact RTL port names and bus widths to be finalized during RTL design.

---

## 13. Interface to Host (802.3 MAC)

SPEC FACT (Section 8.1): The external interface is the standard IEEE 802.3 xMII.

```
                  802.3 MAC
         +---------------------------+
         |  TX:                      |   RX:
TXCLK -->|                           |<-- RXCLK
TXD  -->|   Reconciliation          |<-- RXD
TXEN -->|   Sublayer                |<-- RXDV
TXER -->|                           |<-- RXER
TXC  -->|   (XGMII only)            |<-- RXC
         +---------------------------+
                     |
              (xMII bus)
                     |
         +---------------------------+
         |  MLE xMII Adaptation      |
         |  Layer (THIS DOCUMENT)    |
         +---------------------------+
```

IMPLEMENTATION ASSUMPTION: The Adaptation Layer acts as a PHY from the MAC's
perspective. On TX, it accepts TXCLK, TXD, TXEN/TXER (or TXC for XGMII) and
presents the xMII_block stream to the PCS. On RX, it generates RXCLK, RXD, RXDV/
RXER (or RXC) from the received xMII_block stream.

---

## 14. Link Aggregation Sublayer (Section 8.8)

SPEC FACT (Section 8.8, PDF p302): "Does not apply to MLE."

Section 4.8 defines a Link Aggregation Sublayer for Gen2020 (optional multi-link
bonding). The MLE specification explicitly excludes this -- MLE uses a single ASA
physical link with xMII adaptation at the host side. There is no MLE link bonding
at the adaptation layer level.

IMPLEMENTATION ASSUMPTION: No link aggregation RTL block is required in the MLE
xMII Adaptation Layer. If a system-level Ethernet link aggregation (LACP) is desired
above the 802.3 MAC, that is entirely above the scope of this PHY layer.

---

## 15. Suggested RTL Module Boundaries

```
+===========================================================================+
|                     mle_xmii_adaptation_top                               |
|                                                                            |
|  TX PATH                                                                   |
|  +----------------------+    +------------------------+                   |
|  | xmii_tx_cdc          |    | rate_match_tx          |                   |
|  |                      |    |                        |                   |
|  | Async FIFO for clock |    | Monitor FIFO fill      |                   |
|  | domain crossing      |    | Insert Skip||R||       |                   |
|  | TXCLK -> PCS clk     |    | (BT=0x1e, codes=0x1C)  |                   |
|  | Elastic buffer       |    | Per Table 8-12 cadence |                   |
|  +----------+-----------+    +----------+-------------+                   |
|             |                           |                                 |
|             v                           v                                 |
|  +----------------------+    +------------------------+                   |
|  | encoder_64b65b_tx    |    | oam_fragmentation_tx   |                   |
|  |                      |    |                        |                   |
|  | xMII -> xMII_block   |    | Section 5.5 OAM frame  |                   |
|  | IEEE 802.3 Cl.49     |    | 4b/5b encode           |                   |
|  | Sync bit insert      |    | JJ/JK SOP, TI EOP      |                   |
|  | BT & ctrl fields     |    | CRC8 append            |                   |
|  +----------+-----------+    | PTB JK MDI capture     |                   |
|             |                +----------+-------------+                   |
|             | xMII_block[64:0]          | OAM_frag[9:0]                   |
|             v                           v                                 |
|  +------------------------------------------------------+                 |
|  | phy_block_assembler                                   |                 |
|  |                                                       |                 |
|  | Pack 26 xMII_blocks + OAM_frag + 2nd_ctrl            |                 |
|  | Set bit[1919] format indicator                        |                 |
|  | Output tx_phy_blockE<1919:0> to MLE PCS               |                 |
|  +------------------------------------------------------+                 |
|                                                                            |
|  +---------------------+    +---------------------------+                 |
|  | sec_ctrl_mux_tx     |    | crc8_engine               |                 |
|  |                     |    |                           |                 |
|  | Pack 10-bit payload |    | Poly 0xA6, init 0xFF      |                 |
|  | into bits[1917:1908]|    | XOR 0xFF, byte-reflect    |                 |
|  | Set bit[1919]=1     |    | Shared TX/RX              |                 |
|  +---------------------+    +---------------------------+                 |
|                                                                            |
|  RX PATH                                                                   |
|  +------------------------------------------------------+                 |
|  | phy_block_decomposer                                  |                 |
|  |                                                       |                 |
|  | Extract bit[1919], bits[1917:1908] (2nd ctrl)         |                 |
|  | Extract bits[1907:1898] (OAM_frag)                    |                 |
|  | Extract bits[1897:208] (65x xMII_block)               |                 |
|  +--+-----------------------------+-----------------------+                |
|     |                             |                                        |
|     | xMII_block[] stream         | OAM_frag[9:0] per block               |
|     v                             v                                        |
|  +----------------------+    +------------------------+                   |
|  | rate_match_rx        |    | oam_reassembly_rx      |                   |
|  |                      |    |                        |                   |
|  | Detect & delete      |    | SOP state machine      |                   |
|  | BT=0x1e, code=0x1C   |    | 4b/5b decode           |                   |
|  | blocks               |    | CRC8 verify            |                   |
|  +----------+-----------+    | Discard on CRC fail    |                   |
|             |                | Count errors (3.3.24)  |                   |
|             |                | PTB JK MDI capture     |                   |
|             v                +----------+-------------+                   |
|  +----------------------+               |                                 |
|  | decoder_64b65b_rx    |               v                                 |
|  |                      |    To OAM Control Plane                         |
|  | xMII_block ->        |                                                 |
|  | XGMII format         |                                                 |
|  | Sync bit decode      |                                                 |
|  | Ctrl block decode    |                                                 |
|  +----------+-----------+                                                 |
|             |                                                             |
|             v                                                             |
|  +----------------------+    +------------------------+                   |
|  | xmii_rx_cdc          |    | sec_ctrl_demux_rx      |                   |
|  |                      |    |                        |                   |
|  | Async FIFO for clock |    | Extract bit[1919]      |                   |
|  | domain crossing      |    | Output bits[1917:1908] |                   |
|  | PCS clk -> RXCLK     |    | to 2nd ctrl consumer   |                   |
|  | Generate RXCLK       |    +------------------------+                   |
|  +----------+-----------+                                                 |
|             |                                                             |
|  RXCLK, RXD, RXDV, RXER -> to 802.3 Reconciliation Sublayer              |
+===========================================================================+
```

---

## 16. Spec Facts vs Implementation Assumptions

### 16.1 Normative Spec Facts

| # | Fact | Section |
|---|------|---------|
| 1 | MLE supports MII, GMII, XGMII | 8.6.1 |
| 2 | xMII data grouped per IEEE 802.3 Clause 49 64-bit block format | 8.6.1 |
| 3 | GMII/MII signals mapped to XGMII TXD<31:0>/RXD<31:0> per Table 8-11 | 8.6.1 |
| 4 | Non-data GMII/MII signals mapped to XGMII octet control characters | 8.6.1 |
| 5 | TX rate matching: insert BT=0x1e, all codes=0x1C when no xMII data | 8.6.1.1 |
| 6 | Skip||R|| insertion cadence per Table 8-12 (guidance, not normative) | 8.6.1.1 |
| 7 | Skip||R|| may be inserted between or during ETH packet transmission | 8.6.1.1 |
| 8 | xMII_block[0:64] = 1 sync bit + 64 data/control bits (Table 8-13) | 8.6.1.2 |
| 9 | Data block: Sync=0; Control block: Sync=1, BT in [1:8] | 8.6.1.2 |
| 10 | MLE OAM frame = Section 5.5 OAM frame + 1 byte CRC8 | 8.6.2 |
| 11 | Each physical layer block carries 10 bits OAM (two 4b/5b chars) | 8.6.2.1 |
| 12 | SOP signalled by JJ group then JK group in consecutive blocks | 8.6.2.1 |
| 13 | Each OAM byte is 4b/5b encoded | 8.6.2.1 |
| 14 | CRC8 computed over all OAM frame bytes in ascending order | 8.6.2.1 |
| 15 | CRC8 result is 4b/5b encoded and appended after last OAM byte | 8.6.2.1 |
| 16 | CRC8 resets for every OAM frame | 8.6.2.1 |
| 17 | EOP signalled by TI group | 8.6.2.1 |
| 18 | IDLE outside SOP/data/EOP signalled by II group | 8.6.2.1 |
| 19 | PTB TX timestamp captured when JK of SOP passes TX MDI | 8.6.2.2 |
| 20 | CRC8 polynomial: 0xA6; init: 0xFF; XOR: 0xFF; input and output reflected | 8.6.2.4 |
| 21 | Secondary control channel is OPTIONAL | 8.6.3 |
| 22 | Secondary ctrl channel presence indicated by bit[1919] of tx_phy_blockE | 8.6.3, 8.2.2.4 |
| 23 | Secondary ctrl channel occupies bits[1917:1908] of tx_phy_blockE | 8.2.2.4 (Table 8-5) |
| 24 | RX rate matching: delete all BT=0x1e blocks with all codes=0x1C | 8.7.1.1 |
| 25 | RX: scan for SOP (JJ then JK) to detect start of OAM frame | 8.7.2.1 |
| 26 | PTB RX timestamp captured when JK of SOP passes RX MDI | 8.7.2.1 |
| 27 | PTB delta (RX MDI time minus process time) added to PTB before init | 8.7.2.1 |
| 28 | OAM frame bytes checked against received CRC8; mismatch -> discard | 8.7.2.2 |
| 29 | OAM CRC8 failure count stored in register 3.3.24 | 8.7.2.2 |
| 30 | Link Aggregation Sublayer does not apply to MLE | 8.8 |

### 16.2 Implementation Assumptions (not normative)

| # | Assumption |
|---|------------|
| 1 | Elastic FIFOs (async) used for clock domain crossing at TX and RX |
| 2 | FIFO fill level drives Skip||R|| insertion suppression/assertion |
| 3 | TX clock frequencies follow IEEE 802.3: MII=25MHz, GMII=125MHz, XGMII=156.25MHz |
| 4 | RXCLK is derived from PMA recovered clock divided to xMII rate |
| 5 | 64b/65b encoder/decoder is IEEE 802.3 Clause 49 standard logic |
| 6 | CRC8 engine is shared between TX encode and RX verify paths |
| 7 | OAM frame is held in a buffer until CRC8 is computed before fragmentation |
| 8 | PTB TX timestamp is latched at JK MDI event; late-write into OAM header |
| 9 | Secondary control channel protocol content is implementation-specific |
| 10 | Physical layer block assembly pipeline operates at PCS clock domain |
| 11 | 26 xMII_blocks per tx_phy_blockE payload field is fixed for all MLE modes |
| 12 | Register 3.3.24 is an SC (self-clearing on read) counter |
| 13 | xMII signal set follows standard IEEE 802.3 MII/GMII/XGMII pin conventions |

---

## 17. Relationship to MLE PCS Datapath

The MLE xMII Adaptation Layer is the producer (TX) and consumer (RX) of the
MLE PCS payload-side interface. The boundary is clean:

- TX: Adaptation Layer delivers 26 xMII_blocks plus OAM/secondary-control sidebands to
  MLE PCS. PCS performs PLB assembly, RS-FEC encoding (Section 8.2.4), scrambling
  (Section 8.2.2.5), resync header concatenation (Section 8.2.2.3), and PAM2/4
  mapping (Sections 8.2.2.6-7).
- RX: MLE PCS delivers extracted xMII blocks plus OAM/secondary-control sidebands to
  the Adaptation Layer after RS-FEC check and PLB disassembly.

SPEC FACT (Section 8.2.2.4): The physical layer block is transmitted MSB first:
tx_phy_blockE<1919> is the first bit transmitted into the PCS pipeline.

SPEC FACT (Section 8.2.2.1, Figure 8-2): OAM frame fragments enter the Adaptation
Layer TX path from a "reserved" (OAM) source, are 4b/5b encoded, and packed into the
OAM_fragment field of each physical layer block alongside the 64b/65b xMII data.
Rate matching block insertion also occurs in this pre-FEC stage.

---

## 18. Verification Plan

### 18.1 Unit-Level Tests

| Test | Description | Expected |
|------|-------------|----------|
| UTx-01 | 64b/65b encoder: data block (Sync=0), all byte values | xMII_block[0:64] per Table 8-13 |
| UTx-02 | 64b/65b encoder: control block (Sync=1, BT=0x1e) | Skip||R|| pattern |
| UTx-03 | 4b/5b encoder: all 16 data nibble values | Table 8-14 exact codes |
| UTx-04 | 4b/5b encoder: all control symbols (H/I/J/K/L/Q/R/S/T) | Table 8-15 exact codes |
| UTx-05 | CRC8: known input byte sequence | Verify against independently computed CRC8/0xA6 |
| UTx-06 | CRC8: reset between frames | CRC state = 0xFF at start of each OAM frame |
| UTx-07 | OAM TX fragmentation: single OAM frame | JJ/JK SOP, data chars, CRC byte, TI EOP |
| UTx-08 | OAM TX fragmentation: between two OAM frames | II IDLE chars between EOP and next JJ |
| UTx-09 | Rate matching: FIFO below low-water mark | Skip||R|| inserted at correct cadence |
| UTx-10 | Rate matching: FIFO above high-water mark | No Skip||R|| inserted |
| URx-01 | 64b/65b decoder: data block | Reconstructed TXD/RXD octets correct |
| URx-02 | Rate matching deletion: BT=0x1e block removed | Block not passed to 64b/65b decoder |
| URx-03 | Rate matching: non-Skip block (e.g., BT=0x78) passed through | Block delivered to decoder |
| URx-04 | OAM RX: correct frame, CRC matches | Frame delivered, no counter increment |
| URx-05 | OAM RX: frame with CRC error | Frame discarded, register 3.3.24 incremented |
| URx-06 | OAM RX: JJ without following JK | SOP state machine returns to IDLE_SCAN |
| URx-07 | PTB TX timestamp: JK event pulse at TX MDI | ptb_mdi_tx_oam pulse asserted once per OAM frame |
| URx-08 | PTB RX timestamp: JK event pulse at RX MDI | ptb_mdi_rx_oam pulse asserted once per OAM frame |
| USc-01 | Secondary ctrl channel: bit[1919]=1, bits[1917:1908] non-zero | sec_ctrl_present_rx=1, data correct |
| USc-02 | Secondary ctrl channel: bit[1919]=0 | sec_ctrl_present_rx=0, bits ignored |

### 18.2 Integration Tests

| Test | Description |
|------|-------------|
| INT-01 | End-to-end: GMII ETH frame at 1Gbps through MLES_sym1G0 adaptation, PCS loopback |
| INT-02 | Asymmetric: XGMII 10Gbps DS / MII 100Mbps US through MLES_10G_M |
| INT-03 | OAM frame round-trip: fragmentation TX, reassembly RX, CRC integrity |
| INT-04 | Rate matching under sustained traffic (high xMII utilization) |
| INT-05 | Rate matching under idle (all Skip||R||) |
| INT-06 | PTB timestamp propagation: JK MDI event captured, latched, OAM header updated |
| INT-07 | CRC8 error injection: flip one bit in OAM frame; verify discard and counter |
| INT-08 | Clock ppm stress: TXCLK +/- 100 ppm vs PCS clock; verify no FIFO underrun/overflow |
| INT-09 | All seven MLE speed modes back-to-back mode switch (MLEconfig change) |

---

## 19. Missing / Needs Verification

1. **Table 8-12 numeric values (PARTIALLY RECOVERED)**: The structured extraction
   shows garbled table values for Table 8-12 in the JSONL. The PDF screenshots (p299)
   provide the complete table:
   MLES_sym1G0: DS=208, US=208; Skip DS=51, US=51.
   MLES_sym2G5: DS=832, US=832; Skip DS=47, US=47.
   MLES_sym5G0: DS=364, US=364; Skip DS=9, US=9.
   MLES_2G5_M: DS=96, US=80; Skip DS=1, US=61.
   MLES_5G0_M: DS=936, US=1040; Skip DS=1, US=853.
   MLES_10G_M: DS=1944, US=480; Skip DS=9, US=93.
   MLES_10G_G: DS=936, US=208; Skip DS=1, US=21.
   STATUS: RESOLVED from PDF screenshot. Values recorded in Section 7.2 above.

2. **tx_phy_blockE exact xMII_block packing**: RESOLVED. Figure 8-3 / Table 8-5 gives
   payload span bits[1897:208] = 1690 bits, which fits exactly 26 xMII_blocks x 65
   bits. Earlier local notes referring to 65 xMII_blocks per single physical layer
   block were inconsistent with the payload span and have been corrected.

3. **OAM fragment field width vs. xMII_block count per physical layer block**: RESOLVED.
   Each tx_phy_blockE carries one 10-bit OAM fragment field plus a 1690-bit xMII
   payload field containing 26 xMII_blocks. OAM fragmentation remains one 10-bit slot
   per physical layer block, consistent with Section 8.6.2.1.

4. **Register 3.3.24 definition**: Section 8.7.2.2 references register 3.3.24 for
   OAM integrity checksum failure count. The structured register extraction uses
   domain notation d.a (not d.d.a notation for 3.3.24). NEEDS VERIFICATION: Locate
   exact register definition in Section 3.3 of the spec. The notation 3.3.24 may
   mean domain 3, subdomain 3, address 24 or it may be Section 3.3 item 24.

5. **4b/5b decoder for all code points**: Table 8-14 provides the forward (encode)
   table. The decode table (5-bit code to 4-bit data) is the inverse. All 32 possible
   5-bit codes should be mapped: 16 data codes, 9 control codes (H/I/J/K/L/Q/R/S/T)
   = 25 defined codes. The 7 undefined codes (invalid code words) should generate an
   error signal to the OAM reassembler. NEEDS IMPLEMENTATION DECISION on error
   handling for invalid 4b/5b codes.

6. **Secondary control channel protocol content**: Section 8.6.3 states only that
   the secondary channel is optional and indicated by bit[1919]. No protocol content,
   rate, or format is defined in sections 8.6.3 or 8.7. This is either deferred to a
   future specification revision or is entirely implementer-defined.
   NEEDS CLARIFICATION from ASA specification body or implementer requirements.

7. **CRC8 test vector**: Section 8.6.2.4 defines the CRC8 polynomial and parameters
   but provides no test vector. A reference test vector must be generated from an
   independent CRC8 implementation using polynomial 0xA6 (reflected in/out, init
   0xFF, XOR 0xFF) before RTL verification. The CRC-8 family with these parameters
   should be confirmed against SPEC before golden model lock.

8. **xMII TXCLK source for XGMII**: For XGMII at 10 Gbps, TXCLK is 156.25 MHz with
   DDR (data on both edges, effectively 312.5 MHz equivalent). The spec mentions XGMII
   by name but does not re-specify IEEE 802.3 XGMII timing. NEEDS VERIFICATION that
   the adaptation layer handles XGMII DDR correctly.

9. **Skip||R|| insertion during ETH packet**: Section 8.6.1.1 states "rate matching
   control blocks may be inserted between or during ETH packet transmission." Inserting
   during a packet is unusual for standard Ethernet. NEEDS CLARIFICATION on how the
   64b/65b decoder at the remote end reassembles the packet after mid-packet Skip||R||
   deletion -- specifically, whether the Ethernet frame byte count and CRC are
   preserved correctly across the insertion point.
