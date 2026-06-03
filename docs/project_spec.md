# Project Specification

## User Goal
Build the ASA implementation project from the PDF-backed micro-architecture documentation in `docpdfmd/` and `.silicogen/docs`, treating those documents as the source of truth. Start from shared infrastructure and dependency roots, keep modules aligned to documented micro-architecture boundaries, implement the core transport stack before ASEP/MLE stream-specific features, and make every assumption traceable back to the local spec corpus.

## Canonical Spec
```yaml
meta:
  spec_version: "3.0"
  project_name: asa_motion_link_v2_implementation
  project_mode: greenfield
  design_family: mixed
  implementation_scope: subsystem
  lifecycle_status: implementing
  source_of_truth: mixed
  created: 2026-05-31
  updated: 2026-06-04

problem:
  purpose: >-
    Implement the ASA Motion Link v2.0 digital stack from the local PDF-derived
    micro-architecture documents, beginning with shared control and transport
    infrastructure and progressing toward composable RTL and verification assets.
  success_definition:
    - Shared foundations are implemented from the documented register, interface, and control contracts.
    - Core transport modules are built in dependency order and validated against the local spec docs.
    - Stream-specific ASEP and MLE modules are implemented after the shared stack is stable.
    - Every implemented module has traceable verification evidence for field widths, state transitions, and protocol behavior.
  in_scope:
    - Documentation-driven project map and dependency-ordered implementation roadmap.
    - Shared foundations: register model, common interfaces/message primitives, status/error reporting, simulation entrypoints.
    - Core transport stack: node state machine, OAM control plane, PHY PCS datapath, PHY startup FSM, PTB clock service, DLL mapper/demux, forwarding fabric, Light Sleep FSM, security engine, KeyEx entity.
    - Incremental RTL or executable-model implementation slices validated with local EDA tooling.
  out_of_scope:
    - Analog PMA/PMD implementation beyond a digital interface boundary.
    - Stream-specific ASEP modules before shared infrastructure and transport stack are established.
    - MLE-specific modules before baseline shared infrastructure and transport are established.
    - Any undocumented behavior not traceable to the local spec corpus.
  assumptions:
    - The authoritative design contract is the local PDF-backed documentation under `docpdfmd/` and `.silicogen/docs`.
    - The immediate starting point is a clean implementation effort rather than an audit of existing RTL.
    - Initial progress can be made in simulation-first form before a later FPGA or ASIC commitment is confirmed.
  risks:
    - Several micro-architecture documents are still incomplete or marked not started, which can block downstream RTL work.
    - Top-level integration details such as exact reset convention, clock frequencies, and physical target remain unconfirmed.
    - Security, PTB, and startup sequencing are cross-cutting dependencies that can stall parallel implementation if underspecified.

target:
  execution_targets:
    - simulation
  primary_platform: documentation-driven digital model and RTL bring-up
  process_or_family: not_yet_decided
  board_or_part: not_yet_decided
  frequency_targets: []
  ppa_priority: balanced
  physical_depth: none

architecture:
  top_module: asa_node
  module_hierarchy:
    - name: asa_node
      role: per-node top-level digital integration boundary for ASA v2.0 shared infrastructure and transport stack
      path: hw/top/rtl/
      children:
        - name: common
          path: hw/common/rtl/
          status: DONE
          files: [asa_node_pkg, asa_reg_pkg, asa_intf_pkg, asa_error_pkg, asa_error_aggregator]
        - name: register_model
          path: hw/register_model/rtl/
          status: DONE
          files: [asa_reg_access, asa_reg_bank, asa_soft_reset_ctrl]
        - name: node_fsm
          path: hw/node_fsm/rtl/
          status: DONE
          files: [asa_node_fsm, asa_node_fsm_top]
        - name: oam
          path: hw/oam/rtl/
          status: DONE
          files: [asa_oam_pkg, oam_header_gen, oam_header_check, oam_resp_fifo, oam_error_counters, oam_cad_parser, oam_reg_bridge, oam_longatom, oam_keyex_bridge, oam_ls_bridge, oam_rx_fsm, oam_tx_fsm, oam_top]
        - name: phy_pcs
          path: hw/phy_pcs/rtl/
          status: DONE
        - name: phy_startup
          path: hw/phy_startup/rtl/
          status: DONE
        - name: ptb
          path: hw/ptb/rtl/
          status: DONE
        - name: dll_mapper
          path: hw/dll_mapper/rtl/
          status: DONE
        - name: dll_forwarding
          path: hw/dll_forwarding/rtl/
          status: DONE
        - name: light_sleep
          path: hw/light_sleep/rtl/
          status: DONE
        - name: security
          path: hw/security/rtl/
          status: DONE
        - name: keyex
          path: hw/keyex/rtl/
          status: DONE
        - name: asep
          path: hw/asep/rtl/
          status: DONE
        - name: mle
          path: hw/mle/rtl/
          status: DONE
  clocking:
    reset_style: async_assert_sync_release
    reset_polarity: active_high
    domains: []
  interfaces:
    host_control: custom
    data_plane: streaming
    external_protocols:
      - ASA PLP_TX/PLP_RX
      - ASA DLP_TX/DLP_RX
      - ASA OAM
      - ASEP
      - MLE
  family_specific: {}

contracts:
  ports:
    - name: reg_bus
      direction: inout
      width: 16
      description: Local register access path for domain, subdomain, address, data, and response handling.
    - name: plp_tx_if
      direction: output
      width: 1
      description: Physical-layer transmit primitive bundle carrying DLL containers toward the PHY boundary.
    - name: plp_rx_if
      direction: input
      width: 1
      description: Physical-layer receive primitive bundle carrying PHY-delivered containers and link status toward DLL.
    - name: dlp_tx_if
      direction: input
      width: 1
      description: Stream-facing transmit primitive bundle from ASEP/OAM producers into the DLL mapper.
    - name: dlp_rx_if
      direction: output
      width: 1
      description: Stream-facing receive primitive bundle from DLL demux toward ASD/OAM consumers.
    - name: ptb_if
      direction: inout
      width: 48
      description: Precision Time Base service interface for timestamping, lock status, and follow/delay coordination.
    - name: sec_if
      direction: inout
      width: 1
      description: Security processing interface between DLL container flow and cryptographic/key-management services.
  registers:
    base_address: 0x0000
    stride_bytes: 2
    list: []
  interrupts:
    - name: asa_node_irq
      source: ASAnodeIRQ register aggregation
      trigger: level
      clear_mechanism: self-clearing status register read
  software_view:
    level: driver
    artifacts:
      - header
      - hal

verification:
  methodology: mixed
  simulators_allowed:
    - verilator
  primary_simulator: verilator
  lint_tools:
    - verilator
  formal_tools:
    - yosys
  coverage_targets:
    functional_pct: 0
    line_pct: 0
    branch_pct: 0
    fsm_pct: 0
  required_test_classes:
    - Register access and access-policy tests derived from the register catalog.
    - Node state transition tests against documented state encodings and timing guards.
    - OAM command encode/decode and privilege-check tests.
    - PTB and startup interaction tests.
    - DLL container mapping and demux routing tests.
  required_properties:
    - No undocumented register write may mutate privileged or read-only state.
    - ASAnodeState encodings must match the documented register values.
    - SoftReset must preserve configuration registers while clearing state/status.

tool_capabilities:
  discovered:
    simulators:
      - verilator 5.020
      - iverilog 12.0
    synthesis: []
    formal:
      - yosys
    pnr: []
    firmware_toolchains: []
  constraints:
    unavailable:
      - discovered FPGA implementation flow configuration
    notes:
      - fst2vcd is available for waveform conversion.
      - Makefile provides aggregate `lint` and `test` plus module-level targets.
      - `make -C docpdfmd test` passes on 2026-06-04.

evidence:
  files_read:
    - docpdfmd/.silicogen/docs/asa-project-scope-and-module-map.md
    - docpdfmd/.silicogen/docs/micro-architecture-register-model.md
    - docpdfmd/.silicogen/docs/micro-architecture-node-state-machine.md
    - docpdfmd/.silicogen/docs/micro-architecture-oam-control-plane.md
    - docpdfmd/.silicogen/docs/register_catalog.json
    - docpdfmd/ASA_Technical_Specification_ver2.0.pdf
    - docpdfmd/pipeline/out/asa_structured_chunks.jsonl
    - docpdfmd/images/ (210 recovered spec images)
  reports_read: []
  logs_read: []
  inferred_facts:
    - fact: Project is implementing from PDF-backed micro-architecture docs.
      source: 20 complete micro-architecture documents in .silicogen/docs/
      confidence: high
    - fact: Shared foundations (packages, register model, node FSM) are implemented and tested.
      source: 43 tests passing, verilator lint clean
      confidence: high
    - fact: OAM control plane is next priority — package done, implementation pending.
      source: asa_oam_pkg.sv complete, asa_oam_top.sv is placeholder
      confidence: high
    - fact: Directory structure follows OpenTitan/PULP convention (hw/{module}/rtl/ + dv/).
      source: reorganized 2026-05-31
      confidence: high

unknowns:
  blocking:
    - Confirm whether the first implementation target is simulation-only or should also commit to FPGA and/or ASIC deliverables.
    - Confirm the intended top-level external control interface beyond the internal ASA register/OAM model (for example custom local bus vs AXI/APB wrapper).
    - Confirm the top-level reset convention and any required clock-frequency targets before RTL interfaces are frozen.
    - Confirm whether the initial implementation language should be pure SystemVerilog RTL, executable reference model plus RTL, or another split.
  non_blocking:
    - Exact initial DLP port count and which optional ASEP interfaces will eventually be exposed.
    - Whether light sleep and security should be stubbed or fully implemented in the first transport tranche.
    - Whether the first high-value transport target is Gen2020 baseline mode, ASA-MLE mode, or both.

stage_model:
  design_tracks:
    - architecture
    - rtl
    - verification
    - hw_sw_contracts
    - ci
  optional_tracks:
    - physical
    - firmware
    - fpga_impl
    - asic_signoff
```
