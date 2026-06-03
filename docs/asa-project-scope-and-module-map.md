# ASA v2.0 Project Scope and Module Map

Source: ASA Technical Specification v2.0 (351 pages)
Structured extraction: 594 chunks, 65 register chunks, 8 modules
Generated from: pipeline/out/asa_structured_chunks.jsonl

---

## 1. System Overview and State Diagrams

### Purpose
Defines the overall ASA transceiver architecture: layer stack, node/device/branch
topology, port primitives, and the global state machine governing node lifecycle.

### Key PDF Sections
| Section | Title | Pages |
|---------|-------|-------|
| 1.3 | Glossary (Node, Device, Link, Branch, Root, Leaf) | 22-23 |
| 2.1 | ASA Layers Stack | 25 |
| 2.2 | Physical Layer Port / Data Link Layer Port | 26 |
| 2.3 | Features Overview | 26 |
| 2.4 | ASA Transceiver State Diagram | 27-28 |

### Major Sub-blocks
- ASA Node state machine (PowerOn/Init, Startup, OAM Config, Normal, Test,
  Light Sleep, Fail, Deep Sleep)
- PLP_TX / PLP_RX (Physical Layer Port primitives)
- DLP_TX / DLP_RX (Data Link Layer Port primitives)
- Half-duplex TDD timing structure

### Inputs/Outputs/Interfaces
- PLP_TX: DLL -> PHY (dataUnit, nextPhyBlock, PCSreset, startup, lightSleep)
- PLP_RX: PHY -> DLL (dataUnit, linkLoss, linkFail)
- DLP_TX: ASE/OAM -> DLL (indicateSlot, dataUnit, oamUnit, yield)
- DLP_RX: DLL -> ASD/OAM (dataUnit, forwardUnit, oamUnit)

### Registers / Control Hooks
- ASAnodeState (1.0006): current state [2:0]
- ASAnodeIRQ (1.0008): interrupt flags
- SoftReset (1.0007): state machine reset

### Dependencies
- All other modules depend on this state machine for lifecycle transitions
- OAM Config state required before Normal Mode
- Startup phases gate PHY/DLL initialization

### Mandatory / Optional / Implementation-Dependent
- State machine: MANDATORY
- State transitions: MANDATORY (exact values per spec)
- Deep Sleep: OPTIONAL

### Micro-Architecture Docs Needed
- [x] micro-architecture-register-model.md (contains state definitions)
- [ ] micro-architecture-node-state-machine.md (full FSM with transitions, timers)

---

## 2. Registers (Section 3)

### Purpose
Defines the entire ASA register map: addressing model (d.a / d.i.a / d.a.(m:l)),
access control (RW/RO/SC, L/O, RID/A), and per-register bit-field definitions for
all six address domains.

### Key PDF Sections
| Section | Title | Pages |
|---------|-------|-------|
| 3.1 | User Registers (Domain 0) | 30 |
| 3.2 | PMA/PMD/PCS Registers (Domain 1) | 31-44 |
| 3.3 | DLL Registers (Domain 2) | 45-64 |
| 3.4 | Security Registers (Domain 3) | 65-66 |
| 3.5 | ASEP Registers (Domains 4/5) | 67-86 |
| 3.6 | ASE-Specific Registers | 86-91 |
| 3.7 | ASD Registers | 91-92 |

### Major Sub-blocks
- Domain 0: User registers (implementer-defined)
- Domain 1: PHY/PMA/PCS (1.0001-1.0108) -- capabilities, config, status, link training
- Domain 2: DLL (2.0001-2.2256) -- addressing table, mapper, demux, PTB, OAM errors, Light Sleep
- Domain 3: Security (3.0001-3.0003) -- policy, dropped counters
- Domain 4: ASE per-DLP (4.i.xxxx) -- stream config, I2C/SPI/GPIO/I2S/eDP specific
- Domain 5: ASD per-DLP (5.i.xxxx) -- status, watchdog

### Inputs/Outputs/Interfaces
- Local register interface (from host CPU / test port)
- OAM CAD Read/Write bridge (from OAM entity via Section 5.5.3)
- Internal decoded address bus: domain[2:0], subdomain_dlp_id[5:0],
  register_addr[14:0], bit_m[3:0], bit_l[3:0], has_bit_select, write_data[15:0]

