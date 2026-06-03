---
{
  "section": "III.c",
  "section_title": "Possibility for Multi-Master I2C Functionality",
  "module": "Appendices",
  "depth": 2,
  "page_start": 339,
  "page_end": 341,
  "content_type": "figure",
  "register_address": null,
  "tables": [],
  "figures": [
    {
      "id": "III-5",
      "title": "I2C Multi-Master scenario"
    }
  ],
  "source": "ASA_Technical_Specification_ver2.0.pdf"
}
---

# III.c Possibility for Multi-Master I2C Functionality

III.c Possibility for Multi-Master I2C Functionality
I2C Multi-Master functionally can be used on every local I2C by standard I2C Arbitration. The use
case of I2C debuggers connectable to an I2C bus anywhere on the ASA branch can also be enabled by
this feature in conjunction with MA and SL being implemented on the same ASA device (MA/SLn3,
MA/SLn4 and MA/SLn6 below).
IC debugger #1 | IC debugger #2
I2C MA.iii | I2C MA.iv
ECU | Display
IC | IC | I2C SLb
n3 | node#3 | node#4 | n4
ASE | ASE L
SL | /S
I2C MA.ii | / | ASA | ASA | A
A
M IC | IC M
TRX | TRX
I2C ASD | ASD I2C | I2C SLc
node#2 | node#5
ASA | ASA
I2C SLa
TRX | TRX
ECU | Display
IC | IC | I2C SLd
node#1 | node#6 | n6
ASE | ASE L
Ln | /S
I2C MA.i | S | ASA | ASA | A
C IC | IC M
TRX | TRX
I2 | I2C SLe
ASD | ASD I2C
I2C MA.v
IC debugger #3
Figure III-5: I2C Multi-Master scenario
