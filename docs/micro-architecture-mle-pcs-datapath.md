# Micro-Architecture: MLE PCS Datapath

## 1. Purpose and Scope

This document defines the micro-architecture for RTL/golden-model implementation of the
Physical Coding Sublayer (PCS) digital datapath for ASA Motion Link Ethernet (MLE),
as specified in Section 8 of the ASA Technical Specification v2.0.

MLE defines a Physical Layer compatible with IEEE 802.3 MAC, Reconciliation Sublayer,
and Media-Independent Interface (xMII). It is derived from the Gen2020 ASA Motion Link
Physical Layer (Section 4), reusing the PMA layer and partially reusing the PCS layer.

CRITICAL SCOPE NOTE: This document covers ONLY the differences between MLE and Gen2020
PCS. For all aspects where MLE uses the Gen2020 PCS unchanged, refer to:
  docpdfmd/micro-architecture-phy-pcs-datapath.md

The following areas are DIFFERENT in MLE and are covered here:
- Seven MLE speed modes (MLES_sym1G0 through MLES_10G_G) with distinct TDD timing
- Physical layer block structure: single RS(240,214) codeword for ALL modes
- Physical layer block payload: 64b/65b data from xMII, not DLL containers
- Physical layer block size: tx_phy_blockE<1919:0> (1920 bits = 240 bytes)
- Scrambler polynomial selection: SG1/2/3-based vs SG4/5-based mode determines S0/S1
- MLE Phase1G info field: 40-bit field with MLE-specific capability and config fields
- OAM fragmentation and 4b/5b encoding (Section 8.6.2)
- xMII Transmit Interface Adaptation Layer (Section 8.6) -- interface overview only;
  full xMII adaptation is documented in micro-architecture-mle-xmii-adaptation.md

Scope:
- IN SCOPE: MLE TDD burst structure, MLE speed mode table, MLE FEC selection,
  MLE scrambler differences, MLE Phase1G info field, OAM 4b/5b fragmentation,
  OAM CRC8, PTB timestamp capture, MLEcapability1/2/MLEconfig registers,
  MLE vs Gen2020 difference table, RTL submodule boundaries, interface signals
- OUT OF SCOPE: xMII rate matching internals (see micro-architecture-mle-xmii-adaptation.md),
  OAM frame contents (see micro-architecture-oam-control-plane.md),
  Gen2020 PCS datapath shared logic (see micro-architecture-phy-pcs-datapath.md),
  PMA analog circuits (identical to Gen2020, see Section 8.3)

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 8.1 | ASA Physical Layer -- MLE Overview | 284 | Layer relationship, Figure 8-1 |
| 8.1.1 | MLE Features | 284 | Table 8-1: speed modes, data rates, PMA SG mapping |
| 8.1.2 | Organization of Section 8 | 285 | Section inheritance rules |
| 8.1.3 | ASA MLE Registers | 285 | 1.0020-1.0022 |
| 8.2.2.1 | PCS Transmit Process | 285-286 | Figure 8-2: MLE TX data flow |
| 8.2.2.2 | TDD Burst | 287-288 | Table 8-2 (blocks), Table 8-3 (quiet gap), Table 8-4 (TDD cycle) |
| 8.2.2.2.1 | Synchronization to PTB | 288 | Table 8-4: TDD cycle per mode in PTB tics |
| 8.2.2.3.1 | Header Assembly and Mapping | 288 | Resync header maps to ML SG |
| 8.2.2.4 | Physical Layer Block RS-FEC | 289 | tx_phy_blockE<1919:0>, RS(240,214) |
| 8.2.2.5 | PCS Scrambler | 289-290 | SG1/2/3 vs SG4/5 scrambler application |
| 8.2.3.3 | RS FEC-Decoding | 290 | Mandatory correction for SG3/4/5-based modes |
| 8.2.4 | RS-FEC encoder definition | 290 | RS(240,214) from Section 4.2.4.3 |
| 8.2.7 | Startup and PMA Training | 291-295 | MLE reuses ML startup |
| 8.2.7.1.2 | Phase1G info field | 291-292 | Table 8-6: 40-bit MLE Phase1G info |
| 8.2.7.2 | Startup PhaseSGA | 292-293 | Table 8-7, Table 8-8, Equation 8-1 |
| 8.2.7.3 | Startup PhaseSGB | 293-294 | Table 8-9, Table 8-10 |
| 8.2.7.4 | Startup PhaseSGC | 294-295 | Normal-mode quiet gap, last PLB = inf_SG |
| 8.3.3 | State Diagrams | 295 | References Section 4 (identical) |
| 8.6 | Transmit Interface Adaptation Layer | 296 | Overview |
| 8.6.1 | xMII | 296-299 | Table 8-11 (XGMII/GMII/MII), rate matching |
| 8.6.1.1 | Rate Matching | 299 | Table 8-12: Skip|R|| insertion rates |
| 8.6.1.2 | 64b/65b Mapping | 299-300 | Table 8-13: xMII block to MLE block |
| 8.6.2 | OAM | 300 | Figure 8-9: OAM frame with SOP/EOP/IDLE/CRC |
| 8.6.2.1 | OAM Frame Encoding and Fragmentation | 300 | JJ+JK=SOP, TI=EOP, II=IDLE |
| 8.6.2.2 | PTB Timestamping | 300 | JK of SOP passes transmitting MDI |
| 8.6.2.3 | 4b/5b Encoder | 300-301 | Table 8-14: data, Table 8-15: control |
| 8.6.2.4 | CRC8 Definition | 301 | Poly 0xA6, init 0xFF, XOR 0xFF |
| 8.6.3 | Secondary Control Channel | 301 | Optional, format indicator bit in PLB |
| 8.7 | Receive Interface Adaptation Layer | 302 | RX rate matching, OAM SOP/EOP scan |
| 3.2.9 | MLEcapability1 (1.0020) | -- | Symmetric MLE mode capabilities |
| 3.2.10 | MLEcapability2 (1.0021) | -- | Asymmetric MLE mode capabilities |
| 3.2.11 | MLEconfig (1.0022) | -- | Active MLE mode and direction |

Primary cross-references (for unchanged logic, see):
- micro-architecture-phy-pcs-datapath.md (Gen2020 PCS: scrambler, FEC, resync header)
- micro-architecture-phy-startup-training-fsm.md (Phase1G/SGA/SGB/SGC FSMs)

---

## 3. MLE vs Gen2020 Differences Overview

The following table captures the key points where MLE PCS differs from Gen2020 PCS.
This is the primary reference for implementers who already know the Gen2020 datapath.

SPEC FACT (Section 8.1.2, PDF p285): "If there is no change given in the respective
subsection 8.{section subnumbering}, the corresponding subsection 4.{section
subnumbering} is referenced directly after the section headline with 'See equivalent
subsection in section 4'."

| Topic | Gen2020 (Section 4) | MLE (Section 8) | Spec Ref |
|-------|-------------------|-----------------|----------|
| Data source | DLL container bytes (642B Dn, 212B Up) | xMII 64b/65b blocks | 8.2.2.1, 8.6.1.2 |
| Physical layer block name | tx_phy_block | tx_phy_blockE | 8.2.2.4 |
| PLB size | 5184 bits (Dn SG1/2), 5760 bits (Dn SG3/4/5), 1728 bits (Up) | 1920 bits, all modes | 8.2.2.4 |
| FEC encoder (Dn SG1/2) | RS(216,214), 3 codewords | RS(240,214), 1 codeword | 8.2.4 |
| FEC encoder (Dn SG3/4/5) | RS(240,214), 3 codewords | RS(240,214), 1 codeword | 8.2.4 |
| FEC encoder (Up SG1/2) | RS(108,106), 2 codewords | RS(240,214), 1 codeword | 8.2.4 |
| FEC parity bytes per PLB | 2 (SG1/2 Dn), 26 (SG3/4/5 Dn), 2 (Up) | 26 (all modes) | 8.2.4 |
| Scrambler (SG1/2/3-based) | XOR with S0 only | XOR with S0 only (same) | 8.2.2.5.1 |
| Scrambler (SG4/5-based) | XOR with {S1,S0} pairs | XOR with {S1,S0} pairs (same) | 8.2.2.5.2 |
| TDD cycle duration | 6844 PTB tics (single value) | Per-mode: 628-6708 PTB tics | Table 8-4 |
| Physical layer blocks/burst | 10-72 (Dn SG1-5), 1-2 (Up) | 2-162 (Dn), 1-2 (Up), per mode | Table 8-2 |
| Quiet gap | Per SG (Table 4-4) | Per mode (Table 8-3) | Table 8-3 |
| Resync header | Per SG (Table 4-5) | Maps to ML SG (Table 8-1) | 8.2.2.3.1 |
| Phase1G info field | 40-bit: SGcapability + SGconfig | 40-bit: MLEcapability + MLEconfig | Table 8-6 |
| OAM transport | Direct in container bytes | 4b/5b encoded, fragmented | 8.6.2 |
| OAM integrity | RS-FEC (implicit) | CRC8 (explicit) | 8.6.2.4 |
| xMII interface | None (DLL container) | MII/GMII/XGMII | 8.6.1 |
| PAM mapping | PAM2 (SG1/2/3), PAM4 (SG4/5) | PAM2 (SG1/2/3-based), PAM4 (SG4/5-based) | 8.2.2.6, 8.2.2.7 |
| Startup scrambler | 8.2.2.5.1 for all MLE startup phases | 8.2.2.5.1 (PAM2 always in startup) | 8.2.7.2 |
| Link Aggregation | Optional (Section 4.8) | Does not apply (Section 8.8) | 8.8 |

