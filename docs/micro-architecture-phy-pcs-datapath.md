# Micro-Architecture: PHY PCS Digital Datapath

## 1. Purpose and Scope

The Physical Coding Sublayer (PCS) is the digital signal processing core of the ASA
Physical Layer. It transforms DLL containers into scrambled, FEC-encoded, PAM-mapped
symbol streams for transmission, and reverses this process on receive. It also
generates the Resynchronization Header containing PTB messages and sync sequences
for burst alignment.

This document defines the micro-architecture for RTL/golden-model implementation
of the PCS digital datapath for ASA Gen2020 (Section 4).

Scope:
- IN SCOPE: TDD burst structure, resync header assembly/detection, PRBS11/PRBS9
  generators, PTB message vector codec, RS-FEC encoding/decoding, additive
  scrambler/descrambler, PAM2/PAM4 mapping, CRC32 engine, PLP_TX/PLP_RX primitive
  interface, link quality monitoring hooks, test pattern generation interface
- OUT OF SCOPE: PMA analog circuits (DAC/ADC, CDR, equalization), full startup FSM
  state machines (see micro-architecture-node-state-machine.md), MLE xMII
  adaptation (Section 8.6), DLL mapper internals (see micro-architecture-dll-mapper-demux-core.md)

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 4.2 | Physical Coding Sublayer Functions | 95 | Speed grade overview Table 4-1 |
| 4.2.1 | PCS Reset Function | 95 | Reset scope and timing |
| 4.2.2.1 | PCS Transmit Process | 95-96 | Figure 4-1, Figure 4-2, data flow |
| 4.2.2.2 | Time Division Duplexing Data Burst | 96 | Tables 4-2, 4-3, 4-4 |
| 4.2.2.2.1 | Synchronization to PTB | 97 | TDD cycle = 6844 PTB tics |
| 4.2.2.3 | Resynchronization Header | 97-101 | Figure 4-3, Equations 4-1/4-2 |
| 4.2.2.3.1 | Header Assembly and Mapping | 98 | Tables 4-5, 4-6 |
| 4.2.2.3.2 | Synchronization Sequence | 99 | 40-bit sy vector, sy_double |
| 4.2.2.3.3 | PRBS11 Pattern | 100 | Polynomial, Figure 4-4, init |
| 4.2.2.3.4 | Dithering Source | 100 | PRBS9, 5-bit offset, Figure 4-5 |
| 4.2.2.3.5 | PTB Message Vector | 101 | Tables 4-8, 4-9 (m_ptb[15:0]) |
| 4.2.2.4 | Physical Layer Block RS-FEC | 101-102 | Figures 4-6, 4-7, 4-8 |
| 4.2.2.4.1 | Downstream SG1/SG2 | 102 | 642B payload, 3x RS(216,214) |
| 4.2.2.4.2 | Downstream SG3/4/5 | 102 | 642B payload, 3x RS(240,214) |
| 4.2.2.4.3 | Upstream SG1/2 | 102 | 212B payload, 2x RS(108,106) |
| 4.2.2.5 | PCS Scrambler | 103 | Additive side-stream scrambling |
| 4.2.2.5.1 | Dn SG1/2/3 scrambler | 103 | Single-bit XOR from S0 |
| 4.2.2.5.2 | Dn SG4/5 scrambler | 103 | Dual-bit XOR from S0,S1 |
| 4.2.2.5.3 | Up SG1/2 scrambler | 103 | Single-bit XOR from S0 |
| 4.2.2.6 | PAM2 Mapping | 103 | 0->+1, 1->-1 |
| 4.2.2.7 | PAM4 Gray Encoding | 104 | {0,0}->+1, {0,1}->+1/3, etc. |
| 4.2.3 | PCS Receive Functions | 104 | RX overview |
| 4.2.3.1 | Burst Synchronization | 104 | Detect resync hdr, polarity |
| 4.2.3.2 | PCS Descrambler | 104 | Same operation as TX scrambler |
| 4.2.3.3 | RS-FEC Decoding | 104 | Integrity check, correction |
| 4.2.4 | RS-FEC Encoder Definition | 104-106 | Three encoder variants |
| 4.2.4.1 | RS(108,106) | 104 | Upstream encoder |
| 4.2.4.2 | RS(216,214) | 105 | Downstream SG1/2 encoder |
| 4.2.4.3 | RS(240,214) | 106 | Downstream SG3/4/5 encoder |
| 4.2.5 | Side-Stream Scrambler Polynomial | 107-108 | Dn: x^23+x^5+1, Up: x^23+x^18+1 |
| 4.2.6 | Test Pattern Generation | 109 | References 4.4.1.1 |
| 4.2.9 | CRC32 | 120 | Polynomial 0xF4ACFB13 |
| 4.6 | PLP_TX Interface | 156-157 | TX primitives |
| 4.7 | PLP_RX Interface | 157-158 | RX primitives |

