# Synthesis baseline

**Status: measured, 2026-08-04.** This is the number every later optimization
claim is measured against. It was produced in `2AMLogic/klayout-tools`
(PR #488) before this repo existed; the RTL and testbench migrated here under
issue #2 (`rtl/modexp.v`, `verification/test_modexp.py`,
`verification/request-modexp.json`), and this document is the record that
travels with them.

## The measurement

`klt synthesize` (Yosys 0.67+post) against
`sky130_fd_sc_hd` / `tt_025C_1v80`, with `sky130A` fetched via `ciel`.
`instance_count` is the post-`abc` mapped standard-cell count.

| Design | `WIDTH` | sky130 cells |
| --- | --- | --- |
| `modexp.v` — square-and-multiply over one shared Blakley modular multiplier | 16 | **682** |
| `gcd.v` — minimal iterative-subtractor GCD (a separate, much smaller design) | 16 | 384 |

> **Reproducibility note (2026-10-15, issue #195).** The 682 figure above was
> measured with klt 0.2.0 and is reproduced by that klt version. The pinned
> toolchain (`scripts/setup-env.sh`, `klayout-tools==0.8.0`) gives **717**
> instances / 7144.352 µm² for the same `rtl/modexp.v`, request and
> `sky130_fd_sc_hd` liberty. The cause is the Yosys script klt generates, not
> the PDK revision and not the Yosys build: klt 0.6.0 adds `abc -constr`
> (driving cell and load), `abc -dont_use` for `lpflow_*`/`probe*` cells, and
> `hilomap` tie cells. With `-constr` and `-dont_use` removed the 0.6.0 script
> yields 686 = 682 + 4 `conb_1` tie cells. Evidence:
> [`verification/records/synthesis-baseline/records/20261015-210722-a4653a5.md`](../verification/records/synthesis-baseline/records/20261015-210722-a4653a5.md)
> (with `20261015-205100-4d8d397`). The 682/718 figures elsewhere on this page
> are historical and left as measured; the 718 post-CTS figure was built on the
> 682-cell netlist. Neither number is comparable to any other lab's.

A behavioral naive variant (unrolled multiply with a runtime-modulus divider
per step) was also measured and did not finish `abc` mapping within 120 s —
a different regime entirely, and the one that reaches thousands of cells.

Correctness at the time of measurement: `test_modexp.py` passes 2/2 through
`klt functional-verification`, and `modexp.v` is bit-exact against Python
`pow(base, exp, mod)` across `WIDTH` = 4, 6, 8, 16 at 500 random cases each,
0 mismatches, via a deterministic Icarus cross-check that runs one `klt
functional-verification` request per `WIDTH`
(`verification/cross_check.py`).

## Reproducing it

```bash
# 682 cells for modexp under klt 0.2.0 (717 under the pinned klt). The
# 384-cell gcd control row in the table above was measured in
# 2AMLogic/klayout-tools PR #488 and was not migrated to rtl/, so it has
# no reproduction command here.
PDK=sky130A klt synthesize flow/synthesize-modexp.json --format json \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["instance_count"])'

# bit-exact functional verification
klt functional-verification verification/request-modexp.json --format json

# the WIDTH = 4/6/8/16 cross-check the correctness claim above rests on
python3 verification/cross_check.py
```

`scripts/setup-env.sh` provisions the pinned `klt` revision and `sky130A`
version these commands assume; `docs/environment.md` names them.

## The records behind these numbers

Both claims on this page are backed by append-only evidence records, each
carrying the klt provenance block (tool version, resolved PDK, deck and
input content hashes) and the git revision it was produced against:

- `verification/records/synthesis-baseline/records/` — the `WIDTH=16`
  synthesis measurement, with the raw `klt synthesize` JSON envelope and a
  mapped-netlist snapshot as artifacts.
- `verification/records/width-cross-check/records/` — the `WIDTH` =
  4/6/8/16 bit-exact cross-check, with the per-`WIDTH` vector transcripts as
  artifacts.
- `verification/records/gate-level-sim/records/` — the same suite re-run
  against a gate-level netlist of the **routed layout** rather than the RTL
  (issue #9); see "Post-route gate-level simulation" below.
- `verification/records/place-and-route/records/` — the OpenROAD
  place-and-route runs behind the area/Fmax/power figures below, including
  the two per-corner rebuild sweeps.
- `verification/records/sta-corner-sweep/records/` — standalone multi-corner
  STA (`klt sta`) of the **committed** routed DEF, one fixed geometry
  analysed at all eighteen ratified corners (issue #86); see "STA corner
  characterization of the committed layout" below.
- `verification/records/drc-lvs/records/` — the DRC and LVS runs against the
  routed GDS; `docs/signoff-claim.md` is the authoritative summary.

`verification/README.md` is the authoritative description of that record
format; `verification/check_records.py` enforces it, and fails on a record
whose cited sources have changed since it was minted. The prose on this page
is a summary of those records, not a substitute for them.

## Why the external comparison is not a comparison

The task was chosen after Alibaba's Qwen3.8-Max post
([2026-08-02](https://qwen.ai/blog?id=qwen3.8)) reported an agent optimizing
a GCD/RSA modexp accelerator from 8,298 to 678 Yosys cells over ~500 turns,
on a comparable open stack (cocotb / Icarus / Yosys / OpenROAD) — but against
**Nangate45**.

Yosys cell counts are standard-cell-library dependent. A sky130 count and a
Nangate45 count are not the same measurement, so **682 and 678 cannot be
compared in either direction.** We did not beat 678, we do not claim to have,
and our proximity to it is not evidence that their optimization was small.
Nothing in this repo or derived from it may state or imply otherwise.

## The structural finding, which is real

A naturally-written correct core lands near their *optimized* scale, not
their *starting* scale. Their 8,298 figure therefore describes a deliberately
un-optimized starting RTL rather than a natural implementation — plausibly
behavioral, divider-based, and unrolled, the regime the naive variant above
reaches.

That starting RTL was not published ("no golden reference design"), so its
microarchitecture — algorithm variant, datapath width, degree of unrolling,
whether it is a combined GCD+RSA block — is not recoverable. Reconstructing
it would mean writing intentionally bloated RTL tuned to a number that is not
comparable to ours anyway.

## What this repo does instead (operator ruling, 2026-08-04)

Recreating an artificial ~8k-cell starting point to harvest a large reduction
ratio was considered and rejected: manufacturing the hole we then climb out of
is a rigged demo, and a fragile one, since any reconstruction is a guess at
someone else's handicap.

So the program is:

- **Phase 2** — micro-optimization from the 682-cell core, correctness held
  by the bit-exact suite on every commit. Area and timing gains are reported
  against our own baseline, which is the only honest denominator available.
- **Phase 3** — place-and-route through OpenROAD and a DRC/LVS-clean gate on
  the produced GDS. sky130 makes this meaningful in a way Nangate45 could
  not: a real PDK has a real rule deck, and the resulting block is eligible
  to progress up the maturity ladder.

The load-bearing argument was never the external number. It is that a
mixed-signal design system requires a digital flow underneath it, which makes
this block a prerequisite rather than a detour.

## Place-and-route baseline (constrained, 100 MHz)

**Status: measured, 2026-08-14.** This section is an *addition* to this
document, not a correction — the 682-cell figure above is the **unconstrained
synthesis** cell count and remains exactly as measured. This section is the
first **place-and-route** measurement (`klt place-and-route`, OpenROAD:
floorplan → place → cts → route, DEF→GDS merge), constrained to the 100 MHz
Phase 2 clock target `spec/modexp.md` Decision 2 names, at the nominal corner
(`tt_025C_1v80`) Decision 4 of
[`spec/decision-records/0001-input-domain-interface-and-corner-matrix.md`](../spec/decision-records/0001-input-domain-interface-and-corner-matrix.md)
holds that target to. It answers Decision 2's and Decision 4's revisit
triggers with the first *measured* Fmax and area this design has ever had —
neither existed before this run (`klt synthesize`'s own contract keeps
`timing` `null` by design, deferring every timing number to this step).

### The measurement

| Quantity | Unconstrained synthesis (existing, above) | Constrained P&R, 100 MHz, `tt_025C_1v80` (this section) |
| --- | --- | --- |
| sky130 cell count (`WIDTH=16`) | **682** | **718** (683 after floorplan's tie-cell insertion, 686 after placement's `repair_design`/`repair_timing`, 718 after clock-tree synthesis) |
| Clock constraint | none (`constraints.clock_period_ns: null`) | 100 MHz (`clock_period_ns: 10.0`) |
| Die area | not measured (synthesis has no floorplan) | 21969.2 µm² |
| Core area | not measured | 19398.6 µm² |
| Utilization | not measured | 37.08% |
| Achieved Fmax at `tt_025C_1v80` | not measured | **149.66 MHz** (worst setup slack **+3.318 ns** at the 10 ns/100 MHz constraint — closes with margin, not just barely) |
| Setup / hold violations at `tt_025C_1v80` | not measured | 0 / 0 |
| Estimated power at `tt_025C_1v80` | not measured | 0.876 mW |
| Routed wirelength | not measured | 17805 µm |

**100 MHz closes at the nominal corner, with margin** — the achieved Fmax
(149.66 MHz) is the measured number Decision 2's revisit trigger names;
future work is held to it, not to the 100 MHz target it supersedes. Decision
4's area revisit trigger is answered by the die/core area figures above.

**The cell-count increase (682 → 718) is not a Phase 2 regression.** It is
what the *same* correct RTL costs once actually placed, clocked, and routed:
one tie cell (a real klayout-tools gap — see `flow/README.md`'s "Known
upstream gaps"), a handful of buffers OpenROAD's `repair_design`/
`repair_timing` insert during placement, and a clock tree CTS builds to
distribute `clk` — none of these existed as a concept at the unconstrained-
synthesis stage, which never floorplans, places, or builds a clock tree.

### Full corner-matrix sweep

Decision 4 of the same decision record ratifies all eighteen installed
`sky130_fd_sc_hd` liberty corners as this block's corner matrix, with the 100
MHz Phase 2 target held at the nominal corner specifically (full 18-corner
closure is named there as a later T1 sign-off requirement, not a per-commit
Phase 2 gate) — this run still sweeps every one of them, independently
(`flow/run-corner-sweep.sh`; see `flow/README.md`'s "Known upstream gaps" for
why each corner is a full independent P&R run rather than a single
physical build re-timed per corner), rather than reporting `tt_025C_1v80`
alone:

| Corner | WNS (ns) | TNS (ns) | Fmax (MHz) | Setup viol. | Hold viol. | Utilization | Power (mW) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `ff_100C_1v65` | 4.444 | 0.000 | 179.98 | 0 | 0 | 37.05% | 0.7690 |
| `ff_100C_1v95` | 5.719 | 0.000 | 233.57 | 0 | 0 | 37.02% | 1.0898 |
| `ff_n40C_1v56` | 3.631 | 0.000 | 157.02 | 0 | 0 | 37.25% | 0.6590 |
| `ff_n40C_1v65` | 4.185 | 0.000 | 171.96 | 0 | 0 | 37.09% | 0.7394 |
| `ff_n40C_1v76` | 4.596 | 0.000 | 185.04 | 0 | 0 | 37.19% | 0.8465 |
| `ff_n40C_1v95` | 5.634 | 0.000 | 229.05 | 0 | 0 | 37.02% | 1.0440 |
| `ff_n40C_1v95_ccsnoise` | 5.634 | 0.000 | 229.05 | 0 | 0 | 37.02% | 1.0440 |
| `ss_100C_1v40` | **-4.154** | -64.724 | 70.65 | 16 | 0 | 39.03% | 0.5297 |
| `ss_100C_1v60` | **-0.612** | -8.549 | 94.23 | 16 | 0 | 38.07% | 0.7081 |
| `ss_n40C_1v28` | **-31.697** | -566.638 | 23.98 | 98 | 0 | 42.69% | 0.2969 |
| `ss_n40C_1v35` | **-17.431** | -303.294 | 36.45 | 77 | 0 | 39.04% | 0.4092 |
| `ss_n40C_1v40` | **-12.305** | -194.363 | 44.83 | 19 | 0 | 38.94% | 0.4540 |
| `ss_n40C_1v44` | **-9.134** | -142.507 | 52.26 | 16 | 0 | 38.78% | 0.5188 |
| `ss_n40C_1v60` | **-2.039** | -30.356 | 83.07 | 16 | 0 | 38.93% | 0.6767 |
| `ss_n40C_1v60_ccsnoise` | **-2.039** | -30.356 | 83.07 | 16 | 0 | 38.93% | 0.6767 |
| `ss_n40C_1v76` | **-0.641** | -8.218 | 93.97 | 16 | 0 | 37.56% | 0.8843 |
| `tt_025C_1v80` | 3.318 | 0.000 | 149.66 | 0 | 0 | 37.08% | 0.8758 |
| `tt_100C_1v80` | 3.490 | 0.000 | 153.61 | 0 | 0 | 37.15% | 0.9283 |

Bold negative WNS marks a corner that does **not** close at 100 MHz.

**Finding: 100 MHz closes at every `tt`/`ff` corner, and at none of the nine
`ss` (slow-process) corners.** All seven `ff` corners and both `tt` corners
close with 3.3–5.7 ns of positive margin (Fmax 149.7–233.6 MHz). Every `ss`
corner fails, from a 0.6 ns shortfall at the mildest (`ss_n40C_1v76`,
93.97 MHz achievable) to a 31.7 ns shortfall at the worst (`ss_n40C_1v28`,
the binding corner: only **23.98 MHz** achievable, 98 endpoints violating).
This is not a per-commit Phase 2 gate failure — Decision 4 explicitly holds
the 100 MHz Phase 2 target to the nominal corner alone, which closes — but
it is a real, measured T1 sign-off gap this record exists to surface rather
than to paper over. The critical path at the binding corner
(`ss_n40C_1v28`) is a synchronous flop-to-flop path through an 18-bit
ripple-carry adder (`maj3`/`xnor2` full-adder chain) immediately followed by
a long chain of `a21oi`/`o21ai`/`o211a`-class gates implementing a compare-
and-subtract mux tree — bit-exact with `rtl/modexp.v`'s `mm_sum`
(`mm_p2 + mm_add`, an 18-bit add for `WIDTH=16`) feeding `mm_red`'s two
serially-dependent `(mm_sum >= mm_m2) ? ... : (mm_sum >= mm_m1) ? ... : ...`
compare-and-subtract stages (`rtl/modexp.v` lines 68–75), all combinational
within one `S_MM_RUN` cycle — **exactly the path issue #7 predicted before
this run**. The raw `report_checks` path is frozen as an artifact
(`ss_n40C_1v28-critical-path.txt`). Per this issue's own constraint, this
shortfall is recorded here rather than acted on: the clock constraint in
`flow/par-modexp.json` is not relaxed, and `spec/modexp.md` is not edited.
See issue #16 for the decision record this finding
requires.

The full per-corner `klt place-and-route` JSON envelopes are frozen as
artifacts under
`verification/records/place-and-route/artifacts/20260814-203901-c741877/`.

### Full corner-matrix sweep — mapping-only re-run (issue #56)

**Status: measured, 2026-08-16, superseding record `20260814-203901-c741877`
for freshness.** Per `spec/decision-records/0002-slow-corner-timing-closure-and-mm-red-critical-path.md`
Decision 3's named first step, this re-runs the identical 18-corner sweep
above with a **revised floorplan only** (`flow/run-corner-sweep.sh`:
utilization 55%, `core_margin_um` 2, vs. 35%/4 above) — **no RTL change**
(`git diff` against `rtl/modexp.v` is empty; the post-synthesis netlist hash
matches the run above byte-for-byte) and no new decision record. Full
detail, including the constrained-synthesis-and-floorplan exploration that
selected this configuration, is in
[`verification/records/place-and-route/records/20260816-072918-d8eafca.md`](../verification/records/place-and-route/records/20260816-072918-d8eafca.md).
`layout/modexp.def`/`layout/modexp.gds` (and their DRC/LVS evidence) are
**not** regenerated by this update — they still reflect the original
floorplan above; `flow/par-modexp.json` (the single-corner nominal recipe)
is deliberately left unchanged for that reason, so the revised floorplan
lives only in `flow/run-corner-sweep.sh`.

| Corner | WNS (ns) | TNS (ns) | Fmax (MHz) | Setup viol. | Hold viol. | Utilization | Power (mW) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `ff_100C_1v65` | 4.501 | 0.000 | 181.84 | 0 | 0 | 58.82% | 0.7102 |
| `ff_100C_1v95` | 5.741 | 0.000 | 234.80 | 0 | 0 | 58.65% | 0.9992 |
| `ff_n40C_1v56` | 3.659 | 0.000 | 157.70 | 0 | 0 | 59.50% | 0.6510 |
| `ff_n40C_1v65` | 4.259 | 0.000 | 174.19 | 0 | 0 | 59.36% | 0.7311 |
| `ff_n40C_1v76` | 4.638 | 0.000 | 186.49 | 0 | 0 | 58.81% | 0.7822 |
| `ff_n40C_1v95` | 5.627 | 0.000 | 228.67 | 0 | 0 | 58.77% | 0.9638 |
| `ff_n40C_1v95_ccsnoise` | 5.627 | 0.000 | 228.67 | 0 | 0 | 58.77% | 0.9638 |
| `ss_100C_1v40` | **-3.891** | -60.575 | 71.99 | 16 | 0 | 63.47% | 0.5361 |
| `ss_100C_1v60` | **-0.340** | -4.194 | 96.72 | 16 | 0 | 61.35% | 0.7022 |
| `ss_n40C_1v28` | **-30.562** | -556.070 | 24.65 | 96 | 0 | 67.21% | 0.3075 |
| `ss_n40C_1v35` | **-17.380** | -294.760 | 36.52 | 69 | 0 | 62.72% | 0.3940 |
| `ss_n40C_1v40` | **-11.957** | -186.934 | 45.54 | 17 | 0 | 63.43% | 0.4673 |
| `ss_n40C_1v44` | **-8.839** | -138.310 | 53.08 | 16 | 0 | 63.07% | 0.5247 |
| `ss_n40C_1v60` | **-2.124** | -31.673 | 82.48 | 16 | 0 | 62.96% | 0.6811 |
| `ss_n40C_1v60_ccsnoise` | **-2.124** | -31.673 | 82.48 | 16 | 0 | 62.96% | 0.6811 |
| `ss_n40C_1v76` | **-0.189** | -0.979 | 98.15 | 9 | 0 | 59.70% | 0.8407 |
| `tt_025C_1v80` | 3.334 | 0.000 | 150.02 | 0 | 0 | 59.23% | 0.8630 |
| `tt_100C_1v80` | 3.524 | 0.000 | 154.41 | 0 | 0 | 58.99% | 0.8471 |

**100 MHz still closes at exactly the same 9/18 corners** (both `tt`, all
seven `ff`) **and still fails at all nine `ss` corners** — no corner
crossed the 100 MHz line either direction. **Binding corner is still
`ss_n40C_1v28`**: Fmax improved **23.98 → 24.65 MHz** (+2.8%), WNS improved
**-31.697 → -30.562 ns**. Stated explicitly, per record `0002` Decision 1's
stated-corner requirement: **this mapping-only change closes 1.135 ns of
the 31.697 ns WNS shortfall at the binding corner — 3.6% of the gap —
leaving 96.4% (30.562 ns) open.** This is not a "closes 100 MHz" claim at
any additional corner. The other eight `ss` corners moved by small, mixed
amounts (seven improved 0.05–0.45 ns of WNS, `ss_n40C_1v60`/
`ss_n40C_1v60_ccsnoise` regressed slightly, -0.085 ns) — not a uniform
improvement.

**Conclusion: the binding-corner gap is overwhelmingly architecture-bound,
not mapping-bound.** A fresh supplementary critical-path re-timing at
`ss_n40C_1v28` finds the **identical** flop-to-flop path (same startpoint/
endpoint instance names as the run above, since the netlist itself is
unmodified) through the same `mm_sum`/`mm_red` full-adder-into-compare-and-
subtract-mux-chain gate sequence — a mapping-only change repositions and
rebuffers that chain but cannot meaningfully shorten a fixed combinational
depth. Per record `0002` Decision 3, the remaining gap's next-named step is
an RTL restructuring of that chain — explicitly out of scope for the issue
that produced this update (its own decision record, latency-formula
re-derivation, and full bit-exact re-verification required first).

### STA corner characterization of the committed layout (issue #86)

**Status: condensed to a pointer (issue #432).** The pre-#232 milestone
sections this heading once carried — issue #81's tapcell/PDN/filler
re-measurement, issue #86's 18-corner table, issue #132's liberty derate
analysis, issue #141's 18/18 re-spin — measured the layout that issue
#232's regeneration replaced. Their append-only records remain under
`verification/records/place-and-route/` (notably `20260911-052542-d5e43d3`)
and `verification/records/sta-corner-sweep/` (`20260915-111931-2c125f8`,
`20260923-093000-28a7c96`, `20260924-134500-1a8313b`); none of their
figures describe the committed artifacts. The current state:

- **The committed layout** (issue #232; record
  [`verification/records/place-and-route/records/20261027-013900-98bf55d.md`](../verification/records/place-and-route/records/20261027-013900-98bf55d.md),
  described in [`layout/README.md`](../layout/README.md)):
  `layout/modexp.def`, `layout/modexp.gds`, and the as-built
  `layout/modexp.v` (721 netlist instances), regenerated together from the
  committed flow and shown reproducible — two sequential `flow/run-par.sh`
  runs gave byte-identical DEF, GDS, and netlist. 3,064 components = 721
  netlist instances + 265 tapcells + 2,078 fillers; die 22,761.8 µm²,
  core 19,781.5 µm² (utilization 38.59%), routed wirelength 20,024 µm,
  estimated power 0.8797 mW, Fmax 175.014 MHz (+4.28617 ns WNS) at
  `tt_025C_1v80`. Tapcell insertion, PDN, and standard-cell row fillers
  are present; CMP metal density fill, `DONT_USE_CELLS` exclusion, and an
  IO ring remain absent. The DRC/LVS signoff verdict is stated once in
  [`docs/signoff-claim.md`](signoff-claim.md).
- **18-corner `klt sta` on that layout** (record
  [`verification/records/sta-corner-sweep/records/20261027-013950-98bf55d.md`](../verification/records/sta-corner-sweep/records/20261027-013950-98bf55d.md);
  full table in
  [`verification/signoff/evidence/characterization.md`](../verification/signoff/evidence/characterization.md)):
  100 MHz closes at **10 of 18** corners; binding corner `ss_n40C_1v28`
  at setup WNS **-30.332 ns** / Fmax **24.7942 MHz**; hold slack
  non-negative at all 18 (worst +0.21354 ns). At `tt_025C_1v80` the sweep
  reads +4.82441 ns / 193.215 MHz against the P&R run's +4.28617 ns /
  175.014 MHz for the same DEF — a methodology difference (`klt sta` with
  `spef` omitted times LEF/DEF-derived parasitics), not an improvement.
- **Why the slow corner binds, and what was decided about it** — carried
  in full by the decision records:
  [`0004`](../spec/decision-records/0004-slow-corner-closure-is-cell-selection-bound-and-the-disclosed-t1-item-5-exception.md)
  (closure is cell-selection-bound; the disclosed T1 item 5 exception),
  [`0005`](../spec/decision-records/0005-the-priced-exit-was-run-and-does-not-reproduce.md)
  (the priced exit was run and does not reproduce),
  [`0007`](../spec/decision-records/0007-the-17-of-18-bit-serial-re-spin-is-declined-not-planned.md)
  (the 17/18 bit-serial re-spin is declined), and the `0011`-`0018`
  carry-save Montgomery series under
  [`spec/decision-records/`](../spec/decision-records/).

## Post-route gate-level simulation

The committed bit-exact suite run against a gate-level netlist of the
**routed layout** rather than the RTL; until this leg existed, every
correctness claim on this page rested on behavioural simulation. `klt
place-and-route` does export an as-built post-route netlist —
`layout/modexp.v`, 721 instances, reproduced byte-for-byte by the #232
re-run — but Leg 1 deliberately simulates a netlist **derived from the
routed GDS itself** (`klt extract --abstract-cells` →
`verification/gate-level/spice_to_verilog.py` →
`verification/gate-level/modexp_post_route.v`: 3,064 instances / 69 cell
types / 70 pins / 777 nets; zero-delay, corner-free, `VDD`/`VSS` entering
as `supply1`/`supply0` constants, `WIDTH=16` only), so the run checks
`klt extract`'s own reading of the geometry that was DRC'd and LVS'd
rather than a second reading of the P&R database.

- **Leg 1 (zero-delay): PASS.** `test_modexp.py` unmodified, reached via
  `testbench.search_path` — 2/2 tests, simulated times identical to the
  RTL run's (cycle-for-cycle identical, not merely functionally
  equivalent); the 500-case deep run matches the RTL cross-check 500/500
  with a per-vector transcript byte-identical to
  `verification/records/width-cross-check/artifacts/20260808-031948-5488082/width-16.jsonl`.
- **Leg 2 (net-delay SDF): PASS with a disclosed annotation-class
  exclusion.** On the committed layout, all 1,920 net-delay `INTERCONNECT`
  entries are back-annotated (`environment.sdf.annotated: true`); every
  `IOPATH` cell-arc entry is excluded — record
  [`verification/records/gate-level-sim/records/20261027-050100-163f791.md`](../verification/records/gate-level-sim/records/20261027-050100-163f791.md).

Full method, scope, provenance guards, and the upstream friction filed
along the way:
[`verification/gate-level/README.md`](../verification/gate-level/README.md)
— the single description of that experiment. Records are append-only
under
[`verification/records/gate-level-sim/`](../verification/records/gate-level-sim/).
