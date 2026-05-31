# Micro-Architecture: ASEP I2S Audio Tunneling

## 1. Purpose and Scope

The ASEP I2S module encapsulates I2S (Inter-IC Sound) audio data into ASA DLL containers
for transport over an ASA SerDes link. It enables audio sample streaming with
PTB-synchronized clock recovery so that the I2S receiver can regenerate a bit-accurate
audio clock from the received PTB timestamps, even when the I2S clock source resides
entirely on the transmit side.

This document defines the micro-architecture of the ASEP I2S encoder/decoder module
(ASE and ASD) for RTL or golden-model implementation. It is derived directly from ASA
Technical Specification v2.0, Sections 7.10 and 7.10.1 through 7.10.4.1 (pages 276-282)
and Appendix F (Section VI, pages 349-350), supplemented by register definitions in
Sections 3.5.8.1-3.5.8.3 (pages 84-86).

Scope boundaries:
- IN SCOPE: I2S ASEP packet encoding and decoding, all packet modes (configuration mode
  and data mode), PTB synchronization formula (M/N ratio, f_StrmClk), PTB timestamp
  capture and clock regeneration architecture, all configuration command variants
  (Write, Read, ACK/NACK, Read Response), data mode packet structure, all audio sample
  bit-depth coding tables (8/12/16/20/24/32-bit), register model for I2S data format,
  sample rate, sampling sync, TX/RX data flows, RTL submodule decomposition,
  verification plan
- OUT OF SCOPE: ASEP common header and footer (see micro-architecture-asep-common-framing.md),
  PTB clock generation and leader/follower lock protocol (see micro-architecture-ptb-clock-service.md),
  DLL mapper/demux scheduling, OAM configuration flow, physical I2S electrical
  specification (JEDEC/I2S bus standard), I2S multi-master arbitration

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 7.10.1 | I2S ASEP Features | 276 | Feature overview: formats, master side |
| 7.10.1.1 | Audio Sampling Rate to PTB Synchronization | 276 | M/N formula, Table 7-74 stream clock packet |
| 7.10.2 | I2S Packet Header | 277 | Table 7-76: mode bit + packetID |
| 7.10.3 | I2S Configuration Mode | 277 | Config mode overview |
| 7.10.3.1 | Configuration Command | 277-278 | Table 7-77: command mode bits |
| 7.10.3.2 | Write Command | 278 | Table 7-78: write command payload |
| 7.10.3.3 | Read Command | 278 | Read: no payload |
| 7.10.3.4 | ACK/NACK Command | 278-279 | Table 7-79: ACK/NACK |
| 7.10.3.5 | Read Response Command | 279 | Read response payload |
| 7.10.3.6 | Configuration Command Footer | 279 | Table 7-80: CRC32 footer |
| 7.10.4 | I2S Data Mode | 279-280 | Data mode overview, host/slave send rule |
| 7.10.4.1 | I2S Data Coding | 280-282 | Tables 7-81 to 7-87: data mode packet and per-depth coding |
| 3.5.8.1 | I2S Data Format (4/5.i.0200) | 84-85 | Table 3-96: bit depth, format, channels |
| 3.5.8.2 | I2S Audio Sample Rate (4/5.i.0201) | 85-86 | Table 3-97: 20 standard rates |
| 3.5.8.3 | I2S Sampling Sync (4/5.i.0202-0203) | 86 | Tables 3-98/3-99: timing host, target clock, K, N |
| VI | Appendix F: I2S Audio Sampling (informative) | 349 | INFORMATIVE overview |
| VI.a | I2S Audio Sampling relative to PTB | 349-350 | INFORMATIVE: Figure VI-1 capture/reconstruct principle, Figure VI-2 N table |
| Equation 7-1 | I2S Audio Sampling Rate to PTB Synchronization | 277 | f_SCK/MCK = N / (S(n) - S(n-1)) |

Structured chunk IDs: asa-7.10.1.1, asa-7.9.3.4 (contains 7.10 preamble), asa-7.10.3.1,
asa-7.10.3.4, asa-7.10.4, asa-7.10.4.1, asa-VI, asa-VI.a, asa-3.5.8.1, asa-3.5.8.2,
asa-3.5.8.3

Image references (docpdfmd/images/):
- 10_PTB_leader_follower_sync.png   -- Figure VI-1 principle: left side = capture (ASA node2,
                                       follower), right side = reconstruct (ASA node1, leader)
- 11_I2S_SCK_frequency_table.png   -- Figure VI-2 (mislabeled as SCK table): recommended
                                       divisors N for common audio rates
- 19_PTB_clock_sync_I2S_nodes.png  -- Detailed two-node diagram with PTB follower/leader
                                       clocks, MCK/SCK input/output paths, N multiplier block

---

## 3. I2S Audio Tunneling Model

### 3.1 Overview

SPEC FACT (Section 7.10.1, p276): "The I2S ASEP supports data formats for all common
bit widths in mono, stereo and multi-channel (time-division multiplex, TDM)."

SPEC FACT (Section 7.10.1, p276): "The I2S ASEP supports I2S timing master to be at
either I2S TX or I2S RX."

SPEC FACT (Section 7.10.1, p276): "The I2S ASEP codes audio frequency explicitly for
most common values and supports a derivation off of PTB time stamps."

The I2S ASEP stream is bidirectional:
- In normal (TX-is-host) mode, the I2S TX side ASE sends data and PTB timestamps
  together in data mode packets.
- In I2S-RX-is-host mode, the I2S TX side ASE sends audio sample data only while the
  I2S RX side ASE sends timestamps only.
- The configuration mode provides a side-channel for registering audio format parameters
  (bit depth, channel count, sample rate, timing master, coefficient K, divisor N) before
  or during streaming.

```
  I2S TX side (audio source)              I2S RX side (audio sink)
  +-------------------------------+        +-------------------------------+
  |  I2S TX device (or master)    |        |  I2S RX device (or master)    |
  |  SCK, WS, DATA out            |        |  SCK, WS, DATA in             |
  +---------------+---------------+        +---+---------------------------+
                  |                             |
          +-------+-------+             +------+--------+
          |    ASE        |             |    ASD        |
          |  (I2S TX)     |             |  (I2S RX)     |
          +---+-------+---+             +---+-------+---+
              |       ^                     ^       |
          DLP_TX   DLP_RX              DLP_TX   DLP_RX
              |       |                     |       |
  +-----------v-------+---------------------+-------v-----------+
  |                       ASA SerDes Link                        |
  |              (DLL containers, PTB synchronized)              |
  +--------------------------------------------------------------+
```

The ASEP stream type code for I2S is 0x07 (Table 7-1, Section 7.3, p233).

SPEC FACT (Section 7.10.4, p279-280): "Data mode packets are just sent by the ASEP on
the side of I2S TX in case the TX is also the (audio timing) host."

SPEC FACT (Section 7.10.4, p280): "In case the I2S RX is (audio timing) host, the I2S
TX side ASEP sends audio sample data only while the I2S RX side ASEP sends time stamps
only."

### 3.2 Two Operational Modes

The I2S ASEP has two distinct packet modes, indicated by bit 7 of header byte m+1:

| Mode Bit | Mode | Description |
|----------|------|-------------|
| 0 | I2S Configuration Mode | Register read/write handshake for audio format config |
| 1 | I2S Data Mode | Audio sample streaming with optional PTB timestamps |

### 3.3 Timing Master Roles

The I2S spec defines two clock roles:
- I2S Timing Host (master): the device that generates SCK (serial clock) and WS (word
  select / LRCLK). This is configured via 4/5.i.0202 bit "Timing host select".
