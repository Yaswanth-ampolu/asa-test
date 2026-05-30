# Micro-Architecture: ASEP Common Framing

## 1. Purpose and Scope

The ASEP Common Framing layer defines the universal packet structure that every
Application Stream Encapsulation Protocol (ASEP) stream type must follow when
communicating over ASA Data Link Layer ports. It is the shared foundation on which
Video, I2C, SPI, GPIO, (e)DP, I2S, and Test ASEP all build their stream-specific
headers and payloads.

This document defines the micro-architecture of the ASEP Common Framing entity for
RTL or golden-model implementation, derived directly from ASA Technical Specification
v2.0, Sections 7.3, 7.3.1, 7.3.2, 7.3.2.1, 7.3.3 (pages 231-236).

Scope boundaries:
- IN SCOPE: ASEP packet structure overview (Section 7.3), DLL container byte0/byte1
  fragmentation encoding (Section 7.3.1), common ASEP header byte 0 stream-type and
  follow-flag (Section 7.3.2), common ASEP header byte 1 PTB time-stamp mode and
  bytes 2-5 ingress/presentation timestamps (Section 7.3.2.1), ASEP footer CRC
  framework (Section 7.3.3), Full Packet ID registers (4/5.i.0001-0003), Stream Type
  register (4/5.i.0004), control-interface pin capability registers (4/5.i.0051-0062),
  TX flow (DLP_TX.indicateSlot -> ASEP header assembly -> PTB snapshot ->
  DLP_TX.dataUnit), RX flow (DLP_RX.dataUnit -> fragment strip -> reassembly)
- OUT OF SCOPE: Stream-specific header fields (Sections 7.4-7.11, separate docs),
  DLL Mapper/Demux scheduling (micro-architecture-dll-mapper-demux-core.md),
  PTB clock synchronisation algorithm (micro-architecture-ptb-clock-service.md),
  Security AES-GCM (micro-architecture-link-layer-security.md), register file
  implementation (micro-architecture-register-model.md)

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 7.1 | Application Stream Encapsulator | 231 | ASE/ASD role, DLP_TX/RX binding |
| 7.2 | Application Stream Decapsulator | 231 | ASD reassembly, error recording |
| 7.3 | Common ASEP Format Basics | 231-233 | Overview, stream type table |
| 7.3.1 | Common ASEP Format Basics per DLL Container | 233-235 | Table 7-2 Byte0, Table 7-3 Byte1 |
| 7.3.2 | Common ASEP Format Basics per Header | 235 | Table 7-4 first byte |
| 7.3.2.1 | ASEP PTB Time Stamps | 235-236 | Tables 7-5, 7-6, 7-7 |
| 7.3.3 | Common ASEP Format Basics per Footer | 236 | CRC framework |
| 3.5.1 | General ASEP Registers | 67 | Table 3-74 register overview |
| 3.5.1.1 | Full Packet ID (4/5.i.0001-0003) | 67-68 | 48-bit packet counter |
| 3.5.1.2 | ASEP Stream Type (4/5.i.0004) | 68 | Table 3-75, 7-bit type code |
| 3.5.1.3 | ASEP Stream VendorID (4/5.i.0005) | 68 | Vendor identifier |
| 3.5.1.4 | ASEP Test (4/5.i.0006) | 68-69 | Test enable (L only) |
| 3.5.1.5.1 | Quad-Pin Capability (4/5.i.0051) | 69-70 | Table 3-78 |
| 3.5.1.5.2 | Trio-Pin Capability (4/5.i.0052) | 70-71 | Table 3-79 |
| 3.5.1.5.3 | Duo-Pin Capability (4/5.i.0053-0054) | 71-73 | Tables 3-80, 3-81 |
| 3.5.1.5.4 | Single-Pin Capability (4/5.i.0055-0058) | 73-76 | Tables 3-82 to 3-85 |
| 3.5.1.6 | Pin Config (4/5.i.0059-0062) | 76-78 | Tables 3-86, 3-87 |
| 5.6.1.1.1 | DLP_TX.indicateSlot | 185 | Trigger from DLL to ASE |
| 5.6.1.2.1 | DLP_TX.dataUnit | 185 | ASE payload response to DLL |
| 5.6.1.4.1 | DLP_TX.yield | 186 | ASE no-data response |
| 5.7.1.1.1 | DLP_RX.dataUnit | 187 | DLL delivers container to ASD |

Image references (docpdfmd/images/):
- `73_Figure_7-1_Common_ASEP_packet_format.png` -- Figure 7-1 (PDF p232) common packet diagram
- `74_Figure_7-2_Common_ASEP_DLL_Payload.png` -- Figure 7-2 (PDF p233) container layout
- `75_Figure_7-3_ASEP_mapping_DLL_Payloads.png` -- Figure 7-3 (PDF p234) fragmentation

---

## 3. ASEP System Overview

### 3.1 Role of ASE and ASD (Section 7.1, 7.2, p231)

SPEC FACT: "The Application Stream Encapsulator (ASE) acts as a transmitter on a
DLP_TX whereas the Application Stream Decapsulator (ASD) acts as a receiver on a
DLP_RX. Each ASE and ASD on a specific Data Link Layer Port supports only a single
ASEP (see 3.5.1.2)."

SPEC FACT: "The ASE converts application stream data units into an ASEP format,
where it has to handle header, payload and footer generation as well as
fragmentation into Data Link Layer Containers."

SPEC FACT: "The ASD converts an ASEP format into application data units. It has to
execute the reassembly of fragmented ASEP frames as well as handle errors.
Reassembly errors resulting in verifiably corrupt application data units have to be
recorded in 3.7.1."

SPEC FACT: "For a specific timeout dependent on the stream type and application, the
ASE shall indicate a 'data starve event', when expected application data units are
not being received, in the register 3.6.2."

### 3.2 ASEP Position in the Protocol Stack

```
+-------------------------------------+
|  Application (camera, display, I2C, |
|  SPI, GPIO, I2S, audio, ethernet)   |
+-------------------------------------+
                 |
     +-----------+-----------+
     |  ASE (TX side)         |          |  ASD (RX side)       |
     |  Common Framing        |          |  Common Framing      |
     |  - fragmentation byte  |          |  - reassembly FSM    |
     |  - stream type byte    |          |  - CRC check         |
     |  - follow flag         |          |  - stream dispatch   |
     |  - PTB timestamp       |          |                      |
     |  - stream-specific hdr |          |  stream-specific hdr |
     |  - payload packing     |          |  payload parsing     |
     +-----------+-----------+          +----------+-----------+
                 |                                  |
     +-----------v-----------+          +-----------v-----------+
     |  DLP_TX interface     |          |  DLP_RX interface     |
     |  DLP_TX.indicateSlot  |          |  DLP_RX.dataUnit      |
     |  DLP_TX.dataUnit      |          |                       |
     |  DLP_TX.yield         |          |                       |
     +-----------+-----------+          +-----------+-----------+
                 |                                  |
     +-----------v----------------------------------v-----------+
     |              DLL Mapper/Demux Core                       |
     |   (micro-architecture-dll-mapper-demux-core.md)          |
     +----------------------------------------------------------+
```

### 3.3 ASEP Stream Type Codes (Table 7-1, p233)

SPEC FACT: "Each ASEP header contains in the first byte a <ASEP stream type> value,
which is a unique identifier for each format. The ASEP stream type codes are also
used to identify DLP_TX/DLP_RX purpose (see 3.5.1.2)."

```
Code   Stream Type                Subsection
----   -----------                ----------
0x01   Video Data                 7.4
0x02   I2C                        7.5
0x03   Layer 2 Ethernet Frames    7.6
0x04   SPI                        7.7
0x05   GPIO                       7.8
0x06   (e)DP                      7.9
0x07   I2S                        7.10
0x37   Test ASEP                  7.11
0x7E   Forward Data               Not used in ASEP header; identifies DLP_TX/RX purpose
0x7F   Return OAM                 Not used in ASEP header; identifies DLP_TX/RX purpose
```

