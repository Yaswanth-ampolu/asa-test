# ASA Spec-to-RTL Implementation Workspace

This repository is a focused implementation workspace for the Automotive SerDes Alliance Transceiver Specification v2.0.

The main source of truth for behavior is:
- `ASA_Technical_Specification_ver2.0.pdf`

This repo contains:
- RTL for the implemented ASA modules under `hw/`
- module-level and aggregate testbenches under `hw/*/dv`
- extracted spec markdown and processing scripts under `pipeline/`
- working design and audit notes under `docs/`
- build/test automation in `Makefile` and `scripts/`

## What is implemented

Implemented module families:
- common/shared packages
- register model
- node FSM
- OAM control plane
- PHY startup FSM
- PTB clock service
- PHY PCS datapath
- DLL mapper/demux
- DLL forwarding fabric
- Light Sleep FSM
- Link Layer Security
- KeyEx entity
- ASEP common framing
- ASEP GPIO
- ASEP SPI
- ASEP I2C
- ASEP I2S
- ASEP Video
- ASEP eDP
- MLE PCS datapath
- MLE xMII adaptation

## Verification flow

Primary verification path:
- `make test`
- `make lint`

The project is maintained as a Verilator/iverilog-driven RTL workspace. Questa helper scripts may still exist historically, but they are not the primary signoff path here.

## Spec discipline

Implementation rule used in this workspace:
- PDF first
- recovered images second
- local docs in `docs/` third

Where the spec remained ambiguous, the implemented assumption is called out in the relevant local design note instead of being hidden in RTL.
