# Project State

```yaml
state_version: "5.0"
project_name: asa_motion_link_v2_implementation
last_updated: 2026-06-04

routing:
  active_entry_skill: chip-project-intake
  active_domain_skill: architecture
  active_process_skill: implementation
  next_recommended_skill: rtl-implementation
  rationale: >-
    The spec-base RTL stack is implemented end to end. Aggregate Verilator lint and
    test both pass, and the late MLE document mismatch on payload block count was
    corrected against the PDF/image evidence. Remaining work is optional cleanup only.

tracks:
  architecture:
    status: done
    produced_artifacts:
      - .silicogen/docs/project_spec.md
      - .silicogen/docs/project_state.md
      - .silicogen/docs/asa-project-scope-and-module-map.md
      - .silicogen/docs/micro-architecture-register-model.md
      - .silicogen/docs/micro-architecture-node-state-machine.md
      - .silicogen/docs/micro-architecture-oam-control-plane.md
      - .silicogen/docs/register_catalog.json
      - (all 20 micro-architecture docs complete)
    blockers: []

  rtl:
    status: done
    produced_artifacts:
      - hw/common/rtl/asa_node_pkg.sv
      - hw/common/rtl/asa_reg_pkg.sv
      - hw/common/rtl/asa_intf_pkg.sv
      - hw/common/rtl/asa_error_pkg.sv
      - hw/common/rtl/asa_error_aggregator.sv
      - hw/register_model/rtl/asa_reg_access.sv
      - hw/register_model/rtl/asa_reg_bank.sv
      - hw/register_model/rtl/asa_soft_reset_ctrl.sv
      - hw/node_fsm/rtl/asa_node_fsm.sv
      - hw/node_fsm/rtl/asa_node_fsm_top.sv
      - hw/oam/rtl/
      - hw/phy_startup/rtl/
      - hw/ptb/rtl/
      - hw/phy_pcs/rtl/
      - hw/dll_mapper/rtl/
      - hw/dll_forwarding/rtl/
      - hw/light_sleep/rtl/
      - hw/security/rtl/
      - hw/keyex/rtl/
      - hw/asep/rtl/
      - hw/mle/rtl/
    required_next: []
    blockers: []

  verification:
    status: done
    produced_artifacts:
      - module-level DV for common, node, OAM, PHY startup, PTB, PCS, DLL, LS, LLS, KeyEx, ASEP, and MLE
      - aggregate `make -C docpdfmd test` PASS on 2026-06-04
    required_next: []
    blockers: []

  ci:
    status: done
    produced_artifacts:
      - Makefile (module-level lint/test targets plus aggregate regression)
    blockers: []

  hw_sw_contracts:
    status: in_progress
    produced_artifacts:
      - .silicogen/docs/register_catalog.json (full field-level metadata)
      - .silicogen/docs/register_catalog_readme.md
    blockers:
      - External host interface wrapper not yet defined.

  physical:
    status: not_applicable
    blockers: []

  firmware:
    status: not_applicable
    blockers: []

progress_summary:
  total_modules: 20
  docs_complete: 20
  rtl_complete: 20
  rtl_partial: 0
  rtl_not_started: 0
  tests_passing: "aggregate make -C docpdfmd test passes"

tools_verified:
  - iverilog 12.0 (simulation)
  - verilator 5.020 (simulation + lint)

open_questions:
  blocking: []
  non_blocking:
    - Decide whether to keep or delete dormant Questa helper scripts now that Verilator is the only active signoff path.
    - Decide whether to deepen negative-path DV on ASEP eDP PLM/EDM and MLE OAM sequencer timing.

next_actions:
  immediate:
    - None required for the spec-base RTL deliverable.
  near_term:
    - Optional removal of dormant Questa-only collateral if the repo should be Verilator-only.
  deferred:
    - Optional verification-depth expansion on reduced-stress negative paths.
```