SPEC FACT (Section 7.3, p233): 0x7E (Forward Data) and 0x7F (Return OAM) are NOT
used in ASEP packet headers. They appear only in register 4/5.i.0004 to identify
the DLP_TX/DLP_RX purpose for forwarding fabric and OAM return path ports.

---

## 4. Common ASEP Packet Format (Section 7.3, Figure 7-1, p232)

SPEC FACT (Section 7.3, p231-232): "There is common format per DLL payload, which
unifies the handling of fragmentation. There is common format per ASEP packet, which
unifies the stream identification and time stamping."

The overall structure of an ASEP packet, as derived from Figure 7-1 (p232):

```
+--------------------------------------------------------------------------+
|                         ASEP Packet                                       |
|                                                                          |
| +-------------------+-----------------+-----------+                      |
| |   ASEP Header     |  ASEP Payload   | ASEP      |                      |
| |                   |                 | Footer    |                      |
| | +---+---+---------+-...-+  ...      |  (opt.)   |                      |
| | |B0 |B1 |stream-specific|  payload  |  CRC?     |                      |
| | |   |   |header bytes   |           |           |                      |
| | +---+---+---------+-...-+           |           |                      |
| +-------------------+-----------------+-----------+                      |
|   mHB=1 (no TS)                                                          |
|   mHB=5 (with ingress/presentation TS)                                   |
|                                                                          |
| mHB = maximum byte index of common ASEP header                           |
| mEND = last byte of ASEP packet (footer boundary)                        |
+--------------------------------------------------------------------------+
```

When an ASEP packet is fragmented across multiple DLL containers, each container
carries a DLL payload with:
- Byte 0: fragmentation and boundary position encoding (Section 7.3.1)
- Optional Byte 1: lower boundary position bits (Section 7.3.1)
- Remaining bytes: ASEP packet(s) or fragment(s)

---

## 5. DLL Container Format (Section 7.3.1, Tables 7-2/7-3, p233-234)

### 5.1 Container Byte0 -- Fragmentation Encoding (Table 7-2, p234)

SPEC FACT: "Byte0 of each Data Link Layer Payload provided by an ASEP has the
following format:"

```
Byte0
Bit(s)  Name                        Description
------  ----                        -----------
7:6     ASEP packet fragmentation   00: this container does not include a packet
                                        boundary
                                    10: this container includes a packet end followed
                                        by padding from the boundary position onward
                                        (the boundary position may at maximum also be
                                        the first byte after the container payload,
                                        distinguishing the payload size from the size
                                        of code '01' below)
                                    11: this container includes a packet end followed
                                        by a new ASEP packet header at the indicated
                                        position; if the indicated position is 0x02,
                                        this container is starting a new packet
                                    01: the ASEP packet ends on the last byte of this
                                        container
5:0     ASEP packet boundary        Gives the upper 6 bits <9:4> index position of
        position                    the first byte after the end of the terminating
                                    ASEP packet in the Container payload; this byte
                                    containing the ASEP packet boundary position
                                    itself is index 0
```

SPEC FACT (Table 7-2, p234): Bit 7 of the fragmentation field (fragmentation[1]) is
the MSB of the fragmentation code. When fragmentation[1]=1 (codes 10 or 11), a
second container byte (Byte1) is present carrying the lower 4 bits of the boundary
position.

### 5.2 Container Byte1 -- Lower Boundary Position (Table 7-3, p234)

SPEC FACT: "If the ASEP packet fragmentation MSB is set to 1, a Byte1 is present in
the Container:"

```
Byte1 (present only when fragmentation[7]=1, i.e., codes 10 or 11)
Bit(s)  Name                        Description
------  ----                        -----------
7:4     ASEP packet boundary        Gives the lower 4 bits <3:0> of the ASEP packet
        position                    boundary position (see first byte)
3:0     (reserved)
```

### 5.3 Boundary Position -- Full 10-bit Encoding

SPEC FACT (Tables 7-2, 7-3, p234): The complete ASEP packet boundary position is a
10-bit unsigned integer assembled from two partial fields:

```
boundary_position[9:4] = Byte0[5:0]   (upper 6 bits)
boundary_position[3:0] = Byte1[7:4]   (lower 4 bits, when Byte1 present)

boundary_position[9:0] is the index (in the container payload) of the first byte
after the end of the terminating ASEP packet; index 0 is Byte0 itself.
```

IMPLEMENTATION ASSUMPTION: When fragmentation code is 00 (no packet boundary) or 01
(packet ends on last container byte), the boundary_position field in Byte0[5:0] is
still present in the wire format but its value is not architecturally significant
for boundary location. RTL should not interpret the field in these cases.

### 5.4 Fragmentation Code Summary Table

```
Code  fragmentation[1]  Byte1?  Meaning
----  ----------------  ------  -------
00    0                 No      Container does not include a packet boundary;
                                entire container is mid-packet data
01    0                 No      ASEP packet ends on last byte of container;
                                no padding; next packet starts in next container
10    1                 Yes     Packet end + padding from boundary position onward;
                                boundary_position[9:0] locates first padding byte
11    1                 Yes     Packet end + new ASEP header starts at boundary
                                position; if boundary_position=0x002 (index 2,
                                immediately after Byte0 and Byte1), this container
                                is starting a new packet with no preceding fragment
```

### 5.5 Fragmentation Figure (from Figure 7-3, p234)

```
DLL Payload #1              DLL Payload #2              DLL Payload #3
+------+---+--------+       +------+---+--------+       +------+---+------+------+
|fragm=|bdry| ASEP  |       |fragm=|bdry|ASEP Pkt|       |fragm=|bdry|ASEP  |padd|
| 11   |pos | Pkt#k |       | 00  |pos |Fragment |       | 10   |pos |Pkt#k+1     |
|      |    |+ frag |       |    |    |         |       |      |    |Fragment|ing |
+------+---+--------+       +------+---+--------+       +------+---+------+------+
  fragmentation[1]=1          fragmentation[1]=0          fragmentation[1]=1
  (Byte1 present)             (Byte1 absent)              (Byte1 present)

Figure 7-3: ASEP packet mapping to DLL Payloads (adapted from spec p234)
```

SPEC FACT (p234): "Table 7-2 contains the complete description and is binding in
case of any inconsistency" with Figure 7-3.

---

## 6. Common ASEP Header First Byte (Section 7.3.2, Table 7-4, p235)

SPEC FACT: "All ASEP headers start with the following fields:"

### 6.1 Header Byte 0 Layout (Table 7-4)

```
Byte  Bit(s)  Name                        Description
----  ------  ----                        -----------
0     7:1     ASEP stream type            7-bit stream type code; see Table 7-1
                                          (0x01=Video, 0x02=I2C, 0x03=Ethernet,
                                           0x04=SPI, 0x05=GPIO, 0x06=(e)DP, 0x07=I2S,
                                           0x37=Test ASEP)
0     0       Same container ASEP         0: there is no further ASEP header in the
              header follow flag          same container; if the length of the ASEP
                                          packet is shorter than the container, it is
                                          filled with dummy data
                                          1: there is another ASEP header in the same
                                          container directly after the last byte of the
                                          current packet
```

SPEC FACT: The follow flag (bit 0) set to 1 means a second ASEP packet is packed
back-to-back in the same DLL container, starting immediately after the last byte of
the current packet. This supports dense packing of multiple short ASEP packets
(e.g., GPIO samples) within a single DLL container.

SPEC FACT: The follow flag (bit 0) set to 0 means this packet is the only (or last)
ASEP packet in the container; any remaining bytes in the container payload after the
packet end are dummy/padding bytes.

### 6.2 Stream Type in Header vs Register

```
                    Wire (ASEP Header Byte 0)    Register 4/5.i.0004
                    --------------------------   -------------------
Field width:        7 bits (bits 7:1)            7 bits (bits 6:0)
Value encoding:     identical to Table 7-1 code  identical to Table 7-1 code
Bit position:       Byte0[7:1] (left-shifted 1)  Reg[6:0]
```