- I2S Timing Slave: the device that receives SCK and WS from the master.

The Timing Host can be at either the I2S TX node or the I2S RX node. This distinction
determines which ASA node captures PTB timestamps and which one reconstructs the clock.

---

## 4. PTB Clock Synchronization Architecture

### 4.1 PTB Capture and Reconstruction Principle

SPEC FACT (Section 7.10.1.1, p276): "For this method, the ASE connecting to the I2S
device in master mode shall capture PTB time stamps every 'N' cycles of the SCK (serial
clock of the I2S) or MCK (audio master clock) signal and shall transmit them. SCK and
MCK are related by an integer factor defined in 3.5.8.3."

SPEC FACT (Equation 7-1, p277): The non-master mode side reconstructs the audio sampling
rate as:

    f_SCK  or  f_MCK  =  N / (S(n) - S(n-1))    [frequency in MHz]

where S(n) is the nth PTB timestamp.

INFORMATIVE (Appendix F, VI.a, p349-350): The following describes the capture and
reconstruction principle as shown in Figure VI-1 and the full two-node diagram in
image 19_PTB_clock_sync_I2S_nodes.png:

Capture side (ASA node2 -- I2S master / audio timing host):
1. Receive MCK or SCK from the connected I2S master device.
2. Count "N" cycles of MCK or SCK using a modulo-N counter.
3. Each time the N-counter wraps (counting starts over), capture the local PTB timestamp
   S(n) from the 4ns-resolution PTBclk (PTB Follower CLK running at 250+Delta MHz).
4. Transmit S(n) in the I2S data mode packet (Start time PTB stamp field, bytes m+4..m+6).

Reconstruction side (ASA node1 -- I2S slave / audio timing non-host):
1. Receive PTB timestamps S(n) from the network.
2. Compute M(n) = S(n) - S(n-1) in PTB ticks (difference of successive timestamps).
3. Count M(n) PTB ticks using the local PTB Leader CLK (running at 250 MHz).
4. After counting M PTB ticks, multiply by N to regenerate M*N source clock periods,
   producing the MCK or SCK output to the connected I2S slave device.

```
  ASA node2 (Capture side / I2S master)
  +--------------------------------------------+
  |                                            |
  |  MCK or SCK  ----+                         |
  |  from I2S        |                         |
  |  master          v                         |
  |           +-------------+                  |
  |           | Count "N"   |                  |
  |           | with MCK    |                  |
  |           | or SCK      |                  |
  |           +------+------+                  |
  |                  | N-wrap                  |
  |                  v                         |
  |           +-------------+   4ns PTB tick   |
  |           | Capture PTB |<--(PTB Follower  |
  |           | timestamp   |    CLK 250+D MHz)|
  |           | S(n)        |                  |
  |           +------+------+                  |
  |                  |                         |
  |               S(n) transmitted             |
  +--------------------------------------------+
                     |
        [ASA SerDes link -- PTB messages synced]
                     |
  +--------------------------------------------+
  |  ASA node1 (Reconstruct side / I2S slave)  |
  |                                            |
  |       S(n) received                        |
  |                  |                         |
  |           +------+------+                  |
  |           | M(n) =      |                  |
  |           | S(n)-S(n-1) |                  |
  |           +------+------+                  |
  |                  |                         |
  |           +------+------+   4ns PTB tick   |
  |           | Count M(n)  |<--(PTB Leader    |
  |           | PTB ticks   |    CLK 250 MHz)  |
  |           | regenerated |                  |
  |           +------+------+                  |
  |                  |                         |
  |           +------+------+                  |
  |           | Multiply    |                  |
  |           | by N        |                  |
  |           +------+------+                  |
  |                  |                         |
  |  MCK or SCK  <---+                         |
  |  to I2S                                    |
  |  slave device                              |
  +--------------------------------------------+
```

### 4.2 M/N Stream Clock Formula (Section 7.10.1.1, Table 7-74)

SPEC FACT (Section 7.10.1.1, p276): The stream clock packet (Table 7-74 -- ASEP eDP
Stream Clock Packet is referenced in the same PDF page) carries 24-bit M and N values:

    f_StrmClk = M_vid,ptb / N_vid,ptb  *  f_PTB

where:
- M_vid,ptb: 24-bit unsigned integer numerator
- N_vid,ptb: 24-bit unsigned integer denominator
- f_PTB: PTB tick frequency = 250 MHz (4ns per tick)
- "24-bit allow 14.9 Hz resolution for stream clock values < 250 MHz"

Table 7-74 -- ASEP eDP/I2S Stream Clock Packet (Section 7.10.1.1, p276):

```
Byte      Bit(s)   Name           Description
--------  -------  ----           -----------
m+1_HB    7:5      Reserved       --
m+1_HB    4:0      Reserved       --
m+2_HB    7:0      M_vid,ptb      M[23:16]   Unsigned integer, numerator MSB
[23:16]
m+3_HB    7:0      M_vid,ptb      M[15:8]
[15:8]
m+4_HB    7:0      M_vid,ptb      M[7:0]     Unsigned integer, numerator LSB
[7:0]
m+5_HB    7:0      N_vid,ptb      N[23:16]   Unsigned integer, denominator MSB
[23:16]
m+6_HB    7:0      N_vid,ptb      N[15:8]
[15:8]
m+7_HB    7:0      N_vid,ptb      N[7:0]     Unsigned integer, denominator LSB
[7:0]
```

### 4.3 PTB Capture Equation (Equation 7-1)

SPEC FACT (Equation 7-1, Section 7.10.3.1 preamble, p277):

    f_SCK  or  f_MCK  =  N / (S(n) - S(n-1))       [f in MHz]

where S(n) is the nth PTB time stamp.

This equation gives the instantaneous estimate of SCK or MCK in MHz. The divisor N is
configured by register 4/5.i.0203 (Divisor N, range 1-16535).

### 4.4 Recommended N Divisors for Common Audio Rates (Figure VI-2, Appendix F)

INFORMATIVE (Appendix F, Figure VI-2, p350): The spec provides a table of recommended
lowest N values for common audio sampling rates. The columns represent I2S bit-clock
multiplier values (bit widths 24, 32, 40, 48, 64, 96, 128, 256, 512), which correspond
to the number of SCK cycles per audio sample (or per channel sample).

The following table is derived from spec image 11_I2S_SCK_frequency_table.png (Figure
VI-2). Note that N is chosen so that the PTB timestamp difference S(n)-S(n-1) represents
a meaningful number of PTB ticks (at 4ns each) for each audio rate, giving adequate
measurement resolution.

```
Audio     SCK periods per sample (K coefficient x channel width)
Rate      (Values of N for respective SCK multiples)
(kHz)     24     32     40     48     64     96    128    256    512
--------  ----   ----   ----   ----   ----   ----   ----   ----   ----
8.000     N/A    N/A    N/A    N/A    N/A    N/A     N/A    N/A    N/A
11.025    N/A    N/A    N/A    N/A    N/A    N/A     N/A    N/A    N/A
16.000    N/A    N/A    N/A    N/A    N/A    N/A     N/A    N/A    N/A
22.050    N/A    N/A    N/A    N/A    N/A    N/A     N/A    N/A    N/A
32.000    N/A    N/A    N/A    N/A    N/A    N/A     N/A    N/A    N/A
44.100    (see image 11_I2S_SCK_frequency_table.png for exact values)
48.000    (see image 11_I2S_SCK_frequency_table.png for exact values)
96.000    (see image 11_I2S_SCK_frequency_table.png for exact values)
192.000   (see image 11_I2S_SCK_frequency_table.png for exact values)
```

