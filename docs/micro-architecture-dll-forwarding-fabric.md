# Micro-Architecture: DLL Forwarding Fabric (FoFa)

## 1. Purpose and Scope

The DLL Forwarding Fabric (FoFa) is the inter-node bridging component that sits at
the same architectural layer as ASEP within the Data Link Layer. It connects two
adjacent node DLLs (nodeA and nodeB), buffering and routing containers unaltered
between them. FoFa does NOT modify container content — it only changes the scheduling
path (which queue feeds which DLP_TX port).

### 1.1 Responsibilities
- Buffer containers arriving via DLP_RX(Data Forward) into DataForwardingQueue
- Buffer containers arriving via DLP_RX(OAM Return) into OAMreturnQueue
- Conditionally move containers from DataForwardingQueue to OAMreturnQueue based on
  header inspection (Sections 5.4.1 and 5.4.2)
- Present queued containers to the DLL TX scheduler via DLP_TX(Data Forward) and
  DLP_TX(OAM Return) ports
- Pass OAM frames addressed to the local node via DLP_TX.oamFrameLocal

### 1.2 Out of Scope
- Container payload modification (security, ASEP processing)
- Mapper table management (see micro-architecture-dll-mapper-demux-core.md)
- OAM CAD generation/parsing (see micro-architecture-oam-control-plane.md)
- Register access bridge
- Multicast duplication (handled in DLL demux, not FoFa)

---

## 2. Source References

| Section | Title | Pages | Relevance |
|---------|-------|-------|-----------|
| 5.1 | Data Link Layer Overview | 162 | Figure 5-1, port counts |
| 5.1.1 | DLL Functions | 162 | Forwarding/duplication |
| 5.3.2 | Header Decoding and Demultiplexing | 167-168 | 5.3.2.2 Forward case |
| 5.4 | Forwarding Fabric | 169-170 | Primary definition, Figure 5-5 |
| 5.4.1 | Normal Mode | 169 | DataForwardQueue -> OAMreturnQueue |
| 5.4.2 | Enumerate | 169 | DataForwardQueue -> OAMreturnQueue |
| 5.6.1.5 | DLP_TX.oamFrameLocal | 186 | Local OAM delivery from FoFa |
| 5.6.1.6 | DLP_TX.forwardUnit | 187 | FoFa provides forward container to DLL |
| 5.7.1.2 | DLP_RX.forwardUnit | 187-188 | DLL delivers to FoFa DataForwardQueue |
| 3.3.18 | OAMdmxTX (2.2148) | 59 | OAM static far-side connection |
| 3.6.1 | FoFa ReturnPath (4.i.0100) | 86-87 | Far-side OAM return path register |

Image references (docpdfmd/images/):
- `59_Figure_5-5_Forwarding_Fabric.png`: Two-queue structure, conditionally
  switching arrow, DLP_TX/DLP_RX port layout, nodeA/nodeB boundary
- `55_Figure_5-1_Data_Link_Layer_interfaces_OAM.png`: OAM entity and Security
  entity within DLL, showing DLP_TX/DLP_RX at the DLL boundary

---

## 3. Position in DLL Architecture

SPEC FACT (Figure 5-1, Section 5.1, p162): The Data Link Layer contains OAM entity
and Security entity as sub-blocks. FoFa logically belongs at the ASEP layer (not
inside the DLL block boundary), using DLP_TX and DLP_RX ports.

```
        ASEP Layer
        +------+    +------+    +------+
        | ASE  |    | ASD  |    | FoFa |   <- same layer
        +--+---+    +---+--+    +--+--++
           |            |          |   |
    DLP_TX |            | DLP_RX  TX   RX
           |            |          |   |
  +--------+------------+----------+---+--------+
  |              Data Link Layer                  |
  |   +--------+       +----------+               |
  |   |  OAM   |       | Security |               |
  |   | entity |       |  entity  |               |
  |   +--------+       +----------+               |
  |                                               |
  |         [Mapper/Demux/Header engine]          |
  +----------+--------------------------+---------+
           PLP_TX                    PLP_RX
```

SPEC FACT (Section 5.4, p169): "The FoFa logically belongs on the same layer as the
ASEP, but it does not have the same complexity and only buffers and routes containers
unaltered."

---

## 4. Figure 5-5 Architecture: Two-Queue Model

SPEC FACT + IMAGE EVIDENCE (Figure 5-5, p169, `59_Figure_5-5_Forwarding_Fabric.png`):