Image references:
- Figure 4-1 (PDF p95): Normal Mode PCS transmit data flow
- Figure 4-2 (PDF p96): DLL container mapping to physical layer block
- Figure 4-3 (PDF p97): Resynchronization header construction
- Figure 4-4 (PDF p100): PRBS11 LFSR block diagram
- Figure 4-5 (PDF p100): PRBS9 dithering LFSR block diagram
- Figure 4-6 (PDF p102): Dn SG1/2 FEC mapping (3 codewords)
- Figure 4-7 (PDF p102): Dn SG3/4/5 FEC mapping
- Figure 4-8 (PDF p102): Upstream FEC mapping (2 codewords)
- Figure 4-9 (PDF p104): RS(108,106) parity generation shift register
- Figure 4-10 (PDF p105): RS(216,214) parity generation
- Figure 4-11 (PDF p106): RS(240,214) parity generation
- Figure 4-12 (PDF p107): Downstream scrambler LFSR
- Figure 4-13 (PDF p108): Upstream scrambler LFSR
- Figure 4-14 (PDF p109): Startup PCS transmit data flow (reuses normal mode)
- docpdfmd/images/20-24_Speed_Grade_*.png: TX PSD limit masks per speed grade
- docpdfmd/images/32_CRC32_calculation_table.png: CRC32 test vector

---

## 3. TX Datapath Pipeline

SPEC FACT (Section 4.2.2.1, Figure 4-1, p95):

```
DLL Container (d_plp_tx<7:0>)
         |
         v
+------------------+
| Physical Layer   |    PTB Message
| Block Assembly   |<-- m_ptb<15:0> from PTB Clock Service
| (RS-FEC framing) |
+--------+---------+
         | tx_phy_block
         v
+------------------+       +---------------------+
| Resync Header    |       | PCS Scrambler       |
| Generator        |       | (Dn: x^23+x^5+1)   |
| - PRBS11         |       | (Up: x^23+x^18+1)  |
| - Sync sequence  |       | Additive XOR        |
| - PTB vector     |       +----------+----------+
| - Dithering      |                  |
+--------+---------+                  | tx_phy_block_scr
         |                            v
         | tx_phy_rsync_hdr  +--------+----------+
         |                   | tx_phy_rsync_hdr  |
         +------------------>| tx_phy_block_scr  |
                             | (concatenated)    |
                             +--------+----------+
                                      |
                                      v
                             +------------------+
                             | PAM2 / PAM4      |
                             | Mapping           |
                             +--------+---------+
                                      |
                                      v
                              To PMA (analog TX)
```

### 3.1 TX Step-by-Step

1. PCS receives `PLP_TX.nextPhyBlock()` trigger from timing logic
2. DLL responds with `PLP_TX.dataUnit(d_plp_tx)` containing one container
3. Container bytes are packed into physical layer block with RS-FEC parity
4. Block is scrambled with side-stream additive scrambler
5. Resync header is generated (PRBS11 + sync sequences + PTB message + dithering)
6. Resync header (LSB first) + scrambled block (MSB first) are concatenated
7. Output mapped to PAM2 (SG1/2/3) or PAM4 (SG4/5) symbols
8. Quiet gap inserted after burst

---

