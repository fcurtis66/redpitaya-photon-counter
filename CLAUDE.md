# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Persistent context for Claude Code working in this repository.
Keep this file under ~200 lines and high-signal: every line should change behaviour.
Project context lives here; the full architecture, decisions, and open questions live in `DESIGN.md` (read it at the start of any architecture or design work).

## What this project is

A modular photon counter / time tagger for quantum-optics experiments, built on Red Pitaya STEMlab 125-14 boards (Zynq-7010). It extends Michel Adamic's `zynq_tdc` tapped-delay-line TDC to:

1. Run on two boards = 4 input channels (2 fast inputs per board).
2. Add cross-board coincidence logic.
3. Add photon-number discrimination.
4. Provide a GUI usable by experimentalists who don't know VHDL/Verilog.
5. Be modular: N boards daisy-chained with little loss of performance.

## Who you are working with

The maintainer is an MSc student, comfortable with hardware-synthesis *concepts* but who does **not** write VHDL/Verilog and is not a professional software engineer. Explain HDL changes and any non-trivial code in plain language. Prefer small, reviewable steps over cleverness.

## Repository layout

Upstream Adamic sources are preserved as-is. Treat them as a baseline: keep edits isolated and diffable against upstream.

```
AXITDC/           Adamic's TDC AXI IP core (VHDL sources + simulation testbenches + IP packager metadata)
  src/            Core VHDL: AXITDC.vhd (top wrapper), TDCchannel.vhd, control.vhd, counter.vhd, delayLine.vhd, encoder.vhd
  sim/            Testbenches (controlTb, counterTb, encoderTb)
src/              Vivado project sources: TDCsystem_bd.tcl (block design), ports.xdc, timing.xdc
board/            Red Pitaya board files for Vivado (1.1)
setup/            Board-side files: PLclock, TDCserver2.c, TDCsystem_wrapper.bit (pre-built)
figs/             Architecture diagrams
matlab/           MATLAB GUI (TDCgui5.mlapp — the current operator GUI, v5)
make_project.tcl  Vivado script: creates the full TDCsystem project from scratch
docs/             ADRs (docs/decisions/), milestones.md, hardware/deploy.md
host/             PC-side software: timestamp ingest, coincidence engine, calibration (to be built)
gui/              Replacement operator GUI (to be built; currently matlab/TDCgui5.mlapp is used)
scripts/          Build/deploy helpers (deploy.sh)
bitstreams/       Built .bit files, each committed alongside the source commit that produced it
```

## Facts that constrain the design

(Hardware facts tagged _[verified RP docs, Jun 2026]_ were checked against current Red Pitaya documentation; treat the rest as project notes until confirmed.)

### TDC core & toolchain
- STEMlab 125-14 = Zynq-7010. Adamic's TDC: ~350 MHz core clock, >11 ps resolution, ~14 ns dead time, ~70 MS/s, 47.9 ms measurement range.
- **Vivado 2018.2** — required to source `src/TDCsystem_bd.tcl` without version mismatch. Pin this; record any upgrade as an ADR.
- The PL clock must be lowered 125 → 100 MHz before TDC implementation (`setup/PLclock` does this).
- TDC inputs: E1 pins 17 & 18 (FPGA M14/M15), LVCMOS33 (3.3 V), **rising-edge** sensitive. Detector pulses must arrive as clean 3.3 V logic edges → a discriminator/comparator sits in front of each detector, and pulse amplitude/shape is discarded there.
- **The pre-built `setup/TDCsystem_wrapper.bit` is a 2-channel design.** Deployed identically to both boards it yields all 4 channels (CH0/CH1 on A, CH2/CH3 on B). No 4-channel bitstream or Vivado rebuild is needed through S3 — treat the bitstream as a **black box** until/unless the DMA work (D2) is taken on.
- The C server (`setup/TDCserver2.c`) exposes the TDC over TCP on **port 1001**. Each channel's BRAM holds 2048 × 64-bit timestamps. AXI base addresses: CH0 conf `0x43C00000`, CH0 BRAM `0x43C10000`; CH1 conf `0x43C20000`, CH1 BRAM `0x43C30000`.

