# Candidate builds (issue #132) — supporting evidence, nothing here is landed

**Read this first.** Everything in this directory is **Claim B** of record
`20260923-093000-28a7c96`: a lever matrix measuring *what it would take* to
close 100 MHz at all eighteen ratified corners. **None of it is a claim
about `layout/modexp.def`**, which is Claim A, lives one directory up in
`../sta-corner-sweep-results.json`, and closes at **10 of 18** corners with
the binding corner `ss_n40C_1v28` at **22.80 MHz**.

Every build here was produced inside the gitignored `flow/build/` scratch
tree against *copies* of the RTL. Nothing in `rtl/`, `layout/` or
`flow/par-modexp.json` was modified to produce any of it.

## The matrix

`candidate-matrix.json` is the machine-readable summary; the verbatim
`klt sta` envelope for each row is in that row's own directory. Row 0 (the
committed layout) is included in the matrix for comparison but its envelope
is the sign-off leg one directory up.

| Row | Directory | RTL | Synthesis | P&R corner |
|---|---|---|---|---|
| 0 | `../sta-corner-sweep-results.json` | single-cycle (committed) | unconstrained, `tt` | `tt_025C_1v80` |
| 1 | `01-constrained-synthesis/` | single-cycle (committed) | 10 ns @ `ss_n40C_1v28` | `tt_025C_1v80` |
| 2 | `02-cell-exclusion-only/` | single-cycle (committed) | 10 ns @ ss **+ 209-cell exclusion** | `tt_025C_1v80` |
| 3 | `03-bit-serial/` | bit-serial candidate | 10 ns @ `ss_n40C_1v28` | `tt_025C_1v80` |
| 4 | `04-bit-serial-ss-par/` | bit-serial candidate | 10 ns @ `ss_n40C_1v28` | **`ss_n40C_1v28`** |
| 5 | `05-bit-serial-cell-exclusion/` | bit-serial candidate | 10 ns @ ss **+ exclusion** | `tt_025C_1v80` |
| 6 | `06-bit-serial-cell-exclusion-ss-par/` | bit-serial candidate | 10 ns @ ss **+ exclusion** | **`ss_n40C_1v28`** |

All seven share `flow/par-modexp.json`'s floorplan verbatim (35%
utilization, `core_margin_um` 4, the `power` block, `io` layers met3/met2,
seed 42, `target_stage: route`) and a 10.0 ns clock; only `pdk.corner`
varies. All seven are characterized by `klt sta` over the same eighteen
ratified corners, `spef` omitted.

## What is in each row's directory

| File | What it is |
|---|---|
| `sta-request.json` | the `klt sta` request, verbatim |
| `sta-results.json` | the `klt sta` response envelope, verbatim — **the load-bearing artifact** |
| `par-request.json` | the `klt place-and-route` request, verbatim |
| `par-report.json` | the `klt place-and-route` response — **row 06 only**, because only its in-flow STA is load-bearing (see below); the other rows' ~45 KB responses are distilled into `candidate-matrix.json` instead |
| `synth-request.json` / `synth-report.json` | the `klt synthesize` request/response — **rows 01, 03, 04 only**; rows 02, 05, 06 have none, because their netlists did not come from `klt synthesize` (see "Why rows 2, 5 and 6 are not landable") |

## Supporting files

- **`cell-delay-floors.json`** — every combinational `sky130_fd_sc_hd`
  cell's **per-transition-polarity delay floor** at `ss_n40C_1v28` and
  `tt_025C_1v80`: the smallest value in any `cell_fall` (resp. `cell_rise`)
  table of any of its timing arcs — what no path through the cell can beat
  on that edge, whichever input pin switches, regardless of output load or
  input slew. Both reductions are carried (min-over-arcs and
  max-over-arcs), with the definitions in the file's own `note`, so a
  reader does not have to trust one summary. Extracted from the installed
  sky130A liberty (`open_pdks c6d73a35`).

  This is the root-cause evidence, and the **ratio is not the finding** —
  inverting cells derate 2.5–5x between these corners too. The **absolute
  falling-edge magnitude** is: at `ss_n40C_1v28` the non-inverting compound
  family's falling floors run one to two orders of magnitude above the
  inverting family's for comparable fan-in (`or4_1` **4.4591 ns** against
  `nand4_1` 0.1553 ns; one `or4_1` falling arc is 45% of the whole 10.0 ns
  period before any load), while at `tt_025C_1v80` the same pair is
  0.3558 / 0.0376 ns — same ratio, both negligible. **209 of 351**
  combinational cells have at least one pin that cannot switch in under
  1.0 ns on at least one edge at `ss_n40C_1v28`.
