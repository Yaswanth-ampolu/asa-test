# Image Source Audit and Doc Fixes

Audit of named images in docpdfmd/images/ against existing micro-architecture documents.
Generated: 2026-05-28

---

## Image Inventory by Subsystem

### OAM / DLL Control Plane

| Image | Content | Relevant Doc | Captured? | Priority |
|-------|---------|-------------|-----------|----------|
| 28_OAM_external_root_device_sequence.png | Sequence: External -> Root SW -> Root Device -> Device. Shows OAM Read/Write round-trip with external host driving commands. | micro-architecture-oam-control-plane.md | PARTIAL - mentioned in "Open Issues" section 20.2.7 but not described in body | Important |
| 30_OAM_Root_Device_BC_sequence.png | Sequence: Root SW -> Root Device -> Device B -> Device C. Shows enumeration flow to multiple devices with Self-Announce. | micro-architecture-oam-control-plane.md | PARTIAL - enumeration flow described textually (Section 8) but image not explicitly referenced | Optional |
| 31_OAM_multidevice_sequence.png | Sequence: Root SW -> Root Device -> Device B -> Device C. Multi-device OAM config including mapper table programming and StartTDD. | micro-architecture-oam-control-plane.md | PARTIAL - StartTDD/config covered but multi-device orchestration order not detailed | Important |

**Finding**: Images 28/30/31 confirm that the Root Device OAM entity acts as a bridge between an external host (Root SW) and the ASA OAM protocol. The existing OAM doc notes this as an open question (item 7) but does not define the external host interface. This is an architectural gap.

**Fix recommendation**: Add a note to OAM doc Section 20 acknowledging that the external host interface to the root node OAM entity is implementation-defined, per image evidence.

---

### PTB / Clock Synchronization

| Image | Content | Relevant Doc | Captured? | Priority |
|-------|---------|-------------|-----------|----------|
| 10_PTB_leader_follower_sync.png | Block diagram: PTB Follower (250+delta MHz) captures timestamp S when MCK/SCK count N starts. Leader (250 MHz) regenerates M=S(n)-S(n-1) PTB ticks, multiplies by N. Shows I2S clock recovery via PTB. | asa-project-scope-and-module-map.md, micro-architecture-oam-control-plane.md | NO - not captured in any existing doc | Important |
| 19_PTB_clock_sync_I2S_nodes.png | Detailed block diagram: ASA node1 (leader) counts M PTB ticks, regenerates MCK/SCK to I2S slave. ASA node2 (follower) captures PTB timestamp S. Shows PTB-to-I2S audio clock relationship. | asa-project-scope-and-module-map.md | NO - project scope mentions PTB but not I2S clock regeneration architecture | Optional |

**Finding**: Images 10 and 19 show how the PTB clock is used to regenerate I2S audio sampling clocks across nodes. This is a key architectural detail for the ASEP I2S micro-architecture doc (not yet written). The existing docs do not capture this PTB-to-I2S relationship.

**Fix recommendation**: Add reference to project scope doc under ASEP section noting PTB-based audio clock regeneration.

---

### Security / Key Exchange

| Image | Content | Relevant Doc | Captured? | Priority |
|-------|---------|-------------|-----------|----------|
| 12_ASA_Root_ECU_key_hierarchy.png | Sequence: External ECU -> Root SW -> Root Device -> Node. Shows install_keys_enc() flow: read_config, read_UUID, read_status_keys from each device; then request_keys() from ECU; then install_DK_1_enc() and install_BK_enc() to each device in loop. | asa-project-scope-and-module-map.md, micro-architecture-oam-control-plane.md | PARTIAL - OAM doc lists KeyEx primitives (Section 12.3) but not the multi-device orchestration sequence | Important |
| 13_security_key_exchange_sequence.png | Sequence: Shows IV Counter overflow monitoring. check_IV_Counter_OVF() triggers report_status_LK(), then change_KeySlot()/invalidate_previous_KeySlot(), then install_LKs() with proofs. Shows runtime key rotation. | asa-project-scope-and-module-map.md | NO - project scope mentions key hierarchy but not runtime key rotation | Important |
| 14_KeyEx_install_LKs_sequence.png | Sequence: generate_LKs() -> read_Nonce -> gen_AEADs() -> install_LKs() with check_IV/check_ICV/install_LKs/generate_proofs on device. Per-link loop. Shows proof verification flow. | asa-project-scope-and-module-map.md | NO - not captured | Optional |