IMPLEMENTATION ASSUMPTION: The stream type is placed in bits 7:1 of header byte 0,
not bits 6:0. The value matches the Table 7-1 code directly; the follow flag occupies
bit 0. RTL must shift the 7-bit stream type value left by 1 when writing the first
header byte.

---

## 7. Common ASEP Header Second Byte -- PTB Timestamp Mode (Section 7.3.2.1, Table 7-5, p235)

SPEC FACT: "The second byte contains a switch into ASEP PTB usage:"

### 7.1 Header Byte 1 Layout (Table 7-5)

```
Byte  Bit(s)  Name              Description
----  ------  ----              -----------
1     7:2     (reserved)
1     1:0     PTB time stamp    00: none -- no timestamp present
                                01: ingress time stamp
                                10: presentation time stamp
                                11: user defined (time stamp size 4 bytes)
```

SPEC FACT (p235): "In case of no time stamping, the maximum byte index mHB of the
common ASEP header format is 1." That is, without any timestamp the common header
occupies exactly 2 bytes (Byte0 and Byte1).

SPEC FACT (p235): "In case of ingress or presentation time stamping, mHB is 5."
That is, with either ingress or presentation timestamp the common header occupies
bytes 0 through 5 (6 bytes total).

### 7.2 Common Header Size Summary

```
PTB time stamp field  mHB   Common header bytes   Bytes 2-5 content
--------------------  ---   -------------------   -----------------
00 (none)             1     2 bytes (B0, B1)       absent
01 (ingress)          5     6 bytes (B0..B5)       PTBingress[31:0]
10 (presentation)     5     6 bytes (B0..B5)       PTBpresent[31:0]
11 (user defined)     5     6 bytes (B0..B5)       user-defined 32-bit
```

---

## 8. Ingress Timestamp (Section 7.3.2.1, Table 7-6, p235)

SPEC FACT: "The ingress time stamp is defined in Table 7-6."

### 8.1 Ingress Timestamp Field (Table 7-6)

```
Byte  Bit(s)  Name              Description
----  ------  ----              -----------
2     7:0     PTBingress[31:24] Lower 32 bits of the PTBclk of the ASA node
3     7:0     PTBingress[23:16] containing the ASE, taken when the first payload
4     7:0     PTBingress[15:8]  symbol of this ASEP packet passed the
5     7:0     PTBingress[7:0]   application interface
```

SPEC FACT (Table 7-6, p235): The ingress timestamp is the lower 32 bits
(PTBclk[31:0]) of the 48-bit PTBclk register (2.2200-2.2202) of the ASA node that
contains the ASE. It is captured at the moment the first payload symbol of this
ASEP packet crosses the application interface.

SPEC FACT: The upper 16 bits of the 48-bit PTBclk are NOT included in the timestamp.
Only PTBclk[31:0] is present (4 bytes, big-endian).

### 8.2 Ingress Timestamp Capture Diagram

```
Application Interface
(app data arrives)
         |
         | first payload symbol of ASEP packet
         v
+-------------------+
| PTBclk capture    |  <- snapshot PTBclk[31:0] from register 2.2200-2.2201
| (lower 32 bits)   |
+-------------------+
         |
         | PTBingress[31:0]
         v
+-------------------+
| ASEP Header Gen   |
| Byte 2 = [31:24]  |
| Byte 3 = [23:16]  |
| Byte 4 = [15:8]   |
| Byte 5 = [7:0]    |
+-------------------+
```

---

## 9. Presentation Timestamp (Section 7.3.2.1, Table 7-7, p236)

SPEC FACT: "The presentation time stamp is defined in Table 7-7."

### 9.1 Presentation Timestamp Field (Table 7-7)

```
Byte  Bit(s)  Name               Description
----  ------  ----               -----------
2     7:0     PTBpresent[31:24]  Lower 32 bits of the PTBclk when the first payload
3     7:0     PTBpresent[23:16]  symbol of this ASEP packet is to be presented at
4     7:0     PTBpresent[15:8]   the application interface of the ASA node
5     7:0     PTBpresent[7:0]    containing the ASD
```

SPEC FACT (Table 7-7, p236): The presentation timestamp is the lower 32 bits
(PTBclk[31:0]) of the PTBclk at which the first payload symbol should be presented
(rendered/output) at the application interface of the receiving ASD node.

SPEC FACT: Both ingress and presentation timestamps occupy bytes 2-5 in identical
big-endian 32-bit format; the distinction is only in their semantic meaning
(captured vs. target time) and in the Table 7-5 mode select field (01 vs. 10).

IMPLEMENTATION ASSUMPTION: The presentation timestamp is computed by the
transmitting ASE by adding the desired transport delay to the ingress timestamp or
by reference to a stream-specific deadline schedule. The spec does not define the
formula; it is stream-type specific (see Section 7.4-7.11).

---

## 10. ASEP Footer (Section 7.3.3, p236)

SPEC FACT: "An ASEP format may or may not employ a CRC checksum over one ASEP
packet, which gets sent and may get fragmented into several Data Link Layer
Containers. A CRC checksum might also be separately generated for ASEP header and
ASEP payload."

SPEC FACT: "If the ASEP format does employ a CRC check, the ASD shall check the
consistency of the data after reassembly of the received fragments and shall
indicate an error by incrementing 3.7.1."

SPEC FACT: Section 7.3.3 defines NO specific footer format applicable to all ASEP
types. Whether a footer (e.g., CRC32) is present, its size, and its position are
entirely determined by the stream-type-specific section (7.4-7.11).

IMPLEMENTATION ASSUMPTION: The common framing layer does not know in advance whether
a footer is present or its size. The ASD must use the stream-type-specific header
to determine packet length and footer presence before locating the footer boundary.

For the Video Data ASEP (Section 7.4), a 4-byte CRC32 over the header is present.
Other stream types may have no footer, a header-only CRC, or a whole-packet CRC.

---

## 11. Register Definitions

### 11.1 Common ASEP Registers Overview (Section 3.5.1, Table 3-74, p67)

```
Address         Name                        Section   R/W  Access  Priv
4/5.i.0001-3   fullPacketID[47:0]          3.5.1.1   RO   O       RID
4/5.i.0004      ASEP Stream Type            3.5.1.2   RO   O       RID
4/5.i.0005      ASEP Stream VendorID        3.5.1.3   RO   O       RID
4/5.i.0006      ASEP Test                   3.5.1.4   RW   L       RID
4/5.i.0007-50   reserved
4/5.i.0051      Quad-Pin Capability         3.5.1.5.1 RO   O       RID
4/5.i.0052      Trio-Pin Capability         3.5.1.5.2 RO   O       RID
4/5.i.0053-54   Duo-Pin Capability          3.5.1.5.3 RO   O       RID
4/5.i.0055-58   Single-Pin Capability       3.5.1.5.4 RO   O       RID
4/5.i.0059-62   Pin Config                  3.5.1.6   RW   O       RID
4/5.i.0063-99   reserved
```

SPEC FACT (Section 3.5.1, p67): "Registers in the address range 4/5.i.0001-0099 are
defined for all ASEPs. Registers in the address range 4/5.i.0051-0099 are for each
address the same register for all subdomains."

### 11.2 Full Packet ID (4/5.i.0001-0003, Section 3.5.1.1, p67-68)

SPEC FACT (Section 3.5.1.1, p67): "Each fullPacketID[47:0] is associated with each
DLP_TX_ID and each DLP_RX_ID port and therefore in the ASEP address space, but
managed by the DLL."

```
Register      Bits    Field
4/5.i.0001    15:0    fullPacketID[15:0]    RO O RID
4/5.i.0002    15:0    fullPacketID[31:16]   RO O RID
4/5.i.0003    15:0    fullPacketID[47:32]   RO O RID

Total: 48-bit unsigned counter per DLP port.
Reset value: 0.
```

