# Micro-Architecture: ASEP I2C Tunneling

## 1. Purpose and Scope

The ASEP I2C module encapsulates physical-layer I2C traffic into ASA DLL containers
for point-to-point tunneling across an ASA SerDes link. It allows an I2C Master
connected at one ASA node to communicate with I2C Slave devices connected at a remote
ASA node without direct electrical connection.

The module supports three operational modes:

- Byte Mode: one-to-one emulation of I2C bus events (Start, Stop, Data, Ack, Nack)
  as they occur, transmitted individually. Condition bits are explicit in every frame.
- Bulk Mode: aggregated I2C transactions (write commands, read commands, ACK/NACK
  responses, read responses) packed efficiently. Condition bits are implied.
- Configuration Mode: out-of-band synchronization of I2C clock rate and slave address
  configuration from the I2C Master side ASA node to the I2C Slave side ASA node.

Scope boundaries:
- IN SCOPE: ASEP I2C frame assembly and disassembly, all three mode formats and their
  byte field definitions, register model for clock rate and slave addresses, TX/RX data
  flow, interface to ASEP common framing (header/footer), interface to physical I2C bus,
  interface to register model, RTL submodule decomposition, verification plan
- OUT OF SCOPE: ASEP common header and footer structure (covered in
  micro-architecture-asep-common-framing.md), DLL mapper/demux scheduling, OAM
  configuration flow, physical I2C electrical specification, I2C arbitration and
  multi-master bus management beyond what is referenced in the spec

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 7.5 | ASEP Format: I2C | 240 | Top-level overview, two modes |
| 7.5.1 | I2C Byte Mode | 240-241 | Byte mode packet structure |
| 7.5.1.1 | Command Mode | 240-241 | Table 7-15: byte mode command format |
| 7.5.1.2 | Data Byte | 241 | Table 7-16: byte mode payload |
| 7.5.2 | I2C Bulk Mode | 241-244 | Bulk mode packet structures |
| 7.5.2.1 | Command Mode | 241 | Table 7-17: bulk mode command format |
| 7.5.2.2 | Write Command | 241-242 | Tables 7-18, 7-19: bulk write header+payload |
| 7.5.2.3 | Read Command | 242 | Table 7-20: bulk read header |
| 7.5.2.4 | ACK/NACK Command | 242-243 | Tables 7-21, 7-22: bulk ACK/NACK |
| 7.5.2.5 | Read Response Format | 243-244 | Tables 7-23, 7-24: bulk read response |
| 7.5.2.6 | Bulk Mode Footer | 244 | Table 7-25: bulk mode footer (CRC32) |
| 7.5.3 | I2C Configuration Mode | 244 | Config mode trigger rule |
| 7.5.3.1 | Command Mode | 244-245 | Table 7-26: config mode command format |
| 7.5.3.2 | Write Command | 245 | Table 7-27: config write payload |
| 7.5.3.3 | Read Command | 245 | Config read: no payload |
| 7.5.3.4 | ACK/NACK Command | 245 | Table 7-28: config ACK/NACK payload |
| 7.5.3.5 | Read Response Command | 246 | Table 7-29: config read response payload |
| 7.5.3.6 | Configuration Command Footer | 246 | Table 7-30: config mode footer (CRC32) |
| 7.5.4 | Usage of Format | 246-247 | INFORMATIVE: mode semantics, addressing |
| 3.5.4.1 | I2C clock rate (4/5.i.0200) | 78 | Table 3-88: clock rate register |
| 3.5.4.2 | I2C slave addresses (4/5.i.0201-0208) | 78-80 | Tables 3-89, 3-90: slave address registers |
| Appendix C | I2C Topologies (informative) | 338-340 | Figures III-1 through III-5 |
| Appendix G | Recommended local I2C mapping | 351 | Table VII-1: local I2C access mapping |

Structured chunk IDs: asa-7.5, asa-7.5.1.1, asa-7.5.1.2, asa-7.5.2.1 through
asa-7.5.2.6, asa-7.5.3 through asa-7.5.3.6, asa-7.5.4, asa-3.5.4.1, asa-3.5.4.2,
asa-III, asa-III.a, asa-III.b, asa-III.c, asa-VII

---

## 3. I2C Tunneling Model

### 3.1 Overview

SPEC FACT (7.5, p240): "There are two I2C ASEP modes: Byte Mode and Bulk Mode."
SPEC FACT (7.5.4, p246): "I2C is bidirectional and accordingly, both ASE and ASD have
one DLP_TX connection and DLP_RX connection."

The I2C ASEP stream is symmetric: both the ASE (Application Stream Encoder, connected
at the I2C Master side) and the ASD (Application Stream Decoder, connected at the I2C
Slave side) have independent DLP_TX and DLP_RX connections to the DLL. This reflects
the fact that the I2C bus is bidirectional -- commands flow from master to slave and
acknowledgements, read data, and NACK conditions flow from slave to master.

```
  I2C Master side (root/ECU)        I2C Slave side (display/device)
  +----------------------------+     +----------------------------+
  |           ASA Node A       |     |           ASA Node B       |
  |                            |     |                            |
  | I2C_MA ----+  ASEP I2C    |     |  ASEP I2C  +---- I2C_SL   |
  |  (SDA/SCL) |   ASE        |     |    ASD     |    (SDA/SCL)  |
  |            |  +--------+  |     |  +--------+|               |
  |            +->| I2C TX |--+---> |->| I2C RX +-+             |
  |            |  | engine |  | ASA |  | engine | |             |
  |            |  +--------+  | link|  +--------+ |             |
  |            |  +--------+  |     |  +--------+ |             |
  |            +--| I2C RX |<-+<--- |<-| I2C TX +-+             |
  |               | engine |  |     |  | engine |               |
  |               +--------+  |     |  +--------+               |
  |         DLP_TX + DLP_RX   |     |  DLP_TX + DLP_RX          |
  +----------------------------+     +----------------------------+
```

### 3.2 Mode Selection

SPEC FACT (7.5, p240): The first additional byte after the common ASEP header base
(m_HB+1) carries cmd_id, and the second additional byte (m_HB+2) carries the common
command format including I2C Mode[1:0] and I2C Error.

SPEC FACT (Table 7-14, p240): Common command format byte (m_HB+2):

```
Byte     Bit(s)  Field          Description
------   ------  -----          -----------
m_HB+1   7:0     cmd_id         New (not currently in use) command ID assigned by the
                                 ASEP on I2C Master side for each write and each read
                                 command. ASEP on I2C Slave side shall keep the same
                                 cmd_id in ack/nack and read response commands.
m_HB+2   7       I2C Mode[1]    See I2C Mode[1:0] encoding below
m_HB+2   6       I2C Error      1: I2C bus hang-up detected
                                 0: no error
m_HB+2   5       I2C Mode[0]    See I2C Mode[1:0] encoding below
```

I2C Mode[1:0] encoding:
```
  I2C Mode[1]  I2C Mode[0]  Mode
  -----------  -----------  ----
       1            0       Byte Mode
       0            0       Bulk Mode
       0            1       Configuration Mode
       1            1       Reserved
```

Note: Mode bits are non-contiguous (bits 7 and 5 of m_HB+2). The I2C Error bit
occupies bit 6 between them.

### 3.3 Topology Scenarios

SPEC FACT (Appendix C, p338): "ASEP connections are quasi-statically routed between
ASA nodes on the same ASA branch."

Appendix C (informative) illustrates five topology scenarios:

- Figure III-1 (Scenario 1): Point-to-point tunneling, two independent I2C masters
  (MA.i at node1, MA.ii at node3) connecting to multiple slaves at nodes 4 and 6.
- Figure III-2 (Scenario 2): Same topology with ASEP connections rerouted through
  DLL configuration (demonstrating dynamic path reconfiguration).
- Figure III-3 (Scenario 3): One I2C Master communicating with I2C Slaves behind more
  than one ASA device through multiple parallel I2C ASEP point-to-point tunnels,
  managed by an implementation-specific layer.
- Figure III-4 (Scenario 4): Similar multi-slave topology with camera application.
- Figure III-5 (Scenario 5): Multi-Master scenario using standard I2C arbitration,
  including I2C debugger nodes (MA.iii, MA.iv) connectable at various points on the
  ASA branch. MA/SL capable nodes (nodes 3, 4, 6) act as both Master and Slave.

IMPLEMENTATION ASSUMPTION: The ASA transceiver implements exactly one I2C ASEP
instance per configured DLP. Each DLP carries one I2C tunnel endpoint. Multiple
independent tunnels require multiple DLP_TX/DLP_RX connections.

### 3.4 Recommended Slave Addresses

SPEC FACT (7.5.4, p247):
- I2C Slave address 000_1000 (0x08) is recommended for the root node I2C Slave
  (connected to ASE) for communication with that ASA node.
- I2C Slave address 000_1001 (0x09) is recommended for the non-root I2C multi-mode
  Master/Slave (connected to ASD) for communication with that ASA node.

---

## 4. ASEP I2C Common Command Format (Table 7-14)

All I2C ASEP packets share a common first two bytes following the ASEP common header
base byte m_HB:

```
Byte     Bit(s)  Field           Description
------   ------  -----           -----------
m_HB+1   7:0     cmd_id          Command ID (assigned by I2C Master side ASEP)
m_HB+2   7       I2C Mode[1]     Mode selector MSB (10=Byte, 00=Bulk, 01=Config)
m_HB+2   6       I2C Error       1=I2C bus hang-up; 0=no error
m_HB+2   5       I2C Mode[0]     Mode selector LSB
m_HB+2   4:0     (mode-specific) Lower 5 bits defined per mode
```

The lower 5 bits of m_HB+2 (bits 4:0) are defined differently for each mode and are
described in Sections 5, 6, and 7 below.

---

## 5. Byte Mode (Section 7.5.1)

### 5.1 Purpose

SPEC FACT (7.5.4, p246): "Byte mode is emulating bidirectional I2C mode on a
byte-per-byte/bit basis. I2C condition bits are transmitted."

Each individual I2C bus event (Start, Stop, Data byte, Ack, Nack) is encoded and
transmitted as a separate ASEP I2C packet. This provides full transparency of the I2C
bus state and is appropriate for applications that need precise I2C bus monitoring or
flexible multi-master scenarios.

### 5.2 Command Format (Table 7-15)

SPEC FACT (7.5.1.1, p240-241): In I2C Byte mode, the lower bits of the command byte
at m_HB+2 are defined as:

```
Byte     Bit(s)  Field            Description
------   ------  -----            -----------
m_HB+2   7       I2C Mode[1]      = 1 (Byte Mode)
m_HB+2   6       I2C Error        1: I2C bus hang-up; 0: no error
m_HB+2   5       I2C Mode[0]      = 0 (Byte Mode)
m_HB+2   4       I2C Data         1: Data detected (payload byte follows)
                                   0: not detected (no payload byte)
m_HB+2   3       I2C Nack         1: Nack detected
                                   0: not detected
m_HB+2   2       I2C Ack          1: Ack detected
                                   0: not detected
m_HB+2   1       I2C Stop         1: Stop detected
                                   0: not detected
m_HB+2   0       I2C Start/Restart 1: Start/Restart detected
                                   0: not detected
```

Multiple condition bits may be set simultaneously if multiple events occur within the
same bus observation window.

IMPLEMENTATION ASSUMPTION: The I2C monitor logic observes each bus event transition
and sets the corresponding bit(s). The packet is dispatched when at least one bit is
set. If I2C Data bit is set, the payload byte is appended at m_HB+3.

### 5.3 Data Byte (Table 7-16)

SPEC FACT (7.5.1.2, p241): The conditional payload byte is used for slave address,
offset address, wdata, and rdata.

```
Byte     Bit(s)  Field  Description
------   ------  -----  -----------
m_HB+3   7:0     data   Slave address, offset address, wdata, or rdata
                         Present ONLY if I2C Data bit (m_HB+2[4]) = 1
```

### 5.4 Byte Mode Packet Layout

```
  Offset from ASEP header base (m_HB):
  +--------+--------+--------+
  | m_HB+1 | m_HB+2 | m_HB+3 |    (m_HB+3 present only if Data bit set)
  +--------+--------+--------+
  | cmd_id |Mode/Err| data   |
  |  [7:0] |/Cond   | [7:0]  |
  +--------+--------+--------+
     Byte 1   Byte 2  Byte 3
               ^
               bit7=Mode[1]=1
               bit6=I2CError
               bit5=Mode[0]=0
               bit4=Data
               bit3=Nack
               bit2=Ack
               bit1=Stop
               bit0=Start/Restart
```

Minimum packet size (no data byte): 2 bytes past m_HB (bytes at m_HB+1 and m_HB+2).
Maximum packet size (with data byte): 3 bytes past m_HB.

No CRC footer is defined for byte mode. The ASEP common footer provides integrity
protection at the container level.

---

## 6. Bulk Mode (Section 7.5.2)

### 6.1 Purpose

SPEC FACT (7.5.4, p246): "Bulk mode is accumulating I2C commands of the same kind.
I2C condition bits are implied."

Bulk mode encodes complete I2C transactions (write with data payload, read request,
ACK/NACK bitmap, read data response) as structured packets with explicit length fields.
Multiple bytes of data are grouped into a single ASEP packet, reducing overhead
compared to byte mode for burst transfers.

### 6.2 Bulk Mode Command Format (Table 7-17)

SPEC FACT (7.5.2.1, p241): In I2C Bulk mode, the lower bits of the command byte at
m_HB+2 are defined as:

```
Byte     Bit(s)  Field            Description
------   ------  -----            -----------
m_HB+2   7       I2C Mode[1]      = 0 (Bulk Mode)
m_HB+2   6       I2C Error        1: I2C bus hang-up; 0: no error
m_HB+2   5       I2C Mode[0]      = 0 (Bulk Mode)
m_HB+2   4       Reserved
m_HB+2   3       I2C Address Mode 0: Random location (Offset Address Set)
                                   1: Current location (Offset Address not Set)
m_HB+2   2:0     I2C Format Type  000: Write command format
                                   001: Read command format
                                   010: Ack/Nack format
                                   011: Read response format
                                   1xx: Reserved
```

The I2C Format Type field (bits 2:0) determines which command sub-format follows in
the remaining bytes of the packet.

### 6.3 Write Command (Tables 7-18 and 7-19)

SPEC FACT (7.5.2.2, p241-242): The header of the write command contains five
additional bytes:

```
Byte     Bit(s)  Field               Description
------   ------  -----               -----------
m_HB+3   7:0     Slave address       Slave address of the I2C write command
m_HB+4   7:0     Offset address[15:8] Offset address of the I2C write command (MSB)
m_HB+5   7:0     Offset address[7:0]  Offset address of the I2C write command (LSB)
m_HB+6   7:0     Length[15:8]        Length in bytes of the write data (MSB)
m_HB+7   7:0     Length[7:0]         Length in bytes of the write data (LSB)
```

SPEC FACT (7.5.2.2, p242): The payload contains as many bytes as indicated in the
Length field:

```
Byte          Bit(s)  Field  Description
------        ------  -----  -----------
m_HB+7+n      7:0     wdata  n-th byte of write data (n = 1, 2, ..., Length)
```

Note: When I2C Address Mode (m_HB+2[3]) = 1 (current location), the offset address
bytes (m_HB+4, m_HB+5) are still present in the header but are semantically ignored
by the slave; the slave uses its internal current address pointer.

IMPLEMENTATION ASSUMPTION: The bulk write encoder collects all write data bytes from
the I2C Master and assembles the header+payload atomically before dispatching via
DLP_TX. The Length field is determined at packet assembly time.

```
  Bulk Write Packet Layout (Format Type = 000):
  +--------+--------+--------+--------+--------+--------+--------+-------...------+
  | m_HB+1 | m_HB+2 | m_HB+3 | m_HB+4 | m_HB+5 | m_HB+6 | m_HB+7 | m_HB+8 ... |
  +--------+--------+--------+--------+--------+--------+--------+-------...------+
  | cmd_id |00E00aFFF| SlvAdr | Off[15:8]| Off[7:0]| Len[15:8]| Len[7:0]| wdata |
  +--------+--------+--------+--------+--------+--------+--------+-------...------+
  (E=I2CError, a=AddrMode, FFF=FormatType=000)
```

### 6.4 Read Command (Table 7-20)

SPEC FACT (7.5.2.3, p242): The header of the read command contains five additional
bytes and there is no payload:

```
Byte     Bit(s)  Field               Description
------   ------  -----               -----------
m_HB+3   7:0     Slave address       Slave address of the I2C read command
m_HB+4   7:0     Offset address[15:8] Offset address of the I2C read command (MSB)
m_HB+5   7:0     Offset address[7:0]  Offset address of the I2C read command (LSB)
m_HB+6   7:0     Length[15:8]        Length in bytes of read data to obtain (MSB)
m_HB+7   7:0     Length[7:0]         Length in bytes of read data to obtain (LSB)
```

SPEC FACT (7.5.2.3, p242): The I2C offset address starting from bytes 4 and 5
("Offset address") is incremented in each subsequent I2C command.

There is no payload in the read command.

```
  Bulk Read Packet Layout (Format Type = 001):
  +--------+--------+--------+--------+--------+--------+--------+
  | m_HB+1 | m_HB+2 | m_HB+3 | m_HB+4 | m_HB+5 | m_HB+6 | m_HB+7 |
  +--------+--------+--------+--------+--------+--------+--------+
  | cmd_id |00E0aFFF| SlvAdr |Off[15:8]| Off[7:0]|Len[15:8]| Len[7:0]|
  +--------+--------+--------+--------+--------+--------+--------+
  (FFF=001)     No payload bytes
```

### 6.5 ACK/NACK Command (Tables 7-21 and 7-22)

SPEC FACT (7.5.2.4, p242-243): The header of the ACK/NACK command contains three
additional bytes:

```
Byte     Bit(s)  Field          Description
------   ------  -----          -----------
m_HB+3   7:0     Length[15:8]   Length in BITS of the ack/nack data being returned (MSB)
m_HB+4   7:0     Length[7:0]    Length in BITS of the ack/nack data being returned (LSB)
m_HB+5   7:0     Slave address  Slave address corresponding to the I2C write command
```

