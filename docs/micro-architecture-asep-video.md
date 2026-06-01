# Micro-Architecture: ASEP Video (Section 7.4)

## 1. Purpose and Scope

The ASEP Video (stream type 0x01) module defines the packet format and processing
rules for transporting raw video data over an ASA link using the Application Stream
Encapsulation Protocol. It encapsulates individual video scan lines, blanking-period
metadata, and pixel clock timing information inside standard ASEP frames carried by
the Data Link Layer.

This document defines the micro-architecture of the ASEP Video encoder (ASE) and
decoder (ASD) for RTL or golden-model implementation, derived directly from ASA
Technical Specification v2.0, Sections 7.4, 7.4.1, 7.4.1.1, 7.4.1.2, 7.4.2 (pages
236-240) and Appendix B: Video ASEP Pixel Format Tables (pages 305-337, NORMATIVE).

Scope boundaries:
- IN SCOPE: ASEP Video packet type selector (Table 7-8), Video Line header fields
  (Table 7-9), Video Line footer CRC (Table 7-10), Pixelclk header (Table 7-11),
  Pixelclk payload fields (Table 7-12), Pixelclk footer, pixel format encoding
  (Appendix B, Tables II-1 through II-49, NORMATIVE), PTB presentation timestamp
  usage for video delivery, TX flow (application pixel lines -> ASE -> DLP_TX),
  RX flow (DLP_RX -> ASD -> pixel reconstruction), interface to ASEP common framing
  (micro-architecture-asep-common-framing.md), RTL submodule map, verification plan.
- OUT OF SCOPE: ASEP common framing Byte0/Byte1 container fragmentation and PTB
  timestamp byte assembly (micro-architecture-asep-common-framing.md), DLL scheduler
  (micro-architecture-dll-mapper-demux-core.md), PTB clock synchronization algorithm
  (micro-architecture-ptb-clock-service.md), pixel interface to display or camera
  hardware (implementation-dependent), pixel packing of individual Appendix B tables
  in detail (tables referenced by ID; full contents in ASA spec pages 305-337).

---

## 2. Source References

Section  | Title                                      | Pages    | Relevance
-------- | ------------------------------------------ | -------- | ---------
7.3      | Common ASEP Format Basics                  | 231-236  | Common header/footer, PTB timestamps
7.3.2.1  | ASEP PTB Time Stamps                       | 235-236  | Tables 7-5, 7-6, 7-7
7.4      | ASEP Format: Video Data                    | 236      | Section introduction, PTBpresent
7.4.1    | Video Data Packet Types                    | 236      | Table 7-8 type selector
7.4.1.1  | Video Line                                 | 236-238  | Tables 7-9, 7-10
7.4.1.2  | Pixelclk                                   | 238-240  | Tables 7-11, 7-12, footer
7.4.2    | Usage of Format                            | 240      | Informative usage guidance
Appendix B | Video ASEP Pixel Format Tables (NORMATIVE)| 305-337  | Tables II-1 through II-49
4.2.9    | CRC32                                      | 120-121  | CRC polynomial, starting value

Structured extraction source: pipeline/out/asa_structured_chunks.jsonl, section IDs
asa-7.4, asa-7.4.1, asa-7.4.1.1, asa-7.4.1.2, asa-7.4.2, asa-II-part-1.

---

## 3. ASEP Video System Overview

### 3.1 Role and Stream Type Code

SPEC FACT (Table 7-1, Section 7.3, p233): ASEP stream type 0x01 is "Video Data",
defined in Section 7.4.

SPEC FACT (Section 7.4.2, p240): "this ASEP stream type is unidirectional."

The video ASE transmits pixel line data from a local video source (camera or display
controller) to a remote video sink (display engine or video processor) across the
ASA link. No return channel is defined in the Video Data ASEP.

### 3.2 Position in Protocol Stack

```
  +--------------------------------------------------+
  | Video Source (camera, frame buffer, display eng) |
  +----------------------------+---------------------+
                               |
                    +----------v----------+
                    | ASEP Video ASE (TX) |
                    | - Video Line packer |
                    | - Pixelclk sender   |
                    | - Header/footer gen |
                    +----------+----------+
                               |
               +---------------v---------------+
               | ASEP Common Framing (TX)       |
               | - Container Byte0/Byte1        |
               | - Common header (type+TS)      |
               | - Fragmentation encoder        |
               +---------------+---------------+
                               |
               +---------------v---------------+
               |    DLL Mapper / DLP_TX         |
               +---------------+---------------+
                               | (ASA link)
               +---------------v---------------+
               |    DLL Demux / DLP_RX          |
               +---------------+---------------+
                               |
               +---------------v---------------+
               | ASEP Common Framing (RX)       |
               | - Reassembly, CRC check        |
               | - Common header parsing        |
               +---------------+---------------+
                               |
                    +----------v----------+
                    | ASEP Video ASD (RX) |
                    | - Video Line parse  |
                    | - Pixelclk parse    |
                    | - PTBpresent sched  |
                    +----------+----------+
                               |
  +----------------------------v---------------------+
  | Video Sink (display FIFO, camera host interface) |
  +--------------------------------------------------+
```

---

## 4. Video Data Packet Type Selector (Section 7.4.1, Table 7-8, p236)

SPEC FACT (Section 7.4.1, p236): "All headers start with the following fields:"

```
Byte   Bit(s)  Field                    Encoding
-----  ------  -----                    --------
m+1_HB  7:5   Video Data header type   000: Pixel Clk
                                        001: Video Line, video data
                                        010: Video Line, format specific data
                                        011: Video Line, vendor/user specific data
                                        100: Video Line, null data
                                        101..111: reserved
```

Table reference: Table 7-8, ASEP Video Data--header first part (p236).

Notes:
- m is the maximum byte index of the common ASEP header (mHB), as defined in
  micro-architecture-asep-common-framing.md. mHB is 1 when no PTB timestamp is
  present and 5 when a PTB timestamp is present (bytes 2-5).
- m+1_HB is the first byte of the stream-specific header section, immediately after
  the last common header byte.
- Bits 7:5 of m+1_HB carry the Video Data header type. Bits 4:0 of m+1_HB vary by
  packet type (see Sections 5 and 6 below).

### 4.1 Summary of Packet Types

```
Code  Packet Type         Payload Content
----  -----------         ---------------
000   Pixelclk            Frame timing metadata (rate, lines, pixels, blanking)
001   Video Line (data)   Pixel data; VideoLength*2 = number of pixels
010   Video Line (format) Format-specific data; VideoLength in bytes
011   Video Line (vendor) Vendor/user-specific data; VideoLength in bytes
100   Video Line (null)   Null/dummy line; VideoLength*2 = number of pixels
101+  reserved            Must not be generated; silently discard on RX
```

IMPLEMENTATION ASSUMPTION: The most common packet type in normal operation is 001
(Video Line, video data). Type 000 (Pixelclk) appears between frame groups.
Types 010, 011, and 100 are less frequent specializations; their header structure is
identical to type 001 but payload interpretation differs.

---

## 5. Video Line Header Format (Section 7.4.1.1, Table 7-9, p236-238)

### 5.1 Complete Video Line Header Field Table

```
Byte       Bit(s)  Field                  Width  Description
--------   ------  -----                  -----  -----------
m+1_HB      7:5   Video Data hdr type    3      001: video data; 010: format spec;
                                                 011: vendor/user; 100: null data
m+1_HB       4    Vsync                  1      1: Vertical Sync active for this line
                                                 0: no Vsync
                                                 Display: count of Vsync=1 lines shall
                                                 match display format. Camera: any value.
m+1_HB       3    Vend                   1      1: last line of frame; 0: not last line
m+1_HB       2    Reserved               1      Set to 0 on TX; ignore on RX
m+1_HB      1:0   Video Stream [3:2]     2      Upper 2 bits of 4-bit stream indicator
                                                 (unsigned integer)
m+2_HB      7:6   Video Stream [1:0]     2      Lower 2 bits of 4-bit stream indicator
                                                 Combined: Video Stream [3:0] = 4-bit
                                                 unsigned integer identifying the video
                                                 stream (e.g. stereo channel select)
m+2_HB      5:0   Video Length [13:8]    6      Upper 6 bits of 14-bit Video Length
                                                 (unsigned integer)
m+3_HB      7:0   Video Length [7:0]     8      Lower 8 bits of 14-bit Video Length
                                                 Combined: Video Length [13:0] = 14-bit
                                                 unsigned integer, where:
                                                 If hdr type = 001 or 100:
                                                   VideoLength * 2 = number of pixels
                                                   (Hsync, FrontPorch, BackPorch included)
                                                 If hdr type = 010 or 011:
                                                   VideoLength = payload length in bytes
m+4_HB      7:4   Pixel data format      4      0000: RAW
                                                 0001: RGB
                                                 0010: RGBa (RGB with alpha)
                                                 0011: RGBW
                                                 0100: YUV444
                                                 0101: YUV422
                                                 0110: YUV411
                                                 0111..1111: reserved
m+4_HB      3:0   Pixel bit depth        4      0000: 8 bit
                                                 0001: 10 bit
                                                 0010: 12 bit
                                                 0011: 14 bit
                                                 0100: 16 bit
                                                 0101: 20 bit (RAW only)
                                                 0110: 24 bit (RAW only)
                                                 0111: 28 bit (RAW only)
                                                 1000: 32 bit (RAW only)
                                                 1001..1111: reserved
m+5_HB      7:6   Pixel alpha depth      2      00: none (no alpha channel)
                                                 01: 1 bit alpha
                                                 10: 8 bit alpha
                                                 11: identical to color bit width
m+5_HB      5:0   Reserved               6      Set to 0 on TX; ignore on RX
m+6_HB      7:0   CRC32[31:24]           8      Checksum over header bytes 0 to m+5_HB
                                                 (bytes 0 through m+5 of the ASEP
                                                 packet, inclusive); see 4.2.9
m+7_HB      7:0   CRC32[23:16]           8
m+8_HB      7:0   CRC32[15:8]            8
m+9_HB      7:0   CRC32[7:0]             8
```

