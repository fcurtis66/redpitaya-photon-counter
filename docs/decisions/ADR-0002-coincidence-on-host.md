# ADR-0002 — Cross-board coincidence runs on the host PC (D2)

- **Status:** Accepted
- **Date:** 2026-06-15
- **Deciders:** maintainer
- **Relates to:** DESIGN.md §3, milestones S3 / S6

## Context

Cross-board coincidence logic could live in one of three places:

- **PL (FPGA):** lowest latency, but per-board firmware would have to know about
  other boards' channels — couples the boards and breaks the "add a board = add a
  stream" modularity goal.
- **Per-board ARM:** still requires inter-board data exchange and coordination
  logic on each board.
- **Host PC:** each board stays identical and simply streams its own timestamps;
  all cross-board logic is centralised.

The project's primary differentiators are cross-board sync, coincidence, PNR, a
non-engineer GUI, and **modularity** — none of which is served by coupling the
firmware.

## Decision

Run cross-board coincidence **on the host PC**. Per-board PL/ARM firmware stays
identical (the prebuilt 2-channel bitstream on every board). The host:

1. ingests one timestamp stream per board/channel;
2. applies per-board skew calibration (see ADR-0001 / D1);
3. **k-way merges** the per-channel streams — each is already monotonic, so this
   is a merge, not a general sort (small heap, or just repeatedly take the
   smallest front element for ≤4 channels);
4. runs a **single sliding-window pass** over the merged stream to find
   coincidences within the window.

This merge-plus-window structure is O(total events) and N-channel-ready from the
start; the previously-considered O(N²) all-pairs "brute-force prototype" is
**not** built, as the sliding window is barely more code and is the actual
target design.

## Consequences

- **Modularity (S6):** adding a board is adding a stream — no firmware change.
- **Throughput pressure moves to Ethernet + host.** Verified ceiling ≈ 10–12 M
  tags/s aggregate per board (64-bit tags over 1 GbE); the 2048-deep per-channel
  BRAM is only a ~29 µs burst buffer. Mitigated first by a **compact 32-bit /
  delta wire format** (D4, ~doubles the ceiling) and only if necessary by
  **PL-side AXI DMA** — a stretch that reopens the black-box bitstream and is
  significant block-design work.
- **Latency** is higher than a PL implementation; acceptable because the use
  cases are offline/near-real-time photon counting, not feedback control.
- PNR (D5) is also host-side post-processing in this architecture — consistent
  with running coincidence on the host.