SPEC FACT (7.5.2.4, p243): The payload of the ACK/NACK command has
ceiling((Length+3)/8) bytes:

```
Byte         Bit(s)  Field        Description
------       ------  -----        -----------
m_HB+5+n     7:0     Ack/nack     Packed ACK(=0)/NACK(=1) bits as follows:
                      data         For n=1 (first payload byte):
                                    bit 7: ACK/NACK for slave address
                                    bit 6: ACK/NACK for offset address[15:8]
                                           (set to 1 for 1-byte offset or if
                                            current location was used)
                                    bit 5: ACK/NACK for offset address[7:0]
                                           (set to 1 if current location used)
                                    bit 4: ACK/NACK for wdata at offset+(n-1)*8
                                    bit 3: ACK/NACK for wdata at offset+(n-1)*8+1
                                    bit 2: ACK/NACK for wdata at offset+(n-1)*8+2
                                    bit 1: ACK/NACK for wdata at offset+(n-1)*8+3
                                    bit 0: ACK/NACK for wdata at offset+(n-1)*8+4
                                   For n>1:
                                    bit 7: ACK/NACK for wdata at offset+(n-2)*8+5
                                    bit 6: ACK/NACK for wdata at offset+(n-2)*8+6
                                    bit 5: ACK/NACK for wdata at offset+(n-1)*8+7
                                    bits 4:0: as above
                                   Unused bits in the last byte: set to 1 (=NACK)
```

SPEC FACT (7.5.2.4, p243): "The root node should implement a timeout watchdog
(depending on the schedule cycle for this ASEP and the application use case) and
treat a timeout as a NACK."

### 6.6 Read Response Format (Tables 7-23 and 7-24)

SPEC FACT (7.5.2.5, p243-244): The header of the read response command contains three
additional bytes:

```
Byte     Bit(s)  Field          Description
------   ------  -----          -----------
m_HB+3   7:0     Length[15:8]   Length in read requests of the response data (MSB)
m_HB+4   7:0     Length[7:0]    Length in read requests of the response data (LSB)
m_HB+5   7:0     Slave address  Slave address corresponding to the I2C read command
```

SPEC FACT (7.5.2.5, p243-244): The payload of the read response command has
(Length+1) bytes:

```
Byte     Bit(s)  Field        Description
------   ------  -----        -----------
m_HB+6   7:0     Ack/nack     ACK(=0)/NACK(=1) status byte:
                  data          bit 7: slave address ACK/NACK
                                bit 6: offset address[15:8] ACK/NACK
                                       (set to 1 if offset is 1 byte long)
                                bit 5: offset address[7:0] ACK/NACK
                                bits 4:0: unused, set to 1
m_HB+6+m 7:0     rdata        Return byte of the m-th read command execution
                               (m = 1, 2, ..., Length)
```

SPEC FACT (7.5.2.5, p244): "The root node should implement a timeout watchdog
(depending on the schedule cycle for this ASEP and the application use case) and
treat a timeout as a NACK."

```
  Read Response Packet Layout (Format Type = 011):
  +--------+--------+--------+--------+--------+--------+--------+-------...------+
  | m_HB+1 | m_HB+2 | m_HB+3 | m_HB+4 | m_HB+5 | m_HB+6 |m_HB+7  | m_HB+8 ... |
  +--------+--------+--------+--------+--------+--------+--------+-------...------+
  | cmd_id |00E0aFFF|Len[15:8]| Len[7:0]| SlvAdr | AN_byte| rdata1 | rdata2 ...  |
  +--------+--------+--------+--------+--------+--------+--------+-------...------+
  (FFF=011, AN_byte=ack/nack status)
```

### 6.7 Bulk Mode Footer (Table 7-25)

SPEC FACT (7.5.2.6, p244): The bulk mode footer is a CRC32 appended at the end of
the ASEP packet (last 4 bytes):

```
Byte        Bit(s)  Field        Description
------      ------  -----        -----------
m_END-3     7:0     CRC32[31:24] Checksum over all ASEP packet bytes 0 to "m_END-4",
m_END-2     7:0     CRC32[23:16] where m_END is the last byte index of the entire
m_END-1     7:0     CRC32[15:8]  ASEP packet. See Section 4.2.9 for CRC32 algorithm.
m_END       7:0     CRC32[7:0]
```

IMPLEMENTATION ASSUMPTION: The CRC32 polynomial and computation algorithm are the same
as defined in Section 4.2.9 and used elsewhere in the ASA specification. The footer
covers all bytes from byte 0 of the ASEP packet through m_END-4 inclusive.

---

## 7. Configuration Mode (Section 7.5.3)

### 7.1 Purpose and Trigger Rule

SPEC FACT (7.5.3, p244): "For configuration mode, the I2C Master side ASA node shall
send the contents of relevant ASA registers once after startup and once after each
register write access. The I2C slave side ASA node shall update its registers with
the content of the ASEP packet."

Configuration mode propagates the local I2C configuration registers (clock rate,
slave addresses) from the I2C Master side node to the I2C Slave side node through
the ASEP tunnel. This ensures both nodes operate with consistent I2C bus parameters.

Trigger conditions:
1. After startup (power-on or link re-establishment)
2. After any OAM register write to 4/5.i.0200 (I2C clock rate) or 4/5.i.0201-0208
   (I2C slave addresses) on the I2C Master side node

### 7.2 Configuration Mode Command Format (Table 7-26)

SPEC FACT (7.5.3.1, p244-245): In I2C Configuration mode, the lower bits of byte
m_HB+2 and the next byte m_HB+3 are defined as:

```
Byte     Bit(s)  Field                Description
------   ------  -----                -----------
m_HB+2   7       I2C Mode[1]          = 0 (Config Mode)
m_HB+2   6       I2C Error            1: I2C bus hang-up; 0: no error
m_HB+2   5       I2C Mode[0]          = 1 (Config Mode)
m_HB+2   4:3     Reserved
m_HB+2   2:0     Configuration        000: Write command mode (I2C Master sends config)
                  command mode         001: Read command mode (I2C Master requests config)
                                       010: Ack/Nack mode (I2C Slave confirms write)
                                       011: Read response mode (I2C Slave returns config)
                                       1xx: Reserved
m_HB+3   7:4     Reserved
m_HB+3   3:0     No. of I2C           0: reserved
                  addresses            Number of I2C slave addresses in this message
                                       (valid range: 1-15)
```

The No. of I2C addresses field (m_HB+3[3:0]) indicates how many slave address entries
follow in the payload. Value 0 is reserved and must not be used.

### 7.3 Configuration Write Command (Table 7-27)

SPEC FACT (7.5.3.2, p245): The configuration mode write payload contains as many I2C
slave address entries as indicated in the header (No. of I2C addresses field):

```
Byte     Bit(s)  Field                Description
------   ------  -----                -----------
m_HB+4   7:6     Reserved
m_HB+4   5:0     I2C clock rate[5:0]  I2C clock frequency from register 3.5.4.1
                                       (value in multiples of 100 kHz)
m_HB+5+n 7       offset address       I2C slave offset address length flag from
                  length flag          register 3.5.4.2, entry number n
                                       1: 16-bit offset address
                                       0: 8-bit offset address
m_HB+5+n 6:0     SL address[6:0]      7-bit I2C slave address from register 3.5.4.2,
                                       entry number n
                                       (n = 0, 1, ..., No. of I2C addresses - 1)
```

The total payload size is 1 (clock rate byte) + N (slave address entries), where N is
the value of No. of I2C addresses.

### 7.4 Configuration Read Command (Section 7.5.3.3)

SPEC FACT (7.5.3.3, p245): "There is no payload for the configuration mode read."

The configuration read command consists of only the common header bytes (m_HB+1 and
m_HB+2) plus the mode byte at m_HB+3 with Configuration command mode = 001. No
additional bytes follow before the footer.

### 7.5 Configuration ACK/NACK Command (Table 7-28)

SPEC FACT (7.5.3.4, p245): The configuration mode ACK/NACK is sent as response to
the write command:

```
Byte     Bit(s)  Field        Description
------   ------  -----        -----------
m_HB+4   7:1     Reserved
m_HB+4   0       ACK/NACK     0: configuration write failed
                  flag         1: configuration write succeeded
```

SPEC FACT (7.5.3.4, p245): "The root node should implement a timeout watchdog
(depending on the schedule cycle for this ASEP and the application use case) and
treat a timeout as a NACK."

### 7.6 Configuration Read Response Command (Table 7-29)

SPEC FACT (7.5.3.5, p246): The configuration mode read response payload mirrors the
write command payload format:

```
Byte     Bit(s)  Field                Description
------   ------  -----                -----------
m_HB+4   7:6     Reserved
m_HB+4   5:0     I2C clock rate[5:0]  I2C clock frequency from register 3.5.4.1
m_HB+5+n 7       offset address       I2C slave offset address length flag from
                  length flag          register 3.5.4.2, entry number n
m_HB+5+n 6:0     SL address[6:0]      7-bit I2C slave address from register 3.5.4.2,
                                       entry number n
```

SPEC FACT (7.5.3.5, p246): "The root node should implement a timeout watchdog
(depending on the schedule cycle for this ASEP and the application use case) and
treat a timeout as a NACK."