- **`yosys-cell-exclusion.ys`** — the exact Yosys script rows 2/5/6 were
  mapped with: `klt synthesize`'s own generated script for this design,
  plus one `-dont_use <cell>` for each of those 209 cells. The list is
  reproducible from `cell-delay-floors.json` alone: it is exactly the cells
  with `worst_arc_any_polarity_floor_ns_ss_n40C_1v28 > 1.0` (cross-checked
  name-for-name against this script).
- **`rtl/modexp-bit-serial.v`** — the candidate RTL of rows 3–6, frozen
  verbatim. It keeps the algorithm and the module interface bit-identical
  to the committed `rtl/modexp.v` while serializing each Blakley step
  LSB-first across one-gate-deep slices. **It clears `CLAUDE.md`'s
  correctness gate**: `python3 verification/cross_check.py` →
  2000/2000 match, 0 mismatches across `WIDTH` = 4, 6, 8, 16, and
  `klt functional-verification` → 3/3 pass. Its latency is
  `(WIDTH + popcount(exp)) * (WIDTH*(2*WIDTH+6) + 2) + WIDTH + 3` cycles,
  ≈**33x** the committed core's at `WIDTH=16` — 19539 cycles against 595
  for an all-ones exponent (31.9–32.8x across `popcount(exp)` = 0..16).
  Against row 6's 4.6x clock gain that is a **net throughput loss of
  roughly 7x**: these rows are *closure* results, never throughput
  results.
- **`rtl/bit-serial.patch`** — the same change as a patch against
  `rtl/modexp.v` @ `28a7c96`, including the cocotb testbench additions
  (a directed cycle-count check pinning the re-derived latency formula).
  Apply it to reproduce rows 3–6 from a clean tree.

## Why rows 2, 5 and 6 are not landable

Two independent reasons, both disclosed in
`spec/decision-records/0004-slow-corner-closure-is-cell-selection-bound-and-the-disclosed-t1-item-5-exception.md`
Decision 1:

1. **Not reproducible from a committed `klt` request.** The 209-cell
   exclusion has no `klt synthesize` request field — `abc -dont_use` is a
   hardcoded per-cell-library table inside `klt` — so those rows bypass
   `klt synthesize` and invoke Yosys directly. Every other stage of every
   row is a `klt` verb. A committed recipe that `klt synthesize
   flow/synthesize-modexp.json` cannot re-run would make
   `verification/README.md`'s central promise false for the headline
   timing claim. Filed as
   [klayout-tools#2382](https://github.com/2AMLogic/klayout-tools/issues/2382);
   the downstream re-spin it unblocks is
   [sky130-modexp#141](https://github.com/2AMLogic/sky130-modexp/issues/141).
2. **Row 6's 18/18 is methodology-marginal.** Its `klt sta` setup slack at
   `ss_n40C_1v28` is **+0.489 ns** (105.14 MHz); its own in-flow
   place-and-route STA, which runs `estimate_parasitics -global_routing`
   first, reports **−1.105 ns** (90.05 MHz) on the *same* database. Both
   numbers are in `par-report.json` and `sta-results.json` respectively,
   left disagreeing rather than resolved in the favourable direction. That
   is why `par-report.json` is kept verbatim for this row.

## Reproducing a row

```bash
source .venv/bin/activate            # pinned klt; see docs/environment.md
export PDK=sky130A PDK_ROOT=~/.volare

mkdir -p flow/build/myrow && cd flow/build/myrow
# rows 3-6: git apply the candidate RTL patch first, or copy
#   ../../verification/records/sta-corner-sweep/artifacts/.../rtl/modexp-bit-serial.v
cp <that row>/synth-request.json synth.json      # rows 1, 3, 4
klt synthesize synth.json --format json
# rows 2, 5, 6 instead: yosys -q <candidates>/yosys-cell-exclusion.ys
python3 ../../flow/tie_constants.py <synth netlist> modexp_tied.v
cp <that row>/par-request.json par.json && klt place-and-route par.json --format json
cp <that row>/sta-request.json sta.json && klt sta sta.json --format json
```

Both `klt place-and-route` and `klt sta` were confirmed **bit-identical**
between the repo-pinned OpenROAD `26Q3-1260-g06a5a02279` and a newer
`26Q3-1510-g6cb3f2b704` build on the same host, so a small version drift in
`openroad` should not change these numbers. The committed artifacts are the
pinned-build runs.

## The rule these numbers are read under

Per `spec/decision-records/0002-…` Decision 1, **no claim in this repository
may say this block "closes 100 MHz" without naming the corner or corner set
it holds at** — including row 6's. And per `CLAUDE.md`'s overclaim-trap
section, no figure here is compared to any external standard-cell library's
published result.