---

## 4. MLE Speed Modes

### 4.1 Mode Table (Table 8-1, PDF p284)

SPEC FACT (Section 8.1.1, PDF p284): MLE supports the following combinations of data
rates at the xMII by changing parameters of the PCS, while reusing PMA parameters of
the given ASA Speed Grades.

```
+---------------+---------------+------------------+------------------+-----------+
| Type          | Short Name    | Data Rate Dn     | Data Rate Up     | PMA SG    |
+---------------+---------------+------------------+------------------+-----------+
| Symmetrical   | MLES_sym1G0   | 1 Gbps           | 1 Gbps           | SG2       |
| Symmetrical   | MLES_sym2G5   | 2.5 Gbps         | 2.5 Gbps         | SG3       |
| Symmetrical   | MLES_sym5G0   | 5 Gbps           | 5 Gbps           | SG5       |
| Asymmetrical  | MLES_2G5_M    | 2.5 Gbps         | 100 Mbps         | SG2       |
| Asymmetrical  | MLES_5G0_M    | 5 Gbps           | 100 Mbps         | SG3       |
| Asymmetrical  | MLES_10G_M    | 10 Gbps          | 100 Mbps         | SG4       |
| Asymmetrical  | MLES_10G_G    | 10 Gbps          | 1 Gbps           | SG5       |
+---------------+---------------+------------------+------------------+-----------+
```

Key note: The PMA (baud rate, analog circuits) is identical to the corresponding ML
Speed Grade. All MLE differences are in the PCS and the xMII adaptation layer.

### 4.2 Speed Grade Inheritance for PCS Parameters

SPEC FACT (Section 8.2.2.3.1, PDF p288): "Each MLE physical layer data rate mode uses
the Resynchronization Header of the respective Motion Link Speed Grade, of which it is
derived from. See Table 8-1 for the mapping."

This means:
- MLES_sym1G0, MLES_2G5_M  -> use SG2 resync header (resylen=768, SG2 PRBS11 rules)
- MLES_sym2G5, MLES_5G0_M  -> use SG3 resync header (resylen=1536)
- MLES_sym5G0, MLES_10G_G  -> use SG5 resync header (resylen=1536)
- MLES_10G_M               -> use SG4 resync header (resylen=1152)

For resync header structure, equations, and PRBS11/PRBS9 details, see
micro-architecture-phy-pcs-datapath.md Section 6.

---

## 5. TDD Burst Timing

### 5.1 TDD Cycle Duration per Mode (Table 8-4, PDF p288)

SPEC FACT (Section 8.2.2.2.1, PDF p288): "The PCS in the root node (i.e. clock leader)
and any link-local clock leader therefore starts a new TDD cycle on a fixed value period
of PTB tics (with a tolerance of +/-1)."

```
+---------------+---------------+--------------------+
| Type          | Short Name    | TDD cycle [PTB tics]|
+---------------+---------------+--------------------+
| Symmetrical   | MLES_sym1G0   | 628                 |
| Symmetrical   | MLES_sym2G5   | 628                 |
| Symmetrical   | MLES_sym5G0   | 568                 |
| Asymmetrical  | MLES_2G5_M    | 988                 |
| Asymmetrical  | MLES_5G0_M    | 748                 |
| Asymmetrical  | MLES_10G_M    | 6708                |
| Asymmetrical  | MLES_10G_G    | 748                 |
+---------------+---------------+--------------------+
```

SPEC FACT: Compare with Gen2020: 6844 PTB tics for all speed grades.
MLE TDD cycles are substantially shorter for most modes because MLE packs more data
per physical layer block (larger Ethernet frames) while using fewer blocks per burst.

### 5.2 Physical Layer Blocks per Burst (Table 8-2, PDF p287)

SPEC FACT (Section 8.2.2.2, PDF p287):

```
+---------------+---------------+--------------------+--------------------+
| Type          | Short Name    | PLB Downstream     | PLB Upstream       |
+---------------+---------------+--------------------+--------------------+
| Symmetrical   | MLES_sym1G0   | 2                  | 2                  |
| Symmetrical   | MLES_sym2G5   | 4                  | 4                  |
| Symmetrical   | MLES_sym5G0   | 7                  | 7                  |
| Asymmetrical  | MLES_2G5_M    | 6                  | 1                  |
| Asymmetrical  | MLES_5G0_M    | 9                  | 1                  |
| Asymmetrical  | MLES_10G_M    | 162                | 2                  |
| Asymmetrical  | MLES_10G_G    | 18                 | 2                  |
+---------------+---------------+--------------------+--------------------+
```

Note: Downstream is the direction from the root (clock leader) to the leaf.
Upstream is the direction from the leaf to the root.

### 5.3 Quiet Gap (Table 8-3, PDF p288)

SPEC FACT (Section 8.2.2.2, PDF p287-288): Every TDD data burst is followed by a quiet
gap of baud rate symbols:

```
+---------------+---------------+------------------+------------------+
| Type          | Short Name    | Quiet Gap Dn     | Quiet Gap Up     |
+---------------+---------------+------------------+------------------+
| Symmetrical   | MLES_sym1G0   | 5440             | 5440             |
| Symmetrical   | MLES_sym2G5   | 10880            | 10880            |
| Symmetrical   | MLES_sym5G0   | 9920             | 9920             |
| Asymmetrical  | MLES_2G5_M    | 3520             | 13120            |
| Asymmetrical  | MLES_5G0_M    | 5120             | 20480            |
| Asymmetrical  | MLES_10G_M    | 4320             | 157920           |
| Asymmetrical  | MLES_10G_G    | 5120             | 20480            |
+---------------+---------------+------------------+------------------+
```

All quiet gap values are in baud-rate symbols at the respective PMA speed grade.

### 5.4 TDD Burst Structure

SPEC FACT (Section 8.2.2.2, PDF p287): "A TDD data burst is a concatenation of a single
resynchronization header as defined in 4.2.2.3 and a sequence of physical layer blocks
as defined in 8.2.2.4. The first bit being sent of the resynchronization header is its
LSB, the first bit being sent of the physical layer block is its MSB."

```
+---+-------------------------------+---+-------------------------------+---+
|QG | Resync Hdr | PLB[0] ... PLB[N] |QG | Resync Hdr | PLB[0] ... PLB[M] |QG |
|   | (LSB first)| (MSB first each)  |   | (LSB first)| (MSB first each)  |   |
+---+-------------------------------+---+-------------------------------+---+
    |<------- Downstream Burst ----->|   |<------- Upstream Burst ------->|
    |<------------------------------ TDD Cycle ------------------------------>|
```

N = downstream PLB count per mode (Table 8-2)
M = upstream PLB count per mode (Table 8-2)

---

## 6. MLE Physical Layer Block (tx_phy_blockE)

### 6.1 Block Size and FEC

SPEC FACT (Section 8.2.2.4, PDF p289): "All MLE data rates modes use the same physical
layer block tx_phy_blockE<1919:0>, which is equivalent to 214 bytes payload and 26 bytes
parity of the encoder given in 8.2.4."

SPEC FACT (Section 8.2.4, PDF p290): "The MLE physical layer uses the RS Encoder from
section 4.2.4.3." This is the RS(240,214) encoder.

This means:
- ALL MLE modes (symmetric and asymmetric) use RS(240,214)
- Block size: 240 bytes = 1920 bits -> tx_phy_blockE<1919:0>
- Payload: 214 bytes (m[213:0])
- Parity: 26 bytes (p[25:0])
- FEC capability: t=13 (can correct up to 13 symbol errors)

SPEC FACT (Section 8.2.3.3, PDF p290): "For Speed Grade 3/4/5 based MLE Modes, bit
error correction is mandatory. For Speed Grade 1/2 based MLE Modes, bit error correction
is optional."

### 6.2 Payload Mapping (Table 8-5, PDF p289)

SPEC FACT: The 214 message bytes of tx_phy_blockE are mapped as follows:

```
tx_phy_blockE bit[1919] = m_213,7 = Format indicator (1: secondary control channel
                                    present; 0: no secondary control channel)
tx_phy_blockE bit[1918] = m_213,6 = Reserved, set to 0
tx_phy_blockE bits[1917:1908] = m_213,5..m_212,4 = Secondary control channel <0:9>
                                                    (or 0 if not present)
tx_phy_blockE bits[1907:1898] = m_212,3..m_211,2 = OAM_fragment<0:9>
tx_phy_blockE bits[1897:1833] = m_211,1..m_203,1 = xMII_block_k<0:64>
...
tx_phy_blockE bits[337:273]   = m_23,1..m_15,1   = xMII_block_{k+24}<0:64>
tx_phy_blockE bits[272:208]   = m_15,0..m_7,0    = xMII_block_{k+25}<0:64>
```

Notes on payload structure:
- Bit[1919]: Format indicator -- secondary control channel presence flag
- Bit[1918]: Reserved
- Bits[1917:1908]: Secondary control channel (10 bits), zero if not present
- Bits[1907:1898]: OAM fragment (10 bits = two 4b/5b-encoded nibbles)
- Bits[1897:208]: 26 xMII_blocks, each 65 bits wide (1 sync + 64 data bits)

SPEC FACT (Section 8.2.2.4, PDF p289): "Each physical layer block is transmitted with
MSB first; i.e. tx_phy_blockE<1919>."

IMPLEMENTATION ASSUMPTION: Each xMII_block<0:64> is the 64b/65b encoded block from
the 64b/65b mapping layer (Table 8-13). Bit[0] is the sync bit (0=data, 1=control).
Bits[1:64] carry 8 data bytes for data blocks or control type + codes for control blocks.

### 6.3 FEC Codeword Format

SPEC FACT: The FEC codeword c(x) for the single RS(240,214) codeword has the format:
(m_213,7, m_213,6, ..., m_0,0, p_25,7, ..., p_0,0)

This matches the RS(240,214) encoder defined in Section 4.2.4.3. For the RS encoder
polynomial, generator polynomial coefficients, and GF(2^8) definition, see
micro-architecture-phy-pcs-datapath.md Section 9.4.

---

## 7. MLE TX Datapath Flow

### 7.1 MLE Normal Mode TX Data Flow (Figure 8-2, PDF p286)

SPEC FACT (Figure 8-2 description, Section 8.2.2.1, PDF p285-286): The MLE PCS
transmit process creates ASA MLE physical layer blocks out of data obtained from xMII.

```
xMII (XGMII/GMII/MII)
         |
         v
+---------------------------+    +------------------+
| xMII Adaptation Layer     |    | OAM frame        |
| (Rate Matching +          |    | fragment         |
|  64b/65b encoding)        |    | (4b/5b encoded)  |
+------------+--------------+    +--------+---------+
             | xMII_block[k] (65b)         |
             | (up to 65 blocks per PLB)   | OAM_fragment<0:9>
             v                             |
+--------------------------------------------+
| Physical_layer_block assembly              |
| (tx_phy_blockE<1919:0>)                    |
| - Format indicator + reserved              |
| - Optional secondary ctrl channel          |
| - OAM fragment (10 bits)                   |
| - 65 x xMII_blocks (65b each)              |
|                                            |
| RS(240,214) FEC encoding                   |
| -> append 26 parity bytes                  |
+------------------+-------------------------+
                   | tx_phy_blockE<1919:0>
                   v
        +---------------------+    PTB Clock Leader/Follower FSM
        | Resynchronization   |         |
        | Header              |<--------+ m_ptb
        | (per ML SG, 4.2.2.3)|
        +----------+----------+
                   | tx_phy_rsync_hdr (width=1, LSB first)
                   v
        +---------------------+
        | Downstream          |
        | Scrambler           |
        | S_Dn[22:0]          |
        | (x^23+x^5+1)        |
        +----------+----------+
                   | S0 (SG1/2/3-based) or {S1,S0} (SG4/5-based)
                   v
        +---------------------+
        | PCS Scrambler (XOR) |
        +----------+----------+
                   | tx_phy_blockE_scr (M bits)
                   v
        +----------------------------------------+
        | [tx_phy_rsync_hdr | tx_phy_blockE_scr] |
        |          concatenated                   |
        +------------------+---------------------+
                           |
                           v
                 +------------------+
                 | PAM2/PAM4 Mapping|
                 | (per ML SG)      |
                 +--------+---------+
                          |
                          v
                 +------------------+
                 | Transmit/Disable |
                 +------------------+
                          |
                          v
                    To PMA (MDI)
```

### 7.2 MLE TX Step-by-Step

1. xMII adaptation layer receives 64b/66b blocks from host MAC
2. Rate matching inserts Skip||R|| control blocks as needed (Table 8-12)
3. 64b/66b blocks are converted to 64b/65b format (Table 8-13)
4. 26 xMII_blocks packed into tx_phy_blockE message field (bits[1897:208])
5. OAM fragment (10 bits = two 4b/5b nibbles) inserted at bits[1907:1898]
6. Format indicator and optional secondary control channel fill bits[1919:1908]
7. RS(240,214) FEC parity (26 bytes) appended -> tx_phy_blockE<1919:0> complete
8. Block scrambled with downstream LFSR (S0 for SG1/2/3-based; {S1,S0} for SG4/5-based)
9. Resync header (per ML SG) prepended (LSB first)
10. Concatenated stream mapped to PAM2 (SG1/2/3-based) or PAM4 (SG4/5-based) symbols
11. Quiet gap inserted after all PLBs in burst

---

## 8. MLE PCS Scrambler

### 8.1 Scrambler Selection by MLE Mode

SPEC FACT (Sections 8.2.2.5.1 and 8.2.2.5.2, PDF p289-290):

The scrambler polynomial and application method depend on which ML Speed Grade the
MLE mode is derived from (Table 8-1). The downstream scrambler polynomials are
IDENTICAL to Gen2020:
- Downstream: g_Dn(x) = x^23 + x^5 + 1, LFSR S_Dn[22:0]

The key difference from Gen2020 is the scrambler APPLICATION per mode:

SPEC FACT (Section 8.2.2.5.1): "MLE Modes based on Speed Grade 1/2/3":
The scrambler output S_0 is applied as an additive scrambler sequence to
tx_phy_blockE, advancing by one shift for every one bit in tx_phy_blockE, such that:
  tx_phy_blockE_scr<MSB> = tx_phy_blockE<MSB> XOR S_0

SPEC FACT (Section 8.2.2.5.2): "MLE Modes based on Speed Grade 4 and 5":
The scrambler outputs S_0 and S_1 are applied as an additive scrambler sequence to
tx_phy_blockE, advancing by one shift for every two bits in tx_phy_blockE, such that:
  tx_phy_blockE_scr<MSB>   = tx_phy_blockE<MSB>   XOR S_1
  tx_phy_blockE_scr<MSB-1> = tx_phy_blockE<MSB-1> XOR S_0
and every following tuple {S_1, S_0} is applied to every following
tx_phy_blockE<n:n-1>.

### 8.2 Scrambler Application by MLE Mode

```
+---------------+----------+-----------+----------------------------+
| MLE Mode      | PMA SG   | Scrambler | Application                |
+---------------+----------+-----------+----------------------------+
| MLES_sym1G0   | SG2      | SG1/2/3   | S0 only, 1 shift per bit   |
| MLES_sym2G5   | SG3      | SG1/2/3   | S0 only, 1 shift per bit   |
| MLES_sym5G0   | SG5      | SG4/5     | {S1,S0} pair, 1 shift/2b   |
| MLES_2G5_M    | SG2      | SG1/2/3   | S0 only, 1 shift per bit   |
| MLES_5G0_M    | SG3      | SG1/2/3   | S0 only, 1 shift per bit   |
| MLES_10G_M    | SG4      | SG4/5     | {S1,S0} pair, 1 shift/2b   |
| MLES_10G_G    | SG5      | SG4/5     | {S1,S0} pair, 1 shift/2b   |
+---------------+----------+-----------+----------------------------+
```

SPEC FACT: S_1 = S_Dn[2] XOR S_Dn[5] (from Section 4.2.5, Figure 4-12 -- identical
to Gen2020 SG4/5 scrambler, see micro-architecture-phy-pcs-datapath.md Section 10.2).

SPEC FACT (Section 8.2.7.2, PDF p293): During ALL MLE startup phases (PhaseSGA, SGB,
SGC), the PCS scrambler is run as described in 8.2.2.5.1 (i.e. S0-only mode) for all
MLE modes, regardless of the normal-mode scrambler selection. Scrambled symbols are
mapped to PAM2 as in normal mode (4.2.2.6) for startup phases.

Note for SG4/5-based modes in PhaseSGC: the last physical layer block symbols and
Equation 8-1 symbols are mapped to PAM4 as in normal mode (4.2.2.7).

---

## 9. MLE RS-FEC

### 9.1 Encoder: RS(240,214) for ALL Modes

