# 0003: LVS-closure methodology — recommend a `sky130` extraction-deck layer-coverage extension

- **Status**: ratified
- **Date**: 2026-09-15
- **Decided by**: Builder (issue #87), reading `docs/signoff-claim.md`
  (updated 2026-09-11, issue #81) — no change to `spec/modexp.md` or to
  `docs/signoff-claim.md`'s own verdict

## Context

`docs/signoff-claim.md` is this repo's single authoritative statement of
what its DRC/LVS evidence establishes, and it answers `spec/modexp.md`'s
Signoff row (*"DRC + LVS clean on the OpenROAD-produced GDS"*) as **not
met**: DRC is clean, but LVS is not, and the row requires both conjuncts.
Two independent LVS comparisons are on record, both `status: "mismatch"`,
and `docs/signoff-claim.md` classifies every mismatch on both sides as *not*
a real connectivity defect in this design — but neither comparison reaches
a clean verdict either:

1. **Issue #81's direct-comparison re-run** (`docs/signoff-claim.md`, "LVS"
   section): `klt lvs`, using issue #8's original direct DEF-vs-Verilog
   reference methodology, against the current, tapcell/PDN/filler-cell-
   bearing `layout/modexp.gds`. **17 mismatches, 100% `topology`**, each
   fully attributed by an independent instance-by-instance accounting: 5
   new physical-only cell types this issue's own `power` block adds
   (`sky130_fd_sc_hd__tapvpwrvgnd_1` and the four `__fill_{1,2,4,8}` filler
   masters, none of which can have a synthesis-side counterpart by
   construction) plus the same class of ordinary CTS/timing/antenna-fixup
   insertions and resizes documented since issue #8. Matched net/pin counts
   (333/333) unaffected.
2. **Issue #55's fresh-self-consistent-build comparison** (unaffected by
   issue #81, per `docs/signoff-claim.md`): a from-scratch
   place-and-route run's own `write_verilog` export compared against its
   own extraction — the only comparison so far to get past the
   circuit-type-level block and attempt real net/instance correspondence.
   **1324 mismatches: 888 `topology`, 434 `net.split`, 2 `net.merged`**,
   attributed to two evidenced causes: (a) `klt extract`'s default
   net-naming has no correlation to the reference's own signal names —
   `--def-net-names` (`klayout-tools#951`, already shipped and in use)
   measurably improves this (`net.merged` 48→2) but does not close it; (b)
   the `sky130` extraction deck's own documented layer-coverage limits
   (3367 dead-metal clusters, 1137 shapes on layers outside the deck's
   connectivity graph, both cited directly in the extraction's own
   `warnings[]`) cause some nets to extract as multiple disconnected
   pieces.

Both comparisons stop at **cell-instance granularity** (standard-cell black
boxes, 0 transistor-level devices on either side) — `docs/signoff-claim.md`
is explicit that this is the deepest either comparator has reached, and
that power-net (`VPWR`/`VGND`/`VPB`) correspondence is out of scope for
both. That document also names, but does not choose between, three
possible next routes: a `sky130` extraction-deck layer-coverage extension,
`klt extract`'s net-naming defaults resolved further, or a different LVS
methodology entirely — flagging "a decision-record entry tracking that as
the next input... is a natural follow-up, not undertaken here." This record
is that follow-up.

## Decision

> Of the three routes `docs/signoff-claim.md` names, this record recommends
> **Route 1: a `sky130` extraction-deck layer-coverage extension** (upstream
> `klayout-tools` work) as the next input to closing this block's LVS gap.
> This is a recommendation about which upstream direction is worth pursuing
> next — **it is not itself an implementation**: no deck, extraction-flow,
> or `klt` change is made by this record, and no value in `spec/modexp.md`
> is touched. Per `CLAUDE.md`'s friction protocol, this repo's own
> contribution to Route 1 is limited to filing the underlying gap
> generically at `2AMLogic/klayout-tools` (not yet done as of this record —
> see Consequences) and, if upstream capacity permits, contributing the fix
> there; the deck itself is not this repo's to unilaterally extend.

**Rationale, tied to this repo's own measured gap:**

- **Route 1 addresses the dominant, best-evidenced cause of the largest
  mismatch set.** Of the issue #55 comparison's 1324 mismatches, 888
  `topology` + 434 `net.split` = 1322 (99.8%) are mismatches of the *kind*
  a layer-coverage gap produces (a net that should be one node extracting
  as several disconnected pieces cascades into both a `net.split` finding
  for that net and `topology` findings for every circuit instance whose
  connectivity the split touches). `docs/signoff-claim.md` cites concrete,
  already-measured extraction-side evidence for this specific cause (3367
  dead-metal clusters, 1137 shapes outside the deck's connectivity graph) —
  this is not a hypothesis this record introduces, only the one it acts on.
- **Route 2 (net-naming) is evidenced to have a smaller ceiling on this
  repo's own data.** `--def-net-names` is already shipped and already in
  use here, and its measured effect is narrow: `net.merged` 48→2 — it
  improves exactly one of the three mismatch categories, and only by
  46 instances out of 1324. Net-naming correlation cannot, by construction,
  create or repair a net/topology correspondence that the underlying
  extraction never formed in the first place (the `net.split`/`topology`
  bulk above) — it can only help the comparator recognize a
  correctly-extracted net's identity. Going further "past
  `--def-net-names`" is real, available upstream work, but it is scoped to
  the smaller of the two evidenced causes.
- **Route 3 (a second, netgen-backed engine) does not change what is being
  compared, only how.** Per `docs/cli/lvs.md`'s `"netgen"` engine
  description, that path compares the *same* layout-side netlist this
  repo's `klt extract` already produces (or a pre-extracted SPICE supplied
  the same way) — it re-runs a different comparator over the identical
  extraction artifact, rather than re-extracting the layout with different
  layer coverage. Since both evidenced causes above are properties of *this
  repo's extraction*, not of the `NetlistComparer` engine's own comparison
  algorithm, a second engine reading the same extraction would be expected
  to encounter the same disconnected-net evidence, at the same cell-instance
  granularity `docs/signoff-claim.md` already names as this comparison's
  ceiling. Route 3's genuine value is real but different in kind: it is a
  **cross-check on the verdict**, not a fix for either evidenced cause — a
  legitimate, currently-missing piece of T1 evidence
  (`docs/signoff-claim.md`, "Second-engine cross-check (T1 item 4): not
  run"), and one this record does not recommend against pursuing
  eventually, but not the route best matched to *closing* the specific,
  evidenced gap this repo has today. It also carries a concrete adoption
  cost this repo has already hit once: `netgen` has no Homebrew formula and
  was not present on the build host used for issue #55's evidence, so
  exercising Route 3 needs a from-source build first.
- **Neither Route 1 nor any of the three routes closes the issue #81
  17-mismatch dataset.** Those 17 are structurally different in kind from
  the issue #55 1324: they are the (correct, by-construction) absence of a
  synthesis-side counterpart for a physical-only cell (tapcell/filler
  masters) plus ordinary CTS/resize churn — not a naming, extraction-layer,
  or comparator-algorithm gap. Closing that comparison's verdict is a
  reference-construction / comparison-scoping question (e.g. excluding
  physical-only masters from the compared circuit set), which is outside
  the three routes `docs/signoff-claim.md` names and outside this record's
  recommendation. This is stated here so the recommendation is not read as
  a claim that Route 1 closes *all* open LVS mismatches in this repo — it
  targets the issue #55 comparison's dominant cause specifically.

**What "LVS clean" would mean for `spec/modexp.md`'s Signoff row under this
route** (stated without editing that row): a re-run of the issue #55-style
fresh-self-consistent-build comparison, after a `klt` pin bump past a
`sky130`-deck change that adds connectivity-graph coverage for the specific
layer(s) responsible for today's 1137 ignored-layer shapes and closes (or
measurably shrinks toward zero) today's 3367 dead-metal clusters, reporting
`status: "match"` — or, short of a full `"match"`, a `status: "mismatch"`
whose every remaining finding is independently attributed to a *named,
already-tracked* residual cause (e.g. the 2 remaining `net.merged` findings
Route 2 territory would still need to close, or a re-scoped exclusion of
physical-only cells addressing the issue #81 comparison's 17). Reaching
`"match"` (or that fully-attributed residual state) on **both** of this
record's cited comparisons, at minimum, is what this record considers the
bar for the LVS half of the Signoff row's *"DRC + LVS clean"* conjunction —
consistent with `docs/signoff-claim.md`'s own framing that both conjuncts
are required and that a partial improvement is reported as such, not as
"met with caveats." This is a reading of what the ratified row already
requires, not a new requirement and not a relaxation of it; `spec/modexp.md`
Decision 3's process (a new decision record, not an edit to ratified text)
is exactly the mechanism this record uses, and no cell in `spec/modexp.md`'s
table is changed by it.

## Alternatives considered

- **Route 2 — `klt extract` net-naming defaults resolved further past
  `--def-net-names` (`klayout-tools#951`).** Real, available upstream work
  with a measured (if partial) precedent in this repo's own data
  (`net.merged` 48→2). **Not chosen as the primary recommendation**: it is
  scoped to the smaller of the two evidenced causes behind the issue #55
  comparison's 1324 mismatches (`net.merged` is 2 of 1324; the other two
  categories, 1322 of 1324, are the kind a layer-coverage gap produces, not
  a naming gap), so even a complete Route 2 fix would leave the bulk of the
  current mismatch count unaddressed on this repo's own numbers.
- **Route 3 — a different, second LVS methodology (the `netgen`-backed
  engine `docs/cli/lvs.md` documents).** Valuable as an independent
  cross-check (this repo's own T1 checklist already names it as a missing
  item), and cheaper in one sense — it needs no upstream deck change, only
  a `netgen` build. **Not chosen as the primary recommendation**: it
  compares the same already-extracted, cell-instance-granularity netlist
  this repo's `klt extract` already produces, so it would be expected to
  encounter the same two evidenced causes (extraction-side layer-coverage
  gaps and the still-imperfect net-naming) rather than resolve either one —
  it changes which comparator renders the verdict, not what the verdict is
  computed from. Recommended as a *future, additional* piece of evidence
  once Route 1 (or 2) narrows the gap, not as a substitute for closing it.
- **Route 1 — a `sky130` extraction-deck layer-coverage extension.**
  **Chosen** — see Decision and Rationale above.

## Consequences

- This record does not change `spec/modexp.md`'s Signoff row, and the row
  remains **not met**, exactly as `docs/signoff-claim.md` already states.
  No re-verification, re-synthesis, or re-layout is triggered by this
  record.
- The concrete next action Route 1 implies — filing the specific
  layer-coverage gap (the layer(s) behind this repo's 1137 ignored-layer
  shapes and 3367 dead-metal clusters) generically at
  `2AMLogic/klayout-tools`, per `CLAUDE.md`'s friction protocol — is **not**
  done by this record and is named here as the natural follow-up issue,
  distinct from and in addition to the four upstream reports
  `docs/signoff-claim.md`'s "Friction filed upstream" section already
  lists (none of which covers this specific extraction-layer-coverage gap).
  Whether this repo can drive that upstream fix itself or can only report it
  and wait is an open question this record does not resolve — either way,
  no `sky130-modexp` layout, RTL, or flow change is implied.
- Routes 2 and 3 are not foreclosed. Route 2 remains available, generic
  upstream work with a partial precedent in this repo's data; Route 3
  remains a legitimate, currently-missing T1 cross-check
  (`docs/signoff-claim.md`, "Second-engine cross-check: not run") worth
  pursuing on its own timeline, independent of this record's Route 1
  recommendation, once a `netgen` build is available. Either could still be
  the subject of its own future decision record if circumstances change
  (e.g. if `netgen` becomes readily available before any deck work lands).
- A future issue that acts on this record (e.g. by filing or contributing
  the upstream deck extension) inherits this record's stated bar for
  "LVS clean" above as the target to re-run against, rather than re-deriving
  its own definition of done.