Table reference: Table 7-9, ASEP Video Data--Video line header (p236-238).

### 5.2 Video Line Header Size

The Video Line header occupies bytes 0 through m+9_HB, relative to the start of
the ASEP packet. With respect to the common ASEP header:
- Bytes 0..mHB: common header (2 bytes without timestamp, 6 bytes with timestamp)
- Bytes mHB+1..mHB+9: Video Line stream-specific header (10 bytes always)

IMPLEMENTATION ASSUMPTION: The header CRC32 covers bytes 0 through mHB+5 of the
ASEP packet (common header bytes 0..mHB plus Video Line header bytes mHB+1..mHB+5).
The CRC occupies bytes mHB+6 through mHB+9 (4 bytes). Total stream-specific header
size before payload: 10 bytes (fields through CRC32[7:0]).

### 5.3 Video Line Header ASCII Layout

```
Bit position within each byte:
  7   6   5   4   3   2   1   0
+---+---+---+---+---+---+---+---+
| hdr_type[2:0]     |Vsy|Ven|Rsv|VS[3:2]| <- byte m+1_HB
+---+---+---+---+---+---+---+---+
|VS[1:0]| Video Length [13:8]         | <- byte m+2_HB
+---+---+---+---+---+---+---+---+
| Video Length [7:0]                  | <- byte m+3_HB
+---+---+---+---+---+---+---+---+
| Pixel data format [7:4]|Px bit depth| <- byte m+4_HB
+---+---+---+---+---+---+---+---+
|Px alpha[7:6]| Reserved [5:0]        | <- byte m+5_HB
+---+---+---+---+---+---+---+---+
| CRC32[31:24]                        | <- byte m+6_HB
+---+---+---+---+---+---+---+---+
| CRC32[23:16]                        | <- byte m+7_HB
+---+---+---+---+---+---+---+---+
| CRC32[15:8]                         | <- byte m+8_HB
+---+---+---+---+---+---+---+---+
| CRC32[7:0]                          | <- byte m+9_HB
+---+---+---+---+---+---+---+---+
| --- Video Line Payload ---          | <- byte m+10_HB ... mEND-4
| Pixel data per Appendix B table     |
+---+---+---+---+---+---+---+---+
| Payload CRC32[31:24]                | <- byte mEND-3
+---+---+---+---+---+---+---+---+
| Payload CRC32[23:16]                | <- byte mEND-2
+---+---+---+---+---+---+---+---+
| Payload CRC32[15:8]                 | <- byte mEND-1
+---+---+---+---+---+---+---+---+
| Payload CRC32[7:0]                  | <- byte mEND
+---+---+---+---+---+---+---+---+

hdr_type = Video Data header type [2:0]
Vsy      = Vsync
Ven      = Vend
Rsv      = Reserved (bit 2)
VS       = Video Stream [3:0] (split across bytes m+1 and m+2)
```

---

## 6. Video Line Payload (Appendix B, NORMATIVE, p305-337)

### 6.1 Normative Status

SPEC FACT (Section 7.4.1.1, p238): "Payload: ASA supported pixel formats are listed
in Table II-1 in the appendix."

SPEC FACT (module-map doc, p548): "Appendix B: Normative -- pixel format encoding
tables (33 pages, 8 table chunks)."

Appendix B is NORMATIVE. All pixel data layout within the Video Line payload is
fully determined by the tables in Appendix B. The (Pixel data format, Pixel bit
depth, Pixel alpha depth) triplet in the Video Line header selects the applicable
table. RTL must implement the exact byte-per-pixel and sub-pixel packing order
defined in those tables.

### 6.2 Pixel Format Summary Table (Table II-1, p305)

The following enumerates all named formats and their corresponding Appendix B table.
The (format, depth) codes in the left columns map to the bit-field encodings in the
Video Line header (Section 5.1 above).

```
Format    Depth(color) Alpha    Appendix B Table  Table Number
-------   ------------ -----    ----------------  ------------
RGB       8            none     ASEP RGB 8bit     II-2
RGB       10           none     ASEP RGB 10bit    II-3
RGB       12           none     ASEP RGB 12bit    II-4
RGB       14           none     ASEP RGB 14bit    II-5
RGB       16           none     ASEP RGB 16bit    II-6
RGBa      8            1 bit    ASEP RGBa 8,1bit  II-7
RGBa      8            8 bit    ASEP RGBa 8,8bit  II-8
RGBa      10           1 bit    ASEP RGBa 10,1bit II-9
RGBa      10           8 bit    ASEP RGBa 10,8bit II-10
RGBa      10           10 bit   ASEP RGBa 10,10bit II-11
RGBa      12           1 bit    ASEP RGBa 12,1bit II-12
RGBa      12           8 bit    ASEP RGBa 12,8bit II-13
RGBa      12           12 bit   ASEP RGBa 12,12bit II-14
RGBa      14           1 bit    ASEP RGBa 14,1bit II-15
RGBa      14           8 bit    ASEP RGBa 14,8bit II-16
RGBa      14           14 bit   ASEP RGBa 14,14bit II-17
RGBa      16           1 bit    ASEP RGBa 16,1bit II-18
RGBa      16           8 bit    ASEP RGBa 16,8bit II-19
RGBa      16           16 bit   ASEP RGBa 16,16bit II-20
RGBW      8            none     ASEP RGBW 8bit    II-21
RGBW      10           none     ASEP RGBW 10bit   II-22
RGBW      12           none     ASEP RGBW 12bit   II-23
RGBW      14           none     ASEP RGBW 14bit   II-24
RGBW      16           none     ASEP RGBW 16bit   II-25
YUV444    8            none     ASEP YUV444 8bit  II-26
YUV444    10           none     ASEP YUV444 10bit II-27
YUV444    12           none     ASEP YUV444 12bit II-28
YUV444    14           none     ASEP YUV444 14bit II-29
YUV444    16           none     ASEP YUV444 16bit II-30
YUV422    8            none     ASEP YUV422 8bit  II-31
YUV422    10           none     ASEP YUV422 10bit II-32
YUV422    12           none     ASEP YUV422 12bit II-33
YUV422    14           none     ASEP YUV422 14bit II-34
YUV422    16           none     ASEP YUV422 16bit II-35
YUV411    8            none     ASEP YUV411 8bit  II-36
YUV411    10           none     ASEP YUV411 10bit II-37
YUV411    12           none     ASEP YUV411 12bit II-38
YUV411    14           none     ASEP YUV411 14bit II-39
YUV411    16           none     ASEP YUV411 16bit II-40
RAW       8            none     ASEP Raw 8bit     II-41
RAW       10           none     ASEP Raw 10bit    II-42
RAW       12           none     ASEP Raw 12bit    II-43
RAW       14           none     ASEP Raw 14bit    II-44
RAW       16           none     ASEP Raw 16bit    II-45
RAW       20           none     ASEP Raw 20bit    II-46
RAW       24           none     ASEP Raw 24bit    II-47
RAW       28           none     ASEP Raw 28bit    II-48
RAW       32           none     ASEP Raw 32bit    II-49
```

IMPLEMENTATION ASSUMPTION: All 49 table entries in Appendix B are normative. RTL
implementations that do not support a given format must not generate Video Line
packets with that format+depth combination. The ASD may discard received packets
whose format+depth combination is unsupported, incrementing an appropriate error
counter.