### Clock coherence & cross-board timing (the crux — D1)
- Picosecond resolution is **within** a single board. The cross-board coincidence floor is set by inter-board clock-distribution **jitter**, NOT by TDC resolution. Calibration removes the *constant* skew; it does **not** remove the jitter — that residual is the irreducible cross-board timing spread.
- SATA daisy-chain sync routes the master clock *through the FPGA* to the ADC and **adds jitter** _[verified RP docs/forum, Jun 2026]_. External-clock distribution (Click-Shield-style, U.FL) is lower-jitter. For a ps timing instrument, **prefer low-jitter external distribution over the convenient SATA daisy chain.**
- Both boards MUST derive from **one** physical 125 MHz oscillator. Two independent sources drift → skew not constant → cannot be calibrated out. (This is the trap to avoid.)
- Board A (standard Starter Kit): internal crystal, **no reference-clock input** _[verified RP datasheet, Jun 2026]_ — accepting an external clock needs a HW mod. Board B (ext-clock IZD0031): must receive 125 MHz on **E2** or it won't operate. The two boards are mismatched, so getting both onto one oscillator is non-trivial — resolve the wiring before committing.
- The documented RP **X-Channel** sync is built from **Low-Noise** boards whose secondaries are SATA-clock-modified _[verified RP docs, Jun 2026]_; neither of our boards is that, and Board B's mod is for **E2, not SATA** — so X-Channel is **not drop-in**. The `daisy_tool` CLI enables shared clock **and trigger**; the shared trigger gives a common time origin (handles "do the boards' counters start together?").
- RP product churn: original X-Channel marked discontinued in docs, a new one relaunched ~Nov 2025 — **confirm current hardware/wiring with RP support + supervisor before buying a distribution amp or modifying Board A.**
- Calibration method: feed the **same edge** from the function generator to one channel on each board, measure the constant offset, store as per-board skew. Validate before any optics.

### PNR feasibility (shapes D5 — read before any PNR work)
- Fast analog inputs are **125 MS/s, DC–60 MHz** _[verified RP docs, Jun 2026]_ — ~50× below the "modest" 5 GS/s / 3 GHz the PNR reference papers call the minimum. **Trace/slope-based PNR via the RP analog path is NOT feasible on this hardware.**
- The TDC records **threshold-crossing times only** (no amplitude/shape). So slope-based PNR **cannot** be done as host post-processing of TDC data — there is no slope information in the stream.
- Viable PNR is **timing-based**, exploiting: higher photon number → steeper rising edge → threshold crossed ~tens of ps earlier (Kuijf et al.: slope projection ≈ C·Δt to first order):
  - *Single-threshold arrival-time-shift* — 1 TDC ch/detector + 1 laser-sync ch. Channel-efficient; weakest discrimination; tight jitter budget; **best done same-board** (cross-board clock jitter likely washes it out).
  - *Multi-threshold time-over-threshold* — 2–3 comparators/detector, each into its own TDC ch. Stronger signal; burns channels fast (2 thresh × 2 detectors = all 4 ch); needs external comparators.
  - *Spatial multiplexing (pseudo-PNR)* — split mode across click detectors, count hits. Coarse, channel/detector-hungry; a **different mechanism** from intrinsic PNR.
- Target use (discard heralds ≠ intended n, to lower g²(0)) only needs a clean **1 vs ≥2** cut — the most achievable regime. Per Sempere-Llagostera et al., the g²(0) reduction was **source-efficiency-limited, not detector-resolution-limited** — encouraging for a modest-resolution timing approach.

### Data path & count rate (shapes D4/D6)
- Lab laser: pulse every **12.5 ns = 80 MHz** rep rate. A few-ns coincidence window sits safely inside one pulse period (ample margin at ps resolution).
- **Throughput, not TDC speed, is what drops tags.** 64-bit tags over **1 GbE** _[verified RP docs, Jun 2026]_ ≈ **10–12 M tags/s aggregate per board** sustained (the packet-loss ceiling); the per-channel 2048-deep BRAM is only a ~29 µs burst buffer.
- TDC dead time (~14 ns) **> laser period (12.5 ns)** → cannot tag two consecutive laser pulses; relies on low per-pulse detection probability (and SNSPD reset) to stay sparse. Realistic single-photon singles rate is likely well under the Ethernet ceiling.
- A compact **32-bit / delta-encoded** wire format ≈ **doubles** the ceiling (full range+res needs ~32 bits, not 64) — do this **before** reaching for PL-side DMA. DMA reopens the bitstream (significant block-design work, not a quick add) — stretch only.