### 7.7 Configuration Command Footer (Table 7-30)

SPEC FACT (7.5.3.6, p246): The configuration mode footer is a CRC32 appended at the
end of the ASEP packet:

```
Byte        Bit(s)  Field        Description
------      ------  -----        -----------
m_END-3     7:0     CRC32[31:24] Checksum over all payload bytes 0 to "m_END-4",
m_END-2     7:0     CRC32[23:16] where m_END is the last byte index of the entire
m_END-1     7:0     CRC32[15:8]  ASEP packet. See Section 4.2.9.
m_END       7:0     CRC32[7:0]
```

### 7.8 Configuration Mode Packet Layouts

```
  Config Write Layout (cmd_mode=000):
  +-------+-------+-------+-------+-------+-------...------+-------+-------+-------+-------+
  |m_HB+1 |m_HB+2 |m_HB+3 |m_HB+4 |m_HB+5 | m_HB+6 ...   |END-3  |END-2  |END-1  | END   |
  +-------+-------+-------+-------+-------+-------...------+-------+-------+-------+-------+
  |cmd_id |01E0000|NNN_Nslv|rr_rate|flg_adr| flg_adr(n) ...|CRC[31]|CRC[23]|CRC[15]|CRC[7] |
  +-------+-------+-------+-------+-------+-------...------+-------+-------+-------+-------+

  Config Read Layout (cmd_mode=001):
  +-------+-------+-------+-------+-------+-------+-------+
  |m_HB+1 |m_HB+2 |m_HB+3 |END-3  |END-2  |END-1  | END   |
  +-------+-------+-------+-------+-------+-------+-------+
  |cmd_id |01E0001|NNN_Nslv|CRC[31]|CRC[23]|CRC[15]|CRC[7] |
  +-------+-------+-------+-------+-------+-------+-------+

  Config ACK/NACK Layout (cmd_mode=010):
  +-------+-------+-------+-------+-------+-------+-------+-------+
  |m_HB+1 |m_HB+2 |m_HB+3 |m_HB+4 |END-3  |END-2  |END-1  | END   |
  +-------+-------+-------+-------+-------+-------+-------+-------+
  |cmd_id |01E0010|NNN_Nslv|rrrr_rA|CRC[31]|CRC[23]|CRC[15]|CRC[7] |
  +-------+-------+-------+-------+-------+-------+-------+-------+
  (A=ACK/NACK flag)
```

---

## 8. Register Model

### 8.1 I2C Clock Rate Register (4/5.i.0200)

Section: 3.5.4.1 (p78), Table 3-88

SPEC FACT: Register name "I2C clock rate". Present when stream type is I2C.

```
Bit(s)  Field           R/W   Access  Privilege  Description
------  -----           ---   ------  ---------  -----------
15:6    Reserved        -     -       -          Reserved; write as 0
5:0     I2C clock rate  RW    O       RID        I2C slave side clock rate in
                                                  multiples of 100 kHz.
                                                  Valid range: 0x01..0x3F
                                                  (100 kHz to 6.3 MHz)
                                                  0x00: resets the I2C interface
                                                  controller (upon I2C hang-up)
```

Access notation: RW = Read/Write; O = accessible via OAM channel and locally;
RID = Root nodeID privilege required.

Clock rate encoding table:
```
  Value  Frequency
  -----  ---------
  0x00   Reset/deactivate I2C controller
  0x01   100 kHz  (standard mode)
  0x04   400 kHz  (fast mode)
  0x0A   1.0 MHz  (fast-mode plus, FM+)
  0x1A   2.6 MHz  (approximation)
  0x28   4.0 MHz
  0x3F   6.3 MHz  (maximum encodable)
```

SPEC FACT: Writing 0x00 to bits 5:0 resets the I2C interface controller. This is the
specified recovery mechanism for I2C bus hang-up conditions.

SPEC FACT: The I2C clock rate value from this register is transmitted in Configuration
Mode write and read response packets at byte m_HB+4 bits 5:0 (Table 7-27, Table 7-29).

### 8.2 I2C Slave Address Registers (4/5.i.0201-4/5.i.0208)

Section: 3.5.4.2 (p78-80), Tables 3-89 and 3-90

SPEC FACT: 8 registers contain up to 15 slave address entries (two per register;
entry 0 uses only the lower half of register 4/5.i.0201, entry 14 uses only the
lower half of register 4/5.i.0208; the upper half of 4/5.i.0208 is reserved).

Wait -- the spec states 8 registers, each holding two entries. Register 0201 holds
entries 0 (lower) and 1 (upper), ..., register 0208 holds entry 14 (lower) and
reserved (upper). That yields up to 15 active entries (0..14).

Per-register bit field (Table 3-89):

```
Bit(s)  Field                    R/W   Access  Privilege  Description
------  -----                    ---   ------  ---------  -----------
15      Offset address length    RW    O       RID        Flag for entry N (upper)
        flag N                                             1: 16-bit offset address
                                                           0: 8-bit offset address
14:8    Slave address N          RW    O       RID        7-bit slave address (entry N)
                                                           0x78 (1111_000) when unused
7       Offset address length    RW    O       RID        Flag for entry M (lower)
        flag M                                             1: 16-bit offset address
                                                           0: 8-bit offset address
6:0     Slave address M          RW    O       RID        7-bit slave address (entry M)
                                                           0x78 (1111_000) when unused
```

SPEC FACT: The unused value 0x78 (1111_000) is not in conflict with the I2C bus
specification because 10-bit addressing is not supported by this ASEP.

Slave address register mapping (Table 3-90):

```
  Entry  Register     Bits   Entry  Register     Bits
  -----  --------     ----   -----  --------     ----
    0    4.i.0201     7:0      8    4.i.0205     7:0
    1    4.i.0201    15:8      9    4.i.0205    15:8
    2    4.i.0202     7:0     10    4.i.0206     7:0
    3    4.i.0202    15:8     11    4.i.0206    15:8
    4    4.i.0203     7:0     12    4.i.0207     7:0
    5    4.i.0203    15:8     13    4.i.0207    15:8
    6    4.i.0204     7:0     14    4.i.0208     7:0
    7    4.i.0204    15:8   (rsvd)  4.i.0208    15:8
```

IMPLEMENTATION ASSUMPTION: The same register addresses are present in domain 5
(ASD side) as domain 4 (ASE side), both accessible with the same 4/5.i notation.
The ASD registers reflect the configuration received via Configuration Mode packets.

### 8.3 Common ASEP Registers Used by I2C

| Register | Address | Description |
|----------|---------|-------------|
| cmd_id counter | 4.i.0001-0003 | Full Packet ID (40-bit sequence counter) |
| Stream Type | 4/5.i.0004 | Must be set to I2C type code |
| Pin Capability | 4/5.i.0051-0058 | Reports I2C-capable pin pairs |
| Pin Config | 4/5.i.0059-0062 | Assigns pins to I2C interface-select |
| I2C clock rate | 4/5.i.0200 | See Section 8.1 above |
| I2C slave addrs | 4/5.i.0201-0208 | See Section 8.2 above |
| ASE Status | 4.i.0101 | I2C-specific status bits |
| ASD Watchdog | 5.i.0101 | Timeout watchdog timer |

---

## 9. TX Data Flow

### 9.1 ASE TX Flow (I2C Master side -> DLP_TX)

This flow describes how the I2C Master side ASEP I2C module (ASE) encapsulates
I2C bus events into ASEP packets and delivers them to the DLL.

```
  I2C Bus Events (SDA/SCL)
         |
         v
  +-------------------+
  | I2C Bus Monitor   |
  | (SDA/SCL capture) |
  | Detects:          |
  |  - Start/Restart  |
  |  - Stop           |
  |  - Data byte      |
  |  - Ack/Nack       |
  +--------+----------+
           |
           | Event stream
           v
  +-------------------+
  | Mode Selector     |<--- mode register (byte vs. bulk vs. config)
  |                   |
  | Byte mode:        |
  |  emit one packet  |
  |  per bus event    |
  |                   |
  | Bulk mode:        |
  |  accumulate until |
  |  transaction end  |
  |                   |
  | Config mode:      |
  |  triggered by     |
  |  register write   |
  +--------+----------+
           |
           v
  +-------------------+
  | Packet Assembler  |
  | - Insert cmd_id   |
  |   (assign new ID  |
  |    for each write |
  |    or read cmd)   |
  | - Set Mode bits   |
  | - Set I2CError if |
  |   bus hang-up     |
  | - Append payload  |
  | - Compute CRC32   |
  |   (bulk/config)   |
  +--------+----------+
           |
           v
  +-------------------+
  | ASEP Common       |
  | Header/Footer     |<--- PTB timestamp, sequence counter
  | Framing           |
  +--------+----------+
           |
           v
  +-------------------+
  | DLP_TX            |
  | .dataUnit()       |----> DLL Mapper -> PCS TX -> PHY
  +-------------------+

  Signals at DLP_TX interface:
    DLP_TX.indicateSlot(I2C_stream) -- DLL requests data for this slot
    DLP_TX.dataUnit(payload, len)   -- ASE delivers assembled packet
    DLP_TX.yield()                  -- ASE signals no data available
```

