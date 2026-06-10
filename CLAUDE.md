# CLAUDE.md

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

- Upstream Adamic sources are preserved as-is (TDC IP core, top-level block design, the C server, figures). Treat them as a baseline: keep edits isolated and diffable against upstream.
- `docs/` — `DESIGN.md` lives at the root; `docs/` holds ADRs (`docs/decisions/`), hardware notes, a references index, and milestones.
- `host/` — PC-side software: timestamp ingest, coincidence engine, calibration.
- `gui/` — operator GUI.
- `scripts/` — build/deploy helpers (e.g. the `PLclock` script, board deploy).
- `bitstreams/` — built `.bit` files, each committed alongside the source commit that produced it.

(Confirm exact upstream directory names against the fork once cloned, and correct this list if they differ.)

## Facts that constrain the design

- STEMlab 125-14 = Zynq-7010. Adamic's TDC: ~350 MHz core clock, >11 ps resolution, ~14 ns dead time, ~70 MS/s, 47.9 ms measurement range.
- The PL clock must be lowered 125 → 100 MHz before TDC implementation (the `PLclock` script does this).
- Picosecond resolution is **within** a single board. Cross-board coincidence is limited by inter-board clock coherence plus a fixed, calibratable skew — not by the TDC resolution.
- Original-gen 125-14 multi-board sync is over the **SATA** connectors: one *primary* (unmodified) transmits clock + trigger; *secondary* boards need a resistor mod (R25/R26 → R27/R28) to receive clock over SATA.
- The external-clock board (IZD0031) takes its 125 MHz clock via the **E2** connector and will not boot without it.
- How the two boards share a clock is an **open decision** — see `DESIGN.md`.
- The function generator is the calibration/test source for time-tagging and for measuring inter-board skew, before any real optics.

## Common commands

Fill these in as the toolchain is established, so they are never re-derived from scratch:

- Build bitstream: _TBD (Vivado — record version here)_
- Lower PL clock on the board: `./PLclock`
- Deploy to a board: _TBD_
- Run the C server on the ARM core: _TBD_
- Run host / coincidence engine: _TBD_

## How to work in this repo (behavioural guardrails)

Mistakes in HDL/firmware are slow and expensive to debug on real hardware, and the maintainer cannot always catch a bad VHDL diff by eye. So:

- **Surface assumptions before acting.** If a requirement is ambiguous, ask, or state the assumption explicitly. Do not silently pick an interpretation and build on it.
- **Change only what's asked.** Do not refactor, rename, or "improve" code the task didn't call for. Keep diffs minimal and reviewable.
- **Prefer the simplest thing that works.** No speculative abstraction ahead of need.
- **Don't claim success you haven't verified.** State what was actually tested vs. assumed; flag uncertainty rather than defaulting to a confident "done".
- **Preserve upstream provenance.** When editing Adamic's sources, isolate the change and note what and why; if it's architectural, also record an ADR.
- **Confirm before anything irreversible** — deleting files, force-pushing, overwriting bitstreams, or board-side operations that would need a re-flash.
- **Record architecture decisions** in `docs/decisions/` and reflect them in `DESIGN.md`.

## Pointers

- Architecture, milestones, open questions → `DESIGN.md`
- Decision history → `docs/decisions/`
- Deploy workflow & SSH setup → `docs/hardware/deploy.md`, `scripts/deploy.sh`
- Upstream → Michel Adamic `madamic/zynq_tdc`. Our fork → `fcurtis66/redpitaya-photon-counter`. Prior art: a community 4-channel fork exists (`JosephFeld/zynq_tdc_4_channel`) — review it for ideas, keep our own provenance clean.
