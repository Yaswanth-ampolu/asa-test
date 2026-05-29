# Micro-Architecture: Key Exchange (KeyEx) Entity

## 1. Purpose and Scope

The Key Exchange (KeyEx) Entity is the control-plane component responsible for
provisioning, managing, and rotating cryptographic keys used by Link Layer Security
(LLS). It handles the full key hierarchy lifecycle from Device Key installation at
production time through per-power-cycle Link Key installation and IV-overflow-driven
key rotation.

### 1.1 Responsibilities
- Store and manage Device Keys (DK_0, DK_1, DK=DK_0 XOR DK_1), Binding Keys (BK),
  and Link Keys (LK) per ASA link
- Receive KeyEx OAM messages (via DLL OAM path) and dispatch primitives
- Validate incoming IV and ICV for every secured KeyEx message
- Construct IV and ICV for outgoing KeyEx responses
- Install LKs into LLS key slots via DeviceInternal.install_key
- Monitor TX AEAD Invocation Counter margins and initiate key rotation
- Report LK status to root ECU via KeyEx.report_status_LK (0x81)
- Maintain Power Cycle Nonce (PCN) generated fresh each power cycle

### 1.2 Out of Scope (belongs to Link Layer Security)
- Container-level authentication/encryption (see micro-architecture-link-layer-security.md)
- Per-container IV increment in normal operation
- KeySwitch header bit management
- Dropped container counters (registers 3.0002/3.0003)

### 1.3 Optional Status

SPEC FACT (Section 6.2): "The existence of the Security Entity is optional."

SPEC FACT (Section 6.4.1.5): AES-GCM with AES-128 is mandatory for KeyEx if
security is implemented. AES-GCM with AES-256 is optional.

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 6.2 | Keys and IDs | 194-196 | Key hierarchy |
| 6.2.1 | Key length | 195 | 128 mandatory, 256 optional |
| 6.2.2 | Device Keys | 195-196 | DK_0, DK_1, DK=XOR |
| 6.2.3 | Binding Keys | 196 | BK persistence rules |
| 6.2.4 | Link Keys | 196 | LK non-persistence, per power cycle |
| 6.2.5 | UUIDs | 196 | 128-bit device identity |
| 6.4 | Key Exchange | 203 | Overflow monitoring in process_outgoing_message |
| 6.4.1 | General Concepts | 203-205 | IV, AEAD, direction, status codes |
| 6.4.1.1 | KeyEx locations | 203 | Root ECU SW vs Device |
| 6.4.1.2 | Definitions | 203 | Implicit/Additional/Encrypted Data |
| 6.4.1.3 | Status/Error codes | 203-204 | 8-bit codes table |
| 6.4.1.4 | KeyEx IV construction | 204 | 96-bit IV, bit-exact fields |
| 6.4.1.5 | Cryptography | 204 | AES-GCM mandatory |
| 6.4.1.6 | ICV construction | 204 | Big Endian, field order |
| 6.4.1.7 | Direction field | 204 | 0x00=Root->Device, 0x01=Device->Root |
| 6.4.1.8 | Key slot states | 205 | Empty/Ready/Active/Deactivated |
| 6.4.2 | OAM message mapping | 205-206 | Tables 6-3, 6-4 |
| 6.4.3.1 | install_UUID (0x00) | 206 | One-time UUID write |
| 6.4.3.2 | read_UUID (0x02) | 206 | UUID read |
| 6.4.3.3 | read_current_nonce (0x04) | 207 | Power Cycle Nonce |
| 6.4.3.4 | read_status_keys (0x06) | 207-208 | Key status readback |
| 6.4.3.5 | read_status_keys_ext (0x07) | 209-210 | Secured status + TX IV |
| 6.4.3.6 | setup_policy (0x08) | 210-211 | Security policy per node |
| 6.4.3.7 | install_DK_0_unencrypted (0x10) | 211-212 | DK_0 installation |
| 6.4.3.8 | install_DK_1_unencrypted (0x12) | 212-213 | DK_1 unencrypted |
| 6.4.3.9 | install_DK_1_encrypted (0x13) | 213-215 | DK_1 encrypted via DK_0 |
| 6.4.3.10 | install_BK_encrypted (0x21) | 215-217 | BK encrypted via DK |
| 6.4.3.11 | install_BK_encrypted_by_DK_1_only (0x23) | 217-219 | BK via DK_1 |
| 6.4.3.12 | install_LKs_encrypted (0x31) | 219-221 | LK+Salt installation |
| 6.4.3.13 | change_LKs_KeySlot (0x33) | 221-223 | Active key slot change |
| 6.4.3.14 | report_status_LK (0x81) | 223-225 | Device-initiated IV overflow report |
| 6.4.4.5 | Link Key Installation | 227-229 | Full LK provisioning flow |

