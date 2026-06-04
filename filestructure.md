# File Structure

This file explains the main project layout without dumping the entire tree.

## Root

- `README.md`
  - project overview
- `progress.md`
  - implementation status and remaining scope
- `filestructure.md`
  - this file
- `Makefile`
  - main lint and test entry point
- `ASA_Technical_Specification_ver2.0.pdf`
  - normative spec source used for implementation review

## `docs/`

Local design and audit notes derived from the PDF and implementation work.

Includes:
- module micro-architecture notes
- project scope and state tracking
- register catalog and helper notes

These docs are secondary to the PDF, but they capture local implementation decisions and unresolved assumptions.

## `hw/`

Main RTL and DV tree.

Subdirectories are organized by module family:
- `common/`
- `register_model/`
- `node_fsm/`
- `oam/`
- `phy_startup/`
- `ptb/`
- `phy_pcs/`
- `dll_mapper/`
- `dll_forwarding/`
- `light_sleep/`
- `security/`
- `keyex/`
- `asep/`
- `mle/`
- `top/`

Typical pattern per module:
- `rtl/`
  - synthesizable RTL
- `dv/`
  - focused module-level testbenches

## `pipeline/`

Spec extraction and processing workspace.

Contains:
- scripts used to extract structured data from the PDF
- extracted markdown under `pipeline/out/markdown/`
- intermediate structured outputs used during implementation and audit

This area is supporting infrastructure for spec review, not just build-time RTL logic.

## `scripts/`

Helper scripts used during the project.

Typical contents:
- import/conversion helpers
- simulator helper scripts
- project automation utilities

## `images/`

Recovered figures and image exports from the spec PDF.

These are used as secondary evidence when verifying packet layouts, state diagrams, and architecture figures.

## Generated / local-only areas

These are not intended to be committed as project source:
- `.claude/`
- `.silicogen/`
- `obj_dir/`
- `questa_work/`
- `questa_work_asep_gpio/`
- Python cache directories

## How to navigate the repo

If you want to understand the implementation quickly:
1. read `README.md`
2. read `progress.md`
3. inspect `docs/project_spec.md` and the relevant module micro-architecture note
4. inspect the corresponding `hw/<module>/rtl` and `hw/<module>/dv`