### Key Registers (65 defined in structured extraction)
- 1.0001-1.0008: Capabilities, config, state, reset, IRQ
- 1.0020-1.0022: MLE capability/config
- 1.0100-1.0108: Link training, quality, SQI, MSE, FEC, diagnostics
- 2.0001-2.0007: NodeID, DLLconfig, VendorID, DeviceID
- 2.0008-2.0133: Addressing table (126 entries)
- 2.0146-2.2065: Mapper table (1920 entries)
- 2.2067-2.2146: Demux tables 1 and 2
- 2.2200-2.2212: PTB, OAM errors, DLL errors
- 2.2250-2.2256: Light Sleep registers
- 3.0001-3.0003: Security policy, dropped counters
- 4/5.i.0001-0062: Common ASEP, pin capability/config
- 4/5.i.0200+: Stream-type-specific (I2C, SPI, GPIO, I2S)

### Dependencies
- Used by ALL other modules for configuration and status reporting
- OAM entity is the remote access path (Section 5.5.3)
- Side-effect engine needed for SC (self-clearing) registers

### Mandatory / Optional / Implementation-Dependent
- Domain 0: IMPLEMENTATION-DEPENDENT (size and content)
- Domain 1 base: MANDATORY (1.0001-1.0008)
- Domain 1 extended: depends on features (FEC, link training, diagnostics)
- Domain 2 base: MANDATORY
- Domain 2 mapper/demux size: depends on speed grade and DLP count
- Domain 3: OPTIONAL (only if Security present)
- Domain 4/5: depends on implemented ASEP stream types and DLP count

### Micro-Architecture Docs
- [x] micro-architecture-register-model.md (done, 886 lines)
- [ ] register_catalog.json (machine-readable format for RTL generation)

---

## 3. Physical Layer Gen2020 (Section 4)

### Purpose
Defines the baseline physical layer: PCS (coding, FEC, scrambling), PMA (electrical,
startup state machines), PMD (cable/connector), TDD burst timing, and PTB clock
synchronization. "Gen2020" refers to the original ASA speed grades (SG1-SG5).

### Key PDF Sections
| Section | Title | Pages |
|---------|-------|-------|
| 4.2 | PCS Functions | 95-120 |
| 4.2.2 | PCS Transmit (TDD burst, resync header, FEC, scrambler) | 95-109 |
| 4.2.3 | PCS Receive (burst sync, descrambler, FEC decode) | 104 |
| 4.2.4 | RS-FEC encoder definition | 104-106 |
| 4.2.5 | Side-Stream Scrambler Polynomial | 107 |
| 4.2.7 | Startup and PMA Training Sequence | 109-115 |
| 4.2.8 | Precision Time Base (PTB) | 116-120 |
| 4.3 | PMA Sublayer | 121-134 |
| 4.3.3 | Startup State Diagrams | 122-134 |
| 4.4 | PMA Electrical Parameters | 135-147 |
| 4.5 | Cable/MDI Specifications | 147-155 |
| 4.6 | PLP_TX Interface | 156-157 |
| 4.7 | PLP_RX Interface | 157-158 |
| 4.8 | Link Aggregation Sublayer (optional) | 158-161 |

### Major Sub-blocks
- PCS Transmit: scrambler, RS-FEC encoder, PAM2/PAM4 mapping, TDD burst assembly
- PCS Receive: burst sync, descrambler, RS-FEC decoder, CRC32 check
- Resync Header: sync sequence, PRBS11, dithering, PTB message vector
- RS-FEC: (108,106), (216,214), (240,214) depending on speed grade
- PMA Startup: Phase1G, PhaseSGA, PhaseSGB, PhaseSGC state machines
- PTB: Clock leader/follower, Follow/DelayRequest/DelayReply protocol
- PMA Electrical: TX/RX specs per speed grade, test modes
- PMD: Cable harness (STP/Coax), insertion loss, return loss, crosstalk, MDI
- Link Aggregation: optional multi-link bonding sublayer

### Inputs/Outputs/Interfaces
- PLP_TX primitives: dataUnit, nextPhyBlock, PCSreset, startup, lightSleep
- PLP_RX primitives: dataUnit, linkLoss, linkFail
- PTB interface to OAM header (PTBclk copied into OAM frame at TX time)
- Startup info field exchange between nodes

