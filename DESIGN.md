# DESIGN.md — Living Design Document

This is the single source of truth for the project's architecture, decisions, and open questions. It is meant to be edited continuously. Keep it honest: when something is undecided, say so; when a decision is made, move it from "Open decisions" into the decision log and (if architectural) write an ADR in `docs/decisions/`.

This file lives in the repo (so Claude Code reads it) **and** is uploaded to the Claude Project knowledge base (so planning chats read it). When it changes meaningfully, re-upload it to the Project.

_Last updated: 2026-06-16 — by <!-- name --> (planning-chat sync 2: D1 decided = Path B; clock source, trigger port, and wire-format payload verified from the HDL/block design)_

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

_Built-in intra-board aid (verified from `control.vhd`):_ each 64-bit timestamp word already embeds the **partner channel's event count** at the moment of the event (`data <= zeros & trigger_in & timestamp`). So for the two channels on one board the host gets a free ordering/pairing hint. This is **intra-board only** — it does nothing across boards, where ordering relies on the Path B shared time base (§4).

## 4. The clock-coherence problem (the crux)

The TDC's picosecond resolution is *within* a board. A coincidence between a channel on Board A and a channel on Board B is only as good as how phase-coherent the two boards' clocks are, plus a fixed inter-board skew.

- If both boards run from **one physical oscillator**, their time bases are frequency-locked and the relationship is stable. Two independent 125 MHz sources will drift relative to each other → skew not constant → uncalibratable. So a single shared oscillator is non-negotiable, not just preferable.
- **What calibration can and can't remove.** Calibration removes the *constant* part of the inter-board offset. It does **not** remove the *random* part — the clock-distribution **jitter**. That residual jitter is the true floor on cross-board coincidence timing, and it will be worse than the >11 ps single-board resolution. How much worse depends on the distribution method.
- Calibration method: feed the **same edge** from the function generator into one channel on each board, measure the constant offset, store it as that board's skew. Repeat per channel pair as needed. Validate before any optics.

**Verified hardware facts** _[Red Pitaya docs, Jun 2026]_ that shape the choice:

- The **SATA daisy-chain** sync (RP "X-Channel") routes the master clock *through the FPGA* to the ADC and **adds jitter**; RP recommend the external-clock / **Click-Shield** (U.FL) distribution when low noise matters. For a ps timing instrument, prefer low-jitter external distribution over the convenient SATA chain, and prefer a **star fan-out** over a literal daisy chain (no cumulative per-hop degradation; no board-2-kills-board-3 dependency) for the N-board modularity goal.
- **Our two boards are mismatched, so the synced system is built from external-clock boards.** Board A (standard Starter Kit) has its internal crystal and **no reference-clock input**, so it cannot join a shared-clock chain — it **stays the single-board dev unit** (S0/S1). The synchronised system is **Board B (IZD0031) + a second external-clock board**, both clocked from the **Click Shield's onboard 125 MHz oscillator** over U.FL. The Click Shield also supplies Board B's mandatory boot clock and is the chosen distribution method (D1, §7). Requires OS 2.00-23+ on the synced boards.
- The documented X-Channel system is built from **Low-Noise** boards whose secondaries are SATA-clock-modified — neither of our boards is one, and **Board B's modification is for E2, not SATA** — so X-Channel is **not drop-in**. The `daisy_tool` CLI enables shared clock **and trigger**; the shared trigger establishes a common time origin (handles "do the boards' counters start together?").
- RP product churn: the original X-Channel is marked discontinued while a new one relaunched ~Nov 2025. **Confirm current hardware and exact wiring with RP support + supervisor before buying a distribution amp or modifying Board A.**

**Where the TDC clock actually comes from — verified from `src/TDCsystem_bd.tcl`.** The TDC core's 350 MHz is produced by an MMCM (`clk_wiz_0`) whose input is **FCLK_CLK0** (100 MHz) from the PS — i.e. it derives from each board's **own PS reference crystal** (~33 MHz via the PS PLLs), **not** from the 125 MHz ADC/external clock. The ADC clock is not used anywhere in the design. **Consequence: sharing the 125 MHz across boards (Click Shield) does not by itself synchronise the TDCs** — each board's core still ticks on its independent PS crystal. Two ways to fix it:

- **Path A — shared reference, no bitstream change.** Feed a common reference edge (laser sync, or the Click Shield trigger) to one TDC channel on each board; do all timing relative to it on the host. Because the experiment is pulsed at 80 MHz, the reference recurs every 12.5 ns and inter-clock drift within that window is ~femtoseconds — negligible. Keeps the black box. **Cost: one channel per board for the reference** (so only 2 detectors on our two boards), and the per-board reference can't be shared.
- **Path B — re-clock the TDC from the shared 125 MHz. _CHOSEN (D1, §7 + ADR-0001)._** Modify the block design so the MMCM is fed by the shared external 125 MHz instead of FCLK0 (reconfigure for 350-from-125), so all boards' clocks are genuinely locked. With the Click Shield's shared trigger as a common origin, **all channels stay free for detectors and one shared sync serves the whole system** — the basis for unified, modular PNR (D5). Cost: opens the black box (block-design + IP work — *not* VHDL authoring; the hand-placed carry-chain TDC core is untouched) and requires **re-characterising resolution at the new clock**. Sequencing: S0/S1 stay on the internal-clock black box; Path B is the S2 work.

_Empirical confirmation (S0):_ on one board, a two-channel **difference** of near-simultaneous edges (shared clock, jitter cancels) gave σ ≈ 13.4 ps single-channel, whereas a single-channel **interval** across a full ~1 ms period (clock jitter accumulates) gave σ = 47.6 ps. This is the same principle Path B + short coincidence windows rely on: common-clock differences are TDC-limited, long intervals are clock-limited.

## 5. Channel map

Both TDC channels on a board are the **DIO7 pair** on E1 (verified from `src/ports.xdc` + the RP pinout): `hit0` = DIO7_P = FPGA **M14** = **E1 pin 17**; `hit1` = DIO7_N = FPGA **M15** = **E1 pin 18**. Ground on E1 pin 25/26. Inputs are LVCMOS33 (≤3.3 V), **rising-edge** sensitive. Avoid pin 1 (+3V3) and pin 2 (negative supply rail).

| Logical channel | Board | Physical input | FPGA ball |
|---|---|---|---|
| CH0 | A | E1 DIO7_P (pin 17) | M14 |
| CH1 | A | E1 DIO7_N (pin 18) | M15 |
| CH2 | B | E1 DIO7_P (pin 17) | M14 |
| CH3 | B | E1 DIO7_N (pin 18) | M15 |

(Confirm input polarity/threshold/AC-DC coupling for detector pulses. Physical pin numbers can differ on Gen 2 boards — M14/M15 is the invariant.)

_Channel roles & PNR reference (D5, under Path B):_ PNR needs a **time reference**; the laser sync is the natural one. Because Path B locks all boards to one time base, **a single laser-sync channel anywhere in the system** references every detector on every board → **2N−1 detectors** on N two-channel boards, all simultaneously time-tagging *and* PNR-capable (no separate "tag vs PNR" modes). The reference need **not** be the laser sync — a **self-reference comparator** scheme (two thresholds per detector) needs no sync but costs **2 channels per detector** → only N detectors. The AXITDC `trigger_in` port **cannot** carry the sync: it is an **inter-channel event-counter bus**, not an edge input (verified from `control.vhd`/`AXITDC.vhd`). Even (2N) detector counts would require adding a **dedicated sync channel in the FPGA** — feasible (E1 exposes 16 DIO; the 7010 has slice/BRAM headroom) but it is hand-placed carry-chain work (the one genuinely expert/invasive change).

## 6. Open decisions

Move each to the decision log below once settled, and write an ADR for the architectural ones. (D1, D2, D7 settled — see §7.)

