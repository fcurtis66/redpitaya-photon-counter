# DESIGN.md — Living Design Document

This is the single source of truth for the project's architecture, decisions, and open questions. It is meant to be edited continuously. Keep it honest: when something is undecided, say so; when a decision is made, move it from "Open decisions" into the decision log and (if architectural) write an ADR in `docs/decisions/`.

This file lives in the repo (so Claude Code reads it) **and** is uploaded to the Claude Project knowledge base (so planning chats read it). When it changes meaningfully, re-upload it to the Project.

_Last updated: 2026-06-15 — by Frankie (planning-chat sync: D2/D7 decided; D1/D4/D5/D6 refined with verified Red Pitaya facts)_

---

## 1. Goal & success criteria

Build a cost-efficient, modular photon counter / time tagger for quantum-optics experiments, extending Michel Adamic's `zynq_tdc` TDC.

Success is defined in layers (each is a real milestone, not all required to "pass"):

- **S0** — Adamic's TDC replicated on a single board, matching the paper's performance (>11 ps resolution, dead time and range as published), verified with the function generator.
- **S1** — Same performance reproduced independently on the second board.
- **S2** — Two boards clock-synchronised; a known fixed inter-board skew measured and calibrated out with the function generator.
- **S3** — 4-channel acquisition with cross-board coincidence logic working on test pulses.
- **S4** — Photon-number discrimination implemented (technique from refs — to be specified).
- **S5** — GUI usable by a non-engineer to configure channels, run acquisition, and read out coincidences/histograms.
- **S6** — Modular: a third board can be added without redesign, with quantified performance impact.
- **S7** — Benchmarked on a real quantum-optics experiment.

## 2. Hardware inventory

- **Board A** — STEMlab 125-14 Starter Kit (standard, internal oscillator). Zynq-7010.
- **Board B** — STEMlab 125-14 External-clock Starter Kit (IZD0031). Factory-modified to take an external 125 MHz clock via the E2 connector; will not boot without it. Zynq-7010.
- Function generator (model: <!-- fill in -->) — pulse/clock source for time-tagging tests and skew calibration.
- Single-photon detectors / optics — _available for later benchmarking (S7); specify when known._

## 3. System architecture

Four layers, each doing what it is best at:

1. **FPGA (PL) per board** — Adamic's tapped-delay-line TDC cores, one per channel; time-tags hit events. Identical firmware on every board to preserve modularity. (The prebuilt 2-channel bitstream, deployed identically to both boards, already covers all 4 channels — no rebuild needed through S3.)
2. **ARM/Linux per board** — C server reads tags from the PL over `mmap`, streams them off-board over Ethernet.
3. **Host PC** — ingests timestamp streams from all boards, applies per-board skew calibration, **k-way merges** the (already per-channel-ordered) streams into one ordered stream, then runs a single sliding-window pass for coincidence + photon-number logic.
4. **GUI** — talks to the host layer; configuration, live acquisition, histograms/coincidence readout.

**Decided (D2 — see §7, ADR-0002):** keep per-board firmware identical and do cross-board coincidence **on the host**. This maximises modularity (add a board = add a stream) at the cost of pushing data-path/throughput pressure onto Ethernet + host. The rejected alternative (coincidence in the PL, or on each ARM) is lower-latency but harder to keep modular. The throughput pressure is real and bounded — see §4 and D4/D6 — and is mitigated first by a compact wire format, and only if necessary by PL-side DMA (a stretch that reopens the bitstream).

## 4. The clock-coherence problem (the crux)

The TDC's picosecond resolution is *within* a board. A coincidence between a channel on Board A and a channel on Board B is only as good as how phase-coherent the two boards' clocks are, plus a fixed inter-board skew.

- If both boards run from **one physical oscillator**, their time bases are frequency-locked and the relationship is stable. Two independent 125 MHz sources will drift relative to each other → skew not constant → uncalibratable. So a single shared oscillator is non-negotiable, not just preferable.
- **What calibration can and can't remove.** Calibration removes the *constant* part of the inter-board offset. It does **not** remove the *random* part — the clock-distribution **jitter**. That residual jitter is the true floor on cross-board coincidence timing, and it will be worse than the >11 ps single-board resolution. How much worse depends on the distribution method.
- Calibration method: feed the **same edge** from the function generator into one channel on each board, measure the constant offset, store it as that board's skew. Repeat per channel pair as needed. Validate before any optics.

**Verified hardware facts** _[Red Pitaya docs, Jun 2026]_ that shape the choice:

