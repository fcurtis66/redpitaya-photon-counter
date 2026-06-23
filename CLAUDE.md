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
- **S0 measured baseline (Board A, OS 1.04, 2026-06) — the control for later changes:** 170 active taps of 192, **16.81 ps avg bin width** (code-density, 83 884 counts), **no missing codes**, **single-channel σ ≈ 13.4 ps** (two-channel diff /√2). Expected carry-chain DNL: even/odd zig-zag + a few CLB-boundary fat bins (worst ~74 ps). Re-measure after the OS-2.x port and the Path B re-clock and compare to this.
- **Vivado 2025.2** — current pinned version (upgraded from 2018.2; `src/TDCsystem_bd.tcl` updated accordingly). Pin this; record any further upgrade as an ADR.
- The PL clock must be lowered 125 → 100 MHz before loading the bitstream (`setup/PLclock`). PLclock uses the old `devcfg` sysfs → **OS 1.04 only**; on OS 2.x the 100 MHz must be set via a device-tree overlay (see `docs/hardware/deploy.md`).
- TDC inputs: E1 pins 17 & 18 (FPGA M14/M15), LVCMOS33 (3.3 V), **rising-edge** sensitive. Detector pulses must arrive as clean 3.3 V logic edges → a discriminator/comparator sits in front of each detector, and pulse amplitude/shape is discarded there.
- **The pre-built `setup/TDCsystem_wrapper.bit` is a 2-channel design.** Deployed identically to both boards it yields all 4 channels (CH0/CH1 on A, CH2/CH3 on B). No 4-channel bitstream or Vivado rebuild is needed through S3 — treat the bitstream as a **black box** until/unless the DMA work (D2) is taken on.
- The C server (`setup/TDCserver2.c`) exposes the TDC over TCP on **port 1001**. Each channel's BRAM holds 2048 × 64-bit timestamps. AXI base addresses: CH0 conf `0x43C00000`, CH0 BRAM `0x43C10000`; CH1 conf `0x43C20000`, CH1 BRAM `0x43C30000`.

### Clock coherence & cross-board sync (the crux — D1 DECIDED: Path B)
- Picosecond resolution is **within** a single board. The cross-board floor is set by clock-distribution **jitter**, not TDC resolution; calibration removes the *constant* skew but never the jitter.
- **The TDC core clock derives from FCLK0 (the PS crystal), NOT the 125 MHz ADC/external clock** _[verified from `src/TDCsystem_bd.tcl`]_: the `clk_wiz_0` MMCM is fed by `FCLK_CLK0` (100 MHz) → 350 MHz; the ADC clock is unused in the design. **So sharing the 125 MHz alone does NOT synchronise the TDCs** — each board ticks on its own PS crystal.
- **D1 = Path B:** re-clock the TDC MMCM from the shared external 125 MHz (reconfigure for 350-from-125) so all boards' clocks lock. Distributed by the **Click Shield** (onboard 125 MHz, low-jitter LVDS fan-out; also supplies Board B's boot clock; needs OS 2.00-23+). Frees all channels for detectors and lets one shared sync serve N boards (enables unified PNR — D5). → ADR-0001.
- **Path B opens the black box** (block-design/IP work, *not* VHDL; the carry-chain core is untouched) and **requires re-characterising resolution at the new clock** after rebuild.
- Rejected alternative (Path A): per-board laser-sync reference, no bitstream change, but costs 1 channel/board → only 2 detectors. Pulsed-experiment drift over the 12.5 ns laser period is ~fs (negligible), so Path A *works* — it just doesn't free channels.
- **Board A (standard kit) has no external-clock input** _[verified RP datasheet]_ → it stays the single-board dev unit (S0/S1), NOT in the synced chain. Synced system = external-clock boards (Board B + a new one) on Click Shields.
- SATA daisy-chain ("X-Channel") adds jitter (clock routed through the FPGA) _[verified]_ and uses Low-Noise boards we don't have → not used; Click Shield preferred.