### Registers / Control Hooks
- SGconfig (1.0002): speed grade selection
- MLEcapability1/2 (1.0020, 1.0021): MLE mode support
- MLEconfig (1.0022): active MLE mode
- LinkTraining (1.0100): training control
- LinkQuality (1.0101): received link quality
- SQI (1.0102): signal quality indicator
- MSE (1.0103): mean square error
- FECstat (1.0104): FEC correction count
- PTBclk (2.2200-2.2202): 48-bit PTB clock
- PTBstatus (2.2203): lock state, delay valid

### Dependencies
- DLL depends on PHY for container transport (PLP primitives)
- OAM depends on PHY startup completing before config phase
- PTB synchronization depends on OAM header carrying PTBclk
- Light Sleep re-uses startup phases for wake-up

### Mandatory / Optional / Implementation-Dependent
- PCS/PMA base (SG1 minimum): MANDATORY
- Speed grades 2-5: OPTIONAL (feature-dependent)
- RS-FEC: MANDATORY for each supported speed grade
- PTB: MANDATORY
- Link Aggregation: OPTIONAL
- Test modes: MANDATORY for compliance

### Micro-Architecture Docs Needed
- [ ] micro-architecture-phy-pcs-datapath.md (scrambler, FEC, burst assembly)
- [ ] micro-architecture-phy-startup-fsm.md (Phase1G/SGA/SGB/SGC state machines)
- [ ] micro-architecture-ptb-clock.md (PTB follower FSM, offset/delay calculations)
- [ ] micro-architecture-phy-electrical.md (PMA analog specs, test fixtures)

---

## 4. Data Link Layer (Section 5)

### Purpose
Defines container-based packet transport: TDD multiplexing via mapper, demultiplexing
via addressing/forwarding tables, OAM control plane, Light Sleep negotiation, and
DLP port primitives.

### Key PDF Sections
| Section | Title | Pages |
|---------|-------|-------|
| 5.1 | Overview | 162 |
| 5.2 | DLL Transmit Functions | 163-166 |
| 5.2.2 | Header Generation & Addressing | 164-165 |
| 5.2.3 | Mapping/Multiplexing | 165-166 |
| 5.3 | DLL Receive Functions | 167-168 |
| 5.3.2 | Header Decoding & Demultiplexing | 167-168 |
| 5.4 | Forwarding Fabric | 169-170 |
| 5.5 | OAM | 171-184 |
| 5.6 | DLP_TX Interface | 185-187 |
| 5.7 | DLP_RX Interface | 187-188 |
| 5.8 | Light Sleep | 189-192 |
| 5.9 | DLL Startup, OAM Config | 193 |

### Major Sub-blocks
- Mapper (TX scheduler): deterministic cyclic TDM, 1920-entry table (2.0146-2.2065)
- Header generator: HeaderType, ExtendedID, targetID, packetID
- Demultiplexer: addressing table (2.0008-2.0133), dmx table 1 (2.2067-2.2130),
  dmx table 2 (2.2131-2.2146)
- Forwarding Fabric (FoFa): normal mode and enumerate mode routing
- OAM entity: frame-based control protocol (Section 5.5)
- Light Sleep FSM: LSannounce/LSconfirm/LSdeny/LSsleep negotiation
- DLP_TX port interface (up to 64 ports)
- DLP_RX port interface (up to 64 ports)

### Inputs/Outputs/Interfaces
- PLP_TX / PLP_RX: to/from Physical Layer
- DLP_TX (up to 64): indicateSlot, dataUnit, oamUnit, yield, oamFrameLocal, forwardUnit
- DLP_RX (up to 64): dataUnit, forwardUnit, oamUnit
- OAM is always DLP_TX_ID=0 / DLP_RX_ID=0
- Security entity interface (SecCoP/SIF) for link-layer encryption

### Registers / Control Hooks
- NodeID (2.0001): local node address
- DLLconfig1/2 (2.0002, 2.0003): DLL configuration
- DLLaddrtable (2.0008-2.0133): 126-entry addressing table
- DLLmappertable (2.0146-2.2065): 1920-entry mapper
- DLLdmxtable1/2: demux routing
- DLLcounter/min/max (2.0141-2.0145): mapper scheduling limits
- DLLtransmitErr (2.0140): TX error counter
- PTBclk (2.2200-2.2202): 48-bit clock
- PTBstatus (2.2203): PTB lock state
- OAMerrors1/2 (2.2208, 2.2209): OAM decode errors
- DLLerrors1/2 (2.2210, 2.2211): DLL header/FoFa errors
- LightSleep registers (2.2250-2.2256): LS capability, status, test

