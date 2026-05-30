# Micro-Architecture: ASEP GPIO Tunneling

## 1. Purpose and Scope

The ASEP GPIO module encapsulates the state of up to 16 digital GPIO pins into ASA
DLL containers for transparent transport over the ASA serial link. A single GPIO ASEP
instance (one Application Stream Encapsulator / Decapsulator pair on a DLP_TX /
DLP_RX port pair) carries all pins assigned to that ASEP.

The module has two orthogonal operating dimensions:

1. **Data transmission mode** -- either Full Sampling (FS) or Edge Position (EG)
   encoding of GPIO sample data, controlled by a single register bit.
2. **Configuration mode** -- a request/response packet exchange that propagates
   per-pin and per-ASEP register settings from the root node to the non-root node
   before data transmission begins.

This document defines the micro-architecture for RTL or golden-model implementation
of the GPIO ASEP encoder (ASE) and decoder (ASD), derived directly from ASA
Technical Specification v2.0.

Scope boundaries:
- IN SCOPE: GPIO ASEP packet assembly/disassembly for both configuration mode and
  data transmission mode; GPIO packet header; FS and EG data encoding; per-pin
  configuration tunneling (Mode 1 / Mode 2 write/read/ACK/NACK/read-response);
  CRC32 footer; register bit fields for 4/5.i.0200 and 4/5.i.0201-0216; TX and RX
  datapath FSMs; interface to ASEP common framing; interface to GPIO physical pins.
- OUT OF SCOPE: ASEP common framing header/footer (covered in
  micro-architecture-asep-common-framing.md); DLL mapper/demux scheduling; PTB
  clock generation; OAM control plane; PHY and PCS datapaths.

---

## 2. Source References

| Section | Title                                       | Pages     | Relevance                              |
|---------|---------------------------------------------|-----------|----------------------------------------|
| 7.8     | ASEP Format: GPIO                           | 256       | Top-level overview, pin capacity       |
| 7.8.1   | GPIO Packet Header                          | 256-257   | Table 7-42: header format              |
| 7.8.2   | GPIO Configuration Mode Packet              | 257       | Config mode overview, root/non-root roles |
| 7.8.2.1 | Configuration Command                       | 257-258   | Table 7-43: config command byte        |
| 7.8.2.2 | Mode 1 Write Command                        | 258       | Table 7-44: pin-by-pin config write    |
| 7.8.2.3 | Mode 2 Write Command                        | 258       | Table 7-45: sampling period/mode write |
| 7.8.2.4 | Read Command                                | 258-259   | No payload                             |
| 7.8.2.5 | Mode 1 ACK/NACK Command                     | 259       | Table 7-46: Mode 1 write response      |
| 7.8.2.6 | Mode 2 ACK/NACK Command                     | 259       | Table 7-47: Mode 2 write response      |
| 7.8.2.7 | Mode 1 Read Response Command                | 259       | Read response payload = Mode 1 Write   |
| 7.8.2.8 | Mode 2 Read Response Command                | 259-260   | Read response payload = Mode 2 Write   |
| 7.8.2.9 | Configuration Command Footer                | 260       | Table 7-48: CRC32 footer               |
| 7.8.3   | GPIO Data Transmission Mode Packet          | 260       | Table 7-49: data mode packet frame     |
| 7.8.3.1 | Full Sampling Data Formats                  | 260-263   | Tables 7-50 through 7-54               |
| 7.8.3.2 | Edge Position Data Format                   | 263-264   | Table 7-55                             |
| 3.5.6.1 | GPIO Sampling (4/5.i.0200)                  | 80-81     | Table 3-93: sampling mode/period reg   |
| 3.5.6.2 | GPIO Pin Configuration (4/5.i.0201-0216)    | 81-83     | Tables 3-94, 3-95: per-pin config regs |
| 7.3.2   | Common ASEP Format Basics per Header        | 235       | Table 7-4: byte 0, stream type 0x05    |
| 7.3.2.1 | ASEP PTB Time Stamps                        | 235-236   | Tables 7-5, 7-6: PTB timestamp bytes  |
| Appendix E | GPIO data mode examples (informative)    | 347-348   | Figures V-1, V-2                       |

Image references (docpdfmd/images/):
- `08_GPI_signal_UP_link_SG1_data_format.png` -- 1-GPI signal on UP link at SG1 using
  FS data payload format No.1 (4 TDD burst periods per packet, thinning ratio 1400).
  Shows how samples a(0)_1 through a(4)_4 are packed into bytes 1-8 of the GPIO
  payload, followed by CRC and dummy bytes.
- `09_GPI_signal_UP_SG1_EG_mode.png` -- 1-GPI signal on UP link at SG1 using EG mode.
  Shows signal section numbering (0..3 over 4 TDD burst periods), transition positions
  a(0), a(1), a(2), a(3), and how each 3-byte edge group maps to the wire encoding.
- Appendix E, Figure V-1 (PDF p347) -- FS data mode full waveform example at SG1.
- Appendix E, Figure V-2 (PDF p348) -- EG data mode full waveform example at SG1.

---

## 3. GPIO Tunneling Model

### 3.1 System Context

```
  Root Node                                ASA Link              Non-Root Node
  +--------------------+                                        +--------------------+
  | GPIO Application   |                                        | GPIO Application   |
  | Host (CPU / ECU)   |                                        | Sensor / Actuator  |
  +--------+-----------+                                        +---------+----------+
           |                                                              |
  +--------v-----------+   DLP_TX.dataUnit   +---------+   DLP_RX.dataUnit  +--------v-----------+
  | GPIO ASE           +-------------------->| DLL     +-------------------->| GPIO ASD           |
  | (Encapsulator)     |                     | (Mapper)|                     | (Decapsulator)     |
  +--------^-----------+                     +---------+                     +--------------------+
           |                                                                          |
           |   DLP_RX.dataUnit               +---------+   DLP_TX.dataUnit           |
  +--------+-----------+<--------------------+ DLL     |<----------------------------+
  | GPIO ASD (root)    |                     | (Demux) |                     | GPIO ASE (non-root)|
  +--------------------+                     +---------+                     +--------------------+
           |                                                                          |
  +--------v-----------+                                        +--------------------v+
  | GPIO Pins (root)   |                                        | GPIO Pins (non-root)|
  | (up to 16 per ASEP)|                                        | (up to 16 per ASEP) |
  +--------------------+                                        +---------------------+
```

SPEC FACT (7.8, p256): One GPIO ASEP handles up to 16 GPIO pins.

SPEC FACT (7.8, p256): The GPIO pin group state is coded in reference to
(configurable multiples of) the PTB tic, either in full sampling or edge transition
mode. Both modes use the nominal TDD cycle as a reference for grouping the data.

SPEC FACT (7.8, p256): Before sending data, the root node shall send configuration
mode packets to the non-root node.

SPEC FACT (7.3, Table 7-1): The ASEP stream type code for GPIO is 0x05. This value
occupies bits [7:1] of the common ASEP header byte 0.

### 3.2 Two-Phase Operation

```
  Phase 1: Configuration
  ----------------------
  Root ASE  ---[Config Write Mode 1 (pin params)]---> Non-Root ASD
  Root ASE  <--[ACK/NACK]---------------------------- Non-Root ASD
  Root ASE  ---[Config Write Mode 2 (sampling)]-----> Non-Root ASD
  Root ASE  <--[ACK/NACK]---------------------------- Non-Root ASD
  (Optional)
  Root ASE  ---[Config Read Mode 1 or Mode 2]-------> Non-Root ASD
  Root ASE  <--[Read Response]----------------------- Non-Root ASD

  Phase 2: Data Transmission
  --------------------------
  Non-Root ASE ---[GPIO Data Packet (FS or EG)]-----> Root ASD
  (GPI direction: leaf to root)
  Root ASE     ---[GPIO Data Packet (FS or EG)]-----> Non-Root ASD
  (GPO direction: root to leaf)
```

### 3.3 Full Sampling Mode vs Edge Position Mode

```
  Full Sampling (FS) Mode
  -----------------------
  - Every GPIO sample at each configured PTB-tic multiple is transmitted.
  - Pin state bits are packed into bytes according to the active pin count
    (1, 2, 3-4, 5-8, or 9-16 pins select different packing densities).
  - Suitable for signals with high transition density or where every sample
    matters (e.g., parallel digital bus).

  Edge Position (EG) Mode
  -----------------------
  - Only state transitions (0->1 or 1->0) are encoded.
  - Each transition is represented as a 3-byte group: initial pin state,
    GPIO pin ID, signal section (TDD cycle counter), and transition position
    within that section (in units of configured GPIO sampling period).
  - Suitable for low-density transition signals where EG coding gives
    significant bandwidth reduction over FS.
  - Transition position is a uint in range 0..6843 (SPEC FACT, Table 7-55).
```