## 4. RX Datapath Pipeline

SPEC FACT (Sections 4.2.3, 4.7):

```
From PMA (analog RX)
         |
         v
+------------------+
| Burst Sync       |   Detect resync header, correct polarity,
| (4.2.3.1)        |   align to physical layer block boundaries
+--------+---------+
         |
         v
+------------------+    Extract m_ptb<15:0> from resync header
| PTB Message      |----> to PTB Clock Service
| Extraction       |
+--------+---------+
         |
         v
+------------------+
| PCS Descrambler  |   Same additive scrambler, XOR reversal
| (4.2.3.2)        |
+--------+---------+
         |
         v
+------------------+
| RS-FEC Decode    |   Check/correct parity, report errStat
| (4.2.3.3)        |
+--------+---------+
         |
         v
PLP_RX.dataUnit(phyL_block_rx, errStat) --> to DLL
```

---

## 5. TDD Burst Timing and PTB Relationship

### 5.1 TDD Cycle Duration

SPEC FACT (Section 4.2.2.2.1, p97): "The PCS in the root node (clock leader)
starts a new TDD cycle every 6844 PTB tics (with a tolerance of +/-1)."

6844 PTB tics * 4ns = 27.376 us per TDD cycle (Gen2020).

### 5.2 Burst Structure

```
+---+-----------------------------+---+-----------------------------+---+
|IBG| Resync Hdr | Phy Block(s)  |QG | Resync Hdr | Phy Block(s)  |IBG|
|   |            | (Downstream)  |   |            | (Upstream)    |   |
+---+-----------------------------+---+-----------------------------+---+
|<--------- Downstream Burst ------->|<------- Upstream Burst ------>|
|<--------------------- TDD Cycle ---------------------------------------->|
```

### 5.3 Physical Layer Blocks per Burst

SPEC FACT (Section 4.2.2.2, Tables 4-2, 4-3):

| Direction | Speed Grade | Blocks per Burst |
|-----------|-------------|-----------------|
| Downstream | SG1 | (from Table 4-2) |
| Downstream | SG2 | (from Table 4-2) |
| Downstream | SG3 | (from Table 4-2) |
| Downstream | SG4 | (from Table 4-2) |
| Downstream | SG5 | (from Table 4-2) |
| Upstream | SG1 | (from Table 4-3) |
| Upstream | SG2 | (from Table 4-3) |

IMPLEMENTATION NOTE: Tables 4-2, 4-3, and 4-4 render as empty cells in the
extraction. Exact block counts per speed grade must be verified from PDF. The
1:1 correspondence between DLL containers and physical layer blocks is confirmed
by Figure 4-2 and the payload sizes (642B Dn, 212B Up).

---

## 6. Resynchronization Header

### 6.1 Structure (Figure 4-3, p97)

```
tx_phy_rsync_hdr<0:resylen-1>:

[PRBS11 fill | sync_double | PRBS11 | sync | PRBS11 | m_ptb | ~m_ptb]
 0..n-1        n..n+79       n+80..  m..m+39  ..      last32  last16
                                                        bits    bits
```

For SG3/4/5: sync_double and sync sequences are doubled (repeated 2x).

### 6.2 Resync Header Lengths (Table 4-5)

SPEC FACT (Section 4.2.2.3.1):

| Speed Grade | resylen (symbols) |
|-------------|-------------------|
| SG1 | (from Table 4-5) |
| SG2 | (from Table 4-5) |
| SG3 | (from Table 4-5) |
| SG4 | (from Table 4-5) |
| SG5 | (from Table 4-5) |

### 6.3 Sync Sequence Positions (Table 4-6)

SPEC FACT (Section 4.2.2.3.1):
```
First sync position:  n = 64 + 2*offset
Second sync position: m = depends on speed grade + offset

SG1: m = 264 + offset
SG2: m = 648 + offset
SG3: m = 1376 + offset
SG4: m = 992 + offset
SG5: m = 1376 + offset
```

Offset is a 5-bit value (0-31) from the PRBS9 dithering source.

### 6.4 Construction Equations

