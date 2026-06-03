---
{
  "section": "III.a",
  "section_title": "I2C Point-to-Point Tunneling Topologies",
  "module": "Appendices",
  "depth": 2,
  "page_start": 338,
  "page_end": 339,
  "content_type": "figure",
  "register_address": null,
  "tables": [],
  "figures": [
    {
      "id": "III-1",
      "title": "I2C ASEP point-to-point tunneling–Scenario 1"
    },
    {
      "id": "III-2",
      "title": "I2C ASEP point-to-point tunneling–Scenario 2"
    }
  ],
  "source": "ASA_Technical_Specification_ver2.0.pdf"
}
---

# III.a I2C Point-to-Point Tunneling Topologies

III.a I2C Point-to-Point Tunneling Topologies
ASEP connections are quasi-statically routed between ASA nodes on the same ASA branch.
ECU | Display
I2C SLb
IC node3 | node4 IC
n
ASE ASA | ASA ASE A
I2C MA.ii | Ln
S | M
C | TRX | TRX | C | I2C SLc
IC | IC
I2 | I2
ASD | ASD
node2 | node5
ASA | ASA
I2C SLa
TRX | TRX
ECU | node6
node1 | IC
IC
n | I2C SLd
ASA ASE A
ASE ASA
Ln
S | M
I2C MA.i | TRX IC
C IC TRX | C
I2 | I2 | I2C SLe
ASD
ASD
Display
Figure III-1: I2C ASEP point-to-point tunneling–Scenario 1
ASEP connections can be rerouted on the same topology through DLL configuration.
ECU | Display
I2C SLb
node3 | node4
IC | IC
n
A
ASE ASA | ASA ASE
I2C MA.ii | Ln
S | M
C | TRX | TRX | C
IC | IC | I2C SLc
I2 | I2
ASD | ASD
node2 | node5
ASA | ASA
I2C SLa
TRX | TRX
ECU | node6 IC
IC node1
n | I2C SLd
ASA ASE A
ASE ASA
Ln
S | TRX | M
I2C MA.i | C | TRX | IC C
IC
I2 | I2 | I2C SLe
ASD
ASD
Display
Figure III-2: I2C ASEP point-to-point tunneling–Scenario 2