### 6.3 RAW 32-bit Pixel Format Example (Table II-49, p337)

SPEC FACT: Table II-49 defines RAW 32-bit pixel packing as:

```
Byte    Bits    Field             Condition
------  ------  -----             ---------
n       [0:7]   Raw[m]_[0:7]     n%4=0, m=n/4   (LSByte of 32-bit raw word)
n+1     [0:7]   Raw[m]_[8:15]
n+2     [0:7]   Raw[m]_[16:23]
n+3     [0:7]   Raw[m]_[24:31]                   (MSByte of 32-bit raw word)
```

This yields 32 bits per pixel, 4 bytes per sample, little-endian byte order within
each raw sample word.

IMPLEMENTATION ASSUMPTION: The byte order used in Appendix B tables (n, n+1, n+2,
n+3 = LSByte to MSByte) is consistent across all RAW depth variants. For RAW depths
less than 32 bits (8, 10, 12, 14, 16, 20, 24, 28), the tables define the applicable
sub-word packing; implementers must reference each specific table.

---

## 7. Video Line Footer (Section 7.4.1.1, Table 7-10, p238)

### 7.1 Footer Field Table

```
Byte        Bit(s)  Field            Description
--------    ------  -----            -----------
mEND-3      7:0     CRC32[31:24]     Checksum over all payload bytes m+10_HB to
                                     mEND-4 (where m is the last common header byte
                                     mHB, and mEND is the last byte index of the
                                     entire ASEP packet); see Section 4.2.9
mEND-2      7:0     CRC32[23:16]
mEND-1      7:0     CRC32[15:8]      See 4.2.9
mEND        7:0     CRC32[7:0]
```

Table reference: Table 7-10, ASEP Video Data--Video Line footer (p238).

### 7.2 CRC32 Parameters (Section 4.2.9, p120-121)

SPEC FACT (Section 4.2.9, p120): "The cyclic redundancy check shall use the
polynomial 0xF4ACFB13."
SPEC FACT (Section 4.2.9, p120): "The starting value of the CRC is 0xFFFFFFFF."
SPEC FACT (Section 4.2.9, p120): "The appendix (XOR value) of the CRC is 0xFFFFFFFF."
SPEC FACT (Section 4.2.9, p120): "The input data shall be used byte-wise reflected."
SPEC FACT (Section 4.2.9, p120): "The result data shall be used reflected."

```
CRC32 configuration summary:
  Algorithm:     CRC-32 custom polynomial
  Polynomial:    0xF4ACFB13
  Init value:    0xFFFFFFFF
  Final XOR:     0xFFFFFFFF
  Input reflect: byte-wise (each byte reflected before processing)
  Output reflect: yes (result bits reflected before final XOR)
```

### 7.3 Two Separate CRCs in Video Line Packet

The Video Line packet carries two distinct CRC32 fields:

1. Header CRC32 (4 bytes at bytes m+6_HB through m+9_HB): covers the common header
   bytes 0..mHB plus stream-specific header bytes mHB+1..mHB+5.

2. Payload CRC32 (4 bytes at bytes mEND-3 through mEND): covers all payload bytes
   m+10_HB through mEND-4.

IMPLEMENTATION ASSUMPTION: The header CRC protects the pixel format and line
dimension fields, allowing fast rejection of corrupt header metadata without
processing the payload. The payload CRC covers the full pixel data for end-to-end
data integrity. Both CRCs use the same CRC32 algorithm (Section 4.2.9).

---

## 8. Pixelclk Header Format (Section 7.4.1.2, Table 7-11, p238)

### 8.1 Pixelclk Header Field Table

```
Byte       Bit(s)  Field                  Description
--------   ------  -----                  -----------
m+1_HB      7:5   Video Data hdr type    000: Pixelclk (constant for this packet type)
m+1_HB      4:0   Reserved               Set to 0 on TX; ignore on RX
```

Table reference: Table 7-11, ASEP Video Data--Pixelclk header (p238).

The Pixelclk packet has a minimal stream-specific header: only the packet-type field
(bits 7:5 = 000) and 5 reserved bits. The meaningful content is in the payload.

---

## 9. Pixelclk Payload Format (Section 7.4.1.2, Table 7-12, p238-240)

### 9.1 Complete Pixelclk Payload Field Table

```
Byte       Bit(s)  Field                  Width  Description
--------   ------  -----                  -----  -----------
m+2_HB      7:0   Frame rate             8      Dual-mode encoding:
                                                   If bit 7 = 1 (code 1XXX_XXXX):
                                                   bits [6:0] are a predefined code:
                                                     000_0000 = 23.976 fps
                                                     000_0001 = 24 fps
                                                     000_0010 = 25 fps
                                                     000_0011 = 29.97 fps
                                                     000_0100 = 30 fps
                                                     000_0101 = 48 fps
                                                     000_0110 = 50 fps
                                                     000_0111 = 59.94 fps
                                                     000_1000 = 60 fps
                                                     000_1001 = 72 fps
                                                     000_1010 = 100 fps
                                                     000_1011 = 119.88 fps
                                                     000_1100 = 120 fps
                                                     000_1101 = 144 fps
                                                     000_1110 = 240 fps
                                                     000_1111 = 300 fps
                                                   other [6:0] values: reserved
                                                   If bit 7 = 0 (code 0XXX_XXXX):
                                                   bits [6:0] = frame rate in Hz
                                                   (direct integer encoding, 0-127 Hz)
m+3_HB     15:8   Lines [15:8]           8      Upper 8 bits of 16-bit total line
                                                 count including blanking lines
m+4_HB      7:0   Lines [7:0]            8      Lower 8 bits of total line count
                                                 Combined: Lines[15:0] = 16-bit
                                                 unsigned integer, total lines per
                                                 frame including vertical blanking
m+5_HB      7:6   Reserved               2      Set to 0 on TX; ignore on RX
m+5_HB      5:0   Pixels per line [13:8] 6      Upper 6 bits of 14-bit total pixel
                                                 count per line (in multiples of 2);
                                                 Hsync, FrontPorch, BackPorch included
m+6_HB      7:0   Pixels per line [7:0]  8      Lower 8 bits of pixels per line
                                                 Combined: Pixels[13:0] = 14-bit
                                                 unsigned integer, pixels per full
                                                 line including horizontal blanking;
                                                 must be even (multiples of 2)
m+7_HB      7:0   H-BackPorch            8      Horizontal Back-Porch in pixels
                                                 (uint8); the sum of H-BackPorch,
                                                 H-FrontPorch, and Hsync shall match
                                                 the horizontal blanking of the display
                                                 format; arbitrary for camera data
m+8_HB      7:0   Hsync                  8      Horizontal Sync width in pixels
                                                 (uint8); sum constraint same as above
m+9_HB      7:1   H-FrontPorch           7      Horizontal Front-Porch in pixels
                                                 (unsigned 7-bit integer); sum
                                                 constraint same as above; arbitrary
                                                 for camera data
m+9_HB       0    Hsync-Polarity         1      Horizontal Sync polarity
                                                 (encoding not specified in spec text;
                                                 see Section 15.1 uncertainty)
```

Table reference: Table 7-12, ASEP Video Data--Pixelclk payload (p238-240).

### 9.2 Frame Rate Encoding Detail

SPEC FACT (Table 7-12, p238-239): "For 1XXX_XXXX codes, [6:0] code: [predefined
list of frame rates]". "For 0XXX_XXXX codes, [6:0] denominates the frame rate in Hz."

```
Frame Rate Encoding Summary:
  Byte value format: [mode_bit | code_or_value[6:0]]

  Mode bit = 1 (standard frame rates, coded):
    Full byte  [6:0]  fps value
    ---------- -----  ---------
    0x80       0x00   23.976
    0x81       0x01   24
    0x82       0x02   25
    0x83       0x03   29.97
    0x84       0x04   30
    0x85       0x05   48
    0x86       0x06   50
    0x87       0x07   59.94
    0x88       0x08   60
    0x89       0x09   72
    0x8A       0x0A   100
    0x8B       0x0B   119.88
    0x8C       0x0C   120
    0x8D       0x0D   144
    0x8E       0x0E   240
    0x8F       0x0F   300
    0x90-0xFF  0x10+  reserved

  Mode bit = 0 (direct integer encoding):
    Byte value [6:0] = frame rate in Hz (1..127 Hz representable)
    Byte value 0x00  = 0 Hz (undefined/not applicable)
    Byte range 0x01-0x7F = 1..127 fps direct
```