SPEC FACT (Section 3.5.1.1, p67-68): "It is incremented for each container sent for
this DLP_TX, whereas the lower 5 bits fullPacketID[4:0] are copied into the container
header. See 5.2.2.4."

SPEC FACT (Section 3.5.1.1, p68): "At the receiver side (sinking DLP_RX), the
fullPacketID[47:0] is incremented for every correctly received container. See 5.3.2.1."

SPEC FACT (Section 3.5.1.1, p68): "For the special case of the FoFa, where ASEP
Stream Type is 'Return OAM' or 'Forward Data', the register has no function. See 5.4."

Note: Only the lower 5 bits (fullPacketID[4:0]) appear in the DLL container header
as the packetID field. The remaining 43 upper bits are maintained for error counting
across many containers but are not transmitted.

### 11.3 ASEP Stream Type (4/5.i.0004, Section 3.5.1.2, p68)

SPEC FACT (Table 3-75, p68):

```
Register 4/5.i.0004
Bit(s)  Name        Description                             R/W  Access  Priv
15:7    reserved
6:0     streamType  ASEP stream type as listed in Table 7-1 RO   O       RID
```

SPEC FACT: streamType is read-only and reflects the hardware-implemented stream type.
The value is used during enumeration Self-Announce (Section 5.5.4.2.1) when the
newly discovered node returns ASEP Stream Type for all supported/enabled DLPs.

### 11.4 ASEP Stream VendorID (4/5.i.0005, Section 3.5.1.3, p68)

```
Register 4/5.i.0005
Bit(s)  Name           Description                                    R/W  Access  Priv
15:0    streamVendorID Vendor-defined field to further identify a      RO   O       RID
                       stream, especially among identical stream types
```

### 11.5 ASEP Test (4/5.i.0006, Section 3.5.1.4, p68-69)

```
Register 4/5.i.0006
Bit(s)  Name            Description                                R/W  Access  Priv
15:1    reserved
0       ASEP Test enable 1: test mode on; 0: test mode off         RW   L       RID
                         ASEP Test mode on ASE is further
                         subdivided (see section 3.6.3)
                         On ASD: enables TestDummy mode (7.11)
Access: L only -- NOT OAM-accessible.
```

### 11.6 Pin Capability Registers (4/5.i.0051-0058, Sections 3.5.1.5.1-3.5.1.5.4, p69-76)

These registers describe the ASEP control interface capability for up to 16 logical
pin IDs [15:0]. All are RO O RID.

SPEC FACT (Section 3.5.1.5, p69): "This register describes the support of control
interfaces on up to 16 pin IDs [15:0] on an ASA device. This is a logical mapping;
physical pin information is beyond the scope of this specification."

#### 4/5.i.0051 -- Quad-Pin Capability (Table 3-78, Section 3.5.1.5.1)

Describes SPI and vendor-interface capability for 4 groups of 4 pins each:

```
Bits  Name                        Description
----  ----                        -----------
15:14 reserved
13    Pin-Quad [15:12] SPI cap    1: SPI capable
12    Pin-Quad [15:12] vendor cap 1: vendor interface capable
11:10 reserved
9     Pin-Quad [11:8] SPI cap     1: SPI capable
8     Pin-Quad [11:8] vendor cap  1: vendor interface capable
7:6   reserved
5     Pin-Quad [7:4] SPI cap      1: SPI capable
4     Pin-Quad [7:4] vendor cap   1: vendor interface capable
3:2   reserved
1     Pin-Quad [3:0] SPI cap      1: SPI capable
0     Pin-Quad [3:0] vendor cap   1: vendor interface capable
```

#### 4/5.i.0052 -- Trio-Pin Capability (Table 3-79, Section 3.5.1.5.2)

Describes I2S and vendor-interface capability for 4 groups of 3 pins each
(covering pin IDs [15:1]):

```
Bits  Name                         Description
----  ----                         -----------
15:14 reserved
13    Pin-Trio [15:13] I2S cap     1: I2S capable
12    Pin-Trio [15:13] vendor cap  1: vendor interface capable
11:10 reserved
9     Pin-Trio [11:9] I2S cap      1: I2S capable
8     Pin-Trio [11:9] vendor cap   1: vendor interface capable
7:6   reserved
5     Pin-Trio [7:5] I2S cap       1: I2S capable
4     Pin-Trio [7:5] vendor cap    1: vendor interface capable
3:2   reserved
1     Pin-Trio [3:1] I2S cap       1: I2S capable
0     Pin-Trio [3:1] vendor cap    1: vendor interface capable
```

#### 4/5.i.0053-0054 -- Duo-Pin Capability (Tables 3-80, 3-81, Section 3.5.1.5.3)

Describes I2C and vendor-interface capability for 8 groups of 2 pins each
(covering pin IDs [15:0]):

```
Register 4/5.i.0053 covers pin pairs [7:0]:
  Bits 13,12: Pin-Duo [7:6] I2C cap / vendor cap
  Bits 9,8:   Pin-Duo [5:4] I2C cap / vendor cap
  Bits 5,4:   Pin-Duo [3:2] I2C cap / vendor cap
  Bits 1,0:   Pin-Duo [1:0] I2C cap / vendor cap

Register 4/5.i.0054 covers pin pairs [15:8]:
  Bits 13,12: Pin-Duo [15:14] I2C cap / vendor cap
  Bits 9,8:   Pin-Duo [13:12] I2C cap / vendor cap
  Bits 5,4:   Pin-Duo [11:10] I2C cap / vendor cap
  Bits 1,0:   Pin-Duo [9:8]  I2C cap / vendor cap
```

#### 4/5.i.0055-0058 -- Single-Pin Capability (Tables 3-82 to 3-85, Section 3.5.1.5.4)

Describes GPIO and vendor-interface capability for all 16 individual pins.
Each register covers 4 pin IDs:

```
Register 4/5.i.0055: Pin IDs [3:0]   (Table 3-82)
Register 4/5.i.0056: Pin IDs [7:4]   (Table 3-83)
Register 4/5.i.0057: Pin IDs [11:8]  (Table 3-84)
Register 4/5.i.0058: Pin IDs [15:12] (Table 3-85)

Per pin pair within each register:
  Bit n+1: GPIO capable  1: GPIO capable; 0: not capable
  Bit n:   vendor capable 1: vendor interface capable; 0: not capable
```

### 11.7 Pin Config (4/5.i.0059-0062, Section 3.5.1.6, Table 3-86/3-87, p76-78)

Four registers, one per group of 4 pins:

```
Register mapping (Table 3-87):
  4/5.i.0059: pin range 3:0
  4/5.i.0060: pin range 7:4
  4/5.i.0061: pin range 11:8
  4/5.i.0062: pin range 15:12

Per register bit layout (Table 3-86):

Bits  Name           Description                                R/W  Access  Priv
15:8  Pin active     1xxx_xxxx: quad interface active            RW   O       RID
      select         01xx_xxx0: trio interface active
                     01xx_xxx1: trio + single (lowest) active
                     0010_xx00: upper duo active
                     0010_xx01: upper duo + lowest single
                     0010_xx10: upper duo + 2nd lowest single
                     0010_xx11: upper duo + both low singles
                     0001_00xx: lower duo active
                     0001_01xx: lower duo + 2nd highest single
                     0001_10xx: lower duo + highest single
                     0001_11xx: lower duo + both high singles
                     0000_abcd: per-bit (a=highest, d=lowest single)
7:6   Interface      For highest single, upper duo, trio, quad:
      select n+3     0: vendor specific; 1: GPIO/I2C/I2S/SPI
5:4   Interface      For second highest single:
      select n+2     0: vendor specific; 1: GPIO
3:2   Interface      For second lowest single & lower duo:
      select n+1     0: vendor specific; 1: GPIO / I2C
1:0   Interface      For lowest single:
      select n       0: vendor specific; 1: GPIO
```

---

## 12. TX Data Flow (ASE side)

### 12.1 TX Primitive Sequence

SPEC FACT (Section 5.6.1.1.1, p185): DLP_TX.indicateSlot(size) is generated by the
DLL after each Mapper evaluation, requesting a data unit of the specified size.

