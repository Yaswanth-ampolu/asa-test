# Micro-Architecture: Link Layer Security (LLS)

## 1. Purpose and Scope

The Link Layer Security (LLS) entity protects Data Link Layer containers between two
adjacent ASA nodes using AES-GCM or AES-GMAC. It provides authentication and
integrity protection, with optional encryption, using session keys (Link Keys)
installed per link per power cycle.

### 1.1 Responsibilities
- Classify outgoing containers: bypass or protect
- Build the Security Payload (protection flag byte, Counter, ICV)
- Construct the 96-bit IV from KeyEx=0, Dir, Salt, and TX AEAD Invocation Counter
- Perform AES-GMAC (auth-only) or AES-GCM (auth+encrypt)
- Classify incoming containers: bypass or verify
- Reconstruct the assumed IV from RX AEAD Invocation Counter + received Counter byte
- Verify ICV; drop on failure and increment dropped-RX counter
- Manage two key slots for seamless key rotation
- Update KeySwitch header bit
- Report errors to DLL via error_handler primitive

### 1.2 Out of Scope
- Key Exchange (KeyEx) entity: installs keys via DeviceInternal.install_key
  (see future micro-architecture-keyex-entity.md)
- Persistent key storage hardware
- Key hierarchy above Link Keys (Device Keys, Binding Keys)
- OAM CAD routing (see micro-architecture-oam-control-plane.md)

### 1.3 Optional Status

SPEC FACT (Section 6.2, p194): "The existence of the Security Entity is optional."

SPEC FACT (Section 6.3.1.1): AES-GMAC-128 with 128-bit LKs is required if security
is implemented. AES-GCM-128 is recommended. 256-bit key support is optional.

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 3.4 | Security Registers | 65-66 | Domain 3 registers |
| 3.4.1 | securityPolicy (3.0001) | 65 | Policy encoding |
| 3.4.2 | droppedContainersSecRX (3.0002) | 66 | RX drop counter |
| 3.4.3 | droppedContainersSecTX (3.0003) | 66 | TX drop counter |
| 6.1 | Security Entity overview | 194 | Optional, two components |
| 6.2 | Keys and IDs | 194-196 | Key hierarchy, UUID |
| 6.2.1 | Key length requirements | 195 | 128 mandatory, 256 optional |
| 6.2.4 | Link Keys | 196 | Session keys, not persistent |
| 6.3 | Link Layer Security | 196-203 | LLS definition |
| 6.3.1 | General concepts | 196-198 | Algorithms, IV, container format |
| 6.3.1.1 | Algorithms | 197 | AES-GMAC/GCM |
| 6.3.1.2 | IV construction | 197 | Table 6-1 |
| 6.3.1.3 | Secured container format | 198 | Figure 6-2, Table 6-2 |
| 6.3.1.3.1 | Counter field | 198 | 8-bit, LSB of 64-bit counter |
| 6.3.1.3.2 | ICV field | 198 | 128-bit Auth Tag |
| 6.3.2.1-5 | LLS primitives | 198-200 | SecCoP/SIF interface |
| 6.3.3.1 | DeviceInternal.install_key | 200 | Key slot setup |
| 6.3.4.1 | process_incoming_message | 200-201 | RX processing order |
| 6.3.4.2 | process_outgoing_message | 201-202 | TX processing order, Table 6-2 |
| 6.3.5 | OAM accessibility limitation | 203 | LLS not accessible via OAM |

Image references (docpdfmd/images/):
- `57_Figure_5-3_Container_Payload_secured_unsecured.png`: Container payload layout
- `68_Figure_6-1_Cryptographic_Key_Overview.png`: Key hierarchy example (informative)
- `69_Figure_6-2_Container_Security_enabled.png`: Confirmed container format:
  [Container Header][byte0: bit7=protection_flag, bits6:0=reserved][Counter (lower byte)][DLL Payload (secured)][ICV]
  Brackets: authentication/integrity covers full container; optional encryption covers DLL Payload