MISSING/NEEDS VERIFICATION: The actual N-value table from Figure VI-2 is not
machine-readable from available text extraction. The full table should be verified
against PDF pages 349-350. Confirmed column headings (bit widths): 24, 32, 40, 48, 64,
96, 128, 256, 512.

INFORMATIVE: For a 48 kHz audio rate with 64 SCK cycles per sample (stereo, 32-bit),
the SCK frequency is 48000 * 64 = 3.072 MHz. At 4ns PTB resolution, N=256 would give
timestamp differences of approximately 256 / 3.072MHz = 83.3us = ~20833 PTB ticks,
providing excellent measurement precision.

---

## 5. I2S Packet Header (Section 7.10.2, Table 7-76)

SPEC FACT (Section 7.10.2, p277): "The I2S ASEP header format is shared for all packet
modes."

The I2S packet header follows the common ASEP header (stream type byte 0 = 0x07, PTB
timestamp byte 1) and is at byte index m+1_HB (where m+1_HB follows the common ASEP
header).

Table 7-76 -- ASEP I2S Packet Header:

```
Byte      Bit(s)   Name                Description
--------  -------  ----                -----------
m+1_HB    7        I2S packet mode     0: I2S configuration mode
                                       1: I2S data mode
m+1_HB    6:0      I2S packetID        Each ASEP keeps two independent packetID
                                       counters, one for configuration mode packets
                                       and one for data mode packets.
                                       Both counters start from 1.
                                       Valid range: 1-120. An increment from 120
                                       rolls over to 1. Values 0 and 121-127 are
                                       reserved.
                                       Configuration mode: host side increments
                                       packetID with each packet; slave side copies
                                       the host side packetID into responses.
                                       Data mode: packetID incremented for each
                                       packet sent.
```

SPEC FACT (Section 7.10.2, p277):
- Both I2S packetID counters start from 1.
- I2S packetID valid range is 1-120.
- An increment from 120 rolls over to 1.
- Values 0 and 121-127 are reserved.

---

## 6. I2S Configuration Mode (Section 7.10.3)

The configuration mode provides a reliable request-response handshake for programming
audio format parameters across the ASA link. The host side (root node or I2S timing
host) initiates Write or Read commands; the slave side responds with ACK/NACK or Read
Response packets.

### 6.1 Configuration Command Header (Section 7.10.3.1, Table 7-77)

SPEC FACT (Section 7.10.3.1, p277-278): Configuration command byte follows the I2S
packet header at m+2_HB.

Table 7-77 -- ASEP I2S Configuration Command:

```
Byte      Bit(s)   Name                      Description
--------  -------  ----                      -----------
m+2_HB    7:6      Configuration             00: Write command
                   command mode              01: Read command
                                             10: ACK/NACK command
                                             11: Read response command
m+2_HB    5:0      Reserved                  --
```

### 6.2 Write Command Payload (Section 7.10.3.2, Table 7-78)

SPEC FACT (Section 7.10.3.2, p278):

Table 7-78 -- ASEP I2S Configuration Mode Write Command:

```
Byte      Bit(s)   Name                      Description
--------  -------  ----                      -----------
m+2_HB    7:4      Reserved                  --
m+2_HB    3:0      I2S audio sample bit      See section 3.5.8.1 / register 4/5.i.0200
                   depth
m+3_HB    7        Reserved                  --
m+3_HB    6:4      I2S data format           See section 3.5.8.1 / register 4/5.i.0200
m+3_HB    3        Reserved                  --
m+3_HB    2:0      Number of channels        See section 3.5.8.1 / register 4/5.i.0200
m+4_HB    7:5      Reserved                  --
m+4_HB    4:0      Audio sampling frequency  See section 3.5.8.2 / register 4/5.i.0201
m+5_HB    7        Reserved                  --
m+5_HB    6        Timing host select        See section 3.5.8.3 / register 4/5.i.0202
m+5_HB    5        Reserved                  --
m+5_HB    4        Target clock select       See section 3.5.8.3 / register 4/5.i.0202
m+5_HB    3:2      Reserved                  --
m+5_HB    1:0      Coefficient K[9:8]        See section 3.5.8.3 / register 4/5.i.0202
m+6_HB    7:0      Coefficient K[7:0]        See section 3.5.8.3 / register 4/5.i.0202
m+7_HB    7:0      Divisor N[15:8]           See section 3.5.8.3 / register 4/5.i.0203
m+8_HB    7:0      Divisor N[7:0]            See section 3.5.8.3 / register 4/5.i.0203
```

### 6.3 Read Command (Section 7.10.3.3)

SPEC FACT (Section 7.10.3.3, p278): "The Read command does not have any payload."

The Read command uses the configuration command header only (Table 7-77 with bits 7:6
= 01), followed immediately by the footer (Section 6.6 below).

### 6.4 ACK/NACK Command (Section 7.10.3.4)

SPEC FACT (Section 7.10.3.4, p278-279): "The payload of the ACK/NACK command is
identical to the Write command payload (see section 7.10.3.2) except for the field
below."

ACK/NACK specific field in the command header byte (m+2_HB):

```
Byte      Bit(s)   Name                      Description
--------  -------  ----                      -----------
m+2_HB    0        ACK/NACK                  0: write failed (NACK)
                                             1: write succeeded (ACK)
```

The remaining bytes m+3_HB through m+8_HB mirror the write command payload format
(Table 7-78).

SPEC FACT (Section 7.10.3.5 referenced from 7.10.4, p279): "The root node should
implement a timeout watchdog (depending on the schedule cycle for this ASEP and the
application use case) and treat a timeout as a NACK."

### 6.5 Read Response Command (Section 7.10.3.5)

SPEC FACT (Section 7.10.3.5, p279): "The payload of the Read Response command is
identical to the Write command payload (see section 7.10.3.2)."

SPEC FACT (Section 7.10.3.5, p279): "The root node should implement a timeout watchdog
(depending on the schedule cycle for this ASEP and the application use case) and treat
a timeout as a NACK (all zeros)."

The read response carries the current values of all parameters (bit depth, data format,
channels, sample frequency, timing host select, target clock select, coefficient K,
divisor N) in the same field layout as the write command payload.

### 6.6 Configuration Command Footer (Section 7.10.3.6, Table 7-80)

SPEC FACT (Section 7.10.3.6, p279):

Table 7-80 -- ASEP I2S Configuration Command Footer Format:

```
Byte      Bit(s)   Name              Description
--------  -------  ----              -----------
m-3_END   7:0      CRC32[31:24]      Checksum over all ASEP packet bytes 0 to
                                     m-4_END, where m_END is the last byte index
                                     of the entire ASEP packet
m-2_END   7:0      CRC32[23:16]      (see section 4.2.9 for CRC32 definition)
m-1_END   7:0      CRC32[15:8]
m_END     7:0      CRC32[7:0]
```

The CRC32 covers all ASEP packet bytes from byte 0 (common ASEP header stream type
byte) through byte m-4_END inclusive (i.e., all bytes except the 4 footer bytes).

### 6.7 Configuration Mode Transaction Flow

```
  Host (root / I2S timing master side)     Slave (remote / I2S timing slave side)
          |                                           |
          |--- Write cmd (packetID=1) -------------->|
          |    [bit depth, format, ch, rate,          |
          |     timing host, K, N, CRC32]             |
          |                                           | validate params
          |                                           | write to registers
          |<-- ACK/NACK (packetID=1) ----------------|
          |    [echo params, ACK=1/0, CRC32]          |
          |                                           |
          |--- Read cmd (packetID=2) --------------->|
          |    [header only + CRC32]                  |
          |                                           |
          |<-- Read Response (packetID=2) -----------|
          |    [current params, CRC32]                |
          |                                           |
```

