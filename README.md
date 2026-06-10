# redpitaya-photon-counter

A modular, cost-efficient photon counter / time tagger for quantum-optics experiments, built on Red Pitaya STEMlab 125-14 boards (Zynq-7010). It extends Michel Adamic's [`zynq_tdc`](https://github.com/madamic/zynq_tdc) tapped-delay-line time-to-digital converter into a multi-board system with cross-board coincidence logic, photon-number discrimination, and a GUI for experimentalists.

Fork: [`fcurtis66/redpitaya-photon-counter`](https://github.com/fcurtis66/redpitaya-photon-counter) — MSc summer project (Quantum Dynamics). Work in progress.

## What it does (target)

- Replicates Adamic's single-board TDC performance (>11 ps resolution).
- Runs across two boards for 4 input channels, clock-synchronised and skew-calibrated.
- Detects coincidences across channels and boards.
- Discriminates photon number (technique from referenced papers).
- Exposes a GUI so non-VHDL users can configure and run the counter.
- Scales: additional boards can be daisy-chained with little loss of performance.

## Provenance & licence

This repository builds on Michel Adamic's `zynq_tdc`. Upstream sources are preserved and changes are kept diffable against them. The upstream project appears to be licensed **GPL-3.0** — confirm against the fork and ensure this repository complies (the derived work likely inherits GPL-3.0). A community 4-channel fork ([`JosephFeld/zynq_tdc_4_channel`](https://github.com/JosephFeld/zynq_tdc_4_channel)) exists and is worth reviewing as prior art.

## Layout

```
CLAUDE.md            Persistent context for Claude Code (auto-loaded each session)
DESIGN.md            Living design doc: architecture, decisions, open questions
README.md            This file
docs/
  decisions/         Architecture Decision Records (ADRs)
  milestones.md      Working roadmap
  hardware/          Board notes, clock-sync notes, pinouts
  refs/              References index (papers in the Refs folder)
host/                PC-side software: ingest, coincidence engine, calibration
gui/                 Operator GUI
scripts/             Build/deploy helpers (PLclock, board deploy)
bitstreams/          Built .bit files (committed with their source commit)
<upstream dirs>      Adamic's TDC IP core, top-level block design, C server, figures (preserved)
```

(The upstream directory names are confirmed once the fork is cloned; see `CLAUDE.md`.)

## Getting started

1. Clone: `git clone https://github.com/fcurtis66/redpitaya-photon-counter.git`
2. Read `DESIGN.md` for the architecture and the open decisions.
3. Hardware: see `docs/hardware/` for the clock-sharing plan once decided.
4. Toolchain: Vivado (version to be pinned — see `CLAUDE.md` → Common commands).

## Hardware

- Board A — STEMlab 125-14 Starter Kit (internal clock).
- Board B — STEMlab 125-14 External-clock Starter Kit (IZD0031); needs an external 125 MHz clock via E2 to boot.
- Function generator — pulse/clock source for testing and inter-board skew calibration.
