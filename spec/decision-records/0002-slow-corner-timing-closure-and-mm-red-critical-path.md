# 0002: Slow-corner timing closure, the measured all-corner Fmax, and the `mm_red` critical path

- **Status**: ratified
- **Date**: 2026-08-14
- **Decided by**: Builder (issue #16), extending `spec/modexp.md` Decision 2
  and record `0001` Decisions 4/5

## Context

The first place-and-route run (issue #7, merged as PR #17, record
`verification/records/place-and-route/records/20260814-203901-c741877.md`)
swept the full eighteen-corner `sky130_fd_sc_hd` matrix ratified by record
`0001` Decision 4, rather than reporting the nominal corner alone. The
measured result (`docs/baseline.md#full-corner-matrix-sweep`):

- **100 MHz closes at 9/18 corners** — both `tt` corners and all seven `ff`
  corners, WNS +3.318 to +5.719 ns, achieved Fmax 149.66–233.57 MHz.
- **100 MHz fails at 9/18 corners** — every `ss` (slow-process) corner, WNS
  −0.612 to −31.697 ns, achieved Fmax **23.98–94.23 MHz**.
- The binding corner is **`ss_n40C_1v28`**: WNS −31.697 ns, TNS −566.638 ns,
  98 setup violations, 0 hold violations, achieved Fmax **23.98 MHz**.

This is not a violation of any ratified text. Record `0001` Decision 4
already holds `spec/modexp.md` Decision 2's 100 MHz Phase 2 target to the
nominal corner (`tt_025C_1v80`) alone, which closes with +3.318 ns of
margin, and already names full eighteen-corner closure as a **T1 sign-off**
requirement (record `0001` Decision 5, item 5) rather than a per-commit
Phase 2 gate. What did not exist before this run was any *measured* timing
number at all — record `0001` says so explicitly ("no timing number of any
kind, at any corner, exists yet in this repo"). It exists now, and
`spec/modexp.md` Decision 2's own revisit trigger has therefore fired: *"the
first OpenROAD timing-closure run reports an achievable Fmax. That measured
result — not this target — becomes the number future work is held to."*

This record is that revisit, made per `spec/modexp.md` Decision 3's process
(a new decision record entry, never an edit to the ratified text). The
100 MHz constraint in `flow/par-modexp.json` was not relaxed and is not
relaxed here; `spec/modexp.md` was not edited and is not edited here.

**Provenance of every number below:** all figures are measured, taken from
`docs/baseline.md#full-corner-matrix-sweep` and the frozen artifacts under
`verification/records/place-and-route/artifacts/20260814-203901-c741877/`
(`corner-sweep-results.json`, `ss_n40C_1v28-critical-path.txt`). No figure
in this record is a target or an estimate, and no figure here is compared to
any external standard-cell library's published result — that comparison is
prohibited by `CLAUDE.md`'s overclaim-trap section and is not made.

## Decision 1 — Decision 2's nominal-corner framing stands as ratified

**Options considered:**

- **(a) Promote full eighteen-corner closure at 100 MHz to a Phase 2
  boundary condition** — i.e. "Phase 2 is not done until every corner
  closes." Rejected. It would make Phase 2 (whose ratified scope is
  cell-count and timing work on the existing Blakley core, per
  `spec/modexp.md` Decisions 3 and 5) gate on a 4.2× timing gap at the
  binding corner that no cell-count work closes — see Decision 3 below.
  It would also silently redefine, after the fact, a phase boundary that
  record `0001` Decision 5 already assigned to T1 sign-off, leaving two
  ratified documents disagreeing about what "Phase 2 done" means.
- **(b) Narrow the ratified operating conditions** (record `0001` Decision
  6, −40 °C to 100 °C, 1.28–1.95 V) so the failing low-supply corners fall
  outside the matrix, making the remaining set close. **Rejected on
  principle, and named here so it is not quietly attempted later.** Every
  failing corner is a corner the PDK ships and record `0001` Decision 4
  deliberately chose not to hand-pick around; excluding them because they
  fail is precisely the "relax the ratified spec to make results pass" move
  `CLAUDE.md` forbids. The corner matrix is not renegotiated by this record.
- **(c) The nominal-corner framing stands as-is, with slow-corner closure
  remaining a T1 sign-off requirement exactly as record `0001` Decision 4
  already frames it.** **Chosen.**

**Decision:**

> `spec/modexp.md` Decision 2's 100 MHz Phase 2 target, **held at the
> nominal corner `tt_025C_1v80`** per record `0001` Decision 4, **remains
> the ratified position unchanged**. This measurement does not change what
> "Phase 2 done" means for this block: Phase 2 is cell-count and
> nominal-corner timing work on the existing Blakley core, and it is
> satisfied on the timing axis by the nominal corner closing (measured:
> WNS +3.318 ns, Fmax 149.66 MHz). Full eighteen-corner closure at 100 MHz
> stays a **T1 sign-off** requirement (record `0001` Decision 5, item 5) and
> is **not** promoted to a Phase 2 or Phase 3 boundary condition.
>
> One addition is ratified, because the sweep showed the ambiguity is real:
> **any claim in this repository that this block "closes 100 MHz" — in a
> record, in `docs/`, in an issue, or in a PR — must name the corner or
> corner set the claim holds at.** An unqualified "closes 100 MHz" is now a
> defective claim, because it is true at 9/18 ratified corners and false at
> the other 9. This constrains how results are *stated*; it does not change
> the target, the constraint, or the corner matrix.

**Consequences:** the block's T1 status is unchanged by this record — record
`0001` Decision 5 item 5 remains **not satisfied**, and this record supplies
the measured per-corner table that item 5 asks for while showing it does not
yet pass. A future T1 claim must either close all eighteen corners at
100 MHz, or carry its own decision record explaining what it claims instead.
Nothing about the present Phase 2 work is invalidated, and no re-run of the
existing synthesis, P&R, or cocotb evidence is triggered.

## Decision 2 — The measured all-corner Fmax future work is held to

**Options considered:**

- **(a) Hold future work to the nominal-corner figure (149.66 MHz) alone.**
  Rejected: that is the number the *already-passing* axis is held to, and
  quoting it as "the" Fmax is exactly the unqualified claim Decision 1
  above just declared defective.
- **(b) Hold future work to the worst measured corner, and record the full
  `ss` range alongside it.** **Chosen** — this mirrors `spec/modexp.md`
  Decision 2's own construction ("that measured result — not this target —
  becomes the number future work is held to"), applied to the axis that
  actually binds.

**Decision:**

> As of record `20260814-203901-c741877` (`rtl/modexp.v` @ `c741877`,
> `WIDTH=16`, `flow/par-modexp.json` at 10.0 ns), this block's measured
> **all-corner Fmax is 23.98 MHz**, set at the binding corner
> `ss_n40C_1v28`. Across the nine `ss` corners the measured Fmax range is
> **23.98–94.23 MHz** (worst `ss_n40C_1v28` at 23.98 MHz; mildest
> `ss_100C_1v60` at 94.23 MHz, a 0.612 ns shortfall). The corresponding
> `tt`/`ff` range is 149.66–233.57 MHz.
>
> **These are the numbers any future full-corner-closure claim is held to.**
> A claim of improvement on this axis must (i) report the worst corner's
> Fmax from a fresh eighteen-corner sweep, not the nominal corner's; (ii)
> name `ss_n40C_1v28` explicitly if that corner still binds, or name the new
> binding corner if it does not; and (iii) be produced at the same `WIDTH`
> and through the same `klt place-and-route` request shape, since a
> different `WIDTH` changes the datapath width on the binding path and makes
> the two numbers non-comparable.
>
> **Methodology caveat, ratified with the numbers:** per `flow/README.md`'s
> "Known upstream gaps", each corner in this sweep is a full independent
> place-and-route run rather than one physical build re-timed per corner —
> which is why per-corner utilization varies (37.02%–42.69%) across what is
> nominally the same design. A future comparison must reproduce the same
> methodology (or state plainly that it did not) before the two tables are
> read as measuring the same thing.

**Consequences:** `spec/modexp.md` Decision 2's revisit trigger is now
discharged — an achievable Fmax has been measured and is recorded here, at
both the nominal corner and the binding corner. Any subsequent Fmax claim in
this repository is graded against 23.98 MHz at `ss_n40C_1v28` (all corners)
and 149.66 MHz at `tt_025C_1v80` (nominal), and against nothing else. The
bad consequence is worth stating plainly: this block, as it stands, does not
run at 100 MHz across its own ratified operating conditions, and that is now
a recorded, citable fact rather than an unexamined gap.

## Decision 3 — Recommendation on the `mm_red` critical path

**The measured path** (`ss_n40C_1v28-critical-path.txt`, a supplementary
`report_checks -path_delay max` on the same routed database): a flop-to-flop
path, `_1205_/Q` → `_1172_/D`, data arrival **39.9901 ns** against a required
time of 8.2941 ns (10.0 ns period less a 1.7059 ns library setup time),
slack **−31.6961 ns**. The gate sequence is a `maj3`/`xnor2` full-adder
chain followed by a long `a21oi`/`o21ai`/`o211a`/`a311o`-class compare-and-
subtract mux chain — matching `rtl/modexp.v`'s `mm_sum = mm_p2 + mm_add` (an
18-bit add at `WIDTH=16`) feeding `mm_red`'s two serially-dependent
`(mm_sum >= mm_m2) ? … : (mm_sum >= mm_m1) ? … : …` compare-and-subtract
stages (`rtl/modexp.v` lines 68–75), all combinational within one
`S_MM_RUN` cycle.