### Dependencies
- Depends on PHY (PLP primitives) for container transport
- OAM depends on PTB for timestamp in OAM header
- Security entity sits between DLL and crypto processing
- ASEP modules plug into DLP_TX/DLP_RX ports
- Register model provides OAM Read/Write target

### Mandatory / Optional / Implementation-Dependent
- Mapper/Demux: MANDATORY
- OAM: MANDATORY
- Forwarding Fabric: MANDATORY for branch devices, not needed for leaf-only
- Light Sleep: OPTIONAL
- Security interface: OPTIONAL (only if security feature present)
- Number of DLP ports: IMPLEMENTATION-DEPENDENT (1-64)

### Micro-Architecture Docs Needed
- [x] micro-architecture-oam-control-plane.md (this session)
- [ ] micro-architecture-dll-mapper-demux.md (scheduler, tables, header gen)
- [ ] micro-architecture-dll-forwarding-fabric.md (FoFa routing, enumerate)
- [ ] micro-architecture-light-sleep-fsm.md (negotiation, timers, wake-up)

---

## 5. Security (Section 6)

### Purpose
Defines optional link-layer security: AES-128-GCM encryption/authentication of DLL
containers, and the Key Exchange (KeyEx) protocol for provisioning device keys,
binding keys, and link keys.

### Key PDF Sections
| Section | Title | Pages |
|---------|-------|-------|
| 6.2 | Keys and IDs | 194-196 |
| 6.2.1-6.2.5 | Key lengths, Device Keys, Binding Keys, Link Keys, UUIDs | 195-196 |
| 6.3 | Link Layer Security | 196-203 |
| 6.3.1 | Algorithms (AES-128-GCM), IV construction, container format | 196-198 |
| 6.3.2 | Link Layer Security Primitives | 198-200 |
| 6.3.3 | Private Device-Internal Primitives | 200 |
| 6.3.4 | Process incoming/outgoing message | 200-202 |
| 6.3.5 | Mapping Primitives to OAM (NOT accessible via OAM) | 203 |
| 6.4 | Key Exchange (KeyEx) | 203-229 |
| 6.4.1 | General Concepts, IV, AEAD, ICV, status codes | 203-205 |
| 6.4.2 | Mapping of KeyEx Primitives to OAM messages | 205-206 |
| 6.4.3 | KeyEx Primitives (install_UUID, read_UUID, etc.) | 206-224 |
| 6.4.4 | Key Exchange Phases (informational) | 225-229 |

### Major Sub-blocks
- Link Layer Security Engine: AES-128-GCM encrypt/decrypt per container
- IV Construction: nonce + counter based
- Container format: Counter field + payload + ICV (authentication tag)
- Key Exchange Entity: handles 14 primitives (install_UUID, read_UUID,
  read_current_nonce, read_status_keys, setup_policy, install_DK, install_BK,
  install_LKs, change_LKs_KeySlot, report_status_LK)
- Key hierarchy: Device Key Tier-0 -> Device Key Tier-1 -> Binding Key -> Link Keys
- KeyEx OAM bridge: maps KeyEx primitives to OAM CAD (cmd 0x7C request, 0x7D response)

### Inputs/Outputs/Interfaces
- SecCoP / SIF: interface to DLL (process_transmit_container, return_processed_tx_container,
  process_receive_container, return_processed_rx_payload, error_handler)
- DeviceInternal.install_key: private key installation
- OAM KeyExMsg: KeyEx requests/responses transported exclusively in OAM frames
- Security registers (Domain 3): securityPolicy, dropped counters

### Registers / Control Hooks
- securityPolicy (3.0001): RO, L-only, RID -- security enable/status
- droppedContainersSecRX (3.0002): dropped RX container counter
- droppedContainersSecTX (3.0003): dropped TX container counter

