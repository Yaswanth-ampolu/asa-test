---
{
  "section": "3",
  "section_title": "ASA Registers",
  "module": "Registers",
  "depth": 0,
  "page_start": 29,
  "page_end": 30,
  "content_type": "text",
  "register_address": null,
  "tables": [
    {
      "id": "3-1",
      "title": "ASA register address fields"
    }
  ],
  "figures": [],
  "source": "ASA_Technical_Specification_ver2.0.pdf"
}
---

# 3 ASA Registers

ASA Registers
Each ASA node has its own ASA register map. An ASA Device with more than one node carries a
complete ASA register map for each node. The register map is divided into domains, see Table 3-2.
The number of register subdomains 4 and 5 depends on the number of implemented ASE and ASD.
Register domains and registers for optional features are part of this optional feature and only exist,
when this optional feature is present.
Access: A register can be accessible only locally or through OAM. Access through OAM implies local
access. When a register is accessible through OAM, it can be accessed by the root node under any
condition or it can be accessed only with an authenticated message (enforced by the optional feature
Security Entity, see section 6).
Privilege:A register, which requires the access privilege “authenticated by security” can only be
accessed locally, if security is not present. (INFORMATIVE: access restrictions refer to limitations that
have to be enforced for interoperability; it does not impact accessibility in non-ASA operation
modes).
ASA register addresses are given in the formatof four fields “d.a.(m:l)”or five fields “d.i.a.(m:l)”
depending on the domain/layer, where the fields are described in Table 3-1.
Address
Definition/Description | Range of values
Field
d | domain/layer | 0-5 … used
6-8 … reserved
i | subdomain for DLL Port ID in case of ASE/ASD | 0 … reserved
(only used, when domain is 4 or 5) | 1-63 … DLP ID
a | register number/address within domain | 0 … reserved
1-32767 … register number
m | Most significant bit for indexing within register 0..15
l | Least significant bit for indexing within register 0..14
Table 3-1: ASA register address fields
All ASA registers per address“d.a.”or“d.i.a.”are 16 bitswide. The addition of “m:l” is used for
indexing with these 16 bits (“d.a.m:l”or“d.i.a.m:l”).
If “l” is omitted(“d.a.m”or“d.i.a.m”), only a single bit is addressed/described.
If “l” and “m” are omitted(“d.a”or“d.i.a”), the whole register is addressed/described.
All address fields are given as integer numbers in this section 3 and the rest of the specification. The
register number “a” is given as a 4-digit integer number.
