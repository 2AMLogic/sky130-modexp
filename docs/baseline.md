# Synthesis baseline

**Status: measured, 2026-08-04.** This is the number every later optimization
claim is measured against. It was produced in `2AMLogic/klayout-tools`
(PR #488) before this repo existed; the RTL and testbench migrated here under
issue #2 (`rtl/modexp.v`, `verification/test_modexp.py`,
`verification/request-modexp.json`), and this document is the record that
travels with them.

## The measurement

`klt synthesize` (Yosys 0.67+post) against
`sky130_fd_sc_hd` / `tt_025C_1v80`, with `sky130A` fetched via `volare`.
`instance_count` is the post-`abc` mapped standard-cell count.

| Design | `WIDTH` | sky130 cells |
| --- | --- | --- |
| `modexp.v` — square-and-multiply over one shared Blakley modular multiplier | 16 | **682** |
| `gcd.v` — minimal iterative-subtractor GCD (a separate, much smaller design) | 16 | 384 |

A behavioral naive variant (unrolled multiply with a runtime-modulus divider
per step) was also measured and did not finish `abc` mapping within 120 s —
a different regime entirely, and the one that reaches thousands of cells.

Correctness at the time of measurement: `test_modexp.py` passes 2/2 through
`klt functional-verification`, and `modexp.v` is bit-exact against Python
`pow(base, exp, mod)` across `WIDTH` = 4, 6, 8, 16 at 500 random cases each,
0 mismatches, via a deterministic Icarus cross-check outside the cocotb
harness.

## Reproducing it