Image references (docpdfmd/images/):
- `71_Figure_6-4_Link_Key_Installation.png`: Root SW -> Root Device -> Device B/C,
  loop over links: read_nonce, gen_AEADs, install_LKs (check_IV, check_ICV,
  install_LKs, generate_proofs), proofs_of_installed_LKs, check_proofs
- `72_Figure_6-5_Key_Rotation_IV_Overflow.png`: Three-tier escalation:
  <10% margin -> report_status_LK; <5% margin -> report_status_LK again;
  overflow detected -> change_KeySlot + invalidate_previous_KeySlot + report;
  then Root installs new LK in invalidated slot, both devices call
  LinkLayerSec.install_key
- `70_Figure_6-3_DK1_BK_Installation.png`: DK_1 + BK installation sequence

---

## 3. Key Hierarchy and Roles

### 3.1 Key Hierarchy

```
OEM / Tier-1 production
        |
    [DK_0]   written once by Tier-1 during ECU production
        |
    [DK_1]   written once by OEM during car production
        |
    DK = DK_0 XOR DK_1    (computed, never stored as-is)
        |
    [BK]     one per (Root Device, Non-Root Device) pair
             persistent across power cycles, changeable
             requires DK_0 + DK_1 to install (or DK_1 only for ID 0x23)
        |
    [LK]     one per link, per power cycle
             NOT persistent: must be reinstalled every power cycle
             protected by BK when delivered over OAM
             two key slots per ASA node per link (slot 0, slot 1)
```

### 3.2 KeyEx Entity Locations (Section 6.4.1.1)

SPEC FACT:
- Root Device: KeyEx Entity is at the ASA Root ECU Software (not in the ASA chip)
- Root Device: one KeyEx Entity per ASA Branch
- Non-Root Device: KeyEx Entity is at the ASA Device itself

### 3.3 UUID

SPEC FACT: Each device has a one-time writable 128-bit UUID. If not written, UUID=0.
UUID is freely readable (unlike keys). Used as implicit data in secured primitives.

### 3.4 Power Cycle Nonce (PCN)

SPEC FACT (Section 6.4.3.3): Device generates a Power Cycle Nonce at the beginning
of each power cycle. PCN is read via primitive 0x04. PCN is used as part of the
KeyEx IV construction (Power Cycle Counter field).

---

## 4. KeyEx IV Construction (Section 6.4.1.4)

SPEC FACT: IV is 96 bits. Fields are bit-exact (unlike LLS IV which has unspecified
packing within the 32-bit fixed field):

```
IV[95:95]  KeyEx = 1   (always 1 for KeyEx; LLS uses 0)
IV[94:94]  Direction   0x00=Root->Device, 0x01=Device->Root
IV[93:64]  Salt        30 bits, as installed by KeyEx (or 0 if not installed)
IV[63:32]  Power Cycle Counter  defined by Root Device (= PCN from 6.4.3.3)
IV[31:0]   KeyEx AEAD Invocation Counter
```

SPEC FACT (Section 6.4.1.5): All KeyEx messages use AES-GCM (not GMAC). AES-128
is mandatory; AES-256 is optional.

SPEC FACT (Section 6.4.1.6): ICV is constructed using Network Byte Order (Big
Endian); field order in ICV calculation follows the primitive field order.

---

## 5. KeyEx Primitive Summary

All primitives use OAM CAD command 0x7C (request) / 0x7D (response) transported
exclusively in dedicated OAM frames (CADnext=0 always).

