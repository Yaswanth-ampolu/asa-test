---
{
  "section": "III.b",
  "section_title": "Possibility for Connection to I2C Slaves at more than one ASA Device",
  "module": "Appendices",
  "depth": 2,
  "page_start": 339,
  "page_end": 339,
  "content_type": "figure",
  "register_address": null,
  "tables": [],
  "figures": [
    {
      "id": "III-3",
      "title": "I2C ASEP point-to-point tunneling–Scenario 3"
    },
    {
      "id": "III-4",
      "title": "I2C ASEP point-to-point tunneling–Scenario 4"
    }
  ],
  "source": "ASA_Technical_Specification_ver2.0.pdf"
}
---

# III.b Possibility for Connection to I2C Slaves at more than one ASA Device

III.b Possibility for Connection to I2C Slaves at more than one ASA Device
One I2C Master can communicate to I2C Slaves behind more than one ASA leaf/branch device
through the establishment of more than one I2C ASEP point-2-point tunnel, where the tunnels are
managed by an implementation-specific layer (shown in yellow).
ECU | Display
I2C SLb
IC node3 | node4 IC
n
A
ASE | ASA ASE
I2C MA.ii
M
TRX | C | I2C SLc
IC | IC
I2
ASD ASA | ASD
Ln
S
C | TRX | node5
IC
I2
ASE | ASA
IC | TRX
ASD
node6 IC
n | I2C SLd
ASA ASE A
M
TRX IC
C
I2 | I2C SLe
ASD
Display
Figure III-3: I2C ASEP point-to-point tunneling–Scenario 3
ECU | Camera
I2C SLb
IC node3 | node4 IC
n
ASE ASA | ASA ASE A
I2C MA.ii
M
TRX | TRX | C | I2C SLc
IC | IC
I2
ASD | ASD
Ln
S
C | node2
IC
I2
ASE ASA
node5 IC
IC TRX | n | I2C SLd
ASA ASE
ASD
MA
TRX IC
C
I2 | I2C SLe
ASD
Camera
Figure III-4: I2C ASEP point-to-point tunneling–Scenario 4