IMPLEMENTATION ASSUMPTION: The ASE I2C TX path maintains a small FIFO to buffer
assembled packets between I2C bus event capture and DLL slot scheduling. The FIFO
depth is implementation-dependent but must accommodate at least one complete bulk
packet.

IMPLEMENTATION ASSUMPTION: The cmd_id is incremented for each new write command or
read command. The same cmd_id is echoed back in the corresponding ACK/NACK or read
response. The cmd_id field is 8 bits wide (m_HB+1) and wraps at 0xFF.

### 9.2 ASD TX Flow (I2C Slave side -> DLP_TX, response path)

When the I2C Slave side executes a write or read command received from DLP_RX, the
resulting ACK/NACK or read data must be returned to the master side. This uses the
ASD's DLP_TX connection:

```
  I2C Bus (Slave side: SDA/SCL)
         |
         ^ (ACK/NACK bits driven by slave ICs)
         |
  +-------------------+
  | I2C Master Driver |
  | (ASD drives I2C   |
  |  bus as master)   |
  +--------+----------+
           |
           | ACK/NACK per byte + read data
           v
  +-------------------+
  | Response Assembler|
  | (Bulk or Config   |
  |  mode response)   |
  | - Use same cmd_id |
  |   from request    |
  | - Pack ACK bits   |
  |   or rdata bytes  |
  | - Compute CRC32   |
  +--------+----------+
           |
           v
  +-------------------+
  | ASEP Common       |
  | Header/Footer     |
  | Framing           |
  +--------+----------+
           |
           v
  +-------------------+
  | DLP_TX (ASD side) |----> DLL Mapper -> PCS TX -> PHY
  +-------------------+
```

---

## 10. RX Data Flow

### 10.1 ASE RX Flow (I2C Master side, DLP_RX -> I2C response to host)

The ASE receives ACK/NACK and read response packets that were generated by the ASD
and tunneled back across the ASA link:

```
  PHY -> PCS RX -> DLL Demux
         |
         v
  +-------------------+
  | DLP_RX            |
  | .dataUnit()       |<---- From DLL
  +--------+----------+
           |
           v
  +-------------------+
  | ASEP Common       |
  | Header/Footer     |
  | Checker           |
  +--------+----------+
           |
           v
  +-------------------+
  | Packet Decoder    |
  | - Check Mode bits |
  | - Verify CRC32    |
  |   (bulk/config)   |
  | - Match cmd_id    |
  |   to pending req  |
  | - Extract payload |
  +--------+----------+
           |
           v
  +-------------------+
  | I2C Response      |
  | Handler           |
  | Bulk ACK/NACK:    |
  |  present to host  |
  |  or check result  |
  | Bulk read resp:   |
  |  deliver rdata    |
  | Config ACK/NACK:  |
  |  update status    |
  | Timeout watchdog: |
  |  fire if no resp  |
  |  within deadline  |
  +-------------------+
```

IMPLEMENTATION ASSUMPTION: The timeout watchdog timer is started when a write or read
bulk command is dispatched and is cancelled when the corresponding ACK/NACK or read
response is received. The timer period is application-defined and must account for the
round-trip ASEP scheduling latency.

### 10.2 ASD RX Flow (I2C Slave side, DLP_RX -> I2C bus)

The ASD receives write/read commands from the ASE and executes them on the local I2C
bus:

```
  PHY -> PCS RX -> DLL Demux
         |
         v
  +-------------------+
  | DLP_RX (ASD side) |<---- From DLL
  +--------+----------+
           |
           v
  +-------------------+
  | ASEP Common       |
  | Header/Footer     |
  | Checker           |
  +--------+----------+
           |
           v
  +-------------------+
  | Packet Decoder    |
  | - Check Mode bits |
  | - Verify CRC32    |
  | - Extract cmd_id, |
  |   slave addr,     |
  |   offset, length, |
  |   write data      |
  +--------+----------+
           |
           v
  +-------------------+
  | I2C Bus Master    |
  | Controller        |
  | - Drive SDA/SCL   |
  |   at configured   |
  |   clock rate      |
  |   (reg 4/5.i.0200)|
  | - Issue Start     |
  | - Send slave addr |
  | - Send offset     |
  | - Write or Read   |
  | - Collect ACK bits|
  | - Issue Stop      |
  +--------+----------+
           |
           v
  I2C Bus (SDA/SCL to slave ICs)
```

IMPLEMENTATION ASSUMPTION: The ASD's I2C bus controller uses the clock rate from
register 4/5.i.0200 (updated via Configuration Mode packets or local register write).
The slave address validation uses entries from registers 4/5.i.0201-0208.

### 10.3 Config Mode RX Flow (ASD receiving configuration)

```
  Receive Config Write packet
         |
         v
  +-------------------+
  | Config Decoder    |
  | - Extract clock   |
  |   rate (m_HB+4    |
  |   bits 5:0)       |
  | - Extract N slave |
  |   address entries |
  +--------+----------+
           |
           v
  +-------------------+
  | Register Update   |
  | - Write clock     |
  |   rate to local   |
  |   4/5.i.0200      |
  | - Write slave     |
  |   addresses to    |
  |   4/5.i.0201-0208 |
  +--------+----------+
           |
           v
  +-------------------+
  | Send Config ACK   |
  | via DLP_TX:       |
  |  flag = 1 (ok)    |
  |  or 0 (failed)    |
  +-------------------+
```

SPEC FACT: The I2C slave side ASA node shall update its registers with the content
of the Configuration Mode ASEP packet (7.5.3, p244).

---

## 11. Interface to ASEP Common Framing

SPEC FACT (7.5, p240): "The first additional byte and first three bits of second
additional byte of all I2C commands have the same format" (Table 7-14, the common
command format).

The ASEP I2C module interfaces with the ASEP common framing layer, which provides:
- The base header bytes (m_HB+0 and below): sequence counter, PTB timestamps
- The common DLL container encapsulation

The I2C-specific fields begin at m_HB+1 (cmd_id) and m_HB+2 (mode/error/sub-format).

```
  ASEP Container Structure:
  +----------------------------------+
  | ASEP Common Header               |
  |  (PTB timestamps, seq counter)   |
  |  Bytes 0 .. m_HB                 |
  +----------------------------------+
  | I2C-Specific Content             |
  |  Byte m_HB+1: cmd_id             |
  |  Byte m_HB+2: mode/error/format  |
  |  Byte m_HB+3+: mode-dependent    |
  +----------------------------------+
  | Footer (CRC32, 4 bytes)          |
  |  Bytes m_END-3 .. m_END          |
  |  (bulk mode and config mode only)|
  +----------------------------------+
```

Interface signals to/from ASEP common framing:

| Signal | Direction | Description |
|--------|-----------|-------------|
| i2c_pkt_data[7:0] | I2C->Common | Byte stream of assembled I2C packet |
| i2c_pkt_valid | I2C->Common | Byte valid signal |
| i2c_pkt_sop | I2C->Common | Start of packet marker |
| i2c_pkt_eop | I2C->Common | End of packet marker |
| common_pkt_data[7:0] | Common->I2C | Received packet byte stream |
| common_pkt_valid | Common->I2C | Byte valid signal |
| common_pkt_sop | Common->I2C | Start of packet marker |
| common_pkt_eop | Common->I2C | End of packet marker |
| dlp_tx_slot | DLL->Common | Slot available for TX |
| dlp_rx_data | DLL->Common | Received DLL data |

IMPLEMENTATION ASSUMPTION: The packet byte stream interface above is a representative
RTL interface; the actual implementation may use a FIFO with handshaking or a parallel
bus depending on the project's standard bus protocol.

---

## 12. Interface to Physical I2C Bus

The physical I2C interface is a standard two-wire open-drain bus (SDA and SCL). The
ASEP I2C module must interface to an I2C bus controller that drives SDA/SCL in master
mode and samples in slave mode.

```
  I2C Bus Interface Signals (ASE side, I2C Master role):
  +---------------------------+
  |   ASEP I2C ASE            |
  |                           |
  |  sda_in  <-------         |---> SDA (sampled from bus)
  |  sda_out ------->         |---> SDA (driven to bus, open-drain)
  |  sda_oe  (output enable)  |
  |  scl_in  <-------         |---> SCL (sampled from bus)
  |  scl_out ------->         |---> SCL (driven to bus, open-drain)
  |  scl_oe  (output enable)  |
  +---------------------------+

  I2C Bus Interface Signals (ASD side, I2C Master-to-slaves role):
  +---------------------------+
  |   ASEP I2C ASD            |
  |                           |
  |  sda_in  <-------         |---> SDA (ACK/NACK from slaves)
  |  sda_out ------->         |---> SDA (addresses, data to slaves)
  |  sda_oe  (output enable)  |
  |  scl_out ------->         |---> SCL (generated from clock rate reg)
  |  scl_oe  (always 1)       |
  +---------------------------+
```

