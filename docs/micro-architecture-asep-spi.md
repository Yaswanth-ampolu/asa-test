# Micro-Architecture: ASEP SPI Tunneling

## 1. Purpose and Scope

The ASEP SPI module tunnels a physical SPI bus across one or more ASA links. The root-side
ASA device (connected to the SPI master) segments SPI bus activity into fixed-size chunks
called "SPI data conversion periods" and encapsulates each chunk into one ASEP SPI packet.
The non-root-side ASA device (connected to the SPI slave) decapsulates and replays the SPI
traffic. A separate return path carries SPI MISO data back to the master with a deterministic
latency called the SPI turnaround time.

This document defines the micro-architecture of the ASEP SPI entity for RTL or golden-model
implementation, derived directly from ASA Technical Specification v2.0, Section 7.7.

Scope boundaries:
- IN SCOPE: SPI cycle time definitions (SPI_STC, SPI_DCP, SPI_TAT), SPI packet header,
  configuration mode packets (write/read/ACK-NACK/read-response/footer), data mode packets,
  interrupt packets, SPI data format (10-bit CS+data coding), ASE behavior in root vs non-root,
  SPI master and slave interfacing requirements, register bit-fields 4/5.i.0200, 4/5.i.0201,
  4.i.0210, 4.i.0211, 4.i.0212, 4.i.0213, TX/RX flows, interface to common ASEP framing
- OUT OF SCOPE: Common ASEP header/footer framing (Section 7.3, separate doc),
  DLL mapper scheduling (micro-architecture-dll-mapper-demux-core.md),
  PHY startup and PTB service (separate docs),
  other ASEP stream types (I2C, GPIO, video, eDP, I2S)

---

## 2. Source References

| Section  | Title                                                   | Pages   | Relevance                                  |
|----------|---------------------------------------------------------|---------|--------------------------------------------|
| 7.7      | ASEP Format: SPI                                        | 248     | Top-level model, chunk approach            |
| 7.7.1    | SPI Cycle Time Definitions and ASE Behavior             | 248-249 | SPI_STC, SPI_DCP, SPI_TAT definitions      |
| 7.7.1.1  | SPI DLL Schedule Transmission Cycle                     | 248     | SPI_STC definition                         |
| 7.7.1.2  | SPI ASEP Data Conversion Period                         | 248     | SPI_DCP definition, DCP >= STC constraint  |
| 7.7.1.3  | SPI Turnaround Time                                     | 248     | SPI_TAT definition, PTB timer              |
| 7.7.1.4  | ASE Behavior in Root Node                               | 248-249 | First DCP wait, subsequent immediate TX    |
| 7.7.1.5  | ASE Behavior in Non-Root Node                           | 249     | Mirror packet length requirement           |
| 7.7.1.6  | ASEP Impact on Timing                                   | 249     | Idle gap handling, PTB presentation option |
| 7.7.2    | Additional Requirements to Tunneled SPI Interface       | 249     | Master/slave interfacing requirements      |
| 7.7.2.1  | SPI Master Function and ASA Device Interfacing to SPI Master | 249 | Master clock rate limit, dual CS mechanism |
| 7.7.2.2  | SPI Slave Function and ASA Device Interfacing to SPI Slave | 249 | Slave SCK pause, slave clock rate minimum  |
| 7.7.3    | SPI Packet Header (Table 7-33)                          | 249-250 | Header byte: mode bit, packet ID field     |
| 7.7.4    | SPI Configuration Mode Packet                           | 250     | Config mode purpose                        |
| 7.7.4.1  | Configuration Command (Table 7-34)                      | 250-251 | Config command mode field                  |
| 7.7.4.2  | Write Command (Table 7-35)                              | 251     | Write command payload fields               |
| 7.7.4.3  | Read Command (Table 7-36)                               | 251     | Read command payload fields                |
| 7.7.4.4  | ACK/NACK Command (Table 7-37)                           | 251     | ACK/NACK response, timeout watchdog        |
| 7.7.4.5  | Read Response Command                                   | 251-252 | Read response payload, timeout             |
| 7.7.4.6  | Configuration Command Footer (Table 7-38)               | 252     | CRC32 footer                               |
| 7.7.5    | SPI Data Mode Packet (Table 7-39)                       | 252-254 | Data mode header and payload fields        |
| 7.7.6    | SPI Interrupt Packet (Table 7-40)                       | 254-256 | Interrupt packet format, watchdog          |
| 7.7.7    | SPI Data Format (Table 7-41)                            | 256     | 10-bit CS+data coding (4 bytes -> 5 bytes) |
| 3.5.5.1  | SPI Configuration (4/5.i.0200, Table 3-91)             | 80      | SCK freq, transmission mode, SPI mode      |
| 3.5.5.2  | SPI Minimum Idle (4/5.i.0201, Table 3-92)              | 80      | Minimum idle gap in 16 ns units            |
| 3.6.6.1  | SPI Transmission Cycle, Turnaround (4.i.0210, Table 3-107) | 90 | SPI_STC and SPI_TAT programmed values     |
| 3.6.6.2  | SPI Data Conversion Cycle (4.i.0211, 4.i.0212, Table 3-108) | 90-91 | SPI_DCP in 4 ns units                   |
| 3.6.6.3  | SPI Error Status (4.i.0213, Table 3-109)               | 91      | stcRxErr and stcTxErr status bits          |
| Appendix D | SPI Tunneling Waveform Examples (Informative)         | 341-347 | Figures IV-1 through IV-7                  |

Image references inspected (docpdfmd/images/):

- 01_SPI_write_read_ex1.png  -- Appendix D Fig IV-1: write/read single SPI frame.
  Shows PTB clock, M_CSn(0), M_CSn(1) (Select Slave), M_SCK, M_MOSI, M_MISO at master
  side; ASE/ASD buffer; Up LINK, Dn LINK (TDD slots); S_CS, S_SCK, S_MOSI, S_MISO at slave
  side. Labels: (a) TB = TDD burst, (b) L = latency window, (c) D = data conversion period,
  "5D as the fixed turnaround time" for M_CSn(1), "4D as the fixed turnaround time" for
  M_MISO. [INFORMATIVE]

- 02_SPI_write_read_ex2.png  -- Appendix D Fig IV-2: write/read by single/multiple SPI frames.
  Shows two sequential O_DB#1, O_DB#2 data blocks on master MOSI within one DCP window,
  each encoded with Coded CS and transported in separate Up LINK slots. [INFORMATIVE]

- 03_SPI_write_only_ex3.png  -- Appendix D Fig IV-3: write-only by single/multiple SPI frames.
  Demonstrates write-only case where returned I_DB#1/I_DB#2 on M_MISO carry "Discard command"
  at far side (no read data expected). [INFORMATIVE]

- 04_SPI_extended_timing_buffered.png  -- Appendix D Fig IV-4: write/read with longer SPI
  frame (reduce_latency=1). O_DB#1 (read command) followed by O_DB#2..O_DB#4 (dummy) sent
  upstream; red cross marks a missed Up LINK slot because SCK pause is not engaged.
  I_DB#1..I_DB#4 returned on downstream after 4D turnaround. [INFORMATIVE]

- 05_SPI_extended_timing_multi_frame.png  -- Appendix D Fig IV-5: write/read with longer SPI
  frame, reduce_latency=0. O_DB#1 is held in buffer for minimum latency L before transmission;
  slave side SCK is not paused because pipeline is full. [INFORMATIVE]

- 06_SPI_waveform_motorola_mode.png  -- Appendix D Fig IV-6: Motorola mode CS coding.
  Single frame: CS[1]=1 before Byte#1, CS[0]=0 between bytes, CS[0]=1 after last byte.
  Multiple frame: CS transitions shown as 1/0/0/1/1/0/0/1 across frame boundaries. [INFORMATIVE]

- 07_SPI_waveform_TI_mode.png  -- Appendix D Fig IV-7: TI mode CS coding.
  CS is a pulse per byte group; CS[1]/CS[0] transitions capture one-pulse-width CS operation
  within each 10-bit coded unit. [INFORMATIVE]

---

## 3. SPI Tunneling Model and System Context

### 3.1 Conceptual Model

SPEC FACT (Section 7.7, p248): This ASEP is based on segmenting SPI bus activity into fixed
size chunks of length "SPI data conversion period", where each chunk is transmitted in one
ASEP packet. The response to the SPI master has a defined latency and SPI access has to be
handled in a special way.

The overall topology for SPI tunneling involves:
- Root node: ASA device connected to the SPI master. Hosts the Application Stream Encapsulator
  (ASE) on a DLP_TX port and an Application Stream Decapsulator (ASD) on a DLP_RX return port.