- `70_Figure_6-3_DK1_BK_Installation.png`: Key installation sequence (KeyEx, not LLS)
- `71_Figure_6-4_Link_Key_Installation.png`: LK installation (KeyEx, not LLS)
- `72_Figure_6-5_Key_Rotation_IV_Overflow.png`: IV overflow and key rotation trigger

---

## 3. Architecture Position

SPEC FACT (Figure 5-1, Section 5.1, p162): Security entity is inside the DLL block.
Its interfaces to the DLL core are SecCoP and SIF.

```
                    DLL Core
     +------------------------------------------+
     |                                          |
     |  [Mapper/Scheduler] --- DLP_TX           |
     |        |                    ^            |
     |        v            SecCoP /             |
     |   [Header Gen] -----> LLS  <--> SIF      |
     |        |             entity              |
     |        v            SecCoP \             |
     |  [PLP_TX]              DLP_RX            |
     |                            |             |
     |  [PLP_RX] ----------> [Demux]            |
     +------------------------------------------+
```

SPEC FACT (Section 5.2.1 steps e, 5.3.1 step a): LLS is called synchronously:
- TX: DLL calls process_transmit_container after header construction
- RX: DLL calls process_receive_container before header decode/demux

---

## 4. Security Registers (Domain 3)

### 4.1 securityPolicy (3.0001) — Table 3-71, p65

```
Bits 15:2  Reserved
Bits 1:0   securityPolicy    RO  L  RID
  0b00: No Security
  0b01: Authentication only (AES-GMAC)
  0b11: Authentication and Encryption (AES-GCM)
  0b10: Reserved
```

SPEC FACT: "Every ASA Device shall have a register for determining the security
policy. This register shall be read-only." Access = L (local only, NOT OAM-accessible).

### 4.2 droppedContainersSecRX (3.0002) — Table 3-72, p66

```
Bits 15:0  droppedContainersSecRX   SC  O  RID
  Number of dropped/rejected containers, saturating counter
```

Incremented by DLL when LLS calls error_handler with RX error (6.3.2.5.3).

### 4.3 droppedContainersSecTX (3.0003) — Table 3-73, p66

```
Bits 15:0  droppedContainersSecTX   SC  O  RID
  Number of dropped/rejected containers, saturating counter
```

Incremented by DLL when LLS calls error_handler with TX error (6.3.2.5.3).

---

## 5. Secured Container Format (Table 6-2, PDF p202; Figure 6-2)

SPEC FACT (Section 6.3.1.3, Table 6-2, PDF p202):

```
Byte  Length  Name                  Description
0     1       Payload LLS           Bit 7:
              protection flag         1 = payload protected by LLS (per securityPolicy)
                                      0 = payload NOT protected; Counter/ICV invalid
                                    Bits 6:0: reserved, set to 0
1     1       Counter               Link Layer TX AEAD Invocation Counter (lower byte)
              (byte position 1)     = least significant 8 bits of 64-bit counter
2+    N       DLL Payload           Size unchanged from what was provided by DLL
                                    Size is one of: Dn_P2P_Sec, Dn_MC_Sec,
                                    Up_P2P_Sec, Up_MC_Sec (see Section 5.6.1.1)
2+N   16      ICV                   Integrity Check Value (Auth Tag for AES-GCM/GMAC)
```

SPEC FACT: The entire region from byte 0 through ICV is labeled "Security Payload"
in Figure 6-2. Authentication/integrity covers the full container (header + security
payload). Optional encryption covers only the DLL Payload field.

IMAGE CONFIRMATION (Figure 6-2, `69_Figure_6-2_Container_Security_enabled.png`):
Confirms exactly: [Container Header][byte7 protection_flag | reserved 6:0][Counter
(lower byte)][DLL Payload (secured)][ICV]. The brace labeled "authentication /
integrity check in LLS" spans the full width. The brace labeled "optional encryption
in LLS" spans only the DLL Payload region.