```bash
# 682 cells for modexp, 384 for gcd
for src in gcd modexp; do
  tmp=$(mktemp -d); cp rtl/$src.v "$tmp/"
  cat > "$tmp/req.json" <<JSON
{ "schema": "klt.synthesize.request/1", "engine": "yosys",
  "sources": ["$src.v"], "hdl_toplevel": "$src",
  "pdk": { "cell_library": "sky130_fd_sc_hd", "corner": "tt_025C_1v80" },
  "constraints": { "clock_period_ns": null } }
JSON
  ( cd "$tmp" && PDK=sky130A klt synthesize req.json --format json ) \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["instance_count"])'
done

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

## Place-and-route baseline (constrained, 100 MHz) — appended, issue #7

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

### Nominal-corner re-measurement with tapcell/PDN/filler-cell insertion (issue #81)

**Status: measured, 2026-09-11.** Same reasoning as the "mapping-only
re-run" section above — this is an *addition*, not a correction; the
682/718-cell figures above remain exactly as measured for the
configuration they describe. `flow/par-modexp.json` (the single-corner
nominal recipe backing the *committed* `layout/modexp.gds`/`layout/
modexp.def`, unlike the 55%-utilization sweep above which uses its own
separate `flow/run-corner-sweep.sh` floorplan) gained a `power` block
(`request.power`: tapcell + PDN + filler-cell insertion, per
[klayout-tools#1120](https://github.com/2AMLogic/klayout-tools/pull/1120)),
with the `floorplan`/`io`/`constraints`/`seed` blocks left byte-identical
to the original issue #7 recipe — only the new `power` block differs.

| Quantity | Issue #7 (original, `power` absent) | Issue #81 (this update, `power` added) |
| --- | --- | --- |
| sky130 cell count (`WIDTH=16`) | 718 | 718 logic-bearing + **2356 new physical-only** (265 tapcells + 2087 fillers + 4 antenna-fixup diodes) = **3074** |
| Die area | 21969.2 µm² | 21969.2 µm² (unchanged — same floorplan) |
| Core area | 19398.6 µm² | 19398.6 µm² (unchanged) |
| Utilization | 37.08% | 39.31% (more of the same core area is now occupied, by tapcells/fillers) |
| Achieved Fmax at `tt_025C_1v80` | 149.66 MHz | 159.63 MHz |
| Setup / hold / antenna / route-DRC violations | 0/0/—/— | 0/0/0/0 |
| Estimated power at `tt_025C_1v80` | 0.876 mW | 0.983 mW |
| Routed wirelength | 17805 µm | 19060 µm |

**100 MHz still closes at the nominal corner, with more margin than
before.** The Fmax/wirelength/power deltas are incidental — the floorplan
is unchanged; they are OpenROAD's own legalization/CTS/optimization
responding to tapcell rows now occupying fixed placement sites and antenna
fix-ups now running, **not a claim of anything beyond what they are** (see
`CLAUDE.md`'s overclaim-trap note — this is not a PPA comparison against
any external work). The 718 logic-bearing instances are otherwise the same
concept as issue #7's own 718: 680 present under an identical instance
name and cell type against the unchanged synthesis netlist, 3 resized, 35
new CTS/timing/antenna-fixup insertions, 0 missing.

**This closes DRC for real** (`docs/signoff-claim.md`): all 234
`nwell.space.1`/`nwell.width.1` violations issue #79 classified against
the pre-#81 GDS are gone. LVS is re-run and still reports `mismatch` (17,
was 15 — fully attributed to the 5 new physical-only cell types plus
ordinary CTS churn), so `spec/modexp.md`'s Signoff row remains not met
overall. Full record:
[`verification/records/place-and-route/records/20260911-052542-d5e43d3.md`](../verification/records/place-and-route/records/20260911-052542-d5e43d3.md).

**The 18-corner sweep above (both the original and the mapping-only
re-run) is unaffected** — neither used the committed `flow/par-modexp.json`
recipe this section's original table measures, and issue #81 did not
re-run either sweep with `power` enabled. **That left the committed layout
itself without corner evidence of its own until issue #86; see the next
section.**

### STA corner characterization of the committed layout (issue #86)

**Status: measured, 2026-09-15.** This is the first per-corner timing
evidence about `layout/modexp.def`/`layout/modexp.gds` **themselves** — the
post-#81, tapcell/PDN/filler-cell-bearing artifacts this repo signs off DRC
and LVS against. Both 18-corner sweeps above characterize
`flow/run-corner-sweep.sh`'s *separate* 55%-utilization floorplan and
predate issue #81, so neither could answer "how does the shipped layout
time across the ratified corner set?"

`klt sta` ([klayout-tools#1099](https://github.com/2AMLogic/klayout-tools/issues/1099),
`docs/cli/sta.md`) makes that question answerable: it runs a standalone
OpenSTA session against an already-routed DEF and never places, routes, or
runs CTS. `flow/run-sta-corner-sweep.sh` drives it once per corner against
the **byte-identical** committed DEF — verified, not assumed: all eighteen
responses report the same `provenance.input.content_hash`.

| Corner | WNS (ns) | TNS (ns) | Fmax (MHz) | Setup viol. | Hold viol. | Clock skew (ns) | Power (mW) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `ff_100C_1v65` | 5.7193 | 0.000 | 233.61 | 0 | 0 | 0.00174 | 0.7969 |
| `ff_100C_1v95` | 6.6880 | 0.000 | 301.93 | 0 | 0 | 0.00161 | 1.1370 |
| `ff_n40C_1v56` | 4.4079 | 0.000 | 178.82 | 0 | 0 | 0.00282 | 0.6778 |
| `ff_n40C_1v65` | 5.1717 | 0.000 | 207.11 | 0 | 0 | 0.00249 | 0.7604 |
| `ff_n40C_1v76` | 5.8483 | 0.000 | 240.87 | 0 | 0 | 0.00221 | 0.8713 |
| `ff_n40C_1v95` | 6.6144 | 0.000 | 295.37 | 0 | 0 | 0.00185 | 1.0774 |
| `ff_n40C_1v95_ccsnoise` | 6.6144 | 0.000 | 295.37 | 0 | 0 | 0.00185 | 1.0774 |
| `tt_025C_1v80` | 4.3673 | 0.000 | 177.53 | 0 | 0 | 0.00244 | 0.9307 |
| `tt_100C_1v80` | 4.5229 | 0.000 | 182.58 | 0 | 0 | 0.00241 | 0.9517 |
| `ss_100C_1v40` | **-6.2324** | -94.513 | 61.61 | 16 | 0 | 0.00746 | 0.5515 |
| `ss_100C_1v60` | **-1.0831** | -13.736 | 90.23 | 16 | 0 | 0.00575 | 0.7563 |
| `ss_n40C_1v28` | **-33.8669** | -671.109 | 22.80 | 105 | 0 | 0.02170 | 0.3169 |
| `ss_n40C_1v35` | **-20.2293** | -310.917 | 33.08 | 19 | 0 | 0.01051 | 0.4042 |
| `ss_n40C_1v40` | **-14.4282** | -219.811 | 40.94 | 16 | 0 | 0.01154 | 0.4789 |
| `ss_n40C_1v44` | **-11.0545** | -167.670 | 47.50 | 16 | 0 | 0.01233 | 0.5401 |
| `ss_n40C_1v60` | **-3.2067** | -45.830 | 75.72 | 16 | 0 | 0.00722 | 0.7192 |
| `ss_n40C_1v60_ccsnoise` | **-3.2067** | -45.830 | 75.72 | 16 | 0 | 0.00722 | 0.7192 |
| `ss_n40C_1v76` | 0.5433 | 0.000 | 105.75 | 0 | 0 | 0.00490 | 0.8792 |

- **Setup: 100 MHz closes at 10 of 18 corners** (both `tt`, all seven `ff`,
  and `ss_n40C_1v76`) and **does not close at the other eight `ss`
  corners**. Binding corner `ss_n40C_1v28`: WNS **-33.867 ns**, Fmax
  **22.80 MHz**, ~4.4x short of the target. Stated plainly, per
  `spec/decision-records/0002-...` Decision 1: **this layout does not close
  100 MHz across the ratified corner set.**
- **Hold: 0 violations at all eighteen corners** — the hold half of the T1
  checklist's "setup *and* hold across the PVT corner set", measured against
  the committed layout for the first time. Bounded: this `klt` pin reports a
  hold violation *count*, not hold-side WNS/TNS
  ([klayout-tools#1634](https://github.com/2AMLogic/klayout-tools/pull/1634)
  landed later than the pin), so corners cannot be ranked by hold margin.

**Do not read a delta between this table and the two above.** They differ in
both the artifact and the method: those measure a different floorplan with
no `power` block, and rebuild (and re-optimize) *per corner*, so each corner
carries its own `repair_timing` buffering; this one re-times a single fixed
geometry optimized only at the nominal corner, which reads *worse* at a slow
corner by construction. Separately, `klt sta` with `spef` omitted times
against LEF/DEF-derived parasitics rather than the
`estimate_parasitics -global_routing` basis `klt place-and-route`'s in-flow
STA uses — which is why the nominal corner reads +4.367 ns / 177.53 MHz here
against the +3.736 ns / 159.63 MHz the P&R record reports for the same DEF.
**That is a methodology difference, not an improvement**, and it makes this
table optimistic, not conservative. Full record, limitations, and raw
per-corner envelopes:
[`verification/records/sta-corner-sweep/records/20260915-111931-2c125f8.md`](../verification/records/sta-corner-sweep/records/20260915-111931-2c125f8.md).

### Why the slow corner binds: a standard-cell family derate (issue #132)

**Status: measured, 2026-09-23.** The sweep above was re-run in
`klt sta`'s single-envelope form (`pdk.corners`, a list —
[klayout-tools#1871](https://github.com/2AMLogic/klayout-tools/issues/1871))
against the same byte-identical DEF. **Every figure in the table above
reproduces bit-identically** across a `klt` pin bump (0.4.0 → 0.6.0), a
change of request shape, and two different OpenROAD builds. The verdict is
unchanged — 10/18, binding corner `ss_n40C_1v28` at **22.80 MHz** — and
the newer pin adds the hold-side slack figures the 2026-09-15 run could not
report (worst hold slack **+0.21354 ns**, at `ff_n40C_1v95`; +2.06884 ns at
the binding corner). Record:
[`verification/records/sta-corner-sweep/records/20260923-093000-28a7c96.md`](../verification/records/sta-corner-sweep/records/20260923-093000-28a7c96.md)
(supersedes the 2026-09-15 one).

What is new is *why*. The critical path at `ss_n40C_1v28` — startpoint
`_1205_` (DEF net `mm_a[15]`) → endpoint `_1175_` (DEF net `mm_p[6]`), 20
gates, arrival **42.17 ns** against 8.31 ns required — spends **21.07 ns of
its 42.17 ns in eight non-inverting compound cells** — and it propagates a
*falling* edge through every one of them. Extracting every combinational
cell's **per-polarity delay floor** from the installed liberty (the
smallest value in any `cell_fall`, resp. `cell_rise`, table of any arc —
what no path through the cell can beat on that edge, whichever pin
switches, regardless of load or slew) shows where that matters:

| Cell | fall floor @ `ss_n40C_1v28` | fall floor @ `tt_025C_1v80` | derate | rise floor @ ss |
| --- | --- | --- | --- | --- |
| `or4_1` | **4.4591 ns** | 0.3558 ns | 12.53x | 0.2394 ns |
| `or3_1` | **3.0074 ns** | 0.2678 ns | 11.23x | 0.2331 ns |
| `maj3_1` | **2.8753 ns** | 0.2916 ns | 9.86x | 0.4729 ns |
| `mux2_1` | **2.6321 ns** | 0.2430 ns | 10.83x | 0.3607 ns |
| `a311o_1` | 2.2119 ns | 0.2227 ns | 9.93x | 0.2727 ns |
| `nand4_1` | 0.1553 ns | 0.0376 ns | 4.13x | 0.1933 ns |
| `o41ai_1` | 0.0745 ns | 0.0298 ns | 2.50x | 0.1409 ns |
| `nand2_1` | 0.0674 ns | 0.0206 ns | 3.27x | 0.1240 ns |
| `nor2_1` | 0.0365 ns | 0.0076 ns | 4.80x | 0.2957 ns |
| `inv_1` | 0.0357 ns | 0.0144 ns | 2.48x | 0.0911 ns |

**The ratio is not the finding** — inverting cells derate 2.5–5x too, and
more than that on their rising edge. **The absolute magnitude on the
falling edge is**: at `ss_n40C_1v28`, non-inverting compound cells' falling
floors run one to two orders of magnitude above the inverting family's for
comparable fan-in (`or4_1` 4.4591 ns vs `nand4_1` 0.1553 ns), and a single
`or4_1` falling arc is **45% of the whole 10.0 ns period** before any load
or wire. At `tt_025C_1v80` the same pair is 0.3558 vs 0.0376 ns — the same
ratio, both negligible. That is precisely why a mapping that is clean at
the nominal corner does not survive the corner move. **209 of the 351
combinational cells** have at least one pin that, on at least one edge,
cannot switch in under 1.0 ns at `ss_n40C_1v28`.

A seven-build lever matrix (frozen under that record's
`artifacts/…/candidates/`) separates the levers. The numbers below are
`klt sta` setup slack / Fmax at `ss_n40C_1v28`, and the corner count is how
many of the eighteen close 100 MHz on setup **and** hold:

| RTL | Synthesis | P&R corner | Cells | `ss_n40C_1v28` | Closed |
| --- | --- | --- | --- | --- | --- |
| single-cycle (**committed**) | unconstrained, `tt` | `tt` | 682 | −33.867 ns / 22.80 MHz | 10/18 |
| single-cycle | 10 ns @ ss | `tt` | 717 | −31.855 ns / 23.89 MHz | 10/18 |
| single-cycle | 10 ns @ ss + cell exclusion | `tt` | 865 | −18.307 ns / 35.33 MHz | 13/18 |
| bit-serial | 10 ns @ ss | `tt` | 932 | −10.224 ns / 49.45 MHz | 15/18 |
| bit-serial | 10 ns @ ss | `ss_n40C_1v28` | 932 | −8.039 ns / 55.44 MHz | 16/18 |
| bit-serial | 10 ns @ ss + cell exclusion | `tt` | 1204 | −5.845 ns / 63.11 MHz | 16/18 |
| bit-serial | 10 ns @ ss + cell exclusion | `ss_n40C_1v28` | 1204 | **+0.489 ns / 105.14 MHz** | **18/18** |

Three readings, all of them load-bearing:

- **The cheap experiment is a dead end, and now has a number.**
  `spec/decision-records/0002-…` Decision 3 named a timing-constrained
  synthesis pass as the first thing to try and left it untried. It is worth
  **≈1.1 MHz of a ≈77 MHz gap** and closes no additional corner.
- ~~**100 MHz is reachable at all eighteen corners**~~ — **withdrawn,
  2026-09-24, see the subsection below.** The 18/18 row did not reproduce.
  The ratified target is still *not* lowered, but that is now a decision
  about the target rather than a claim backed by a reproducible 18/18.
- **The 18/18 row is not landed**, for two disclosed reasons: the cell
  exclusion has no `klt synthesize` request field (it was produced by
  invoking Yosys directly, so it is not re-runnable from a committed
  request), and that row's own in-flow place-and-route STA —
  routing-estimated parasitics rather than LEF/DEF-derived — reports
  **−1.105 ns / 90.05 MHz** at the same corner on the same database. Both
  numbers are real and they disagree about closure. Its cost is also not
  small: **+522 cells** and ≈**33x** the cycle count — against a 4.6x
  clock gain, a **net throughput loss of roughly 7x**. It is a *closure*
  result, not a throughput result, and must never be quoted as one.

The full decision, with the exception it ratifies and the priced exit from
it, is
[`spec/decision-records/0004-slow-corner-closure-is-cell-selection-bound-and-the-disclosed-t1-item-5-exception.md`](../spec/decision-records/0004-slow-corner-closure-is-cell-selection-bound-and-the-disclosed-t1-item-5-exception.md).

### The 18/18 row did not reproduce (issue #141, 2026-09-24)

The blocking dependency the row above names —
[klayout-tools#2382](https://github.com/2AMLogic/klayout-tools/issues/2382),
a request-level cell exclusion in `klt synthesize` — **landed upstream**
([#2429](https://github.com/2AMLogic/klayout-tools/pull/2429),
`constraints.dont_use`). Issue #141 ran the exit end-to-end through
committed `klt` requests for the first time. Result, frozen as
[`verification/records/sta-corner-sweep/records/20260924-134500-1a8313b.md`](../verification/records/sta-corner-sweep/records/20260924-134500-1a8313b.md):

| | row 6 (frozen, 2026-09-23) | re-spin (2026-09-24) |
| --- | --- | --- |
| mapped instances | 1204 | **1105** |
| `klt sta` @ `ss_n40C_1v28` | +0.489 ns / 105.14 MHz | **−0.574 ns / 94.57 MHz** |
| in-flow P&R STA @ same corner | −1.105 ns / 90.05 MHz | **−1.160 ns / 89.60 MHz** |
| corners closed | **18/18** | **17/18** |

- **The reproducibility objection is discharged.** `klt synthesize` driven
  by a committed `constraints.dont_use` request produces a netlist
  **byte-identical** to the frozen hand-rolled Yosys script's, on the same
  host, with a flag-for-flag identical `abc` line.
- **Row 6's netlist is not reproducible across hosts by *any* route.** Both
  the committed request and row 6's own frozen script give 1105 instances
  here, identically under Yosys 0.67 and 0.68 — so the 1204 figure traces
  to the **ABC build embedded in the Yosys binary**, not to the request
  field and not to a Yosys version. That 8.2% mapping difference is worth
  **1.06 ns** at the binding corner: the difference between closing and not.
- **The two STA methodologies now agree, against closure.** The in-flow
  number reproduced to within 0.06 ns; the optimistic `klt sta` number is
  the one that moved.
- **Nothing was landed.** `layout/`, `rtl/` and `flow/`'s requests are
  unchanged; T1 item 5 remains the disclosed 10/18 at 22.80 MHz against the
  committed layout. The re-spun (uncommitted) GDS is `klt drc` **clean, 0
  violations**, which is recorded so the next attempt knows item 3 is not
  automatically at risk.

Re-priced bill, superseding record `0004` Decision 2's:
[`spec/decision-records/0005-the-priced-exit-was-run-and-does-not-reproduce.md`](../spec/decision-records/0005-the-priced-exit-was-run-and-does-not-reproduce.md).

### What this run does not claim

Per `klt place-and-route`'s documented v1 scope, the GDS this section's
figures were originally measured against had **no tapcell insertion, no
power-grid (PDN) generation, no metal fill, no filler-cell insertion, and
no `DONT_USE_CELLS` exclusion** — core-only floorplanning, no IO ring.
**Updated, issue #81 (2026-09-11)**: `flow/par-modexp.json` (the
committed, single-corner nominal recipe backing `layout/modexp.gds`) has
since gained a `power` block, and the regenerated GDS now has tapcell
insertion, PDN generation, and filler-cell insertion — see
[`layout/README.md`](../layout/README.md) and
[`verification/records/place-and-route/records/20260911-052542-d5e43d3.md`](../verification/records/place-and-route/records/20260911-052542-d5e43d3.md)
for the current state; DRC is now clean against it
([`docs/signoff-claim.md`](signoff-claim.md)). Metal (density) fill and
`DONT_USE_CELLS` exclusion remain absent. **The 18-corner sweep figures in
this section are unaffected** — they were always measured via
`flow/run-corner-sweep.sh`'s separate, revised (55% utilization) floorplan,
never against the committed `layout/modexp.gds`/`flow/par-modexp.json`
this note describes, and issue #81 did not re-run that sweep. It is not
yet a fully signoff-ready macro (LVS is still not clean); the full record,
including provenance and the reproduction recipe, is at
[`verification/records/place-and-route/`](../verification/records/place-and-route/).

## Post-route gate-level simulation — appended, issue #9; Leg 2 updated, issues #55, #78

**Status: Leg 1 achieved (PASS). Leg 2 re-attempted, 2026-09-09 (issue
#78) — still FAIL, but the failure class narrowed materially.** Until this
run, every correctness claim on this page
rested on *behavioural* simulation of `rtl/modexp.v`. Synthesis mapping,
tie-cell insertion, CTS, and OpenROAD's placement/timing optimizations were
unverified by simulation.

### What was simulated, and why it is not the P&R input netlist

`klt place-and-route` exports no post-route gate-level netlist (its response
contract is `def_path` + `gds_path`). The netlist simulated here is therefore
**derived from the routed layout itself** —
`layout/modexp.gds` → `klt extract --abstract-cells` (issue #8's
`layout/lvs/modexp_layout_abstracted.spice`) →
`verification/gate-level/spice_to_verilog.py` →
`verification/gate-level/modexp_post_route.v`, **718 instances / 59 cell
types / 68 pins / 1214 nets**, all cross-checked against
`layout/lvs/modexp_layout_extract_report.json` before the run is allowed to
proceed.

That 718 matters: the netlist P&R was *given* has 683 instances (+1 tie
cell). Simulating that one and calling the result "post-route" would omit all
35 CTS/timing-fixup insertions and all 5 drive-strength resizes the routed
GDS actually contains — an overclaim that would have *passed*.

### The measurement

| Leg | Driver | Result |
| --- | --- | --- |
| `test_modexp.py`, unmodified, via `klt functional-verification` | `verification/gate-level/run-gate-level-sim.sh` | `status: "pass"`, 2/2 tests, 0 failed |
| 500-case randomized run, `cross_check_tb.py` unmodified, same pinned seed as the RTL cross-check | `verification/gate-level/gate_level_cross_check.py` | 500/500 match, 0 mismatches |

The second leg's per-vector transcript is **byte-identical** to the RTL
cross-check's committed `WIDTH=16` transcript
(`verification/records/width-cross-check/artifacts/20260808-031948-5488082/width-16.jsonl`) —
the routed netlist returned exactly the same 500 results, in the same order.
The klt leg's simulated time also matches the RTL run's to the nanosecond
(23750.0 ns / 180480.0 ns), i.e. the routed design is cycle-for-cycle
identical to the RTL, not merely functionally equivalent.

`test_modexp.py` was not edited, and was not copied: it is reached through a
git symlink (`git ls-files -s verification/gate-level/test_modexp.py` → mode
`120000`).

### What this run does not claim

- **No parasitics** (no `--parasitics` extraction, no SPEF), **no timing**,
  **no corner**. It is zero-delay logic; the only delay in it is a 1 ns
  `UNIT_DELAY` on flop outputs, a race-avoidance device rather than a
  characterized delay. sky130A ships 18 liberty corners but one
  corner-independent set of Verilog cell models, so this run has no corner
  attribute at all. Timing evidence remains the OpenSTA corner sweep above.
- **No power/ground network** — power pins are dropped; this GDS has no PDN.
- **`WIDTH` = 16 only.** The netlist is an extraction of one fixed physical
  layout of one elaboration; `WIDTH` is an RTL parameter that does not
  survive synthesis. The case count is *not* reduced (500, matching the RTL
  claim).
- **Leg 2 (delay-annotated SDF simulation), updated 2026-09-09 (issue
  #78): RE-ATTEMPTED — still FAIL, narrower failure class.** Issue #55
  first bumped this repo's `klt` pin past
  [klayout-tools#1007](https://github.com/2AMLogic/klayout-tools/pull/1007)
  and ran Leg 2 end to end for the first time: 200 of ~753 `INTERCONNECT`
  entries (all top-level-port-attached) could not be resolved by Icarus
  13.0's `$sdf_annotate`, filed generically as
  [klayout-tools#1056](https://github.com/2AMLogic/klayout-tools/issues/1056).
  Issue #78 bumped the pin again, past
  [klayout-tools#1069](https://github.com/2AMLogic/klayout-tools/pull/1069)
  (`#1056`'s fix — a generated pass-through wrapper), and re-ran Leg 2
  against a fresh post-route build's own `write_verilog` netlist +
  `write_sdf` output (not `layout/modexp.gds` — a pin bump does not
  reproduce P&R byte-for-byte). Result: the fix works for its stated scope
  (top-level ports, including `done`, now resolve), but `klt`'s own SDF
  diagnostic gate still reports the run **FAILED** — a new, narrower
  residual class of 49 unresolved `INTERCONNECT` entries (down from 200),
  and the regression itself still returns a uniform, constant-zero result
  on every case even though `done` itself now resolves. Not a "blocked, no
  artifact" state — a concrete, evidenced fail, now with a much smaller
  surface. Full detail:
  `verification/records/gate-level-sim/records/20260909-230216-92e00f2.md`.

Full method, scope, and the friction filed upstream:
[`verification/gate-level/README.md`](../verification/gate-level/README.md).
Records are at
[`verification/records/gate-level-sim/`](../verification/records/gate-level-sim/).