SPEC FACT (Section 5.6.1.1.3, p185): "ASE replies with 5.6.1.2 [dataUnit] or
5.6.1.4 [yield]. OAM always replies with 5.6.1.3 [oamUnit]."

SPEC FACT (Section 5.6.1.2.1, p185): "DLP_TX.dataUnit(ase_payload) -- The ASE uses
DLP_TX.dataUnit to provide the payload of a container to the DLL. The size shall be
the size, which has been requested."

SPEC FACT (Section 5.6.1.4.1, p186): "DLP_TX.yield() -- The ASE or FoFa uses
DLP_TX.yield to signal, that it has no data to send and forfeits the transmit
opportunity."

SPEC FACT (Section 5.6.1.4.3, p186): When yield is received from an ASE, "No
container is constructed for this ASE. Instead, OAM is polled with 5.6.1.1."

### 12.2 TX Flow Diagram

```
DLL Mapper evaluation -> DLP_TX_ID_select = i
          |
          v
DLP_TX.indicateSlot(size)  [DLL -> ASE_i, size = Dn/Up_P2P/MC/_Sec]
          |
          |
+---------+---------+
|                   |
| application data  | no data
| available         | available
|                   |
v                   v
ASE assembles       DLP_TX.yield()
container           [ASE -> DLL]
payload:            |
                    v
+------------------+ DLL polls OAM
| 1. Build Byte0   | with indicateSlot
|    frag + bndry  |
+------------------+
| 2. Build Byte1   |
|    (if frag[1]=1)|
+------------------+
| 3. Build ASEP    |
|    Header:       |
|    B0: type|follow|
|    B1: PTB mode  |
|    B2-5: if TS   |
|    + stream hdr  |
+------------------+
| 4. PTB snapshot  |  <- capture PTBclk[31:0] if timestamp mode != 00
|    (if ingress   |     at moment first payload symbol crosses appl intf
|     TS enabled)  |
+------------------+
| 5. Pack payload  |
|    bytes         |
+------------------+
| 6. Stream-spec   |
|    footer (CRC?) |
+------------------+
          |
          v
DLP_TX.dataUnit(ase_payload)  [ASE -> DLL]
          |
          v
DLL constructs container header (nodeID, streamID, targetID,
  packetID = fullPacketID[i][4:0] after increment), puts to PLP_TX
```

### 12.3 Container Size Values (Section 5.6.1.1.1, p185)

SPEC FACT:

```
Size name    Bytes  Use
Dn_P2P       638    Downstream point-to-point, unsecured
Dn_P2P_Sec   620    Downstream point-to-point, secured
Dn_MC        636    Downstream multicast, unsecured
Dn_MC_Sec    618    Downstream multicast, secured
Up_P2P       208    Upstream point-to-point, unsecured
Up_P2P_Sec   190    Upstream point-to-point, secured
Up_MC        206    Upstream multicast, unsecured
Up_MC_Sec    188    Upstream multicast, secured
OAM_frame    188    OAM only (not used for ASEP)
```

IMPLEMENTATION ASSUMPTION: The ASEP common framing layer receives the size value
from DLP_TX.indicateSlot and must produce a byte array of exactly that size. Any
unused bytes after the last ASEP payload byte (and after any footer) are filled with
padding (dummy bytes); the fragmentation code 10 with boundary_position locates the
end of meaningful data.

### 12.4 Multi-Packet Packing (follow flag)

When the application provides more than one short ASEP packet that fits in a single
DLL container, the ASE may pack multiple packets back-to-back using the follow flag:

```
Payload layout for two packets in one container:
  Byte 0:   Byte0 fragmentation/boundary for Packet#k
  [Byte 1]: Byte1 if frag[1]=1
  Bytes m..m+N-1: ASEP Packet#k header + payload + footer
  (header Byte0 bit 0 = 1: follow flag set)
  Bytes m+N..m+N+M-1: ASEP Packet#k+1 header + payload + footer
  (header Byte0 bit 0 = 0: follow flag clear, last packet)
  Remaining bytes: dummy padding (if any)
```

SPEC FACT (Table 7-4, p235): The follow flag of 1 means "there is another ASEP
header in the same container directly after the last byte of the current packet."

---

## 13. RX Data Flow (ASD side)

### 13.1 RX Primitive

SPEC FACT (Section 5.7.1.1.1, p187): "DLP_RX.dataUnit(size, dll_payload, phyLStat,
dllStat) -- The DLL uses DLP_RX.dataUnit to provide the payload of a received
container, along with status information, to an ASD or OAM."

```
dllStat values:
  decode_good        no packetID error
  duplicate_packetID packetID in header < fullPacketID[4:0]+1
  missing_packetID   packetID in header > fullPacketID[4:0]+1
```

### 13.2 RX Reassembly Flow Diagram

```
DLP_RX.dataUnit(size, dll_payload, phyLStat, dllStat)
         [DLL -> ASD_i]
          |
          v
+----------------------+
| 1. Parse Byte0       |
|    fragmentation[1:0]|
|    boundary_pos[9:4] |
+----------+-----------+
           |
    frag[1]=1?
   /           \
  Yes           No
  |              |
  v              v
Parse Byte1    Byte1 absent;
frag_pos[3:0]  boundary pos from
               Byte0[5:0] only (6 bits)
  |              |
  +------+-------+
         |
         v
+----------------------+
| 2. Locate ASEP packet|
|    boundaries using  |
|    fragmentation code|
|    + boundary_pos    |
+----------------------+
         |
         v
+----------------------+
| 3. For each ASEP     |
|    packet/fragment:  |
|    Parse Byte0       |
|    (stream type,     |
|     follow flag)     |
|    Parse Byte1       |
|    (PTB mode)        |
|    If mode != 00:    |
|    Extract PTB[31:0] |
|    from bytes 2-5    |
|    Parse stream-spec |
|    header fields     |
+----------------------+
         |
         v
+----------------------+
| 4. Buffer fragment   |
|    or pass complete  |
|    packet to stream  |
|    decoder           |
+----------------------+
         |
     fragmentation 01 or
     last fragment
         |
         v
+----------------------+
| 5. If CRC present:   |
|    verify CRC after  |
|    full reassembly   |
|    Error -> 3.7.1    |
+----------------------+
         |
         v
+----------------------+
| 6. Deliver to stream-|
|    specific ASD      |
+----------------------+
```

### 13.3 Error Handling on RX

SPEC FACT (Section 7.2, p231): "Reassembly errors resulting in verifiably corrupt
application data units have to be recorded in 3.7.1."

SPEC FACT (Section 7.3.3, p236): "If the ASEP format does employ a CRC check, the
ASD shall check the consistency of the data after reassembly of the received
fragments and shall indicate an error by incrementing 3.7.1."

IMPLEMENTATION ASSUMPTION: The ASD must also check dllStat from DLP_RX.dataUnit for
duplicate_packetID or missing_packetID conditions. A missing_packetID means one or
more containers were lost; the in-progress reassembly buffer for the affected ASEP
packet should be discarded.

---

## 14. Interface to DLL Mapper/Demux

The ASEP common framing entity connects to the DLL Mapper/Demux through the standard
DLP_TX and DLP_RX interface primitives. There is one ASE per DLP_TX port and one ASD
per DLP_RX port.

### 14.1 TX Interface (DLL -> ASE)

| Primitive | Direction | Description |
|-----------|-----------|-------------|
| DLP_TX.indicateSlot(size) | DLL -> ASE | DLL requests container payload of given size; triggers ASE assembly cycle |
| DLP_TX.dataUnit(ase_payload) | ASE -> DLL | ASE provides assembled container payload |
| DLP_TX.yield() | ASE -> DLL | ASE has no data; DLL falls back to OAM |

### 14.2 RX Interface (DLL -> ASD)

| Primitive | Direction | Description |
|-----------|-----------|-------------|
| DLP_RX.dataUnit(size, dll_payload, phyLStat, dllStat) | DLL -> ASD | DLL delivers received DLL payload to ASD for parsing and reassembly |