**Options considered:**

- **(a) Accept the slow-corner Fmax as a known characteristic** of the
  single-cycle Blakley reduction this block's ratified design already
  commits to (`spec/modexp.md` Design section, Decision 5), and do nothing.
  Legitimate, and correct *if* the program never needs T1 sign-off at
  100 MHz across all corners. Not chosen as the standing recommendation,
  because record `0001` Decision 5 item 5 says the program does intend to
  reach that bar.
- **(b) Recommend RTL pipelining of `mm_red` immediately** as the next
  action. Not chosen as the *first* action: it changes the exact latency
  formula ratified in record `0001` Decision 3, so it costs a new decision
  record, a re-derivation and re-measurement of that formula, a full
  bit-exact re-verification at every verified `WIDTH`, and a new cell count
  — before any cheaper option has been tried.
- **(c) Recommend a constrained-synthesis experiment first, then RTL
  restructuring if that is insufficient.** **Chosen.**

**Decision (a recommendation, explicitly not a mandate — whoever picks up
any resulting work makes the final call):**

> The `mm_red` critical path **is** worth a named follow-up, in this order:
>
> 1. **First, and cheapest: a constrained-synthesis experiment.** The
>    synthesis feeding this run was deliberately *unconstrained* —
>    `flow/synthesize-modexp.json` sets `constraints.clock_period_ns: null`,
>    chosen so the run reproduces the 682-cell baseline byte-for-byte. The
>    18-bit adder on the binding path was therefore mapped with no timing
>    pressure at all, and a ripple-carry structure is what falls out. A
>    timing-constrained synthesis pass may select a faster adder/compare
>    structure with **no RTL change, no cycle-count change, and no change to
>    record `0001` Decision 3's latency formula** — so it requires no new
>    decision record and no re-verification of the interface contract, only
>    a fresh cell count and a fresh eighteen-corner sweep. This is the
>    recommended next experiment. It is *not* expected to close a 4.2×
>    gap on its own; its job is to establish how much of the gap is mapping
>    and how much is architecture, which nothing in this repository
>    currently knows.
> 2. **Second, if (1) is insufficient: a named Phase 3 RTL follow-up** to
>    break the single-cycle add-then-reduce chain — e.g. registering
>    `mm_sum` so the 18-bit add and the two compare-and-subtract stages
>    occupy separate cycles. The measured shortfall is structural, not a
>    placement or sizing artifact: 39.99 ns of arrival time against a 10 ns
>    period is a ~4.2× gap, and the path is one combinational chain whose
>    depth is set by the RTL, not by the floorplan. **Any such change is
>    Phase 3 scope and requires its own decision record**, because it
>    invalidates record `0001` Decision 3's ratified latency formula
>    (`cycles = WIDTH*(WIDTH + 3) + popcount(exp_in)*(WIDTH + 2) + 2`),
>    which is part of this block's ratified interface contract and cannot be
>    changed silently. It also requires a full bit-exact re-verification at
>    every verified `WIDTH` before any timing result from it counts, per
>    `CLAUDE.md`'s correctness gate.
>
> Neither step is undertaken by this record, and neither is a Phase 2 gate.
> If the program elects option (a) above instead — accepting 23.98 MHz at
> the binding corner as a characteristic of the single-cycle Blakley
> reduction — that is a legitimate outcome, but it must be recorded as its
> own decision record, because it converts the T1 item-5 gap from "open" to
> "accepted", which is a change in the block's sign-off story and not a
> silent default.

**Consequences:** the next timing-directed piece of work on this block has a
named, ordered starting point and a stated cost for each step, instead of
each future issue re-deriving the critical path from the artifacts. The
cheap step (1) risks nothing already ratified; the expensive step (2)
carries a known, enumerated price (new decision record, latency-formula
re-derivation, full bit-exact re-verification, new cell count) so it is not
started under an assumption that it is free. Nothing in this record obliges
anyone to start either one.

## Numbers in this record

Every figure above is measured, sourced from
`docs/baseline.md#full-corner-matrix-sweep` and the frozen artifacts under
`verification/records/place-and-route/artifacts/20260814-203901-c741877/`,
produced against `rtl/modexp.v` @ `c741877` at `WIDTH=16`. No figure is a
target, an estimate, or a projection, and no external standard-cell
library's published figure is referenced or compared against, consistent
with `CLAUDE.md`'s overclaim-trap section and `docs/baseline.md`.