## Common commands

- **Create Vivado project from scratch:** in Vivado 2018.2 Tcl console, `source make_project.tcl` from the repo root
- **Lower PL clock on the board:** `./setup/PLclock` (run on the board via SSH)
- **Load prebuilt bitstream on the board (black-box S0–S3 flow, no Vivado):** `cat setup/TDCsystem_wrapper.bit > /dev/xdevcfg` (run after `PLclock`)
- **Compile C server on the board:** `gcc -o tdc_server setup/TDCserver2.c -lm` (gcc is present on the board's ARM Linux)
- **Deploy to a board:** `./scripts/deploy.sh board-a` — see `docs/hardware/deploy.md` for SSH setup
- **Build bitstream:** _TBD — record Vivado generate-bitstream command here once confirmed_
- **Run the C server:** _TBD — record start command and any systemd/init config here_
- **Run host / coincidence engine:** _TBD_

## How to work in this repo (behavioural guardrails)

Mistakes in HDL/firmware are slow and expensive to debug on real hardware, and the maintainer cannot always catch a bad VHDL diff by eye. So:

- **Surface assumptions before acting.** If a requirement is ambiguous, ask, or state the assumption explicitly. Do not silently pick an interpretation and build on it.
- **Change only what's asked.** Do not refactor, rename, or "improve" code the task didn't call for. Keep diffs minimal and reviewable.
- **Prefer the simplest thing that works.** No speculative abstraction ahead of need.
- **Don't claim success you haven't verified.** State what was actually tested vs. assumed; flag uncertainty rather than defaulting to a confident "done".
- **Preserve upstream provenance.** When editing Adamic's sources, isolate the change and note what and why; if it's architectural, also record an ADR.
- **Confirm before anything irreversible** — deleting files, force-pushing, overwriting bitstreams, or board-side operations that would need a re-flash.
- **Record architecture decisions** in `docs/decisions/` and reflect them in `DESIGN.md`.

## Decision status (snapshot — full rationale + ADRs in DESIGN.md / docs/decisions)

- **D7 (toolchain/build) — settling.** Vivado 2018.2 pinned; prebuilt 2-ch bitstream used as a black box through S3. → decision-log entry due.
- **D1 (clock sharing) — OPEN (crux).** Principle settled (one oscillator → constant skew → calibrate out); the *physical* scheme is not (which source, which connector per board, jitter vs convenience). Architectural → needs an **ADR**. Do not buy/modify hardware before confirming the wiring.
- **D2 (coincidence location) — direction settled: host.** Algorithm = k-way merge of the per-channel (already-sorted) streams → a single sliding-window pass; this is N-channel-ready, so skip the O(N²) brute-force prototype. → log entry + short ADR.
- **D4 (wire format) — OPEN; lean compact 32-bit/delta** (doubles the throughput ceiling — see data-path facts).
- **D5 (PNR method) — OPEN, reframed.** Not "slope PNR as host post-processing" (impossible on TDC data) but: *can a ps-TDC do same-board arrival-time-shift PNR well enough for a 1-vs-≥2 herald cut?* Feasibility question for S4; validate on the function generator (two slightly time-shifted pulses) before any detector. Depends on D1 jitter. Reference papers: Kuijf et al. (mean-derivative projection), Sempere-Llagostera et al. (rising-edge slope, g²(0) reduction) — add to DESIGN.md §11.
- **D6 (window/rate) — partially answered.** Few-ns window OK; sustained ceiling ~10–12 M tags/s/board (Ethernet-bound). Refine once the expected per-detector singles rate is known.

## Pointers

- Architecture, milestones, open questions → `DESIGN.md`
- Decision history → `docs/decisions/`
- Deploy workflow & SSH setup → `docs/hardware/deploy.md`, `scripts/deploy.sh`
- Upstream → Michel Adamic `madamic/zynq_tdc`. Our fork → `fcurtis66/redpitaya-photon-counter`. Prior art: a community 4-channel fork exists (`JosephFeld/zynq_tdc_4_channel`) — review it for ideas, keep our own provenance clean.