**SG1/SG2 (Equation 4-1):**
```
tx_phy_rsync_hdr<k> =
  rsync_prbs<k>                    for 0 <= k <= n-1
  sy_double<k mod n>               for n <= k <= n+79
  rsync_prbs<k>                    for n+80 <= k <= m-1
  sy<k mod m>                      for m <= k <= m+39
  rsync_prbs<k>                    for m+40 <= k <= resylen-33
  m_ptb<k mod (resylen-32)>        for resylen-32 <= k <= resylen-17
  ~m_ptb<k mod (resylen-16)>       for resylen-16 <= k <= resylen-1
```

**SG3/4/5 (Equation 4-2):** Same but with doubled sync sequences (80+80 and 40+40).

### 6.5 PTB Message Vector in Header (last 32 symbols)

SPEC FACT: m_ptb[15:0] is placed at the END of the resync header:
- Bits 15:0 in normal polarity at positions resylen-32 to resylen-17
- Bits 15:0 inverted at positions resylen-16 to resylen-1

This allows the receiver to extract PTB timestamps and determine signal polarity.

---

## 7. PRBS11 Generator (Section 4.2.2.3.3)

SPEC FACT:
- Polynomial: g_ReSy(x) = x^11 + x^2 + 1
- LFSR: S_ReSy[10:0], output tap S0 = S_ReSy[0]
- Feedback: S_ReSy[0] XOR S_ReSy[9] -> input
- Init: Reset to 0x001 at startup_INIT
- One shift per resync header symbol

---

## 8. Dithering Source / PRBS9 (Section 4.2.2.3.4)

SPEC FACT:
- Polynomial: g_Di(x) = x^9 + x^4 + 1
- LFSR: S_Di[8:0], output tap S0 = S_Di[0]
- Init: Reset to 0x001 at startup_INIT
- Offset generation: advance LFSR 5 times, combine as:
  `offset = {S[t=0], S[t=1], S[t=2], S[t=3], S[t=4]}` (5-bit, MSB first)
- Value range: 0 to 31
- New offset value generated per resynchronization header

---

## 9. RS-FEC Encoding

### 9.1 Encoder Selection by Speed Grade

SPEC FACT:

| Direction | Speed Grade | Encoder | k | 2t | n | Codewords/Block |
|-----------|-------------|---------|---|----|----|-----------------|
| Downstream | SG1, SG2 | RS(216,214) | 214 | 2 | 216 | 3 |
| Downstream | SG3, SG4, SG5 | RS(240,214) | 214 | 26 | 240 | 3 |
| Upstream | SG1, SG2 | RS(108,106) | 106 | 2 | 108 | 2 |

### 9.2 Physical Layer Block Sizes

SPEC FACT:
- Dn SG1/2: tx_phy_block<5183:0> = 3 * 216 * 8 = 5184 bits (642B payload + 6B parity)
- Dn SG3/4/5: tx_phy_block<5759:0> = 3 * 240 * 8 = 5760 bits (642B payload + 78B parity)
- Up SG1/2: tx_phy_block<1727:0> = 2 * 108 * 8 = 1728 bits (212B payload + 4B parity)

### 9.3 Container-to-FEC Mapping

SPEC FACT (Section 4.2.2.4.1, Figure 4-6):
- d_plp_tx bytes 0-213 -> 1st codeword message m[213]..m[0]
- d_plp_tx bytes 214-427 -> 2nd codeword message
- d_plp_tx bytes 428-641 -> 3rd codeword message
- Each codeword: (m[k-1,7], m[k-1,6], ..., m[0,0], p[2t-1,7], ..., p[0,0])

### 9.4 RS Encoder Definitions

**RS(108,106)** -- Section 4.2.4.1:
- GF(2^8), primitive polynomial: x^8 + x^4 + x^3 + x^2 + 1
- Generator: g(x) = (x - a^0)(x - a^1) = g2*x^2 + g1*x + g0
- Coefficients: g0=0x02, g1=0x03, g2=0x01