| ID | Primitive | Direction | Secured? | Notes |
|----|-----------|-----------|----------|-------|
| 0x00 | install_UUID | R->D | No | One-time write |
| 0x02 | read_UUID | R->D | No | Readable anytime |
| 0x04 | read_current_nonce | R->D | No | Returns PCN |
| 0x06 | read_status_keys | R->D | No | Key status, slot states |
| 0x07 | read_status_keys_ext | R->D | Yes (BK) | Status + TX IV counters |
| 0x08 | setup_policy | R->D | Yes | Security policy per node |
| 0x10 | install_DK_0_unencrypted | R->D | No | DK_0 plaintext install |
| 0x12 | install_DK_1_unencrypted | R->D | No | DK_1 plaintext install |
| 0x13 | install_DK_1_encrypted | R->D | Yes (DK_0) | DK_1 via DK_0 |
| 0x21 | install_BK_encrypted | R->D | Yes (DK) | BK via DK |
| 0x23 | install_BK_encrypted_by_DK_1_only | R->D | Yes (DK_1) | BK via DK_1 only |
| 0x31 | install_LKs_encrypted | R->D | Yes (BK) | Install LK + Salt |
| 0x33 | change_LKs_KeySlot | R->D | Yes (BK) | Switch active key slot |
| 0x81 | report_status_LK | D->R | Yes (BK/LK) | Device reports IV overflow |

SPEC FACT (Section 6.4.3): "Primitives with an even ID (LSB=0) shall be used for
unprotected/unencrypted operations."

---

## 6. Key Slot State Machine (Section 6.4.1.8)

SPEC FACT:

| State | Value | Description |
|-------|-------|-------------|
| Empty | 0b00 | No key installed |
| Ready | 0b01 | Key installed, not yet active |
| Active | 0b11 | Key installed and in use |
| Deactivated | 0b10 | Key installed but disabled |

State tracking is per-slot, per-direction (TX and RX have independent state per slot):
```
Status_LKs byte:
  Bits 7:6  Slot 0, RX
  Bits 5:4  Slot 0, TX
  Bits 3:2  Slot 1, RX
  Bits 1:0  Slot 1, TX
```

SPEC FACT (Section 6.4.1.8): "For RX: Deactivated = received valid switch to
different slot. For TX: Deactivated = other slot got activated by KeyEx OAM message."

---

## 7. Status and Error Codes (Section 6.4.1.3)

| Code | Meaning |
|------|---------|
| 0x00 | OK |
| 0x10 | Nonce computation not finished |
| 0x11 | Authentication failed |
| 0x12 | Wrong UUID |
| 0x20 | Already written (one-time write) |
| 0x21 | Written but verify failed |
| 0x30 | UUID not written yet |
| 0x40 | DK_0 not written |
| 0x41 | DK_1 not written |
| 0x42 | BK not written |
| 0x43 | Max write cycles reached |
| 0x44 | LK not written |
| 0x50 | Not enough LKs |
| 0x51 | Too many LKs |
| 0x52 | Unsupported LK size |
| 0x53 | Unsupported Salt size |
| 0x60 | Unsupported key slot |
| 0x61 | Key slot empty |
| 0x62 | Key slot deactivated before |
| 0xFF | Unspecified error (optional) |

---

## 8. Link Key Installation Flow (Section 6.4.4.5, Figure 6-4)

SPEC FACT (Section 6.4.4.5): Runs at every power cycle and at key rotation.

```
Root SW                        Root Device           Device B            Device C
  |                                 |                    |                    |
  | generate_LKs()                  |                    |                    |
  |<--------------------------------|                    |                    |
  |     [loop over each link]       |                    |                    |
  | send_msg(B)                     |                    |                    |
  |-------------------------------->| KeyEx.read_Nonce() |                    |
  |                                 |------------------->|                    |
  |                   Nonce         |<- - - - - - - - - -|                    |
  |<--------------------------------|                    |                    |
  | gen_AEADs()                     |                    |                    |
  | send_msg(B)                     |                    |                    |
  |-------------------------------->| KeyEx.install_LKs()|                    |
  |                                 |------------------->| check_IV()         |
  |                                 |                    | check_ICV()        |
  |                                 |                    | install_LKs()      |
  |                                 |                    | generate_proofs()  |
  |            proofs_of_installed  |<- - - - - - - - - -|                    |
  |<--------------------------------|                    |                    |
  | send_msg(C)                     | KeyEx.install_LKs()|                    |
  |-------------------------------->|---------------------------------------->|
  |                                 |                    |    check_IV()      |
  |                                 |                    |    check_ICV()     |
  |                                 |                    |    install_LKs()   |
  |                                 |                    |    generate_proofs |
  |           proofs_of_installed   |<- - - - - - - - - - - - - - - - - - - -|
  |<--------------------------------|                    |                    |
  | check_proofs()                  |                    |                    |
```