IMPLEMENTATION ASSUMPTION: The selection between FS and EG mode is a static
configuration applied at startup via register 4/5.i.0200[13] (GPIO Sampling Mode).
Runtime mode switching while data packets are in flight is not specified and should
be avoided; an implementation may require a brief pause in data transmission when
switching modes.

---

## 4. ASEP Common Framing Integration

### 4.1 Common Header (Section 7.3.2)

All GPIO ASEP packets carry the common ASEP header before the GPIO-specific header.

```
Byte  Bit(s)  Name                       Description
----  ------  ----                       -----------
0     7:1     ASEP stream type           0x05 (GPIO) in bits [7:1]
0     0       Same-container follow flag 0: no further ASEP header in container
                                         1: another ASEP header follows in container
1     7:2     Reserved                   Set to 0
1     1:0     PTB time stamp             00: none  01: ingress  10: presentation
                                         11: user defined (4 bytes)
[2-5] 7:0     PTBingress[31:0]           Present only if PTB time stamp != 00
              or PTBpresent[31:0]        Lower 32 bits of PTBclk at ingress/presentation
```

SPEC FACT (7.3.2.1, p235-236): When PTB time stamp = 00, the maximum common header
byte index m_HB = 1. When ingress or presentation time stamp is used, m_HB = 5.

IMPLEMENTATION ASSUMPTION: For GPIO, ingress time stamping (mode 01) is the typical
choice. The ASE captures PTBclk at the moment the first GPIO sample of the packet
crosses the application interface. The timestamp precision equals one PTB tic (4 ns
at 250 MHz PTB clock).

### 4.2 CRC32 Footer (Section 7.8.2.9, Table 7-48; Section 4.2.9)

Both configuration mode packets and data transmission mode packets terminate with a
4-byte CRC32 footer.

```
Byte       Bit(s)  Name          Description
--------   ------  ----          -----------
m_END-3    7:0     CRC32[31:24]  Checksum over ASEP packet bytes 0 to (m_END-4)
m_END-2    7:0     CRC32[23:16]  where m_END is the last byte index of the entire
m_END-1    7:0     CRC32[15:8]   ASEP packet
m_END      7:0     CRC32[7:0]    CRC32 polynomial defined in Section 4.2.9
```

SPEC FACT (7.8.2.9, p260): Checksum covers all ASEP packet bytes 0 to (m_END - 4).

SPEC FACT (7.8.3, Table 7-49): Data transmission mode packets also carry the same
4-byte CRC32 footer (bytes m_END-3 to m_END), checksum over byte 0 to m_END-4.

---

## 5. GPIO Packet Header (Section 7.8.1, Table 7-42)

The GPIO packet header immediately follows the common ASEP header (at byte m_HB+1).
It is shared across both configuration mode and data transmission mode packets.

```
Byte      Bit(s)  Name               Description
--------  ------  ----               -----------
m_HB+1    7       GPIO packet mode   0: GPIO configuration mode
                                     1: GPIO data transmission mode
m_HB+1    6:0     GPIO packet ID     Starts at 1; incremented by 1 for every GPIO
                                     packet sent; wraps around from 127 to 1.
                                     0: reserved (shall not be used).
```

SPEC FACT (7.8.1, p256-257): GPIO packet IDs are a single sequence of IDs over all
packet modes (both configuration and data transmission packets share the same
incrementing counter).

IMPLEMENTATION ASSUMPTION: The 7-bit GPIO packet ID counter is maintained per-ASEP
instance (i.e., per DLP_TX). The counter is initialized to 1 at ASEP startup or
reset. The non-root ASD uses the packet ID for gap detection (missing packet
monitoring) but the spec does not define explicit gap error behavior for GPIO beyond
the general ASD error counter at register 3.7.1.

---

## 6. Configuration Mode Packets (Section 7.8.2)

### 6.1 Purpose and Transaction Model

SPEC FACT (7.8.2, p257): GPIO configuration mode packets transfer GPIO configuration
information from ASA registers in the ASA root node to ASA registers in the ASA
non-root node.

SPEC FACT (7.8.2, p257): The GPIO ASE in the ASA root node issues write/read
commands to the GPIO ASE/ASD in the non-root node. The GPIO ASE/ASD in the non-root
node responds with ACK/NACK to Write commands, and with Read Response to Read
commands.

```
  Transaction sequence (root -> non-root direction):

  Root ASE                                Non-Root ASD
  --------                                ------------
  Config Write Mode 1 (pin parameters) -->
                                       <-- Mode 1 ACK/NACK
  Config Write Mode 2 (sampling)       -->
                                       <-- Mode 2 ACK/NACK
  (Optional) Config Read Mode 1        -->
                                       <-- Mode 1 Read Response
  (Optional) Config Read Mode 2        -->
                                       <-- Mode 2 Read Response
```

### 6.2 Configuration Command Selector (Section 7.8.2.1, Table 7-43)

Byte m_HB+2 is the configuration command discriminator. It is present in every
configuration mode packet (bit 7 of m_HB+1 = 0 selects configuration mode).

```
Byte      Bit(s)  Name                      Description
--------  ------  ----                      -----------
m_HB+2    7       GPIO configuration mode   0: GPIO configuration mode 1 (pin params)
                                            1: GPIO configuration mode 2 (sampling)
m_HB+2    6:5     Configuration command     00: Write command mode
                  mode                      01: Read command mode
                                            10: ACK/NACK mode
                                            11: Read response mode
m_HB+2    4       (Mode 1 bit 4 = Reserved; Mode 2 bit 4:0 = GPIO Pin Sampling
                   Period [12:8]; interpretation depends on mode above)
```

SPEC FACT (7.8.2.1, p257-258): Table 7-43 encodes exactly 4 configuration command
modes (Write, Read, ACK/NACK, Read Response) plus 2 sub-modes (Mode 1 = pin config,
Mode 2 = sampling config) in byte m_HB+2.

### 6.3 Mode 1 Write Command (Section 7.8.2.2, Table 7-44)

Mode 1 Write carries pin-by-pin direction, default behavior, drive mode, and enable
configuration for up to 16 pins in a single packet.

```
Byte            Bit(s)  Name                   Description
--------------  ------  ----                   -----------
m_HB+2          7       GPIO configuration     0 (Mode 1)
                         mode
m_HB+2          6:5     Cmd mode               00 (Write)
m_HB+2          4       Reserved
m_HB+2          3:0     Number of pins         n = 0..15
                                                Number of pin configurations in
                                                this packet. Each pin occupies 2 bytes.

  Per-pin pair (for pin index 0..n-1), at byte offsets 2*n+1 and 2*n+2:

m_HB+2+2*n+1    7:4     Reserved
m_HB+2+2*n+1    3:0     GPIO pin ID            GPIO pin ID for this configuration entry
m_HB+2+2*n+2    7       Reserved
m_HB+2+2*n+2    6       GPIO signal direction  0: GPI (leaf ASE -> root ASD)
                                                1: GPO (root ASE -> leaf ASD)
                                                [See note on direction semantics below]
m_HB+2+2*n+2    5:3     GPO pin default /      See Section 3.5.6.2 / Table 3-94
                         reset behavior         000: floating
                                                001: pull-down to low state
                                                010: pull-up to high state
                                                111..011: user-defined
m_HB+2+2*n+2    2:1     GPO drive mode         00: push/pull mode
                                                01: open drain
                                                10, 11: user defined
m_HB+2+2*n+2    0       GPIO enable            0: disable  1: enable
```

SPEC FACT (7.8.2.2, p258): Configuration for each pin ID occupies two bytes; n = 0
to 15 pins per packet.