### 14.3 Multiplexing Note

SPEC FACT (Section 7.1, p231): "Each ASE and ASD on a specific Data Link Layer Port
supports only a single ASEP." Therefore there is a 1:1 mapping between DLP port and
ASEP stream type; no stream-type demultiplexing is done within the DLL payload.

---

## 15. Interface to Stream-Specific ASEP Modules

The ASEP common framing layer is a shared shim between the DLL and each
stream-specific encoder/decoder. The boundary between common framing and
stream-specific logic is:

```
Common framing handles:
  TX: DLL container Byte0/Byte1 (fragmentation + boundary position)
      Common ASEP header Byte0 (stream type + follow flag)
      Common ASEP header Byte1 (PTB mode select)
      Common ASEP header Bytes 2-5 (PTB ingress or presentation timestamp if enabled)
      Fragmentation logic (splitting ASEP packets across DLL containers)
      Follow-flag packing (multiple short packets in one container)

  RX: Parse DLL container Byte0/Byte1 (fragmentation decode)
      Parse common ASEP header Byte0 (stream type, follow flag)
      Parse common ASEP header Byte1 (PTB mode)
      Extract PTB timestamp bytes 2-5 (if present)
      Reassembly across multiple containers (fragment buffering)
      Deliver complete ASEP payload bytes [mHB+1..mEND-footer] to stream decoder
      Pass PTB timestamp to stream decoder

Stream-specific modules handle:
  TX: Stream-specific header bytes [mHB+1..]
      Payload packing (pixel lines, I2C transactions, SPI frames, etc.)
      Footer assembly (CRC32 for video, etc.)

  RX: Stream-specific header parsing starting at byte [mHB+1]
      Payload interpretation and application delivery
      Footer verification (CRC check)
```

### 15.1 Interface to Video ASEP (Section 7.4)

```
TX: common framing -> video encoder
  mHB = 1 (no TS) or 5 (with TS)
  video encoder receives: DLL slot size, mHB
  video encoder produces: header bytes [mHB+1..mHB+9], video lines, CRC32

RX: video decoder <- common framing
  video decoder receives: reassembled bytes starting at [mHB+1], PTBingress[31:0]
```

### 15.2 Interface to Other Stream Types

Each stream-specific ASEP module receives from the common framing layer:
- On TX: the available payload size after the common header (size - Byte0 overhead - mHB - 1 bytes)
- On RX: the reconstructed ASEP payload starting at byte mHB+1, plus the PTB timestamp if present

---

## 16. Interface to PTB Clock Service

SPEC FACT (Tables 7-6, 7-7, p235-236): The ingress timestamp is "the lower 32 bits
of the PTBclk of the ASA node containing the ASE, taken when the first payload symbol
of this ASEP packet passed the application interface." The presentation timestamp is
the target PTBclk at which the first payload symbol is to be presented at the ASD.

### 16.1 PTB Interface

| Signal | Direction | Description |
|--------|-----------|-------------|
| ptb_clk_lower32[31:0] | PTB -> ASE | Current PTBclk[31:0] for ingress timestamp capture |
| ptb_clk_valid | PTB -> ASE | 1: PTBclk is locked and valid; 0: unreliable |
| ingress_ts_capture | ASE -> PTB | Pulse: capture current ptb_clk_lower32 at first payload symbol boundary |
| ingress_ts[31:0] | PTB -> ASE | Latched value after ingress_ts_capture |

IMPLEMENTATION ASSUMPTION: If PTB is not locked (ptb_clk_valid=0) and the stream
type requires an ingress timestamp, the ASE must still place a value in bytes 2-5.
The spec does not explicitly define the fallback; inserting 0x00000000 is recommended
to indicate invalid timestamp.

IMPLEMENTATION ASSUMPTION: The presentation timestamp calculation (mode 10) is
stream-type-specific. The common framing layer inserts whatever value the
stream-specific encoder provides into bytes 2-5; it does not compute the deadline.

---

## 17. RTL Submodule Architecture

### 17.1 Block Diagram

```
+===========================================================+
|                   asep_common_framing_top                  |
|                                                           |
|   TX PATH                                                 |
|   +-----------------+    +-----------------------+         |
|   | ase_tx_ctrl     |    | frag_encoder          |         |
|   |                 |    |                       |         |
|   | Receive         |--->| Build Byte0 (frag+pos)|         |
|   | indicateSlot    |    | Build Byte1 if needed |         |
|   | Coordinate      |    | Manage boundary pos   |         |
|   | assembly        |    +-----------------------+         |
|   +--------+--------+                                     |
|            |                                              |
|   +--------v--------+    +-----------------------+         |
|   | hdr_builder     |    | ptb_ts_capture        |         |
|   |                 |    |                       |         |
|   | Byte0: type+flg |<---| Latch PTBclk[31:0]   |<- PTBclk|
|   | Byte1: PTB mode |    | at first payload sym  |         |
|   | Bytes 2-5: TS   |    | from appl interface   |         |
|   +--------+--------+    +-----------------------+         |
|            |                                              |
|   +--------v--------+                                     |
|   | follow_packer   |                                     |
|   |                 |                                     |
|   | Multi-pkt pack  |                                     |
|   | follow flag ctrl|                                     |
|   | Dummy padding   |                                     |
|   +--------+--------+                                     |
|            |                                              |
|   DLP_TX.dataUnit(ase_payload)                            |
|                                                           |
|   RX PATH                                                 |
|   DLP_RX.dataUnit(size, dll_payload, phyLStat, dllStat)   |
|            |                                              |
|   +--------v--------+                                     |
|   | frag_decoder    |                                     |
|   |                 |                                     |
|   | Parse Byte0/1   |                                     |
|   | Decode frag code|                                     |
|   | Locate pkt bndry|                                     |
|   +--------+--------+                                     |
|            |                                              |
|   +--------v--------+    +-----------------------+         |
|   | hdr_parser      |    | ptb_ts_extractor      |         |
|   |                 |    |                       |         |
|   | Parse Byte0:    |--->| Extract bytes 2-5     |         |
|   |  stream type    |    | when mode != 00       |         |
|   |  follow flag    |    | Output ts[31:0]       |         |
|   | Parse Byte1:    |    +-----------------------+         |
|   |  PTB mode       |                                     |
|   +--------+--------+                                     |
|            |                                              |
|   +--------v--------+                                     |
|   | reassembler     |                                     |
|   |                 |                                     |
|   | Fragment buffer |                                     |
|   | Reconstruct pkt |                                     |
|   | Handle miss pkt |                                     |
|   +--------+--------+                                     |
|            |                                              |
|   +--------v--------+                                     |
|   | stream_dispatch |                                     |
|   |                 |                                     |
|   | Route by type   |                                     |
|   | to video/i2c/   |                                     |
|   | spi/gpio/etc.   |                                     |
|   +-----------------+                                     |
|                                                           |
|   REGISTERS                                               |
|   +-----------------+                                     |
|   | asep_reg_file   |                                     |
|   |                 |                                     |
|   | 4/5.i.0001-3   |                                     |
|   | 4/5.i.0004     |                                     |
|   | 4/5.i.0005     |                                     |
|   | 4/5.i.0006     |                                     |
|   | 4/5.i.0051-62  |                                     |
|   +-----------------+                                     |
+===========================================================+
```

### 17.2 Module Descriptions

