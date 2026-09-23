# 0004: Slow-corner closure is cell-selection-bound; the disclosed T1 item-5 exception, and the measured route out of it

- **Status**: ratified
- **Date**: 2026-09-23
- **Decided by**: Builder (issue #132), discharging
  `spec/decision-records/0002-slow-corner-timing-closure-and-mm-red-critical-path.md`
  Decision 3's named follow-up, and extending record `0001` Decision 5 item 5

## Context

T1 checklist item 5 (Digital column: *"multi-corner static timing analysis
— setup and hold across the PVT corner set"*) passes only when **every**
corner a `klt sta` citation reports is `timing_status: "constrained"` with
non-negative setup **and** hold slack. Against the committed, post-#81
layout (`layout/modexp.def`, content_hash `sha256:a35b9567…`) the ratified
100 MHz Clock row closes at **10 of 18** ratified corners; the binding
corner `ss_n40C_1v28` achieves **22.80 MHz**, roughly **4.4x short**.

Record `0002` named two ordered follow-ups and explicitly deferred both: a
constrained-synthesis experiment first (*"its job is to establish how much
of the gap is mapping and how much is architecture, which nothing in this
repository currently knows"*), and RTL restructuring second if that proved
insufficient. Neither had ever been run. Issue #132 ran both, plus a third
lever record `0002` did not anticipate, and this record is the result.

**Provenance of every number below**: all figures are measured, produced by
issue #132 and frozen under
`verification/records/sta-corner-sweep/artifacts/20260923-093000-28a7c96/`
(the sign-off leg) and its `candidates/` subtree (the experiment matrix).
Nothing here is a target, an estimate, or a projection, and no external
standard-cell library's published figure is referenced or compared against,
per `CLAUDE.md`'s overclaim-trap section.

## The critical path at `ss_n40C_1v28`, re-derived against the shipped layout

Record `0002` measured the critical path against the **pre**-#81 layout.
Re-derived here against the layout this repo actually ships
(`report_checks -path_delay max` on `layout/modexp.def`, sky130A
`sky130_fd_sc_hd__ss_n40C_1v28.lib`, ideal clock, 10.0 ns period; frozen as
`…/artifacts/20260923-093000-28a7c96/ss_n40C_1v28-critical-path.txt`):

> **Startpoint** `_1205_` (flop driving net **`mm_a[15]`**) →
> **Endpoint** `_1175_` (flop driving net **`mm_p[6]`**), 20 combinational
> gates, data arrival **42.17 ns** against a required time of **8.31 ns**
> (10.0 ns period less 1.69 ns library setup), slack **−33.87 ns**.

The DEF's own net names make the RTL correspondence exact rather than
inferred: `mm_a[15]` is `rtl/modexp.v`'s multiplier MSB (the bit selecting
`mm_add`) and `mm_p[6]` is a bit of the running partial product. The path
is therefore the whole single-cycle `S_MM_RUN` body —
`mm_add = mm_a[WIDTH-1] ? mm_b : 0`, `mm_sum = mm_p2 + mm_add`, then
`mm_red`'s two serially-dependent compare-and-subtract stages — exactly the
structure record `0002` Decision 3 identified, now with a current number
(42.17 ns, against that record's 39.99 ns on the older layout).

**What is new is the gate-level composition**, and it is not what a depth
argument predicts. Eight of the twenty gates are sky130's *non-inverting
compound* cells, and they alone account for **21.07 ns of the 42.17 ns**:

| Gate on the path | Delay at `ss_n40C_1v28` |
|---|---|
| `and3_1` | 2.00 ns |
| `a211o_1` | 2.36 ns |
| `a311o_1` | 3.03 ns |
| `a31o_1` | 1.71 ns |
| `maj3_1` x3 (the adder carry chain) | 3.24 + 3.46 + 3.52 ns |
| `a32o_1` | 1.75 ns |

## The root cause: a falling-edge floor in one cell family, not a per-path depth problem

Every `sky130_fd_sc_hd` combinational cell's **delay floor** was extracted
from the installed liberty at both corners — the smallest value in any
`cell_fall` (resp. `cell_rise`) table of *any* of its timing arcs: the
delay no path through that cell can beat on that transition direction,
whichever input pin switches, regardless of output load or input slew. All
351 combinational cells; full table frozen as
`…/candidates/cell-delay-floors.json`.

**Polarity is the axis that matters, and a polarity-blind reduction hides
the whole effect.** Falling floors:

| Cell | fall floor @ `ss_n40C_1v28` | fall floor @ `tt_025C_1v80` | derate | (rise floor @ ss, for contrast) |
|---|---|---|---|---|
| `or4_1` | **4.4591 ns** | 0.3558 ns | 12.53x | 0.2394 ns |
| `or3_1` | **3.0074 ns** | 0.2678 ns | 11.23x | 0.2331 ns |
| `maj3_1` | **2.8753 ns** | 0.2916 ns | 9.86x | 0.4729 ns |
| `mux2_1` | **2.6321 ns** | 0.2430 ns | 10.83x | 0.3607 ns |
| `a311o_1` | 2.2119 ns | 0.2227 ns | 9.93x | 0.2727 ns |
| `a211o_1` | 1.8208 ns | 0.1909 ns | 9.54x | 0.2072 ns |
| `or2_1` | 1.6325 ns | 0.1725 ns | 9.46x | 0.2336 ns |
| `a32o_1` | 1.4481 ns | 0.1677 ns | 8.64x | 0.3833 ns |
| `a31o_1` | 1.1421 ns | 0.1381 ns | 8.27x | 0.2423 ns |
| `and3_1` | 0.8054 ns | 0.1084 ns | 7.43x | 0.4777 ns |
| — inverting families, same corners — | | | | |
| `nand4_1` | 0.1553 ns | 0.0376 ns | 4.13x | 0.1933 ns |
| `o21ai_0` | 0.1014 ns | 0.0344 ns | 2.95x | 0.1584 ns |
| `o31ai_1` | 0.0858 ns | 0.0324 ns | 2.65x | 0.1713 ns |
| `o41ai_1` | 0.0745 ns | 0.0298 ns | 2.50x | 0.1409 ns |
| `nand2_1` | 0.0674 ns | 0.0206 ns | 3.27x | 0.1240 ns |
| `nor2_1` | 0.0365 ns | 0.0076 ns | 4.80x | 0.2957 ns |
| `inv_1` | 0.0357 ns | 0.0144 ns | 2.48x | 0.0911 ns |

Three things follow, and the third is the one that binds.

1. **Ratios alone would be misleading.** Plenty of inverting cells derate
   3–5x too, and several derate more than that on their *rising* edge.
   Ratio is not the finding.
2. **Absolute magnitude on the falling edge is the finding.** At
   `ss_n40C_1v28` the non-inverting compound family's falling floors are
   **one to two orders of magnitude** larger than the inverting family's
   for comparable fan-in — `or4_1` 4.4591 ns against `nand4_1` 0.1553 ns.
   A single `or4_1` falling arc is **45% of the 10.0 ns clock period**,
   before any load, before any wire. At `tt_025C_1v80` the same pair is
   0.3558 ns against 0.0376 ns: the ratio is nearly the same, and both are
   negligible against the budget. **This is why nominal-corner-clean
   mapping decisions do not survive the corner move.**
3. **A path collects whichever edge it actually propagates.** The critical
   path above propagates a *falling* edge through every one of its eight
   non-inverting compound cells. That is not a coincidence — the falling
   edge is the cheap one to arrive on and the expensive one to leave on.

**209 of the 351 combinational cells** have at least one input pin that, on
at least one edge, cannot switch in under 1.0 ns at `ss_n40C_1v28` — more
than 10% of the entire clock period for one gate. That criterion
(`worst_arc_any_polarity_floor_ns_ss_n40C_1v28 > 1.0`, carried per-cell in
the frozen table) is exactly the exclusion list rows 2, 5 and 6 below were
mapped with.

This reframes the problem. Record `0002` read the gap as architectural
("39.99 ns of arrival time against a 10 ns period is a ~4.2x gap, and the
path is one combinational chain whose depth is set by the RTL"). That
reading is correct as far as it goes — the matrix below confirms RTL
restructuring is the single biggest lever — but it is **incomplete**:
**the mapper's cell-family choice is a second, independent lever that no
amount of RTL work reaches**, and nothing in this repository had measured
it. Reducing logic depth does not help if the remaining gates each cost
2–4 ns; the matrix below shows the RTL lever alone stalling at 49.45 MHz
for exactly that reason. Yosys's ABC maps against this very liberty and
still selects the slow family, because it optimizes area subject to a
delay *target* rather than avoiding cells whose floor alone consumes half
the budget.

## The measured lever matrix

Seven builds, one table. Every row: `WIDTH=16`, `flow/par-modexp.json`'s
floorplan (35% utilization, `core_margin_um` 4, the `power` block, seed 42,
`target_stage: route`), 10.0 ns clock, then one `klt sta` characterization
of that row's own routed DEF at all eighteen ratified corners. The
`ss_n40C_1v28` column is the binding corner's `klt sta` setup slack;
"closed" counts corners with `timing_status: "constrained"` and
non-negative setup **and** hold slack.

| # | RTL | Synthesis | P&R corner | Cells | `ss_n40C_1v28` | Fmax there | Closed |
|---|---|---|---|---|---|---|---|
| 0 | single-cycle (shipped) | unconstrained, `tt` | `tt` | 682 | −33.867 ns | 22.80 MHz | 10/18 |
| 1 | single-cycle | **10 ns @ `ss_n40C_1v28`** | `tt` | 717 | −31.855 ns | 23.89 MHz | 10/18 |
| 2 | single-cycle | 10 ns @ ss + **cell exclusion** | `tt` | 865 | −18.307 ns | 35.33 MHz | 13/18 |
| 3 | **bit-serial** | 10 ns @ ss | `tt` | 932 | −10.224 ns | 49.45 MHz | 15/18 |
| 4 | bit-serial | 10 ns @ ss | **`ss_n40C_1v28`** | 932 | −8.039 ns | 55.44 MHz | 16/18 |
| 5 | bit-serial | 10 ns @ ss + **cell exclusion** | `tt` | 1204 | −5.845 ns | 63.11 MHz | 16/18 |
| 6 | bit-serial | 10 ns @ ss + cell exclusion | **`ss_n40C_1v28`** | 1204 | **+0.489 ns** | **105.14 MHz** | **18/18** |

Read row by row, the three levers separate cleanly:

- **Constrained synthesis alone (row 1) buys essentially nothing**:
  22.80 → 23.89 MHz, still 10/18, at a cost of 35 cells. Record `0002`
  Decision 3's step 1 asked precisely "how much of the gap is mapping" and
  deferred an answer; the answer is **≈1.1 MHz of a ≈77 MHz gap**. This
  record discharges that question with its number, and the cheap option is
  now closed as a dead end rather than left as an untried hope.
- **Cell-family exclusion is worth ~10x more than the constraint** on the
  *unchanged* RTL (row 1 → row 2): +11.44 MHz against the constraint's
  +1.09 MHz, and 10/18 → 13/18.
- **RTL restructuring (row 3) is the single largest lever**: 49.45 MHz,
  15/18 — but on its own it still leaves a 2.0x shortfall, so record
  `0002`'s implied hope that pipelining alone closes the gap is refuted.
- **Only all three together close it** (row 6): 18/18, +0.489 ns of setup
  margin and +2.519 ns of hold margin at the binding corner.

The "bit-serial" RTL in rows 3–6 is a re-derivation of the Blakley inner
step that keeps the algorithm and the module interface bit-identical while
serializing each step LSB-first across one-gate-deep slices (one serial
full-adder pass, one serial dual-subtractor pass, one select cycle). It is
bit-exact against `pow(base, exp, mod)` — **2000/2000 match, 0 mismatches
across `WIDTH` = 4, 6, 8, 16** (`verification/cross_check.py`), and 3/3 on
the `klt functional-verification` suite — and is frozen verbatim as
`…/candidates/rtl/modexp-bit-serial.v`. Its cost is stated plainly, not
buried: **+250 cells (682 → 932 before exclusion, 1204 after)** and a
latency of `(WIDTH + popcount(exp))*(WIDTH*(2*WIDTH+6)+2) + WIDTH + 3`
cycles, which at `WIDTH=16` is **32.8x** the single-cycle core's cycle
count for an all-ones exponent (19539 against 595) and 31.9–32.8x across
`popcount(exp)` = 0..16. **Row 6 trades ~33x more cycles for ~4.6x more
clock — a net throughput loss of roughly 7x.** It is a *closure* result,
**not** a throughput result, and must never be quoted as one.

## Decision 1 — Row 6 is not landed, and why that is the correct call

**Options considered:**

- **(a) Land row 6 now** — commit the bit-serial RTL, the excluded-cell
  netlist and the new routed layout, and claim item 5 met at 18/18.
  **Rejected on two independent grounds, either sufficient.**
  1. **It is not reproducible through the committed `klt` flow.** The cell
     exclusion is not expressible in a `klt synthesize` request: the
     `-dont_use` list is a hardcoded per-cell-library table in `klt`
     (`_ABC_DONT_USE_GLOBS`, sky130 → `lpflow_*` / `probe*` only) with no
     request-level field, and that table's own documentation says a caller
     wanting a different exclusion "can be served later by an explicit
     request field". Row 6 was produced by invoking Yosys directly with the
     209 exclusions appended — legitimate as an *experiment*, but a
     committed recipe that cannot be re-run by `klt synthesize
     flow/synthesize-modexp.json` would make `verification/`'s central
     promise ("no claim without a testbench", re-runnable from committed
     artifacts) false for the headline timing claim. Filed upstream per
     `CLAUDE.md`'s friction protocol (see "Friction filed" below).
  2. **The 18/18 is methodology-marginal and must not be read as
     comfortable.** Row 6's own in-flow place-and-route STA — which runs
     `estimate_parasitics -global_routing` before timing — reports
     **−1.105 ns / 90.05 MHz** at `ss_n40C_1v28` on the *same* database
     the `klt sta` sweep scores at +0.489 ns / 105.14 MHz. The two numbers
     are both real and disagree about closure, because `klt sta` with
     `spef` omitted is optimistic relative to a routing-estimated run (the
     same methodology gap record `20260915-111931-2c125f8` already
     documented). A design whose closure verdict flips with the parasitic
     basis has no margin, and landing it under the more favourable of two
     available methods would be exactly the kind of quiet grade inflation
     this repo exists to avoid.
- **(b) Re-ratify the 100 MHz target down to the measured floor.**
  **Rejected, and named here so it is not attempted later.** Row 6 is a
  live, measured demonstration that 100 MHz is *reachable* at all eighteen
  corners in this PDK with this block's function. `spec/modexp.md`
  Decision 3 and `CLAUDE.md` permit changing a ratified target only on a
  showing that the target is **wrong**; the evidence here shows the
  opposite. The target is not lowered, not narrowed, and the corner matrix
  of record `0001` Decision 4 is not renegotiated.
- **(c) Carry the gap as an explicit, bounded, disclosed exception with
  its number, while recording the measured route out of it.**
  **Chosen.**

**Decision:**

> **T1 item 5 is FAIL, disclosed, with its number.** As of
> `layout/modexp.def` @ content_hash `sha256:a35b9567…`, the ratified
> 100 MHz Clock row closes at **10 of 18** ratified corners. The binding
> corner is **`ss_n40C_1v28`** at **22.80 MHz** (setup slack −33.867 ns,
> TNS −671.109 ns, 105 setup violations). **Hold is clean at all eighteen
> corners** (worst hold slack +0.214 ns at `ff_n40C_1v95`, +2.069 ns at
> the binding corner), so the failure is purely setup.
>
> This exception is **bounded** in three explicit ways, all of which must
> be restated by anything that cites it:
> 1. **It is a FAIL, not a pass-with-caveats.** `spec/modexp.md`'s Clock
>    row is not amended, the corner matrix is not narrowed, and
>    `verification/signoff/block-manifest.json` cites the failing sweep so
>    `klt signoff` renders item 5 `unmet` from the evidence itself rather
>    than from an absence of evidence.
> 2. **It carries its number**: 22.80 MHz at `ss_n40C_1v28`, 10/18. Per
>    record `0002` Decision 1, no claim in this repository may say this
>    block "closes 100 MHz" without naming the corner set; that rule now
>    binds this record's own number too.
> 3. **It is time-bounded by a named, measured exit**: Decision 2 below.
>
> The all-corner Fmax future work is held to is hereby updated from record
> `0002` Decision 2's **23.98 MHz** to **22.80 MHz** at `ss_n40C_1v28`,
> measured on the current layout by `klt sta` rather than by eighteen
> independent per-corner rebuilds. The two numbers are **not** a
> regression against each other and must not be reported as one — they are
> different layouts measured by different methods (see record
> `20260915-111931-2c125f8`, "Why these numbers are not corner-for-corner
> comparable").

**Consequences:** item 5 moves from `no_evidence` (no citable envelope
existed) to a cited, graded `unmet` — a worse-looking row that is a
strictly better evidence state, because the number is now machine-checked
against the committed layout's own hash instead of asserted in prose. The
bad consequence, stated plainly: this block still does not run at 100 MHz
across its own ratified operating conditions, it is not going to before
the exit in Decision 2 is available, and no result in this repository may
be phrased as though it does.

## Decision 2 — The named exit, and its enumerated price

**Options considered:**

- **(a) Leave the route out unstated**, as "future work". Rejected: the
  whole cost of record `0002`'s deferral was that its step 1 sat untried
  for five weeks because nobody could see what it would cost or buy. This
  record is not going to repeat that.
- **(b) State the exit as an ordered, priced sequence with its blocking
  dependency named.** **Chosen.**

**Decision:**

> The measured exit from Decision 1's exception is **row 6 of the lever
> matrix**, and it is blocked on exactly one external capability:
>
> 1. **Blocking dependency**: a request-level standard-cell exclusion in
>    `klt synthesize` —
>    [klayout-tools#2382](https://github.com/2AMLogic/klayout-tools/issues/2382).
>    Until it exists, row 6 cannot be expressed as a committed, re-runnable
>    recipe, and this repo does not land timing claims it cannot re-run.
>    Tracked downstream as
>    [sky130-modexp#141](https://github.com/2AMLogic/sky130-modexp/issues/141),
>    which carries the bill below as its own acceptance criteria.
> 2. **When it lands**, the re-spin is: bit-serial RTL (frozen, already
>    bit-exact at every verified `WIDTH`) → `klt synthesize` with the
>    exclusion list and `constraints.clock_period_ns: 10.0` at
>    `ss_n40C_1v28` → `klt place-and-route` at `ss_n40C_1v28` →
>    `klt sta` over the eighteen corners.
> 3. **Its enumerated price, so nobody starts it believing it is free:**
>    - a **new decision record**, because it invalidates record `0001`
>      Decision 3's ratified latency formula
>      (`cycles = WIDTH*(WIDTH + 3) + popcount(exp_in)*(WIDTH + 2) + 2`),
>      which is part of this block's ratified interface contract;
>    - **+522 cells** (682 → 1204) and ~**33x** the cycle count, both of
>      which must be reported alongside any Fmax claim from it;
>    - a **full re-mint of every layout-derived evidence leg**, because it
>      replaces `layout/modexp.def` and `layout/modexp.gds`: T1 items 3
>      (DRC), 4 (LVS), 7 (post-layout simulation) and 11 (power delivery)
>      all cite the current GDS/DEF content hashes and go stale at a
>      stroke. Item 3 is currently **met**; a careless re-spin turns a met
>      row unmet;
>    - a **resolution of the two-methodology disagreement** at the binding
>      corner (row 6: `klt sta` +0.489 ns vs in-flow routing-estimated
>      −1.105 ns), since a +0.489 ns claim that the other available method
>      contradicts is not a sign-off-grade result. Extracted parasitics
>      (`klt extract --parasitics` → `request.spef`) is the principled
>      resolution and is itself blocked on the net-name-correlation problem
>      issue #55 evidenced.
>
> **This sequence is a recommendation, not a mandate** — whoever picks it
> up makes the final call, exactly as record `0002` Decision 3 framed its
> own. What is ratified here is the *pricing*, so the call is made with
> the cost visible.

**Consequences:** the next timing-directed piece of work on this block has
a measured target (18/18, +0.489 ns), a named blocker, and a four-item
bill. Nothing obliges anyone to start it. If the program instead elects to
keep Decision 1's exception indefinitely, that is legitimate — but it
remains a disclosed FAIL carried against an unamended ratified row, and
converting it to anything else needs its own decision record.

## Friction filed

Per `CLAUDE.md`'s friction protocol, filed generically at
`2AMLogic/klayout-tools` (the gap described, not this design):

- **`klt synthesize` has no request-level standard-cell exclusion** —
  [klayout-tools#2382](https://github.com/2AMLogic/klayout-tools/issues/2382).
  The `abc -dont_use` list is a hardcoded per-cell-library table; a caller
  cannot express a corner-driven exclusion (e.g. "exclude every cell whose
  delay floor at the target corner exceeds a fraction of the clock
  period") without bypassing `klt` and invoking Yosys directly, which
  makes the resulting netlist non-reproducible from a committed request.

## Numbers in this record

Every figure above is measured. The sign-off leg (row 0, the critical-path
report, and the eighteen-corner table Decision 1 ratifies) was produced on
this repo's pinned toolchain — klt `dac2b5da`, OpenROAD
`26Q3-1260-g06a5a02279` via the pinned `openroad/orfs` image, sky130A
`open_pdks c6d73a35`. Frozen at
`verification/records/sta-corner-sweep/records/20260923-093000-28a7c96.md`
and its artifacts. No figure here is a target, an estimate, or a
projection, and no external standard-cell library's published figure is
referenced or compared against, consistent with `CLAUDE.md`'s
overclaim-trap section and `docs/baseline.md`.
