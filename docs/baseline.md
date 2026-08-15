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

### What this run does not claim

Per `klt place-and-route`'s documented scope, the produced GDS
(`layout/modexp.gds`) has **no tapcell insertion, no power-grid (PDN)
generation, no metal fill, no filler-cell insertion, and no
`DONT_USE_CELLS` exclusion** — core-only floorplanning, no IO ring. It is
not a signoff-ready macro; DRC/LVS-clean signoff is later work (issue #8 and
beyond). The full record, including provenance and the reproduction recipe,
is at
[`verification/records/place-and-route/`](../verification/records/place-and-route/).

## Post-route gate-level simulation — appended, issue #9

**Status: Leg 1 achieved, Leg 2 blocked on upstream tooling.** Until this
run, every correctness claim on this page rested on *behavioural* simulation
of `rtl/modexp.v`. Synthesis mapping, tie-cell insertion, CTS, and OpenROAD's
placement/timing optimizations were unverified by simulation.

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
- **Leg 2 (delay-annotated / SDF simulation at the corner set) was NOT
  achieved**, and is not claimed. No artifact in this flow carries post-route
  delays: `klt place-and-route` has no SDF export and `klt
  functional-verification` has no SDF option
  ([klayout-tools#1002](https://github.com/2AMLogic/klayout-tools/issues/1002),
  open). Independently, Icarus 12.0 cannot simulate the SDF-annotatable
  (non-`FUNCTIONAL`) cell models at all
  ([klayout-tools#1004](https://github.com/2AMLogic/klayout-tools/issues/1004)).
  Both blockers are evidenced in the record's artifacts.

Full method, scope, and the friction filed upstream:
[`verification/gate-level/README.md`](../verification/gate-level/README.md).
The record is
[`verification/records/gate-level-sim/`](../verification/records/gate-level-sim/).
