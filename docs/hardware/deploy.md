# Deploy & bring-up — Adamic TDC on Red Pitaya

Repeatable procedure for getting Adamic's 2-channel TDC running on a board and
verifying its performance (milestone **S0** on Board A, **S1** on Board B).

Facts here tagged _[verified, Jun 2026]_ were checked against current Red Pitaya
docs/datasheets; untagged items are project convention. See `CLAUDE.md` and
`DESIGN.md` for the wider context, and `docs/decisions/` for the ADRs.

---

## 0. Safety first (read before wiring)

The TDC inputs are **direct 3.3 V FPGA pins** on E1 — no protection, no 50 Ω
termination. Absolute max on any DIO pin is **−0.40 V to 3.3 V + 0.55 V**
_[verified]_; exceeding it damages the FPGA permanently.

- **Function-generator output load MUST be set to High-Z.** If the Siglent is set
  to "50 Ω load" while driving the high-impedance FPGA pin, the real output is
  **2×** the displayed value (3.3 V set → ~6.6 V actual → dead pin).
- **Scope-verify every new signal at ≤ 3.3 V before it touches the board.**
- Drive levels **0 V (low) to ~3.0 V (high)** — leave margin below 3.3 V.
- Watch for **overshoot** on fast edges into a cable; keep cables short.
- Connect/disconnect E1 jumpers with the board **powered off**.
- **Avoid E1 pin 1 (+3.3 V) and pin 2 (negative supply rail, ~−3.3 to −4 V).**

---

## 1. Hardware connections

### E1 input pin map (both boards)

The bitstream hard-constrains the two TDC channels to FPGA balls **M14/M15**
(`src/ports.xdc`), which are the **DIO7** pair on E1:

| Logical | Signal           | FPGA ball | E1 pin |
|---------|------------------|-----------|--------|
| CH0     | `hit0` / DIO7_P  | M14       | **17** |
| CH1     | `hit1` / DIO7_N  | M15       | **18** |
| Ground  | GND              | —         | **25 or 26** |

- DIO7_P/N are the **9th pin-pair from the +3V3 end (pin 1)**. Locate the pin-1
  marker on the PCB silkscreen and count up 9 pairs.
- DIO7 defaults to **GPIO** (its CAN alternate is off by default) — no config.
- Confirm the GND pin with a multimeter (continuity to an SMA connector shell)
  before connecting signals. Physical pin numbers can differ on Gen 2 boards —
  always re-confirm against that board's pinout; M14/M15 is the invariant.

### Signal source / scope

- **Function generator:** Siglent SDG2042X (40 MHz max — fine for test pulses;
  **cannot** clock Board B, see §2).
- **Scope:** Tektronix TDS2024C (200 MHz, 4-ch) — used as the safety gate
  (verify ≤ 3.3 V, check edges) and for ns-level sanity. It cannot resolve the
  ps-scale TDC timing; that comes from the TDC's own statistics.
- Cabling: BNC-to-flying-lead (or BNC→screw-terminal) + female Dupont jumpers to
  the E1 header; an IDC ribbon + breakout is safer than loose jumpers. Use
  **equal-length** cables for two-channel tests. Tee the scope in with a BNC T to
  monitor while acquiring.

---

## 2. OS setup

The board-side scripts decide the OS, because **`setup/PLclock` uses the old
`devcfg` sysfs interface** (`/sys/devices/soc0/amba/f8007000.devcfg/...`) that was
**removed in OS 2.00** _[verified]_ when Red Pitaya moved to the Linux FPGA
Manager framework.

### Board A (Gen 1) — OS 1.04

Run S0 on **OS 1.04**, the newest pre-2.0 release, so `PLclock` and
`cat > /dev/xdevcfg` work unmodified. This isolates wiring/test-bench bugs from
OS-port bugs.

1. Download the **OS 1.04** image from the Red Pitaya **software archive**
   (current download pages list only 2.x; older images live in the archive)
   _[verified]_.
2. Flash with **balenaEtcher** to a ≥ 8 GB class-10 microSD (select image →
   select SD card → Flash; double-check the target drive).
3. Boot (SD + Ethernet + power); reach at `rp-xxxxxxxx.local` or DHCP IP.
4. `ssh root@<ip>` (password historically `root` — confirm for your image).

### Board B + synchronised boards — OS 2.x (required)

Click Shield synchronisation **requires OS 2.00-23 or newer on all units**
_[verified]_, so the synced boards run OS 2.x and need the bitstream port (§4,
Appendix A). Board A stays the single-board dev unit on 1.04.

> Pin the per-board OS choice in `CLAUDE.md` (D7 reproducibility).

---

## 3. Deploy the TDC — OS 1.04 path (Board A)

```bash
# from repo root, on the host:
scp -r setup/ root@<ip>:/root/            # PLclock, TDCserver2.c, bitstream

# on the board (ssh):
cd /root/setup
./PLclock                                  # lower PL clock 125 -> 100 MHz (must run first)
cat TDCsystem_wrapper.bit > /dev/xdevcfg   # load bitstream (OS 1.04 method)
gcc -o tdc_server TDCserver2.c -lm         # compile C server
./tdc_server                               # serves TDC over TCP on port 1001
```

Sanity: the server should report listening on **port 1001**. Each channel's BRAM
holds 2048 × 64-bit timestamps (AXI addrs in `CLAUDE.md`).