SPEC FACT: Host increments I2S configuration mode packetID with each packet; slave
copies host packetID into response. Timeout on host side treated as NACK (all zeros).

---

## 7. I2S Data Mode (Section 7.10.4)

### 7.1 Data Mode Overview

SPEC FACT (Section 7.10.4, p279-280): In data mode, the ASEP on the side of I2S TX
sends data if TX is also the audio timing host. In the RX-is-host variant, TX-side
ASEP sends audio sample data only; RX-side ASEP sends timestamps only.

### 7.2 Data Mode Packet Structure (Section 7.10.4, Table 7-81)

Table 7-81 -- ASEP I2S Data Mode Packet:

```
Byte           Bit(s)   Name                      Description
----------     -------  ----                      -----------
m+2_HB         7:2      Reserved                  --
m+2_HB         1:0      I2S data length[9:8]      Number of data bytes in this packet
                                                   (10-bit field, upper 2 bits here)
m+3_HB         7:0      I2S data length[7:0]      In case of a packet from I2S RX,
                                                   this field is 0
m+4_HB         7:0      Start time PTB            PTB time stamp at the start of
                         stamp[23:16]              counter N of MCK/SCK cycles
m+5_HB         7:0      Start time PTB
                         stamp[15:8]
m+6_HB         7:0      Start time PTB
                         stamp[7:0]
m+6+n_HB       7:0      I2S data                  Audio sample data bytes, coded
                                                   per section 7.10.4.1 (Tables 7-82
                                                   to 7-87)
...
m-3_END        7:0      CRC32[31:24]              Checksum over byte 0 to m-4_END
m-2_END        7:0      CRC32[23:16]
m-1_END        7:0      CRC32[15:8]
m_END          7:0      CRC32[7:0]
```

The "Start time PTB stamp" is a 24-bit value (3 bytes), representing the lower 24 bits
of the PTB timestamp captured at the start of the N-count period for MCK/SCK cycles.

IMPLEMENTATION ASSUMPTION: The PTB timestamp field in the data mode packet (3 bytes,
24 bits) is a subset of the 48-bit PTBclk register. The lower 24 bits of PTBclk provide
approximately 67.1ms of timestamp range at 4ns resolution before rollover. For
continuous audio streams this is generally sufficient between consecutive N-count
periods, but implementations should handle potential rollover for very low audio rates
with large N.

---

## 8. I2S Data Coding (Section 7.10.4.1)

### 8.1 Sample Ordering Rules

SPEC FACT (Section 7.10.4.1, p280): "P denotes the audio sample index. A higher index
means an audio sample later in time."

SPEC FACT (Section 7.10.4.1, p280): "Q denotes the channel index. In case of stereo,
1 denotes the left channel, 2 denotes the right channel. In case of TDM, the channel
definition is up to user."

SPEC FACT (Section 7.10.4.1, p280): "The samples in the I2S data field shall always be
ordered: firstly by ascending channel index for all channels within one audio sample,
secondly by ascending audio sample indexes."

This means for each sample time P, all Q channels are packed together in channel order
Q=1, Q=2, ..., Q=num_ch, then the next sample P+1 follows.

### 8.2 Bit Depth Coding Tables

#### 8.2.1 8-bit Audio (Table 7-82)

```
Byte    Bit(s)   Name
------  -------  ----
n       7:0      P-th audio sample, Q-th channel: I2S data word [7:0]
```

One byte per sample-channel.

#### 8.2.2 12-bit Audio (Table 7-83)

```
Byte    Bit(s)   Name
------  -------  ----
n       7:4      Reserved
n       3:0      P-th audio sample, Q-th channel: I2S data word [11:8]
n+1     7:0      P-th audio sample, Q-th channel: I2S data word [7:0]
```

Two bytes per sample-channel (4 MSBs of first byte reserved, upper nibble = bits 11:8).

#### 8.2.3 16-bit Audio (Table 7-84)

```
Byte    Bit(s)   Name
------  -------  ----
n       7:0      P-th audio sample, Q-th channel: I2S data word [15:8]
n+1     7:0      P-th audio sample, Q-th channel: I2S data word [7:0]
```

Two bytes per sample-channel, big-endian.

#### 8.2.4 20-bit Audio (Table 7-85)

```
Byte    Bit(s)   Name
------  -------  ----
n       7:4      Reserved
n       3:0      P-th audio sample, Q-th channel: I2S data word [19:16]
n+1     7:0      P-th audio sample, Q-th channel: I2S data word [15:8]
n+2     7:0      P-th audio sample, Q-th channel: I2S data word [7:0]
```

Three bytes per sample-channel (4 MSBs reserved).

#### 8.2.5 24-bit Audio (Table 7-86)

```
Byte    Bit(s)   Name
------  -------  ----
n       7:0      P-th audio sample, Q-th channel: I2S data word [23:16]
n+1     7:0      P-th audio sample, Q-th channel: I2S data word [15:8]
n+2     7:0      P-th audio sample, Q-th channel: I2S data word [7:0]
```

Three bytes per sample-channel, big-endian.

#### 8.2.6 32-bit Audio (Table 7-87, from Section 7.11.3 context, p282)

```
Byte    Bit(s)   Name
------  -------  ----
n       7:0      P-th audio sample, Q-th channel: I2S data word [31:24]
n+1     7:0      P-th audio sample, Q-th channel: I2S data word [23:16]
n+2     7:0      P-th audio sample, Q-th channel: I2S data word [15:8]
n+3     7:0      P-th audio sample, Q-th channel: I2S data word [7:0]
```

Four bytes per sample-channel, big-endian.

### 8.3 Bit Depth Summary Table

```
Bit Depth   Bytes/sample-ch   Notes
---------   ---------------   -----
8           1                 All 8 bits active
12          2                 Upper nibble of first byte reserved
16          2                 Both bytes active, big-endian
20          3                 Upper nibble of first byte reserved
24          3                 All 3 bytes active, big-endian
32          4                 All 4 bytes active, big-endian
```

SPEC FACT: The register 4/5.i.0200 defines bit depth codes 0-5 (8/12/16/20/24/32 bit)
with values 6-15 reserved.

---

## 9. Register Definitions

### 9.1 I2S Data Format Register -- 4/5.i.0200 (Section 3.5.8.1, Table 3-96)

SPEC FACT (Section 3.5.8.1, p84-85):

```
Address: 4/5.i.0200
Name: I2S Data Format

Bit(s)   Name                  R/W   Access  Priv   Description
-------  ----                  ---   ------  ----   -----------
15:12    reserved
11:8     I2S audio sample      RW    O       RID    0: 8 bit
         bit depth per                              1: 12 bit
         channel                                    2: 16 bit
                                                    3: 20 bit
                                                    4: 24 bit
                                                    5: 32 bit
                                                    6-15: reserved
7        reserved
6:4      I2S data format       RW    O       RID    0: I2S format
                                                    1: left-justified format
                                                    2: right-justified format
                                                    3: TDM mode
                                                    4-7: reserved
3        reserved
2:0      Number of channels    RW    O       RID    uint; 0: reserved
         (uint)                                     1-8: number of channels
```

Access key: R/W = Read/Write; O = OAM channel and local; RID = Root node ID only.

### 9.2 I2S Audio Sample Rate Register -- 4/5.i.0201 (Section 3.5.8.2, Table 3-97)

SPEC FACT (Section 3.5.8.2, p85-86):

```
Address: 4/5.i.0201
Name: I2S Audio Sample Rate

Bit(s)   Name                  R/W   Access  Priv   Description
-------  ----                  ---   ------  ----   -----------
15:5     reserved
4:0      Audio sampling        RW    O       RID    All values given in kHz
         frequency
```