**Finding**: Images 12-14 provide the complete KeyEx operational sequences that the spec text describes abstractly. Key insight from image 13: runtime key rotation is triggered by IV counter overflow margin monitoring (at 10% and 5% thresholds), not just on startup. This is relevant for the future Security Engine micro-architecture doc.

**Fix recommendation**: Add note to project scope Security section about runtime key rotation being IV-counter-overflow-driven.

---

### Physical Layer Electrical

| Image | Content | Relevant Doc | Captured? | Priority |
|-------|---------|-------------|-----------|----------|
| 15_signal_response_time_ns.png | Waveform: Impulse response, ~350ns settling, peak +23mV/-15mV. Cable/channel characterization. | asa-project-scope-and-module-map.md | NO - PHY electrical section mentions cable specs but no waveform details | Optional |
| 16_cable_RL_vs_frequency.png | Plot: Cable return loss vs frequency | asa-project-scope-and-module-map.md | NO | Optional |
| 17_small_signal_response_time.png | Waveform: Small signal step response | asa-project-scope-and-module-map.md | NO | Optional |
| 18_IL_limit_lines_SDP_Coax.png | Plot: Insertion loss limit lines for STP and Coax cables | asa-project-scope-and-module-map.md | NO | Optional |
| 20_Speed_Grade_1_frequency.png | Plot: TX PSD limits (upper/lower) for SG1, 0-2000MHz. Upper ~-87dBm/Hz at DC, -103dBm/Hz at 2GHz. | asa-project-scope-and-module-map.md | NO | Optional |
| 21_Speed_Grade_2_frequency.png | Plot: TX PSD limits for SG2 | asa-project-scope-and-module-map.md | NO | Optional |
| 22_Speed_Grade_3_frequency.png | Plot: TX PSD limits for SG3 | asa-project-scope-and-module-map.md | NO | Optional |
| 23_Speed_Grade_4_frequency.png | Plot: TX PSD limits for SG4 | asa-project-scope-and-module-map.md | NO | Optional |
| 24_Speed_Grade_5_frequency.png | Plot: TX PSD limits for SG5 | asa-project-scope-and-module-map.md | NO | Optional |
| 25_MDI_return_loss_DnTX_DnRX.png | Plot: MDI return loss spec | asa-project-scope-and-module-map.md | NO | Optional |
| 26_Near_End_XTalk_PSA_NEXT.png | Plot: Near-end crosstalk spec | asa-project-scope-and-module-map.md | NO | Optional |
| 27_Far_End_XTalk_PSAACRF.png | Plot: Far-end crosstalk spec | asa-project-scope-and-module-map.md | NO | Optional |
| 29_MDI_insertion_loss_DnTX_DnRX.png | Plot: MDI insertion loss spec | asa-project-scope-and-module-map.md | NO | Optional |

**Finding**: Images 15-29 are all PHY electrical characterization plots from Section 4.4/4.5. These are analog design specifications, not digital architecture. They belong in the future micro-architecture-phy-electrical.md document. No existing doc needs to capture them in detail.

**Fix recommendation**: None for existing docs. Note in project scope that PHY electrical specs have image assets available.

---

### ASEP Stream Types