### PNR feasibility (shapes D5 — read before any PNR work)
- Fast analog inputs are **125 MS/s, DC–60 MHz** _[verified RP docs]_ — ~50× below the 5 GS/s / 3 GHz the PNR papers call minimum. **Trace/slope PNR via the RP analog path is NOT feasible.** The TDC records **threshold-crossing times only** — no amplitude/shape in the stream.
- Viable PNR is **timing-based** (higher photon number → steeper edge → earlier crossing; Kuijf: projection ≈ C·Δt). Two reference mechanisms:
  - *Laser-sync (external ref)* — 1 channel per detector + **one shared sync** for the whole system (under Path B's locked clocks) → **2N−1 detectors** on N 2-ch boards, all simultaneously tagging + PNR-capable.
  - *Self-reference comparators* — two thresholds/detector → **2 channels/detector**, no sync → only N detectors; needs external comparators. (Proves PNR does **not** require a laser sync.)
- The AXITDC **`trigger_in` port canNOT carry the sync** — it is an inter-channel **event-counter bus**, not an edge input _[verified `control.vhd`/`AXITDC.vhd`]_. The sync must occupy a real hit channel.
- Even (2N) detector counts → need a **dedicated FPGA sync channel** = hand-placed carry-chain work (2 ch/board is Adamic's choice, not a HW limit; E1 exposes 16 DIO).
- Target use (discard heralds ≠ intended n, to lower g²(0)) needs only a clean **1-vs-≥2** cut — the achievable regime; per Sempere-Llagostera the limit was source efficiency, not detector resolution.
- **Per-tap code-density calibration is a PNR prerequisite, not optional** (from S0 diagnostics): the delay-line DNL (zig-zag + ~74 ps fat bins) is at the **same tens-of-ps scale as the photon-number shifts**, so linearise raw taps with the S0 calibration table before any PNR decision, and keep the discrimination point off known fat bins.
- Still **OPEN**: feasibility — does the jitter budget resolve the tens-of-ps photon-number shifts? Validate on the function generator (two slightly time-shifted edges) before any detector.

### Data path & count rate (shapes D4/D6)
- Lab laser: pulse every **12.5 ns = 80 MHz** rep rate. A few-ns coincidence window sits safely inside one pulse period (ample margin at ps resolution).
- **Throughput, not TDC speed, is what drops tags.** 64-bit tags over **1 GbE** _[verified RP docs, Jun 2026]_ ≈ **10–12 M tags/s aggregate per board** sustained (the packet-loss ceiling); the per-channel 2048-deep BRAM is only a ~29 µs burst buffer.
- TDC dead time (~14 ns) **> laser period (12.5 ns)** → cannot tag two consecutive laser pulses; relies on low per-pulse detection probability (and SNSPD reset) to stay sparse. Realistic single-photon singles rate is likely well under the Ethernet ceiling.
- **Only 43 of every 64 BRAM bits are payload** _[verified `control.vhd`]_: `[21 zeros][11-bit partner event-count][32-bit timestamp]`. A **packed wire format ~halves off-board volume** (and ~doubles the count-rate ceiling) before any DMA. The partner-count is a free **intra-board** coincidence-ordering hint (cross-board needs the Path B time base). DMA reopens the bitstream (significant block-design work) — stretch only.

## Common commands

- **Create Vivado project from scratch:** in Vivado 2025.2 Tcl console, `source make_project.tcl` from the repo root
- **Lower PL clock on the board:** `./setup/PLclock` (run on the board via SSH)
- **Load bitstream — OS 1.04 (Board A):** `cat setup/TDCsystem_wrapper.bit > /dev/xdevcfg` (after `PLclock`). **OS 2.x (synced boards):** `bootgen` → `.bit.bin`, load with `fpgautil -b`, and set the 100 MHz PL clock via a device-tree overlay (PLclock fails on 2.x). See `docs/hardware/deploy.md`.
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

- **D1 (clock sync) — DECIDED: Path B.** Re-clock the TDC from a shared 125 MHz (Click Shield) because the TDC core runs off the PS crystal, not the ADC clock (verified from the block design). Board A stays standalone; synced system = external-clock boards on OS 2.x. Implementation pending (S2). → ADR-0001 (Accepted).
- **D2 (coincidence location) — DECIDED: host.** k-way merge of per-channel streams → single sliding-window pass; skip the O(N²) prototype. → ADR-0002.
- **D7 (toolchain) — DECIDED.** Vivado 2025.2 (upgraded from 2018.2); prebuilt 2-ch bitstream as black box through S3; Board A on OS 1.04. → decision log.
- **D3 (GUI stack) — OPEN.** Free + portable for non-engineers.
- **D4 (wire format) — OPEN; lean packed.** Only 43/64 bits are payload → packed format ~doubles the rate ceiling.
- **D5 (PNR) — OPEN (feasibility).** Timing-based; laser-sync (2N−1, system-wide under Path B) vs self-reference comparators (2 ch/detector). `trigger_in` ruled out as a sync input. Per-tap code-density calibration is a prerequisite (DNL at the photon-number scale). Validate the jitter budget on the function generator first.
- **D6 (window/rate) — partially answered.** Few-ns window OK; ~10–12 M tags/s/board Ethernet ceiling; refine once singles rate known.

## Pointers

- Architecture, milestones, open questions → `DESIGN.md`
- Decision history → `docs/decisions/`
- Deploy workflow & SSH setup → `docs/hardware/deploy.md`, `scripts/deploy.sh`
- Upstream → Michel Adamic `madamic/zynq_tdc`. Our fork → `fcurtis66/redpitaya-photon-counter`. Prior art: a community 4-channel fork exists (`JosephFeld/zynq_tdc_4_channel`) — review it for ideas, keep our own provenance clean.