IMPORTANT NOTE: Figure 6-4 caption says "(function names not binding!)".
The sequence shows the logical flow; actual OAM primitive IDs are 0x04 and 0x31.

### 8.1 Device-Side Validation of install_LKs_encrypted (ID: 0x31)

SPEC FACT (Section 6.4.4.5): Device MUST check in this order:
1. IV.KeyEx_bit == 1 (else drop, return 0x11)
2. IV.Direction == 0 Root->Device (else drop, return 0x11)
3. IV.Salt is consistent for all KeyEx messages this power cycle (else 0x11)
4. IV.Power_Cycle_Counter is consistent for all messages this power cycle (else 0x11)
5. IV.KeyEx_AEAD_Invocation_Counter > previous received value (else 0x11)
6. UUID matches device UUID (else return 0x12)
7. Check ICV (else return 0x11)
8. Decrypt LKs and Salts
9. Install LKs and Salts into respective key slot
10. Startup/unblock Link Layer Protection
11. Update stored IV counter

---

## 9. Key Rotation on IV Overflow (Section 6.4, Figure 6-5)

SPEC FACT (Section 6.4, PDF p203): The overflow monitoring happens inside
`process_outgoing_message` of LLS:

```
After incrementing TX AEAD Invocation Counter:
  If margin_to_overflow < 10%: call KeyEx.report_status_LK (0x81)
  If margin_to_overflow <  5%: call KeyEx.report_status_LK (0x81) again
  If counter reaches maximum:  deactivate current slot, switch to other slot,
                               call KeyEx.report_status_LK (0x81)
```

IMAGE EVIDENCE (Figure 6-5, `72_Figure_6-5_Key_Rotation_IV_Overflow.png`):
```
Device B monitors IV counter (check_IV_Counter_OVF)
  alt [overflow_margin < 10%]:
    Device B -> Root Device: KeyEx.report_status_LK() -> Return
  alt [overflow_margin < 5%]:
    Device B -> Root Device: KeyEx.report_status_LK() -> Return
  alt [overflow detected]:
    Device B: change_KeySlot() + invalidate_previous_KeySlot()
    Device B -> Root Device: report_status_LK() -> Return
    Root Device: send_msg(C) -> (installs new LK in invalidated slot)
    Device C: change_KeySlot() + invalidate_previous_KeySlot()
    Device C -> Root Device: report_status_LK() -> Return
  alt [default]:
    Root Device: send_msg(C)
  [Key Slot invalidated]:
    Root Device -> Device B: KeyEx.install_LKs() -> LinkLayerSec.install_key()
                              -> proofs_of_installed_LKs
    Root Device -> Device C: KeyEx.install_LKs() -> LinkLayerSec.install_key()
                              -> proofs_of_installed_LKs
```

Caption note: "(function names not binding!)"

---

## 10. LK Installation into LLS (Section 6.3.3.1)

SPEC FACT: DeviceInternal.install_key sets per slot:
- Link Key value
- Salt value
- Next TX AEAD Invocation Counter = 1
- Last RX AEAD Invocation Counter = 0

SPEC FACT (Section 6.4.3.12): If no slot is active, first slot with a key is
activated. If both slots written in same call, slot 0 = Active, slot 1 = Ready.

Salt size: SPEC FACT (Section 6.4.3.12 LKs_Salts format): "Size_Salts [uint8] -- the
number of bytes per salt. Always 4 for AES." Salt bits[29:0] used (30 bits of 32).

---

## 11. Interfaces

### 11.1 OAM Control Plane Interface

| Signal | Dir | Description |
|--------|-----|-------------|
| keyex_oam_rx(cmd, id, params) | OAM->KeyEx | Received KeyEx OAM message (cmd 0x7C) |
| keyex_oam_tx(cmd, id, params) | KeyEx->OAM | KeyEx response (cmd 0x7D) |

SPEC FACT: Each KeyEx OAM message occupies an exclusive OAM frame (CADnext=0).
All fields in Big Endian. Status Code in Parameters byte 0 of response.

### 11.2 Link Layer Security Interface

| Signal | Dir | Description |
|--------|-----|-------------|
| install_key(slot, key, salt) | KeyEx->LLS | DeviceInternal.install_key |
| report_status_trigger(slot, margin) | LLS->KeyEx | IV overflow notification |

SPEC FACT (Section 6.3.5): LLS primitives are NOT accessible through OAM. Only
DeviceInternal.install_key is the bridge from KeyEx to LLS.