- The **SATA daisy-chain** sync (RP "X-Channel") routes the master clock *through the FPGA* to the ADC and **adds jitter**; RP recommend the external-clock / **Click-Shield** (U.FL) distribution when low noise matters. For a ps timing instrument, prefer low-jitter external distribution over the convenient SATA chain, and prefer a **star fan-out** over a literal daisy chain (no cumulative per-hop degradation; no board-2-kills-board-3 dependency) for the N-board modularity goal.
- **Our two boards are mismatched.** Board A (standard Starter Kit) has its internal crystal and **no reference-clock input** — feeding it an external clock needs a hardware mod. Board B (IZD0031) **must** receive 125 MHz on **E2** or it won't operate. Getting both onto one oscillator is therefore non-trivial.
- The documented X-Channel system is built from **Low-Noise** boards whose secondaries are SATA-clock-modified — neither of our boards is one, and **Board B's modification is for E2, not SATA** — so X-Channel is **not drop-in**. The `daisy_tool` CLI enables shared clock **and trigger**; the shared trigger establishes a common time origin (handles "do the boards' counters start together?").
- RP product churn: the original X-Channel is marked discontinued while a new one relaunched ~Nov 2025. **Confirm current hardware and exact wiring with RP support + supervisor before buying a distribution amp or modifying Board A.**

Open hardware question (D1, see §6 + ADR-0001): with the mismatch above, the realistic routes are (a) an external 125 MHz source → Board B E2 and a modified Board A; (b) Board A as master relaying its clock to Board B's E2 (needs a path off Board A); (c) — explicitly rejected — two independent sources. None is free; (a) scales best to N boards.

## 5. Channel map

| Logical channel | Board | Physical input | Notes |
|---|---|---|---|
| CH0 | A | IN1 | |
| CH1 | A | IN2 | |
| CH2 | B | IN1 | |
| CH3 | B | IN2 | |

(Confirm input polarity/threshold/AC-DC coupling expectations for detector pulses.)

_Note (depends on D5):_ a timing-based PNR scheme changes this map. Single-threshold arrival-time-shift PNR needs one channel for the **laser sync** (e.g. CH3), leaving 3 for detectors; multi-threshold time-over-threshold PNR consumes 2–3 channels *per detector* and would exhaust 4 channels with a single detector pair. Revisit this table once D5 is settled.

## 6. Open decisions

Move each to the decision log below once settled, and write an ADR for the architectural ones. (D2 and D7 have been settled — see §7.)

- **D1 — Clock-sharing scheme** between Board A and Board B (see §4). **Principle settled** (one oscillator → constant skew → calibrate out); the **physical scheme is open** (which source, which connector per board, jitter-vs-convenience). Architectural → ADR-0001 drafted (status: Proposed). Do not buy/modify hardware before confirming wiring with RP support. _Blocks S2._
- **D3 — GUI stack** (web app served from a board, vs desktop Python/Qt on the host). Must be free and portable for non-engineer users.
- **D4 — Timestamp wire format** between boards and host. Leaning **compact 32-bit / delta-encoded** rather than 64-bit: full range (47.9 ms) at full resolution (~11 ps) needs ~32 bits, and halving tag size roughly **doubles** the sustainable count rate (see D6). Settles alongside the merge strategy (now in §3).
- **D5 — Photon-number method.** **Reframed.** The reference slope/mean-derivative methods need the analog pulse trace (5 GS/s, 3 GHz); the RP analog path (125 MS/s, DC–60 MHz) is ~50× too slow, and the TDC records threshold-crossing *times* only — so slope PNR cannot be done as host post-processing of TDC data. Viable path is **timing-based** (higher photon number → steeper edge → earlier crossing; Kuijf: projection ≈ C·Δt). Real question for S4: *can a ps-TDC do same-board arrival-time-shift PNR well enough for a clean 1-vs-≥2 herald cut?* Options + trade-offs in §11 refs and CLAUDE.md. Validate on the function generator (two slightly time-shifted pulses) before any detector. **Depends on D1 jitter** (likely must be same-board).
- **D6 — Target coincidence window & max count rate.** **Partially answered.** Lab laser fires every 12.5 ns (80 MHz); a **few-ns window** sits safely inside one pulse period with ample ps-resolution margin. Sustainable rate is **Ethernet-bound at ~10–12 M tags/s aggregate per board** (64-bit tags, 1 GbE), *not* TDC-limited; the 2048-deep BRAM is a ~29 µs burst buffer; TDC dead time (~14 ns) exceeds the laser period, so consecutive pulses can't both be tagged. Refine the target once the expected per-detector singles rate is known. Drives D4.

## 7. Decision log

_Decisions that have been made. Newest first. Link ADRs where written._

- **2026-06-15 — D2: cross-board coincidence runs on the host PC.** Per-board firmware stays identical; the host k-way-merges the per-channel streams and runs a single sliding-window pass. Chosen for modularity (add a board = add a stream); accepts throughput pressure on Ethernet/host, mitigated by a compact wire format (D4) and, only if needed, PL-side DMA. Architectural → **ADR-0002** (`docs/decisions/`).
- **2026-06-15 — D7: Vivado 2018.2 pinned; prebuilt 2-channel bitstream used as a black box.** `setup/TDCsystem_wrapper.bit` deployed identically to both boards covers all 4 channels (CH0/CH1 on A, CH2/CH3 on B), so no Vivado rebuild is needed through S3. The black box is reopened only for the DMA work (a D2-related stretch). Any Vivado upgrade is itself recorded as an ADR. _(Toolchain pin — log entry, no standalone ADR.)_