- Non-root node: ASA device connected to the SPI slave. Hosts an ASD on a DLP_RX port (receives
  outgoing SPI data from root) and an ASE on a DLP_TX port (sends SPI MISO return data back).

SPEC FACT (Section 7.7, p248): The SPI interface pin names are Serial Clock SCK, Master In
Slave Out MISO, Master Out Slave In MOSI and Chip Select CS. [Informative note in spec.]

IMPLEMENTATION ASSUMPTION: The ASEP SPI entity occupies one or more DLP_TX/DLP_RX port pairs.
The ASE on the root side drives DLP_TX with outbound SPI data; the ASD on the root side listens
on DLP_RX for return MISO data. Mirrored roles exist on the non-root (slave) side.

### 3.2 System Block Diagram

```
  Root Node                           Non-Root Node
  +--------------------------+         +---------------------------+
  |  SPI Master              |         |  SPI Slave                |
  |  M_CSn(0) M_CSn(1)       |         |  S_CS S_SCK S_MOSI S_MISO |
  |  M_SCK  M_MOSI  M_MISO   |         +----------+----------------+
  +---+--------+--------+----+                    |
      |        |        |              +----------+----------------+
      |        |        |              | ASD (non-root side)       |
  +---v--------v----+   |              |  spi_slave_ctrl           |
  | ASE (root side) |   |              |  data_unpack              |
  |  spi_capture    |   |              |  cs_reconstruct           |
  |  data_pack      |   |              +----------+----------------+
  |  cs_encode      |   |                         |
  |  dcp_timer      |   |              +----------v----------------+
  +--------+--------+   |              | ASE (non-root side)       |
           |            |              |  miso_capture             |
  +--------v--------+   |              |  data_pack (return)       |
  | DLP_TX (up)     |<--+              +----------+----------------+
  |                 |   ^                         |
  +--------+--------+   |              +----------v----------------+
           |            |              | DLP_TX (up, return)       |
           |            |              +----------+----------------+
  +--------v--------+   |                         |
  | ASA Link        |   |         <----------------+
  | (DLL+PHY)       |<------------------------------------------->|
  +--------+--------+   |
           |            |
  +--------v--------+   |
  | DLP_RX (dn ret) +---+
  |                 |
  | ASD (root ret)  |
  |  tat_timer      |
  |  miso_replay    |
  +--------+--------+
           |
     M_MISO (returned to SPI master)
```

IMPLEMENTATION ASSUMPTION: The ASE on the root side uses two DLP identifiers: one upstream
DLP_TX for outbound SPI data (MOSI + CS), and one downstream DLP_RX for the return MISO data.
The non-root side mirrors this with a downstream DLP_RX for received MOSI data and an upstream
DLP_TX for the MISO response. This matches the general ASEP bidirectional transceiver note in
Section 7.3.

---

## 4. SPI Cycle Time Definitions

### 4.1 SPI_STC: SPI DLL Schedule Transmission Cycle

SPEC FACT (Section 7.7.1.1, p248): The "SPI DLL schedule transmission cycle" (SPI_STC) is
defined as the maximum duration (within a programmed DLL schedule) from the start of a first
SPI ASE DLL schedule slot to the start of a second SPI ASE DLL schedule slot, while during
this period the SPI ASD has received an ASEP packet once at least. The SPI_STC is measured
as integer multiple of TDD cycles.

SPEC FACT (Register 4.i.0210, Table 3-107, p90): The SPI schedule transmission cycle field
occupies bits [7:0] of register 4.i.0210. Valid values are 1-255 in unit TDD cycle; 0 is
reserved.

### 4.2 SPI_DCP: SPI ASEP Data Conversion Period

SPEC FACT (Section 7.7.1.2, p248): The "SPI ASEP data conversion period" (SPI_DCP) is
defined as the duration of SPI bus activity (on master side) converted into one SPI ASEP
packet.

SPEC FACT (Section 7.7.1.2, p248): SPI_DCP has to be equal or larger than SPI_STC.

  SPI_DCP >= SPI_STC

SPEC FACT (Register 4.i.0211/0212, Table 3-108, p91): SPI_DCP is stored across two registers:

  4.i.0211 [15:0]  : SPIconvCycle[15:0]   (in multiples of 4 ns)
  4.i.0212 [3:0]   : SPIconvCycle[19:16]  (upper 4 bits, in multiples of 4 ns)
  4.i.0212 [15:4]  : Reserved

The full 20-bit value gives SPI_DCP = SPIconvCycle * 4 ns.

SPEC FACT (Registers 4.i.0211, 4.i.0212, Table 3-108, p91): These registers exist only on
ASA node connecting to SPI Master.

### 4.3 SPI_TAT: SPI Turnaround Time

SPEC FACT (Section 7.7.1.3, p248-249): The SPI turnaround time (SPI_TAT) is defined as an
integer multiple of SPI_DCP. It denotes the time on the SPI interface between a data conversion
block from the SPI master to the response data block out of the SPI-over-ASA tunnel to the SPI
master.

SPEC FACT (Section 7.7.1.3, p248): The start point for counting the turnaround time is when
the buffering of the first SPI data block of the SPI frame into the ASA device (ASE memory)
is complete. The turnaround time stops when the first SPI bit (in response) is on the SPI
interface.

SPEC FACT (Section 7.7.1.3, p249): The ASE/ASD of the ASA device connected to the SPI master
controls the data buffering time in order to keep the turnaround time of SPI return data
constant. The ASE/ASD counts the turnaround time by using the PTB clock frequency/4
(nominally 16 ns resolution).

SPEC FACT (Register 4.i.0210, Table 3-107, p90): The SPI turnaround time field occupies bits
[15:8] of register 4.i.0210. The value is an integer multiple of the SPI_DCP value (as
programmed in 3.6.6.2).

Note (informative, from spec): The ASA-internal mandatory PTB is used as time base, but the
events on the external (outside ASA compliant portion) SPI interface start and stop the timer.

### 4.4 Relationship Between Timing Parameters

```
  |<---- SPI_DCP (one data conversion period) ---->|
  |<-- SPI_STC -------->|                           |
  |                                                 |
  |                                                 |
  PTB ticks (16 ns resolution):
  - SPI_STC = N * TDD_cycle   (integer, N = 4.i.0210[7:0])
  - SPI_DCP = SPIconvCycle * 4 ns  (4.i.0211/0212)
  - SPI_TAT = K * SPI_DCP          (integer K = 4.i.0210[15:8])
  - Constraint: SPI_DCP >= SPI_STC

  Master-side clock rate constraint:
    M_SCK * SPI_STC < 160 bytes    (Section 7.7.2.1)

  Slave-side clock rate constraint:
    S_SCK * SPI_STC >= 128 bytes   (Section 7.7.2.2)
```

---

## 5. ASE Behavior: Root Node vs Non-Root Node

### 5.1 ASE Behavior in Root Node

SPEC FACT (Section 7.7.1.4, p248-249): On the start of an SPI frame, the ASE waits SPI_DCP to
record data to construct an SPI ASEP data mode packet.

SPEC FACT (Section 7.7.1.4, p249): If the same SPI frame continues for more than one SPI_DCP,
starting from the second SPI ASEP data mode packet, all the SPI data buffered shall be sent
immediately via the DLP_TX.dataUnit when a DLP_TX.indicateSlot is received (see Section 5.6.1).

Informative note in spec: For longer SPI frames, this will eventually lead to no waiting times
for (the last bit of) SPI data for any valid combination of SPI_STC and SPI_DCP and ensures
a guaranteed SPI_TAT as short as possible in the schedule and ASA branch.

State machine summary for root ASE:

```
  State: IDLE
    -> Event: first SCK edge or CS assertion detected
    -> Action: start DCP timer (SPI_DCP countdown using PTB/4)
    -> Next: FIRST_DCP_WAIT

  State: FIRST_DCP_WAIT
    -> Continuously record SPI data (MOSI + CS) into capture buffer
    -> Event: DCP timer expires
    -> Action: pack captured data into SPI ASEP data mode packet,
               submit via DLP_TX.dataUnit on next DLP_TX.indicateSlot
    -> Next: RUNNING

  State: RUNNING  (second and subsequent DCP windows)
    -> Event: DLP_TX.indicateSlot received
    -> Action: immediately pack all buffered SPI data since last packet
               into SPI ASEP data mode packet, submit DLP_TX.dataUnit
    -> Continue until SPI frame ends (CS deasserts)
    -> On frame end: -> IDLE
```