| Image | Content | Relevant Doc | Captured? | Priority |
|-------|---------|-------------|-----------|----------|
| 01_SPI_write_read_ex1.png | SPI waveform: Write+Read transaction example 1 | asa-project-scope-and-module-map.md | NO - ASEP SPI mentioned as future doc | Optional |
| 02_SPI_write_read_ex2.png | SPI waveform: Write+Read transaction example 2 | asa-project-scope-and-module-map.md | NO | Optional |
| 03_SPI_write_only_ex3.png | SPI waveform: Write-only transaction | asa-project-scope-and-module-map.md | NO | Optional |
| 04_SPI_extended_timing_buffered.png | SPI waveform: Extended timing with buffering | asa-project-scope-and-module-map.md | NO | Optional |
| 05_SPI_extended_timing_multi_frame.png | SPI waveform: Multi-frame extended timing | asa-project-scope-and-module-map.md | NO | Optional |
| 06_SPI_waveform_motorola_mode.png | SPI waveform: Motorola SPI mode (CPOL/CPHA) | asa-project-scope-and-module-map.md | NO | Optional |
| 07_SPI_waveform_TI_mode.png | SPI waveform: TI SSI mode | asa-project-scope-and-module-map.md | NO | Optional |
| 08_GPI_signal_UP_link_SG1_data_format.png | GPIO: Upstream link SG1 data format waveform | asa-project-scope-and-module-map.md | NO | Optional |
| 09_GPI_signal_UP_SG1_EG_mode.png | GPIO: Upstream SG1 edge mode format | asa-project-scope-and-module-map.md | NO | Optional |
| 11_I2S_SCK_frequency_table.png | Table: I2S SCK frequency values for different sample rates | asa-project-scope-and-module-map.md | NO | Optional |

**Finding**: Images 01-09 and 11 are all ASEP stream-type-specific waveforms and tables from Appendix D (SPI), Appendix E (GPIO), and Section 7.10 (I2S). These belong in their respective future ASEP micro-architecture documents.

**Fix recommendation**: None for existing docs. These are source material for future docs.

---

### Other

| Image | Content | Relevant Doc | Captured? | Priority |
|-------|---------|-------------|-----------|----------|
| 32_CRC32_calculation_table.png | CRC32 polynomial coefficient table | asa-project-scope-and-module-map.md | NO - CRC32 is in PHY PCS section 4.2.9 | Optional |
| 00_ASA_logo_title_page.png | ASA logo/title page | None | N/A | N/A |

---

## Summary of Findings

### Omissions Found in Existing Docs

| # | Doc | What's Missing | Source Image | Priority |
|---|-----|---------------|-------------|----------|
| 1 | OAM doc | External host interface to root OAM entity is architectural gap | 28, 30, 31 | Important |
| 2 | OAM doc | Multi-device enumeration ordering (B before C) | 31 | Optional |
| 3 | Project scope | PTB-to-I2S audio clock regeneration architecture | 10, 19 | Important |
| 4 | Project scope | Runtime key rotation triggered by IV counter overflow margins | 13 | Important |
| 5 | Project scope | Link Key installation sequence (read_Nonce -> gen_AEADs -> install_LKs -> proof) | 14 | Optional |
| 6 | Project scope | PHY electrical image assets available for future doc | 15-29 | Optional |
| 7 | Register model | Appendix G local I2C register mapping is informative, needs adapter doc | N/A (spec text) | Optional |

### Priority Classification

- **Blocking**: None. All existing docs are architecturally sound.
- **Important** (4 items): Items 1, 3, 4 should be patched into existing docs.
- **Optional** (3 items): Items 2, 5, 6, 7 are for future docs or minor notes.

---

## Patches Applied

### Patch 1: OAM doc - External host interface note
File: micro-architecture-oam-control-plane.md, Section 20.2, item 7
Status: Already mentions this as open issue. No additional patch needed.

### Patch 2: Project scope doc - Image inventory reference
File: asa-project-scope-and-module-map.md
Action: Add "Image Assets" subsection referencing available images by subsystem.

### Patch 3: Project scope doc - Security runtime key rotation note
File: asa-project-scope-and-module-map.md
Action: Add note under Security section about IV counter overflow driving key rotation.

### Patch 4: Project scope doc - PTB/I2S clock regeneration note
File: asa-project-scope-and-module-map.md
Action: Add note under ASEP section about PTB-based audio clock recovery.