### 11.3 Register Model Interface

| Signal | Dir | Description |
|--------|-----|-------------|
| security_policy_rd[1:0] | Reg->KeyEx | Read securityPolicy (3.0001) |
| security_policy_wr[1:0] | KeyEx->Reg | Write policy via setup_policy (0x08) |

### 11.4 Error/Status Outputs

| Signal | Dir | Description |
|--------|-----|-------------|
| keyex_status[7:0] | KeyEx->OAM | Status code for current primitive response |
| iv_overflow_alert | LLS->KeyEx | Threshold / overflow alert |

---

## 12. Suggested RTL Module Boundaries

```
+================================================================+
|                       keyex_top                                  |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | keyex_oam_dispatcher|    | key_hierarchy_mgr   |             |
|  |                     |    |                     |             |
|  | Parse cmd 0x7C/0x7D |    | UUID storage        |             |
|  | Route to primitives |    | DK_0, DK_1 storage  |             |
|  | Format response     |    | DK = XOR compute    |             |
|  +---------------------+    | BK storage          |             |
|                             | Access control      |             |
|                             +---------------------+             |
|  +---------------------+    +---------------------+             |
|  | key_slot_controller |    | iv_builder (KeyEx)  |             |
|  |                     |    |                     |             |
|  | Two slots per link  |    | Bit-exact 96-bit IV |             |
|  | Empty/Ready/Active/ |    | KeyEx=1, Dir, Salt  |             |
|  | Deactivated states  |    | PCN, AEAD counter   |             |
|  | TX/RX independent   |    +---------------------+             |
|  +---------------------+                                        |
|  +---------------------+    +---------------------+             |
|  | aead_keyex_pipeline |    | install_flow_ctrl   |             |
|  |                     |    |                     |             |
|  | AES-GCM for all     |    | install_UUID        |             |
|  | KeyEx messages      |    | install_DK_0/1      |             |
|  | IV validation       |    | install_BK          |             |
|  | ICV verify/generate |    | install_LKs         |             |
|  | Big Endian ICV order|    | change_KeySlot      |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | status_reporter     |    | overflow_monitor    |             |
|  |                     |    |                     |             |
|  | read_status_keys    |    | Track TX counter    |             |
|  | read_status_ext     |    | 10%/5% thresholds   |             |
|  | Status_LKs struct   |    | Overflow deactivate |             |
|  | report_status_LK    |    | Trigger 0x81 report |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | proof_verifier      |    | pcn_generator       |             |
|  |                     |    |                     |             |
|  | Check proofs from   |    | Generate PCN at     |             |
|  | device responses    |    | power-on            |             |
|  | Root-side only      |    | Read via 0x04       |             |
|  +---------------------+    +---------------------+             |
+================================================================+
```

---

## 13. Spec Facts vs Implementation Assumptions

### Spec Facts
- KeyEx Entity at root is in Root ECU Software, not in ASA chip
- KeyEx IV[95] = 1 (distinguishes from LLS IV where bit 95 = 0)
- KeyEx IV exact packing: [95]=KeyEx, [94]=Dir, [93:64]=Salt(30bit), [63:32]=PCN, [31:0]=InvocationCounter
- AES-GCM mandatory for KeyEx; AES-GMAC not used for KeyEx
- ICV in Big Endian, field order = primitive field order
- PCN generated at power-on, read via primitive 0x04
- LK Salt = 4 bytes, bits [29:0] used
- Key slot states: Empty(00), Ready(01), Active(11), Deactivated(10)
- Status_LKs: 2 bits per (slot, direction) pair within one byte
- IV overflow thresholds: 10% and 5% trigger report_status_LK
- Upon counter maximum: deactivate slot, switch to other, report
- install_LKs: slot 0 Active, slot 1 Ready if both written in one call
- DeviceInternal.install_key sets counters: TX counter=1, RX counter=0
- Primitives with even ID = unprotected; odd = protected