### 5.2 ASE Behavior in Non-Root Node

SPEC FACT (Section 7.7.1.5, p249): The ASE shall always respond with an SPI ASEP data mode
packet of the same length as the corresponding one received from the ASE in the root node.

IMPLEMENTATION ASSUMPTION: This means the non-root ASD (receiving the MOSI packet from root)
must inform the non-root ASE (sending MISO return data) of the exact byte count of the received
packet. The non-root ASE pads with valid SPI MISO data captured from the slave bus, or dummy
bytes if the slave has not produced enough data, to match the received packet length.

### 5.3 ASEP Impact on Timing

SPEC FACT (Section 7.7.1.6, p249): The SPI ASEP does not fully maintain SPI bus timing,
especially for SPI idle gaps. The minimum SPI idle gap shall be used to enable compatibility
with connected SPI devices. This SPI idle gap has to be taken into consideration for payload
reservation.

SPEC FACT (Section 7.7.1.6, p249): For multiple SPI frames inside one DCP, the last frame's
position within the DCP is captured and can be reconstructed.

SPEC FACT (Section 7.7.1.6, p249): If precise timing is required for the SPI bus interface,
the common ASEP mechanism with PTB presentation times has to be used and payload data rate
adjusted accordingly.

---

## 6. Additional Interfacing Requirements

### 6.1 SPI Master Side (Root Node)

SPEC FACT (Section 7.7.2.1, p249): The SPI master shall order read/write accesses in such a
way that within a given window of length SPI_DCP, there is at maximum one write access and at
maximum one read access.

SPEC FACT (Section 7.7.2.1, p249): The SPI master side clock rate SCK satisfies the condition:
M_SCK * SPI_STC < 160 bytes. The master side SPI influx data rate is kept below average
reserved data rate in ASA schedule.

SPEC FACT (Section 7.7.2.1, p249): The ASA device interfacing to the SPI master shall offer a
mechanism to allow for the ASA device receiving SPI read/write commands and with latency
returning read data.

Informative note in spec: For instance, by using 2 distinct SPI CS signals, the SPI master
may distinguish the transmit data to the SPI ASE of an ASA device and the read data from the
SPI ASD of the same device. These two SPI CS signals are allowed to be active at the same time,
i.e. write-only, read-only and simultaneous read-write are possible.

### 6.2 SPI Slave Side (Non-Root Node)

SPEC FACT (Section 7.7.2.2, p249): The SPI master on the ASD of ASA device (branch or leaf)
connected to the SPI slave is able to stop issuing the SCK to pause the SPI communication when
the ASD receives an empty SPI packet from ASA node interfacing to the SPI master (root).

SPEC FACT (Section 7.7.2.2, p249): The SPI slave side clock rate SCK satisfies the condition:
S_SCK * SPI_STC >= 128 bytes. The maximum payload sent in one container can locally be turned
around on the SPI within SPI_STC. The MOSI buffer at the SPI slave side is never fuller than
128 bytes and the latency of the turnaround to gather the response data is SPI_STC at maximum.

---

## 7. ASEP SPI Packet Header

SPEC FACT (Section 7.7.3, p249-250, Table 7-33): The SPI ASEP header format is shared for all
packet modes. SPI packet IDs are a single sequence of IDs over all packet modes.

The SPI-specific header occupies byte m_HB+1 (immediately following the common ASEP first byte):

```
  Byte       Bit(s)  Name             Description
  ---------  ------  ---------------  ---------------------------------------------------
  m_HB+1     7       SPI packet mode  0 = SPI configuration mode
                                      1 = SPI data mode
  m_HB+1     6:0     SPI packet ID    Starts at 1, increments by 1, max 120, rolls to 1.
                                      Values 0 and 121-126 are reserved.
                                      ASE at SPI master side assigns each new SPI packet
                                        this incrementing ID.
                                      ASE at SPI slave side sets this ID to echo the
                                        response to the received SPI packet.
                                      Value 127 signifies an SPI interrupt packet;
                                        does not affect any packet ID counters.
```

IMPLEMENTATION ASSUMPTION: The common ASEP first byte (byte m_HB+0) carries ASEP stream type
0x04 (SPI) in bits [7:1] and the same-container follow flag in bit [0], per Section 7.3.2.
The SPI-specific header starts at m_HB+1.

IMPLEMENTATION ASSUMPTION: The packet ID counter is separate from the common ASEP Full Packet
ID counter (registers 4/5.i.0001-0003). The SPI packet ID is a 7-bit field limited to the
range 1..120; packet ID 127 is overloaded as the interrupt indicator.

---

## 8. Configuration Mode Packets (Section 7.7.4)

### 8.1 Purpose

SPEC FACT (Section 7.7.4, p250): SPI configuration mode packet is used to transfer SPI
configuration information from ASA registers in the ASA node interfacing to the SPI master
to ASA registers in the ASA node interfacing to the SPI slave.

SPEC FACT (Section 7.7.4, p250): The SPI ASE interfacing to the SPI master device issues the
write/read command to the SPI ASE/ASD in the node interfacing to the SPI slave devices.
The SPI ASE/ASD interfacing to the SPI slave devices in turn responds with ACK/NACK to a
Write command and with Read Response to a Read command.

### 8.2 Configuration Command Byte (Table 7-34)

SPEC FACT (Section 7.7.4.1, p250-251, Table 7-34): Configuration command length depends on
the specific configuration command mode.

```
  Byte       Bit(s)  Name                   Description
  ---------  ------  ---------------------  ----------------------------------
  m_HB+2     7:6     Configuration command  00 = Write command mode
                       mode                 01 = Read command mode
                                            10 = ACK/NACK mode
                                            11 = Read response mode
  m_HB+2     5:4     Reserved
```

### 8.3 Write Command (Table 7-35)

SPEC FACT (Section 7.7.4.2, p251, Table 7-35):

```
  Byte       Bit(s)  Name               Description
  ---------  ------  -----------------  --------------------------------------
  m_HB+2     3:2     Transmission mode  Copy value from register 3.5.5.1 (4/5.i.0200[3:2])
  m_HB+2     1:0     SPI mode           Copy value from register 3.5.5.1 (4/5.i.0200[1:0])
  m_HB+3     7:0     SPI minimum idle   See Section 3.5.5.2 (4/5.i.0201[7:0])
  m_HB+4     7:2     Reserved
  m_HB+4     1:0     SCK frequency[9:8] Copy value from register 3.5.5.1 (4/5.i.0200[13:12])
  m_HB+5     7:0     SCK frequency[7:0] Copy value from register 3.5.5.1 (4/5.i.0200[11:4])
```

### 8.4 Read Command (Table 7-36)

SPEC FACT (Section 7.7.4.3, p251, Table 7-36):

```
  Byte       Bit(s)  Name      Description
  ---------  ------  --------  ---------------
  m_HB+2     3:0     Reserved
```

The Read command has no additional payload beyond the configuration command byte and this
reserved nibble.

### 8.5 ACK/NACK Command (Table 7-37)

SPEC FACT (Section 7.7.4.4, p251, Table 7-37): The payload of the ACK/NACK command is
identical to the Write command (Table 7-35) except for the following override field:

```
  Byte       Bit(s)  Name      Description
  ---------  ------  --------  ----------------------
  m_HB+4     2       ACK/NACK  0 = write failed (NACK)
                                1 = write succeeded (ACK)
```

SPEC FACT (Section 7.7.4.4, p251): The root node should implement a timeout watchdog (depending
on the schedule cycle for this ASEP and the application use case) and treat a timeout as a NACK.

### 8.6 Read Response Command

SPEC FACT (Section 7.7.4.5, p251-252): The payload of the Read Response command is identical
to the Write command (Table 7-35). The root node should implement a timeout watchdog and treat
a timeout as a NACK (all zeros).

IMPLEMENTATION ASSUMPTION: For Read Response, the "ACK/NACK" bit at m_HB+4[2] carries the
current configuration value echo, not an ACK/NACK status. The surrounding fields (transmission
mode, SPI mode, min idle, SCK frequency) reflect the current non-root register values.

### 8.7 Configuration Command Footer (Table 7-38)

SPEC FACT (Section 7.7.4.6, p252, Table 7-38):

```
  Byte        Bit(s)  Name           Description
  ----------  ------  -------------  -----------------------------------------
  m_END-3     7:0     CRC32[31:24]   CRC32 checksum over all ASEP packet bytes
  m_END-2     7:0     CRC32[23:16]     0 to (m_END-4), where m_END is the last
  m_END-1     7:0     CRC32[15:8]      byte index of the entire ASEP packet.
  m_END       7:0     CRC32[7:0]     CRC32 polynomial as defined in Section 4.2.9
```