**RS(216,214)** -- Section 4.2.4.2:
- Same GF(2^8) and primitive polynomial
- Generator: same form, same coefficients g0=0x02, g1=0x03, g2=0x01

**RS(240,214)** -- Section 4.2.4.3:
- Same GF(2^8) and primitive polynomial
- Generator: g(x) = product_{i=0}^{25} (x - a^i), 27 coefficients
- g0=0x5E, g1=0x2B, g2=0x4D, ..., g25=0xF6, g26=0x01 (Table 4-12)

### 9.5 RS-FEC Decoding Requirements (Section 4.2.3.3)

SPEC FACT:
- "Check integrity of RS-FEC parity bits. If correction fails, frame is invalid."
- "For SG1 and SG2, only the integrity check is mandatory, correction is optional."
- "Statistics shall be kept in registers 3.2.16 (FECstat) and 3.2.13 (LinkQuality)."

errStat output of PLP_RX.dataUnit:
- noErr: no byte error
- corErr: corrected byte error(s)
- uncErr: uncorrectable byte errors

---

## 10. Scrambler / Descrambler (Section 4.2.5)

### 10.1 Polynomials

SPEC FACT:
- Downstream: g_Dn(x) = x^23 + x^5 + 1
- Upstream: g_Up(x) = x^23 + x^18 + 1

### 10.2 LFSR Structure

**Downstream (Figure 4-12):** S_Dn[22:0]
- Output tap S0: feedback from S_Dn[0] XOR S_Dn[22] -> input
- Second output S1 = S_Dn[2] XOR S_Dn[5] (for SG4/5 PAM4)

**Upstream (Figure 4-13):** S_Up[22:0]
- Output tap S0: feedback from S_Up[0] XOR S_Up[22] -> input

### 10.3 Scrambler Application

SPEC FACT (Sections 4.2.2.5.1-3):

| Direction/SG | Bits scrambled | Operation |
|---|---|---|
| Dn SG1/2/3 | tx_phy_block<MSB:0> | XOR with S0, one shift per bit |
| Dn SG4/5 | tx_phy_block<MSB:0> | XOR pairs with {S0,S1}, one shift per 2 bits |
| Up SG1/2 | tx_phy_block<MSB:0> | XOR with S0, one shift per bit |

### 10.4 Scrambler State Management

SPEC FACT (Section 4.2.5):
- Init: S_Dn[22:0] = S_Up[22:0] = 0x000001 for LinkID=0
- Alternative seeds: 0x000003/0x000005/0x000007 for LinkID=1/2/3
- Reset at startup_INIT (root) or first received Phase1G resync header (leaf)
- Advanced during startup phases (4.2.7)
- **Held** during resync header and quiet gap (not advanced)

---

## 11. PAM Mapping (Sections 4.2.2.6, 4.2.2.7)

### 11.1 PAM2 (SG1, SG2, SG3, and all Upstream)

SPEC FACT (Section 4.2.2.6):
```
Bit 0 -> symbol +1
Bit 1 -> symbol -1
```
One bit maps to one baud-rate symbol.

### 11.2 PAM4 Gray Encoding (SG4, SG5 Downstream only)

SPEC FACT (Section 4.2.2.7):
```
{MSB, LSB} -> symbol
{0, 0}     -> +1
{0, 1}     -> +1/3
{1, 1}     -> -1/3
{1, 0}     -> -1
```
Two bits map to one baud-rate symbol (Gray coded).

---

## 12. CRC32 (Section 4.2.9)

SPEC FACT:
- Polynomial: 0xF4ACFB13
- Starting value: 0xFFFFFFFF
- XOR appendix: 0xFFFFFFFF
- Input: byte-wise reflected
- Output: reflected

Image 32_CRC32_calculation_table.png provides a 16-step test vector:
- Byte 0: 0x80, CRC=0x00000000
- Byte 1: 0x55, CRC=0xA8C9E9B6
- ...
- Byte 15: (end), CRC=0xB843C1B8

IMPLEMENTATION NOTE: CRC32 is used for the startup info field integrity check
(Section 4.2.7.5, Table 4-20). Not used on normal-mode physical layer blocks
(those use RS-FEC for integrity).