SPEC FACT (Section 8.2.4, PDF p290): "The MLE physical layer uses the RS Encoder from
section 4.2.4.3." -- This is RS(240,214) universally for all MLE modes.

This is a significant difference from Gen2020, which used three different encoders
depending on speed grade and direction.

```
+-------------------+----------------------------------+
| Encoder           | RS(240,214)                      |
| Field             | GF(2^8)                          |
| Primitive poly    | x^8 + x^4 + x^3 + x^2 + 1       |
| k (message syms)  | 214 bytes                        |
| n (codeword syms) | 240 bytes                        |
| 2t (parity syms)  | 26 bytes                         |
| t (error correct) | 13 symbols                       |
| Codewords/PLB     | 1                                |
| Generator g(x)    | product_{i=0}^{25}(x - a^i)      |
+-------------------+----------------------------------+
```

For the RS(240,214) generator polynomial coefficients (g0 through g26), see
micro-architecture-phy-pcs-datapath.md Section 9.4.

### 9.2 FEC Decode Requirements

SPEC FACT (Section 8.2.3.3, PDF p290):
- Speed Grade 1/2-based modes (MLES_sym1G0, MLES_sym2G5, MLES_2G5_M, MLES_5G0_M):
  bit error correction is OPTIONAL (integrity check mandatory)
- Speed Grade 3/4/5-based modes (MLES_sym5G0, MLES_10G_M, MLES_10G_G):
  bit error correction is MANDATORY
- If correction cannot be done, the RS-FEC frame is invalid

SPEC FACT: "Statistics shall be kept in the registers described in 3.2.16 and 3.2.13."
(These are FECstat 1.0104 and LinkQuality 1.0101, same registers as Gen2020.)

---

## 10. MLE Phase1G Info Field (Table 8-6, PDF p292)

### 10.1 Overview

SPEC FACT (Section 8.2.7.1.2, PDF p291): "The info field for Phase1G inf_1G<39:0> is
32bits + 8bits long and defined as follows:"

The MLE Phase1G info field has the same 40-bit size as the Gen2020 Phase1G info field,
but the internal fields differ: instead of SGcapability and SGconfig, it carries
MLEcapability and MLEconfig.

### 10.2 MLE Phase1G Info Field Bit Definition (Table 8-6)

```
Bits  Name              Description
---------------------------------------------------------------------------
39:32 ParityByte        inf_1G[32+k] = inf_1G[k] XOR inf_1G[8+k] XOR
                        inf_1G[16+k] XOR inf_1G[24+k]  for k=0..7

31:30 Phase1Gstatus     00=TRAINING, 01=PREPARED, 10=PROCEED, 11=ERROR

29:27 MLE capability    Bits <29:27> correspond to bits [15:13] of register 3.2.9
                        (MLEcapability1: MLES_sym1G0, MLES_sym2G5, MLES_sym5G0)

26:25 (reserved)        Bits <26:25> are reserved, set to 0

24:19 MLE capability    Bits <24:19> correspond to bits [15:10] of register 3.2.10
                        (MLEcapability2: asymmetric modes capability bits)

18:16 (reserved)        Bits <18:16> are reserved, set to 0

15:11 MLE config        Info field created by root node or link-local root (far-side):
                        Bits <15:11> are to be written to bits [15:11] of register
                        3.2.11 (MLEconfig), only accepted by non-root node.
                        If '11111' is received, nothing is written.
                        Info field created by non-root / near-side node:
                        contains bits [15:11] of register 3.2.11 (info only)

10:8  TXtest            Transmitter test request (see 4.4.1.1):
                        000: no test
                        001: linearity test
                        010: jitter test
                        011: droop test
                        100: PSD test
                        101: BER test

7:1   Reserved          Set to 0

0     Physical Layer    0: ASA Motion Link (SerDes)
      Mode              1: ASA Motion Link Ethernet (MLE)
```

### 10.3 Comparison with Gen2020 Phase1G Info Field

| Bits  | Gen2020 Field      | MLE Field            |
|-------|--------------------|----------------------|
| 39:32 | ParityByte (same)  | ParityByte (same)    |
| 31:30 | Phase1Gstatus (same)| Phase1Gstatus (same)|
| 29:16 | SGcapability[13:0] | MLEcapability (3.2.9/10)|
| 15:11 | SGconfig[4:0]      | MLEconfig[15:11]     |
| 10:8  | TXtest (same)      | TXtest (same)        |
| 7:1   | Reserved (same)    | Reserved (same)      |
| 0     | PhysLayerMode      | PhysLayerMode (same) |

---

## 11. MLE Startup Phases (Sections 8.2.7.2 - 8.2.7.4)

### 11.1 General Rule

SPEC FACT (Section 8.2.7, PDF p291): "MLE reuses the ML startup patterns and state
machines. It only changes the parameters given in this section 8.2.7."

For the full FSM state diagrams and timer/counter details, see
micro-architecture-phy-startup-training-fsm.md.

### 11.2 PhaseSGA MLE Parameters (Section 8.2.7.2)

SPEC FACT (PDF p292-293):

SGA physical layer blocks per burst (Table 8-7):
```
+---------------+---------------+------------------+------------------+
| Type          | Short Name    | PLB Downstream   | PLB Upstream     |
+---------------+---------------+------------------+------------------+
| Symmetrical   | MLES_sym1G0   | 2                | 2                |
| Symmetrical   | MLES_sym2G5   | 4                | 4                |
| Symmetrical   | MLES_sym5G0   | 4                | 3                |
| Asymmetrical  | MLES_2G5_M    | 3                | 4                |
| Asymmetrical  | MLES_5G0_M    | 5                | 5                |
| Asymmetrical  | MLES_10G_M    | 41               | 41               |
| Asymmetrical  | MLES_10G_G    | 5                | 5                |
+---------------+---------------+------------------+------------------+
```

SGA quiet gap baud rate symbols (Table 8-8):
```
+---------------+---------------+------------------+------------------+
| Type          | Short Name    | Quiet Gap Dn     | Quiet Gap Up     |
+---------------+---------------+------------------+------------------+
| Symmetrical   | MLES_sym1G0   | 5440             | 5440             |
| Symmetrical   | MLES_sym2G5   | 10880            | 10880            |
| Symmetrical   | MLES_sym5G0   | 8960             | 10880            |
| Asymmetrical  | MLES_2G5_M    | 9280             | 7360             |
| Asymmetrical  | MLES_5G0_M    | 12800            | 12800            |
| Asymmetrical  | MLES_10G_M    | 81120            | 81120            |
| Asymmetrical  | MLES_10G_G    | 12800            | 12800            |
+---------------+---------------+------------------+------------------+
```

SPEC FACT (Section 8.2.7.2, PDF p292): "The first bit being sent of the resync header
is its LSB. The first bit being sent of the physical layer block (except second to last
one) is its MSB. The first bit being sent of the last physical layer block is its LSB."

SPEC FACT (Section 8.2.7.2): "The second to last physical layer block tx_phy_blockE
for a startup PhaseSGA burst, where inf_SG is the info field defined in 4.2.7.5, is
defined as (Equation 8-1):

  tx_blockE_SGA<n> =
    0                      for  0 <= n <= 255
    inf_SG[n mod 255]      for  256 <= n <= 767
    0                      for  768 <= n <= 1023
    inf_SG[n mod 1023]     for  1024 <= n <= 1535
    0                      for  1536 <= n <= 1919"

SPEC FACT: "The PCS Scrambler is being run as described in 8.2.2.5.1 for all MLE modes."
(S0-only scrambler for all startup phases.)

SPEC FACT: "Scrambled symbols are mapped to PAM2 as in normal mode (4.2.2.6)."

### 11.3 PhaseSGB MLE Parameters (Section 8.2.7.3)

SGB physical layer blocks per burst (Table 8-9):
```
+---------------+---------------+------------------+------------------+
| Type          | Short Name    | PLB Downstream   | PLB Upstream     |
+---------------+---------------+------------------+------------------+
| Symmetrical   | MLES_sym1G0   | 2                | 2                |
| Symmetrical   | MLES_sym2G5   | 4                | 4                |
| Symmetrical   | MLES_sym5G0   | 4                | 3                |
| Asymmetrical  | MLES_2G5_M    | 6                | 1                |
| Asymmetrical  | MLES_5G0_M    | 9                | 1                |
| Asymmetrical  | MLES_10G_M    | 81               | 1                |
| Asymmetrical  | MLES_10G_G    | 9                | 1                |
+---------------+---------------+------------------+------------------+
```