| Signal | Direction | Description |
|--------|-----------|-------------|
| sda_in | I2C bus -> ASE/ASD | Serial data sampled from I2C bus |
| sda_out | ASE/ASD -> I2C bus | Serial data driven to I2C bus |
| sda_oe | ASE/ASD -> I2C bus | Output enable for SDA (open-drain) |
| scl_in | I2C bus -> ASE | SCL sampled (for clock stretching detection) |
| scl_out | ASE/ASD -> I2C bus | SCL driven by master controller |
| scl_oe | ASE/ASD -> I2C bus | Output enable for SCL |
| i2c_clk_rate[5:0] | RegModel -> I2C ctrl | Clock rate from 4/5.i.0200[5:0] |
| i2c_reset | RegModel -> I2C ctrl | Asserted when 4/5.i.0200[5:0] = 0x00 |

IMPLEMENTATION ASSUMPTION: The I2C bus clock is generated by dividing a system
reference clock using the value from register 4/5.i.0200 bits 5:0. The formula is:
  f_I2C = i2c_clk_rate[5:0] * 100 kHz
A value of 0x00 holds the I2C controller in reset.

---

## 13. Interface to Register Model

The ASEP I2C module accesses the following registers through the local register
interface:

| Register | Address | Direction | When Accessed |
|----------|---------|-----------|---------------|
| I2C clock rate | 4/5.i.0200 | Read (by I2C ctrl) | At startup and when updated |
| I2C clock rate | 4/5.i.0200 | Write (by config RX) | On Config Mode packet receipt |
| I2C slave addrs | 4/5.i.0201-0208 | Read (by ASD TX) | When building Config response |
| I2C slave addrs | 4/5.i.0201-0208 | Write (by config RX) | On Config Mode write packet |
| Stream Type | 4/5.i.0004 | Read (by common framing) | At DLL enumeration |
| ASE Status | 4.i.0101 | Write (by ASE) | On I2C error or status change |
| ASD Watchdog | 5.i.0101 | Write (by ASD) | On timeout or completion |

```
  Register Interface Signals:
  reg_rd_addr[14:0]  --> Register File  (register address)
  reg_rd_domain[2:0] --> Register File  (domain: 4=ASE, 5=ASD)
  reg_rd_dlp[5:0]    --> Register File  (DLP instance index i)
  reg_rd_data[15:0]  <-- Register File  (returned register value)
  reg_wr_addr[14:0]  --> Register File  (register address)
  reg_wr_domain[2:0] --> Register File
  reg_wr_dlp[5:0]    --> Register File
  reg_wr_data[15:0]  --> Register File
  reg_wr_en          --> Register File
  reg_wr_ack         <-- Register File  (write acknowledged)
```

SPEC FACT (7.5.3, p244): The I2C slave side ASA node (ASD) shall update its registers
with the content of the Configuration Mode ASEP packet. This means the ASD's config
RX path must perform register writes to its local 4/5.i.0200 and 4/5.i.0201-0208.

IMPLEMENTATION ASSUMPTION: Register writes triggered by Configuration Mode packets
use the same local register write path as OAM-driven register writes, but with a
different source identifier. The write access control (OAM channel privilege RID) does
not apply to internal register updates from the local ASEP logic.

---

## 14. RTL Submodules

```
  +================================================================+
  |                    asep_i2c_top                                 |
  |                                                                  |
  |  +-----------------------+    +-----------------------+          |
  |  |  i2c_ase              |    |  i2c_asd              |          |
  |  |  (Master side)        |    |  (Slave side)         |          |
  |  |                       |    |                       |          |
  |  | +-------------------+ |    | +-------------------+ |          |
  |  | | i2c_bus_monitor   | |    | | i2c_bus_master    | |          |
  |  | | Detects Start,    | |    | | Drives SDA/SCL    | |          |
  |  | | Stop, Data, Ack,  | |    | | from clock rate   | |          |
  |  | | Nack on SDA/SCL   | |    | | register          | |          |
  |  | +--------+----------+ |    | +--------+----------+ |          |
  |  |          |            |    |          |            |          |
  |  | +--------v----------+ |    | +--------v----------+ |          |
  |  | | byte_mode_encoder | |    | | cmd_executor      | |          |
  |  | | Packs event bits  | |    | | Executes write or | |          |
  |  | | into cmd byte     | |    | | read I2C txn from | |          |
  |  | +--------+----------+ |    | | decoded ASEP pkt  | |          |
  |  |          |            |    | +--------+----------+ |          |
  |  | +--------v----------+ |    |          |            |          |
  |  | | bulk_mode_encoder | |    | +--------v----------+ |          |
  |  | | Accumulates write | |    | | bulk_resp_builder | |          |
  |  | | or read cmd into  | |    | | Assembles ACK/NACK| |          |
  |  | | header+payload    | |    | | or read response  | |          |
  |  | +--------+----------+ |    | | packet with       | |          |
  |  |          |            |    | | cmd_id echo       | |          |
  |  | +--------v----------+ |    | +--------+----------+ |          |
  |  | | config_tx         | |    |          |            |          |
  |  | | Builds Config     | |    | +--------v----------+ |          |
  |  | | Write packet from | |    | | config_rx         | |          |
  |  | | registers on      | |    | | Decodes Config    | |          |
  |  | | startup or write  | |    | | Write, updates    | |          |
  |  | +--------+----------+ |    | | local registers,  | |          |
  |  |          |            |    | | sends ACK/NACK    | |          |
  |  | +--------v----------+ |    | +--------+----------+ |          |
  |  | | tx_pkt_fifo       | |    |          |            |          |
  |  | | Buffers assembled | |    | +--------v----------+ |          |
  |  | | packets for DLL   | |    | | tx_pkt_fifo (ASD) | |          |
  |  | | slot scheduling   | |    | | Response packets  | |          |
  |  | +--------+----------+ |    | +--------+----------+ |          |
  |  |          |            |    |          |            |          |
  |  | +--------v----------+ |    | +---------v---------+ |          |
  |  | | crc32_engine (TX) | |    | | crc32_engine (TX) | |          |
  |  | | Bulk/Config footer| |    | | Bulk/Config footer| |          |
  |  | +--------+----------+ |    | +--------+----------+ |          |
  |  |          |            |    |          |            |          |
  |  | +--------v----------+ |    | +---------v---------+ |          |
  |  | | rx_pkt_fifo       | |    | | rx_pkt_fifo (ASD) | |          |
  |  | | Buffers received  | |    | | Incoming commands | |          |
  |  | | ACK/NACK/rdata    | |    | | from ASE          | |          |
  |  | +--------+----------+ |    | +--------+----------+ |          |
  |  |          |            |    |          |            |          |
  |  | +--------v----------+ |    | +---------v---------+ |          |
  |  | | crc32_engine (RX) | |    | | crc32_engine (RX) | |          |
  |  | | Verify incoming   | |    | | Verify incoming   | |          |
  |  | | bulk/config CRC   | |    | | bulk/config CRC   | |          |
  |  | +--------+----------+ |    | +--------+----------+ |          |
  |  |          |            |    |          |            |          |
  |  | +--------v----------+ |    | +---------v---------+ |          |
  |  | | resp_matcher      | |    | | pkt_decoder       | |          |
  |  | | Matches cmd_id of | |    | | Decodes mode bits,| |          |
  |  | | response to       | |    | | format type, and  | |          |
  |  | | outstanding req   | |    | | payload fields    | |          |
  |  | +--------+----------+ |    | +--------+----------+ |          |
  |  |          |            |    |          |            |          |
  |  | +--------v----------+ |    |          |            |          |
  |  | | timeout_watchdog  | |    |          |            |          |
  |  | | Per-cmd timer;    | |    |          |            |          |
  |  | | treats expiry as  | |    |          |            |          |
  |  | | NACK (7.5.2.4)    | |    |          |            |          |
  |  | +-------------------+ |    |          |            |          |
  |  +-----------------------+    +-----------------------+          |
  |                                                                  |
  |  +----------------------------+                                   |
  |  | reg_if                     |                                   |
  |  | Local register read/write  |                                   |
  |  | interface to 4/5.i.0200   |                                   |
  |  | and 4/5.i.0201-0208        |                                   |
  |  +----------------------------+                                   |
  +================================================================+
```

### 14.1 Module Descriptions

| Module | Function | ASE/ASD |
|--------|----------|---------|
| asep_i2c_top | Top-level instantiation, I2C DLP port hookup | Both |
| i2c_ase | I2C Master-side ASEP entity | ASE |
| i2c_asd | I2C Slave-side ASEP entity | ASD |
| i2c_bus_monitor | Observe SDA/SCL, detect I2C conditions | ASE |
| byte_mode_encoder | Pack I2C events into byte mode ASEP packets | ASE |
| bulk_mode_encoder | Accumulate I2C transaction into bulk ASEP packets | ASE |
| config_tx | Build and transmit Configuration Mode write packets | ASE |
| tx_pkt_fifo | Buffer assembled packets pending DLL slot | ASE |
| crc32_engine (TX) | Compute CRC32 footer for bulk and config packets | Both |
| rx_pkt_fifo | Buffer received response packets | ASE |
| crc32_engine (RX) | Verify CRC32 on received bulk and config packets | Both |
| resp_matcher | Match received cmd_id to outstanding request | ASE |
| timeout_watchdog | Per-command timeout; on expiry signals NACK | ASE |
| i2c_bus_master | Drive SDA/SCL as I2C master toward slave ICs | ASD |
| cmd_executor | Execute decoded write/read command on I2C bus | ASD |
| bulk_resp_builder | Assemble ACK/NACK or read response packet | ASD |
| config_rx | Decode Config Write packet, update registers | ASD |
| pkt_decoder | Parse mode bits, format type, payload fields | ASD |
| reg_if | Read/write 4/5.i.0200 and 4/5.i.0201-0208 | Both |