---

## 13. PLP Interface Contracts

### 13.1 PLP_TX Primitives (Section 4.6)

| Primitive | Parameters | Description |
|-----------|-----------|-------------|
| PLP_TX.dataUnit | d_plp_tx<7:0><0:len-1> | DLL provides container bytes |
| PLP_TX.nextPhyBlock | (none) | PCS requests next block |
| PLP_TX.PCSreset | (none) | Reset all PCS state |
| PLP_TX.startup | PTBstamp | Trigger startup sequence |
| PLP_TX.lightSleep | (none) | Enter Light Sleep |

Container lengths (len):
- Downstream: 642 bytes (header + payload)
- Upstream: 212 bytes

### 13.2 PLP_RX Primitives (Section 4.7)

| Primitive | Parameters | Description |
|-----------|-----------|-------------|
| PLP_RX.dataUnit | phyL_block_rx, errStat | Decoded block to DLL |
| PLP_RX.linkLoss | index | Expected burst not detected |
| PLP_RX.linkFail | index | Normal mode exit to retry |

phyL_block_rx sizes: 642B (Dn), 212B (Up)
errStat: noErr / corErr / uncErr

---

## 14. Link Quality Monitoring

### 14.1 Related Registers

| Register | Address | Content |
|----------|---------|---------|
| LinkQuality | 1.0101 | Link losses [15:10], FEC block losses [9:0] |
| SQI | 1.0102 | Signal Quality Indicator |
| MSE | 1.0103 | Mean Square Error |
| FECstat | 1.0104 | FEC correction statistics |

### 14.2 Update Logic

SPEC FACT (Section 4.2.3.3): "Statistics shall be kept in registers 3.2.16 and 3.2.13."
- FECstat: count of corrected codewords (or corrected symbols, per implementation)
- LinkQuality[9:0]: count of physical layer blocks with uncorrectable FEC
- LinkQuality[15:10]: count of entirely lost TDD bursts (link losses)
- PLP_RX.linkLoss increments link loss count

---

## 15. Test Pattern Generation (Section 4.2.6)

SPEC FACT: "Test pattern generation is described in the respective subsections of
transmitter test modes in 4.4.1.1."

Test types (from Phase1G info field, Table 4-15, bits 10:8):
- 001: Linearity test (PRBS13Q pattern, Section 4.4.1.1.2)
- 010: Jitter test (Section 4.4.1.1.3)
- 011: Droop test (Section 4.4.1.1.4)
- 100: PSD test (Section 4.4.1.1.5)
- 101: BER test (Section 4.4.1.1.6)

The test pattern generator replaces the normal FEC-encoded physical layer block
output with a defined test sequence. The PCS scrambler and PAM mapping still apply.

---

## 16. Interfaces

### 16.1 Interface to DLL Mapper/Demux Core

| Signal | Dir | Description |
|--------|-----|-------------|
| plp_tx_next_phy_block | PCS->DLL | Request next container |
| plp_tx_data_unit(bytes[]) | DLL->PCS | Container bytes (642 or 212) |
| plp_rx_data_unit(bytes[], errStat) | PCS->DLL | Decoded block + status |
| plp_rx_link_loss | PCS->DLL | Burst detection failure |
| plp_rx_link_fail | PCS->DLL | Exit normal mode |

### 16.2 Interface to PTB Clock Service

| Signal | Dir | Description |
|--------|-----|-------------|
| ptb_tdd_cycle_start | PTB->PCS | Start new TDD cycle (every 6844 tics) |
| ptb_m_ptb_tx[15:0] | PTB->PCS | PTB message for resync header |
| ptb_m_ptb_rx[15:0] | PCS->PTB | Extracted PTB message from RX |
| ptb_mdi_tx_event | PCS->PTB | First symbol passes TX MDI |
| ptb_mdi_rx_event | PCS->PTB | First symbol passes RX MDI |

### 16.3 Interface to Node State Machine