```
                   nodeB (far-side)
                        |
    DLP_TX         +----+----+        DLP_TX
  (Data Forward) <-+  Data   |      (OAM Return)
        ^           | Forward|<---+      ^
        |           | Queue  | conditionally
        |           +----+---+ switching  |
        |                |    arrow       |
        |           +----+----+           |
        |           |  OAM    +---------->+
        |           | return  |
        |           | Queue   |
        |           +----+----+
        |                |
    DLP_RX         ------+------     DLP_RX
  (Data Forward)       nodeA      (OAM Return)
        |               line            |
```

Observations from image:
1. Two queues: DataForwardingQueue (left column) and OAMreturnQueue (right column)
2. A single dashed arrow labeled "conditionally switching queue" goes from
   DataForwardingQueue to OAMreturnQueue
3. Both queues have DLP_TX (output, upward) and DLP_RX (input, downward) ports
4. The horizontal dashed line divides nodeB (far-side, upper half) from nodeA
   (near-side, lower half) -- indicating this is an inter-node bridge
5. Containers arriving at DLP_RX(Data Forward) from nodeA enter DataForwardingQueue
6. Containers arriving at DLP_RX(OAM Return) from nodeA enter OAMreturnQueue
7. Containers exit toward nodeB via DLP_TX(Data Forward) and DLP_TX(OAM Return)

---

## 5. Queue Switching Logic (Sections 5.4.1, 5.4.2)

The FoFa TX side inspects headers in the DataForwardingQueue and conditionally moves
them to OAMreturnQueue under exactly two conditions:

### 5.4.1 Normal Mode Switch

```
Condition: HeaderType=0 AND streamID=0 AND targetID=nodeID(nodeB)
Action:    Move container from DataForwardingQueue into OAMreturnQueue
```

This handles OAM response frames from the far-side node (nodeB) addressed to nodeB
itself, which are OAM Return traffic and should exit via the OAM Return path.

### 5.4.2 Enumerate Mode Switch

```
Condition: HeaderType=1 AND streamID=0 AND targetIDx=0 AND nodeID(nodeB)=0
Action:    Move container from DataForwardingQueue into OAMreturnQueue
```

This handles Node-Discover OAM frames during enumeration when nodeB has not yet been
assigned a nodeID (nodeID=0).

SPEC FACT (Section 5.4): "If neither of these conditions is evaluated TRUE, each queue
just operates as a first-in first-out buffer."

---

## 6. DLP_TX/DLP_RX Stream Type Assignments

SPEC FACT (Section 5.4, p169-170):

### 6.1 Data Forward Stream

| Port | Node | Registration |
|------|------|-------------|
| DLP_RX (Data Forward) | nodeA | Always listed in DemuxTable2 (3.3.16) of nodeA |
| DLP_TX (Data Forward) | nodeB | Always listed in Mapping Table (3.3.13) of nodeB |

### 6.2 OAM Return Stream

| Port | Node | Registration | Notes |
|------|------|-------------|-------|
| DLP_RX (OAM Return) | near-side from root | unused | OAM traffic from root already local |
| DLP_RX (OAM Return) | far-side from root | hard-connected to DLP_TX of OAM entity | Bypasses mapper |
| DLP_TX (OAM Return) | near-side from root | listed in Mapping Table of nodeB | Scheduled via mapper |
| DLP_TX (OAM Return) | far-side from root | hard-connected to DLP_RX of OAM entity | Bypasses demux |

### 6.3 OAMdmxTX Register Interaction

SPEC FACT (Section 3.3.18, register 2.2148): `OAMdmxTX[5:0]` identifies the DLP_RX_ID
that OAM is statically connected to (far-side configuration). Value 0 means OAM TX is
part of the normal mapper operation (near-side).

SPEC FACT (Section 5.6.1.5.3): "If nodeID=0, DLL copies FoFa ReturnPath (3.6.1) onto
register OAMdmxTX." This establishes the OAM return connection at enumeration time.

---

## 7. Forwarding Decision Logic

The forwarding decision happens in two places:

### 7.1 Demux-Level (DLL Receive, Section 5.3.2)

When a container arrives on PLP_RX and passes security processing, the DLL receive
process evaluates these cases for every targetID in the header:

| Case | Condition | Action |
|------|-----------|--------|
| 5.3.2.1 Local Sink | targetIDx == NodeID && != 0 | DLP_RX.dataUnit to local ASEP/OAM |
| 5.3.2.2 Forward | targetIDx != NodeID && != 0 | DLP_RX.forwardUnit to FoFa |
| 5.3.2.3 Rcv Node-Discover | H=1, streamID=0, targetIDx=0, ownNodeID=0 | OAM local |
| 5.3.2.4 Distribute Node-Discover | H=1, streamID=0, targetIDx=0, not in DmxTable2 | FoFa fwd |
| 5.3.2.5 Rcv Self-Announce | H=1, streamID=0, targetID0=1 | OAM local |
| 5.3.2.6 Fwd Self-Announce | H=1, streamID=0, targetIDx=1 | FoFa fwd |

The DLL calls `DLP_RX.forwardUnit` which puts the container into FoFa's
DataForwardingQueue.

### 7.2 FoFa TX Level (Section 5.4.1, 5.4.2)

After containers are in DataForwardingQueue, the FoFa TX side inspects the header and
either:
- Passes the container to DLP_TX(Data Forward) -> continues toward nodeB
- Switches to OAMreturnQueue -> exits via DLP_TX(OAM Return) -> back to root OAM

---

## 8. DLP Primitive Contracts for FoFa

### 8.1 DLP_RX Primitives (FoFa receives from DLL)

**DLP_RX.forwardUnit(size, header, dll_payload, phyLStat, dllStat)** -- Section 5.7.1.2

SPEC FACT: "When the Receive Process of the DLL decodes a header targetID which is
associated to a DLP_RX with stream type 'Forward Data'."

Effect: "Size, header and data are put on the DataForwardQueue of the ForwardingFabric."

**DLP_RX parameters:**
- `size`: container size in bytes
- `header`: unmodified DLL header (all header bits preserved, including KeySwitch)
- `dll_payload`: container payload (unmodified, security layer has already processed)
- `phyLStat`: physical layer error status from 4.7.1.1
- `dllStat`: decode_good / duplicate_packetID / missing_packetID

### 8.2 DLP_TX Primitives (FoFa sends to DLL)

**DLP_TX.forwardUnit(size, header, payload)** -- Section 5.6.1.6

SPEC FACT: "The FoFa uses DLP_TX.forwardUnit to provide the header and the payload of
a container to the DLL." Called after DLP_TX.indicateSlot(size) from the scheduler.

Effect: "DLL uses the provided header and payload in the next container to be sent."
(DLL does NOT reconstruct the header -- the FoFa-supplied header is used directly.)

**DLP_TX.oamFrameLocal(container, phyLerrStat)** -- Section 5.6.1.5

SPEC FACT: "The FoFa uses DLP_TX.oamFrameLocal to signal to the DLL that it has a
container (with an OAM frame) addressed to the local node."

Generated: "Always, when OAMreturnQueue is not empty and the targetID in the container
header is equal to the local nodeID."

Effect: "DLL takes data the same way as from PLP_RX (see 4.7.1.1) and feeds it to the
Data Link Layer Receive Process." This re-enters the container into the local RX path.

**DLP_TX.yield()** -- Section 5.6.1.4

Called when FoFa has nothing to transmit on the indicated slot.

---

## 9. Branch Topology Behavior

### 9.1 Node Roles

In a branch topology, FoFa sits between two DLL instances:
- **Near-side DLL** (nodeA): connects toward the root
- **Far-side DLL** (nodeB): connects toward the leaf/further branch

### 9.2 Upstream (Leaf to Root)

Containers from far-side nodeB destined for root travel:
```
Far-side DLL TX -> nodeB physical link -> near-side DLL RX
-> DLL demux: if targetID != nodeA, case 5.3.2.2 -> DLP_RX.forwardUnit
-> FoFa DataForwardingQueue
-> FoFa TX: check 5.4.1/5.4.2 -- if OAM response: switch to OAMreturnQueue
-> DLP_TX(OAM Return) or DLP_TX(Data Forward)
-> near-side DLL TX scheduler -> root physical link
```

### 9.3 Downstream (Root to Leaf)

Containers from root for far-side nodes travel:
```
Root TX -> near-side DLL RX
-> DLL demux: targetID = far-side nodeID, case 5.3.2.2 -> DLP_RX.forwardUnit
-> FoFa DataForwardingQueue
-> FoFa TX: does not match 5.4.1/5.4.2 (targetID is far-side, not nodeB itself)
-> DLP_TX(Data Forward) -> far-side DLL RX
-> far-side DLL demux: local delivery
```