IMPLEMENTATION ASSUMPTION: The CRC32 covers the entire ASEP packet including the common ASEP
header byte at m_HB+0 through to m_END-4. The polynomial definition (Section 4.2.9) is the
standard IEEE 802.3 CRC32.

---

## 9. Data Mode Packet (Section 7.7.5, Table 7-39)

### 9.1 Data Mode Header Fields

SPEC FACT (Section 7.7.5, p252-254, Table 7-39):

```
  Byte        Bit(s)  Name                    Description
  ----------  ------  ----------------------  ---------------------------------------------------
  m_HB+2      7       Reserved
  m_HB+2      6       Reduce latency          0: ASE of near side transmits SPI packet as soon
                                                 as possible, without waiting for latency to avoid
                                                 far-side underflow. Use when SPI packets are not
                                                 transmitted consecutively. For consecutive use
                                                 with this mode, far-side ASD must pause SCK.
                                              1: ASE of near side buffers the SPI packet for at
                                                 least "SPI transmission cycle" to avoid underflow
                                                 at far side.
  m_HB+2      5:2     CSn                     Chip Select value:
                                                 0 = ASA node (interfacing to SPI slave) itself
                                                 1..15 = external SPI slave Chip Select value
                                                 For interrupt packet: identifies interrupt source
  m_HB+2      1:0     Current packet status   00 = void (null): no SPI data in this packet.
                                                   If ASD receives this during SPI communication,
                                                   ASD shall keep SCK low to pause transaction.
                                              01 = dummy: conveys dummy data to generate SCK at
                                                   far-side to read SPI data from slave.
                                                   Dummy data may be discarded by SPI slave.
                                              10 = valid
                                              11 = reserved
  m_HB+3      7:0     Length of SPI payload   Unsigned integer. Number of SPI bytes coded as
                        [7:0]                  10-bit with CS flag (see Section 7.7.7).
                                               Number of encoded payload bytes:
                                                 n = ceil("Length of SPI payload" * 10 / 8)
  m_HB+4      7:6     Reserved
  m_HB+4      5:0     Position last rising    Unsigned integer, 16 ns unit [29:24].
                        CS [29:24]             Position of last falling edge of CS in this packet.
  m_HB+5      7:0     Position last rising    [23:16]
                        CS [23:16]             ASD uses this value to reproduce the position
  m_HB+6      7:0     Position last rising    [15:8]  of the last CS.
                        CS [15:8]              Only used when packet contains more than one SPI
  m_HB+7      7:0     Position last rising    [7:0]   frame. Invalid if only a single SPI frame
                        CS [7:0]               or no SPI data is present.
  m_HB+8      7:5     Reserved
  m_HB+8      4:2     Operation status SPI    0x0 = Normal status
                        slave side [2:0]       0x1 = Busy (ASD buffer not empty)
                                               0x2 = Error happened (SPI data packet broken)
                                               else = reserved
  m_HB+8      1       SPI slave interrupt     0 = no interrupt
                        flag                   1 = interrupt active.
                                               For eSPI device: slave notifies master of
                                               SPI transaction request via this flag.
  m_HB+8      0       SPI module reset        0 = no effect
                        request                1 = ASE issued reset command to SPI module
  m_HB+9+n    7:0     SPI data with coded     10-bit unit size. Number of data bytes depends
                        CS coding              on SPI data; up to 160 bytes (SPI data and CS)
                                               coded into 128 bytes.
  m_END-3     7:0     CRC32[31:24]            Checksum over byte 0 to m_END-4
  m_END-2     7:0     CRC32[23:16]
  m_END-1     7:0     CRC32[15:8]
  m_END       7:0     CRC32[7:0]
```

### 9.2 Data Mode Packet Size Bounds

IMPLEMENTATION ASSUMPTION: The maximum SPI payload per data mode packet is 128 bytes of SPI
data (each byte carrying 2 CS bits in 10-bit coding). This results in n = ceil(128*10/8) = 160
encoded bytes in the m_HB+9+n payload field. Combined with the 10-byte header and 4-byte CRC
footer, maximum packet size is approximately 174 bytes plus the common ASEP first byte.

---

## 10. Interrupt Packet (Section 7.7.6, Table 7-40)

SPEC FACT (Section 7.7.6, p254): If the connected SPI devices support the interrupt feature,
this packet is used to convey the information.

SPEC FACT (Section 7.7.6, p254-256): The interrupt packet uses SPI packet ID = 127 in the
header (see Section 7.7.3). This does not affect packet ID counters.

SPEC FACT (Section 7.7.6, p254): The ASA node connected to the interrupting SPI slave should
implement a watchdog and repeat the interrupt message after a timeout (value depending on
schedule cycle and application use case).

```
  Byte        Bit(s)  Name                    Description
  ----------  ------  ----------------------  ---------------------------------------------------
  m_HB+2      7:6     Reserved
  m_HB+2      5:2     Interrupt Source        Chip Select value:
                                                0 = ASA node (interfacing to SPI slave) itself
                                                1..15 = external SPI slave CS value
                                              Identifies the source of the interrupt.
  m_HB+2      1:0     Reserved, set to 0
  m_HB+3      7:0     Interrupt counter [7:0] Unsigned integer.
                                              Increments for each assertion and deassertion
                                              of an interrupt. Starts at 1, rolls over from
                                              127 to 1. Shared counter for all interrupt
                                              sources. Value 0 is reserved.
  m_HB+4      7       SPI slave interrupt     0 = no interrupt
                        flag                   1 = interrupt active.
                                               eSPI: slave requests SPI transaction via flag.
  m_HB+4      6       Reserved
  m_HB+4      5       Reserved
  m_HB+4      4:2     Operation status SPI    0x0 = Normal status
                        slave side [2:0]       0x1 = Busy (ASD buffer not empty)
                                               0x2 = Error (SPI data packet broken)
                                               else = reserved
  m_HB+4      1       Reserved
  m_HB+4      0       SPI module reset        0 = no effect
                        request                1 = ASE issued reset command to SPI module
  m_END-3     7:0     CRC32[31:24]            Checksum over byte 0 to m_END-4
  m_END-2     7:0     CRC32[23:16]
  m_END-1     7:0     CRC32[15:8]
  m_END       7:0     CRC32[7:0]
```

IMPLEMENTATION ASSUMPTION: The interrupt packet has no SPI data payload; it terminates
immediately with the CRC32 footer. Total size is the common header byte + 3 SPI header bytes
+ 3 header bytes of interrupt content + 4 CRC bytes = approximately 11 bytes before common
framing overhead.

---

## 11. SPI Data Format (Section 7.7.7, Table 7-41)

### 11.1 10-bit Coding Scheme

SPEC FACT (Section 7.7.7, p256, Table 7-41): Every four SPI bytes are coded with the Chip
Select signals into 5 payload bytes.

SPEC FACT (Section 7.7.7, p256): Chip Select information CS1 denotes the CS state on the SPI
interface just before the data byte, where '0' denotes a low state and '1' denotes a high
state or pulse (see also Transmission Mode in 3.5.5.1). CS0 denotes the CS state on the SPI
interface just after the data byte.

### 11.2 Byte-Level Encoding Table

SPEC FACT (Section 7.7.7, p256, Table 7-41):

```
  Encoded     Bit(s)  SPI source field
  byte n      ------  -----------------------------------------
  n           7       CS1 of SPI data byte m
  n           6       CS0 of SPI data byte m
  n           5:0     SPI data byte m [7:2]   (upper 6 bits)
  n+1         7:6     SPI data byte m [1:0]   (lower 2 bits)
  n+1         5       CS1 of SPI data byte m+1
  n+1         4       CS0 of SPI data byte m+1
  n+1         3:0     SPI data byte m+1 [7:4] (upper 4 bits)
  n+2         7:4     SPI data byte m+1 [3:0] (lower 4 bits)
  n+2         3       CS1 of SPI data byte m+2
  n+2         2       CS0 of SPI data byte m+2
  n+2         1:0     SPI data byte m+2 [7:6] (upper 2 bits)
  n+3         7:2     SPI data byte m+2 [5:0] (lower 6 bits)
  n+3         1       CS1 of SPI data byte m+3
  n+3         0       CS0 of SPI data byte m+3
  n+4         7:0     SPI data byte m+3 [7:0] (all 8 bits)
```

4 SPI data bytes + 8 CS bits = 40 bits = 5 bytes. Ratio: 4 SPI bytes -> 5 encoded bytes (10
bits per SPI byte: 8 data + 1 CS1 + 1 CS0).