---

## 6. IV Construction (Section 6.3.1.2, Table 6-1)

SPEC FACT: IV is 96 bits total.

```
IV[95:0] = Fixed_Field[31:0] || Invocation_Field[63:0]

Fixed Field (32 bits):
  Bits 31:2  KeyEx   = 0 (always 0 for LLS containers; KeyEx uses 1)
  Bit  1     Dir     = 0 for Downstream, 1 for Upstream
  Bits 0     Salt    = set by KeyEx.install_LKs (see Section 6.4.3.12)
                       (VERIFY: Salt width vs position vs Table 6-1 — see uncertainty)

Invocation Field (64 bits):
  Next Link Layer TX AEAD Invocation Counter
  (starts at 1, increments per protected container)
```

SPEC FACT: "Counter that increments for every AEAD invocation in TX direction for
secured Link Layer Containers only and starts with 1."

---

## 7. Key Slot State (Section 6.3.3.1)

SPEC FACT: DeviceInternal.install_key sets up per link, per key slot:

| Field | Value after install |
|-------|---------------------|
| Link Key | installed value |
| Salt | installed value |
| Next TX AEAD Invocation Counter | 1 |
| Last RX AEAD Invocation Counter | 0 |

Two key slots exist for seamless rotation. KeySwitch bit in container header selects
which slot: 0 = first slot, 1 = second slot.

---

## 8. Outgoing Message Processing (Section 6.3.4.2, PDF p201-202)

Steps executed in order after primitive 6.3.2.1 is called:

```
1. Is message an exempt OAM frame?
   Exempt = {KeyEx primitives} | {Node Discover} | {Self Announce}
   If yes: return unmodified via 6.3.2.2 (bypass)

   Note: Empty OAM frames:
     - BEFORE LKs installed: pass without checks (bypass)
     - AFTER  LKs installed: must pass security

2. Set Security Payload byte0, bit7 = 1 (protection flag)

3. Select Key, Salt, Next TX AEAD Invocation Counter, Status
   from currently selected key slot

4. Check if key slot is "ready" or "active"
   If NOT: drop container, increment droppedContainersSecTX, call 6.3.2.5, STOP

5. Construct IV:
   IV = { KeyEx=0 | Dir | Salt } || { Next TX AEAD Invocation Counter }

6. Set Counter byte (byte 1 of Security Payload) =
   LSB 8 bits of Next TX AEAD Invocation Counter

7. Perform crypto:
   securityPolicy=0b01 (auth only):   AES-GMAC
     AAD = Container Header + byte0 (protection flag) + Counter byte
     Input = DLL Payload (unchanged)
     Output = ICV (128-bit Auth Tag)
   securityPolicy=0b11 (auth+encrypt): AES-GCM
     AAD = Container Header + byte0 (protection flag) + Counter byte
     Input = DLL Payload (plaintext)
     Output = DLL Payload (ciphertext) + ICV

8. Increment Next TX AEAD Invocation Counter by 1

9. Update KeySwitch bit in Container Header

10. Return via 6.3.2.2: Container Header (with KeySwitch) + Security Payload
```

---

## 9. Incoming Message Processing (Section 6.3.4.1, PDF p200-201)

Steps executed in order after primitive 6.3.2.3 is called:

```
1. Is message an exempt OAM frame?
   Exempt = {KeyEx primitives} | {Node Discover} | {Self Announce}
   All such messages shall have byte0,bit7=0
   If yes: return via 6.3.2.4 (bypass)

   Note: OAM frames not in exempt list, when security enabled but LKs not installed:
     filtered out (all args in 6.3.2.4 set to 0)

   Empty OAM frames:
     - BEFORE LKs installed: pass without checks
     - AFTER  LKs installed: pass security

2. Determine key slot from KeySwitch (Header) Flag:
   KeySwitch=0 -> first slot
   KeySwitch=1 -> second slot

3. Check if key slot is valid and ready
   If NOT: drop, increment droppedContainersSecRX, STOP

4. Reconstruct assumed IV:
   Split Last RX AEAD Invocation Counter (64-bit) into:
     Last Shadow Counter = bits[63:8]  (most significant 56 bits)
     Last Counter        = bits[7:0]   (least significant 8 bits)

   If Last Counter < received Counter (byte1 of Security Payload):
     Assumed AEAD Counter = Last Shadow Counter[63:8] || received Counter[7:0]

   If Last Counter >= received Counter:
     Assumed AEAD Counter = (Last Shadow Counter + 1)[63:8] || received Counter[7:0]

5. Perform crypto (AES-GMAC or AES-GCM based on configuration)
   AAD covers Container Header + protection flag byte + Counter byte

6. Check ICV:
   If FAIL: drop container, call 6.3.2.5 (AUTH_FAIL or DECRYPT_FAIL), STOP

   If PASS:
     a. Update Last RX AEAD Invocation Counter = assumed AEAD Invocation Counter
     b. AES-GMAC: return container without Counter and ICV (via 6.3.2.4)
     c. AES-GCM: return container with decrypted DLL Payload, Counter/ICV removed (via 6.3.2.4)
     d. Switch active RX Key Slot if this message was received with correct ICV
        of the other key slot; deactivate old slot
```

---

## 10. Key Rotation and IV Overflow (Figure 6-5)

SPEC FACT (Figure `72_Figure_6-5_Key_Rotation_IV_Overflow.png` and Section 6.4.3.13):
The KeyEx entity monitors the TX AEAD Invocation Counter for overflow margin.
When margin drops below threshold, KeyEx initiates key rotation:
1. New LK installed in the inactive slot
2. KeySwitch bit transitions to new slot on next TX container
3. On receiver: when a container with new KeySwitch and valid ICV arrives,
   the new slot becomes active and old slot is deactivated

LLS does NOT manage key rotation independently. It reports counter state to KeyEx
(via KeyEx.report_status_LK); rotation is driven by KeyEx.

---

## 11. SecCoP/SIF Interface (Primitives)

### 11.1 DLL-to-LLS (SecCoP calls)

| Primitive | Direction | Description |
|-----------|-----------|-------------|
| process_transmit_container(header, dll_payload) | DLL->LLS | Outgoing container for protection |
| process_receive_container(header, sec_payload) | DLL->LLS | Incoming container for verification |

### 11.2 LLS-to-DLL (SIF responses)

| Primitive | Direction | Description |
|-----------|-----------|-------------|
| return_processed_tx_container(header, sec_payload) | LLS->DLL | Protected outgoing container |
| return_processed_rx_payload(dll_payload) | LLS->DLL | Verified/decrypted payload |
| error_handler(dir, err_code) | LLS->DLL | Error notification |

Error codes: AUTH_FAIL, DECRYPT_FAIL, OAM_FILTER

### 11.3 KeyEx-to-LLS (Internal)

| Primitive | Direction | Description |
|-----------|-----------|-------------|
| DeviceInternal.install_key(slot, key, salt) | KeyEx->LLS | Install key slot |

---

## 12. Suggested RTL Module Boundaries