| Signal | Dir | Description |
|--------|-----|-------------|
| pcs_reset | NSM->PCS | PLP_TX.PCSreset equivalent |
| startup_trigger(ptb_stamp) | NSM->PCS | PLP_TX.startup equivalent |
| light_sleep_trigger | NSM->PCS | PLP_TX.lightSleep equivalent |
| pcs_mode | NSM->PCS | normal/startup/test/sleep |

### 16.4 Interface to PMA Startup FSM

| Signal | Dir | Description |
|--------|-----|-------------|
| startup_phase | FSM->PCS | Phase1G/SGA/SGB/SGC/Normal |
| tx_pattern_sel | FSM->PCS | Training vs normal vs test |
| phase1g_info[39:0] | FSM->PCS | Phase1G info field content |
| phaseSG_info[511:0] | FSM->PCS | PhaseSGA/B/C info field |

### 16.5 Interface to Register Model

| Signal | Dir | Description |
|--------|-----|-------------|
| sg_config[4:0] | Reg->PCS | Speed grade from 1.0002 |
| link_quality_update | PCS->Reg | Increment 1.0101 counters |
| fec_stat_update | PCS->Reg | Increment 1.0104 counter |
| link_id[1:0] | Reg->PCS | LinkID for scrambler seed |

---

## 17. Suggested RTL Module Boundaries

```
+================================================================+
|                       pcs_top                                    |
|                                                                  |
|  TX PATH                                                         |
|  +---------------------+    +---------------------+             |
|  | pcs_tx_ctrl         |    | tdd_burst_scheduler |             |
|  |                     |    |                     |             |
|  | Sequences TX stages |    | PTB cycle counting  |             |
|  | Normal/startup/test |    | Burst/quiet timing  |             |
|  | mode mux            |    | Block count per SG  |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | resync_header_gen   |    | fec_encoder         |             |
|  |                     |    |                     |             |
|  | Assemble resync hdr |    | RS(108,106) for Up  |             |
|  | Insert sync seq     |    | RS(216,214) for Dn12|             |
|  | Insert PTB msg      |    | RS(240,214) for Dn345|            |
|  | Dithering offset    |    | GF(2^8) arithmetic  |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | prbs11_gen          |    | scrambler           |             |
|  |                     |    |                     |             |
|  | x^11+x^2+1 LFSR    |    | Dn: x^23+x^5+1     |             |
|  | S_ReSy[10:0]        |    | Up: x^23+x^18+1    |             |
|  | Init 0x001          |    | S0 (and S1 for SG4/5)|            |
|  +---------------------+    | Hold during resync  |             |
|                             +---------------------+             |
|  +---------------------+                                        |
|  | dithering_source    |    +---------------------+             |
|  |                     |    | pam2_mapper         |             |
|  | x^9+x^4+1 LFSR     |    |                     |             |
|  | 5-bit offset gen    |    | 0->+1, 1->-1       |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | ptb_msg_vector_codec|    | pam4_gray_encoder   |             |
|  |                     |    |                     |             |
|  | TX: insert m_ptb    |    | {0,0}->+1           |             |
|  | + inverted copy     |    | {0,1}->+1/3         |             |
|  | RX: extract m_ptb   |    | {1,1}->-1/3         |             |
|  | + polarity detect   |    | {1,0}->-1           |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  RX PATH                                                         |
|  +---------------------+    +---------------------+             |
|  | pcs_rx_ctrl         |    | resync_header_check |             |
|  |                     |    |                     |             |
|  | Sequences RX stages |    | Sync sequence corr  |             |
|  | errStat routing     |    | Polarity detection  |             |
|  | Link loss detect    |    | Block alignment     |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | descrambler         |    | fec_decoder         |             |
|  |                     |    |                     |             |
|  | Same LFSR as TX     |    | Syndrome calc       |             |
|  | Additive reversal   |    | Error correction    |             |
|  +---------------------+    | (optional SG1/2)    |             |
|                             +---------------------+             |
|  COMMON                                                          |
|  +---------------------+    +---------------------+             |
|  | crc32_engine        |    | test_pattern_gen    |             |
|  |                     |    |                     |             |
|  | Poly 0xF4ACFB13     |    | PRBS13Q, jitter,    |             |
|  | For startup info    |    | droop, PSD, BER     |             |
|  | CRC integrity check |    | patterns            |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | link_quality_monitor|    | pcs_register_adapter|             |
|  |                     |    |                     |             |
|  | FECstat, LinkQuality|    | SG config decode    |             |
|  | SQI, MSE hooks      |    | LinkID seed         |             |
|  | errStat aggregation |    | Status read-back    |             |
|  +---------------------+    +---------------------+             |
+================================================================+
```