Audio sampling frequency encoding:

```
Code    Rate (kHz)    Code    Rate (kHz)
------  ----------    ------  ----------
0x00    8.000         0x0D    88.200
0x01    11.025        0x0E    96.000
0x02    16.000        0x0F    176.400
0x03    22.050        0x10    192.000
0x04    32.000        0x11    352.000  (352.8 kHz)
0x05    37.800        0x12    384.000
0x06    44.056        0x13    768.000
0x07    44.100        0x14-0x1F  reserved
0x08    47.250
0x09    48.000
0x0A    50.000
0x0B    50.400
0x0C    64.000
```

SPEC FACT: 20 standard audio sampling rates are explicitly coded (codes 0x00-0x13).
Values 0x14-0x1F are reserved.

### 9.3 I2S Sampling Sync 1 Register -- 4/5.i.0202 (Section 3.5.8.3, Table 3-98)

SPEC FACT (Section 3.5.8.3, p86):

```
Address: 4/5.i.0202
Name: I2S Sampling Sync 1

Bit(s)   Name                  R/W   Access  Priv   Description
-------  ----                  ---   ------  ----   -----------
15       reserved
14       Timing host select    RW    O       RID    The master device generates SCK and
                                                    WS. The setting refers to the I2S
                                                    interface in the same device as the
                                                    ASA node.
                                                    0: I2S TX is in master mode
                                                    1: I2S RX is in master mode
13       reserved
12       Target clock select   RW    O       RID    0: SCK
                                                    1: MCK
11:10    reserved
9:0      Coefficient K         RW    O       RID    Unsigned integer, fixed ratio between
                                                    SCK/MCK and audio sampling rate.
                                                    Valid range: 1-1023
                                                    0: reserved
```

SPEC FACT: Coefficient K is the ratio K = f_SCK / f_audio (or f_MCK / f_audio). For
standard stereo I2S (2 channels x 32-bit = 64 SCK cycles per sample), K = 64.

### 9.4 I2S Sampling Sync 2 Register -- 4/5.i.0203 (Section 3.5.8.3, Table 3-99)

SPEC FACT (Section 3.5.8.3, p86):

```
Address: 4/5.i.0203
Name: I2S Sampling Sync 2

Bit(s)   Name                  R/W   Access  Priv   Description
-------  ----                  ---   ------  ----   -----------
15:0     Divisor N             RW    O       RID    Unsigned integer
                                                    Valid range: 1-16535
                                                    0: reserved
```

SPEC FACT: N is the number of SCK or MCK cycles between successive PTB timestamp
captures. From Equation 7-1: f_SCK or f_MCK = N / (S(n) - S(n-1)) in MHz.

### 9.5 Register Summary

```
Address        Name                   R/W   Access  Priv   Section
------------   ----                   ---   ------  ----   -------
4/5.i.0200     I2S Data Format        RW    O       RID    3.5.8.1
4/5.i.0201     I2S Audio Sample Rate  RW    O       RID    3.5.8.2
4/5.i.0202     I2S Sampling Sync 1    RW    O       RID    3.5.8.3
4/5.i.0203     I2S Sampling Sync 2    RW    O       RID    3.5.8.3
```

Note: The i subscript in 4/5.i.xxxx denotes the per-DLP port index. Each DLP_TX (domain
4) and DLP_RX (domain 5) has its own copy of these registers.

---

## 10. TX and RX Data Flows

### 10.1 I2S ASE TX Flow (Configuration Mode Write)

```
  +----------------------------------------------------+
  |  Application (I2S timing host / root node ECU)     |
  |  -> Wants to configure remote audio format         |
  +--------------------+-------------------------------+
                       |
                       v
  +----------------------------------------------------+
  |  Configuration Mode State Machine (TX path)        |
  |                                                    |
  |  1. Build I2S Write Command packet:                |
  |     a. Common ASEP header (stream type = 0x07,    |
  |        follow flag, optional PTB timestamp mode)  |
  |     b. I2S packet header (mode=0, packetID++)      |
  |     c. Config command byte (mode=00 Write)         |
  |     d. Write payload: bit depth, format, channels, |
  |        sample rate, timing host, target clock K, N |
  |     e. Footer CRC32 over all bytes                 |
  |                                                    |
  |  2. Pass to DLL via DLP_TX.dataUnit                |
  +--------------------+-------------------------------+
                       |
                       v (DLL -> ASA link -> remote ASD)
                       |
  +--------------------+-------------------------------+
  |  Configuration Mode State Machine (RX / slave)     |
  |                                                    |
  |  1. Receive Write cmd, check CRC32                 |
  |  2. Apply new parameters to local registers:       |
  |     4/5.i.0200, 4/5.i.0201, 4/5.i.0202-0203       |
  |  3. Build ACK/NACK response:                       |
  |     echo params + ACK=1(success) or 0(fail)        |
  |  4. Return ACK/NACK with same packetID             |
  +----------------------------------------------------+
```

### 10.2 I2S ASE TX Flow (Data Mode -- TX is Host)

```
  +----------------------------------------------------+
  |  I2S TX device (audio timing master)               |
  |  SCK / MCK out, WS out, DATA out                   |
  +--------------------+-------------------------------+
                       |
                       v
  +----------------------------------------------------+
  |  SCK/MCK Counter Module                            |
  |                                                    |
  |  Count N cycles of SCK or MCK                      |
  |  On N-wrap: trigger PTB timestamp capture          |
  +-------+---------+----------------------------------+
          |         |
          |   N-wrap signal
          |         v
  +-------|---------------------------+
  |  PTB  |  Capture                 |
  |  Timestamp Module                |
  |                                  |
  |  Latch PTBclk[23:0] on N-wrap    |
  |  -> start_time_ptb_stamp[23:0]   |
  +-------+--------------------------+
          |
          v
  +-------+--------------------------+
  |  Audio Sample Buffer             |
  |                                  |
  |  Collect I2S audio samples       |
  |  Pack per bit-depth coding       |
  |  (Table 7-82 through 7-87)       |
  +-------+--------------------------+
          |
          v
  +-------+--------------------------+
  |  Data Mode Packet Builder        |
  |                                  |
  |  a. Common ASEP header           |
  |  b. I2S packet header (mode=1,   |
  |     data packetID++)             |
  |  c. Data mode header:            |
  |     - I2S data length[9:0]       |
  |     - start_time_ptb_stamp[23:0] |
  |  d. I2S data bytes (per coding)  |
  |  e. Footer CRC32                 |
  +-------+--------------------------+
          |
          v (DLP_TX.dataUnit -> DLL -> ASA link)
```

### 10.3 I2S ASD RX Flow (Data Mode -- RX is Slave)

```
  (DLL -> DLP_RX.dataUnit -> ASD)
          |
          v
  +-------+--------------------------+
  |  Data Mode Packet Parser         |
  |                                  |
  |  a. Verify stream type = 0x07    |
  |  b. Parse mode=1, check packetID |
  |  c. Extract data length, PTB stamp|
  |  d. Verify CRC32                 |
  +-------+--------------------------+
          |
          v
  +-------+--------------------------+
  |  Audio Sample Decoder            |
  |                                  |
  |  Decode per configured bit depth |
  |  Restore channel interleaving    |
  |  (ascending Q then ascending P)  |
  +-------+--------------------------+
          |
          v
  +-------+--------------------------+
  |  PTB Clock Reconstruction        |
  |                                  |
  |  Receive PTB stamp S(n)          |
  |  Compute M(n) = S(n) - S(n-1)   |
  |  Count M(n) PTB ticks then x N   |
  |  Regenerate SCK/MCK output       |
  +-------+--------------------------+
          |
          v
  +-------+--------------------------+
  |  I2S RX device                   |
  |  Receives audio + SCK/MCK/WS     |
  +------------------------------------+
```

