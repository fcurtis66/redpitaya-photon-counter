# Milestones / roadmap

Working roadmap. Tick items as done; keep dates honest. Treat **S0–S3 as the core
summer deliverable**, and **S4–S7 as stretch**.

## S0 — Single-board TDC replicated (Board A)
- [ ] Toolchain set up; Vivado version pinned (DESIGN.md D7)
- [ ] Build/flash Adamic's bitstream; run C server
- [ ] Lower PL clock 125 → 100 MHz (PLclock)
- [ ] Verify resolution/dead-time/range vs paper using the function generator

## S1 — Second board (Board B) reproduces S0
- [ ] Board B boots with external 125 MHz clock via E2
- [ ] Same TDC performance verified independently

## S2 — Two boards clock-synced + skew-calibrated
- [ ] Decide clock-sharing scheme (DESIGN.md D1) + write ADR
- [ ] Establish shared/relayed clock between boards
- [ ] Measure fixed inter-board skew with the function generator (same edge to both)
- [ ] Store + apply skew calibration

## S3 — 4-channel acquisition + cross-board coincidence
- [ ] Decide where coincidence logic lives (DESIGN.md D2) + ADR
- [ ] Decide timestamp wire format + merge strategy (DESIGN.md D4)
- [ ] Coincidence working on test pulse trains; validate window + rate (DESIGN.md D6)

## S4 — Photon-number discrimination
- [ ] Pick reference technique (DESIGN.md D5) + ADR
- [ ] Implement; validate on test signals

## S5 — Operator GUI
- [ ] Decide GUI stack (DESIGN.md D3) + ADR
- [ ] Configure channels, run acquisition, read coincidences/histograms

## S6 — Modularity proven
- [ ] Add a third board with no redesign
- [ ] Quantify performance impact of each added board

## S7 — Real experiment benchmark
- [ ] Run on a quantum-optics setup; compare against expectations / a reference instrument
