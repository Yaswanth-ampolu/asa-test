---
{
  "section": "VII",
  "section_title": "Appendix G: Recommended Mapping of ASA Register Addresses to local I2C (informative)",
  "module": "Unknown",
  "depth": 1,
  "page_start": 351,
  "page_end": 351,
  "content_type": "asep_protocol",
  "register_address": null,
  "tables": [
    {
      "id": "VII-1",
      "title": "Local I2C to ASA Register Mapping"
    }
  ],
  "figures": [],
  "source": "ASA_Technical_Specification_ver2.0.pdf"
}
---

# VII Appendix G: Recommended Mapping of ASA Register Addresses to local I2C (informative)

VIIAppendix G: Recommended Mapping of ASA Register Addresses to local I2C
(informative)
Use 7bit addressing with 1111_011 to address the ASA register map(s) on the ASA device (as 10bit
addressing is not supported). Use R/W-bit of first byte in I2C.
Payload starts from second byte. Send a command and the hierarchical ASA register address
preceded by a node/port identifier as payload. The following table shows the complete sequence of
bytes for a write command on the ASA register map.
For a read command, bytes 6 and 7 are not sent. Instead, bytes 6 and 7 are returned by the ASA
device.
Byte Bit(s) Name | Description
7:1 ASA register access | Local I2C address for ASA register map
access
R/W bit | I2C protocol bit
ASA register map command 0: Write
1: Read
6:5 | reserved, set to 0
4:1 node/port identifier | Local identifier for multi-port device (not
identical with ASA nodeID)
ASA register domain[3] | “d” inTable 3-1
7:5 ASA register domain[2:0]
4:0 ASA register subdomain[5:1] “i” inTable 3-1; set to 0 if not ASA register
domain 4 or 5
ASA register subdomain[0]
6:0 ASA register address[14:8] “a” inTable 3-1
7:0 ASA register address[7:0]
7:0 Register data [15:8] | Data to be written (only present on write)
7:0 Register data [7:0]
Table VII-1: Local I2C to ASA Register Mapping