### 10.4 I2S Data Mode -- RX is Host Variant

When I2S RX is the audio timing host (register 4/5.i.0202 Timing host select = 1):

- I2S TX side ASE sends data mode packets with I2S data length > 0 but PTB stamp = 0
  (or carries only audio sample data, no timestamp).
- I2S RX side ASE sends data mode packets with I2S data length = 0 but PTB stamp present
  (timestamp-only packets, providing the N-count PTB capture values to the TX side for
  potential diagnostic purposes).

SPEC FACT (Section 7.10.4, p279-280): In case the I2S RX is host, the TX-side ASEP sends
audio sample data only while the RX-side ASEP sends time stamps only. The data length
field in a packet from I2S RX is 0 (Table 7-81).

---

## 11. Interface Definitions

### 11.1 External Interfaces

```
Interface           Direction     Width    Description
---------           ---------     -----    -----------
i2s_sck             IN/OUT        1        Serial Clock (from I2S master)
i2s_ws              IN/OUT        1        Word Select / LRCLK
i2s_data_in         IN            1        I2S audio data input (from I2S TX device)
i2s_data_out        OUT           1        I2S audio data output (to I2S RX device)
i2s_mck             IN/OUT        1        Master Clock (optional, per Coefficient K)
ptb_clk             IN            48       PTBclk bus from PTB clock service
ptb_locked          IN            1        PTB locked status from PTB service
```

### 11.2 DLL Interfaces

```
Interface           Direction     Description
---------           ---------     -----------
DLP_TX.indicateSlot IN            Slot notification from DLL mapper
DLP_TX.dataUnit     OUT           ASEP packet container to DLL
DLP_TX.yield        OUT           No-data response when no packet ready
DLP_RX.dataUnit     IN            Received ASEP packet from DLL demux
```

### 11.3 Register Interface

```
Interface           Direction     Description
---------           ---------     -----------
reg_bus             IN/OUT        OAM/local register access (domain 4/5 sub i)
reg_addr[14:0]      IN            Register address within domain
reg_wdata[15:0]     IN            Write data
reg_rdata[15:0]     OUT           Read data
reg_wen             IN            Write enable
```

---

## 12. RTL Submodule Decomposition

```
  +------------------------------------------------------------------+
  |               I2S ASEP Top (asep_i2s_top)                         |
  |                                                                  |
  |  +------------------------+  +--------------------------------+  |
  |  |  Config Mode Engine    |  |  Data Mode Engine              |  |
  |  |  (asep_i2s_cfg)        |  |  (asep_i2s_data)               |  |
  |  |                        |  |                                |  |
  |  |  - Write cmd builder   |  |  - SCK/MCK counter (mod-N)     |  |
  |  |  - Read cmd builder    |  |  - PTB timestamp capture       |  |
  |  |  - ACK/NACK parser     |  |  - Audio sample FIFO           |  |
  |  |  - Read resp parser    |  |  - Bit-depth encoder           |  |
  |  |  - CRC32 generator     |  |  - Data mode packet builder    |  |
  |  |  - Timeout watchdog    |  |  - CRC32 generator             |  |
  |  |  - packetID_cfg counter|  |  - packetID_data counter       |  |
  |  +----------+-------------+  +------+-------------------------+  |
  |             |                       |                            |
  |  +----------+----------+            |                            |
  |  |  Register Interface |            |                            |
  |  |  (asep_i2s_regs)    |<-----------+----------------------------|
  |  |                     |                                         |
  |  |  0200: I2S format   |  <-- bit depth, data fmt, num ch        |
  |  |  0201: sample rate  |  <-- audio sampling frequency           |
  |  |  0202: sync ctrl 1  |  <-- timing host, target clk, K        |
  |  |  0203: divisor N    |  <-- N for PTB capture period           |
  |  +--------------------++                                         |
  |                        |                                         |
  |  +---------------------+--------+                                |
  |  |  PTB Clock Reconstruction    |                                |
  |  |  (asep_i2s_ptb_recon)        |                                |
  |  |                              |                                |
  |  |  - S(n) receive queue        |                                |
  |  |  - M(n) = S(n)-S(n-1) calc  |                                |
  |  |  - PTB tick counter (M ticks)|                                |
  |  |  - Multiply-by-N output gen  |                                |
  |  +------------------------------+                                |
  |                                                                  |
  |  +------------------------------+                                |
  |  |  I2S Data Decoder            |                                |
  |  |  (asep_i2s_decoder)          |                                |
  |  |                              |                                |
  |  |  - data_length extraction    |                                |
  |  |  - sample ordering (P,Q)     |                                |
  |  |  - bit-depth unpacker        |                                |
  |  +------------------------------+                                |
  |                                                                  |
  |  +------------------------------+                                |
  |  |  ASEP Common Framing I/F     |                                |
  |  |  (asep_common_if)            |                                |
  |  |                              |                                |
  |  |  - stream type = 0x07        |                                |
  |  |  - packet header gen/parse   |                                |
  |  |  - DLP_TX/RX port            |                                |
  |  +------------------------------+                                |
  +------------------------------------------------------------------+
```

### 12.1 asep_i2s_cfg (Configuration Mode Engine)

Responsibilities:
- Build Write, Read, ACK/NACK, and Read Response command packets.
- Maintain cfg-mode packetID counter (1-120, wraps to 1).
- CRC32 computation over configuration packets (using same CRC32 polynomial as Section
  4.2.9).
- Timeout watchdog: configurable timer, on expiry inject NACK (all-zeros) response.
- Parse incoming configuration response packets and validate CRC32.

### 12.2 asep_i2s_data (Data Mode Engine)

Responsibilities:
- SCK/MCK pulse counter: counts to N, generates N-wrap trigger.
- On N-wrap: latch PTBclk[23:0] as start_time_ptb_stamp.
- Audio sample input FIFO: accepts I2S audio samples from the physical interface.
- Bit-depth encoder: packs raw audio samples to wire format per Table 7-82 to 7-87.
- Data mode packet builder: assembles header, data length, PTB stamp, audio data, footer.
- Data mode packetID counter (1-120, wraps to 1, independent of config counter).

### 12.3 asep_i2s_ptb_recon (PTB Clock Reconstruction)

Responsibilities:
- Receive S(n) PTB timestamps from incoming data mode packets.
- Compute M(n) = S(n) - S(n-1), handling rollover at the 24-bit boundary.
- Count M(n) PTB ticks from the local PTBclk (using ptb_clk input).
- After M ticks counted, generate N output clock periods to drive SCK/MCK.

IMPLEMENTATION ASSUMPTION: The reconstruction module needs to pipeline the M(n)
computation and count to overlap with incoming audio data. A sufficiently deep queue
(depth >= 2 S(n) timestamps) prevents starving the output clock.

### 12.4 asep_i2s_decoder (I2S Data Decoder)

Responsibilities:
- Extract data_length[9:0] and PTB timestamp from data mode packet header.
- Parse audio sample bytes according to configured bit depth (from register 4/5.i.0200).
- Restore P/Q ordering: for each sample time P, output channels Q=1..num_ch in order.
- Drive output to I2S RX physical interface.

### 12.5 asep_i2s_regs (Register Interface)

Responsibilities:
- Expose registers 4/5.i.0200 through 4/5.i.0203 to OAM and local access.
- Shadow copy for atomic read/write operations.
- Enforce write privilege (RID: Root node ID only).

