# ADR-0001 — Inter-board clock sharing & TDC re-clocking (D1)

- **Status:** Accepted (Path B) — implementation pending (S2)
- **Date:** 2026-06-15 (proposed) → 2026-06-16 (accepted)
- **Deciders:** maintainer + supervisor
- **Relates to:** DESIGN.md §4 / §5, milestone S2, D5 (PNR)

## Context

Cross-board coincidence requires the synchronised boards to share a time base.
There are **two layers** to this, and the second was the surprise:

1. **Physical clock distribution.** All synced boards must derive from one
   physical oscillator (two independent sources drift → skew not constant →
   uncalibratable). Verified RP facts (Jun 2026): the SATA daisy-chain
   ("X-Channel") routes the clock *through the FPGA* and **adds jitter**; the
   **Click Shield** (U.FL, onboard 125 MHz oscillator, LVDS fan-out) is the
   low-jitter option RP recommends, and it also supplies the external-clock
   board's mandatory boot clock. Requires OS 2.00-23+.
2. **The TDC must actually *use* the shared clock.** Verified from
   `src/TDCsystem_bd.tcl`: the TDC core's 350 MHz comes from an MMCM fed by
   **FCLK_CLK0** (PS, ~33 MHz crystal → PLLs), **not** from the 125 MHz ADC/
   external clock — which is unused in the design. So **sharing the 125 MHz does
   not by itself synchronise the TDCs**; each board's core still ticks on its own
   PS crystal.

Calibration removes the *constant* inter-board skew but never the *jitter*, which
sets the true cross-board floor (worse than single-board >11 ps).

## Options (for layer 2)

- **Path A — shared reference, no bitstream change.** Feed a common reference
  edge (laser sync / Click Shield trigger) to one TDC channel per board; time
  everything relative to it on the host. The 80 MHz pulsed experiment makes the
  reference recur every 12.5 ns, so inter-clock drift within that window is
  ~femtoseconds (negligible). Keeps the black box. **Cost: one channel per board
  for the reference (→ 2 detectors on our two boards); the reference cannot be
  shared across boards.**
- **Path B — re-clock the TDC from the shared 125 MHz.** Modify the block design
  so the MMCM input is the shared external 125 MHz (reconfigure for 350-from-125)
  instead of FCLK0, locking all boards' clocks. With the Click Shield's shared
  trigger as a common origin, **all channels stay free for detectors and one
  shared sync serves N boards.** Cost: opens the black box (block-design + IP
  work — *not* VHDL authoring; the hand-placed carry-chain TDC core is untouched)
  and requires re-characterising resolution at the new clock.

Board A (standard Starter Kit, no external-clock input) cannot join a shared-clock
chain and is **not** part of the synchronised system either way.

## Decision

**Path B**, with Click Shield distribution. Rationale: it locks the clocks
properly, frees every channel for detectors, and lets a single laser-sync channel
serve the whole system — which is the enabler for **unified, modular PNR** (D5,
the (2N−1)-detector economics in §5). Path A was the cheaper fallback but its
per-board reference channel and 2-detector ceiling undercut the modular-PNR goal.

Hardware: a second **external-clock STEMlab 125-14** (Zynq-7010, to keep the
bitstream identical) + **2 Click Shields** + U.FL (boxed). Board A stays the
single-board dev unit (S0/S1) on OS 1.04; synced boards run OS 2.x.

## Consequences

- **S2 now contains a real bitstream change**: re-point `clk_wiz_0` to the shared
  125 MHz, reconfigure for 350 MHz, rebuild, and **re-run the code-density
  resolution test** against the S0 baseline before trusting cross-board numbers.
  The external clock is lower-jitter than FCLK, so resolution should hold or
  improve — but measure, don't assume.
- **PNR (D5) becomes system-wide**, not same-board: with locked clocks, one
  laser-sync channel references every detector on every board.
- The `trigger_in` port is **not** a usable sync input — it is an inter-channel
  event-counter bus (verified `control.vhd`/`AXITDC.vhd`); the shared reference
  must occupy a real hit channel (or the Click Shield trigger path).
- Even (2N) detector counts would need a dedicated FPGA sync channel = hand-placed
  carry-chain work; out of scope unless required.
- Re-confirm exact Click Shield wiring/SKUs with RP + supervisor before purchase.
- Update with the **measured cross-board jitter** once S2 hardware is validated.
