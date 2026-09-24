# 0005: DR-0004 Decision 2's priced exit was run; its reproducibility blocker is gone and its 18/18 is not

- **Status**: ratified
- **Date**: 2026-09-24
- **Decided by**: Builder (issue #141), discharging
  `spec/decision-records/0004-slow-corner-closure-is-cell-selection-bound-and-the-disclosed-t1-item-5-exception.md`
  Decision 2's named exit

## Context

Record `0004` Decision 1 carried T1 item 5 as a **disclosed FAIL with its
number** — the committed `layout/modexp.def` closes 100 MHz at **10 of 18**
ratified corners, binding corner `ss_n40C_1v28` at **22.80 MHz** — and
Decision 2 named, priced, and deliberately did **not** start the way out of
it: candidate **row 6** of that record's lever matrix, which measured
**18 of 18** corners closed at **+0.489 ns / 105.14 MHz**.

Decision 2 named exactly one blocking dependency: `klt synthesize` had no
request-level standard-cell exclusion, so row 6's 209-cell exclusion could
only be produced by bypassing `klt` and invoking Yosys directly — and this
repository does not land a timing claim it cannot re-run from a committed
request.

**That dependency has landed.**
[klayout-tools#2382](https://github.com/2AMLogic/klayout-tools/issues/2382)
was closed by
[klayout-tools#2429](https://github.com/2AMLogic/klayout-tools/pull/2429)
("feat(synthesize): request-level standard-cell exclusion
(`constraints.dont_use`)", merge commit `9cabec7b`). Issue #141 ran the exit.

**Provenance of every number below**: measured by issue #141 and frozen as
`verification/records/sta-corner-sweep/records/20260924-134500-1a8313b.md`
and its artifacts. Nothing here is a target, an estimate, or a projection,
and no external standard-cell library's published figure is referenced or
compared against, per `CLAUDE.md`'s overclaim-trap section.

## What the re-spin measured

One change from row 6, and only one: the exclusion is now a **committed
`klt synthesize` request field**. Everything else — the frozen bit-serial
RTL, `constraints.clock_period_ns: 10.0` at `ss_n40C_1v28`,
`flow/par-modexp.json`'s floorplan with only `pdk.corner` moved, the
eighteen ratified corners — is row 6 verbatim.

| | row 6 (frozen, 2026-09-23) | this re-spin (2026-09-24) |
| --- | --- | --- |
| mapped instances | 1204 | **1105** |
| `klt sta` @ `ss_n40C_1v28`, `spef` omitted | +0.48871 ns / 105.138 MHz | **−0.57431 ns / 94.5688 MHz** |
| in-flow P&R STA @ same corner | −1.10506 ns / 90.0491 MHz | **−1.16023 ns / 89.6039 MHz** |
| corners closed | **18 / 18** | **17 / 18** |
| hold | clean, all 18 | clean, all 18 |

Three findings, each measured:

1. **The reproducibility blocker is genuinely gone.** `klt synthesize`
   driven by the committed request produces a netlist **byte-identical**
   (`sha256:f33ededc…`) to the one row 6's frozen hand-rolled Yosys script
   produces when run directly on the same host. The generated `abc` line is
   flag-for-flag identical, in the same order — the built-in
   `sky130_fd_sc_hd` table's two globs first (under the default
   `dont_use_mode: "additive"`), then the 209 request-supplied names.
2. **Row 6's netlist is not reproducible across hosts — by any route.**
   Both the committed request *and* row 6's own frozen script produce
   **1105** instances here, not 1204, identically under Yosys 0.67 and
   0.68. So this is neither a request-vs-script difference nor a Yosys
   *version* effect; what remains is the **ABC build embedded in the Yosys
   binary**. Mapping stability across builds is not something this
   repository had ever measured, and row 6's headline number turns out to
   depend on it.
3. **The two STA methodologies now agree, against closure.** Decision 2's
   fourth bill item required resolving a 1.59 ns disagreement between
   `klt sta` (+0.489 ns) and the in-flow routing-estimated STA
   (−1.105 ns). On the re-spun database the gap is 0.59 ns and **both
   methods report a negative slack** at the binding corner. The in-flow
   number reproduced to within 0.06 ns of row 6's; it was the optimistic
   `klt sta` number that moved.

The correctness gate is unaffected and was re-run on the same RTL:
`verification/cross_check.py` → **2000/2000 match, 0 mismatches** at
`WIDTH` = 4, 6, 8, 16; `klt functional-verification` → **3/3**, including
the candidate's directed latency-formula check.

## Decision 1 — Row 6's 18/18 is withdrawn as a reachability claim; the 17/18 re-spin is recorded, not landed

**Options considered:**

- **(a) Land the re-spun configuration anyway** — commit the bit-serial
  RTL, the `constraints.dont_use` synthesis request, the `ss_n40C_1v28`
  P&R request and the resulting layout, and report 17/18 at 94.57 MHz.
  **Rejected.** The entire price record `0004` Decision 2 enumerated —
  **+423 cells** (682 → 1105), **≈33x** the cycle count at `WIDTH=16`
  (19539 against 595 for an all-ones exponent), a **net throughput loss of
  roughly 8x** against the 4.15x clock gain, a superseded ratified latency
  formula, and a full re-mint of every layout-derived evidence leg — was
  priced **against closure**. Closure is exactly what did not arrive. Paying
  an 8x throughput loss to move a disclosed FAIL from 10/18 to 17/18, while
  still failing at the same binding corner, is a materially different trade
  from the one Decision 2 priced, and it is not the Builder's to make
  silently inside the issue that assumed the other outcome.
- **(b) Discard the run as a negative result.** **Rejected.** It is the
  most informative measurement this block has produced about its own
  reproducibility, and record `0004`'s own framing — that the cost of
  record `0002`'s deferral was nobody being able to see what a lever would
  cost or buy — applies with full force here.
- **(c) Withdraw the 18/18 reachability claim, record the re-spin in full
  as a sibling evidence record, and re-price the exit against what was
  actually measured — without landing the layout.** **Chosen.**

**Decision:**

> **Record `0004`'s row 6 no longer stands as a demonstration that 100 MHz
> is reachable at all eighteen ratified corners.** Its 18/18 was measured
> on a netlist that this repository cannot reproduce — not from the newly
> committed request, and not from row 6's own frozen script — on a host
> whose Yosys/ABC build differs. Anything citing record `0004` Decision 1's
> "live, measured demonstration that 100 MHz is *reachable*" must now cite
> this record alongside it and state the reproduction result: **17 of 18,
> −0.574 ns / 94.57 MHz at `ss_n40C_1v28`**.
>
> **`layout/modexp.def`, `layout/modexp.gds`, `rtl/modexp.v`,
> `flow/synthesize-modexp.json` and `flow/par-modexp.json` are unchanged by
> this record.** Record `0004` Decision 1's exception stands verbatim,
> against the same layout and the same number: T1 item 5 is a disclosed
> **FAIL**, 10 of 18, `ss_n40C_1v28` at **22.80 MHz**, hold clean
> everywhere. `verification/signoff/block-manifest.json` continues to cite
> record `20260923-093000-28a7c96`; no T1 row changes state as a result of
> this record, in either direction.
>
> **What must still not happen** (restating record `0004` Decision 1(b),
> which this record does not weaken): the 100 MHz target is **not**
> lowered and the eighteen-corner matrix of record `0001` Decision 4 is
> **not** narrowed. 94.57 MHz at seventeen of eighteen corners is a
> measurement, not a new target, and nothing in this repository may quote
> it as one.

**Consequences:** the block's shipped evidence state is exactly what it was
before this work, which is the point — nothing regressed, and nothing was
claimed that a re-run cannot produce. The cost, stated plainly: the program
no longer has a demonstrated all-corner 100 MHz configuration for this
block. It has a *near*-miss it can reproduce (17/18, 94.57 MHz) and a
former 18/18 it cannot.

## Decision 2 — Record `0001` Decision 3's latency formula is NOT superseded

**Options considered:**

- **(a) Supersede it now**, as record `0004` Decision 2 anticipated, with
  the bit-serial core's re-derived
  `(WIDTH + popcount(exp)) * (WIDTH*(2*WIDTH+6) + 2) + WIDTH + 3`.
  **Rejected.** Record `0001` Decision 3's formula is a statement about the
  interface contract of **the RTL this repository ships**, and Decision 1
  above does not ship the bit-serial core. Superseding the ratified latency
  of a module whose source is unchanged would make the spec describe a
  design that does not exist — precisely the failure record `0001` was
  created to fix.
- **(b) Leave the ratified formula in force and record the re-derived one
  as measured, unratified, candidate-scoped detail.** **Chosen.**

**Decision:**

> `spec/decision-records/0001-input-domain-interface-and-corner-matrix.md`
> Decision 3's latency contract —
> `cycles(WIDTH, exp_in) = WIDTH*(WIDTH + 3) + popcount(exp_in)*(WIDTH + 2) + 2`
> — **remains ratified and unamended**, because `rtl/modexp.v` is unchanged.
>
> The bit-serial candidate's latency is
> `(WIDTH + popcount(exp)) * (WIDTH*(2*WIDTH+6) + 2) + WIDTH + 3` cycles
> (inclusive counting convention: both the `start` sampling edge and the
> `done` edge count, which reads one higher than record `0001` Decision 3's
> exclusive convention applied to the same core). It is **measured, not
> ratified**: verified at every tested `popcount(exp)` from 0 to `WIDTH` by
> the candidate patch's directed `test_modexp_latency_formula`, frozen with
> the candidate under
> `verification/records/sta-corner-sweep/artifacts/20260923-093000-28a7c96/candidates/`.
> **Whichever PR eventually lands the bit-serial core owns the decision
> record that supersedes record `0001` Decision 3** — this record
> deliberately does not spend that supersession in advance.
>
> Record `0001` Decision 3's side-channel note carries over unchanged and
> is *worse* for the candidate, not better: an observer counting cycles to
> `done` still learns `popcount(exp_in)`, and the per-multiply cost is now
> `WIDTH*(2*WIDTH+6) + 2` cycles rather than `WIDTH + 2`, so the leak is
> larger in absolute terms.

**Consequences:** the ratified interface contract continues to describe the
shipped RTL exactly. The cost: the re-derived formula lives in an evidence
record rather than in the spec until the core lands, so a reader of
`spec/` alone will not find it.

## Decision 3 — The exit is re-priced, and the mapping-stability gap is named

**Options considered:**

- **(a) Re-assert record `0004` Decision 2's bill unchanged.** Rejected: two
  of its four line items have now moved, and re-asserting a stale price is
  how record `0002`'s step 1 sat untried for five weeks.
- **(b) Re-price it against what was measured, and name the newly-visible
  obstacle.** **Chosen.**

**Decision:**

> Record `0004` Decision 2's exit is **re-priced**, item by item:
>
> | Decision 2 bill item | Status after this re-spin |
> | --- | --- |
> | Blocking dependency: request-level cell exclusion | **Discharged.** `constraints.dont_use` landed (klayout-tools#2429); the committed request reproduces the frozen script's netlist byte for byte. |
> | New decision record superseding record `0001` Decision 3 | **Deferred, deliberately** — see Decision 2 above. Still owed by whichever PR lands the bit-serial core. |
> | +522 cells / ≈33x cycles, reported alongside any Fmax claim | **Re-measured: +423 cells** (682 → 1105, not 1204) and ≈33x cycles; net throughput loss ≈**8x** against a 4.15x clock gain. Still a closure result, never a throughput result. |
> | Full re-mint of T1 items 3, 4, 7, 11 | **Partly de-risked.** `klt drc --deck sky130` against the re-spun GDS is **clean, 0 violations**, so item 3 (currently met) is on this evidence re-mintable without regression. Items 4, 7 and 11 remain unrun against it. |
> | Resolve the two-methodology disagreement | **Resolved, against closure.** `klt sta` −0.574 ns and in-flow −1.160 ns now agree at the binding corner. |
>
> **And one new item, which record `0004` could not have known:**
>
> > **Mapping stability across Yosys/ABC builds is unmeasured, and this
> > block's slow-corner closure is sensitive to it.** A 99-instance (8.2%)
> > mapping difference between two hosts running the same script at the
> > same nominal Yosys version moved the binding corner's `klt sta` slack
> > by **1.06 ns** — across the closure threshold. Until a Yosys/ABC build
> > is pinned the way `docs/environment.md` already pins `klt` and the PDK,
> > no cell-exclusion-dependent timing claim from this block is
> > host-portable, and `docs/environment.md`'s "Resolved version on the
> > environment these records were produced on" table is not a pin.
>
> **This sequence remains a recommendation, not a mandate**, exactly as
> record `0004` Decision 2 framed its own. What is ratified here is the
> corrected *pricing* and the newly-named obstacle.

**Consequences:** whoever next picks up slow-corner closure starts from a
reproducible 17/18 rather than an unreproducible 18/18, knows that the
remaining ~0.57 ns is inside the noise band of a toolchain the repository
does not pin, and knows that pinning it is now on the critical path rather
than being housekeeping. The bad consequence, stated plainly: the gap to
Decision 1's exception closing is no longer "run the priced exit" — it is
"run the priced exit **and** find another ~0.57 ns **and** pin the mapper",
and nothing in this repository currently knows where that 0.57 ns comes
from.

## Friction filed

Per `CLAUDE.md`'s friction protocol, the gap this run surfaced is described
generically (the tool gap, not this design) and filed at
`2AMLogic/klayout-tools`: a synthesis flow whose mapped netlist is not
reproducible across two installs of the same nominal engine version has no
way, through `klt`, to *detect* that — the response's `engine_version` is
`"0.68"` on both hosts, and there is no build-identity or
mapped-netlist-digest field a caller can compare. See the issue linked from
`verification/records/sta-corner-sweep/records/20260924-134500-1a8313b.md`.

`constraints.dont_use` itself is reported working exactly as documented,
including the additive merge order and the
"pattern matching zero cells is an error" validation
(`cell_exclusions.validated: true`, 209 requested, 211 effective).

## Numbers in this record

Every figure above is measured, at `klt 0.6.0+gc66f18fd6225`
(`c66f18fd`, 11 commits ahead of klayout-tools#2429's merge commit
`9cabec7b`), OpenROAD `26Q3-1510-g6cb3f2b704`, YoWASP Yosys `0.67` and
`0.68`, Icarus `12.0`, sky130A `open_pdks c6d73a35`. Frozen at
`verification/records/sta-corner-sweep/records/20260924-134500-1a8313b.md`
and its artifacts. No figure here is a target, an estimate, or a
projection, and no external standard-cell library's published figure is
referenced or compared against, consistent with `CLAUDE.md`'s
overclaim-trap section and `docs/baseline.md`.