SGB quiet gap baud rate symbols (Table 8-10):
```
+---------------+---------------+------------------+------------------+
| Type          | Short Name    | Quiet Gap Dn     | Quiet Gap Up     |
+---------------+---------------+------------------+------------------+
| Symmetrical   | MLES_sym1G0   | 5440             | 5440             |
| Symmetrical   | MLES_sym2G5   | 10880            | 10880            |
| Symmetrical   | MLES_sym5G0   | 8960             | 10880            |
| Asymmetrical  | MLES_2G5_M    | 3520             | 13120            |
| Asymmetrical  | MLES_5G0_M    | 5120             | 20480            |
| Asymmetrical  | MLES_10G_M    | 4320             | 157920           |
| Asymmetrical  | MLES_10G_G    | 5120             | 20480            |
+---------------+---------------+------------------+------------------+
```

SPEC FACT: "The last physical layer block is identical to PhaseSGA as defined in
Equation 8-1." (Same inf_SG embedding pattern.)

SPEC FACT: "The PCS Scrambler is being run as described in 8.2.2.5.1 for all MLE modes."

SPEC FACT: "For all Speed Grades, scrambled symbols are mapped to PAM2 as in normal
mode (4.2.2.6)." (PAM4 is NOT used in PhaseSGB even for SG4/5-based modes.)

### 11.4 PhaseSGC MLE Parameters (Section 8.2.7.4)

SPEC FACT (PDF p294-295): PhaseSGC burst is constructed like normal-mode TDD with one
difference: all input data is equal to zero except for the last physical layer block.

SPEC FACT: "The number of symbols in the quiet gap is the same as in normal mode
(see Table 8-3)." (Normal-mode quiet gaps apply.)

SPEC FACT: "The last physical layer block is identical to PhaseSGA as defined in
Equation 8-1." (Same inf_SG embedding pattern.)

SPEC FACT: "The PCS Scrambler is being run as described in 8.2.2.5.1 for all MLE modes."

SPEC FACT (Section 8.2.7.4, PDF p295): "For MLE modes derived from Speed Grades 4 and
5, scrambled physical layer block symbols and symbols of Equation 8-1 are mapped to
PAM4 as in normal mode (4.2.2.7), scrambled symbols of all MLE modes derived from
Speed Grades 1, 2 and 3 are mapped to PAM2 as in normal mode (4.2.2.6)."

SPEC FACT (Section 8.2.7.5, PDF p295): PhaseSGA/SGB/SGC info field: "See equivalent
subsection in section 4. Also see section 8.1.2." (512-bit info field with CRC32
is identical to Gen2020, see micro-architecture-phy-startup-training-fsm.md Section 5.)

---

## 12. MLE Registers

### 12.1 MLEcapability1 (Register 1.0020)

SPEC FACT (Section 3.2.9, Register 1.0020): Access type RO O RID.

```
Bit   Name                    Description
----------------------------------------------------------------------
15    MLES_sym1G0_cap         1: capable of MLES_sym1G0 (1G symmetric)
14    MLES_sym2G5_cap         1: capable of MLES_sym2G5 (2.5G symmetric)
13    MLES_sym5G0_cap         1: capable of MLES_sym5G0 (5G symmetric)
12:0  Reserved                Set to 0
```

SPEC FACT (Table 8-6, MLE Phase1G info field): Bits <29:27> of the Phase1G info field
correspond to bits [15:13] of register 3.2.9 (this register).

### 12.2 MLEcapability2 (Register 1.0021)

SPEC FACT (Section 3.2.10, Register 1.0021): Access type RO O RID.
Contains capability bits for asymmetric MLE modes.

```
Bit   Name                    Description
----------------------------------------------------------------------
15    MLES_2G5_M_cap          1: capable of MLES_2G5_M (2.5G/100M asymm)
14    MLES_5G0_M_cap          1: capable of MLES_5G0_M (5G/100M asymm)
13    MLES_10G_M_cap          1: capable of MLES_10G_M (10G/100M asymm)
12    MLES_10G_G_cap          1: capable of MLES_10G_G (10G/1G asymm)
11:0  Reserved                Set to 0
```

NOTE: Exact bit layout per Section 3.2.10 / Table 3-13. Table 8-6 of the spec
confirms: "Bits <24:19> correspond to bits [15:10] of register 3.2.10."
Bit[24] of info field = bit[15] of 1.0021; bit[19] of info field = bit[10] of 1.0021.
Bits [9:0] of 1.0021 are reserved.

### 12.3 MLEconfig (Register 1.0022)

SPEC FACT (Section 3.2.11, Register 1.0022): Access type RW O RID.

```
Bit    Name             Description
----------------------------------------------------------------------
15     MLE_asym_dir     1: DnTX/UpRX direction
                        0: DnRX/UpTX direction
                        Not applicable for symmetric modes
14:11  MLE_mode         Active MLE mode selection:
                          0000: MLES_sym1G0
                          0001: MLES_sym2G5
                          0010: MLES_sym5G0
                          0011: reserved
                          0100: reserved
                          0101: MLES_2G5_M
                          0110: MLES_5G0_M
                          0111: MLES_10G_M
                          1000: MLES_10G_G
                          1001-1110: reserved
                          1111: do not use (startup info compatibility)
10:0   Reserved         Set to 0
```

SPEC FACT: Bits [15:11] of MLEconfig are exchanged during Phase1G startup (Table 8-6,
bits <15:11> of inf_1G). The root node (far side) writes its desired MLEconfig[15:11]
into the leaf's MLEconfig register through the startup info field exchange.

---

## 13. OAM Fragmentation and 4b/5b Encoding (Section 8.6.2)

### 13.1 OAM Frame Structure in MLE

SPEC FACT (Section 8.6.2, PDF p300): "MLE uses the OAM frame of section 5.5 with the
addition of one byte for integrity checksum."

SPEC FACT (Figure 8-9, PDF p300): MLE OAM frame encoded structure:

```
+------+-----+-----------+--------+-----+--------+-----+------+
| IDLE | SOP | OAM header| CAD #1 | ... | CAD #n | CRC | EOP  | IDLE |
+------+-----+-----------+--------+-----+--------+-----+------+
```

Each element is a 4b/5b-encoded character or pair of characters (10 bits per physical
layer block OAM slot).

### 13.2 OAM Fragmentation (Section 8.6.2.1)

SPEC FACT (Section 8.6.2.1, PDF p300): Each physical layer block takes 10 bits of
encoded fragmented OAM data, or two 4b/5b characters.

SPEC FACT: "Before the first byte of the OAM frame, one group of two control characters
JJ and then (in the next physical layer block) one group of two control characters JK
are transmitted to mark SOP (start of packet)."
-> SOP = JJ (in one PLB), then JK (in the following PLB)

SPEC FACT: "Each byte of OAM frame data is 4b/5b encoded."
-> Each data byte expands to two 4b/5b nibbles = 10 bits = one PLB OAM slot

SPEC FACT: "Each byte of the section 5.5 OAM frame is fed (in ascending byte order)
into the CRC8 checksum calculator (see section 8.6.2.4). The resulting 8 bits of the
checksum are also 4b/5b encoded. There CRC8 resets for every OAM frame."

SPEC FACT: "After the last byte of the OAM frame, one group of TI is transmitted to
mark EOP (end of packet)."
-> EOP = TI character pair

SPEC FACT: "Outside of SOP, OAM frame data and EOP, a group of II is transmitted per
physical layer block to mark IDLE."
-> IDLE = II character pair

### 13.3 OAM 4b/5b Encoding Summary

```
+----------+---------------------+------------------------------+
| Function | Characters          | 4b/5b codes                  |
+----------+---------------------+------------------------------+
| SOP      | JJ (PLB n)          | J=11000, J=11000             |
|          | JK (PLB n+1)        | J=11000, K=10001             |
| Data     | lo_nibble hi_nibble | See Table 8-14 below         |
| EOP      | TI                  | T=01101, I=11111             |
| IDLE     | II                  | I=11111, I=11111             |
| CRC      | lo_nibble hi_nibble | Same 4b/5b encoding as data  |
+----------+---------------------+------------------------------+
```

### 13.4 4b/5b Data Encoding Table (Table 8-14, PDF p301)

SPEC FACT: 4b to 5b mapping for data nibbles:

```
Data[3:0]  5b code    Data[3:0]  5b code
-----------            -----------
0000       11110       1000       10010
0001       01001       1001       10011
0010       10100       1010       10110
0011       10101       1011       10111
0100       01010       1100       11010
0101       01011       1101       11011
0110       01110       1110       11100
0111       01111       1111       11101
```

### 13.5 4b/5b Control Characters (Table 8-15, PDF p301)

SPEC FACT:

```
Symbol  5b code  Description
-------------------------------
H       00100    Halt
I       11111    Idle
J       11000    Start #1
K       10001    Start #2
L       00110    Start #3
Q       00000    Quiet
R       00111    Reset
S       11001    Set
T       01101    Terminate (End)
```

### 13.6 OAM Byte Encoding Process

SPEC FACT: Each OAM frame byte (8 bits) is encoded as two 4b/5b symbols (10 bits total).
The lower nibble (bits[3:0]) is encoded first, followed by the upper nibble (bits[7:4]).
This results in 10 bits per OAM byte in the physical layer block OAM slot.