### 9.4 Multicast

SPEC FACT (Section 5.1.1): "Demultiplexing includes Duplication of multicast
containers, when applicable." Multicast duplication is handled in the DLL demux
(DmxTable1 matching multiple DLP_RX_IDs), not in FoFa. FoFa receives individually
dispatched DLP_RX.forwardUnit calls per target.

### 9.5 OAM During Enumeration

During enumeration (nodeID=0), Node-Discover frames trigger case 5.3.2.4:

SPEC FACT (Section 5.3.2.4): "For the first DLP_RX_ID with stream type 'Data Forward'
which is not found in DmxTable2, invoke primitive 5.7.1.2."

This forwards Node-Discover through FoFa to the next undiscovered node.

---

## 10. Error Handling

| Condition | Effect | Register |
|-----------|--------|----------|
| Header cannot be decoded | Increment DLL header decode error, discard | 2.2210[15:8] |
| targetID not in DmxTable2 (forward case) | Increment demux ForwardError, discard | 2.2147[7:0] |
| nodeID.streamID not in DmxTable1 (local sink) | Increment demux LocalError, discard | 2.2147[15:8] |
| Security failure on RX | Container discarded before reaching FoFa | 3.0002/3.0003 |

FoFa itself has no additional error registers beyond those managed by the DLL demux
and OAM layers. The FoFa only receives containers that have already passed DLL decode
and security checks.

---

## 11. Suggested RTL Module Boundaries

```
+================================================================+
|                    dll_fofa_top                                  |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | fofa_rx_input       |    | fofa_header_checker |             |
|  |                     |    |                     |             |
|  | Accept DLP_RX.      |    | Inspect DataFwd     |             |
|  | forwardUnit from    |    | queue head:         |             |
|  | DLL demux           |    | - Sec 5.4.1 check  |             |
|  | Enqueue to          |    | - Sec 5.4.2 check  |             |
|  | DataForwardQueue    |    | -> switch decision  |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | fofa_data_fwd_queue |    | fofa_oam_rtn_queue  |             |
|  |                     |    |                     |             |
|  | FIFO: containers    |    | FIFO: containers    |             |
|  | awaiting forward    |    | to return to OAM    |             |
|  | or switch           |    | (toward root)       |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+    +---------------------+             |
|  | fofa_oam_local_     |    | fofa_tx_arbiter     |             |
|  | detect              |    |                     |             |
|  |                     |    | Respond to          |             |
|  | Check OAMreturnQ    |    | DLP_TX.indicateSlot:|             |
|  | for local-addressed |    | - data_fwd port     |             |
|  | OAM frames          |    | - oam_rtn port      |             |
|  | -> DLP_TX.oamFrame  |    | - oamFrameLocal     |             |
|  |    Local()          |    | -> yield if empty   |             |
|  +---------------------+    +---------------------+             |
|                                                                  |
|  +---------------------+                                        |
|  | fofa_register_if    |                                        |
|  |                     |                                        |
|  | OAMdmxTX (2.2148)  |                                        |
|  | FoFa ReturnPath     |                                        |
|  | (4.i.0100)          |                                        |
|  +---------------------+                                        |
+================================================================+
```

---

## 12. Interfaces to Other Modules

### 12.1 Interface to DLL Mapper/Demux Core

| Signal | Dir | Description |
|--------|-----|-------------|
| dlp_rx_fwd(size, hdr, payload, phyStat, dllStat) | DLL->FoFa | Container to forward (5.7.1.2) |
| dlp_tx_indicate(size) | DLL->FoFa | Slot offered for Data Forward TX |
| dlp_tx_fwd_unit(size, hdr, payload) | FoFa->DLL | Container to transmit (5.6.1.6) |
| dlp_tx_oam_local(container, phyStat) | FoFa->DLL | Local OAM frame (5.6.1.5) |
| dlp_tx_yield() | FoFa->DLL | No data to transmit (5.6.1.4) |

### 12.2 Interface to OAM Control Plane

| Signal | Dir | Description |
|--------|-----|-------------|
| oam_rx_from_fofa | FoFa->OAM | Via DLP_TX.oamFrameLocal path |
| oam_dmx_tx_id[5:0] | Reg->FoFa | OAMdmxTX value for far-side routing |

### 12.3 Interface to Register Model