- **D3 — GUI stack** (web app served from a board, vs desktop Python/Qt on the host). Must be free and portable for non-engineer users.
- **D4 — Timestamp wire format.** Leaning **compact / packed**. Verified from the core (`control.vhd`): each 64-bit BRAM word is `[21 zero bits][11-bit partner event-count][32-bit timestamp]` — only **43 bits of real payload**, 21 hardwired zeros. So a packed wire format nearly halves off-board data immediately (before any DMA) and roughly doubles the sustainable count rate (D6). Decide packing + merge/ordering strategy (merge is in §3).
- **D5 — Photon-number method.** **Reframed; reference mechanism analysed (see §5).** Trace/slope methods need the analog pulse (5 GS/s, 3 GHz); the RP analog path (125 MS/s, DC–60 MHz) is ~50× too slow and the TDC records threshold-crossing *times* only — so PNR must be **timing-based** (higher photon number → steeper edge → earlier crossing; Kuijf: projection ≈ C·Δt). Two reference mechanisms: **laser-sync** (1 shared channel, channel-efficient under Path B) or **self-reference comparators** (2 channels/detector, no sync). Still **open**: (1) feasibility — whether a ps-TDC's jitter budget resolves the tens-of-ps photon-number shifts for a clean **1-vs-≥2** cut; (2) which reference mechanism. Validate on the function generator (two slightly time-shifted pulses) before any detector. Sequenced after Path B (S4).
  - **Prerequisite (from S0 diagnostics):** per-tap **code-density calibration is load-bearing, not optional**. The delay-line DNL — the even/odd zig-zag plus a few CLB-boundary fat bins (worst ~74 ps), visible in the S0 baseline — sits at the **same tens-of-ps scale as the photon-number time shifts**, and imprints comb structure on the two-channel histogram. Raw taps must be linearised into real ps (using the S0 code-density table) before any PNR decision, and the discrimination point must not land on a known fat bin.
- **D6 — Target coincidence window & max count rate.** **Partially answered.** Lab laser fires every 12.5 ns (80 MHz); a **few-ns window** sits safely inside one pulse period with ample ps-resolution margin. Sustainable rate is **Ethernet-bound at ~10–12 M tags/s aggregate per board** (64-bit tags, 1 GbE), *not* TDC-limited; the 2048-deep BRAM is a ~29 µs burst buffer; TDC dead time (~14 ns) exceeds the laser period, so consecutive pulses can't both be tagged. Refine once the expected per-detector singles rate is known. Drives D4.

## 7. Decision log

_Decisions that have been made. Newest first. Link ADRs where written._