### 11.3 Motorola Mode vs TI Mode CS Encoding

INFORMATIVE (Appendix D, Fig IV-6, image 06_SPI_waveform_motorola_mode.png): In Motorola mode,
the CS line is held asserted (low) across all bytes of one SPI frame. The CS[1] at the first
byte boundary is '1' (high before frame start), transitions to '0' (low = active) and stays '0'
between all bytes within the frame (CS[0] and CS[1] are both '0' for inter-byte boundaries).
At the last byte, CS[0] = '1' (CS deasserted after last byte). For back-to-back frames separated
by a gap, the CS[1] = '1' of the subsequent frame's first byte signals the inter-frame idle.

INFORMATIVE (Appendix D, Fig IV-7, image 07_SPI_waveform_TI_mode.png): In TI mode, the CS
produces one pulse per byte group transaction. CS[1] = '1' at the start of each SPI frame byte,
CS[0] = '0' immediately after; the CS line produces a brief pulse per byte. The 10-bit coding
faithfully captures this pulse width in the CS1/CS0 bit pair.

SPEC FACT (Register 4/5.i.0200, Table 3-91, p80): Transmission mode 00 = original SPI frame
format (Motorola mode); 01 = one pulse width CS signal mode (TI mode).

---

## 12. Register Bit Fields

### 12.1 Register 4/5.i.0200: SPI Configuration

SPEC FACT (Section 3.5.5.1, Table 3-91, p80):

```
  Address: 4/5.i.0200
  Name: SPI Configuration
  Access: RW, OAM channel and local (O), Privilege: RID (Root nodeID only)

  Bit(s)  Name              Description
  ------  ----------------  -------------------------------------------------------
  15:14   Reserved
  13:4    SCK frequency     SCK frequency of ASA device interfacing to SPI slave.
                            Unit: 100 kHz. Valid range: 0x001 to 0x3FF.
                            0x000 deactivates / resets the SPI module.
                            (10-bit field: bits [13:12] = SCK freq [9:8],
                             bits [11:4] = SCK freq [7:0])
  3:2     Transmission mode 00 = original SPI frame format (Motorola mode)
                            01 = one pulse width CS signal mode (TI mode)
                            10, 11 = reserved
  1:0     SPI mode          00 = SPI mode 0 (CPOL=0, CPHA=0)
                            01 = SPI mode 1 (CPOL=0, CPHA=1)
                            10 = SPI mode 2 (CPOL=1, CPHA=0)
                            11 = SPI mode 3 (CPOL=1, CPHA=1)
                            CPOL = Clock Polarity, CPHA = Clock Phase
```

Note: The register exists in both the ASE (domain 4) and ASD (domain 5) address spaces. The
write command in Section 7.7.4.2 copies these values to the non-root node's ASD registers.

### 12.2 Register 4/5.i.0201: SPI Minimum Idle

SPEC FACT (Section 3.5.5.2, Table 3-92, p80):

```
  Address: 4/5.i.0201
  Name: SPI Minimum Idle
  Access: RW, OAM channel and local (O), Privilege: RID

  Bit(s)  Name            Description
  ------  --------------  -------------------------------------------------------
  15:8    Reserved
  7:0     SPI minimum     Lower bound of SPI idle period. Unit: 16 ns.
            idle          Value 0 = no minimum idle enforced.
                          Maximum idle = 255 * 16 ns = 4080 ns.
```

### 12.3 Register 4.i.0210: SPI Transmission Cycle, Turnaround

SPEC FACT (Section 3.6.6.1, Table 3-107, p90):

```
  Address: 4.i.0210
  Name: SPI Transmission Cycle, Turnaround
  Exists only on ASA node connecting to SPI Master
  Access: RW, OAM channel and local (O), Privilege: RID

  Bit(s)  Name                    Description
  ------  ----------------------  -----------------------------------------------
  15:8    SPI turnaround time     Integer multiple of SPI_DCP (as programmed in
                                  3.6.6.2). See also Section 7.7.1.3.
  7:0     SPI schedule            0: reserved.
            transmission cycle    1-255: SPI_STC value in units of TDD cycle.
                                  See also Section 7.7.1.1.
```

### 12.4 Registers 4.i.0211, 4.i.0212: SPI Data Conversion Cycle

SPEC FACT (Section 3.6.6.2, Table 3-108, p91):

```
  Address: 4.i.0211, 4.i.0212
  Name: SPI Data Conversion Cycle
  Exists only on ASA node connecting to SPI Master
  Access: RW, OAM channel and local (O), Privilege: RID

  Register    Bit(s)    Name                  Description
  ----------  --------  --------------------  ----------------------------------
  4.i.0211    15:0      SPIconvCycle[15:0]    SPI_DCP in multiples of 4 ns.
                                              (lower 16 bits)
  4.i.0212    3:0       SPIconvCycle[19:16]   SPI_DCP upper 4 bits.
                                              See also Section 7.7.1.2.
  4.i.0212    15:4      Reserved
```

SPI_DCP = SPIconvCycle[19:0] * 4 ns

### 12.5 Register 4.i.0213: SPI Error Status

SPEC FACT (Section 3.6.6.3, Table 3-109, p91):

```
  Address: 4.i.0213
  Name: SPI Error Status
  Exists only on ASA node connecting to SPI Master
  Access: SC (Self-Clearing), OAM channel and local (O), Privilege: RID

  Bit(s)  Name      Description
  ------  --------  ----------------------------------------------------------
  15:2    Reserved
  1       stcRxErr  SPI schedule transmission cycle (see 3.6.6.1) elapsed
                    without receiving data to ASD. Self-clears on read.
  0       stcTxErr  SPI schedule transmission cycle (see 3.6.6.1) elapsed
                    without a second transmit opportunity. Self-clears on read.
```

---

## 13. Interface to ASEP Common Framing

### 13.1 Common ASEP First Byte

SPEC FACT (Section 7.3.2, Table 7-4): All ASEP packets begin with a common byte:

```
  Byte m_HB+0:
    Bit(s)  Name                        Description
    ------  --------------------------  ----------------------------------------
    7:1     ASEP stream type            0x04 for SPI (Table 7-1)
    0       Same container ASEP header  0: no further ASEP header in this container
              follow flag               1: another ASEP header follows immediately
```

SPEC FACT (Section 7.3, Table 7-1, p233): SPI stream type code is 0x04.

### 13.2 PTB Timestamps

IMPLEMENTATION ASSUMPTION: SPI ASEP may optionally carry PTB timestamps in the common ASEP
header extension per Section 7.3.2.1. When precise timing reconstruction is required (as noted
in Section 7.7.1.6), the ASE embeds the PTB presentation time in the header so the ASD can
replay the SPI bus activity with accurate inter-frame gaps.

### 13.3 Fragmentation

SPEC FACT (Section 7.3.1, p233): There is a common format per DLL payload which unifies the
handling of fragmentation. Each ASEP packet may span multiple DLL containers.

IMPLEMENTATION ASSUMPTION: The ASE assembles a complete SPI ASEP data mode packet (up to ~174
bytes) and hands it to the DLL via DLP_TX.dataUnit. The DLL mapper fragments this across one
or more DLL containers as needed. The ASD on the far side reassembles fragments using the common
ASEP reassembly mechanism before processing the SPI packet.

SPEC FACT (Section 7.3, p232): The ASD communicates with the Data Link Layer via the primitives
defined in Section 5.7.1. Reassembly errors resulting in corrupt data must be recorded in the
ASD Status register (3.7.1).

---

## 14. Interface to Physical SPI Bus

### 14.1 Master-Side Pins (Root Node)

```
  Signal    Direction   Description
  --------  ----------  --------------------------------------------------------
  M_SCK     Input       SPI clock from SPI master. Monitored to detect start of
                        SPI frame and to count bits for data capture.
  M_MOSI    Input       Master-Out-Slave-In data captured by ASE into DCP buffer.
  M_CSn(0)  Input       CS for writing transmit data to SPI ASE of root node.
  M_CSn(1)  Input       CS for reading return data from SPI ASD of root node.
                        (Two-CS mechanism per informative note in 7.7.2.1.)
  M_MISO    Output      Return SPI data driven by ASD of root node after SPI_TAT.
```

IMPLEMENTATION ASSUMPTION: The two-CS mechanism requires separate pin assignments.
M_CSn(0) gates capture into the ASE buffer; M_CSn(1) gates the M_MISO output from the ASD.
Both may be simultaneously asserted for simultaneous read/write operation.

### 14.2 Slave-Side Pins (Non-Root Node)