| Signal | Dir | Description |
|--------|-----|-------------|
| node_id[4:0] | Reg->FoFa | NodeID (2.0001) for 5.4.1/5.4.2 checks |
| fofa_rtn_path[5:0] | Reg->FoFa | FoFa ReturnPath (4.i.0100) |
| oam_dmx_tx_wr[5:0] | FoFa->Reg | Write OAMdmxTX when nodeID=0 bootstrap |

### 12.4 Interface to Node State Machine

| Signal | Dir | Description |
|--------|-----|-------------|
| normal_mode | NSM->FoFa | Enable forwarding (Light Sleep halts queues) |
| ls_halt | NSM->FoFa | Halt DataForwardQueue during Light Sleep |

---

## 13. Implementation Assumptions

The following behaviors are NOT explicitly specified and are implementation-defined:

1. **Queue depth**: The spec does not define FIFO depth for DataForwardingQueue or
   OAMreturnQueue. Depth must accommodate worst-case burst traffic without dropping.

2. **Backpressure**: If queues are full, behavior is implementation-defined. The spec
   says DLP_TX.yield when no data available but does not specify what happens when the
   receive side has no buffer space.

3. **OAM return queue priority vs data forward queue**: When both queues have data and
   the TX scheduler offers a slot, the spec does not define arbitration priority.
   IMPLEMENTATION ASSUMPTION: OAM return traffic may need higher priority to prevent
   OAM starvation in heavy data-forward scenarios.

4. **Ordering guarantee**: The spec says queues operate as "first-in first-out buffers"
   when no switching occurs. Whether ordering is guaranteed across a switch event
   (container moved from DataForwardQ to OAMreturnQ) is not stated.

5. **Light Sleep halt**: The spec says mapper is halted during Light Sleep. Whether
   FoFa queues are also halted (preventing dequeue during sleep) is not explicitly
   stated for FoFa specifically; the mapper halt effectively stops TX scheduling.

---

## 14. Verification Plan

| Test Case | What to Verify |
|-----------|---------------|
| Unicast local delivery | Container with targetID=NodeID goes to DLP_RX.dataUnit, not FoFa |
| Unicast forward | Container with targetID=farNodeID goes to FoFa DataForwardingQueue |
| No switch (normal data) | Container with non-OAM streamID passes straight through to DLP_TX(DataFwd) |
| 5.4.1 OAM switch | Container with H=0, streamID=0, targetID=nodeB -> moves to OAMreturnQ |
| 5.4.2 Enumerate switch | Container with H=1, streamID=0, targetIDx=0, nodeB_id=0 -> OAMreturnQ |
| oamFrameLocal delivery | Local-addressed OAM container in OAMreturnQ -> DLL receive path |
| Yield behavior | Empty queue -> DLP_TX.yield, no junk transmitted |
| Demux miss ForwardError | targetID not in DmxTable2 -> 2.2147[7:0] incremented |
| Multicast | Multiple DLP_RX.forwardUnit calls issued by demux, each handled independently |
| Node-Discover enumeration | 5.3.2.4 -> first "Data Forward" DLP_RX, forwarded via FoFa |
| Light Sleep halt | Queue drain stops, no TX during sleep |

---

## 15. Remaining Uncertainties

1. **OAMreturnQueue DLP_RX source on far side**: The spec says the DLP_RX(OAM Return)
   on the far-side from root is "hard connected to the DLP_TX of the OAM entity."
   Whether "hard connected" implies a direct wire (no queue) or a dedicated FIFO is
   implementation-dependent. The spec does not define this connection further.

2. **Self-Announce forwarding**: Section 5.3.2.6 uses DLP_RX.forwardUnit for Self-
   Announce frames. Whether these enter the DataForwardingQueue or a separate queue
   in FoFa is not specified.

3. **Multiple FoFa instances per device**: A branch device has one near-side DLL and
   one or more far-side DLLs. Whether there is one FoFa per far-side link or a shared
   FoFa is implementation-defined. The spec treats each link independently.

4. **Queue switching atomicity**: When a container is "moved" from DataForwardingQueue
   to OAMreturnQueue (5.4.1/5.4.2), whether this is a physical move, a pointer swap,
   or a re-queue operation is not specified. Implementations must ensure no duplication
   or loss during the move.

5. **DLP_TX.oamFrameLocal trigger race**: Section 5.6.1.5.2 says oamFrameLocal is
   generated "always, when OAMreturnQueue is not empty and targetID equals local
   nodeID." If the OAMreturnQueue has mixed local and non-local OAM frames, the
   trigger condition and sequencing are not fully specified.