IMPLEMENTATION ASSUMPTION: The encoding order (lo nibble first vs hi nibble first)
follows standard 4b/5b conventions used in FDDI/Fast Ethernet, where the lower nibble
of a byte is transmitted first. Verify against Section 8.6.2.3 in the spec.

### 13.7 PTB Timestamp Capture (Section 8.6.2.2)

SPEC FACT (Section 8.6.2.2, PDF p300): "The PTB time stamp in the header of the OAM
frame is taken, when the group of two control characters JK of the SOP passes the
transmitting MDI."

This means the PTB clock value is latched at the moment the second of the two SOP
physical layer blocks (the JK block) is transmitted at the MDI (not when it enters
the encoder). The captured PTB value is then written into the OAM frame header's
PTBclk field.

On receive (Section 8.7.2.1): "The receiver marks the time when the group of two
control characters JK of the SOP passed the receiving MDI. If the OAM message will
be used to initialize the PTB, the delta between the received time and the time the
message was processed will be added to the timestamp prior to initializing the PTB."

### 13.8 CRC8 Definition (Section 8.6.2.4)

SPEC FACT (Section 8.6.2.4, PDF p301):
- Polynomial: 0xA6 (i.e. x^8 + x^5 + x^2 + x + 1 in binary 10100110)

  NOTE: The spec states "the polynomial 0xA6". In CRC convention, 0xA6 represents
  the non-leading coefficients: x^7 + x^5 + x^2 + x = bits 7,5,2,1. As a standard
  CRC-8 polynomial the full representation must be verified from the spec binary
  definition.

- Starting value: 0xFF
- XOR appendix (output): 0xFF
- Input data: byte-wise reflected
- Result data: reflected

SPEC FACT: "There CRC8 resets for every OAM frame." (The starting value 0xFF is
reloaded at the beginning of every new OAM frame.)

SPEC FACT: The CRC8 is computed over all bytes of the section 5.5 OAM frame
(in ascending byte order), then the 8-bit CRC result is 4b/5b encoded and appended
after the last OAM byte, before the EOP character.

---

## 14. xMII Transmit Interface Adaptation Layer (Section 8.6 Overview)

### 14.1 xMII Support

SPEC FACT (Section 8.6.1, PDF p296): "MLE supports data rates, which fall into the
speed range of MII, GMII and XGMII."

SPEC FACT: "The data received on XGMII, GMII or MII shall be grouped for 64bit block
format according to 'IEEE 802.3 Standard for Ethernet, Clause 49'."

SPEC FACT (Table 8-11, PDF p296): Mapping of MII and GMII signals to XGMII signals:
```
XGMII signal  GMII mapping              MII mapping
---------------------------------------------------------------------------
TXD<31:0>     TXD_13<7:0>, TXD_12<7:0>, TXD_11<7:0>, TXD_10<7:0>
              (four GMII lanes)
              TXD_17<3:0>, TXD_16<3:0>, ..., TXD_10<3:0>
              (eight MII lanes)
RXD<31:0>     RXD_13<7:0>, RXD_12<7:0>, RXD_11<7:0>, RXD_10<7:0>
              RXD_17<3:0>, RXD_16<3:0>, ..., RXD_10<3:0>
```

### 14.2 Rate Matching

SPEC FACT (Section 8.6.1.1, PDF p299): "When no data is available from the xMII, the
Adaptation Layer shall generate data for Rate Matching."

SPEC FACT: "The Rate Matching shall insert control blocks of Block Type 0x1e with all
control codes set to 'Skip||R||' 0x1C. These rate matching control blocks may be
inserted between or during ETH packet transmission, and will be removed by the receiver."

SPEC FACT (Table 8-12, PDF p299): Rate matching insertion guidance (average):
```
+---------------+---------------+-------------------+-------------------+
| Type          | Short Name    | Every N PLB (Dn)  | Insert Skip (Dn)  |
+---------------+---------------+-------------------+-------------------+
| Symmetrical   | MLES_sym1G0   | 208               | 51                |
| Symmetrical   | MLES_sym2G5   | 832               | 47                |
| Symmetrical   | MLES_sym5G0   | 364               | 9                 |
| Asymmetrical  | MLES_2G5_M    | 96                | 1                 |
| Asymmetrical  | MLES_5G0_M    | 936               | 1                 |
| Asymmetrical  | MLES_10G_M    | 1944              | 9                 |
| Asymmetrical  | MLES_10G_G    | 936               | 1                 |
+---------------+---------------+-------------------+-------------------+
```
(Upstream figures similarly in Table 8-12; omitted here for brevity.)

### 14.3 64b/65b Mapping (Table 8-13, PDF p299-300)

SPEC FACT (Section 8.6.1.2, PDF p299): The 64b/66b IEEE 802.3 block format is mapped
to xMII_block[0:64] (65 bits) for the MLE physical layer block.

```
+-------------+------+-------+--------+--------+--------+--------+--------+--------+--------+
| xMII_block  | [0]  | [1:8] | [9:16] |[17:24] |[25:32] |[33:40] |[41:48] |[49:56] |[57:64] |
+-------------+------+-------+--------+--------+--------+--------+--------+--------+--------+
| Data Block  | Sync0| D0    | D1     | D2     | D3     | D4     | D5     | D6     | D7     |
|             |      |[0:7]  |[0:7]   |[0:7]   |[0:7]   |[0:7]   |[0:7]   |[0:7]   |[0:7]  |
+-------------+------+-------+--------+--------+--------+--------+--------+--------+--------+
| Ctrl Block  | Sync1| Block | See IEEE 802.3 Figure 49-7                                    |
|             |      | Type  |                                                               |
+-------------+------+-------+--------+--------+--------+--------+--------+--------+--------+
```

Sync bit: 0 = Data block, 1 = Control block.
Each physical layer block carries 65 such xMII_blocks.

Full xMII adaptation internals (rate matching implementation, GMII/MII to XGMII
conversion state machine, 64b/65b encoder/decoder) are documented in:
micro-architecture-mle-xmii-adaptation.md (to be written).

---

## 15. MLE RX Datapath Overview

### 15.1 RX Rate Matching (Section 8.7.1.1)

SPEC FACT (Section 8.7.1.1, PDF p302): "The receiver shall delete all control blocks
of Block Type 0x1e with all control codes set to 'Skip||R||' 0x1C."

### 15.2 RX OAM SOP/EOP Synchronization (Section 8.7.2.1)

SPEC FACT (Section 8.7.2.1, PDF p302): "The receiver shall scan for SOP character to
detect the start of a frame."

SPEC FACT: "The receiver marks the time when the group of two control characters JK of
the SOP passed the receiving MDI. If the OAM message will be used to initialize the PTB,
the delta between the received time and the time the message was processed will be added
to the timestamp prior to initializing the PTB."

### 15.3 RX Reassembly and Integrity Check (Section 8.7.2.2)

SPEC FACT (Section 8.7.2.2, PDF p302): "The 4b/5b decoded OAM frame bytes shall be
checked versus the received integrity checksum and mismatching OAM frames shall be
discarded. The number of OAM frames failing integrity checksum will be counted in
3.3.24."

---

## 16. Interfaces

### 16.1 Interface to xMII Adaptation Layer

SPEC FACT: The MLE PCS presents the same PLP_TX/PLP_RX primitives toward the DLL as
Gen2020 PCS (Section 4.6/4.7). The DLL is unaware of whether the physical layer uses
Gen2020 or MLE.

On the xMII side, the adaptation layer provides:

| Signal | Dir | Description |
|--------|-----|-------------|
| xmii_tx_data[31:0] | xMII->Adapt | XGMII TX data (or GMII/MII equivalent) |
| xmii_tx_ctrl[3:0] | xMII->Adapt | XGMII TX control flags |
| xmii_tx_clk | xMII->Adapt | XGMII TX clock (156.25 or 125 MHz) |
| xmii_rx_data[31:0] | Adapt->xMII | XGMII RX data |
| xmii_rx_ctrl[3:0] | Adapt->xMII | XGMII RX control flags |
| xmii_rx_clk | Adapt->xMII | XGMII RX clock |
| mii_tx_data[3:0] | xMII->Adapt | MII TX nibble (if MII mode) |
| mii_rx_data[3:0] | Adapt->xMII | MII RX nibble |
| gmii_tx_data[7:0] | xMII->Adapt | GMII TX byte (if GMII mode) |
| gmii_rx_data[7:0] | Adapt->xMII | GMII RX byte |

IMPLEMENTATION ASSUMPTION: xMII interface type (MII/GMII/XGMII) is
implementation-dependent. SPEC FACT (Section 8.6.1): "All MLE speed modes can be
supported by XGMII. It is up to the implementer to filter out (and inject) idle periods
on the XGMII to achieve the xMII payload data rate of the MLE speed mode."

### 16.2 Interface to PCS Core (MLE-specific signals)