```
  Signal    Direction   Description
  --------  ----------  --------------------------------------------------------
  S_SCK     Output      SPI clock generated by ASD of non-root node. Stopped
                        (held low) when a void/null packet is received.
  S_MOSI    Output      Outbound data to SPI slave, replayed from received packet.
  S_CS      Output      Chip Select to SPI slave, reconstructed from coded CS bits.
  S_MISO    Input       MISO data captured from SPI slave by non-root ASE and
                        returned upstream.
```

SPEC FACT (Section 7.7.2.2, p249): The non-root ASD stops issuing SCK when a void (null)
packet is received (Current packet status = 00).

---

## 15. TX/RX Flows

### 15.1 Outbound Data Flow (Root ASE -> Non-Root ASD)

```
  1. SPI master asserts M_CSn(0), starts clocking M_SCK.
  2. Root ASE: DCP timer starts (PTB/4 = 16 ns resolution).
  3. Root ASE: captures M_MOSI bits into internal buffer, records CS1/CS0 per byte.
  4. Root ASE: DCP timer expires (first packet) OR DLP_TX.indicateSlot received
     (subsequent packets).
  5. Root ASE: applies 10-bit coding (Section 7.7.7) to pack 4 SPI bytes -> 5 bytes.
  6. Root ASE: assembles SPI data mode packet:
       - Common ASEP header (stream type 0x04)
       - SPI header (mode=1, packet ID++)
       - Data mode header (reduce_latency, CSn, current_packet_status, length,
         position_last_rising_CS, operation_status, interrupt_flag, reset_request)
       - Coded SPI payload
       - CRC32 footer
  7. Root ASE: calls DLP_TX.dataUnit with packet, when DLP_TX.indicateSlot active.
  8. DLL: fragments and transmits in DLL containers over ASA link (Up LINK direction).
  9. Non-root ASD: receives reassembled ASEP packet via DLP_RX.dataUnit.
 10. Non-root ASD: decodes packet, extracts coded SPI payload.
 11. Non-root ASD: unpacks 5 encoded bytes -> 4 SPI data bytes + CS1/CS0 per byte.
 12. Non-root ASD: reconstructs CS line (position_last_rising_CS used for multi-frame).
 13. Non-root ASD: drives S_SCK, S_MOSI, S_CS toward SPI slave.
     - If packet status = 00 (void): stops S_SCK (holds low).
     - If packet status = 01 (dummy): drives dummy data to generate S_SCK for MISO
       capture; slave may discard MOSI.
     - If packet status = 10 (valid): drives real SPI data.
```

### 15.2 Return Data Flow (Non-Root ASE -> Root ASD)

```
  1. Non-root ASE: captures S_MISO bits from SPI slave during S_SCK.
  2. Non-root ASE: packs return data into SPI data mode packet of SAME length as
     received outbound packet (Section 7.7.1.5).
  3. Non-root ASE: assembles SPI data mode packet with same packet ID echoed in header.
  4. Non-root ASE: calls DLP_TX.dataUnit, transmitted in next available DLP slot
     (Dn LINK direction toward root).
  5. DLL: fragments and transmits in DLL containers.
  6. Root ASD: receives reassembled ASEP packet via DLP_RX.dataUnit.
  7. Root ASD: manages TAT timer.
     - TAT timer started when first SPI data block buffering was complete (step 3
       of outbound flow).
     - TAT timer target = SPI_TAT * SPI_DCP (from 4.i.0210[15:8] * 4.i.0211/0212).
  8. Root ASD: when TAT timer expires, drives M_MISO with return data from received
     packet. First SPI bit on M_MISO stops the TAT timer.
  9. SPI master reads M_MISO return data, eventually deasserts M_CSn(1).
```

### 15.3 Configuration Mode Flow

```
  Root host CPU writes configuration registers 4/5.i.0200, 4/5.i.0201.
  Root ASE: detects configuration change, assembles config mode packet (mode=0 in header).
  Config Write command (Table 7-35):
    - Transmission mode, SPI mode from 4/5.i.0200[3:0]
    - SPI min idle from 4/5.i.0201[7:0]
    - SCK frequency from 4/5.i.0200[13:4]
  Root ASE: transmits config packet upstream via DLP_TX.dataUnit.
  Non-root ASD/ASE: receives config packet, programs its local registers accordingly.
  Non-root ASE: responds with ACK/NACK packet (Table 7-37).
  Root ASD: receives ACK/NACK, reports to root host CPU via 4.i.0213 or direct status.

  For config read:
  Root ASE: sends Read command packet (Table 7-36, no payload beyond header).
  Non-root ASE: responds with Read Response packet (Table 7-35 payload).
  Root ASD: receives Read Response, forwards current config to root register map.
```

### 15.4 Interrupt Flow

```
  Non-root ASD: detects interrupt assertion from SPI slave (e.g. eSPI interrupt line).
  Non-root ASE: assembles interrupt packet (packet ID = 127 in SPI header).
    - Interrupt Source = CS value identifying interrupting slave
    - Interrupt counter increments for each assert/deassert
    - SPI slave interrupt flag = 1
  Non-root ASE: transmits interrupt packet upstream.
  Root ASD: receives interrupt packet, signals root host CPU via ASA interrupt mechanism.
  If no ACK from root host within watchdog timeout:
    Non-root ASE: retransmits interrupt packet.
```

---

## 16. Reduce Latency Mode

SPEC FACT (Section 7.7.5, Table 7-39, p252-253): The reduce_latency bit in the data mode
packet header controls near-side ASE buffering behavior:

```
  reduce_latency = 0 (default):
    ASE of near side transmits SPI packet as soon as possible.
    Far-side ASD must support SCK pause (stops SCK when void packet received).
    Suitable for non-consecutive SPI packet transmission.

  reduce_latency = 1:
    ASE of near side buffers SPI packet for at least one "SPI transmission cycle"
    (SPI_STC) before transmitting.
    This prevents underflow at far-side by ensuring the pipeline is fed at a
    minimum rate. No SCK pausing required at far-side.
    Used for consecutive/pipelined SPI transmission.
```

INFORMATIVE (Appendix D, Fig IV-4, image 04_SPI_extended_timing_buffered.png): With
reduce_latency=1 (buffered mode), first data block O_DB#1 is transmitted immediately via
Up LINK when DLP_TX.indicateSlot arrives; subsequent O_DB#2..O_DB#4 dummy blocks maintain the
pipeline. Return I_DB#1..I_DB#4 arrive continuously on the Dn LINK. The red X in the diagram
marks a slot that is NOT missed because the pipeline is maintained -- the ASD does not pause.

INFORMATIVE (Appendix D, Fig IV-5, image 05_SPI_extended_timing_multi_frame.png): With
reduce_latency=0, first data block O_DB#1 is held in the buffer for the minimum latency L
before transmission. This delays pipeline start by L but the pipeline then runs continuously
without SCK pausing.

---

## 17. RTL Submodules

### 17.1 Root Node Submodules

```
  +-------------------------------------------------------------------+
  | spi_ase_root                                                      |
  |  +--------------------+  +--------------------------------------+ |
  |  | spi_capture        |  | dcp_timer                            | |
  |  |  - clk_edge_detect |  |  - ptb_clk_div4 input               | |
  |  |  - mosi_shift_reg  |  |  - dcp_countdown (from 4.i.0211/12) | |
  |  |  - cs1_cs0_latch   |  |  - stc_countdown (from 4.i.0210[7:0])| |
  |  +--------+-----------+  +----------------+---------------------+ |
  |           |                               |                       |
  |  +--------v-------------------------------v---------------------+ |
  |  | spi_packer                                                    | |
  |  |  - 10bit_cs_encoder (Section 7.7.7)                          | |
  |  |  - data_mode_hdr_gen (mode, pkt_id, reduce_lat, csn, status, | |
  |  |                        length, pos_last_cs, op_status)        | |
  |  |  - pkt_id_counter (1..120, wraps, 127 for interrupt)         | |
  |  +--------+------------------------------------------------------+ |
  |           |                                                         |
  |  +--------v------------------------------------------------------+ |
  |  | crc32_gen (Section 4.2.9)                                     | |
  |  +--------+------------------------------------------------------+ |
  |           |                                                         |
  |  +--------v------------------------------------------------------+ |
  |  | dlptx_if                                                      | |
  |  |  - indicate_slot_handler                                      | |
  |  |  - dataunit_submit                                            | |
  |  +---------------------------------------------------------------+ |
  +-------------------------------------------------------------------+

  +-------------------------------------------------------------------+
  | spi_asd_root (return path)                                        |
  |  +--------------------+  +--------------------------------------+ |
  |  | tat_timer          |  | dlprx_if                             | |
  |  |  - ptb_clk_div4    |  |  - dataunit_receive                  | |
  |  |  - tat_target      |  |  - reassembly_buf                    | |
  |  |    (4.i.0210[15:8] |  +----------------+---------------------+ |
  |  |     * SPI_DCP)     |                   |                       |
  |  +--------+-----------+  +----------------v---------------------+ |
  |           |              | spi_unpacker                          | |
  |           |              |  - 10bit_cs_decoder                  | |
  |           |              |  - return_data_buf                    | |
  |           +------------->| tat_control                          | |
  |                          +----------------+---------------------+ |
  |                                           |                       |
  |                          +----------------v---------------------+ |
  |                          | miso_replay                          | |
  |                          |  - miso_shift_reg                    | |
  |                          |  - cs_reconstruct                    | |
  |                          +---------------------------------------+ |
  +-------------------------------------------------------------------+

  +-------------------------------------------------------------------+
  | spi_cfg_ase_root (configuration mode TX)                         |
  |  +--------------------+                                          | |
  |  | cfg_pkt_gen        |                                          | |
  |  |  - write_cmd_gen   |                                          | |
  |  |  - read_cmd_gen    |                                          | |
  |  |  - ack_watchdog    |                                          | |
  |  +--------+-----------+                                          | |
  |           |                                                       |
  |  crc32_gen + dlptx_if (shared)                                   |
  +-------------------------------------------------------------------+
```

