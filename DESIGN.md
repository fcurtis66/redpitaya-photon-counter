# DESIGN.md — Living Design Document

This is the single source of truth for the project's architecture, decisions, and open questions. It is meant to be edited continuously. Keep it honest: when something is undecided, say so; when a decision is made, move it from "Open decisions" into the decision log and (if architectural) write an ADR in `docs/decisions/`.

This file lives in the repo (so Claude Code reads it) **and** is uploaded to the Claude Project knowledge base (so planning chats read it). When it changes meaningfully, re-upload it to the Project.

_Last updated: <!-- date --> — by <!-- name -->_

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

## 3. System architecture (provisional)

Four layers, each doing what it is best at:

1. **FPGA (PL) per board** — Adamic's tapped-delay-line TDC cores, one per channel; time-tags hit events. Identical firmware on every board to preserve modularity.
2. **ARM/Linux per board** — C server reads tags from the PL over `mmap`, streams them off-board over Ethernet.
3. **Host PC** — ingests timestamp streams from all boards, applies per-board skew calibration, merges into one ordered stream, runs coincidence + photon-number logic.
4. **GUI** — talks to the host layer; configuration, live acquisition, histograms/coincidence readout.

**Provisional stance:** keep per-board firmware identical and do cross-board coincidence on the host. This maximises modularity (add a board = add a stream) at the cost of pushing data-path/throughput pressure onto Ethernet + host. The alternative (coincidence in the PL, or on each ARM) is lower-latency but harder to keep modular. **This is an open decision — see §6.**

## 4. The clock-coherence problem (the crux)

The TDC's picosecond resolution is *within* a board. A coincidence between a channel on Board A and a channel on Board B is only as good as how phase-coherent the two boards' clocks are, plus a fixed inter-board skew.

- If both boards run from a **shared clock**, the relationship between their time bases is stable, and the remaining offset is a *constant* that can be measured once and subtracted.
- Calibration method: feed the **same edge** from the function generator into one channel on each board, measure the constant time offset, store it as that board's skew. Repeat per channel pair as needed.

Open hardware question (see §6): do we (a) feed a single shared 125 MHz reference into both boards, (b) make Board A the primary and feed its clock to Board B, or (c) some mix? Board B already expects an external clock via E2; Board A has the internal oscillator and (original-gen) SATA sync but would need the secondary resistor mod to *receive* a clock. Resolve with Red Pitaya's multiboard docs + supervisor before committing.

## 5. Channel map

| Logical channel | Board | Physical input | Notes |
|---|---|---|---|
| CH0 | A | IN1 | |
| CH1 | A | IN2 | |
| CH2 | B | IN1 | |
| CH3 | B | IN2 | |

(Confirm input polarity/threshold/AC-DC coupling expectations for detector pulses.)

## 6. Open decisions

Move each to the decision log below once settled, and write an ADR for the architectural ones.

- **D1 — Clock-sharing scheme** between Board A and Board B (see §4).
- **D2 — Where coincidence logic lives** (PL vs per-board ARM vs host; see §3).
- **D3 — GUI stack** (web app served from a board, vs desktop Python/Qt on the host). Must be free and portable for non-engineer users.
- **D4 — Timestamp wire format** between boards and host (compactness vs simplicity; ordering/merging strategy).
- **D5 — Photon-number method** — which reference technique, and what it implies for the data path and coincidence windows.
- **D6 — Target coincidence window & max count rate** — drives D2/D4; depends on the experiment class (g²(0)/HBT, heralded singles, HOM, multiplexed PNR).
- **D7 — Vivado version & build flow** — pin it once and record in CLAUDE.md.

## 7. Decision log

_Decisions that have been made. Newest first. Link ADRs where written._

- _(none yet)_

## 8. Milestones / roadmap

See `docs/milestones.md` for the working roadmap; high-level order is S0 → S7 above.

## 9. Risks

- Inter-board clock coherence not achievable to the needed precision → coincidence resolution capped. _Mitigation: settle D1 early, validate with function generator before any optics._
- Host data path can't sustain the count rate → dropped tags. _Mitigation: settle D6 early; size buffers; test with high-rate pulse trains._
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

Index of the papers in the Refs folder (to be filled in once shared). For each: short tag, full citation, what we use it for.

- _(to be added)_

## Changelog

- _(start here: date — what changed — who)_