SPEC FACT (7.8.2.2, p258): Semantics for GPIO signal direction in the register
correspond to the local pin. The root node shall do direction conversion when sending
configuration (i.e., what is GPI from the leaf's local perspective appears as GPO in
the root's register view, and the root must flip the direction bit when sending).

### 6.4 Mode 2 Write Command (Section 7.8.2.3, Table 7-45)

Mode 2 Write sets the GPIO pin sampling period and sampling mode (FS or EG).

```
Byte      Bit(s)  Name                       Description
--------  ------  ----                       -----------
m_HB+2    7       GPIO configuration mode    0 (Mode 1 bit in cmd selector)
                                             Note: Mode 2 is selected when bit 7 = 1
                                             of the config command byte -- see 7.8.2.1
m_HB+2    6:5     Cmd mode                   00 (Write)
m_HB+2    4:0     GPIO Pin Sampling          GPIO Pin Sampling Period [12:8]
                  Period [12:8]              (see Section 3.5.6.1)
m_HB+3    7:0     GPIO Pin Sampling          GPIO Pin Sampling Period [7:0]
                  Period [7:0]               (see Section 3.5.6.1)
m_HB+4    7       GPIO Sampling Mode         0: Full sampling (FS mode)
                                             1: Edge position (EG mode)
                                             (see Section 3.5.6.1)
m_HB+4    6:0     Reserved
```

SPEC FACT (7.8.2.3, p258): Table 7-45 defines the Mode 2 Write command with a
13-bit GPIO Pin Sampling Period and a 1-bit GPIO Sampling Mode.

IMPLEMENTATION ASSUMPTION: The 13-bit GPIO Pin Sampling Period value is expressed in
multiples of PTB tics (one PTB tic = 4 ns at 250 MHz). A value of 0 is reserved; all
other values set the inter-sample interval. All GPIO IDs within the same ASE or ASD
shall apply the same thinning rate (Section 3.5.6.1).

### 6.5 Read Command (Section 7.8.2.4)

SPEC FACT (7.8.2.4, p258-259): There is no payload for the Read command. The Read
command is identified by Configuration command mode = 01 in byte m_HB+2[6:5].

### 6.6 Mode 1 ACK/NACK Command (Section 7.8.2.5, Table 7-46)

The Mode 1 ACK/NACK payload is identical to the Mode 1 Write command payload (same
byte layout) except for the following override at byte m_HB+2[4]:

```
Byte      Bit(s)  Name       Description
--------  ------  ----       -----------
m_HB+2    4       ACK/NACK   0: write failed (NACK)
                              1: write succeeded (ACK)
```

SPEC FACT (7.8.2.5, p259): The root node should implement a timeout watchdog
(depending on the schedule cycle for this ASEP and the application use case) and
treat a timeout as a NACK (all zeros).

### 6.7 Mode 2 ACK/NACK Command (Section 7.8.2.6, Table 7-47)

The Mode 2 ACK/NACK payload is identical to the Mode 2 Write command payload except
for the following override at byte m_HB+4[6]:

```
Byte      Bit(s)  Name       Description
--------  ------  ----       -----------
m_HB+4    6       ACK/NACK   0: write failed (NACK)
                              1: write succeeded (ACK)
```

SPEC FACT (7.8.2.6, p259): Same timeout / all-zeros NACK rule applies.

### 6.8 Mode 1 Read Response Command (Section 7.8.2.7)

SPEC FACT (7.8.2.7, p259): The payload of the Mode 1 Read Response command is
identical to the Mode 1 Write command payload (Section 7.8.2.2). The same timeout /
all-zeros NACK rule applies.

### 6.9 Mode 2 Read Response Command (Section 7.8.2.8)

SPEC FACT (7.8.2.8, p259-260): The payload of the Mode 2 Read Response command is
identical to the Mode 2 Write command payload (Section 7.8.2.3). The same timeout /
all-zeros NACK rule applies.

### 6.10 Configuration Mode Packet Layout Summary

```
  Configuration Mode Packet (generic layout, Mode 1 Write example):

  Byte offset from ASEP packet start (assuming m_HB = 1, no PTB timestamp):

  [0]         Common ASEP header byte 0 (stream type 0x05, follow flag)
  [1]         Common ASEP header byte 1 (PTB timestamp mode)
  [2] m_HB+1  GPIO packet header: GPIO packet mode=0, GPIO packet ID
  [3] m_HB+2  Config command byte: config mode (bit 7), cmd mode [6:5], data [4:0]

  Mode 1 Write specific:
  [4] m_HB+3  = m_HB+2+2*0+1 : pin[0] reserved[7:4], GPIO pin ID[3:0]
  [5] m_HB+4  = m_HB+2+2*0+2 : reserved[7], direction[6], default/reset[5:3],
                                 drive mode[2:1], enable[0]
  ... (repeat for each pin up to n=15)

  [last-3]    CRC32[31:24]
  [last-2]    CRC32[23:16]
  [last-1]    CRC32[15:8]
  [last]      CRC32[7:0]
```

---

## 7. Data Transmission Mode Packet (Section 7.8.3, Table 7-49)

### 7.1 Data Mode Packet Frame

The GPIO data transmission mode packet header immediately follows the GPIO packet
header (at byte m_HB+2, since bit 7 of m_HB+1 = 1 selects data transmission mode).

```
Byte        Bit(s)  Name                   Description
----------  ------  ----                   -----------
m_HB+2      7       GPIO data              0: Full sampling mode (FS)
                    transmission mode      1: Edge position mode (EG)
m_HB+2      6:2     Reserved
m_HB+2      1:0     GPIO data length       Upper 2 bits [9:8] of the count of GPIO
                    [9:8]                  sampling points (FS mode) or edge position
                                           groups (EG mode) in this packet.
m_HB+3      7:0     GPIO data length       Lower 8 bits [7:0] of the data length.
                    [7:0]                  Combined: 10-bit value = number of
                                           sampling time points or edge groups.
m_HB+4      7:0     GPIO pin IDs [15:8]    Bit-mask of active GPIO pin IDs.
                                           Bit position = GPIO pin ID.
                                           1: data payload valid for this pin ID.
                                           0: data payload not valid for this pin ID.
m_HB+5      7:0     GPIO pin IDs [7:0]     Lower 8 bits of the 16-bit pin ID mask.
m_HB+5+n    7:0     GPIO data              n >= 1; GPIO payload bytes.
(variable)          (variable)             Format depends on data transmission mode
                                           (FS or EG) and number of active pin IDs.
                                           See Sections 7.8.3.1 and 7.8.3.2.
m_END-3     7:0     CRC32[31:24]           Checksum over byte 0 to m_END-4
m_END-2     7:0     CRC32[23:16]           see Section 4.2.9
m_END-1     7:0     CRC32[15:8]
m_END       7:0     CRC32[7:0]
```

SPEC FACT (7.8.3, p260): GPIO data length is the count of GPIO sampling points #t
(FS mode) or edge position groups (EG mode) contained in this packet.

SPEC FACT (7.8.3, p260): GPIO pin IDs field is a 16-bit bitmask where each bit
position equals the corresponding GPIO pin ID (bit 0 = pin 0 ... bit 15 = pin 15).
Value 1 means the data payload is valid for that GPIO pin ID.

---

## 8. Full Sampling Data Formats (Section 7.8.3.1, Tables 7-50 through 7-54)

### 8.1 Overview

SPEC FACT (7.8.3.1, p260): For the full sampling data format, 5 different codings,
each covering a range of pin count, are defined. The coding shall fit the number of
valid GPIO pin IDs. The small capital variables 'a' through 'p' correspond to the
ordered ascending set of active GPIO pin IDs.

SPEC FACT (7.8.3.1, p261): The first sample of a packet shall always correspond to
the beginning of a TDD cycle, such that there are always the same number of samples
in a packet for a given GPIO pin sampling period.

### 8.2 Coding Selection by Active Pin Count

```
  Active GPIO Pin Count   Bytes per Sampling Time Point   Table
  ---------------------   ----------------------------    -----
  9 to 16                 2 bytes (16 bits, 1 per pin)    7-50
  5 to 8                  1 byte  (8 bits, 1 per pin)     7-51
  3 to 4                  1 byte  (2 time points packed)  7-52
  2                       1 byte  (4 time points packed)  7-53
  1                       1 byte  (8 time points packed)  7-54
```

IMPLEMENTATION ASSUMPTION: The pin count used to select the coding is the number of
bit positions set to 1 in the GPIO pin IDs mask (bytes m_HB+4 and m_HB+5 of the data
packet header). The encoder counts active bits at packet assembly time.

### 8.3 FS Coding for 9-16 Active Pins (Table 7-50)

Each sampling time point #t occupies 2 consecutive bytes. Bytes are indexed by k
(k = 1 to n-1 for n time points, increasing k = later sampling time).

```
Byte          Bit   Signal
-----------   ----  ------
m_HB+5+k      7     GPIO ID "a" @ sampled time #t
m_HB+5+k      6     GPIO ID "b" @ sampled time #t
m_HB+5+k      5     GPIO ID "c" @ sampled time #t
m_HB+5+k      4     GPIO ID "d" @ sampled time #t
m_HB+5+k      3     GPIO ID "e" @ sampled time #t
m_HB+5+k      2     GPIO ID "f" @ sampled time #t
m_HB+5+k      1     GPIO ID "g" @ sampled time #t
m_HB+5+k      0     GPIO ID "h" @ sampled time #t
m_HB+5+k+1    7     GPIO ID "i" @ sampled time #t
m_HB+5+k+1    6     GPIO ID "j" @ sampled time #t  (valid only if >=10 active pins)
m_HB+5+k+1    5     GPIO ID "k" @ sampled time #t  (valid only if >=11 active pins)
m_HB+5+k+1    4     GPIO ID "l" @ sampled time #t  (valid only if >=12 active pins)
m_HB+5+k+1    3     GPIO ID "m" @ sampled time #t  (valid only if >=13 active pins)
m_HB+5+k+1    2     GPIO ID "n" @ sampled time #t  (valid only if >=14 active pins)
m_HB+5+k+1    1     GPIO ID "o" @ sampled time #t  (valid only if >=15 active pins)
m_HB+5+k+1    0     GPIO ID "p" @ sampled time #t  (valid only if =16 active pins)
```

SPEC FACT (7.8.3.1, p261): Sample data on bits "j" to "p" is only valid for 10 to
16 pins coded; otherwise invalid. k ranges between 1 and n-1. Larger k values
contain later sampling times.

### 8.4 FS Coding for 5-8 Active Pins (Table 7-51)

Each sampling time point #t occupies 1 byte. k ranges from 1 to n.

```
Byte        Bit   Signal
---------   ----  ------
m_HB+5+k    7     GPIO ID "a" @ sampled time #t
m_HB+5+k    6     GPIO ID "b" @ sampled time #t
m_HB+5+k    5     GPIO ID "c" @ sampled time #t
m_HB+5+k    4     GPIO ID "d" @ sampled time #t
m_HB+5+k    3     GPIO ID "e" @ sampled time #t
m_HB+5+k    2     GPIO ID "f" @ sampled time #t  (valid only if >=6 active pins)
m_HB+5+k    1     GPIO ID "g" @ sampled time #t  (valid only if >=7 active pins)
m_HB+5+k    0     GPIO ID "h" @ sampled time #t  (valid only if =8 active pins)
```

SPEC FACT (7.8.3.1, p261): Sample data on bits "f" to "h" only valid for 6 to 8
pins coded; otherwise invalid. k ranges 1 to n; larger k = later sampling times.

### 8.5 FS Coding for 3-4 Active Pins (Table 7-52)

Two consecutive sampling time points (#t and #t+1) are packed into 1 byte.
k ranges from 1 to n.

```
Byte        Bit   Signal
---------   ----  ------
m_HB+5+k    7     GPIO ID "a" @ sampled time #t
m_HB+5+k    6     GPIO ID "b" @ sampled time #t
m_HB+5+k    5     GPIO ID "c" @ sampled time #t
m_HB+5+k    4     GPIO ID "d" @ sampled time #t  (valid only if =4 active pins)
m_HB+5+k    3     GPIO ID "a" @ sampled time #t+1
m_HB+5+k    2     GPIO ID "b" @ sampled time #t+1
m_HB+5+k    1     GPIO ID "c" @ sampled time #t+1
m_HB+5+k    0     GPIO ID "d" @ sampled time #t+1  (valid only if =4 active pins)
```

SPEC FACT (7.8.3.1, p262): Sample data on "d" is only valid for 4 pins coded;
otherwise invalid. k ranges 1 to n; larger k = later sampling times.

### 8.6 FS Coding for 2 Active Pins (Table 7-53)

Four consecutive sampling time points (#t, #t+1, #t+2, #t+3) packed into 1 byte.
k ranges from 1 to n.

```
Byte        Bit   Signal
---------   ----  ------
m_HB+5+k    7     GPIO ID "a" @ sampled time #t
m_HB+5+k    6     GPIO ID "b" @ sampled time #t
m_HB+5+k    5     GPIO ID "a" @ sampled time #t+1
m_HB+5+k    4     GPIO ID "b" @ sampled time #t+1
m_HB+5+k    3     GPIO ID "a" @ sampled time #t+2
m_HB+5+k    2     GPIO ID "b" @ sampled time #t+2
m_HB+5+k    1     GPIO ID "a" @ sampled time #t+3
m_HB+5+k    0     GPIO ID "b" @ sampled time #t+3
```

SPEC FACT (7.8.3.1, p262): 2 pins at sampled time #t, #t+1, #t+2 and #t+3 per byte.

### 8.7 FS Coding for 1 Active Pin (Table 7-54)

Eight consecutive sampling time points (#t through #t+7) packed into 1 byte.
k ranges from 1 to n.

```
Byte        Bit   Signal
---------   ----  ------
m_HB+5+k    7     GPIO ID "a" @ sampled time #t
m_HB+5+k    6     GPIO ID "a" @ sampled time #t+1
m_HB+5+k    5     GPIO ID "a" @ sampled time #t+2
m_HB+5+k    4     GPIO ID "a" @ sampled time #t+3
m_HB+5+k    3     GPIO ID "a" @ sampled time #t+4
m_HB+5+k    2     GPIO ID "a" @ sampled time #t+5
m_HB+5+k    1     GPIO ID "a" @ sampled time #t+6
m_HB+5+k    0     GPIO ID "a" @ sampled time #t+7
```

SPEC FACT (7.8.3.1, p263): 1 pin at sampled times #t through #t+7 per byte.
Larger k = later sampling times.

### 8.8 FS Packing Efficiency Summary

```
  Active Pins    Samples per Byte   Bytes per Sample   Bits per Pin per Sample
  -----------    ----------------   ----------------   -----------------------
  1              8                  1/8                1 bit
  2              4 (2 pins)         1/4                1 bit
  3-4            2 (3-4 pins)       1/2                1 bit
  5-8            1 (5-8 pins)       1                  1 bit
  9-16           1 (9-16 pins)      2                  1 bit
```

All FS codings maintain exactly 1 bit per pin per sample point. The byte packing
efficiency increases as fewer pins are active, using time-domain multiplexing within
each byte.

### 8.9 Appendix E FS Mode Example (INFORMATIVE)

INFORMATIVE (Appendix E, Figure V-1, p347): The FS data mode example shows 1 GPI
signal on UP link at SG1 using Data payload format No. 1 (1-pin coding, Table 7-54).
The thinning ratio (GPIO Pin Sampling Period) is set to 1400 PTB tics. The signal
spans 4 TDD burst periods (27.376 us each). The remainder of 6844 divided by 1400
is 1244. The GPIO packet carries samples a(0)_1, a(1)_1, a(2)_1, a(3)_1, a(4)_1
from the 1st TDD burst period in byte 1, and so on. The ASEP packet structure is:
Container Header | GPIO Header | GPIO payload (bytes 1-8 with samples from TDD
bursts 1-4) | CRC (4 bytes) | dummy bytes.

INFORMATIVE (image 08_GPI_signal_UP_link_SG1_data_format.png): The diagram confirms
that for 1 GPI signal in FS mode at SG1 (thinning = 1400):
- PTB ingress time (1) marks the start of packet sampling.
- Sampling data period = 1400 PTB tics.
- Remainder = 6844 mod 1400 = 1244 (non-full period samples at TDD burst boundary).
- Samples within each TDD burst period are labeled a(offset)_burst.
- The ASEP packet groups 4 TDD burst periods with 5 samples per burst = 20 samples.
- Each byte in the payload carries 8 sequential samples of pin "a".

---

## 9. Edge Position Data Format (Section 7.8.3.2, Table 7-55)

### 9.1 Edge Group Encoding

SPEC FACT (7.8.3.2, p263): The edge position is coded in groups of 3 bytes. Edge
positions are firstly packed in ascending order of transition position, and secondly
in ascending order of GPIO pin ID.

Each 3-byte group encodes one state transition on one GPIO pin:

```
Byte          Bit(s)  Name                     Description
-----------   ------  ----                     -----------
m_HB+5+k      7       Initial data             Pin state at beginning of signal
                                               section (0 or 1).
m_HB+5+k      6:3     GPIO pin ID              GPIO pin ID of this edge position
                                               group (0..15).
m_HB+5+k      2:0     Signal section [5:3]     Upper 3 bits of the 6-bit signal
                                               section counter (TDD cycle counter).
                                               uint; counter for TDD cycle of sampled
                                               data; rolls over to 0.
m_HB+5+k+1    7:5     Signal section [2:0]     Lower 3 bits of the 6-bit signal
                                               section counter.
m_HB+5+k+1    4:0     Transition position      Upper 5 bits [12:8] of the 13-bit
                       [12:8]                   transition position.
                                               uint, valid range 0..6843.
                                               Marks the position of a transition
                                               (0->1 or 1->0) of sampled data within
                                               the signal section in units of the
                                               configured GPIO sampling period.
m_HB+5+k+2    7:0     Transition position      Lower 8 bits [7:0] of the 13-bit
                       [7:0]                    transition position.
```

SPEC FACT (7.8.3.2, p263-264): Transition position valid range is 0 to 6843. The
signal section is a counter for the TDD cycle of sampled data; it rolls over to 0.

IMPLEMENTATION ASSUMPTION: The signal section counter increments once per TDD burst
period within the sampling window covered by one GPIO data packet. The 6-bit field
allows up to 64 distinct TDD cycles per packet before roll-over, giving a maximum
observable window of 64 x TDD_burst_period (64 x 27.376 us = 1.752 ms at SG1).

IMPLEMENTATION ASSUMPTION: k increments by 3 for each successive edge group (each
group is exactly 3 bytes). The total number of edge groups in the packet equals the
GPIO data length field (m_HB+2[1:0] concat m_HB+3[7:0]) in the data mode header.

### 9.2 EG Ordering Rules

SPEC FACT (7.8.3.2, p263): Edge positions shall be packed:
1. First in ascending order of transition position (within a signal section).
2. Second in ascending order of GPIO pin ID (when two pins have the same position).

IMPLEMENTATION ASSUMPTION: The EG encoder must sort pending transitions at the end
of each sampling window before inserting them into the outgoing packet. A simple
priority queue indexed by (signal_section, transition_position, gpio_pin_id) is
sufficient.

### 9.3 EG vs FS Bandwidth Comparison

```
  Example: 1 GPI pin, SG1, sampling period = 1400 tics, 4 TDD bursts per packet.

  Samples per TDD burst = 6844 / 1400 = ~4.89, use 5.
  Samples per packet = 4 bursts x 5 = ~20 samples.

  FS mode: ceil(20/8) = 3 bytes per pin per packet.
  EG mode: 3 bytes per TRANSITION (regardless of sample count).

  For a static pin (0 transitions):   FS = 3 bytes,  EG = 0 bytes (no groups).
  For a pin with 1 transition:         FS = 3 bytes,  EG = 3 bytes.
  For a pin with 4 transitions:        FS = 3 bytes,  EG = 12 bytes.

  EG is advantageous only when transition count < FS payload byte count.
  For multi-pin cases, break-even depends on pin count and transition density.
```

### 9.4 Appendix E EG Mode Example (INFORMATIVE)

INFORMATIVE (Appendix E, Figure V-2, p348): The EG data mode example shows 1 GPI
signal on UP link at SG1 using EG mode with the same 4 TDD burst periods. The signal
section position runs 0..3 across 4 TDD burst periods. Four transitions are recorded:
a(0), a(1), a(2), a(3). The 12-byte edge position payload (4 groups of 3 bytes)
encodes: initial state, pin ID "a", signal section number, and transition position
within that section.

INFORMATIVE (image 09_GPI_signal_UP_SG1_EG_mode.png): The example byte stream for
signal "a" shows 4 edge groups encoded as follows (bit fields per Table 7-55):
- Group a(0): byte1={0, a, 0, 0, 0}, byte2={0, 0, 0, 0, 0}, byte3={0x00}
  (initial=0, pin=a, section=0, position=0)
- Group a(1): byte1={1, a, 0, 0, 0}, byte2={1, 0, 0, 0, 4}, byte3={0x00}
  (initial=1, pin=a, section=0, position=4)
- Group a(2): byte1={0, a, 0, 0, 1}, byte2={0, 0, 0, 0, ?}, byte3={?}
  (transition from 1 to 0 in section 1)
- Group a(3): byte1={1, a, 0, 0, 1}, byte2={1, 0, 0, 0, ?}, byte3={?}
  (transition from 0 to 1 in section 1 or later)
  [Exact position values from image are illustrative; authoritative source is Table 7-55]

---

## 10. Register Bit Fields

### 10.1 Register 4/5.i.0200: GPIO Sampling (Section 3.5.6.1, Table 3-93)

Address: 4/5.i.0200 (Domain 4 = ASE, Domain 5 = ASD; i = DLP instance index)

```
Bit(s)  Name                 R/W   Access  Privilege  Description
------  ----                 ---   ------  ---------  -----------
15:14   Reserved             -     -       -          Reserved; set to 0
13      GPIO Sampling Mode   RW    O       RID        0: Full sampling transmission
                                                         mode (FS mode)
                                                      1: Edge position transmission
                                                         mode (EG mode)
12:0    GPIO Pin Sampling    RW    O       RID        uint; pin sampling period in
        Period                                         multiples of PTB tics.
                                                      0: reserved (do not use).
                                                      All other values: active period.
                                                      Applies to both FS and EG modes.
```

SPEC FACT (3.5.6.1, p80-81, Table 3-93): All GPIO IDs included in the same ASE or
ASD shall apply to the same thinning rate (GPIO pin sampling period). The register is
read/write, accessible via OAM channel (Access = O), with Root nodeID privilege only
(Privilege = RID).

IMPLEMENTATION ASSUMPTION: At link startup, the GPIO Sampling Period register is
0x0000 (reserved value). The root OAM layer must write a valid non-zero value via
OAM CAD before GPIO data transmission begins. An implementation may assert a
configuration-not-ready flag until GPIO Sampling Period != 0.

### 10.2 Registers 4/5.i.0201 - 4/5.i.0216: GPIO Pin Configuration (Section 3.5.6.2, Tables 3-94, 3-95)

There are 16 configuration registers, one per GPIO pin (pin IDs 0-15), all sharing
the same bit field layout.

```
Bit(s)  Name                    R/W   Access  Privilege  Description
------  ----                    ---   ------  ---------  -----------
15:8    Reserved                -     -       -          Reserved; set to 0
7       Pin availability        RO    O       RID        0: pin not available
                                                         1: pin available
                                                         [Hardware-determined; RO]
6       GPIO signal direction   RW    O       RID        0: GPI (leaf ASE -> root ASD)
                                                         1: GPO (root ASE -> leaf ASD)
5:3     GPIO pin default /      RW    O       RID        Only valid for available pins.
        reset behavior                                   000: floating
                                                         001: pull-down to low state
                                                         010: pull-up to high state
                                                         111..011: user-defined
                                                         Shall be asserted during
                                                         Power-On / Init state.
                                                         INFORMATIVE: behavior should
                                                         be asserted within 10 ms of
                                                         stable power supply.
2:1     GPO drive mode          RW    O       RID        Only valid for available output
                                                         pins.
                                                         00: push/pull mode
                                                         01: open drain
                                                         10, 11: user defined
0       GPIO enable             RW    O       RID        0: disable
                                                         1: enable
```

SPEC FACT (3.5.6.2, p81-83, Table 3-94): 16 configuration registers, one for each
of the maximum number of GPIO pins per ASEP on one DLP_TX/DLP_RX.

Register Address to GPIO Pin ID Mapping (Table 3-95):

```
  Register Address   GPIO Pin ID    Register Address   GPIO Pin ID
  ----------------   -----------    ----------------   -----------
  4/5.i.0201         Pin 0          4/5.i.0209         Pin 8
  4/5.i.0202         Pin 1          4/5.i.0210         Pin 9
  4/5.i.0203         Pin 2          4/5.i.0211         Pin 10
  4/5.i.0204         Pin 3          4/5.i.0212         Pin 11
  4/5.i.0205         Pin 4          4/5.i.0213         Pin 12
  4/5.i.0206         Pin 5          4/5.i.0214         Pin 13
  4/5.i.0207         Pin 6          4/5.i.0215         Pin 14
  4/5.i.0208         Pin 7          4/5.i.0216         Pin 15
```

SPEC FACT (3.5.6.2, p82, Table 3-95): This is the normative mapping between GPIO
pin IDs 0-15 and register addresses 4/5.i.0201 through 4/5.i.0216.

### 10.3 Register Summary

```
  Register       Address Range       Purpose
  ----------     -----------------   -------
  GPIO Sampling  4/5.i.0200          Sampling period (13 bits), sampling mode (FS/EG)
  GPIO Pin 0     4/5.i.0201          Pin 0: availability, direction, default, drive, enable
  GPIO Pin 1     4/5.i.0202          Pin 1: same layout
  ...            ...                 ...
  GPIO Pin 15    4/5.i.0216          Pin 15: same layout
```

Note: The "4/5" prefix means the register exists in both the ASE domain (4) and ASD
domain (5). The "i" index selects the DLP instance. One DLP instance = one GPIO ASEP
instance = up to 16 GPIO pins.

---

## 11. TX and RX Datapath Flows

### 11.1 GPIO ASE TX Flow (Encoder)

```
  Application / GPIO Pin Interface
           |
           | [GPIO pin state samples, clocked at GPIO Sampling Period]
           v
  +-------------------+
  | Pin Sampler       | -- Samples all enabled GPIO pins at each PTB-tic multiple
  |                   |    defined by GPIO Pin Sampling Period register.
  | FS mode: capture  |    Accumulates samples into a per-TDD-burst buffer.
  | pin state bitmask |
  | EG mode: detect   |    EG mode: detect rising/falling edges; record
  | rising/falling    |    (signal_section, transition_position, pin_id, initial).
  +-------------------+
           |
           v
  +-------------------+
  | Packet Builder    | -- When sufficient samples/edges accumulated (one GPIO
  |                   |    packet interval = configurable multiples of TDD cycle),
  | 1. Build common   |    assemble output packet:
  |    ASEP header    |    1. Common ASEP header (byte 0: type 0x05; byte 1: PTB mode)
  | 2. GPIO pkt hdr   |    2. Optional PTB ingress timestamp (4 bytes)
  | 3. Data mode hdr  |    3. GPIO packet header (mode=1, packet ID++)
  | 4. GPIO payload   |    4. Data mode header (FS/EG mode, data length, pin ID mask)
  | 5. CRC32 footer   |    5. GPIO payload (FS or EG encoded)
  +-------------------+    6. CRC32 footer
           |
           v
  DLP_TX.dataUnit()   -- Push assembled ASEP packet bytes to DLL when slot indicated
```

### 11.2 GPIO ASD RX Flow (Decoder)

```
  DLP_RX.dataUnit()   -- Receive ASEP packet bytes from DLL
           |
           v
  +-------------------+
  | Fragment Reassembler| -- Re-assembles ASEP packet from one or more DLL containers
  |                   |    using ASEP packet boundary position (per Section 7.3.1).
  +-------------------+
           |
           v
  +-------------------+
  | CRC32 Checker     | -- Verify CRC32 over bytes 0 to (m_END-4).
  |                   |    On failure: increment ASD error counter (register 3.7.1).
  +-------------------+
           |
           v
  +-------------------+
  | GPIO Packet Header| -- Extract GPIO packet mode (config/data) and packet ID.
  | Parser            |    Check for missing packet IDs (gap detection).
  +-------------------+
           |
     +-----+------+
     |             |
   mode=0        mode=1
  (config)      (data)
     |             |
     v             v
  +----------+  +--------------------+
  | Config   |  | Data Mode Header   |
  | Command  |  | Parser             |
  | Handler  |  |                    |
  |          |  | Extract: FS/EG,    |
  | Write ->  |  | data length,       |
  | update    |  | pin ID mask        |
  | local     |  +--------------------+
  | registers |          |
  |           |     +----+----+
  | ACK/NACK  |     |         |
  | -> send   |   FS mode   EG mode
  | response  |     |         |
  +----------+  +--------+ +--------+
                | FS      | | EG     |
                | Decoder | | Decoder|
                |         | |        |
                | Extract | | Extract|
                | samples | | edge   |
                | per pin | | groups |
                | from    | | (3B    |
                | packed  | | each)  |
                | bytes   | |        |
                +----+----+ +---+----+
                     |          |
                     v          v
              GPIO Pin Output / Application Interface
```

### 11.3 Config Mode TX/RX Flow

```
  Root ASE (Config TX)                     Non-Root ASD (Config RX)
  --------------------                     ------------------------
  1. Read local registers:
     - 4/5.i.0201-0216 (per-pin config)
     - 4/5.i.0200 (sampling params)

  2. Build Mode 1 Write packet:
     - common ASEP header (type 0x05)
     - GPIO pkt header (mode=0, ID++)
     - config cmd byte (mode1, write)
     - n pin configuration pairs
     - CRC32 footer
                           ----------------------->
                                                     3. Parse packet; update
                                                        local pin config registers
                                                        (4/5.i.0201-0216)
                                                     4. Send Mode 1 ACK/NACK
                           <-----------------------
  5. Timeout watchdog:
     If no ACK/NACK within
     schedule-dependent window:
     treat as NACK (all zeros)

  6. Build Mode 2 Write packet:
     - common ASEP header
     - GPIO pkt header (mode=0, ID++)
     - config cmd byte (mode2, write)
     - sampling period [12:0]
     - sampling mode (FS/EG)
     - CRC32 footer
                           ----------------------->
                                                     7. Parse packet; update
                                                        register 4/5.i.0200
                                                     8. Send Mode 2 ACK/NACK
                           <-----------------------
  9. Begin data transmission
```

---

## 12. Interface to ASEP Common Framing

```
  Signal / Interface          Direction   Description
  ------------------          ---------   -----------
  asep_tx_data[7:0]           OUT->DLL    ASEP packet byte stream to DLL container
  asep_tx_valid               OUT->DLL    Packet byte valid
  asep_tx_sop                 OUT->DLL    Start of ASEP packet
  asep_tx_eop                 OUT->DLL    End of ASEP packet
  asep_rx_data[7:0]           IN<-DLL     ASEP packet byte stream from DLL container
  asep_rx_valid               IN<-DLL     Packet byte valid
  asep_rx_sop                 IN<-DLL     Start of ASEP packet (after reassembly)
  asep_rx_eop                 IN<-DLL     End of ASEP packet
  asep_rx_crc_ok              IN<-DLL     CRC32 pass/fail (or computed by GPIO module)
  dlp_tx_indicate_slot        IN<-DLL     DLL signals available TX slot; triggers
                                          packet builder to start next GPIO packet
  dlp_tx_slot_size[15:0]      IN<-DLL     Size of available TX slot in bytes
  dlp_rx_data_valid           IN<-DLL     New reassembled ASEP packet ready
  ptb_clk[31:0]               IN<-PTB     Lower 32 bits of PTBclk for ingress timestamp
  asep_stream_type[6:0]       STATIC      0x05 (GPIO); wired constant in ASE byte 0
```

IMPLEMENTATION ASSUMPTION: The GPIO ASE module interfaces to the ASEP common framing
layer which handles DLL container fragmentation/reassembly (Section 7.3.1). The GPIO
module does not directly manage container boundaries; it presents complete ASEP
packets. The common framing layer inserts the ASEP packet boundary position bytes
(per Table 7-2).

---

## 13. Interface to Physical GPIO Pins

```
  Signal                   Direction   Description
  ------                   ---------   -----------
  gpio_pin_in[15:0]        IN          Physical GPIO input pin states; one bit per
                                       GPIO pin ID 0-15. Registered on each
                                       PTB-tic multiple defined by GPIO Sampling Period.
  gpio_pin_out[15:0]       OUT         Physical GPIO output pin states for GPO pins;
                                       driven from received GPIO data payload.
  gpio_pin_oe[15:0]        OUT         Output enable per pin; derived from
                                       GPIO signal direction register bit [6] of
                                       4/5.i.0201-0216.
  gpio_pin_enable[15:0]    OUT         Per-pin enable; derived from register bit [0]
                                       of 4/5.i.0201-0216 (GPIO enable).
  gpio_pin_drv_mode[1:0]   OUT         Drive mode for GPO pins; from register bits
  (per pin)                            [2:1] of 4/5.i.0201-0216 (GPO drive mode).
  gpio_pin_default[2:0]    OUT         Default/reset state per pin; from register
  (per pin)                            bits [5:3] of 4/5.i.0201-0216.
  gpio_sample_clk          IN          Sample clock; derived from PTBclk and GPIO
                                       Pin Sampling Period (4/5.i.0200[12:0]).
  gpio_pin_avail[15:0]     IN          Hardware-determined pin availability; feeds
                                       register bit [7] of 4/5.i.0201-0216 (RO).
```

IMPLEMENTATION ASSUMPTION: The gpio_sample_clk is generated by a configurable
divider/counter that counts PTB tics and fires a sample pulse every GPIO Pin Sampling
Period tics. The counter resets to 0 at the beginning of each TDD burst period to
ensure the first sample of each packet aligns to TDD cycle start (per SPEC FACT,
Section 7.8.3.1, p261).

IMPLEMENTATION ASSUMPTION: GPO pin output latency (from receiving GPIO data packet
to GPIO pin state change) is bounded by one GPIO packet interval plus DLL container
transport latency. The exact value is implementation-dependent and must be
characterized per application.

---

## 14. RTL Submodules

### 14.1 Submodule Hierarchy

```
  gpio_asep_top
  |
  +-- gpio_ase_tx                   GPIO Application Stream Encapsulator (TX side)
  |   |
  |   +-- gpio_pin_sampler          Sample GPI pins at GPIO Sampling Period rate
  |   +-- gpio_fs_encoder           Full Sampling mode: pack samples into payload bytes
  |   +-- gpio_eg_encoder           Edge Position mode: detect and encode transitions
  |   +-- gpio_pkt_builder          Assemble ASEP packet (header + payload + footer)
  |   +-- gpio_crc32_gen            CRC32 generation (per Section 4.2.9 polynomial)
  |   +-- gpio_pkt_id_counter       7-bit GPIO packet ID counter (1..127, wraps at 127->1)
  |
  +-- gpio_asd_rx                   GPIO Application Stream Decapsulator (RX side)
  |   |
  |   +-- gpio_pkt_parser           Parse GPIO packet header, detect mode, check ID gap
  |   +-- gpio_fs_decoder           Full Sampling mode: unpack payload bytes to pin states
  |   +-- gpio_eg_decoder           Edge Position mode: decode edge groups to transitions
  |   +-- gpio_crc32_chk            CRC32 verification; flag error if mismatch
  |   +-- gpio_pin_output_drv       Drive GPIO output pins from decoded GPO data
  |
  +-- gpio_cfg_handler              Configuration mode packet handler (both ASE and ASD)
  |   |
  |   +-- gpio_cfg_tx               Transmit Mode 1/Mode 2 Write and Read commands
  |   +-- gpio_cfg_rx               Receive and apply Write; generate ACK/NACK; handle Read
  |   +-- gpio_cfg_timeout_wdog     Timeout watchdog for ACK/NACK wait window
  |
  +-- gpio_reg_if                   Register interface to 4/5.i.0200 and 4/5.i.0201-0216
  |
  +-- gpio_sample_clk_gen           PTB-tic divider to produce GPIO sample clock
```

### 14.2 Submodule Descriptions

**gpio_pin_sampler**: Registers all enabled GPI pin inputs on the rising edge of
gpio_sample_clk. In EG mode, computes XOR with previous sample to detect edges.
Produces 16-bit sample bus per clock tick.

**gpio_fs_encoder**: Takes N active pin samples per clock tick; packs them into bytes
according to the coding selection (1/2/3-4/5-8/9-16 pins). Accumulates packed bytes
until the packet interval expires.

**gpio_eg_encoder**: In EG mode, captures (pin_id, signal_section, transition_pos,
initial_data) per edge. Sorts edge records by (signal_section, transition_pos,
pin_id) at packet boundary. Serializes as 3-byte groups per Table 7-55.

**gpio_pkt_builder**: At DLP_TX.indicateSlot trigger, assembles the full ASEP packet:
common ASEP header bytes (type 0x05, PTB mode, optional timestamp), GPIO packet
header, data mode header (FS/EG, data length, pin mask), payload, CRC32.

**gpio_crc32_gen/chk**: CRC32 over all packet bytes from byte 0 to (m_END - 4).
Polynomial and calculation method per Section 4.2.9. The check module flags a
CRC failure; the ASD increments error counter at register 3.7.1 on failure.

**gpio_pkt_id_counter**: 7-bit counter initialized to 1 at reset. Increments by 1
for every GPIO packet (config or data) sent. Rolls from 127 to 1 (0 is reserved
and must never be used). Shared across config and data packet modes.

**gpio_cfg_handler**: Finite state machine in root-side ASE/ASD for initiating and
completing the Mode 1 and Mode 2 configuration exchange. Reads local register values
from gpio_reg_if; formats Mode 1 or Mode 2 Write packets; supervises ACK/NACK
timeout watchdog; on non-root side, receives write packets and applies values to
local registers.

**gpio_cfg_timeout_wdog**: Programmable countdown timer started when a Write or Read
command is sent. On expiry without matching ACK/NACK/Read-Response, asserts NACK
signal (all zeros treatment per spec).

**gpio_reg_if**: Provides read/write access to registers 4/5.i.0200 and 4/5.i.0201-
0216. Decodes domain (4=ASE, 5=ASD), DLP index (i), and register address. Enforces
access control (RO for pin availability bit; RW for all others; RID privilege only).

**gpio_sample_clk_gen**: 13-bit counter counting PTB tics; resets at each TDD burst
period start; generates gpio_sample_clk pulse at count == GPIO Pin Sampling Period.

---

## 15. Spec Facts vs Implementation Assumptions

### 15.1 Confirmed Spec Facts

| ID  | Source          | Fact                                                                   |
|-----|-----------------|------------------------------------------------------------------------|
| SF01| 7.8 p256        | One GPIO ASEP handles up to 16 GPIO pins.                             |
| SF02| 7.8 p256        | Pin state coded in reference to configurable multiples of PTB tic.    |
| SF03| 7.8 p256        | Both modes (FS and EG) use nominal TDD cycle as reference.            |
| SF04| 7.8 p256        | Root node SHALL send configuration mode packets before data.          |
| SF05| 7.3 Table 7-1   | ASEP stream type code for GPIO = 0x05.                                |
| SF06| 7.8.1 p256-257  | GPIO packet header is shared across config and data packet modes.     |
| SF07| 7.8.1 p256-257  | GPIO packet ID is a single sequence over all packet modes (1-127).    |
| SF08| 7.8.2 p257      | Config mode: root issues write/read; non-root responds ACK/NACK or   |
|     |                 | Read Response.                                                         |
| SF09| 7.8.2.2 p258    | Mode 1 Write: each pin occupies 2 bytes; n = 0..15 pins per packet.  |
| SF10| 7.8.2.2 p258    | Root converts direction semantics (local vs remote) before sending.  |
| SF11| 7.8.2.3 p258    | Mode 2 Write: 13-bit sampling period + 1-bit FS/EG mode.             |
| SF12| 7.8.2.4 p258-259| Read Command has no payload.                                          |
| SF13| 7.8.2.5 p259    | Timeout on ACK/NACK treated as NACK (all zeros).                     |
| SF14| 7.8.2.9 p260    | Config mode CRC32 footer: checksum over bytes 0 to (m_END-4).        |
| SF15| 7.8.3 p260      | Data mode GPIO data length = count of sampling points (FS) or edge   |
|     |                 | groups (EG).                                                           |
| SF16| 7.8.3 p260      | GPIO pin IDs: bitmask; bit position = pin ID; 1 = payload valid.     |
| SF17| 7.8.3.1 p260    | FS mode: 5 different codings for pin counts 1, 2, 3-4, 5-8, 9-16.   |
| SF18| 7.8.3.1 p261    | First sample in packet = beginning of TDD cycle (alignment rule).    |
| SF19| 7.8.3.1 p261    | Variables 'a'..'p' = ordered ascending set of active GPIO pin IDs.   |
| SF20| 7.8.3.2 p263    | EG: edge positions coded in groups of 3 bytes.                       |
| SF21| 7.8.3.2 p263    | EG: packed ascending by transition position, then by GPIO pin ID.     |
| SF22| 7.8.3.2 p263-264| EG transition position valid range: 0 to 6843.                       |
| SF23| 3.5.6.1 p80-81  | All GPIO IDs in same ASE/ASD apply same thinning rate.               |
| SF24| 3.5.6.1 p80-81  | GPIO Sampling Period = 0 is reserved.                                 |
| SF25| 3.5.6.2 p81-83  | 16 pin configuration registers; pin 0 = 4/5.i.0201 ... pin 15 = 0216.|
| SF26| 3.5.6.2 p81-83  | Pin default/reset behavior asserted during Power-On / Init state.    |
| SF27| 7.3.2 p235      | Common ASEP header byte 0 [7:1] = stream type; [0] = follow flag.    |
| SF28| 7.3.2.1 p235-236| m_HB = 1 if no PTB timestamp; m_HB = 5 if ingress/presentation.     |

### 15.2 Implementation Assumptions

| ID  | Location     | Assumption                                                              |
|-----|--------------|-------------------------------------------------------------------------|
| IA01| Section 3.3  | FS/EG mode is static; mode switch requires pause in data transmission. |
| IA02| Section 4.1  | Ingress timestamping (mode 01) is the typical choice for GPIO ASEP.   |
| IA03| Section 5    | GPIO packet ID gap detection uses register 3.7.1 error counter.       |
| IA04| Section 6.2  | Mode 2 sampling period written before Mode 1 pin config is not         |
|     |              | prohibited by spec but Mode 1 then Mode 2 order is conventional.       |
| IA05| Section 8.2  | Active pin count for coding selection = popcount(GPIO pin IDs mask).  |
| IA06| Section 9.1  | Signal section counter is 6-bit; max 64 TDD cycles per packet.        |
| IA07| Section 9.1  | EG encoder uses sort by (section, position, pin_id) at packet boundary.|
| IA08| Section 10.1 | GPIO Sampling Period must be non-zero before data TX begins.          |
| IA09| Section 13   | GPO output latency = 1 packet interval + DLL transport latency.        |
| IA10| Section 14.2 | gpio_sample_clk counter resets at TDD burst period start boundary.    |
| IA11| Section 14.2 | gpio_pkt_id_counter is shared across config and data mode packets.    |

---

## 16. Verification Plan

### 16.1 Configuration Mode Tests

| Test ID  | Description                                                              |
|----------|--------------------------------------------------------------------------|
| VCFG-001 | Mode 1 Write for single pin: verify correct 2-byte pin config encoding. |
| VCFG-002 | Mode 1 Write for 16 pins: verify all 16 x 2-byte pairs correct.        |
| VCFG-003 | Mode 2 Write: verify sampling period [12:0] and mode bit encoding.     |
| VCFG-004 | Read Command: verify no payload generated (packet contains only header  |
|          | + config cmd byte + footer).                                            |
| VCFG-005 | Mode 1 ACK: verify ACK bit = 1 in byte m_HB+2[4]; rest = Mode 1 Write.|
| VCFG-006 | Mode 1 NACK: verify ACK bit = 0; full packet all-zeros behavior.       |
| VCFG-007 | Mode 2 ACK/NACK: verify m_HB+4[6] set/cleared correctly.              |
| VCFG-008 | Mode 1 Read Response: verify payload identical to Mode 1 Write payload.|
| VCFG-009 | Mode 2 Read Response: verify payload identical to Mode 2 Write payload.|
| VCFG-010 | Timeout watchdog: verify NACK (all-zeros) generated on timeout expiry. |
| VCFG-011 | CRC32 footer: verify CRC32 value over all config packet bytes.         |
| VCFG-012 | Direction conversion: verify root flips direction bit vs local view.    |
| VCFG-013 | GPIO packet ID increments across config packets; wrap 127->1.          |

### 16.2 FS Data Mode Tests

| Test ID  | Description                                                              |
|----------|--------------------------------------------------------------------------|
| VFS-001  | 1 active pin: verify 8 samples packed into 1 byte per Table 7-54.     |
| VFS-002  | 2 active pins: verify 4 time points x 2 pins per byte per Table 7-53. |
| VFS-003  | 3 active pins: verify 2 time points x 3 pins per byte; bit 4 invalid. |
| VFS-004  | 4 active pins: verify 2 time points x 4 pins per byte; all 8 bits used.|
| VFS-005  | 5 active pins: verify 1 time point per byte, bits 2:0 invalid.        |
| VFS-006  | 8 active pins: verify 1 time point per byte, all 8 bits valid.        |
| VFS-007  | 9 active pins: verify 2 bytes per time point; byte 2 bits 6:0 invalid.|
| VFS-008  | 16 active pins: verify 2 bytes per time point; all 16 bits valid.     |
| VFS-009  | Data length field in header matches actual number of time points.      |
| VFS-010  | Pin ID mask in header matches active pins used in payload.             |
| VFS-011  | First sample aligns to TDD cycle boundary (IA10 alignment rule).      |
| VFS-012  | CRC32 footer over entire data packet correct.                          |
| VFS-013  | GPIO packet ID increments across data packets; wrap 127->1.           |
| VFS-014  | Pin ordering: 'a' = lowest active pin ID; 'b' = next; etc.           |

### 16.3 EG Data Mode Tests

| Test ID  | Description                                                              |
|----------|--------------------------------------------------------------------------|
| VEG-001  | Single transition: verify 3-byte group encoding per Table 7-55.        |
| VEG-002  | Initial data bit: verify correct pin state at start of signal section.  |
| VEG-003  | GPIO pin ID field: verify 4-bit field at byte[6:3] for various pin IDs.|
| VEG-004  | Signal section counter: verify 6-bit counter (split [5:3] and [2:0]).  |
| VEG-005  | Transition position: verify 13-bit encoding; max 6843.                 |
| VEG-006  | Sort order: multiple transitions sorted by position then pin ID.        |
| VEG-007  | Zero transitions: verify empty payload, data length = 0.               |
| VEG-008  | Transition at position 0: verify transition_pos[12:0] = 0.             |
| VEG-009  | Transition at position 6843: verify max value encodes correctly.       |
| VEG-010  | Signal section rollover: section counter wraps from 63 to 0.           |
| VEG-011  | Data length field = number of 3-byte edge groups in packet.            |
| VEG-012  | CRC32 footer over entire EG data packet correct.                       |
| VEG-013  | Cross-pin multi-edge sort: ascending section, ascending pos, pin ID.   |

### 16.4 Register Interface Tests

| Test ID  | Description                                                              |
|----------|--------------------------------------------------------------------------|
| VREG-001 | Read 4/5.i.0200: verify GPIO Sampling Mode [13] and Period [12:0].    |
| VREG-002 | Write 4/5.i.0200: verify both fields update; reserved [15:14] = 0.    |
| VREG-003 | Write period = 0 to 4/5.i.0200: verify reserved treatment / rejection. |
| VREG-004 | Read 4/5.i.0201: verify pin availability [7] is RO.                   |
| VREG-005 | Write all RW fields in 4/5.i.0201: direction, default, drive, enable.  |
| VREG-006 | Write pin availability [7] to 4/5.i.0201: verify field is unaffected. |
| VREG-007 | Address decode: 4/5.i.0209 maps to pin 8; 4/5.i.0216 maps to pin 15. |
| VREG-008 | Domain 4 vs Domain 5 access: verify separate ASE/ASD register spaces. |

---

## 17. Missing / Needs Verification

### 17.1 Spec Gaps (Normative Ambiguities)

1. **GPIO packet ID on config vs data boundary**: The spec states IDs are "a single
   sequence over all packet modes" (Section 7.8.1). It does not specify whether the
   counter resets if the ASEP transitions from configuration mode back to data mode
   or vice versa mid-session. NEEDS VERIFICATION against implementation examples.

2. **Number of pins field in Mode 1 Write**: Table 7-44 specifies m_HB+2[3:0] as
   "Number of pins" with n = 0..15. It is unclear whether n = 0 is a valid write
   (payload would contain no pin pairs, only the command byte) or is reserved.
   NEEDS VERIFICATION.

3. **Mode 1 ACK/NACK full payload**: Section 7.8.2.5 states the Mode 1 ACK/NACK
   "payload is identical to the Mode 1 Write payload except for the field below"
   (the ACK/NACK bit). It is not stated whether the non-root node must echo back
   the exact pin configuration data or may send a minimized version. NEEDS
   CLARIFICATION.

4. **Config mode direction**: Section 7.8.2 says "The GPIO ASE in ASA root node
   issues the write/read command." It is not specified whether the non-root node
   may initiate a configuration write to the root. IMPLEMENTATION ASSUMPTION made
   that config is always root-initiated.

5. **FS mode invalid bits**: For 9 active pins, Table 7-50 says bits "j" to "p"
   are invalid. The spec does not mandate what value these invalid bits must carry
   (zero, don't-care). IMPLEMENTATION ASSUMPTION: sender shall set invalid bits
   to 0; receiver shall ignore them.

6. **EG mode GPIO data length 10-bit range**: The data length field is 10 bits
   (m_HB+2[1:0] concat m_HB+3[7:0]), giving range 0-1023 edge groups per packet.
   There is no explicit spec statement that 1023 is the maximum. NEEDS VERIFICATION
   as to whether there is a practical upper bound imposed by TDD burst period count
   or packet size limits.

7. **Config mode timeout watchdog duration**: Section 7.8.2.5 says the timeout is
   "depending on the schedule cycle for this ASEP and the application use case."
   No default or minimum value is specified. NEEDS APPLICATION-LEVEL DEFINITION.

8. **GPIO ASEP in MLE modes**: The GPIO ASEP sections (7.8) do not reference MLE
   modes (Section 8). Whether GPIO ASEP is supported in MLE configurations
   (where higher DLL speeds are used) is not explicitly stated. NEEDS VERIFICATION.

9. **CRC32 polynomial for GPIO**: Both configuration and data packets reference
   Section 4.2.9 for CRC32. Section 4.2.9 defines the polynomial for PCS frames.
   The spec does not explicitly confirm whether the same CRC32 polynomial applies
   at the ASEP layer. NEEDS VERIFICATION against Section 4.2.9.

10. **Sampling Period register in Mode 2**: The Mode 2 Write command carries a
    13-bit GPIO Pin Sampling Period. The register 4/5.i.0200[12:0] also holds a
    13-bit value. The exact relationship (is the Mode 2 Write value the same as
    the register value, or is there a scaling factor?) is assumed to be 1:1 but
    is not explicitly stated. NEEDS CONFIRMATION.

### 17.2 Appendix E Informative Content (Not Design-Binding)

- Figures V-1 and V-2 (Appendix E, pp347-348) are explicitly informative.
  The concrete numeric examples (thinning ratio 1400, 4 TDD burst periods, SG1)
  are for illustration only and do not constrain the implementation parameter space.
- Images 08 and 09 provide compatible but non-binding visual confirmation of the
  Table 7-50 through Table 7-55 encoding rules.