| Signal | Dir | Description |
|--------|-----|-------------|
| mle_mode[3:0] | Reg->PCS | Active MLE mode from MLEconfig[14:11] |
| mle_asym_dir | Reg->PCS | Direction bit from MLEconfig[15] |
| oam_fragment[9:0] | OAMenc->PCS | Two 4b/5b-encoded nibbles for PLB OAM slot |
| sec_ctrl_ch[9:0] | SecCtrl->PCS | Secondary control channel bits (optional) |
| sec_ctrl_present | SecCtrl->PCS | Format indicator: 1 if secondary ctrl present |
| xmii_block[64:0] | Adapt->PCS | 65-bit 64b/65b encoded block (one per PLB slot) |
| xmii_block_valid | Adapt->PCS | Block available for insertion |
| ptb_jk_tx_event | PCS->PTB | JK SOP character passes TX MDI |
| ptb_jk_rx_event | PCS->PTB | JK SOP character passes RX MDI |

### 16.3 Interface to Gen2020 PCS Shared Logic

IMPLEMENTATION ASSUMPTION: The MLE PCS reuses the following Gen2020 sub-engines
(parameter-configurable):
- Resync header generator (configured per ML SG, see Section 6.2 of Gen2020 doc)
- Downstream scrambler LFSR S_Dn[22:0] with x^23+x^5+1 polynomial
- RS(240,214) FEC encoder (identical to Gen2020 SG3/4/5 encoder)
- PAM2/PAM4 mapper (identical to Gen2020)
- PTB message vector codec (identical to Gen2020)

Signals shared with Gen2020 PCS core:

| Signal | Dir | Description |
|--------|-----|-------------|
| sg_base[2:0] | Reg->PCS | Derived ML SG for resync header selection |
| ptb_m_ptb_tx[15:0] | PTB->PCS | PTB message for resync header |
| ptb_m_ptb_rx[15:0] | PCS->PTB | Extracted PTB message from RX |
| tdd_cycle_tics | PCS->TDD | TDD cycle length in PTB tics (mode-specific) |
| dn_blk_count | PCS->TDD | Downstream PLB count per mode (Table 8-2) |
| up_blk_count | PCS->TDD | Upstream PLB count per mode (Table 8-2) |
| quiet_gap_dn | PCS->TDD | Downstream quiet gap symbol count (Table 8-3) |
| quiet_gap_up | PCS->TDD | Upstream quiet gap symbol count (Table 8-3) |

### 16.4 Interface to Register Model

| Signal | Dir | Description |
|--------|-----|-------------|
| mle_cap1[15:0] | Reg->PCS | MLEcapability1 (1.0020) |
| mle_cap2[15:0] | Reg->PCS | MLEcapability2 (1.0021) |
| mle_config[15:0] | Reg->PCS | MLEconfig (1.0022) |
| fec_stat_update | PCS->Reg | Increment 1.0104 FECstat |
| link_quality_update | PCS->Reg | Increment 1.0101 LinkQuality |
| oam_crc_fail_count | PCS->Reg | Increment OAM CRC8 fail counter (3.3.24) |

---

## 17. Suggested RTL Module Boundaries

```
+==================================================================+
|                        mle_pcs_top                               |
|                                                                   |
|  +---------------------+    +-----------------------------+      |
|  | mle_mode_decoder    |    | mle_tdd_burst_scheduler     |      |
|  |                     |    |                             |      |
|  | Map MLEconfig[14:11]|    | MLE TDD cycle (Table 8-4)  |      |
|  | to PMA SG, resync   |    | PLB counts (Table 8-2)     |      |
|  | header params, QG,  |    | Quiet gap (Table 8-3)      |      |
|  | scrambler mode sel  |    | Startup SGA/SGB/SGC params |      |
|  +---------------------+    +-----------------------------+      |
|                                                                   |
|  +---------------------+    +-----------------------------+      |
|  | mle_plb_assembler   |    | mle_fec_encoder             |      |
|  |                     |    |                             |      |
|  | Pack xMII blocks    |    | RS(240,214) for ALL modes   |      |
|  | Insert OAM fragment |    | 214B payload -> 240B cword  |      |
|  | Insert sec ctrl ch  |    | Reuse Gen2020 RS(240,214)   |      |
|  | Set format indicator|    | engine from pcs_top         |      |
|  | -> tx_phy_blockE    |    +-----------------------------+      |
|  +---------------------+                                         |
|                                                                   |
|  +---------------------+    +-----------------------------+      |
|  | mle_scrambler       |    | mle_oam_4b5b_encoder        |      |
|  |                     |    |                             |      |
|  | S0-only (SG1/2/3)   |    | JJ/JK SOP encoding          |      |
|  | {S1,S0} (SG4/5)     |    | Byte -> two 5b symbols     |      |
|  | Startup always S0   |    | TI EOP encoding             |      |
|  | Reuse Gen2020 LFSR  |    | II IDLE encoding            |      |
|  +---------------------+    | CRC8 feed + append          |      |
|                             +-----------------------------+      |
|  +---------------------+    +-----------------------------+      |
|  | mle_crc8_engine     |    | mle_ptb_jk_capture          |      |
|  |                     |    |                             |      |
|  | Poly 0xA6           |    | Detect JK pair at TX MDI   |      |
|  | Init 0xFF           |    | Latch PTB timestamp         |      |
|  | XOR out 0xFF        |    | Write to OAM header field  |      |
|  | Byte-reflected I/O  |    | RX: scan for JK SOP        |      |
|  | Reset per OAM frame |    | Add processing delta       |      |
|  +---------------------+    +-----------------------------+      |
|                                                                   |
|  +---------------------+    +-----------------------------+      |
|  | mle_phase1g_info_   |    | mle_startup_plb_gen         |      |
|  | encoder_decoder     |    |                             |      |
|  | 40-bit MLE Phase1G  |    | PhaseSGA/SGB: zero-fill     |      |
|  | info field          |    | Second-to-last PLB = Eq 8-1|      |
|  | MLE cap/config mux  |    | PhaseSGC: zero except last |      |
|  +---------------------+    | Last PLB = Eq 8-1 (inf_SG) |      |
|                             +-----------------------------+      |
|                                                                   |
|  RECEIVE PATH                                                     |
|  +---------------------+    +-----------------------------+      |
|  | mle_plb_disassembler|    | mle_oam_4b5b_decoder        |      |
|  |                     |    |                             |      |
|  | Extract OAM frag    |    | Detect JJ/JK SOP scan      |      |
|  | Extract sec ctrl    |    | 5b -> 4b data decode        |      |
|  | Extract xMII blocks |    | TI EOP detection            |      |
|  | Format ind parse    |    | CRC8 check on reassembly   |      |
|  +---------------------+    | Discard on CRC fail        |      |
|                             +-----------------------------+      |
|  +---------------------+    +-----------------------------+      |
|  | mle_fec_decoder     |    | mle_register_adapter        |      |
|  |                     |    |                             |      |
|  | RS(240,214) decode  |    | MLEcap1/2, MLEconfig decode |      |
|  | SG1/2-based: check  |    | Mode -> SG mapping          |      |
|  | SG3/4/5-based: corr |    | OAM CRC fail count (3.3.24)|      |
|  +---------------------+    +-----------------------------+      |
+==================================================================+
```

---

## 18. Spec Facts vs Implementation Assumptions

### Spec Facts (normative, from Section 8)

- MLE is a derivation of Gen2020 ML Physical Layer (identical PMA)
- Seven MLE modes: MLES_sym1G0/2G5/5G0 (symmetric) and MLES_2G5_M/5G0_M/10G_M/10G_G (asymmetric)
- All MLE modes use tx_phy_blockE<1919:0> = 1920 bits = 240 bytes
- All MLE modes use RS(240,214), single codeword, 214B payload, 26B parity
- FEC correction mandatory for SG3/4/5-based modes; optional for SG1/2-based modes
- Resync header per mode = resync header of the mapped ML SG (Table 8-1 mapping)
- TDD cycle lengths: MLES_sym1G0=628, sym2G5=628, sym5G0=568, 2G5_M=988, 5G0_M=748, 10G_M=6708, 10G_G=748 PTB tics
- Physical layer blocks per burst: per Table 8-2 (Dn: 2/4/7/6/9/162/18; Up: 2/4/7/1/1/2/2)
- Quiet gap per mode: per Table 8-3
- Scrambler: SG1/2/3-based modes use S0 only; SG4/5-based modes use {S1,S0} pairs
- Startup phases (SGA/SGB) always use S0 scrambler for all MLE modes; mapped PAM2
- PhaseSGC uses PAM4 for SG4/5-based modes, PAM2 for SG1/2/3-based modes
- Startup second-to-last PLB = Equation 8-1 (inf_SG embedding pattern)
- MLE Phase1G info field: 40 bits, bits[31:30]=Phase1Gstatus, bits[29:16]=MLEcap, bits[15:11]=MLEconfig, bit[0]=PhysLayerMode=1
- SOP = JJ then JK in consecutive PLB OAM slots
- EOP = TI characters
- IDLE = II characters
- Each OAM byte 4b/5b encoded (two 5b nibbles = 10 bits per PLB OAM slot)
- CRC8 polynomial 0xA6, init 0xFF, XOR output 0xFF, byte-reflected I/O
- CRC8 resets per OAM frame; appended after last OAM data byte before EOP
- PTB timestamp taken when JK of SOP passes transmitting MDI
- RX: PTB timestamp taken when JK of SOP passes receiving MDI; processing delta added
- Rate matching inserts 0x1e Block Type, control code 0x1C (Skip||R||)
- 64b/66b IEEE 802.3 blocks mapped to 65-bit xMII_block[0:64] per Table 8-13
- MLEcapability1 (1.0020): bits[15:13] = symmetric mode capabilities
- MLEcapability2 (1.0021): bits[15:12] = asymmetric mode capabilities
- MLEconfig (1.0022): bit[15]=direction, bits[14:11]=mode selection
- Link Aggregation does NOT apply to MLE (Section 8.8)