| Module | Function | Notes |
|--------|----------|-------|
| ase_tx_ctrl | Top-level TX FSM: receives indicateSlot, dispatches assembly, sends dataUnit or yield | Per DLP_TX port |
| frag_encoder | Computes fragmentation code (00/01/10/11) and boundary_position[9:0]; generates Byte0 and optional Byte1 | Requires knowledge of ASEP packet size and container size |
| hdr_builder | Assembles common ASEP header: Byte0 (type+follow), Byte1 (PTB mode), Bytes 2-5 (timestamp) | PTB mode configured per stream |
| ptb_ts_capture | Latches PTBclk[31:0] at application-interface crossing; provides ingress timestamp | Interfaces with PTB clock service |
| follow_packer | Implements follow-flag packing for multiple short packets in one container; handles dummy padding | Optional; needed for GPIO/I2C streams |
| frag_decoder | Parses container Byte0/Byte1; decodes fragmentation code and boundary_position | Per DLP_RX port |
| hdr_parser | Extracts stream type, follow flag, PTB mode from common ASEP header bytes 0-1 | |
| ptb_ts_extractor | Extracts 4-byte PTB timestamp from header bytes 2-5 when PTB mode != 00 | |
| reassembler | Fragment reassembly buffer; handles multi-container ASEP packets; discards on missing_packetID | Depth = max ASEP packet size |
| stream_dispatch | Routes reassembled ASEP payload to stream-specific decoder by stream type | |
| asep_reg_file | Holds all 4/5.i.0001-0062 registers; exposes OAM read interface; manages fullPacketID increment | Shared logic with DLL for fullPacketID |

---

## 18. Spec Facts vs Implementation Assumptions

### 18.1 Spec Facts (normative, from ASA Technical Specification v2.0)

| # | Spec Fact | Source |
|---|-----------|--------|
| 1 | ASEP Byte0[7:6] = fragmentation code 00/01/10/11 | Table 7-2, p234 |
| 2 | ASEP Byte0[5:0] = boundary_position[9:4] (upper 6 bits) | Table 7-2, p234 |
| 3 | Byte1 present only when fragmentation[7]=1 (codes 10 or 11) | Table 7-2/7-3, p234 |
| 4 | ASEP Byte1[7:4] = boundary_position[3:0] (lower 4 bits) | Table 7-3, p234 |
| 5 | ASEP Byte1[3:0] = reserved | Table 7-3, p234 |
| 6 | boundary_position is the index of the first byte after the ASEP packet end; Byte0 itself is index 0 | Table 7-2, p234 |
| 7 | Code 11: if boundary_position=0x002, container starts a new packet | Table 7-2, p234 |
| 8 | Code 10: boundary_position may equal the first byte after the container payload | Table 7-2, p234 |
| 9 | Table 7-2 is binding over Figure 7-3 in case of inconsistency | p234 |
| 10 | ASEP Header Byte0[7:1] = stream type (7 bits) | Table 7-4, p235 |
| 11 | ASEP Header Byte0[0] = follow flag | Table 7-4, p235 |
| 12 | Follow flag=0: container remainder is dummy data if packet shorter than container | Table 7-4, p235 |
| 13 | Follow flag=1: another ASEP header immediately follows last byte of current packet | Table 7-4, p235 |
| 14 | ASEP Header Byte1[7:2] = reserved | Table 7-5, p235 |
| 15 | ASEP Header Byte1[1:0] = PTB mode: 00=none, 01=ingress, 10=presentation, 11=user-defined | Table 7-5, p235 |
| 16 | mHB = 1 when PTB mode = 00; mHB = 5 when PTB mode = 01, 10, or 11 | Section 7.3.2.1, p235 |
| 17 | PTBingress[31:0] = lower 32 bits of ASE node PTBclk at first payload symbol | Table 7-6, p235 |
| 18 | PTBpresent[31:0] = lower 32 bits of PTBclk target time for first payload symbol at ASD | Table 7-7, p236 |
| 19 | Both ingress and presentation timestamps are 4 bytes, big-endian, in bytes 2-5 | Tables 7-6, 7-7, p235-236 |
| 20 | ASEP footer CRC is optional; whether present is stream-type-specific | Section 7.3.3, p236 |
| 21 | CRC check is done after full reassembly; error increments register 3.7.1 | Section 7.3.3, p236 |
| 22 | fullPacketID[47:0] spans 4/5.i.0001-0003; lower 5 bits go into container header | Section 3.5.1.1, p67 |
| 23 | fullPacketID managed by DLL, lives in ASEP address space | Section 3.5.1.1, p67 |
| 24 | fullPacketID has no function for FoFa stream types (Return OAM, Forward Data) | Section 3.5.1.1, p68 |
| 25 | streamType (4/5.i.0004[6:0]) is RO; matches Table 7-1 values | Table 3-75, p68 |
| 26 | ASEP Test (4/5.i.0006) is L-only, not OAM-accessible | Table 3-77, p68-69 |
| 27 | Pin capability registers 4/5.i.0051-0058 are RO O RID | Tables 3-78 to 3-85, p69-76 |
| 28 | Pin config registers 4/5.i.0059-0062 are RW O RID | Table 3-86, p76-78 |
| 29 | One ASE per DLP_TX port; each supports exactly one ASEP | Section 7.1, p231 |
| 30 | ASE communicates with DLL via primitives in Section 5.6.1 | Section 7.1, p231 |
| 31 | ASD communicates with DLL via primitives in Section 5.7.1 | Section 7.2, p231 |
| 32 | Data starve event must be indicated in register 3.6.2 on timeout | Section 7.1, p231 |

### 18.2 Implementation Assumptions (not explicitly in spec)

| # | Assumption | Rationale |
|---|------------|-----------|
| A1 | Stream type value is left-shifted 1 bit into Byte0[7:1]; follow flag is Byte0[0] | Table 7-4 layout |
| A2 | Fragmentation Byte0[5:0] encoding of boundary_position when Byte1 is absent (codes 00, 01) is present in the wire byte but not functionally required | Table 7-2 format always includes the field |
| A3 | When PTB is not locked, ingress timestamp bytes 2-5 should be set to 0x00000000 to signal invalidity | Spec does not define fallback; 0 is safe default |
| A4 | Presentation timestamp is computed by stream-specific encoder and passed to common header builder; common framing does not compute it | Stream-type-specific knowledge required |
| A5 | Reassembly buffer depth must accommodate maximum ASEP packet size for the stream type; video ASEP can have large line payloads | Stream-dependent |
| A6 | On missing_packetID, the in-progress reassembly should be flushed | Fragments without all predecessors cannot be validated |
| A7 | fullPacketID increment and container packetID insertion is implemented in the DLL, which reads fullPacketID from the ASEP register space | Section 3.5.1.1 says "managed by the DLL" |
| A8 | The ASE is instantiated once per DLP_TX_ID (i=1..Nr_DLP_TX); DLP_TX_ID=0 is always OAM | DLL assigns DLP_TX_ID=0 to OAM |
| A9 | User-defined timestamp mode (11) occupies the same 4 bytes 2-5 as ingress/presentation; content is implementation-specific | Table 7-5 entry "time stamp size 4 bytes" |

---

## 19. Verification Plan

### 19.1 Container Framing (Byte0/Byte1)

| Test | Check | Expected |
|------|-------|----------|
| VF-1 | ASEP packet fits exactly in container | fragmentation = 01, Byte1 absent |
| VF-2 | ASEP packet ends mid-container with padding | fragmentation = 10, Byte1 present, boundary_position = first padding byte index |
| VF-3 | ASEP packet continues into next container | fragmentation = 00, no boundary position needed |
| VF-4 | ASEP packet end + new packet starts in same container | fragmentation = 11, Byte1 present, boundary_position = start of new header |
| VF-5 | boundary_position at index 0x002 (new packet at first content byte) | fragmentation = 11, position = 0x002 |
| VF-6 | boundary_position at maximum (first byte after container end) | fragmentation = 10, position = container_size |
| VF-7 | fragmentation = 00 for pure mid-packet container | no Byte1; Byte0[5:0] field value not checked |
| VF-8 | Verify Byte1[3:0] = 0 (reserved bits) | RX parses and ignores these bits |

### 19.2 Common ASEP Header