---

## 13. Packet Layer Summary Diagrams

### 13.1 Configuration Mode Write Packet Layout

```
Byte     Content
------   -------
0        Common ASEP header byte0: stream type = 0x07 (bits 7:1), follow flag (bit 0)
1        Common ASEP header byte1: PTB timestamp mode (bits 1:0)
[2..5]   Optional: PTB ingress/presentation timestamp (if mode != 00)
m+1_HB   I2S packet header: mode=0 (bit 7), packetID (bits 6:0)
m+2_HB   Config command byte: cmd_mode=00 Write (bits 7:6), reserved (bits 5:4), bit_depth (3:0)
m+3_HB   data_format (6:4), reserved (3), num_channels (2:0)
m+4_HB   reserved (7:5), audio_sampling_freq (4:0)
m+5_HB   reserved (7), timing_host_sel (6), reserved (5), target_clk_sel (4), reserved (3:2), K[9:8] (1:0)
m+6_HB   K[7:0]
m+7_HB   N[15:8]
m+8_HB   N[7:0]
m-3_END  CRC32[31:24]
m-2_END  CRC32[23:16]
m-1_END  CRC32[15:8]
m_END    CRC32[7:0]
```

### 13.2 Data Mode Packet Layout (TX is Host)

```
Byte          Content
------        -------
0             Common ASEP header byte0: stream type = 0x07, follow flag
1             Common ASEP header byte1: PTB timestamp mode
[2..5]        Optional: PTB ingress timestamp
m+1_HB        I2S packet header: mode=1 (bit 7), packetID (bits 6:0)
m+2_HB        reserved (7:2), I2S data length[9:8] (1:0)
m+3_HB        I2S data length[7:0]
m+4_HB        Start time PTB stamp[23:16]
m+5_HB        Start time PTB stamp[15:8]
m+6_HB        Start time PTB stamp[7:0]
m+7_HB...     I2S audio data bytes (format per bit depth coding tables)
m-3_END       CRC32[31:24]
m-2_END       CRC32[23:16]
m-1_END       CRC32[15:8]
m_END         CRC32[7:0]
```

### 13.3 Configuration Mode ACK/NACK Packet Layout

```
Byte          Content
------        -------
0             Common ASEP header byte0: stream type = 0x07, follow flag
1             Common ASEP header byte1
m+1_HB        I2S packet header: mode=0, packetID (copy from Write cmd)
m+2_HB        Config command byte: cmd_mode=10 ACK/NACK (bits 7:6), ... ACK (bit 0)
m+3_HB..m+8_HB  Same payload as Write command (echo of parameters)
m-3_END..m_END  CRC32
```

---

## 14. Specification Facts vs Implementation Assumptions

### 14.1 Specification Facts (Direct Spec Citations)

| Label | Spec Reference | Claim |
|-------|---------------|-------|
| SF-01 | Section 7.10.1, p276 | I2S ASEP supports all common bit widths in mono, stereo, and TDM. |
| SF-02 | Section 7.10.1, p276 | I2S ASEP supports I2S timing master at either I2S TX or I2S RX. |
| SF-03 | Section 7.10.1, p276 | I2S ASEP codes audio frequency explicitly for most common values and supports derivation from PTB timestamps. |
| SF-04 | Section 7.10.1.1, p276 | ASE in master mode captures PTB timestamps every N cycles of SCK or MCK. |
| SF-05 | Equation 7-1, p277 | f_SCK or f_MCK = N / (S(n) - S(n-1)) [MHz], where S(n) is nth PTB timestamp. |
| SF-06 | Section 7.10.2, Table 7-76, p277 | I2S packetID valid range is 1-120; wraps from 120 to 1; values 0 and 121-127 reserved. |
| SF-07 | Section 7.10.2, Table 7-76, p277 | Two independent I2S packetID counters exist: one for config mode, one for data mode. |
| SF-08 | Section 7.10.2, p277 | Config mode: host increments packetID; slave copies host packetID into response. |
| SF-09 | Section 7.10.3.3, p278 | Read command has no payload. |
| SF-10 | Section 7.10.3.4, p278-279 | ACK/NACK payload is identical to Write payload except the ACK bit (m+2_HB bit 0). |
| SF-11 | Section 7.10.3.5, p279 | Read response payload is identical to Write command payload. |
| SF-12 | Section 7.10.3.5, p279 | Root node timeout treated as NACK (all zeros). |
| SF-13 | Section 7.10.4, p279-280 | Data mode packets are sent by ASEP on the side of I2S TX if TX is audio timing host. |
| SF-14 | Section 7.10.4, p280 | If I2S RX is host: TX side ASEP sends audio samples only; RX side ASEP sends timestamps only. |
| SF-15 | Section 7.10.4.1, p280 | Sample ordering: ascending channel index Q for all channels within one sample P, then ascending P. |
| SF-16 | Table 7-81, p280 | Data length field is 0 in a packet from I2S RX. |
| SF-17 | Section 3.5.8.1, Table 3-96 | 4/5.i.0200 bit depths: 0=8bit, 1=12bit, 2=16bit, 3=20bit, 4=24bit, 5=32bit. |
| SF-18 | Section 3.5.8.2, Table 3-97 | 4/5.i.0201 codes 0x00-0x13 define 20 standard audio sampling rates; others reserved. |
| SF-19 | Section 3.5.8.3, Table 3-98 | 4/5.i.0202: Coefficient K valid range 1-1023; 0 reserved. |
| SF-20 | Section 3.5.8.3, Table 3-99 | 4/5.i.0203: Divisor N valid range 1-16535; 0 reserved. |
| SF-21 | Section 7.10.1.1, p276 | f_StrmClk = M_vid,ptb / N_vid,ptb * f_PTB; 24-bit M/N allows 14.9 Hz resolution for clocks < 250 MHz. |

### 14.2 Informative Claims (Appendix F)

| Label | Source | Claim |
|-------|--------|-------|
| INF-01 | Appendix F, VI.a, p349 | Figure VI-1 illustrates the capture/reconstruction principle for I2S timing. |
| INF-02 | Appendix F, VI.a, p349-350 | Figure VI-2 shows recommended lowest N values for common audio rates across bit widths 24-512. |
| INF-03 | Image 19_PTB_clock_sync_I2S_nodes.png | ASA node2 counts N with MCK/SCK from I2S master, captures PTB stamp at each N-wrap, transmits S(n). ASA node1 computes M(n)=S(n)-S(n-1), counts M PTB ticks, multiplies by N to regenerate MCK/SCK output. |
| INF-04 | Image 10_PTB_leader_follower_sync.png | Capture side uses PTB Follower counter (250+Delta MHz); reconstruct side uses PTB Leader counter (250 MHz). |

### 14.3 Implementation Assumptions

| Label | Assumption |
|-------|-----------|
| IA-01 | The 24-bit PTB timestamp in the data mode packet (m+4_HB..m+6_HB) represents PTBclk[23:0], the lower 24 bits of the 48-bit PTBclk register. |
| IA-02 | The M(n) computation on the receiver must handle 24-bit rollover of PTB timestamps (PTBclk[23:0] max ~67ms at 4ns). |
| IA-03 | The packetID counter for data mode and config mode are independent hardware counters, not shared. |
| IA-04 | The timeout watchdog in the configuration mode engine must be parameterized by the application; the spec defines no fixed timeout value. |
| IA-05 | CRC32 uses the standard polynomial from Section 4.2.9 (same as other ASEP footers). |
| IA-06 | When timing host select (reg 4/5.i.0202 bit 14) = 0 (I2S TX is master), the TX-side ASA node runs the SCK/MCK capture engine; the RX-side runs the reconstruction engine. When = 1 (I2S RX is master), roles are reversed. |
| IA-07 | The coefficient K and divisor N programmed into registers must match the actual SCK/MCK-to-audio-rate ratio of the connected I2S device. Mismatch will cause clock reconstruction error. |
| IA-08 | Bit depth coding for 12-bit and 20-bit modes uses a nibble-aligned big-endian format (upper nibble of first byte reserved to 0). RTL should zero-extend on TX and mask on RX. |