IMPLEMENTATION ASSUMPTION: The predefined code list covers fractional and high
frame rates that cannot be expressed as direct integers (23.976, 29.97, 59.94,
119.88). When mode bit = 0, only integer frame rates 1-127 Hz are representable.
For frame rates requiring fractional precision beyond the predefined list, the spec
provides no mechanism; the closest predefined code should be used.

### 9.3 Horizontal Blanking Constraint

SPEC FACT (Table 7-12, p239-240): "the sum of H-Back-Porch, H-FrontPorch and Hsync
shall match the horizontal blanking of the display format; is allowed arbitrary
values for camera data."

```
Required constraint for display mode:
  H-BackPorch + H-FrontPorch + Hsync = horizontal blanking pixels

  Where:
    horizontal blanking = (Pixels per line) - (active pixel count per line)

Relaxed for camera mode:
  H-BackPorch, H-FrontPorch, Hsync may carry any values
  The constraint is informational only when camera source is used
```

IMPLEMENTATION ASSUMPTION: The H-FrontPorch field in the Pixelclk payload is 7 bits
wide (byte m+9_HB bits 7:1), giving a range of 0-127 pixels. This limits the maximum
H-FrontPorch to 127 pixels. The H-BackPorch and Hsync fields are 8 bits (uint8), range
0-255 pixels. For display formats with large blanking, implementers must verify that
the 7-bit H-FrontPorch field is sufficient.

---

## 10. Pixelclk Footer (Section 7.4.1.2, p240)

The Pixelclk packet has a 4-byte footer with the same CRC32 structure as the Video
Line footer, but covering the Pixelclk payload bytes.

```
Byte        Bit(s)  Field            Description
--------    ------  -----            -----------
mEND-3      7:0     CRC32[31:24]     Checksum over all ASEP packet bytes 0 to
mEND-2      7:0     CRC32[23:16]     mEND-4, where mEND is the last byte index
mEND-1      7:0     CRC32[15:8]      of the entire ASEP packet; see 4.2.9
mEND        7:0     CRC32[7:0]
```

IMPLEMENTATION ASSUMPTION: The Pixelclk packet footer coverage "all ASEP packet bytes
0 to mEND-4" includes both the common header bytes (0..mHB), the Pixelclk stream
header byte (mHB+1), and the Pixelclk payload bytes (mHB+2..mHB+9). This differs
from the Video Line packet, which has separate header and payload CRCs.

---

## 11. PTB Timestamp Usage in Video ASEP

### 11.1 Presentation Timestamp (Table 7-7, Section 7.3.2.1, p236)

SPEC FACT (Section 7.4, p236): The common ASEP header bytes 2-5 carry PTBpresent
when PTB mode = 10. In Video ASEP context:

```
Byte  Bit(s)  Field              Description
----  ------  -----              -----------
2     7:0     PTBpresent[31:24]  Lower 32 bits of the PTBclk when the first payload
3     7:0     PTBpresent[23:16]  symbol of this ASEP packet is to be presented at
4     7:0     PTBpresent[15:8]   the application interface of the ASA node
5     7:0     PTBpresent[7:0]    containing the ASD
```

The presentation timestamp is the target delivery time for the first pixel of the
Video Line at the display or downstream processor. It allows synchronized multi-link
video delivery and display refresh scheduling.

### 11.2 Ingress Timestamp Mode for Video

SPEC FACT (Table 7-6, Section 7.3.2.1, p235): When PTB mode = 01 (ingress), bytes
2-5 carry PTBingress[31:0], the lower 32 bits of the PTBclk at the transmitting ASE
node, captured when the first payload symbol of the ASEP packet passed the
application interface.

For video, this corresponds to the capture time of the first pixel of the line at
the transmitting side.

### 11.3 PTB Mode Selection

```
PTB mode  Byte1[1:0]  mHB  Use case
--------  ----------  ---  --------
No TS     00          1    Low-latency; no synchronization required
Ingress   01          5    Capture timestamp; used for latency measurement
Present   10          5    Synchronized display delivery with deadline
User      11          5    Implementation-defined; 4-byte user timestamp
```

IMPLEMENTATION ASSUMPTION: For synchronized display applications (e.g., multi-screen
or audio-video sync), PTB presentation timestamp mode (10) is expected. For camera
capture applications where timing is to be measured, ingress mode (01) is more
appropriate. The choice is application- and system-level.

---

## 12. Usage of Format (Section 7.4.2, p240)

SPEC FACT (Section 7.4.2, p240): "this ASEP stream type is unidirectional."

SPEC FACT (Section 7.4.2, p240): "The vast majority of Video Data ASEP Packet types
to be transmitted are Video Line packets."

SPEC FACT (Section 7.4.2, p240): "It is recommended, that the Pixelclk Packet is
sent between two groups of Video Line Packets each representing a frame."

SPEC FACT (Section 7.4.2, p240): "It is at the discretion of the implementer, how
often a Pixelclk packet is required to keep the information up to date."

SPEC FACT (Section 7.4.2, p240): "An application may also not require the information
of the pixelclk packet."

### 12.1 Typical Frame Transmission Sequence

```
DLP_TX stream (one ASEP Video instance):

  ... [Pixelclk packet] ...           <- Optional; send between frames
  [Video Line 0: Vsync=1, Vend=0]     <- First line of frame with Vsync
  [Video Line 1: Vsync=0, Vend=0]     <- Active lines
  [Video Line 2: Vsync=0, Vend=0]
  ...
  [Video Line N-1: Vsync=0, Vend=1]   <- Last line of frame (Vend=1)
  [Pixelclk packet]                   <- Optional; recommended between frames
  [Video Line 0 of next frame: Vsync=1, Vend=0]
  ...
```

SPEC FACT (Table 7-9, p237): "Number of video lines with Vsync=1 shall match display
format, allowed any values for camera data."

SPEC FACT (Table 7-9, p237): Vend=1 on the last line of frame; Vend=0 on all
other lines.

### 12.2 Video Line Packet Composition Per Line

```
One video scan line (hdr type 001) ASEP packet structure:

  Common header (2 or 6 bytes):
    [stream_type=0x01 | follow=0] [PTB_mode=xx] [PTBpresent or PTBingress if mode!=00]

  Video Line header (10 bytes):
    [hdr_type=001|Vsync|Vend|Rsv|VS[3:2]] [VS[1:0]|VidLen[13:8]]
    [VidLen[7:0]] [PixFmt|PixDepth] [AlphaDepth|Rsv] [CRC32H 4 bytes]

  Payload (variable):
    Pixel data packed per Appendix B table for (PixFmt, PixDepth, AlphaDepth)
    Size = determined by VideoLength and pixel format
    For hdr type 001 or 100: VideoLength * 2 = pixel count

  Footer (4 bytes):
    [Payload CRC32 4 bytes]
```

---

## 13. TX Data Flow (ASE side)

### 13.1 TX Flow Diagram

```
Video source (camera / frame buffer)
        |
        | pixel_line[N] ready
        v
+--------------------+
| video_line_src     |
| (app interface)    |
| - Vsync status     |
| - Vend detection   |
| - Pixel format cfg |
+--------+-----------+
         |
         | DLP_TX.indicateSlot(size) from DLL
         v
+--------------------+
| ase_video_tx_ctrl  |
| TX FSM             |
| - Pending packet?  |
| - Determine type   |
|   (VideoLine/Pclk) |
+---+------------+---+
    |            |
no data       data available
    |            |
    v            v
DLP_TX.yield  +--------------------+
              | hdr_builder_video  |
              |                    |
              | Build m+1_HB:      |
              |  hdr_type[2:0]     |
              |  Vsync, Vend       |
              |  Video Stream[3:0] |
              |                    |
              | Build m+2_HB:      |
              |  VS[1:0]           |
              |  VideoLength[13:8] |
              |                    |
              | Build m+3_HB:      |
              |  VideoLength[7:0]  |
              |                    |
              | Build m+4_HB:      |
              |  PixFmt[3:0]       |
              |  PixDepth[3:0]     |
              |                    |
              | Build m+5_HB:      |
              |  AlphaDepth[1:0]   |
              |  Reserved=0        |
              +--------+-----------+
                       |
              +--------v-----------+
              | header_crc32       |
              |                    |
              | Compute CRC32 over |
              | bytes 0..mHB+5     |
              | Write m+6..m+9_HB  |
              +--------+-----------+
                       |
              +--------v-----------+
              | pixel_packer       |
              |                    |
              | Pack pixels per    |
              | Appendix B table   |
              | (PixFmt,PixDepth,  |
              |  AlphaDepth)       |
              | into payload bytes |
              | m+10_HB..mEND-4    |
              +--------+-----------+
                       |
              +--------v-----------+
              | payload_crc32      |
              |                    |
              | Compute CRC32 over |
              | bytes m+10_HB to   |
              | mEND-4             |
              | Write mEND-3..mEND |
              +--------+-----------+
                       |
                       v
              DLP_TX.dataUnit(ase_payload) -> Common framing -> DLL
```