| Test | Check | Expected |
|------|-------|----------|
| VH-1 | stream type encoding in Byte0[7:1] | All 8 stream types: 0x01-0x07, 0x37 |
| VH-2 | follow flag Byte0[0]=0, single packet | No next packet; remaining bytes are dummy |
| VH-3 | follow flag Byte0[0]=1, two packets packed | Second ASEP header immediately after first packet end |
| VH-4 | PTB mode Byte1[1:0]=00, mHB=1 | No timestamp bytes present |
| VH-5 | PTB mode Byte1[1:0]=01, mHB=5 | 4-byte ingress timestamp at bytes 2-5 |
| VH-6 | PTB mode Byte1[1:0]=10, mHB=5 | 4-byte presentation timestamp at bytes 2-5 |
| VH-7 | Byte1[7:2] = 0 (reserved) | Transmit 0; receive: ignore |

### 19.3 PTB Timestamp

| Test | Check | Expected |
|------|-------|----------|
| VP-1 | PTBingress[31:0] = PTBclk[31:0] at application interface crossing | Captured value matches PTBclk register snapshot |
| VP-2 | PTBingress big-endian in bytes 2-5 | Byte2=[31:24], Byte3=[23:16], Byte4=[15:8], Byte5=[7:0] |
| VP-3 | PTBpresent big-endian in bytes 2-5 | Same byte order as ingress |
| VP-4 | PTB not locked: timestamp = 0x00000000 | Implementation assumption A3 |
| VP-5 | Timestamp captured at first payload symbol boundary, not at header build time | Verify timing against application interface |

### 19.4 Registers

| Test | Check | Expected |
|------|-------|----------|
| VR-1 | fullPacketID increments on each TX container | 4/5.i.0001 increments; [4:0] matches header packetID |
| VR-2 | fullPacketID reads back via OAM (O access) | OAM Read returns correct value |
| VR-3 | fullPacketID resets to 0 on SoftReset | 3-register 48-bit counter cleared |
| VR-4 | streamType (4/5.i.0004) is read-only | Write attempt has no effect |
| VR-5 | ASEP Test (4/5.i.0006) is L-only | OAM Read/Write rejected |
| VR-6 | Pin capability registers are RO, OAM-readable | Write has no effect; OAM read succeeds |
| VR-7 | Pin config registers are RW OAM | Write changes value; read returns new value |

### 19.5 Data Starve

| Test | Check | Expected |
|------|-------|----------|
| VS-1 | ASE sends yield when no application data within timeout | DLP_TX.yield() is generated; DLL falls back to OAM |
| VS-2 | Data starve event recorded in register 3.6.2 | 3.6.2 incremented (stream-type-specific timeout) |

---

## 20. Missing / Needs Verification

1. **fullPacketID bit width discrepancy**: Section 3.5.1.1 (p67-68) and the register
   micro-architecture doc (micro-architecture-register-model.md) both state 48 bits
   across three 16-bit registers (4/5.i.0001-0003). However, the OAM doc references
   "40-bit" fullPacketID in some places. The register model document's Table 7.2
   shows three registers producing 48 bits. SPEC FACT from Section 3.5.1.1: three
   registers. IMPLEMENTATION ASSUMPTION: 48-bit. VERIFY by confirming the spec has
   exactly three registers as defined in Table 3-74 (4/5.i.0001, 0002, 0003).

2. **PTBingress capture timing**: The spec says the ingress timestamp is "taken when
   the first payload symbol of this ASEP packet passed the application interface."
   This is a synchronous capture event at the TX side's application boundary. For
   camera video, this is well-defined (first pixel). For I2C or SPI, "first payload
   symbol" is ambiguous. VERIFY whether stream-specific sections (7.5, 7.7) define
   the exact capture point for their payload types.

3. **Boundary position encoding when fragmentation=00 or 01**: The spec defines that
   Byte0[5:0] always carries boundary_position[9:4], even for codes 00 and 01.
   Code 01 means "packet ends on last byte of container" -- the boundary position
   is architecturally irrelevant in that case. Code 00 means no packet boundary.
   VERIFY whether the ASE should write a specific value (e.g., 0x00) or an
   unspecified value into Byte0[5:0] for codes 00 and 01.

4. **Presentation timestamp computation for non-video streams**: The common framing
   spec (7.3.2.1) defines the presentation timestamp format but does not specify how
   the ASE computes the future PTBclk value for non-video streams. For SPI timing
   (Section 7.7.1.6), the spec notes "if precise timing is required for the SPI bus
   interface, the common ASEP mechanism with PTB presentation times has to be used."
   VERIFY whether Sections 7.5-7.10 specify the deadline calculation method or
   leave it to the implementer.

5. **Data starve register 3.6.2 definition**: Section 7.1 (p231) references register
   3.6.2 for the data starve event, but the timeout value is stated as "stream type
   and application dependent." VERIFY whether register 3.6.2 contains a configurable
   timeout threshold or is purely a status/error counter.

6. **User-defined timestamp (mode 11) size**: Table 7-5 (p235) states mode 11 is
   "user defined (time stamp size 4 bytes)" which matches the mHB=5 rule. VERIFY
   that mode 11 always uses exactly 4 bytes at bytes 2-5, consistent with modes 01
   and 10, and that no stream type uses a different-size user-defined timestamp.

7. **Follow flag with fragmentation codes 10 and 11**: When fragmentation=10 or 11
   (Byte1 present), and multiple ASEP packets are packed via follow flag, the
   interaction between the boundary position field and the follow flag is not
   explicitly illustrated in the spec. VERIFY that the boundary_position in Byte0/1
   refers to the entire container's last terminating ASEP packet, not to the first
   packet when follow flag is set.

8. **fullPacketID for FoFa ports**: Section 3.5.1.1 states the register "has no
   function" for Forward Data and Return OAM stream types. VERIFY whether the DLL
   still increments or reads fullPacketID for these ports, or whether it simply
   ignores the register entirely.

9. **Byte1[3:0] reserved bits on receive**: Table 7-3 marks Byte1[3:0] as reserved.
   VERIFY whether the ASD is required to reject containers where Byte1[3:0] != 0,
   or whether these bits must be silently ignored (as is typical for reserved fields
   in ASA).

10. **Stream type = 0x37 (Test ASEP) header format**: The Test ASEP is defined in
    Section 7.11. VERIFY whether it uses the full common ASEP header (mHB=1 or 5)
    or a modified format, and whether the PTB timestamp modes are all supported.

---

## 21. Summary

The ASEP Common Framing layer is a mandatory shared infrastructure component for
all ASEP stream types in an ASA node. Its key functional elements are:

1. **DLL Container Framing (Section 7.3.1)**: Byte0 encodes a 2-bit fragmentation
   code and 6 bits of boundary position; Byte1 (when fragmentation[1]=1) extends
   the boundary position to 10 bits total. Four fragmentation codes describe whether
   a container carries a packet boundary with padding (10), a packet boundary followed
   by a new packet header (11), a mid-packet fragment (00), or a packet ending on the
   last byte (01).

2. **Common ASEP Header (Section 7.3.2)**: Byte0 carries the 7-bit stream type in
   bits 7:1 and the follow flag in bit 0. The follow flag enables back-to-back packing
   of multiple short ASEP packets within one DLL container. Byte1 selects the PTB
   timestamp mode (none, ingress, presentation, or user-defined).

3. **PTB Timestamps (Section 7.3.2.1)**: When enabled, bytes 2-5 carry a 32-bit
   PTBclk timestamp (lower 32 bits only). The ingress timestamp is captured at the
   transmitting ASE when the first payload symbol crosses the application interface;
   the presentation timestamp is the target delivery time at the receiving ASD.

4. **ASEP Footer (Section 7.3.3)**: Optional CRC checksum; stream-type-specific.
   The ASD verifies CRC after complete reassembly and increments error register 3.7.1
   on failure.

5. **ASEP Registers (Sections 3.5.1-3.5.1.6)**: fullPacketID (48-bit counter,
   4/5.i.0001-0003, managed by DLL), stream type (4/5.i.0004, RO), stream vendor ID
   (4/5.i.0005, RO), ASEP test enable (4/5.i.0006, L-only), pin capability (RO,
   4/5.i.0051-0058), and pin config (RW, 4/5.i.0059-0062).
