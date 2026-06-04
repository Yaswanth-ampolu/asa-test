# Progress

## Current state

The spec-base RTL implementation pass is complete at the module level.

Implemented and verified on the main local flow:
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

## What has been achieved

- Converted the ASA v2.0 spec into working RTL module families.
- Added focused DV for each major block.
- Brought aggregate `make test` and `make lint` to green on the local repo flow.
- Reconciled several doc/spec mismatches during implementation, including:
  - DLL mapper pseudocode selection behavior
  - OAM header layout and CAD mapping details
  - StartTDD/PTB-timed Node FSM behavior
  - Light Sleep response-count and restart-state handling
  - MLE payload block sizing at the PCS/xMII boundary

## Remaining gaps vs full PDF breadth

The repo implements the intended RTL module boundary, not every broader ecosystem function mentioned by the PDF.

Still outside the achieved scope:
- full board/system integration beyond module boundaries
- full silicon bring-up and lab validation
- exhaustive malformed-traffic and stress verification for every late-stage module
- full electrical/cycle-accurate external protocol engines where the repo intentionally stopped at controller/packet abstraction
- broader non-RTL functions such as policy software, production firmware flows, or ecosystem interoperability campaigns

Module-specific residual limits still worth noting:
- Node FSM:
  - OAM Config link-loss threshold remains an explicit implementation assumption because the PDF wording is not fully decisive there
- ASEP eDP:
  - implemented at the stream-local packetization boundary, not as a full DisplayPort subsystem
- MLE PCS / xMII:
  - main datapath is in place, but deeper stress/negative-path DV can still be extended

## Not achieved from the PDF

Not achieved in this repo as deliverables:
- production-complete DisplayPort PHY / HDCP / DSC stack
- cycle-accurate full electrical models for all tunneled peripheral buses
- final packaging/integration of all optional behaviors into a single product-level top
- exhaustive compliance validation against every informative appendix example

## Recommended next work

If this repo continues past the current base implementation, the highest-value next steps are:
1. extend negative-path DV on late large modules
2. add higher-level integration benches across DLL, ASEP, and MLE boundaries
3. perform a final PDF audit on remaining assumption-heavy edges
4. clean and stabilize any nonessential historical helper scripts