### 13.2 Pixelclk TX Sub-flow

```
Pixelclk send decision (triggered by frame boundary or implementer policy):

  +---------------------------+
  | pixelclk_gen              |
  |                           |
  | Assemble m+1_HB:          |
  |   hdr_type[2:0] = 000     |
  |   Reserved[4:0] = 0       |
  |                           |
  | Assemble payload bytes:   |
  |   m+2_HB: frame_rate      |
  |   m+3_HB: lines[15:8]     |
  |   m+4_HB: lines[7:0]      |
  |   m+5_HB: rsv|ppl[13:8]   |
  |   m+6_HB: ppl[7:0]        |
  |   m+7_HB: h_backporch     |
  |   m+8_HB: hsync_width     |
  |   m+9_HB: h_frontporch|pol|
  |                           |
  | Compute footer CRC32 over |
  | bytes 0..mEND-4           |
  | Write mEND-3..mEND        |
  +---------------------------+
```

### 13.3 Container Size and Fragmentation

For each DLP_TX.indicateSlot(size), the video ASE must produce a payload of exactly
the indicated size. A single video line packet may be:
- Smaller than the container: handled by common framing with fragmentation code 10
  or 01 and dummy padding.
- Larger than the container: common framing splits across multiple containers using
  fragmentation codes 00 and 10/01.

SPEC FACT (Section 5.6.1.1.1, p185): Container size values include Up_P2P=208 bytes,
Dn_P2P=638 bytes (see also micro-architecture-asep-common-framing.md Section 12.3).

A 4K (3840x2160) RGB 8-bit line has 3840 * 3 = 11520 payload bytes. This requires
multiple Dn_P2P containers per line. Upstream video (leaf->root) faces severe size
constraints (Up_P2P=208 bytes) and may require very short lines or sub-line slicing.

IMPLEMENTATION ASSUMPTION: The video ASE does not slice a single pixel line across
multiple ASEP packets. Each ASEP Video Line packet contains exactly one complete
scan line. Fragmentation across multiple DLL containers is handled transparently by
the common framing layer. The VideoLength field in the header describes the entire
line.

---

## 14. RX Data Flow (ASD side)

### 14.1 RX Flow Diagram

```
DLP_RX.dataUnit from DLL -> Common framing reassembly
        |
        | Reassembled ASEP packet bytes mHB+1..mEND
        v
+--------------------+
| asd_video_rx_ctrl  |
| RX dispatch        |
| Parse m+1_HB[7:5]  |
| = hdr_type         |
+---+--------+-------+
    |        |
  000       001/010/011/100
  Pixelclk  Video Line
    |        |
    v        v
+----------+ +-----------------------+
| pclk_    | | video_line_parser     |
| parser   | |                       |
|          | | Parse m+1_HB:         |
| Parse    | |  hdr_type, Vsync      |
| payload  | |  Vend, VS[3:2]        |
| bytes    | |                       |
| m+2..m+9 | | Parse m+2_HB:         |
|          | |  VS[1:0]              |
| Validate | |  VidLen[13:8]         |
| footer   | |                       |
| CRC32    | | Parse m+3_HB:         |
|          | |  VidLen[7:0]          |
| Output:  | |                       |
|  fps     | | Parse m+4_HB:         |
|  lines   | |  PixFmt, PixDepth     |
|  ppl     | |                       |
|  blanking| | Parse m+5_HB:         |
|  params  | |  AlphaDepth           |
+----------+ |                       |
             | Verify header CRC32   |
             | over bytes 0..mHB+5   |
             | Error -> err_cnt++    |
             |                       |
             | Verify payload CRC32  |
             | over bytes mHB+10..   |
             | mEND-4                |
             | Error -> 3.7.1++      |
             |                       |
             | Select Appendix B     |
             | unpack table for      |
             | (PixFmt,PixDepth,Alpha)|
             |                       |
             | Unpack pixels from    |
             | payload bytes         |
             | mHB+10..mEND-4        |
             |                       |
             | Output:               |
             |  Vsync, Vend          |
             |  pixel_stream[N]      |
             |  PTBpresent if valid  |
             +-----------------------+
                       |
                       v
              Video sink application
```

### 14.2 CRC Error Handling

SPEC FACT (Section 7.3.3, p236): "If the ASEP format does employ a CRC check, the
ASD shall check the consistency of the data after reassembly of the received fragments
and shall indicate an error by incrementing 3.7.1."

The Video Line packet has two CRC fields. IMPLEMENTATION ASSUMPTION: Both header CRC
and payload CRC must be verified. A header CRC failure should prevent parsing of the
pixel format/depth fields (since they may be corrupt) and the entire line should be
discarded. A payload CRC failure on an otherwise valid header means the pixel data is
corrupted; the line is discarded.

---

## 15. Interface to ASEP Common Framing

### 15.1 TX Interface

The video ASE sits above the common framing layer. The division of responsibility:

```
Common framing provides to Video ASE (TX):
  - DLP_TX.indicateSlot(size): trigger to build a container payload
  - mHB value: first stream-specific byte index = mHB+1
  - Available payload bytes: size - (Byte0/Byte1 overhead) - (mHB+1) bytes

Video ASE provides to Common framing (TX):
  - stream_type = 0x01 (fixed, loaded in Byte0[7:1])
  - follow_flag = 0 (Video Lines are not typically packed back-to-back)
  - ptb_mode[1:0]: selected per configuration (00, 01, 10, or 11)
  - PTBpresent[31:0] or PTBingress[31:0]: for Bytes 2-5 if ptb_mode != 00
  - Assembled ASEP packet bytes starting at mHB+1
```

### 15.2 RX Interface

```
Common framing provides to Video ASD (RX):
  - Reassembled ASEP packet bytes starting at mHB+1
  - ptb_mode[1:0] (from common header Byte1[1:0])
  - PTBpresent[31:0] or PTBingress[31:0] (from bytes 2-5 if ptb_mode != 00)
  - Packet reassembly status (complete / CRC fail at DLL level)

Video ASD provides to application:
  - Pixel stream
  - Vsync, Vend flags
  - Video Stream indicator [3:0]
  - Pixelclk parameters (fps, lines, ppl, blanking)
  - PTBpresent[31:0] for display scheduling
```

### 15.3 Interface Table

Primitive / Signal         | Direction          | Description
-------------------------- | ------------------ | -----------
DLP_TX.indicateSlot(size)  | DLL -> common -> ASE | Trigger container assembly
DLP_TX.dataUnit(payload)   | ASE -> common -> DLL | Return assembled payload bytes
DLP_TX.yield()             | ASE -> common -> DLL | No data available
DLP_RX.dataUnit(...)       | DLL -> common -> ASD | Deliver reassembled packet
ptb_clk_lower32[31:0]      | PTB service -> ASE   | Current PTBclk[31:0]
ptb_clk_valid              | PTB service -> ASE   | PTB locked and valid
pres_ts[31:0]              | App/scheduler -> ASE | Presentation deadline (if mode=10)
pixel_line_in[N]           | Video source -> ASE  | Pixel data for current line
vsync_in                   | Video source -> ASE  | Vsync signal
vend_in                    | Video source -> ASE  | Frame-end signal
pixel_line_out[N]          | ASD -> Video sink    | Reconstructed pixel data
vsync_out                  | ASD -> Video sink    | Recovered Vsync
vend_out                   | ASD -> Video sink    | Recovered frame-end
pclk_out.*                 | ASD -> Video sink    | Recovered Pixelclk parameters
ptb_present_out[31:0]      | ASD -> Video sink    | Presentation timestamp from header

---

## 16. RTL Submodule Architecture

### 16.1 Top-Level Block Diagram

