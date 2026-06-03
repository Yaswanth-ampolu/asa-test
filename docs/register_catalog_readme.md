# Register Catalog README

## Overview

`register_catalog.json` is a machine-readable catalog of all ASA v2.0 registers
defined in Sections 3.1–3.8 of the ASA Technical Specification v2.0.

Source documents:
- `docpdfmd/micro-architecture-register-model.md` (primary)
- `pipeline/out/asa_structured_chunks.jsonl` (address/section cross-reference)

## Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| address | string | Register address in `d.a` format (e.g. "1.0001") |
| address_range_end | string | Last address of a contiguous range (e.g. "2.0133"); absent for single registers |
| name | string | Register name from the spec |
| domain | int or string | 1=PHY, 2=DLL, 3=Security, 4=ASE, 5=ASD, "4_or_5"=common ASEP |
| subdomain_kind | string or null | "DLP_TX_ID" for ASE (domain 4), "DLP_RX_ID" for ASD (domain 5), null otherwise |
| section | string | PDF section number (e.g. "3.2.1") |
| page | int | PDF page number |
| rw_type | string | "RO", "RW", or "SC" (self-clearing) |
| access | string | "O" (OAM + local) or "L" (local only) |
| privilege | string | "RID" (root ID only) or "A" (authenticated) |
| reset | string | Reset/default value as hex string, or "VERIFY" if not specified in spec |
| optional_feature | string or null | Feature gate: "LightSleep", "LinkAggregation", "MLE", "Security", or null for mandatory |
| stream_type | string | (ASEP only) Stream type this register applies to: "I2C", "SPI", "GPIO", "I2S" |
| fields | array | Per-field bit definitions (see below) |

## Field Object Fields

| Field | Type | Description |
|-------|------|-------------|
| bits | string | Bit range (e.g. "15:0", "7", "3:0") |
| name | string | Field name |
| rw_type | string | "RO", "RW", or "SC" for this specific field |
| access | string | "O" or "L" |
| privilege | string | "RID" or "A" |
| description | string | Human-readable field description from spec |

## Address Conventions

### Single-node registers
Address format: `d.a` where d=domain (1-5), a=register number.

### ASE/ASD registers
Format: `4/5.i.0xxx` where `i` = DLP port ID (1-63).
In the catalog, these use address `4/5.i.0xxx` with `subdomain_kind` set.
For stream-specific registers that share the same address across stream types
(e.g., 4/5.i.0200 is used for I2C, SPI, GPIO, and I2S), separate entries are
created with a `stream_type` discriminator field and an address suffix
(e.g., `4/5.i.0200_I2C`, `4/5.i.0200_SPI`).

### Register ranges
When `address_range_end` is present, the entry covers a contiguous block of
registers that share the same format (e.g., DLLmappertable 2.0146-2.2065).

## Reset Values

- Explicit hex value (e.g. "0x0000"): confirmed from spec
- "VERIFY": spec does not state a reset value for this register; implementation must determine

## SC (Self-Clearing) Semantics

SC registers are written by hardware (events set flags or increment counters).
Software/OAM reads return the accumulated value and atomically clear to 0.
Software cannot write SC fields directly — they appear read-only on the bus.

## Usage for RTL Generation

The catalog can be used to:
1. Generate register file RTL (address decoder, reset values, access control)
2. Generate OAM CAD bridge logic (which registers are O-accessible)
3. Generate documentation or golden-model register state
4. Validate register access in simulation

Example Python usage:
```python
import json

with open("register_catalog.json") as f:
    catalog = json.load(f)

# Find all RW OAM-accessible registers in domain 2
dll_rw = [r for r in catalog
          if r["domain"] == 2
          and r["rw_type"] == "RW"
          and r["access"] == "O"]

# Find all LightSleep-optional registers
ls_regs = [r for r in catalog if r.get("optional_feature") == "LightSleep"]
```

## Total Register Count

The catalog contains approximately 75 entries covering:
- Domain 1 (PHY): 1.0001 – 1.0499 (20 entries including Link Aggregation range)
- Domain 2 (DLL): 2.0001 – 2.2256 (30 entries including ranges)
- Domain 3 (Security): 3.0001 – 3.0003 (3 entries)
- Domain 4/5 common: 4/5.i.0001 – 4/5.i.0062 (9 entries)
- Domain 4/5 stream-specific: per stream type 0200+ (13 entries)
- Domain 4 ASE-only: 4.i.0100 – 4.i.0213 (7 entries)
- Domain 5 ASD-only: 5.i.0100 – 5.i.0102 (3 entries)