### 17.2 Non-Root Node Submodules

```
  +-------------------------------------------------------------------+
  | spi_asd_nonroot                                                   |
  |  +--------------------+  +--------------------------------------+ |
  |  | dlprx_if           |  | spi_slave_ctrl                       | |
  |  |  - reassembly_buf  |->|  - s_sck_gen                        | |
  |  |  - pkt_type_decode |  |  - s_mosi_drive                     | |
  |  +--------------------+  |  - s_cs_reconstruct                  | |
  |                          |    (position_last_rising_CS field)   | |
  |                          |  - sck_pause_ctrl (void pkt detect)  | |
  |                          +----------------+---------------------+ |
  |                                           |                       |
  |                          +----------------v---------------------+ |
  |                          | pkt_len_register                     | |
  |                          |  feeds spi_ase_nonroot for mirroring | |
  |                          +---------------------------------------+ |
  +-------------------------------------------------------------------+

  +-------------------------------------------------------------------+
  | spi_ase_nonroot (MISO return path)                                |
  |  +--------------------+                                          | |
  |  | miso_capture       |                                          | |
  |  |  - s_miso_shift_reg|                                          | |
  |  |  - len_from_asd    | (mirrors received pkt length)            | |
  |  +--------+-----------+                                          | |
  |           |                                                       |
  |  spi_packer (return), crc32_gen, dlptx_if (shared)               |
  +-------------------------------------------------------------------+
```

### 17.3 Shared Infrastructure

```
  +-------------------------------------------------------------------+
  | spi_reg_block                                                     |
  |  4/5.i.0200: SCK frequency, transmission mode, SPI mode          |
  |  4/5.i.0201: SPI minimum idle (16 ns units)                      |
  |  4.i.0210:   SPI_TAT (integer multiple of DCP) [15:8]            |
  |              SPI_STC (TDD cycle count)         [7:0]             |
  |  4.i.0211:   SPIconvCycle[15:0]  (4 ns unit)                     |
  |  4.i.0212:   SPIconvCycle[19:16] (4 ns unit, upper nibble)       |
  |  4.i.0213:   stcRxErr[1], stcTxErr[0]  (SC, OAM+local, RID)     |
  +-------------------------------------------------------------------+
```

---

## 18. Common ASEP Framing Integration

The SPI ASEP module plugs into the common ASEP framework as follows:

```
  DLP_TX interface (outbound, per Section 5.6.1):
    - DLP_TX.indicateSlot: triggers ASE to submit buffered packet
    - DLP_TX.dataUnit:     carries assembled ASEP SPI packet
    - DLP_TX.yield:        used if ASE has nothing to send in this slot

  DLP_RX interface (return, per Section 5.7.1):
    - DLP_RX.dataUnit:     delivers reassembled ASEP SPI return packet to ASD
```

IMPLEMENTATION ASSUMPTION: The ASEP SPI TX submodule must register for a DLP_TX slot
assignment in the DLL mapper table (registers 2.0146-2.2065). The SPI stream type 0x04 is
configured in register 4/5.i.0004 (ASEP Stream Type). Each SPI DLP port uses one slot entry
(or multiple if higher bandwidth is required).

IMPLEMENTATION ASSUMPTION: The data starve event (Section 7.3) must be tracked: if no SPI
activity occurs within a stream-type-specific timeout, the ASE reports the data starve condition
in register 4.i.0101 (ASE Status).

---

## 19. Timing Constraints Summary

| Parameter | Definition | Source | Register |
|-----------|------------|--------|----------|
| SPI_STC | Max DLL schedule window between two SPI ASE slots (TDD cycles) | 7.7.1.1 | 4.i.0210[7:0] |
| SPI_DCP | Duration of SPI bus activity in one ASEP packet (4 ns units) | 7.7.1.2 | 4.i.0211/0212 |
| SPI_TAT | Turnaround time, integer * SPI_DCP (PTB/4 = 16 ns resolution) | 7.7.1.3 | 4.i.0210[15:8] |
| SPI_MIN_IDLE | Minimum SPI idle gap enforced by ASD on slave side (16 ns units) | 7.7.1.6 | 4/5.i.0201[7:0] |
| M_SCK_MAX | M_SCK * SPI_STC < 160 bytes (master clock rate upper bound) | 7.7.2.1 | derived |
| S_SCK_MIN | S_SCK * SPI_STC >= 128 bytes (slave clock rate lower bound) | 7.7.2.2 | derived |
| SCK_FREQ | Slave SCK frequency set via 4/5.i.0200[13:4] (100 kHz unit) | 3.5.5.1 | 4/5.i.0200 |

---

## 20. Spec Facts vs Implementation Assumptions Summary

### 20.1 Confirmed SPEC FACTs

- ASEP SPI stream type code = 0x04 (Section 7.3, Table 7-1)
- Chunk-based segmentation model, one chunk per ASEP packet (Section 7.7)
- SPI_DCP >= SPI_STC (hard constraint, Section 7.7.1.2)
- SPI_TAT is integer multiple of SPI_DCP (Section 7.7.1.3)
- TAT timer uses PTB/4 (nominally 16 ns resolution) (Section 7.7.1.3)
- Root ASE waits SPI_DCP for first packet, then transmits immediately on indicateSlot
  (Section 7.7.1.4)
- Non-root ASE always mirrors the received packet length (Section 7.7.1.5)
- SPI idle gap does not fully preserve original timing (Section 7.7.1.6)
- Master: max one write + one read per SPI_DCP window (Section 7.7.2.1)
- Master clock rate: M_SCK * SPI_STC < 160 bytes (Section 7.7.2.1)
- Slave clock rate: S_SCK * SPI_STC >= 128 bytes (Section 7.7.2.2)
- Non-root ASD stops SCK on void packet receipt (Section 7.7.2.2)
- SPI packet ID range 1..120, rolls over; 127 = interrupt (Section 7.7.3, Table 7-33)
- Config mode: write/read/ACK-NACK/read-response command modes (Section 7.7.4)
- Data mode: reduce_latency, CSn, packet_status, length, position_last_CS (Section 7.7.5)
- Interrupt: shared counter 1..127, watchdog repeat required (Section 7.7.6)
- 10-bit coding: 4 SPI bytes + 8 CS bits -> 5 payload bytes (Section 7.7.7)
- CS1 = CS state before byte, CS0 = CS state after byte (Section 7.7.7)
- Registers 4.i.0210, 4.i.0211, 4.i.0212, 4.i.0213 exist only on root (SPI master) node
- Register 4/5.i.0200 exists in both ASE (domain 4) and ASD (domain 5) address spaces
- stcRxErr and stcTxErr are self-clearing (SC) flags (Section 3.6.6.3)

### 20.2 INFORMATIVE (Appendix D Waveforms)

All seven figures in Appendix D (images 01-07) are explicitly labeled Informative in the spec.
They provide implementation guidance but impose no normative requirements:

- Figure IV-1: Single write/read SPI frame, turnaround labels "5D" / "4D"
- Figure IV-2: Multiple SPI frames within one DCP window
- Figure IV-3: Write-only with return discard
- Figure IV-4: Extended timing with reduce_latency=1 (buffered mode, no SCK pause)
- Figure IV-5: Extended timing with reduce_latency=0 (minimum latency buffering, L delay)
- Figure IV-6: Motorola mode CS encoding (CS sustained low across frame)
- Figure IV-7: TI mode CS encoding (CS pulse per byte group)

### 20.3 IMPLEMENTATION ASSUMPTIONs

- Dual-CS mechanism at master side (M_CSn(0) for TX, M_CSn(1) for RX select) drawn from
  the informative note in Section 7.7.2.1; specific pin count is implementation-dependent.
- Non-root ASD passes received packet length to non-root ASE for length-mirroring.
- The "same ASEP packet ID" is echoed in return packets (slave ASE copies root ASE packet ID).
- Config Read Response uses the Write command payload structure with current register values;
  the ACK/NACK bit position is not normatively defined for read response.
- CRC32 polynomial follows Section 4.2.9 (IEEE 802.3 standard polynomial 0xEDB88320).
- ASEP stream type 0x04 is written to 4/5.i.0004 during OAM configuration.
- PTB/4 timer (16 ns resolution) uses the mandatory PTB clock derived from the PHY layer;
  the timer is not a separate clock domain but a divided version of the PTB reference.

---

## 21. Verification Plan

### 21.1 Functional Tests

| Test | Description | Key Check |
|------|-------------|-----------|
| VT-SPI-001 | SPI_DCP timer accuracy | Timer expires within +/-1 PTB tick of programmed value |
| VT-SPI-002 | First-DCP buffering (root ASE) | Packet not submitted until DCP expires |
| VT-SPI-003 | Subsequent-DCP immediate TX | Packet submitted on first indicateSlot after DCP1 |
| VT-SPI-004 | SPI_TAT constant enforcement | M_MISO first bit appears exactly at TAT boundary |
| VT-SPI-005 | Reduce latency = 0 behavior | Packet held for at least SPI_STC before TX |
| VT-SPI-006 | Reduce latency = 1 behavior | Packet submitted immediately on indicateSlot |
| VT-SPI-007 | Void packet -> SCK pause | Non-root ASD holds S_SCK low on receipt of status=00 |
| VT-SPI-008 | Dummy packet handling | Non-root drives S_SCK but MOSI is dummy; MISO captured |
| VT-SPI-009 | Non-root response length mirror | Return packet byte count equals received byte count |
| VT-SPI-010 | 10-bit CS encoding (Motorola) | Packed CS1/CS0 bits match CS line observations |
| VT-SPI-011 | 10-bit CS encoding (TI mode) | Pulse-width CS correctly captured in CS1/CS0 bits |
| VT-SPI-012 | SPI packet ID rollover | ID increments 1..120, wraps to 1 |
| VT-SPI-013 | Interrupt packet ID=127 | Interrupt pkt carries ID=127, does not advance counter |
| VT-SPI-014 | Config Write -> ACK | Non-root responds with ACK/NACK within watchdog window |
| VT-SPI-015 | Config Write timeout -> NACK | Root watchdog fires if ACK not received in time |
| VT-SPI-016 | Config Read -> Read Response | Non-root echoes current register values |
| VT-SPI-017 | Interrupt watchdog retry | Non-root retransmits interrupt packet on timeout |
| VT-SPI-018 | Multi-frame position_last_CS | Field correctly set when DCP contains >1 SPI frame |
| VT-SPI-019 | stcRxErr flag assertion | 4.i.0213[1] set when ASD receives no data in SPI_STC |
| VT-SPI-020 | stcTxErr flag assertion | 4.i.0213[0] set when ASE misses TX opportunity in SPI_STC |
| VT-SPI-021 | CRC32 mismatch | ASD discards packet, increments ASD Status (5.i.0100) |
| VT-SPI-022 | SCK frequency setting | 4/5.i.0200[13:4]=0 deactivates SPI module |
| VT-SPI-023 | SPI mode CPOL/CPHA | All four SPI mode combinations produce correct clk/data phase |
| VT-SPI-024 | Minimum idle gap enforcement | ASD inserts minimum idle between SPI frames per 4/5.i.0201 |

### 21.2 Boundary and Corner Cases

- SPI_DCP == SPI_STC (minimum allowed configuration)
- SPI_TAT = 1 * SPI_DCP (minimum turnaround)
- Maximum SPI payload: 128 SPI bytes (160 encoded bytes) per packet
- Simultaneous M_CSn(0) and M_CSn(1) assertion (simultaneous read/write)
- SPI frame spanning more than two SPI_DCP windows
- Empty SPI frame (no MOSI data within one DCP)
- Back-to-back interrupt assertions before root acknowledges

---

## 22. Missing / Needs Verification

### 22.1 Register 4.i.0212 Bit-Level Ambiguity

The structured chunk for 4.i.0212 (Section 3.6.6.2) is incomplete in the pipeline extraction.
From the PDF scan (p91, Table 3-108) the three-row table confirms:
- 4.i.0211: SPIconvCycle[15:0] in multiples of 4 ns
- 4.i.0202.3:0: SPIconvCycle[19:16] (note: register address "4.i.0202.3:0" seen in PDF table
  header may be a typo for 4.i.0212; needs cross-check against register model)
- 4.i.0202.15:4: Reserved

NEEDS VERIFICATION: Confirm whether the register storing SPIconvCycle[19:16] is address
4.i.0212 (consistent with the naming convention 4.i.0211 / 4.i.0212) or address 4.i.0202
(which appears in the raw PDF scan). The raw PDF table shows "4.i.0201" through "4.i.0202"
which conflicts with section numbering 3.6.6.2. The register model document
(micro-architecture-register-model.md) should be authoritative.

### 22.2 ACK/NACK Bit Position Ambiguity

Section 7.7.4.4 states the ACK/NACK payload is "identical to the Write command except for the
following field": byte m_HB+4 contains ACK/NACK. However, Table 7-35 (Write command) assigns
m_HB+4[1:0] = SCK frequency[9:8] and m_HB+4[7:2] = Reserved. The PDF scan of Table 7-37 shows
bit position = 2 for ACK/NACK. The exact bit encoding of the override within m_HB+4 needs RTL
clarification:

NEEDS VERIFICATION: Whether bit 2 of m_HB+4 in ACK/NACK mode replaces the SCK_freq[9:8]
field (bits [1:0]) or is a separate bit at position 2 leaving the SCK_freq field intact.

### 22.3 Interrupt Counter Roll-Over Value

Section 7.7.6 states the interrupt counter "roles over from 127 to 1". The value 0 is reserved.
Maximum count before rollover is 127 (7 bits). However the header field is defined as only 8
bits at m_HB+3[7:0]. The range described (1..127) leaves values 128-255 undefined.

NEEDS VERIFICATION: Whether interrupt counter values 128-255 are reachable or if the counter
is effectively a 7-bit field embedded in an 8-bit register byte.

### 22.4 position_last_rising_CS Field Name

Section 7.7.5 (Table 7-39) uses the field name "Position last rising CS" in bytes m_HB+4 to
m_HB+7, but the textual description states "The position of last falling edge of CS in this
packet." The name says "rising" and the description says "falling edge."

NEEDS VERIFICATION: Confirm whether the 30-bit position field captures the last rising edge or
the last falling edge of the CS signal. The informative waveforms (Appendix D) do not resolve
this directly.

### 22.5 Config Mode Packet Header Byte Count

Section 7.7.4 defines a config mode packet. The header structure uses bytes starting at m_HB+1
(SPI header with mode=0 and packet ID), then m_HB+2 (config command byte), followed by command-
specific payload bytes m_HB+3 through m_HB+5 for Write/ACK-NACK/Read Response, or no additional
bytes for Read. The total ASEP packet overhead (common header + SPI header + config fields +
footer) is not explicitly stated.

NEEDS VERIFICATION: Confirm whether the config mode packet uses the same CRC32 footer
structure as the data mode packet (4 bytes) and whether a PTB timestamp extension in the common
ASEP header increases the offset of m_HB.

### 22.6 Multiple CS Lines and Domain 5 Register Scope

Section 7.7.5 Table 7-39 defines CSn field as 4 bits (bits [5:2]) supporting CS values 0..15.
However, register 4/5.i.0200 is a single 16-bit register covering only one SPI configuration.

NEEDS VERIFICATION: Whether multiple external SPI slaves (CS 1..15) require separate register
instances (4/5.i.0200 per CS) or whether a single SPI configuration is shared across all
external CS lines on one DLP port.

---

*End of Micro-Architecture: ASEP SPI Tunneling*