### Dependencies
- DLL provides container transport and OAM channel for KeyEx messages
- KeyExMsg is always the only CAD in an OAM frame (exclusive container)
- Link Layer Security primitives NOT accessible via OAM (6.3.5)
- PTB not directly used by security, but encrypted containers carry counter

### Mandatory / Optional / Implementation-Dependent
- Entire Security module: OPTIONAL
- If present: AES-128-GCM algorithm MANDATORY
- Key hierarchy structure: MANDATORY if security present
- Key slot count: IMPLEMENTATION-DEPENDENT

### Micro-Architecture Docs Needed
- [ ] micro-architecture-security-engine.md (AES-GCM datapath, IV/counter, key slots)
- [ ] micro-architecture-keyex-entity.md (KeyEx FSM, primitive handling, OAM bridge)

---

## 6. ASEP - Application Stream Encapsulation Protocol (Section 7)

### Purpose
Defines how application data (video, I2C, SPI, GPIO, eDP, I2S, Ethernet, TestDummy)
is encapsulated into DLL containers for transport over the ASA link. Each stream type
has its own packet format, configuration mode, and data mode.

### Key PDF Sections
| Section | Title | Pages |
|---------|-------|-------|
| 7.3 | Common ASEP Format Basics | 231-236 |
| 7.3.1 | Per DLL Container | 233 |
| 7.3.2 | Per Header (including PTB time stamps) | 235 |
| 7.3.3 | Per Footer | 236 |
| 7.4 | Video Data | 236-240 |
| 7.5 | I2C | 240-246 |
| 7.6 | Layer 2 Ethernet Frame | 247 |
| 7.7 | SPI | 248-256 |
| 7.8 | GPIO | 256-263 |
| 7.9 | VESA eDP | 264-276 |
| 7.10 | I2S Audio | 276-281 |
| 7.11 | TestDummy | 282-283 |

### Major Sub-blocks
- Common ASEP header/footer framing (sequence counter, PTB timestamps)
- Video ASE: line data, pixelclk, multiple pixel formats (Appendix B)
- I2C ASE: bulk mode, configuration mode, tunneled master/slave
- SPI ASE: data mode, config mode, interrupt, cycle timing
- GPIO ASE: full sampling, edge position, per-pin configuration
- eDP ASE: VESA DP encapsulation (8b10b and 128b/132b modes), AUX channel
- I2S ASE: audio sample transport, PTB-synchronized sampling
- Ethernet ASE: Layer 2 frame pass-through
- TestDummy ASE: configurable test pattern generation

### Inputs/Outputs/Interfaces
- DLP_TX: ASE provides data via DLP_TX.dataUnit when slot indicated
- DLP_RX: ASD receives data via DLP_RX.dataUnit
- Application pins: I2C SDA/SCL, SPI MOSI/MISO/CLK/CS, GPIO pins,
  eDP lanes, I2S BCLK/LRCLK/DATA
- PTB clock for timestamp synchronization

### Registers / Control Hooks
- Stream Type (4/5.i.0004): identifies encapsulation type
- Full Packet ID (4/5.i.0001-0003): 40-bit sequence counter
- Pin Capability (4/5.i.0051-0058): quad/trio/duo/single pin modes
- Pin Config (4/5.i.0059-0062): actual pin assignments
- I2C: clock rate (4/5.i.0200), slave addresses (4/5.i.0201-0208)
- SPI: config (4/5.i.0200), min idle (4/5.i.0201), timing (4.i.0210-0213)
- GPIO: sampling (4/5.i.0200), pin config (4/5.i.0201-0216)
- I2S: data format (4/5.i.0200), sample rate (4/5.i.0201), sync (4/5.i.0202-0203)
- ASE Status (4.i.0101): ASE-specific status
- ASE Test (4.i.0102), TestDummy Config (4.i.0103-0111)
- ASD Status (5.i.0100), Watchdog (5.i.0101), Status2 (5.i.0102)
- FoFa ReturnPath (4.i.0100): return OAM routing

### Dependencies
- DLL mapper assigns time slots to ASEP streams
- OAM configures stream types and mapper slots during enumeration
- PTB provides timestamps for ASEP headers (especially video, I2S)
- Security encrypts ASEP container payloads transparently