### 14.2 Parameter Table

| Parameter | Default | Description |
|-----------|---------|-------------|
| I2C_DLP_ID | 0 | DLP instance index (i) for register addressing |
| NODE_IS_ROOT | 0 | 1=ASE (master side), 0=ASD (slave side) |
| TX_FIFO_DEPTH | 4 | Number of packets in TX FIFO |
| RX_FIFO_DEPTH | 4 | Number of packets in RX FIFO |
| WATCHDOG_CYCLES | 1000 | Default timeout in system clock cycles |
| MAX_SLAVE_ADDRS | 15 | Maximum slave address entries (fixed by spec) |
| MAX_BULK_LENGTH | 65535 | Maximum bulk write/read length in bytes |

---

## 15. Spec Facts vs Implementation Assumptions

### 15.1 Spec Facts (directly from ASA Spec v2.0)

| ID | Section | Fact |
|----|---------|------|
| SF-01 | 7.5, p240 | There are two I2C ASEP modes: Byte Mode and Bulk Mode. |
| SF-02 | 7.5.4, p246 | I2C is bidirectional; both ASE and ASD have DLP_TX and DLP_RX. |
| SF-03 | Table 7-14 | cmd_id is assigned by ASEP on I2C Master side; Slave side echoes it. |
| SF-04 | Table 7-14 | I2C Mode[1:0] = 10=Byte, 00=Bulk, 01=Config, 11=reserved. |
| SF-05 | Table 7-14 | I2C Error bit (m_HB+2[6]) = 1 indicates I2C bus hang-up. |
| SF-06 | Table 7-15 | Byte mode: bits 4:0 of m_HB+2 are Data, Nack, Ack, Stop, Start/Restart. |
| SF-07 | Table 7-16 | Byte mode payload byte at m_HB+3 present only when I2C Data bit set. |
| SF-08 | Table 7-17 | Bulk mode: bit 3 = Address Mode (0=random, 1=current), bits 2:0 = Format Type. |
| SF-09 | Table 7-18 | Bulk write header: slave addr (1B), offset addr (2B), length (2B). |
| SF-10 | Table 7-19 | Bulk write payload: Length bytes of wdata. |
| SF-11 | Table 7-20 | Bulk read: same header as write, no payload. |
| SF-12 | Table 7-21 | Bulk ACK/NACK header: length in BITS (2B), slave addr (1B). |
| SF-13 | Table 7-22 | Bulk ACK/NACK payload: ceiling((Length+3)/8) bytes; 0=ACK, 1=NACK. |
| SF-14 | 7.5.2.4, p243 | Root node should implement timeout watchdog and treat timeout as NACK. |
| SF-15 | Table 7-23 | Bulk read response header: length in read requests (2B), slave addr (1B). |
| SF-16 | Table 7-24 | Bulk read response payload: ack/nack byte + Length bytes of rdata. |
| SF-17 | 7.5.2.5, p244 | Root node should implement timeout watchdog for read response. |
| SF-18 | Table 7-25 | Bulk mode footer: CRC32 over all ASEP packet bytes 0 to m_END-4. |
| SF-19 | 7.5.3, p244 | Config mode: Master sends registers once after startup and after each write. |
| SF-20 | 7.5.3, p244 | Config mode: Slave shall update its registers with ASEP packet content. |
| SF-21 | Table 7-26 | Config mode: cmd_mode 000=Write, 001=Read, 010=ACK/NACK, 011=ReadResp. |
| SF-22 | Table 7-26 | Config mode: m_HB+3[3:0] = No. of I2C addresses (0=reserved). |
| SF-23 | Table 7-27 | Config write: clock rate [5:0] at m_HB+4, then N slave addr entries. |
| SF-24 | 7.5.3.3, p245 | Config read has no payload. |
| SF-25 | Table 7-28 | Config ACK/NACK: single bit flag at m_HB+4[0] (0=fail, 1=success). |
| SF-26 | Table 7-29 | Config read response: same format as config write payload. |
| SF-27 | Table 7-30 | Config footer: CRC32 over all payload bytes 0 to m_END-4. |
| SF-28 | Table 3-88 | Register 4/5.i.0200 bits 5:0: I2C clock rate in 100 kHz multiples. |
| SF-29 | Table 3-88 | Writing 0x00 to 4/5.i.0200[5:0] resets the I2C interface controller. |
| SF-30 | Table 3-89 | Each slave address register holds 2 entries: bits 14:8 and 6:0, with offset flags at bits 15 and 7. |
| SF-31 | Table 3-90 | 15 slave address entries in registers 4/5.i.0201 through 4/5.i.0208 (upper half of 0208 reserved). |
| SF-32 | Table 3-89 | Unused slave address entries set to 0x78 (1111_000). |
| SF-33 | 7.5.4, p247 | Recommended: root node I2C slave address = 0x08 (000_1000). |
| SF-34 | 7.5.4, p247 | Recommended: non-root I2C multi-mode master/slave address = 0x09 (000_1001). |
| SF-35 | App. C, p338 | ASEP connections are quasi-statically routed between ASA nodes on same branch. |

### 15.2 Implementation Assumptions (not defined in spec)

| ID | Assumption |
|----|-----------|
| IA-01 | The ASE I2C TX path maintains a small FIFO to buffer assembled packets. Depth is implementation-defined. |
| IA-02 | cmd_id is an 8-bit counter that increments per write or read command and wraps at 0xFF. |
| IA-03 | The timeout watchdog period is application-defined and must be configured to exceed the maximum round-trip ASEP scheduling latency. |
| IA-04 | ASD register writes triggered by Configuration Mode packets use the same local register write path as OAM writes but bypass OAM access-control privilege checking. |
| IA-05 | One I2C ASEP instance is instantiated per DLP instance (i). Multiple I2C tunnels require multiple DLP pairs. |
| IA-06 | The CRC32 algorithm for the bulk/config footer is the same polynomial as Section 4.2.9 (same as used in PCS and other ASEP footers). |
| IA-07 | Byte mode does not require a CRC footer; protection is provided by the ASEP common container integrity. |
| IA-08 | When I2C Address Mode = 1 (current location), the offset address bytes in the bulk write/read header are transmitted but the ASD ignores them when driving the I2C bus. |
| IA-09 | The maximum encodable clock rate is 6.3 MHz (0x3F * 100 kHz); higher rates are not supported by the 6-bit field. |
| IA-10 | The ASD slave address validation (checking if an incoming command targets a valid slave address from 4/5.i.0201-0208) is not mandated by the spec and is implementation-defined. |
| IA-11 | In byte mode, multiple condition bits can be set in the same packet if multiple I2C events occur close together; the serialization granularity is implementation-defined. |
| IA-12 | The Configuration Mode trigger on "after each register write access" is implemented by monitoring write-acks from the register file for address 4/5.i.0200 or 4/5.i.0201-0208. |

---

## 16. Verification Plan

### 16.1 Unit-Level Test Cases

| Test | Mode | Description | Pass Criteria |
|------|------|-------------|---------------|
| BYT-01 | Byte | Start condition only: I2C Start detected, Data=0 | cmd byte = 0b_10E_0_0_0_0_1; no data byte |
| BYT-02 | Byte | Stop after data: Data=1 + Stop=1 simultaneously | cmd byte = 0b_10E_1_0_0_1_0; data byte follows |
| BYT-03 | Byte | Data byte with Ack: Data=1 + Ack=1 | cmd byte has both bits set; payload byte present |
| BYT-04 | Byte | NACK (slave did not ack): Nack=1 | cmd byte has Nack bit set; no data byte |
| BYT-05 | Byte | I2C Error flag: I2C bus hang-up detected | m_HB+2[6] = 1 |
| BYT-06 | Byte | All condition bits clear: yields nothing or empty | No packet generated |
| BLK-01 | Bulk | Write 1 byte: slave=0x50, offset=0x0010, len=1 | Correct header and payload per Table 7-18/7-19 |
| BLK-02 | Bulk | Write 256 bytes: verify length encoding | Length[15:8]=0x01, Length[7:0]=0x00 |
| BLK-03 | Bulk | Read 16 bytes: current location mode | Address Mode bit=1; offset addr ignored |
| BLK-04 | Bulk | ACK/NACK for 1 write byte: all ACK | Payload = ceiling((1+3)/8) = 1 byte; bits = 0 |
| BLK-05 | Bulk | ACK/NACK for 5 write bytes: all NACK | Multiple payload bytes; all bits = 1 |
| BLK-06 | Bulk | ACK/NACK length = 0 bits: reserved | Edge case: verify no assertion failure |
| BLK-07 | Bulk | Read response: 4 reads returned | Payload = 5 bytes (1 AN + 4 rdata) |
| BLK-08 | Bulk | CRC32 footer: verify computation vs. reference | CRC matches independent calculation |
| BLK-09 | Bulk | CRC32 error injection: one byte flipped | Decoder asserts CRC error |
| BLK-10 | Bulk | Timeout watchdog: no response within window | ASE reports NACK to upper layer |
| BLK-11 | Bulk | cmd_id matching: correct response paired with req | Mismatched cmd_id: response discarded |
| CFG-01 | Config | Write: 1 slave address, clock rate = 0x04 | Correct payload per Table 7-27 |
| CFG-02 | Config | Write: 15 slave addresses (maximum) | Payload = 16 bytes total |
| CFG-03 | Config | Write: 0 addresses (reserved) | Should not generate packet; log error |
| CFG-04 | Config | Read: no payload | Packet ends after m_HB+3 (before footer) |
| CFG-05 | Config | ACK/NACK: success flag = 1 | m_HB+4[0] = 1; other bits = 0 |
| CFG-06 | Config | ACK/NACK: failure flag = 0 | m_HB+4[0] = 0 |
| CFG-07 | Config | Read response: mirror of write payload | Payload matches locally read register values |
| CFG-08 | Config | ASD register update: verify reg write | After Config Write received: 4/5.i.0200 and 4/5.i.0201 updated |
| CFG-09 | Config | Startup trigger: config sent once at power-on | First DLP_TX data unit after startup is Config Write |
| CFG-10 | Config | Register write trigger: OAM writes 4/5.i.0200 | Config Write sent within one ASEP slot |