```
+================================================================+
|                    security_top                                  |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | tx_security_pipeline|    | rx_security_pipeline|             |
|  |                     |    |                     |             |
|  | bypass_classifier   |    | bypass_classifier   |             |
|  | key_slot_select     |    | key_slot_select     |             |
|  | iv_builder (TX)     |    | iv_counter_recon    |             |
|  | aead_engine_adapter |    | aead_engine_adapter |             |
|  | sec_payload_builder |    | icv_checker         |             |
|  | keyswitch_updater   |    | payload_stripper    |             |
|  | tx_counter_incr     |    | rx_counter_updater  |             |
|  +---------------------+    | keyslot_switcher    |             |
|                             +---------------------+             |
|  +---------------------+    +---------------------+             |
|  | key_slot_table      |    | drop_counter_block  |             |
|  |                     |    |                     |             |
|  | Two slots per link  |    | droppedSecTX (3.0003)|            |
|  | Key, Salt,          |    | droppedSecRX (3.0002)|            |
|  | TX counter,         |    | SC behavior          |            |
|  | RX counter,         |    +---------------------+             |
|  | State (ready/active)|                                        |
|  +---------------------+                                        |
|                             +---------------------+             |
|  +---------------------+    | bypass_classifier   |             |
|  | iv_builder          |    | (shared logic)      |             |
|  |                     |    |                     |             |
|  | Concatenate:        |    | KeyEx OAM frames    |             |
|  | KeyEx || Dir ||     |    | Node Discover       |             |
|  | Salt || Counter     |    | Self Announce       |             |
|  +---------------------+    | Empty OAM pre-LK    |             |
|                             +---------------------+             |
+================================================================+
```

---

## 13. Interfaces to Other Modules

### 13.1 DLL TX Path

| Signal | Dir | Description |
|--------|-----|-------------|
| secp_tx_req(header, dll_payload) | DLL->LLS | process_transmit_container |
| secp_tx_resp(header, sec_payload) | LLS->DLL | return_processed_tx_container |
| secp_tx_err(err_code) | LLS->DLL | error_handler TX path |

### 13.2 DLL RX Path

| Signal | Dir | Description |
|--------|-----|-------------|
| secp_rx_req(header, sec_payload) | DLL->LLS | process_receive_container |
| secp_rx_resp(dll_payload) | LLS->DLL | return_processed_rx_payload |
| secp_rx_err(err_code) | LLS->DLL | error_handler RX path |

### 13.3 Register Model

| Signal | Dir | Description |
|--------|-----|-------------|
| security_policy[1:0] | Reg->LLS | securityPolicy (3.0001) |
| dropped_rx_inc | LLS->Reg | Increment droppedContainersSecRX |
| dropped_tx_inc | LLS->Reg | Increment droppedContainersSecTX |

### 13.4 KeyEx Entity

| Signal | Dir | Description |
|--------|-----|-------------|
| install_key(slot, key, salt, tx_ctr_init) | KeyEx->LLS | DeviceInternal.install_key |
| tx_counter_status | LLS->KeyEx | Report TX AEAD Invocation Counter for overflow monitoring |

### 13.5 OAM Control Plane

No direct interface. SPEC FACT (Section 6.3.5): "All primitives of the Link Layer
Security shall not be accessible through the OAM channel or external interfaces."

---

## 14. Spec Facts vs Implementation Assumptions

### Spec Facts
- Authentication-only mode (AES-GMAC) is mandatory; encryption optional
- IV = 96 bits: Fixed[31:0] || Invocation[63:0]
- KeyEx=0 in IV fixed field for LLS containers
- Dir=0 downstream, Dir=1 upstream
- TX counter starts at 1, increments per protected container
- RX counter reconstruction from shadow+received byte
- ICV = 128 bits (16 bytes), after DLL Payload
- Security Payload byte0 bit7 = protection flag; bits 6:0 = reserved
- Counter byte = LSB 8 bits of TX AEAD Invocation Counter
- Two key slots for rotation
- KeySwitch 0=slot1, 1=slot2
- RX key slot switch on valid ICV from other slot
- KeyEx, Node-Discover, Self-Announce bypass LLS
- Empty OAM: bypass before LKs installed, must pass security after
- Non-exempt OAM when LKs not installed: filtered (dropped)
- securityPolicy is local-only (L), not OAM-accessible
- Dropped counters are SC, OAM-accessible, saturating 16-bit

### Implementation Assumptions
- AEAD engine latency: pipelined; DLL TX/RX can stall waiting for LLS response
- Key slot state machine: "ready" = key installed but not yet active for RX;
  "active" = currently used for encrypt/decrypt; "deactivated" = old slot after rotation
  (these state names are inferred from Section 6.3.4.1/6.3.4.2 usage; exact state
  names are not normative)