### Mandatory / Optional / Implementation-Dependent
- ASEP common framing: MANDATORY (if any ASEP stream present)
- Each stream type: OPTIONAL (application-dependent)
- Pin capability: IMPLEMENTATION-DEPENDENT (hardware)
- Number of DLP instances per stream type: IMPLEMENTATION-DEPENDENT
- TestDummy: MANDATORY for compliance testing

### Micro-Architecture Docs Needed
- [ ] micro-architecture-asep-common-framing.md (header/footer, PTB stamps)
- [ ] micro-architecture-asep-i2c.md (bulk/config mode, tunneling)
- [ ] micro-architecture-asep-spi.md (cycle timing, data/config mode)
- [ ] micro-architecture-asep-gpio.md (sampling modes, edge detection)
- [ ] micro-architecture-asep-video.md (line packing, pixel formats, pixelclk)
- [ ] micro-architecture-asep-edp.md (DP encapsulation, AUX channel)
- [ ] micro-architecture-asep-i2s.md (audio sampling, PTB sync)

---

## 7. Physical Layer MLE (Section 8)

### Purpose
Defines the Multi-Link Extension physical layer: higher-speed modes beyond Gen2020
that multiplex the link across multiple physical layer blocks per TDD burst, supporting
speeds up to 10 Gbps. Reuses Gen2020 startup but adds xMII adaptation, OAM
fragmentation, and secondary control channel.

### Key PDF Sections
| Section | Title | Pages |
|---------|-------|-------|
| 8.1 | Overview, MLE Features, Organization | 284-285 |
| 8.1.1 | MLE Features (speed modes table) | 284 |
| 8.1.3 | ASA MLE Registers | 285 |
| 8.2 | PCS Functions (MLE-specific) | 285-295 |
| 8.2.2 | TDD Burst, Resync Header (MLE differences) | 287-289 |
| 8.2.4 | RS-FEC encoder (MLE variants) | 290 |
| 8.2.7 | Startup and Training (MLE Phase1G/SGA/SGB/SGC) | 291-295 |
| 8.3 | PMA Sublayer (MLE) | 295 |
| 8.6 | Transmit Interface Adaptation Layer | 296-302 |
| 8.6.1 | xMII (rate matching, 64b/65b mapping) | 296-299 |
| 8.6.2 | OAM (frame encoding, fragmentation, CRC8) | 300-301 |
| 8.6.3 | Secondary Control Channel | 301 |
| 8.7 | Receive Interface Adaptation Layer | 302 |
| 8.8 | Link Aggregation Sublayer | 302 |

### Major Sub-blocks
- MLE PCS: similar to Gen2020 but with different scrambler polynomials per mode
- MLE speed modes: MLES_sym1G0, MLES_2G5, MLES_5G0, MLES_2G5_M, MLES_5G0_M,
  MLES_10G_M, MLES_10G_G
- xMII Adaptation Layer: maps standard MII interface to ASA TDD bursts
- Rate Matching: absorbs speed differences between xMII and PCS
- 64b/65b Mapping: for MLE modes based on SG4/5
- OAM Fragmentation: OAM frame split across physical layer blocks with 4b/5b
  encoding, SOP/EOP markers, CRC8 integrity
- Secondary Control Channel: low-rate side-channel during MLE operation

### Inputs/Outputs/Interfaces
- xMII (RGMII/SGMII-like): standard Ethernet PHY interface to host
- PLP_TX / PLP_RX: same primitives as Gen2020
- OAM frame input: same 5.5 OAM frame, 4b/5b encoded with CRC8
- PTB: same timestamping in resync header

### Registers / Control Hooks
- MLEcapability1 (1.0020): supported MLE modes bitmask
- MLEcapability2 (1.0021): extended MLE capabilities
- MLEconfig (1.0022): active MLE mode selection
- SGconfig (1.0002): base speed grade (MLE extends this)

### Dependencies
- Reuses Gen2020 startup (Phase1G) -- same state machines
- DLL is unaware of MLE vs Gen2020 (PHY presents same PLP interface)
- OAM frame format identical but encoded differently (4b/5b + CRC8)
- PTB protocol unchanged

### Mandatory / Optional / Implementation-Dependent
- Entire MLE module: OPTIONAL
- If present: at least one MLE mode MANDATORY
- xMII interface: MANDATORY if MLE present
- OAM fragmentation: MANDATORY if MLE present
- Secondary Control Channel: OPTIONAL