### 16.2 Register Access Tests

| Test | Register | Description | Pass Criteria |
|------|----------|-------------|---------------|
| REG-01 | 4/5.i.0200 | Write clock rate 0x04 (400 kHz) | I2C bus operates at 400 kHz |
| REG-02 | 4/5.i.0200 | Write 0x00: I2C reset | I2C controller enters reset; bus quiescent |
| REG-03 | 4/5.i.0200 | Write 0x01 (100 kHz): minimum valid | I2C operates at 100 kHz |
| REG-04 | 4/5.i.0200 | Write 0x3F (6.3 MHz): maximum | I2C operates at 6.3 MHz |
| REG-05 | 4/5.i.0200 | Read after write: value persists | Read returns written value |
| REG-06 | 4/5.i.0201 | Write two slave addresses + offset flags | Both entries correctly packed in register |
| REG-07 | 4/5.i.0208 | Write entry 14 (lower half), upper=rsvd | Lower half updated; upper half unchanged |
| REG-08 | 4/5.i.0201-0208 | All 15 entries set; verify extraction in Config Write | Config packet payload has all 15 entries |
| REG-09 | 4/5.i.0201 | Unused entry = 0x78 | Config write entry reflects unused marker |
| REG-10 | 4/5.i.0200 | OAM Write privilege check (RID required) | Non-root OAM write rejected; local write allowed |

### 16.3 Integration Tests

| Test | Description | Pass Criteria |
|------|-------------|---------------|
| INT-01 | Full bulk write: ASE TX -> ASA link -> ASD RX -> I2C bus | I2C slave receives correct data bytes |
| INT-02 | Full bulk read: ASE TX read cmd -> ASD RX -> I2C bus -> ASD TX resp -> ASE RX | ASE delivers correct rdata to application |
| INT-03 | Config synchronization: OAM write to 4.i.0200 -> Config Write -> ASD updates register | ASD 4/5.i.0200 matches ASE 4/5.i.0200 |
| INT-04 | I2C NACK propagation: slave NACKs address -> ACK/NACK bulk response -> ASE reports NACK | Host application notified of NACK |
| INT-05 | Byte mode passthrough: Start+Address+Data+Ack+Stop sequence | All 5 events transported as 5 byte mode packets |
| INT-06 | Multi-DLP: two independent I2C tunnels on DLP 0 and DLP 1 | Both tunnels operate independently |
| INT-07 | Link restart: Config Write triggered after link re-establishment | ASD registers re-synchronized after ASA restart |

---

## 17. Missing / Needs Verification

1. **Byte mode and CRC protection**: Byte mode packets do not have an explicit CRC
   footer defined in Section 7.5.1. It is assumed the ASEP common container CRC (if
   any) provides protection. VERIFY: Does the ASEP common framing include its own CRC
   for byte mode, or is byte mode unprotected at the ASEP level?

2. **Bit positions in Table 7-14 (common format)**: Mode[1] is at bit 7 and Mode[0]
   is at bit 5 of m_HB+2, with I2C Error at bit 6. This makes the mode a non-contiguous
   2-bit field. VERIFY that the encoding table (10=Byte, 00=Bulk, 01=Config) uses
   [bit7, bit5] as {Mode[1], Mode[0]} respectively, which is the interpretation from
   Table 7-14 in the PDF.

3. **ACK/NACK Length field: bits vs. bytes**: The bulk ACK/NACK Length field (Tables
   7-21) is stated to be "Length (in bits) of the ack/nack data being returned." This
   differs from write/read commands where Length is in bytes. VERIFY: Does the encoder
   compute the bit count as (number_of_writes + 3 address/slaveaddr_bits) and does the
   decoder correctly compute ceiling((Length+3)/8) payload bytes?

4. **Config Mode No. of I2C addresses = 0**: The spec states "0: reserved" for the
   No. of I2C addresses field (Table 7-26). VERIFY whether a zero value in a received
   packet should be treated as a decode error, silently ignored, or triggers specific
   error handling.

5. **Config Mode trigger timing**: The spec requires a Configuration Mode write "once
   after startup." It is not specified whether this must complete before the first bulk
   or byte mode packet is sent, or whether it can be concurrent. VERIFY the sequencing
   requirement.

6. **ASD driving I2C bus**: The spec confirms the ASD has DLP_TX and DLP_RX but does
   not explicitly state that the ASD acts as an I2C Master toward local slave ICs. This
   is architecturally implied by the topology diagrams (Appendix C) showing ICs
   connected to the ASD node. VERIFY: Is the ASD always the I2C bus master toward its
   local slave ICs, or can it also operate as an I2C slave?

7. **Byte mode without data byte**: If the I2C Data bit (m_HB+2[4]) is 0, there is no
   payload byte at m_HB+3. In this case the packet consists of only m_HB+1 (cmd_id)
   and m_HB+2 (event bits). VERIFY the minimum packet size that the ASEP common framing
   accepts and whether padding is needed.

8. **cmd_id assignment rule**: The spec states "a new (not currently in use) command
   ID" for each write and read. The parenthetical "(not currently in use)" implies a
   cmd_id must not be reused while a response is still pending. VERIFY: Is this
   enforced at the sender (cmd_id must wait for ACK before reuse), or is it only a
   recommendation?

9. **Offset address length flag in config payload**: The offset address length flag in
   the Config Write payload (m_HB+5+n bit 7) mirrors register 4/5.i.0201-0208 bit 7
   (or bit 15 for the upper entry). VERIFY the exact byte ordering: is entry 0
   (register 4.i.0201[7:0]) placed at m_HB+5, entry 1 at m_HB+6, etc.?

10. **Timeout watchdog accessible register**: The spec says "the root node should
    implement a timeout watchdog." No register is defined for configuring the watchdog
    period. VERIFY whether 5.i.0101 (ASD Watchdog) or another register is intended
    for this purpose, or whether it is purely an implementation concern.

11. **10-bit I2C addressing**: The spec note in Table 3-89 states "This is not in
    conflict with I2C bus specification as 10-bit addressing is not supported by this
    ASEP." VERIFY: Is 10-bit I2C addressing entirely excluded from the ASEP tunneling
    protocol, and should the implementation simply not attempt 10-bit address sequences
    on the I2C bus?

12. **img-xxx files for Appendix C (pages 338-340)**: The image filenames for the
    I2C topology diagrams from Appendix C (Figures III-1 through III-5) were not
    found in docpdfmd/images/ under the named-figure convention used for other images.
    The img-xxx.png files (img-223.png through img-273.png) in docpdfmd/images/ likely
    correspond to these pages but their content has not been verified. VERIFY: Do
    the img-xxx files at the high page numbers contain the I2C topology figures, and
    if so, identify which img file maps to which topology scenario.

---

## 18. Summary

The ASEP I2C module provides a complete bidirectional I2C tunneling service across the
ASA SerDes link. The key architectural facts are:

1. Three modes: Byte (per-event transparency), Bulk (efficient transaction grouping),
   and Configuration (register synchronization) - each with a distinct packet format.

2. A 2-byte common header (cmd_id + mode/error/format byte) precedes all
   I2C-specific content starting at offset m_HB+1.

3. Bulk and Configuration mode packets are protected by a 4-byte CRC32 footer;
   byte mode relies on the ASEP common container integrity.

4. The Configuration Mode implements an out-of-band I2C parameter synchronization
   protocol: the ASE sends clock rate and slave address registers to the ASD once at
   startup and on every OAM register write to those registers.

5. Two registers fully define the local I2C bus: 4/5.i.0200 (clock rate, 6-bit, resets
   on 0x00) and 4/5.i.0201-0208 (15 slave address entries with 8/16-bit offset flags).

6. The cmd_id field provides request-response correlation across the half-duplex ASA
   link; the root node implements a timeout watchdog to handle NACK on non-response.