---

## 18. Spec Facts vs Implementation Assumptions

### Spec Facts (normative)
- 1:1 correspondence between DLL containers and physical layer blocks
- Resync header sent LSB first; physical layer block sent MSB first
- PRBS11 polynomial: x^11 + x^2 + 1, init 0x001
- PRBS9 polynomial: x^9 + x^4 + 1, init 0x001
- Dn scrambler: x^23 + x^5 + 1, init 0x000001 (LinkID=0)
- Up scrambler: x^23 + x^18 + 1, init 0x000001 (LinkID=0)
- Scrambler held during resync header and quiet gap
- PAM2: 0->+1, 1->-1
- PAM4 Gray: {0,0}->+1, {0,1}->+1/3, {1,1}->-1/3, {1,0}->-1
- RS(108,106) for upstream, RS(216,214) for Dn SG1/2, RS(240,214) for Dn SG3/4/5
- All RS encoders use GF(2^8) with primitive poly x^8+x^4+x^3+x^2+1
- CRC32 polynomial: 0xF4ACFB13, init 0xFFFFFFFF, XOR 0xFFFFFFFF
- FEC correction optional for SG1/2 (integrity check mandatory)
- TDD cycle: 6844 PTB tics for Gen2020 clock leader

### Implementation Assumptions (not in spec)
- FEC encoder latency: one container pipeline delay (implementation trades area vs latency)
- Scrambler can be implemented as parallel XOR tree for high-speed SG
- PAM4 output levels (+1, +1/3, -1/3, -1) are normalized; actual voltage from PMA DAC
- Test pattern generator shares scrambler and PAM mapper pipeline stages
- CRC32 computation may be parallelized to 8/16/32-bit widths
- Link quality counters update at end-of-block (after FEC decode completes)

---

## 19. Missing / Needs Verification

1. **Tables 4-2, 4-3, 4-4, 4-5 numeric values**: These critical tables (physical
   layer blocks per burst, quiet gap lengths, resync header lengths) render as empty
   cells in the extraction. VERIFY exact numeric values from PDF pages 96-98.

2. **Synchronization sequence sy<0:39> bit values**: Table 4-7 defines the 40-bit
   fixed vector but the extraction does not render individual bit values. VERIFY
   from PDF page 99.

3. **Downstream scrambler S1 generation**: Equation 4-10 states S1 = S_Dn[2] XOR
   S_Dn[5]. This second output tap is only used for SG4/5 (PAM4 requires 2 bits
   per symbol). VERIFY the exact tapping positions from Figure 4-12.

4. **FEC decoder correction capability**: For RS(240,214), t=13 (can correct up to
   13 symbol errors). For RS(216,214) and RS(108,106), t=1. The spec says correction
   is optional for SG1/2. VERIFY whether SG3/4/5 correction is mandatory.

5. **CRC32 usage scope**: The extraction confirms CRC32 is defined in 4.2.9 and used
   for startup info field (4.2.7.5). VERIFY whether CRC32 is also used in any
   normal-mode data path or only during startup.

6. **MLE PCS differences**: Section 8.2 reuses Gen2020 PCS structure but with
   different scrambler polynomials and FEC parameters for some modes. This document
   covers Gen2020 only. A separate MLE PCS doc is needed for those differences.

7. **Error injection for golden model**: The spec does not define error injection
   points. For verification, implement injection at: pre-FEC (bit flip in message),
   post-FEC (symbol corruption), and channel (PAM level noise). These are
   IMPLEMENTATION ASSUMPTIONS for testbench use.