### Micro-Architecture Docs Needed
- [ ] micro-architecture-mle-pcs-datapath.md (MLE PCS differences from Gen2020)
- [ ] micro-architecture-mle-xmii-adaptation.md (rate matching, 64b/65b)
- [ ] micro-architecture-mle-oam-fragmentation.md (4b/5b, CRC8, SOP/EOP)

---

## 8. Appendices

### Purpose
Supplementary reference material: KeyEx status code mappings, video pixel format
tables, I2C topology examples, SPI waveform examples, GPIO data mode examples,
I2S audio sampling examples, and recommended I2C register address mapping.

### Key PDF Sections
| Section | Title | Pages |
|---------|-------|-------|
| Appendix A | KeyEx Primitive Status Code Mapping | 304 |
| Appendix B | Video ASEP Pixel Format Tables | 305-337 |
| Appendix C | I2C Topologies (informative) | 338-340 |
| Appendix D | SPI Tunneling Waveform Examples (informative) | 341-346 |
| Appendix E | GPIO Data Mode Examples (informative) | 347-348 |
| Appendix F | I2S Audio Sampling / PTB Examples (informative) | 349-350 |
| Appendix G | Recommended ASA Register -> local I2C Mapping | 351 |

### Content Types
- Appendix A: Normative -- required status code handling
- Appendix B: Normative -- pixel format encoding tables (33 pages, 8 table chunks)
- Appendix C-F: Informative -- implementation guidance
- Appendix G: Informative -- local access convenience mapping

### Dependencies
- Appendix A: used by Security/KeyEx entity
- Appendix B: used by Video ASEP encoder/decoder
- Appendix G: used by local register interface implementation

### Mandatory / Optional / Implementation-Dependent
- Appendix A: MANDATORY if security present
- Appendix B: MANDATORY if video ASEP present
- Appendix C-G: INFORMATIVE (implementation guidance only)

### Micro-Architecture Docs Needed
- No standalone doc needed; referenced by other module docs

---

## Cross-Module Dependency Map

```
                    +------------------+
                    |   Node State     |
                    |   Machine (2.4)  |
                    +--------+---------+
                             |
              +--------------+---------------+
              |              |               |
     +--------v-----+  +----v------+  +-----v--------+
     | PHY Gen2020  |  |    DLL    |  | PHY MLE      |
     | (Section 4)  |  | (Sec 5)  |  | (Section 8)  |
     +------+-------+  +----+------+  +------+-------+
            |                |                |
            +-------+--------+--------+-------+
                    |                  |
            +-------v-------+  +------v-------+
            |   OAM Entity  |  |   Security   |
            |  (Sec 5.5)    |  |   (Sec 6)    |
            +-------+-------+  +------+-------+
                    |                  |
            +-------v------------------v-------+
            |        Register Model            |
            |         (Section 3)              |
            +-------+-------+-------+----------+
                    |       |       |
          +---------+   +---+---+  +--------+
          |             |       |           |
   +------v------+ +---v---+ +-v------+ +--v-------+
   | ASEP Video  | |ASEP   | |ASEP    | |ASEP      |
   | I2C/SPI/... | |GPIO   | |eDP     | |I2S/Eth   |
   | (Sec 7.4-7) | |(7.8)  | |(7.9)   | |(7.10/7.6)|
   +-------------+ +-------+ +--------+ +----------+
```

---

## Document Status Summary

