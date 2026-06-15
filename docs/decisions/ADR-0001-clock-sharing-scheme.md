# ADR-0001 — Inter-board clock-sharing scheme (D1)

- **Status:** Proposed (decision pending — do not commit hardware changes yet)
- **Date:** 2026-06-15
- **Deciders:** maintainer + supervisor (+ Red Pitaya support for wiring confirmation)
- **Relates to:** DESIGN.md §4, milestone S2

## Context

Cross-board coincidence requires Board A and Board B to share a time base. The
TDC gives >11 ps resolution *within* a board; across boards the limiting factors are:

1. **Frequency lock** — both boards must derive from **one** physical 125 MHz
   oscillator. Two independent sources drift, the inter-board skew stops being
   constant, and calibration cannot recover it. This is a hard requirement.
2. **Constant skew** — with frequency lock, the remaining offset is a constant
   that is measured once (same function-generator edge into one channel of each
   board) and subtracted. This part is solved by calibration.
3. **Jitter** — the *random* part of the clock distribution. Calibration cannot
   remove it; it sets the true cross-board coincidence floor, which will be
   worse than the single-board >11 ps.

Verified Red Pitaya facts (docs, Jun 2026) that constrain the options:

- The **SATA daisy-chain** ("X-Channel") routes the master clock *through the
  FPGA* to the ADC and **adds jitter**; RP recommend the external-clock /
  **Click-Shield** (U.FL) distribution when low noise matters.
- The documented X-Channel uses **Low-Noise** boards with SATA-clock-modified
  secondaries — neither of our boards is one.
- **Board A** (standard Starter Kit): internal crystal, **no reference-clock
  input** — accepting an external clock needs a hardware mod.
- **Board B** (IZD0031, external-clock): **must** receive 125 MHz on **E2** — and
  its modification is for E2, **not** SATA.
- `daisy_tool` enables shared clock **and trigger**; the shared trigger gives a
  common time origin.
- Product churn: original X-Channel discontinued, a new one relaunched ~Nov 2025.

## Options

- **(a) External 125 MHz source → both boards.** Board B via E2 (native); Board A
  via a hardware mod to accept external clock. Lowest-jitter, **scales best to N
  boards** via a star fan-out. Cost: a low-jitter distribution source + surgery
  on Board A.
- **(b) Board A as master, relaying its crystal to Board B's E2.** Needs a path to
  get Board A's reference off-board to E2; uses the boards as-is otherwise. Cost:
  finding/validating that path; does not generalise cleanly to N boards.
- **(c) Two independent sources.** **Rejected** — clocks drift, skew not constant.

## Decision

Pending. Current lean: **(a)**, because it minimises jitter and is the only
option that scales to the N-board modularity goal (S6) via a star fan-out rather
than a degrading daisy chain. To be confirmed with Red Pitaya support (exact
wiring, current X-Channel hardware) and the supervisor before any purchase or
board modification.

## Consequences

- Cross-board coincidence resolution will be jitter-limited and worse than
  single-board; validate the achieved figure on the function generator before
  any optics.
- Photon-number resolution (D5), which rides on the same timing budget, will
  likely have to be done **same-board** (detector + its laser-sync reference on
  one board).
- A star fan-out keeps each added board independent (no board-2-kills-board-3
  dependency), supporting modularity.
- Update this ADR to **Accepted** with the chosen route and measured jitter once
  S2 hardware is validated.