## 8. Milestones / roadmap

See `docs/milestones.md` for the working roadmap; high-level order is S0 → S7 above.

## 9. Risks

- Inter-board clock-distribution **jitter** (not just frequency coherence) caps cross-board coincidence resolution below the single-board >11 ps. _Mitigation: settle D1 toward low-jitter external distribution; calibrate the constant skew with the function generator before any optics; keep PNR same-board (D5)._
- Host data path can't sustain the count rate → dropped tags. Verified ceiling ≈ 10–12 M tags/s per board (64-bit tags over 1 GbE); BRAM is only a ~29 µs burst buffer. _Mitigation: compact 32-bit/delta wire format (D4) to ~double the ceiling; size buffers; test with high-rate pulse trains; PL-side DMA as a last resort (reopens the bitstream)._
- Toolchain/bitstream reproducibility drift. _Mitigation: pin Vivado version (D7); commit bitstreams with their source commit._
- Scope creep beyond a one-summer project. _Mitigation: treat S0–S3 as the core deliverable; S4–S7 as stretch._

## 10. Prior art

Community forks and related implementations reviewed. These are reference material only — not bases to fork from.

### `JosephFeld/zynq_tdc_4_channel`
- **URL:** https://github.com/JosephFeld/zynq_tdc_4_channel
- **Status:** Incomplete / misleading name. Despite being called `zynq_tdc_4_channel`, the README explicitly describes its `src` folder as "source files for creating a **two-channel** TDC system example project." The setup files, C server, and PLclock script are identical to Adamic's original — it appears to be a fork that got partway toward 4 channels but did not demonstrably reach it.
- **What's useful:** May show how a second TDC core IP was instantiated in the top-level Vivado block design. Worth reading once S0 is working (i.e. when we tackle per-board 4-channel expansion). Do not treat any part of it as verified or tested.
- **What it doesn't address:** Cross-board synchronisation, coincidence logic, photon-number discrimination, GUI, or modularity — i.e. the novel contributions of this project.
- **Decision:** Fork Adamic (`madamic/zynq_tdc`) as our baseline — our fork is `fcurtis66/redpitaya-photon-counter`. JosephFeld is kept as a browser-tab reference only.

### `ljthink/zynq_tdc` and `diamond2nv/zynq_tdc-1`
- Forks of Adamic with no apparent functional changes. Confirmed same performance specs and file structure. Not useful as references beyond verifying Adamic's numbers are consistently cited.

## 11. References

Index of the papers in the Refs folder. For each: short tag, full citation, what we use it for.

- **[Kuijf-2026]** — I.S. Kuijf, F.B. Baalbergen, L. Seldenthuis, E.P.L. van Nieuwenburg, M.J.A. de Dood, "Extracting Photon-Number Information from Superconducting Nanowire Single-Photon Detectors Traces via Mean-Derivative Projection," arXiv:2511.13475v3 (2026). _Use:_ primary D5 reference. Shows PC1 ≈ derivative of the mean trace, and that the projection ≈ a photon-number-dependent **time shift** Δt (Eq. 1) — the bridge that makes timing-based PNR on a TDC plausible. Also: confidence metric (Bhattacharyya), modest-hardware (5 GS/s / 3 GHz) FPGA feasibility, ~45 ps 1-photon FWHM / ~50–100 ps peak spacing (our jitter budget reference).
- **[Sempere-2022]** — S. Sempere-Llagostera, G.S. Thekkadath, R.B. Patel, W.S. Kolthammer, I.A. Walmsley, "Reducing g²(0) of a parametric down-conversion source via photon-number resolution with superconducting nanowire detectors," Opt. Express 30(2), 3138 (2022). _Use:_ the application — herald-arm PNR (rising-edge slope, 10–60% linear fit) to discard multiphoton heralds and lower g²(0). Confirms the easy regime is **1 vs ≥2** (P(1|2)=4.47%) and that the result was source-efficiency-limited, not detector-resolution-limited — encouraging for a modest-resolution timing approach.

## Changelog

- 2026-06-15 — Planning-chat sync. Decided D2 (coincidence on host) and D7 (Vivado 2018.2 + black-box 2-ch bitstream); added decision-log entries and ADR-0001 (D1, Proposed) / ADR-0002 (D2, Accepted). Refined §4 with verified Red Pitaya clock/jitter facts and the Board A/B mismatch; reframed D5 (timing-based PNR, not analog-trace); answered D6 in part (80 MHz laser, few-ns window, ~10–12 M tags/s/board Ethernet ceiling); leaned D4 toward compact 32-bit/delta tags; populated §11 with the two PNR papers. — <!-- name -->