| Module | Micro-Architecture Doc | Doc Status | RTL Status | Path |
|--------|----------------------|------------|------------|------|
| Common Packages | (shared) | DONE | DONE | hw/common/rtl/ |
| Registers | micro-architecture-register-model.md | DONE | DONE | hw/register_model/rtl/ |
| Node State Machine | micro-architecture-node-state-machine.md | DONE | DONE | hw/node_fsm/rtl/ |
| OAM Control Plane | micro-architecture-oam-control-plane.md | DONE | DONE | hw/oam/rtl/ |
| PHY PCS Datapath | micro-architecture-phy-pcs-datapath.md | DONE | DONE | hw/phy_pcs/rtl/ |
| PHY Startup FSM | micro-architecture-phy-startup-training-fsm.md | DONE | DONE | hw/phy_startup/rtl/ |
| PTB Clock | micro-architecture-ptb-clock-service.md | DONE | IMPLEMENTED | hw/ptb/rtl/ |
| DLL Mapper/Demux | micro-architecture-dll-mapper-demux-core.md | DONE | DONE | hw/dll_mapper/rtl/ |
| DLL Forwarding Fabric | micro-architecture-dll-forwarding-fabric.md | DONE | DONE | hw/dll_forwarding/rtl/ |
| Light Sleep FSM | micro-architecture-light-sleep-fsm.md | DONE | DONE | hw/light_sleep/rtl/ |
| Security Engine | micro-architecture-link-layer-security.md | DONE | DONE | hw/security/rtl/ |
| KeyEx Entity | micro-architecture-keyex-entity.md | DONE | DONE | hw/keyex/rtl/ |
| ASEP Common Framing | micro-architecture-asep-common-framing.md | DONE | DONE | hw/asep/rtl/ |
| ASEP I2C | micro-architecture-asep-i2c.md | DONE | DONE | hw/asep/rtl/ |
| ASEP SPI | micro-architecture-asep-spi.md | DONE | DONE | hw/asep/rtl/ |
| ASEP GPIO | micro-architecture-asep-gpio.md | DONE | DONE | hw/asep/rtl/ |
| ASEP Video | micro-architecture-asep-video.md | DONE | DONE | hw/asep/rtl/ |
| ASEP eDP | micro-architecture-asep-edp.md | DONE | DONE | hw/asep/rtl/ |
| ASEP I2S | micro-architecture-asep-i2s.md | DONE | DONE | hw/asep/rtl/ |
| MLE PCS Datapath | micro-architecture-mle-pcs-datapath.md | DONE | DONE | hw/mle/rtl/ |
| MLE xMII Adaptation | micro-architecture-mle-xmii-adaptation.md | DONE | DONE | hw/mle/rtl/ |

---

## RTL Implementation Progress

### Completed (verified, lint-clean, tests pass)

| Component | Files | Tests |
|-----------|-------|-------|
| Common Packages | asa_node_pkg, asa_reg_pkg, asa_intf_pkg, asa_error_pkg | Lint clean |
| Error Aggregator | asa_error_aggregator.sv | 16 tests (foundation TB) |
| Register Bank | asa_reg_bank.sv (SC, saturating inc, SoftReset) | 7 tests pass |
| Register Access | asa_reg_access.sv (decode, ACL, domain routing) | 16 tests (foundation TB) |
| SoftReset Controller | asa_soft_reset_ctrl.sv | Tested via reg_bank TB |
| Node FSM Core | asa_node_fsm.sv (all state transitions) | 20 tests pass |
| Node FSM Top | asa_node_fsm_top.sv (all 7 interface groups) | Lint clean |

### Closeout

| Component | Status | Blocking |
|-----------|--------|----------|
| Aggregate lint | Remaining | Duplicate package entries in top-level lint file list |
| Status/spec docs | Remaining | Stale progress tables and completion markers |
| Focused PDF audit | Remaining | Final spot-check on ASEP eDP, MLE PCS, MLE xMII |

---

## Recommended Implementation Order

1. Full regression -- DONE
2. Aggregate lint dedup fix
3. Focused PDF audit on ASEP eDP / MLE PCS / MLE xMII
4. Status/spec doc refresh
5. Final graph update

---

## Project Directory Structure

```
hw/
├── common/rtl/              Shared packages + error aggregator
├── node_fsm/rtl/            Node state machine (core + top)
│           /dv/             Node FSM testbench (20 tests)
├── register_model/rtl/      Address decode, bank, reset controller
│                 /dv/       Register bank testbench (7 tests)
├── oam/rtl/                 OAM control plane
│       /dv/                 OAM testbench
├── phy_pcs/rtl/             PHY PCS datapath
├── phy_startup/rtl/         PHY startup training FSM
├── dll_mapper/rtl/          DLL mapper/demux
├── dll_forwarding/rtl/      Forwarding fabric
├── ptb/rtl/                 PTB clock service
├── light_sleep/rtl/         Light sleep FSM
├── security/rtl/            Link layer security
├── keyex/rtl/               Key exchange entity
├── asep/rtl/                ASEP common + GPIO/SPI/I2C/I2S/Video/eDP
├── mle/rtl/                 MLE PCS + xMII
└── top/dv/                  Integration testbench
```