```
+===============================================================+
|                  asep_video_top                               |
|                                                               |
|   TX PATH                                                     |
|   +------------------+      +---------------------------+     |
|   | ase_video_tx_ctrl|      | pclk_assembler            |     |
|   | (TX FSM)         |      |                           |     |
|   |                  |      | Frame rate encode (8-bit) |     |
|   | State:           |      | Lines[15:0] split         |     |
|   |  IDLE            |      | PPL[13:0] split           |     |
|   |  WAIT_SLOT       |      | H-BP[7:0] uint8           |     |
|   |  SENDING_LINE    |      | Hsync[7:0] uint8          |     |
|   |  SENDING_PCLK    |      | H-FP[6:0] + pol           |     |
|   |                  |      +---------------------------+     |
|   +--+---------------+                                        |
|      |                                                        |
|   +--v---------------+      +---------------------------+     |
|   | vline_hdr_builder|      | pixel_packer              |     |
|   |                  |      |                           |     |
|   | hdr_type [2:0]   |      | Appendix B format table   |     |
|   | Vsync / Vend     |      | selector                  |     |
|   | Video Stream[3:0]|      | Pixel bit-pack engine     |     |
|   | VideoLength[13:0]|      | (format x depth matrix)   |     |
|   | PixFmt[3:0]      |      +---------------------------+     |
|   | PixDepth[3:0]    |                                        |
|   | AlphaDepth[1:0]  |      +---------------------------+     |
|   +--+---------------+      | crc32_engine              |     |
|      |                      |                           |     |
|   +--v-------------------+  | Poly: 0xF4ACFB13          |     |
|   | header_crc32_calc    |  | Init: 0xFFFFFFFF          |     |
|   | covers bytes 0..mHB+5|  | Final XOR: 0xFFFFFFFF     |     |
|   | output: bytes mHB+6.9|  | Input/output reflected    |     |
|   +--+-------------------+  +--+------------------------+     |
|      |                         |                              |
|   +--v-----------------------+-v-+                            |
|   |   payload_crc32_calc         |                            |
|   |   covers bytes mHB+10..mEND-4|                            |
|   |   output: bytes mEND-3..mEND |                            |
|   +------------------------------+                            |
|      |                                                        |
|   DLP_TX.dataUnit(payload) to common framing                  |
|                                                               |
|   RX PATH                                                     |
|   DLP_RX from common framing -> reassembled pkt bytes         |
|      |                                                        |
|   +--v---------------+                                        |
|   | asd_video_rx_ctrl|                                        |
|   | (RX dispatch FSM)|                                        |
|   | Parse m+1[7:5]   |                                        |
|   | Route to vline   |                                        |
|   | or pclk path     |                                        |
|   +--+----------+----+                                        |
|      |          |                                             |
|   +--v------+ +-v-----------------+                           |
|   | pclk_   | | vline_hdr_parser  |                           |
|   | parser  | |                   |                           |
|   |         | | hdr_type / Vsync  |                           |
|   | Decode  | | Vend / VS[3:0]    |                           |
|   | fps mode| | VideoLength[13:0] |                           |
|   | Parse   | | PixFmt / PixDepth |                           |
|   | lines / | | AlphaDepth        |                           |
|   | ppl /   | +--+----------------+                           |
|   | blanking|    |                                            |
|   |         | +--v----------------+                           |
|   | Verify  | | hdr_crc32_check   |                           |
|   | footer  | | covers 0..mHB+5   |                           |
|   | CRC32   | | error -> err_cnt  |                           |
|   +----+----+ +--+----------------+                           |
|        |         |                                            |
|        |      +--v----------------+                           |
|        |      | pixel_unpacker    |                           |
|        |      | Appendix B table  |                           |
|        |      | selector and      |                           |
|        |      | unpack engine     |                           |
|        |      +--+----------------+                           |
|        |         |                                            |
|        |      +--v----------------+                           |
|        |      | payload_crc_check |                           |
|        |      | covers mHB+10..   |                           |
|        |      | mEND-4            |                           |
|        |      | error -> 3.7.1    |                           |
|        |      +--+----------------+                           |
|        |         |                                            |
|   +----|---------|--+                                         |
|   | output_stage    |                                         |
|   | pixel_line_out  |                                         |
|   | vsync / vend    |                                         |
|   | ptb_present_out |                                         |
|   | pclk_params_out |                                         |
|   +-----------------+                                         |
|                                                               |
+===============================================================+
```

### 16.2 Module Descriptions

Module               | Function                                          | Notes
-------------------- | ------------------------------------------------- | -----
ase_video_tx_ctrl    | TX top FSM: arbitrates VideoLine vs Pixelclk send; handles yield | Per DLP_TX port
vline_hdr_builder    | Builds Video Line stream-specific header bytes mHB+1..mHB+5 | Configurable per line
header_crc32_calc    | CRC32 over bytes 0..mHB+5; produces 4-byte header CRC | Uses shared crc32_engine
pclk_assembler       | Builds Pixelclk packet payload bytes mHB+2..mHB+9; encodes frame rate | Triggered at frame boundary
pixel_packer         | Packs application pixel data into Appendix B byte layout | 49-table matrix; all formats and depths
payload_crc32_calc   | CRC32 over payload bytes mHB+10..mEND-4; produces 4-byte payload CRC | Uses shared crc32_engine
crc32_engine         | Shared CRC32 core: poly=0xF4ACFB13, init=0xFFFFFFFF, XOR=0xFFFFFFFF, reflected | One instance, time-shared or pipelined
asd_video_rx_ctrl    | RX dispatch FSM: routes by hdr_type[2:0] to video line or pixelclk path | Per DLP_RX port
vline_hdr_parser     | Parses Video Line header fields from bytes mHB+1..mHB+5 | Output: PixFmt, PixDepth, VideoLength, Vsync, Vend
hdr_crc32_check      | Verifies header CRC over bytes 0..mHB+5; increments header error counter on fail | Fast-reject corrupt headers
pclk_parser          | Decodes Pixelclk payload; expands frame rate code to fps value | Stores pclk parameters in register shadow
pixel_unpacker       | Unpacks payload bytes per Appendix B table selected by (PixFmt, PixDepth, AlphaDepth) | Mirror of pixel_packer
payload_crc_check    | Verifies payload CRC; on fail increments register 3.7.1 | Must operate after full reassembly

---

## 17. Register Interface

No stream-specific registers are defined in the ASA specification for the Video ASEP
beyond the common ASEP registers inherited from micro-architecture-asep-common-framing.

### 17.1 Inherited Common ASEP Registers

Register        | Address          | Access  | Description
--------------- | ---------------- | ------- | -----------
fullPacketID[47:0] | 4/5.i.0001-0003 | RO O RID | 48-bit packet counter; lower 5 bits in container header
streamType      | 4/5.i.0004[6:0]  | RO O RID | Stream type = 0x01 for Video Data (fixed)
streamVendorID  | 4/5.i.0005       | RO O RID | Vendor-defined stream identifier
ASEP Test       | 4/5.i.0006[0]    | RW L     | Test mode enable; L-only, not OAM accessible
ASD Status      | 5.i.0100         | RO O     | ASD-specific status (payload errors, etc.)
ASD Watchdog    | 5.i.0101         | RW O     | ASD watchdog / data timeout
ASD Status2     | 5.i.0102         | RO O     | Extended ASD status

### 17.2 Error Counter

SPEC FACT (Section 7.3.3, p236): Register 3.7.1 is incremented by the ASD on
reassembly CRC errors.

IMPLEMENTATION ASSUMPTION: The payload CRC32 error on a Video Line packet increments
register 3.7.1. A header CRC32 error on the same packet should also increment a
related error counter; the exact register assignment for header-only CRC errors is
not explicitly stated in the spec for Section 7.4.

---

## 18. Video Line Packet Size Computation

### 18.1 Payload Size

For hdr_type = 001 or 100 (video data or null):
  VideoLength * 2 = pixel count (including blanking pixels)

The number of bytes in the payload depends on the pixel format and depth.
Each Appendix B table defines bytes-per-pixel-group. General formula:

```
  Let P = VideoLength * 2   (pixel count)
  Let bytes_per_pixel = f(PixFmt, PixDepth, AlphaDepth)
    (from Appendix B; varies by format: e.g., RGB 8-bit = 3 bytes per pixel,
     YUV422 8-bit = 2 bytes per chroma pair, RAW 32-bit = 4 bytes per pixel)

  payload_bytes = P * bytes_per_pixel (may not be integer; Appendix B tables
    define exact grouping that yields integer byte counts)
```

IMPLEMENTATION ASSUMPTION: The VideoLength field encodes pixel count / 2 as an
unsigned integer. Thus VideoLength is always a whole number (pixel counts are
always even). For YUV422 (two pixels per chroma group) and YUV411 (four pixels per
chroma group), the VideoLength value and the pixel count relationship from the spec
ensures the grouping works out to whole bytes.

### 18.2 Total ASEP Packet Size (Video Line)

```
  Total = (mHB + 1)         <- common header: 2 bytes (no TS) or 6 bytes (with TS)
        + 10                <- stream-specific header (Table 7-9) + header CRC32
        + payload_bytes     <- pixel payload
        + 4                 <- footer CRC32 (Table 7-10)

  Example: RGB 8-bit, 1920 active pixels + 80 blanking = 2000 pixels, no TS:
    mHB = 1  (no timestamp)
    header   = 2 + 10 = 12 bytes
    payload  = 2000 * 3 = 6000 bytes
    footer   = 4 bytes
    total    = 6016 bytes (spans ~10 x Dn_P2P containers at 638 bytes each)
```