---

## 15. Missing / Needs Verification

| Item | Issue | Action |
|------|-------|--------|
| NV-01 | Figure VI-2 N-divisor table | Full numeric content of recommended N values for all audio rates and bit widths is not machine-readable from available extraction. Verify from PDF pages 349-350 (image 11_I2S_SCK_frequency_table.png). |
| NV-02 | m+2_HB bit layout (Write cmd) | The spec chunk for Table 7-78 references bits 7:6 for command mode in the configuration command byte, but also places bit-depth at 3:0. The exact bit positions for fields in m+2_HB through m+5_HB need validation against PDF p278 for any reserved bit gaps. |
| NV-03 | ACK bit position in ACK/NACK | The spec says the ACK/NACK field differs from Write by one field. The extracted text shows m+2_HB bit 0 = ACK/NACK. Verify this is bit 0 and not another position (PDF p278-279). |
| NV-04 | PTB stamp width in data mode | Data mode packet uses 3-byte (24-bit) PTB timestamp. This may represent PTBclk[23:0] or a different 24-bit slice. Verify from PDF p280 (Table 7-81 annotation). |
| NV-05 | Stream clock formula context | Table 7-74 (ASEP eDP Stream Clock Packet) is referenced in section 7.10.1.1. Clarify whether this table is shared with eDP or is an I2S-specific variant. |
| NV-06 | N upper range vs K upper range | Register 4/5.i.0203 Divisor N max = 16535 (not 16384). The value 16535 is unusual (not a power of 2). Verify from PDF p86 Table 3-99. |
| NV-07 | Sample rate 0x11 (352.000 kHz) | Register 3-97 code 0x11 = 352.000 kHz. Audio standard rates of 352.8 kHz (8x 44.1) exist. Verify exact value (352.000 or 352.800). |
| NV-08 | Data mode: whether CRC32 covers the PTB timestamp | Table 7-81 footer: "Checksum over byte 0 to m-4". Does "byte 0" refer to the common ASEP header byte 0 or the I2S data mode header? Verify from PDF p280. |
| NV-09 | Appendix F examples | Spec section VI.a references I2S examples beyond the capture/reconstruction principle. Verify if additional numerical examples exist on PDF pages 349-350. |

---

## 16. Verification Plan

### 16.1 Unit Test Cases

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| VT-01 | Config mode Write command assembly | Verify all fields packed per Table 7-78; CRC32 matches; packetID=1 on first packet. |
| VT-02 | Config mode Read command | Verify header-only packet with cmd_mode=01; no payload bytes before footer. |
| VT-03 | Config mode ACK/NACK parsing | Verify ACK=1 and ACK=0 correctly set bit 0 of m+2_HB; remaining bytes echo Write payload. |
| VT-04 | Config mode packetID wraparound | Send 121 config write commands; verify packetID reaches 120, then wraps to 1 (not 121 or 0). |
| VT-05 | Config mode timeout -> NACK | Configure timeout for 3 schedule cycles; withhold slave response; verify root injects NACK=0. |
| VT-06 | Data mode packet, 8-bit depth | Verify 1 byte per sample-channel; channel ordering ascending Q; sample ordering ascending P. |
| VT-07 | Data mode packet, 16-bit depth | Verify 2 bytes per sample-channel, big-endian [15:8] then [7:0]. |
| VT-08 | Data mode packet, 24-bit depth | Verify 3 bytes per sample-channel, big-endian. |
| VT-09 | Data mode packet, 12-bit depth | Verify 2 bytes; upper nibble = 0; bits [11:8] in lower nibble of first byte. |
| VT-10 | Data mode packet, 20-bit depth | Verify 3 bytes; upper nibble = 0; bits [19:16] in lower nibble of first byte. |
| VT-11 | Data mode packet, 32-bit depth | Verify 4 bytes per sample-channel, big-endian. |
| VT-12 | Data mode data length field | Verify I2S data length[9:0] counts bytes correctly for stereo 16-bit at various sample batch sizes. |
| VT-13 | PTB timestamp capture (N-wrap) | Set N=64; count 64 SCK pulses; verify PTB stamp captured at wrap, placed in packet m+4..m+6. |
| VT-14 | PTB clock reconstruction | Feed two consecutive stamps S(1)=1000 and S(2)=1500 with N=64; verify M=500 PTB ticks counted and N=64 output pulses generated. |
| VT-15 | PTB timestamp 24-bit rollover | Set S(n-1)=0xFFFFF0 and S(n)=0x000010; verify M computed as 0x20 (correct rollover arithmetic). |
| VT-16 | CRC32 error detection (config) | Corrupt one byte in config packet; verify CRC32 mismatch flagged; error counted in 3.7.1. |
| VT-17 | CRC32 error detection (data) | Corrupt one audio sample byte; verify CRC32 mismatch flagged. |
| VT-18 | Data mode packetID independence | Run 5 data mode packets and 3 config mode packets interleaved; verify each counter increments independently. |
| VT-19 | RX-is-host data mode | Configure timing host select=1 (RX is host); verify TX sends data_length>0 with PTB stamp=0; verify RX sends data_length=0 with valid PTB stamp. |
| VT-20 | Register write propagation | Write bit depth=4 (24-bit) to 4/5.i.0200 via OAM CAD; verify next data mode packets use 24-bit coding. |
| VT-21 | ASEP stream type = 0x07 | Verify all I2S packets have stream type 0x07 in common ASEP header byte 0 bits 7:1. |
| VT-22 | Sample rate register codes | Read 4/5.i.0201 back for each of 20 defined sample rates; verify decode to correct kHz value. |

### 16.2 Integration Test Cases

| Test ID | Description |
|---------|-------------|
| IT-01 | Full audio streaming: TX-is-host 48kHz stereo 16-bit at 64 SCK cycles/sample, verify RX clock regeneration stays within 1 PTB tick of transmit SCK over 1000 samples. |
| IT-02 | Configuration handshake over live link: Write new bit depth; receive ACK; verify data mode packets switch to new depth on next packet. |
| IT-03 | DLL contention: I2S data mode shares DLL slots with another ASEP stream; verify no packet loss or packetID skips under 80% link utilization. |
| IT-04 | PTB resync during streaming: Force PTB offset correction during active I2S stream; verify PTB reconstruction on RX recovers within 2 PTB ticks. |

---

## 17. Dependencies and Related Documents

| Document | Relation |
|----------|---------|
| micro-architecture-asep-common-framing.md | Provides ASEP common header/footer, stream type 0x07 encoding, DLP_TX/RX framing |
| micro-architecture-ptb-clock-service.md | Provides PTBclk counter, PTB locked status, 4ns resolution tick, leader/follower roles |
| micro-architecture-dll-mapper-demux-core.md | Schedules I2S DLP_TX slots; routes incoming I2S packets to the I2S ASD |
| micro-architecture-register-model.md | Provides OAM CAD register access to 4/5.i.0200-0203; privilege enforcement |
| micro-architecture-oam-control-plane.md | OAM Write/Read CAD sequences used to configure I2S registers remotely |
| ASA Technical Specification v2.0 | Primary normative source; Section 7.10 pp276-282, Appendix F pp349-350 |
