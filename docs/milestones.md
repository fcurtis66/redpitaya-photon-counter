# Milestones / roadmap

Working roadmap. Tick items as done; keep dates honest. Treat **S0–S3 as the core
summer deliverable**, and **S4–S7 as stretch**.

## S0 — Single-board TDC replicated (Board A) — ✅ COMPLETE (2026-06)
- [x] Toolchain set up; Vivado 2018.2 pinned, OS 1.04 (DESIGN.md D7)
- [x] Build/flash Adamic's bitstream; run C server
- [x] Lower PL clock 125 → 100 MHz (PLclock)
- [x] Verify **resolution** vs paper (code-density + single-shot jitter, function generator)
- [ ] Dead-time (~14 ns) and measurement-range (47.9 ms) — _not in reported S0 results; confirm or mark N/A_

### S0 baseline — the control for all later changes (re-measure after OS port & Path B re-clock)
- **Code-density (TDC0, 83 884 counts):** 170 active taps of 192, **avg bin width 16.81 ps**. INL curve monotonic → **no missing codes / bubbles**. Expected carry-chain character: even/odd DNL zig-zag + a few CLB-boundary fat bins (worst ~74 ps ≈ 4.4 LSB).
- **Single-shot jitter (two-channel, 0 delay, shared clock):** σ = 19.4 ps → **single-channel σ ≈ 13.4 ps** (= 19.4/√2). Mean ≈ 0 (−4×10⁻¹¹ ps) → no fixed channel skew; cables matched. Clean Gaussian envelope (with DNL comb striping, expected).
- **Interval test (single-channel START/STOP, ~1 ms):** σ = 47.6 ps — larger than the two-channel σ because over a full period the **reference-clock jitter no longer cancels**. Empirical evidence for the Path-B rationale: short, common-clock *differences* are TDC-limited; long *intervals* are clock-limited. Mean 0.999985 ms vs 1.000000 → −15 ppm, consistent with oscillator tolerance.
- _Verdict:_ faithful replication of Adamic's TDC (paper: >11 ps). 16.81 ps avg bin vs ">11 ps" is in-family — avg bin width and best-case resolution are defined differently, and per-board carry-chain placement varies.

## S1 — Second board (Board B) reproduces S0
- [ ] Board B boots with external 125 MHz clock via E2
- [ ] Same TDC performance verified independently

## S2 — Two boards clock-synced + skew-calibrated
- [x] Decide clock-sharing scheme (DESIGN.md D1) → **Path B re-clock + Click Shield** (ADR-0001)
- [ ] Establish shared/relayed clock between boards (Click Shield 125 MHz)
- [ ] Measure fixed inter-board skew with the function generator (same edge to both)
- [ ] Store + apply skew calibration

## S3 — 4-channel acquisition + cross-board coincidence
- [x] Decide where coincidence logic lives (DESIGN.md D2) → **host** (ADR-0002)
- [~] Decide timestamp wire format + merge strategy (DESIGN.md D4) — merge decided (host k-way + sliding window); wire format leaning **T3-style 64-bit packet** (open: field widths / sync-counter rollover)
- [ ] Coincidence working on test pulse trains; validate window + rate (DESIGN.md D6)

## S4 — Photon-number discrimination
- [ ] Pick reference technique (DESIGN.md D5) + ADR
- [ ] **Apply per-tap code-density calibration before PNR** — the delay-line DNL (even/odd zig-zag + fat bins, S0 baseline) sits at the same tens-of-ps scale as the photon-number time shifts, so raw taps must be linearised into real ps first. Calibration table = the S0 code-density result.
- [ ] Implement; validate on test signals

## S5 — Operator GUI
- [ ] Decide GUI stack (DESIGN.md D3) + ADR
- [ ] Configure channels, run acquisition, read coincidences/histograms

## S6 — Modularity proven
- [ ] Add a third board with no redesign
- [ ] Quantify performance impact of each added board

## S7 — Real experiment benchmark
- [ ] Run on a quantum-optics setup; compare against expectations / a reference instrument