- Counter overflow: not explicitly bounded in spec. Implementation should notify
  KeyEx before rollover; KeyEx manages rotation.

---

## 15. Verification Plan

| Test | Stimulus | Expected Outcome |
|------|----------|-----------------|
| Unsecured policy | securityPolicy=0b00 | No LLS processing, all containers bypass |
| Secured TX GMAC | TX container, policy=0b01 | byte0.bit7=1, Counter set, ICV appended, DLL Payload unchanged |
| Secured TX GCM | TX container, policy=0b11 | byte0.bit7=1, Counter set, DLL Payload encrypted, ICV appended |
| Secured RX valid ICV | RX container, correct ICV | Return decrypted payload, update RX counter |
| Secured RX bad ICV | RX container, wrong ICV | Drop, AUTH_FAIL, droppedSecRX++ |
| KeyEx OAM bypass | TX/RX KeyEx OAM frame | Passes unmodified, byte0.bit7=0 |
| Node-Discover bypass | TX/RX Node-Discover | Passes unmodified |
| Empty OAM pre-LK | Empty OAM before LK install | Passes without security |
| Empty OAM post-LK | Empty OAM after LK install | Must pass security |
| Non-exempt OAM no-LK | Non-exempt OAM, no LK | Filtered (dropped) |
| KeySwitch=1 slot | TX/RX with second key slot | Routes to slot 1 state |
| Key rotation trigger | RX valid ICV from other slot | Switch RX active slot, deactivate old |
| IV overflow boundary | TX counter near rollover | KeyEx should rotate before rollover |
| TX key slot not ready | Key slot not ready | Drop TX, droppedSecTX++ |
| RX key slot not valid | Key slot invalid | Drop RX, droppedSecRX++ |

---

## 16. Remaining Uncertainties

1. **Salt field bit width and position in IV Fixed Field**: Table 6-1 lists the
   Fixed Field as {KeyEx, Dir, Salt} in 32 bits but does not give explicit bit
   widths for Salt. Salt is "set by the Link Key Installation" (6.4.3.12). VERIFY
   exact bit positions from Table 6-1 and Section 6.4.3.12 parameter definitions.

2. **Key slot state names**: Section 6.3.4.1/6.3.4.2 use "valid", "ready", "active"
   without defining a formal key slot state machine. The exact states and transitions
   between them depend on KeyEx primitives (6.4.3.12, 6.4.3.13) which are KeyEx scope.
   VERIFY against KeyEx state machine when that module is written.

3. **AAD construction not fully specified**: Section 6.3.4 says "do crypto processing"
   but does not explicitly list every field that goes into the AAD (Additional
   Authenticated Data). The Container Header is authenticated; whether the protection
   flag byte and Counter byte are included in AAD or treated as plaintext overhead
   requires careful reading of NIST SP 800-38D usage context. VERIFY.

4. **RX counter rollover handling**: The reconstruction algorithm handles shadow +
   received-byte to advance the counter window by 1. What happens if the gap between
   the assumed counter and actual counter exceeds 256 (full byte rollover without a
   transition) is not specified. Implementation must decide on replay window policy.

5. **Encryption of headers**: The spec says "optional encryption in LLS" with the
   brace in Figure 6-2 covering only DLL Payload, not Container Header. Container
   Header is always plaintext for routing. VERIFY this is correct and not
   implementation-dependent.

6. **securityPolicy bit 0b10 reserved status**: If a device reads 0b10, behavior is
   unspecified. Implementation must handle this gracefully.

7. **Multi-link security**: Key hierarchy shows Link Keys per link between adjacent
   nodes (Figure 6-1). Whether branch devices with multiple links have independent
   key slots per link or a shared table is not specified for LLS specifically.
   VERIFY in KeyEx entity design.