---

## 19. Spec Facts vs Implementation Assumptions

### 19.1 Spec Facts

No.  | Spec Fact                                                           | Source
---- | ------------------------------------------------------------------- | ------
SF-1 | ASEP stream type 0x01 = Video Data                                  | Table 7-1, p233
SF-2 | Video Data ASEP is unidirectional                                   | Section 7.4.2, p240
SF-3 | Packet type field is bits 7:5 of byte m+1_HB                        | Table 7-8, p236
SF-4 | 000=Pixelclk, 001=Video data, 010=Format specific, 011=Vendor, 100=Null | Table 7-8, p236
SF-5 | Vsync=1: vertical sync active for line; display must match format   | Table 7-9, p237
SF-6 | Vend=1: last line of frame                                          | Table 7-9, p237
SF-7 | Video Stream [3:0] split across bits [1:0] of m+1_HB and [7:6] of m+2_HB | Table 7-9, p237
SF-8 | VideoLength [13:0] = 14-bit unsigned integer                        | Table 7-9, p237
SF-9 | For hdr type 001 or 100: VideoLength*2 = pixel count (blanking included) | Table 7-9, p237
SF-10| For hdr type 010 or 011: VideoLength = payload length in bytes      | Table 7-9, p237
SF-11| Pixel data format field [7:4] of m+4_HB: 0000=RAW..0110=YUV411     | Table 7-9, p237
SF-12| Pixel bit depth field [3:0] of m+4_HB: 0000=8bit..1000=32bit       | Table 7-9, p237
SF-13| Bit depths 0101(20), 0110(24), 0111(28), 1000(32) are RAW-only      | Table 7-9, p237
SF-14| Pixel alpha depth [7:6] of m+5_HB: 00=none, 01=1bit, 10=8bit, 11=color width | Table 7-9, p237
SF-15| Header CRC32 covers bytes 0 to m+5_HB; polynomial per 4.2.9        | Table 7-9, p237-238
SF-16| Payload CRC32 covers bytes m+10_HB to mEND-4                       | Table 7-10, p238
SF-17| Pixelclk header: bits 7:5 = 000; bits 4:0 = reserved (set to 0)    | Table 7-11, p238
SF-18| Frame rate byte bit 7 = 1: use predefined code in bits [6:0]        | Table 7-12, p238
SF-19| Frame rate byte bit 7 = 0: bits [6:0] = frame rate in Hz (direct)  | Table 7-12, p238
SF-20| Predefined codes: 0x00=23.976, 0x01=24, 0x02=25 ... 0x0F=300 fps   | Table 7-12, p239
SF-21| Lines[15:0] = total lines including blanking (2 bytes, bytes m+3..m+4_HB) | Table 7-12, p239
SF-22| Pixels per line [13:0] = total pixels in multiples of 2; blanking included | Table 7-12, p239
SF-23| H-BackPorch = uint8 (byte m+7_HB)                                  | Table 7-12, p239
SF-24| Hsync = uint8 (byte m+8_HB)                                        | Table 7-12, p239
SF-25| H-FrontPorch = unsigned 7-bit integer in bits [7:1] of m+9_HB      | Table 7-12, p240
SF-26| Hsync-Polarity = bit 0 of m+9_HB                                   | Table 7-12, p240
SF-27| H-BackPorch + H-FrontPorch + Hsync = horiz blanking for display formats | Table 7-12, p239-240
SF-28| Camera data: blanking parameters may be arbitrary                   | Table 7-12, p239-240
SF-29| Pixelclk recommended between two frame groups of Video Line packets | Section 7.4.2, p240
SF-30| Pixelclk send frequency is implementer-discretion                   | Section 7.4.2, p240
SF-31| Appendix B tables II-1 through II-49 are NORMATIVE                  | Appendix B, p305-337
SF-32| CRC32 polynomial: 0xF4ACFB13; init: 0xFFFFFFFF; XOR: 0xFFFFFFFF; reflected | Section 4.2.9, p120

### 19.2 Implementation Assumptions

No.  | Assumption                                                          | Rationale
---- | ------------------------------------------------------------------- | ---------
IA-1 | Header CRC32 covers common header (0..mHB) and first 6 stream bytes (mHB+1..mHB+5); 4-byte CRC at mHB+6..mHB+9 | Table 7-9 byte-by-byte layout interpretation
IA-2 | Payload CRC32 footer covers bytes from mHB+10 to mEND-4 (the pixel payload only) | Table 7-10 explicit range
IA-3 | Video Line packet contains exactly one complete scan line; no ASEP-level pixel slicing | Implied by VideoLength semantics
IA-4 | Follow flag is not set for Video Line packets in typical operation; one line per ASEP packet | Video lines are large; packing multiple per container impractical
IA-5 | Pixelclk total packet CRC covers bytes 0..mEND-4 (entire packet including common header) | By analogy with other ASEP types; spec says "all ASEP packet bytes 0 to mEND-4" for Pixelclk footer
IA-6 | Reserved bits in Video Line header (m+5_HB[5:0], m+1_HB[2]) are set to 0 on TX and silently ignored on RX | Standard ASA reserved field behavior
IA-7 | For unsupported pixel format+depth combinations (e.g., 20-bit non-RAW), RX should discard the line and increment error counter | No spec-defined handling; discard is safest
IA-8 | Hsync-Polarity encoding: 0=active low, 1=active high (not specified in spec text) | Common video interface convention; VERIFY
IA-9 | Video Stream [3:0] = 0 for single-stream configurations; used to distinguish stereo, multi-view, etc. | Field is unsigned integer; semantics are application-defined
IA-10| When PTB is not locked and presentation TS mode is selected, bytes 2-5 are filled with 0x00000000 | From common framing doc assumption; video may need a different fallback
IA-11| The pixel_packer and pixel_unpacker must implement all 49 Appendix B tables to be compliant | Appendix B is normative; omitting tables would be non-compliant

---

## 20. Verification Plan

### 20.1 Video Line Header Encoding

Test  | Stimulus                                         | Expected Response
----- | ------------------------------------------------ | -----------------
VV-1  | hdr_type = 001, Vsync=1, Vend=0                 | m+1_HB[7:5]=001, bit4=1, bit3=0
VV-2  | hdr_type = 001, Vsync=0, Vend=1 (last line)     | m+1_HB[7:5]=001, bit4=0, bit3=1
VV-3  | VideoLength=960 (1920 pixels)                    | m+2_HB[5:0]=0b001111, m+3_HB=0b11000000
VV-4  | Video Stream [3:0] = 0xA (1010)                 | m+1_HB[1:0]=10, m+2_HB[7:6]=10
VV-5  | PixFmt=0001(RGB), PixDepth=0010(12bit)          | m+4_HB = 0x12
VV-6  | AlphaDepth=10 (8-bit alpha)                     | m+5_HB[7:6] = 10
VV-7  | Reserved field m+1_HB[2] transmitted as 0       | bit2 = 0 always
VV-8  | Reserved field m+5_HB[5:0] transmitted as 0     | bits 5:0 = 0 always
VV-9  | Header CRC32 correctness (golden pattern)        | CRC over bytes 0..mHB+5 matches reference
VV-10 | hdr_type = 100 (null), Vsync=0, Vend=0          | m+1_HB[7:5]=100; payload still VideoLength*2

### 20.2 Pixel Packing / Unpacking (Appendix B Compliance)

Test  | Stimulus                                         | Expected Response
----- | ------------------------------------------------ | -----------------
VPP-1 | RGB 8-bit: 3 pixels [R0G0B0, R1G1B1, R2G2B2]   | 9 payload bytes as per Table II-2
VPP-2 | YUV422 8-bit: 2-pixel chroma pair               | 4 bytes per pair per Table II-31
VPP-3 | RAW 32-bit: pixel value 0xDEADBEEF              | 4 bytes: 0xEF,0xBE,0xAD,0xDE (LE per Table II-49)
VPP-4 | RGB 10-bit: pack 3 pixels into bytes             | Verify exact bit positions per Table II-3
VPP-5 | YUV444 12-bit: Y,U,V all 12-bit                 | Verify byte packing per Table II-28
VPP-6 | RGBa 8bit,1bit: alpha occupies 1 bit             | Verify packing per Table II-7
VPP-7 | RGBa 16bit,16bit: alpha = color depth            | Verify AlphaDepth field = 11; packing per Table II-20
VPP-8 | Roundtrip: pack then unpack for all 49 formats  | Output matches input for each Appendix B table

### 20.3 Pixelclk Packet