- **2026-06-16 — D1: cross-board clock sync via Path B (re-clock the TDC from a shared 125 MHz, distributed by Click Shield).** Verified from `src/TDCsystem_bd.tcl` that the TDC core derives from FCLK0 (each board's PS crystal), **not** the ADC clock — so sharing the ADC clock alone does not synchronise the TDCs. Chose **Path B** (re-point the MMCM to the shared external 125 MHz) over Path A (per-board laser-sync reference) because it locks the clocks, frees all channels for detectors, and lets one shared sync serve N boards — the basis for unified, modular PNR. Hardware: a second external-clock board + 2 Click Shields; **Board A (standard kit) stays the single-board dev unit, not in the synced chain**; synced boards need OS 2.x. Implementation pending (block-design re-clock for 350-from-125 + resolution re-characterisation; carry-chain core untouched). Architectural → **ADR-0001** (now Accepted). _Sequencing: S0/S1 on internal clock first; Path B is S2._
- **2026-06-15 — D2: cross-board coincidence runs on the host PC.** Per-board firmware stays identical; the host k-way-merges the per-channel streams and runs a single sliding-window pass. Chosen for modularity (add a board = add a stream); accepts throughput pressure on Ethernet/host, mitigated by a compact wire format (D4) and, only if needed, PL-side DMA. Architectural → **ADR-0002** (`docs/decisions/`).
- **2026-06-15 — D7: Vivado 2018.2 pinned; prebuilt 2-channel bitstream used as a black box.** `setup/TDCsystem_wrapper.bit` deployed identically to both boards covers all 4 channels (CH0/CH1 on A, CH2/CH3 on B), so no Vivado rebuild is needed through S3. The black box is reopened for the Path B re-clock (S2) and the DMA work. Any Vivado upgrade is itself recorded as an ADR. _(Toolchain pin — log entry, no standalone ADR.)_

## 8. Milestones / roadmap

See `docs/milestones.md` for the working roadmap; high-level order is S0 → S7 above.

**Status:** **S0 complete** (2026-06) — Adamic's TDC replicated on Board A (internal clock, OS 1.04). Baseline: 170 active taps, **16.81 ps avg bin width**, no missing codes, **single-channel σ ≈ 13.4 ps**. This is the **control** to re-measure after the OS-2.x port and the Path B re-clock. (Dead-time/range checks not yet reported.) Full numbers in `docs/milestones.md`.

## 9. Risks

- Inter-board clock-distribution **jitter** caps cross-board coincidence resolution below the single-board >11 ps. _Mitigation: Path B locks clocks via the low-jitter Click Shield; calibrate the constant skew on the function generator before any optics._
- **Path B re-clock changes the TDC's clock source** (FCLK0 → shared 125 MHz). The delay-line resolution is clock-dependent, so it **must be re-characterised** after the re-clock, and the bitstream rebuild must close timing at 350 MHz. _Mitigation: keep the carry-chain core untouched; re-run the code-density resolution test and compare to the S0 baseline before trusting cross-board numbers._
- Expanding past 2 channels/board (e.g. for even detector counts) means **hand-placed carry-chain work** — the most invasive part of the design and the maintainer can't write it. _Mitigation: prefer the laser-sync (2N−1) scheme; treat extra channels as a separate, scoped effort._
- Host data path can't sustain the count rate → dropped tags. Verified ceiling ≈ 10–12 M tags/s per board (64-bit tags over 1 GbE); only **43 of 64 bits are real payload** (`control.vhd`), so a packed format ~doubles headroom. _Mitigation: packed wire format (D4); size buffers; test high-rate trains; PL-side DMA as a last resort._
- Toolchain/bitstream reproducibility drift, incl. the **OS split** (Board A on OS 1.04 for the black-box `PLclock`/`xdevcfg` flow; synced boards on OS 2.x for Click Shield + the ported bitstream). _Mitigation: pin Vivado 2018.2 and the per-board OS in CLAUDE.md; commit bitstreams with their source commit._
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

- 2026-06 — **S0 complete + characterised.** Recorded the S0 baseline (16.81 ps avg bin width, 170 active taps, no missing codes, single-channel σ ≈ 13.4 ps) in §8 and `milestones.md` as the control for later changes. Added the single-vs-two-channel jitter evidence to §4 (supports Path B). Added a D5 prerequisite: per-tap code-density calibration is load-bearing for PNR because the delay-line DNL is at the photon-number signal scale. — <!-- name -->

- 2026-06-16 — Planning-chat sync 2. **Decided D1 = Path B** (re-clock the TDC from a shared 125 MHz via Click Shield); added the §7 entry and rewrote ADR-0001 to Accepted. Verified from `TDCsystem_bd.tcl` that the TDC clock comes from FCLK0/PS-crystal, not the ADC clock (§4), and documented the Path A vs Path B trade. Confirmed E1 pins (DIO7_P/N = M14/M15 = pins 17/18) and rewrote §5 with the laser-sync-vs-self-reference PNR economics. Verified from `control.vhd`/`AXITDC.vhd` that `trigger_in` is an inter-channel event-counter bus (not a usable sync input) and that only 43 of 64 BRAM bits are payload (informs D4); noted the partner-count intra-board coincidence aid (D2). Updated risks (Path B resolution re-characterisation, carry-chain expansion, OS split). — <!-- name -->
- 2026-06-15 — Planning-chat sync. Decided D2 (coincidence on host) and D7 (Vivado 2018.2 + black-box 2-ch bitstream); added decision-log entries and ADR-0001 (D1, Proposed) / ADR-0002 (D2, Accepted). Refined §4 with verified Red Pitaya clock/jitter facts and the Board A/B mismatch; reframed D5 (timing-based PNR, not analog-trace); answered D6 in part (80 MHz laser, few-ns window, ~10–12 M tags/s/board Ethernet ceiling); leaned D4 toward compact 32-bit/delta tags; populated §11 with the two PNR papers. — <!-- name -->