### Implementation Assumptions
- PCN is a random number generated at power-on (spec says "generated at start of
  power cycle" but does not specify the generation mechanism)
- The KeyEx AEAD Invocation Counter (root-side TX counter) starts at 1 and is
  distinct from the LLS TX AEAD Invocation Counter
- Key slot state transitions not mapped to a formal FSM in the spec; transitions
  are inferred from primitive behavior descriptions
- Salt = 4 bytes but only bits[29:0] used; bits[31:30] of the Salt field in the IV
  are effectively 0 (30 bits of 32 used per 6.4.3.12)
- proof_verifier is root-side only; non-root devices do not verify proofs from other
  devices

---

## 14. Verification Plan

| Test | Stimulus | Expected Outcome |
|------|----------|-----------------|
| DK_0 install | install_DK_0_unencrypted(0x10) | DK_0 stored, status 0x00 |
| DK_0 second write | install_DK_0_unencrypted again | Return 0x20 (already written) |
| DK_1 unencrypted | install_DK_1_unencrypted(0x12) | DK_1 stored, status 0x00 |
| DK_1 encrypted | install_DK_1_encrypted(0x13) | Verify ICV using DK_0, install |
| BK install | install_BK_encrypted(0x21) | Verify ICV using DK, install BK |
| read UUID before write | read_UUID(0x02) | UUID = 0 |
| install UUID | install_UUID(0x00) | UUID stored, status 0x00 |
| install UUID again | install_UUID again | Return 0x20 |
| read nonce | read_current_nonce(0x04) | Returns PCN |
| LK install, cold start | install_LKs_encrypted(0x31) | IV check, ICV check, install, slot 0=Active |
| LK install, both slots | install_LKs for two nodes | Slot 0=Active, slot 1=Ready |
| LK status read | read_status_keys(0x06) | Returns Status_LKs, Status_DK_BK |
| LK status ext | read_status_keys_ext(0x07) | Secured response with TX IV counters |
| change key slot | change_LKs_KeySlot(0x33) | New slot becomes Active, old Deactivated |
| report status 10% | TX counter at 90% of range | Device sends report_status_LK(0x81) |
| report status 5% | TX counter at 95% of range | Device sends report_status_LK again |
| overflow reached | TX counter at max | Slot deactivated, switch, report |
| IV replay rejected | Re-send old IV value | Device drops, returns 0x11 |
| wrong UUID | install_LKs with wrong UUID | Device drops, returns 0x12 |
| bad ICV | install_LKs with corrupted ICV | Device drops, returns 0x11 |
| DK_1 missing on BK install | install_BK before DK_1 | Returns 0x41 |

---

## 15. Remaining Uncertainties

1. **PCN = Power Cycle Counter vs Power Cycle Nonce**: Section 6.4.3.3 calls it
   "Power Cycle Nonce" but the IV field in Section 6.4.1.4 says "Power Cycle Counter
   as defined by the Root Device." The relationship between the device-generated
   nonce (read via 0x04) and the root-defined counter in the IV is not fully
   resolved. VERIFY if PCN from 0x04 is used verbatim as IV[63:32] or if the root
   maps/transforms it.

2. **Salt bit usage in KeyEx IV**: Section 6.4.3.12 says "use bits [29:0] to install
   as Salt." Section 6.4.1.4 gives IV[93:64] = Salt (30 bits). This is consistent,
   but the spec does not state what goes in IV[93:64] if the Salt field is wider than
   30 bits in any other context. VERIFY no other primitive uses a wider salt.

3. **Root-side KeyEx AEAD Invocation Counter init and management**: Section 6.4.4.5
   says "Root Node shall initialize its KeyEx AEAD Invocation Counter used for
   creating the IV of outgoing KeyEx messages with 1." Whether this counter persists
   within a power cycle or resets per OAM session is not specified.

4. **Overflow threshold computation**: "Margin to overflow drops below 10%/5%" is
   defined relative to the 64-bit invocation counter max value. The exact threshold
   values (10% and 5% of 2^64) are large; whether implementations use approximations
   (e.g. top few bits) is not specified.

5. **change_LKs_KeySlot (0x33) vs automatic slot switching**: The spec defines
   primitive 0x33 for explicit slot change. Section 6.4 also describes automatic
   slot switching when overflow occurs. Whether 0x33 is the normative mechanism for
   rotation (or just an auxiliary) needs VERIFY against the full flow.

6. **report_status_LK (0x81) ICV key**: Table 6-31 (Request) says key=BK; Table 6-32
   (Response from Root) says key=LK (new LK in new key slot). VERIFY this asymmetry
   is intentional and trace through the response generation flow.

7. **Non-root KeyEx Entity scope**: For a branch device, the KeyEx Entity is "at the
   ASA Device itself." Whether a branch device runs the same primitives as a leaf
   device, or whether it acts as a relay for further downstream devices, is not
   fully specified for multi-hop branch topologies.