Test  | Stimulus                                         | Expected Response
----- | ------------------------------------------------ | -----------------
VPC-1 | fps code = 0x88 (bit7=1, [6:0]=0x08 -> 60fps)  | m+2_HB = 0x88; decoded value = 60.00 fps
VPC-2 | fps code = 0x83 (bit7=1, [6:0]=0x03 -> 29.97)  | m+2_HB = 0x83; decoded value = 29.97 fps
VPC-3 | fps direct = 0x1E (bit7=0, [6:0]=30 -> 30Hz)   | m+2_HB = 0x1E; decoded value = 30 fps
VPC-4 | Lines = 1125 (1080p total)                      | m+3_HB = 0x04, m+4_HB = 0x65
VPC-5 | Pixels per line = 2200 (1080p total)            | m+5_HB[5:0]=0x08, m+6_HB=0x98
VPC-6 | H-BP=148, Hsync=44, H-FP=88 (1080p CEA-861)   | Sum = 280 = blanking pixels (2200-1920)
VPC-7 | Camera mode: H-BP=0, Hsync=0, H-FP=0           | Values passed through unchanged; no constraint enforced
VPC-8 | Pixelclk footer CRC covers entire packet        | Verify CRC over bytes 0..mEND-4

### 20.4 PTB Timestamp in Video Context

Test  | Stimulus                                         | Expected Response
----- | ------------------------------------------------ | -----------------
VPT-1 | PTB mode=10, presentation TS = 0x12345678       | Bytes 2-5 of common header = 0x12,0x34,0x56,0x78
VPT-2 | PTB mode=01, ingress capture at pixel-line start | Bytes 2-5 = captured PTBclk[31:0] big-endian
VPT-3 | PTB mode=00, no timestamp                       | mHB=1; bytes 2-5 absent; stream hdr at byte 2

### 20.5 CRC Error Handling

Test  | Stimulus                                         | Expected Response
----- | ------------------------------------------------ | -----------------
VCE-1 | Corrupt one bit in header CRC field             | ASD detects CRC mismatch; line discarded; error count++
VCE-2 | Corrupt one payload byte (pixel data)           | Payload CRC fails; register 3.7.1 incremented
VCE-3 | Both CRCs corrupt                               | Both errors flagged; line discarded

### 20.6 Vsync and Vend Sequencing

Test  | Stimulus                                         | Expected Response
----- | ------------------------------------------------ | -----------------
VVS-1 | N lines per frame, Vsync=1 on first line        | Sink sees Vsync=1 exactly on first line of frame
VVS-2 | Vend=1 on last line of frame                    | Sink sees Vend=1 exactly once per frame
VVS-3 | Missing Vend (line count error)                 | Sink can detect missing frame boundary; watchdog fires

---

## 21. Missing / Needs Verification

1. HSYNC-POLARITY encoding: Spec Table 7-12 (p240) defines Hsync-Polarity as bit 0
   of byte m+9_HB but does not specify the encoding (0=active low vs 1=active high
   or vice versa). VERIFY whether the spec defines the polarity encoding elsewhere
   (e.g., in a display format reference or companion document) or whether it is
   left entirely to the implementer. This affects interoperability for display sinks.

2. Multiple Vsync=1 lines: Spec Table 7-9 (p237) states "Number of video lines with
   Vsync=1 shall match display format." Some display formats (e.g., interlaced) have
   multiple Vsync lines per frame. VERIFY whether the spec clarifies the exact Vsync
   line count for different display standards, or whether compliance is left to the
   application layer.

3. Pixelclk footer CRC coverage: The Pixelclk footer text (Section 7.4.1.2, p240) is
   truncated in the structured extraction after "Footer (last four bytes):" with no
   explicit table text captured. The coverage range for the Pixelclk footer CRC is
   inferred by analogy with the Video Line footer definition and the general ASEP
   footer pattern ("all ASEP packet bytes 0 to mEND-4"). VERIFY against the original
   PDF pages 238-240 to confirm the Pixelclk footer CRC coverage exactly.

4. H-FrontPorch bit width: Spec Table 7-12 defines H-FrontPorch in bits 7:1 of
   byte m+9_HB, giving 7 bits (range 0-127 pixels). Standard 1080p CEA-861 requires
   H-FP=88 pixels, which fits. 4K/UHD timing (H-FP=176 for some formats) exceeds
   7 bits (max 127). VERIFY whether this is a known limitation of the spec, or
   whether the field is actually defined differently (e.g., in units other than
   single pixels, or combined with another field).

5. Pixel format valid combinations: The spec defines PixFmt and PixDepth fields
   independently, but some combinations are invalid (e.g., YUV422 with 20-bit depth
   has no Appendix B table; only RAW supports depths above 16 bits). VERIFY whether
   the spec explicitly forbids invalid combinations or relies on Appendix B absence
   as the implicit prohibition.

6. Video Stream field semantics: The 4-bit Video Stream indicator field [3:0] is
   defined as an unsigned integer in Table 7-9, but its application semantics (stream
   multiplexing, stereo pair identification, multi-view coding) are not defined in
   Section 7.4. VERIFY whether another section of the spec or an application note
   defines the Video Stream numbering convention.

7. Format-specific and vendor/user data types (hdr_type 010, 011): The spec defines
   these types in Table 7-8 and notes "VideoLength is in bytes" in Table 7-9, but
   provides no payload format definition. VERIFY whether these are truly
   implementation-defined or whether another part of the spec (or a future version)
   will define their content.

8. Null data type (hdr_type 100) pixel count constraint: hdr_type=100 (null data)
   uses VideoLength*2=pixel count but the payload is null/dummy. VERIFY whether the
   ASD must produce a null pixel output for null lines or simply discard them, and
   whether a null line contributes to the Vsync/Vend line count.

9. Appendix B table completeness for RGBa: The spec defines RGBa combinations with
   alpha depths 1-bit, 8-bit, and identical-to-color. The Pixel alpha depth field
   encoding 11 ("identical to color bit width") combined with various color depths
   yields 5 RGBa tables (8+8, 10+10, 12+12, 14+14, 16+16 from Tables II-11, II-14,
   II-17, II-20). VERIFY that there is no Appendix B table for 8+1bit as Table II-7
   vs 8+8bit as Table II-8 -- ensure RTL correctly maps alpha_depth encoding to the
   right Appendix B table selector for each combination.

10. PTB presentation timestamp deadline computation: Section 7.3.2.1 defines the
    presentation timestamp format but does not specify how the Video ASE computes the
    target presentation PTBclk value. For synchronized display, the deadline is
    frame-rate-driven (1/fps interval). VERIFY whether the spec or a companion
    document defines the algorithm for computing PTBpresent for video lines, or
    whether it is left fully to the implementer.

---

## 22. Summary

The ASEP Video module (stream type 0x01) encapsulates raw video scan lines and pixel
clock metadata into ASEP packets for unidirectional transport over an ASA link. Its
key elements are:

1. Packet Type Selector (Table 7-8): A 3-bit field in the first stream-specific
   header byte distinguishes Pixelclk (000), Video Line data (001), format-specific
   (010), vendor/user (011), and null (100) packets.

2. Video Line Header (Table 7-9): A 10-byte stream-specific header (following the
   common ASEP header) carries Vsync and Vend flags, a 4-bit Video Stream indicator,
   a 14-bit VideoLength count, a 4-bit pixel data format code (RAW/RGB/RGBa/RGBW/
   YUV444/YUV422/YUV411), a 4-bit pixel bit depth code (8-32 bit), a 2-bit alpha
   depth code, and a 4-byte CRC32 over the header bytes.

3. Video Line Payload (Appendix B, NORMATIVE): The pixel payload layout is fully
   defined by 49 normative tables (II-1 through II-49) covering all supported pixel
   format and bit depth combinations. A separate 4-byte payload CRC32 (Table 7-10)
   protects the pixel data.

4. Pixelclk Packet (Tables 7-11, 7-12): A metadata packet with 1-byte stream header
   and 8-byte payload carrying frame rate (coded or direct integer), total lines
   including blanking (16-bit), pixels per line (14-bit, multiples of 2), H-BackPorch
   (uint8), Hsync width (uint8), H-FrontPorch (7-bit), and Hsync-Polarity. A single
   footer CRC32 covers the entire Pixelclk packet.

5. PTB Timestamps: The common ASEP header supports ingress (mode 01) or presentation
   (mode 10) timestamps in bytes 2-5. For video delivery to synchronized displays,
   presentation timestamp mode is expected; for camera capture latency measurement,
   ingress mode is used.

6. Unidirectional flow: The Video ASEP is transmit-only from the video source node.
   The vast majority of packets are Video Line (hdr_type 001). Pixelclk packets are
   sent at implementer discretion, typically between frames.