---

## 4. Host readout (MATLAB GUI)

1. Open `matlab/TDCgui5.mlapp` in MATLAB App Designer.
2. Connect to `<board-ip>:1001`.
3. With a slow pulse train on CH0, confirm timestamps appear at the expected
   interval. That is S0 "first light".

(A Python TCP client to port 1001 is the planned `host/` replacement; not needed
for S0.)

---

## 5. S0 performance tests (the pass/fail)

Record each measured value next to the paper's spec — that table is the S0
checklist in `milestones.md`. Target specs: >11 ps resolution, ~14 ns dead time,
47.9 ms range, ~70 MS/s, ~350 MHz core.

1. **First light** — low-rate pulse on CH0; timestamps arrive at the rep-rate
   interval. Confirms the whole chain.
2. **Two-channel skew / single-shot jitter** — split one generator edge to CH0
   (pin 17) and CH1 (pin 18) via a BNC-T with **equal-length** cables. Histogram
   Δt = t(CH1) − t(CH0). Mean = channel/cable skew; σ = combined single-shot
   jitter (≈ √2 × per-channel). Sanity + a first resolution figure.
3. **Resolution / bin width (the >11 ps number)** — feed a signal **asynchronous**
   to the TDC core clock; histogram the fine-time codes. Bin widths give the LSB
   and DNL/INL. Use the same statistical (code-density) method as the paper so
   numbers are comparable.
4. **Dead time (~14 ns)** — two pulses with decreasing separation (double-pulse /
   burst, or the two phase-locked Siglent channels). Find the minimum spacing at
   which **both** are still timestamped.
5. **Range (47.9 ms)** — low-frequency input; confirm timestamps climb to
   ~47.9 ms before the coarse counter rolls over.
6. **(Optional) Throughput** — high-rate train. Note the off-board path saturates
   at the **~10–12 M tags/s Ethernet ceiling** (64-bit tags, 1 GbE) before the
   TDC's ~70 MS/s — so confirm core behaviour, not full off-board rate.

---

## 6. S1 (Board B)

Provide Board B's 125 MHz via the **Click Shield onboard oscillator** (Board B's
own external-clock requirement; the Siglent's 40 MHz can't do it). On OS 2.x with
the ported bitstream (Appendix A), repeat §3–§5. No cross-board work yet — that is
S2 and depends on D1 + the clock-source question (Appendix B).

---

## Appendix A — OS 2.x bitstream port (for B / synced boards)

1. **Convert the bitstream** on the host (Vivado 2018.2 ships `bootgen`):
   ```
   echo -n "all:{ TDCsystem_wrapper.bit }" > fpga.bif
   bootgen -image fpga.bif -arch zynq -process_bitstream bin -o TDCsystem_wrapper.bit.bin -w
   ```
2. **Load with FPGA Manager:** `fpgautil -b /root/setup/TDCsystem_wrapper.bit.bin`
   (or `overlay.sh` with a project dir).
3. **Reproduce the 100 MHz PL clock.** `PLclock` will NOT work on OS 2.x. The
   documented route is a **device-tree overlay** that sets the PL clock to
   100 MHz, loaded via `overlay.sh`. _Author/validate this `.dtbo`; this is the
   real work of the port, not the bootgen step._ **TODO: confirm and record the
   exact method here once tested.**

## Appendix B — Cross-board sync: the TDC clock source (RESOLVED → Path B)

**Confirmed from `src/TDCsystem_bd.tcl`:** the TDC core's 350 MHz is produced by
the `clk_wiz_0` MMCM whose input is **FCLK_CLK0** (100 MHz from the PS, i.e. each
board's own PS crystal). The 125 MHz ADC/external clock is **not used anywhere**
in the design. So sharing the 125 MHz (Click Shield) does **not** by itself
synchronise the two TDCs — each ticks on its independent PS crystal.

**Decision (D1, ADR-0001): Path B.** S2 re-clocks the TDC by re-pointing
`clk_wiz_0/clk_in1` from `FCLK_CLK0` to the shared external 125 MHz and
reconfiguring the MMCM for 350-from-125 (e.g. VCO 875 MHz: ×7 then ÷2.5). Then
rebuild and **re-run the code-density resolution test** (§5 step 3) against the S0
baseline — the delay-line resolution is clock-dependent and must be re-verified.
The carry-chain TDC core is **not** touched. This is block-design/IP work, not
VHDL authoring.

(Path A — a per-board laser-sync reference with no bitstream change — was the
fallback; it works because pulsed-experiment drift over 12.5 ns is ~fs, but it
costs one channel per board. Rejected in favour of Path B's all-channels-free,
one-shared-sync scaling. See ADR-0001.) Does not affect S0/S1.

---

## Troubleshooting quick hits

- **No timestamps:** check `PLclock` ran *before* the bitstream load; check the
  C server is up on :1001; scope-confirm the pulse actually reaches pin 17 at
  3.3 V logic; confirm rising edges (TDC is 0→1 sensitive).
- **Nonsense / no edges:** likely wrong E1 pin — re-verify pin 17/18 vs pin-1
  marker.
- **Board dead after wiring:** suspect over-voltage (load setting / overshoot) or
  a jumper on pin 1/2.
- **`/dev/xdevcfg` missing:** you are on OS 2.x — use Appendix A.