### Implementation Assumptions (not normative)

- mle_mode_decoder is a look-up ROM keyed on MLEconfig[14:11] for all timing parameters
- xMII_block packing into tx_phy_blockE is word-aligned: 65 blocks x 29.5 bytes is NOT
  byte-aligned; implementers must verify bit-exact packing against Table 8-5
- CRC8 polynomial 0xA6 in normal form = x^7 + x^5 + x^2 + x^1 (hex A6 = 10100110 binary);
  the full standard form including x^8 is 0x1A6; verify against spec binary definition
- OAM nibble encoding order (lo-then-hi or hi-then-lo) follows FDDI 4b/5b convention
  (lo nibble first); must be verified against Section 8.6.2.3 before RTL
- Startup Equation 8-1 (inf_SG embedding): the "n mod 255" and "n mod 1023" patterns
  repeat the 512-bit SGA/SGB/SGC info field across the PLB bits -- note "255" in the
  spec likely means modulo 256 or a 256-bit window; verify original PDF equation exactly
- The secondary control channel content and its encoding are implementation-dependent;
  the spec only defines the format indicator bit and 10-bit slot in the PLB
- mle_plb_assembler pipeline: FEC encoding latency of 1 PLB period is assumed;
  actual latency must be balanced against burst scheduling requirements

---

## 19. Verification Plan

### 19.1 Unit-Level Checks

| Block | Test | Expected Result |
|-------|------|-----------------|
| mle_mode_decoder | All 7 modes | Correct TDD tics, PLB count, QG, SG |
| mle_plb_assembler | Pack 26 xMII_blocks + OAM + sec ctrl | Bit-exact tx_phy_blockE |
| mle_fec_encoder | RS(240,214) on known payload | Correct 26-byte parity (same polynomial as Gen2020 SG3/4/5) |
| mle_scrambler | SG1/2/3 S0 mode | One LFSR advance per bit, XOR applied |
| mle_scrambler | SG4/5 {S1,S0} mode | One LFSR advance per 2 bits, both taps |
| mle_oam_4b5b_encoder | SOP=JJ+JK, IDLE=II, EOP=TI | 10-bit patterns per Table 8-15 |
| mle_oam_4b5b_encoder | Data byte 0x00 | 11110 11110 (lo=0000->11110, hi=0000->11110) |
| mle_oam_4b5b_encoder | Data byte 0xFF | 11101 11101 (lo=1111->11101, hi=1111->11101) |
| mle_crc8_engine | Known OAM frame | Match expected CRC8 with poly 0xA6 |
| mle_crc8_engine | Reset between frames | CRC reloads 0xFF at each frame start |
| mle_ptb_jk_capture | JK pair detection | PTB latched at MDI symbol time |

### 19.2 Integration-Level Checks

| Scenario | Expected Result |
|----------|-----------------|
| MLES_sym1G0 normal mode, 2 PLBs | TDD cycle = 628 PTB tics; Dn=2 PLBs; QG=5440 |
| MLES_10G_M, 162 PLBs downstream | TDD cycle = 6708 PTB tics; QG Dn=4320, Up=157920 |
| OAM frame fragmentation | SOP (JJ then JK), data bytes, CRC byte, EOP (TI), IDLE (II) |
| OAM CRC8 mismatch on RX | Frame discarded; counter 3.3.24 incremented |
| Rate matching control block | Skip||R|| (0x1e/0x1C) inserted; RX deletes same |
| MLE Phase1G exchange | Root writes MLEconfig[15:11] into leaf via inf_1G<15:11> |
| Startup PhaseSGA | Second-to-last PLB has Equation 8-1 inf_SG pattern |
| PhaseSGB, SG4/5-based mode | PAM2 used (not PAM4); last PLB = Eq 8-1 |
| PhaseSGC, SG4/5-based mode | PAM4 used for PLB and Eq 8-1 symbols |
| RS(240,214) decode, 13 errors | Corrected (SG3/4/5-based mandatory correction) |
| RS(240,214) decode, 14 errors | Uncorrectable; frame discarded |

### 19.3 Cross-module Checks (MLE vs Gen2020)

| Check | Expectation |
|-------|-------------|
| PLP_TX/PLP_RX primitives | DLL identical; MLE invisible to DLL |
| PTB m_ptb in resync header | Identical structure; timing differs per MLE mode |
| Scrambler init (startup_INIT) | Same init state as Gen2020 (0x000001 for LinkID=0) |
| Scrambler held during resync header and QG | Same rule as Gen2020 |

---

## 20. Missing / Needs Verification

1. **Table 8-4 (TDD cycle values) RESOLVED**: Values read from PDF p288:
   MLES_sym1G0=628, MLES_sym2G5=628, MLES_sym5G0=568, MLES_2G5_M=988,
   MLES_5G0_M=748, MLES_10G_M=6708, MLES_10G_G=748. All values now in Section 5.1.

2. **Equation 8-1 "mod 255" vs "mod 256"**: The spec text states "inf_SG[n mod 255]"
   for n in 256..767. This is unusual -- 512 bits of inf_SG indexed mod 255 gives
   values 0..254 (255 unique indices). Verify exact equation from PDF page 293 before
   RTL implementation. NEEDS VERIFICATION.

3. **CRC8 polynomial binary representation**: Section 8.6.2.4 states "polynomial 0xA6".
   Standard CRC-8/MAXIM-DOW uses 0x31; CRC-8/SMBUS uses 0x07. 0xA6 = 10100110b
   implies taps at x^7+x^5+x^2+x^1. The full polynomial with implicit x^8 is 0x1A6.
   The byte-reflected form used for implementation should be verified against the spec
   table or test vector if one exists. NEEDS VERIFICATION.

4. **MLEcapability2 exact bit layout**: The register model doc notes the exact layout
   "matches Table 3-13 in the specification." Table 8-6 confirms bits<24:19> of the
   info field map to bits[15:10] of register 3.2.10. Full 16-bit field layout (which
   asymmetric modes map to which bits within 15:10) needs verification from PDF Table
   3-13. NEEDS VERIFICATION.

5. **Secondary control channel content**: Section 8.6.3 (PDF p301) states the secondary
   control channel is optional, indicated by bit[1919] of tx_phy_blockE. The spec
   provides the 10-bit slot location but no further content definition beyond "optional."
   Content format (if any standard definition exists) NEEDS VERIFICATION from any
   referenced external standard.

6. **OAM nibble encoding order**: The spec says "Each byte of OAM frame data is 4b/5b
   encoded" but does not explicitly state lo-nibble-first vs hi-nibble-first in the
   extracted text. FDDI 4b/5b convention is lo-nibble first. Verify against the full
   Section 8.6.2.3 text in the PDF. NEEDS VERIFICATION.

7. **xMII_block bit ordering within PLB**: Table 8-5 shows m_211,1..m_203,1 = xMII_block_k
   but the indexing across byte boundaries at 65-bit xMII_block boundaries is not
   straightforward. Exact bit-packing formula must be derived from Table 8-5 in the
   spec PDF and verified before RTL. NEEDS VERIFICATION.

8. **MLE PhaseSGC applicability**: In Gen2020, PhaseSGC only applies to SG4/SG5.
   For MLE, it applies to MLE modes derived from SG4/5 (MLES_10G_M uses SG4,
   MLES_sym5G0 and MLES_10G_G use SG5). Verify which MLE modes trigger PhaseSGC
   in the startup FSM. NEEDS VERIFICATION.

9. **OAM CRC8 failure counter register 3.3.24**: Section 8.7.2.2 references counter
   3.3.24. Verify this register address exists in the register model (DLL domain 3
   address 24). The register model doc should be cross-checked. NEEDS VERIFICATION.
