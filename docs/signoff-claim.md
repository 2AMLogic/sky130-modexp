# Signoff claim: DRC + LVS on the routed GDS

**This is the single authoritative statement of what this repo's DRC/LVS
evidence establishes and does not establish**, per issue #8. It answers
`spec/modexp.md`'s Signoff row — *"DRC + LVS clean on the OpenROAD-produced
GDS"* — against `layout/modexp.gds` (from #7).

## Verdict: **not met** — with a fully evidenced, bounded gap, not an
unqualified failure

Neither DRC nor LVS reports a clean result against `layout/modexp.gds`. That
is the honest reading of the spec's Signoff row today: **not met**, not
"met with caveats." What follows is why that verdict does not mean "this
layout has real defects" — every reported finding on both sides is
classified with evidence, and none of them is a real geometry or
connectivity defect in this design.

## DRC

`klt drc layout/modexp.gds --deck sky130 --format json` → `status:
"violations"`, 10 violations, all `diff.enclosing.licon.1`. Full report,
provenance, and per-violation classification: `layout/drc/README.md` and
`layout/drc/modexp-drc-report.json`.

**Classification: (iii) — a `klt drc` check-engine limitation firing on
correct-by-construction geometry**, not a real defect and not the
missing-filler-cell row-boundary artifact class this issue anticipated in
advance. Reproduces standalone on the single, unmodified
`sky130_fd_sc_hd__and3_1` cell pulled directly from the PDK's own library
GDS (no synthesis, no P&R, no neighbouring cell) — root-caused to `klt
drc`'s `"enclosing"` check building its `Region` from raw, unmerged
same-layer shapes (`kdb.Region(cell.begin_shapes_rec(...))`, no `.merge()`),
which reports a false enclosure violation where this one cell's `diff`
geometry happens to be drawn as two abutting (not one merged) rectangles.
Confirmed as the only cell (of 437) in `sky130_fd_sc_hd.gds` exhibiting this
raw-vs-merged discrepancy. Full evidence, the exact `Region` operations that
reproduce and resolve it, and the library-wide scope check:
`layout/drc/README.md`.

### Deck coverage gaps (enumerated, per this issue's acceptance criteria)

`klt drc --deck sky130` runs a **curated starter subset of 17 rules**, not
the full sky130 design rule manual (`docs/cli/drc.md`, "Coverage"), over
`poly`, `diff`, `li1`, `met1`, `licon1`, `mcon`, `met2`, and `via`
(met1↔met2 via1). Specifically, as of this evidence's `deck.content_hash`
(`sha256:cc62ce576bd65c127270fda943443493529f6e0a9f7ff85c7e9595938698e73e`):

- **Six of the seventeen rules approximate an official rule** the check
  primitives cannot express exactly: two approximate a compound-layer
  expression (a boolean union of two mask layers, e.g. `diff.or(tap)`) as a
  single-drawn-layer check; four more (`met2.width.1`, `via.width.1`,
  `met1.enclosing.via.1`, `met2.enclosing.via.1`) approximate an official
  rule that additionally bounds a max size/length or a
  periphery-scoped/corner-relaxed refinement the single/two-layer check
  primitives don't support. Every approximation is named in its rule's own
  docstring in `src/klayout_tools/decks/sky130.py`.
- **`m2.6` (minimum met2 area, 0.0676 µm²) is not transcribed at all** —
  tracked upstream as a candidate follow-on (area/density/antenna rule
  authoring was out of scope for the check-primitive work that added those
  kinds), not silently dropped.
- **`li1.enclosing.licon1.1` is the one rule whose threshold is
  deliberately not its source value** — the official rule (`li.5`) requires
  its 0.08 µm margin only on two adjacent edges of each cut, a conditional
  form the check primitives can't express; this deck instead transcribes
  `li.5`'s *unconditional floor* (0.0 µm — "`li1` must actually cover the
  `licon1` cut it lands on"), which catches the real defect class (a
  conductor missing part of its cut) with no false positives on correct
  geometry, at the cost of leaving the 0.08 µm two-adjacent-edges half
  uncovered.

None of the 10 reported violations are on `li1.enclosing.licon1.1` or any of
the six approximated rules — the one rule that fired (`diff.enclosing.licon.1`,
official rule `licon.5`) is transcribed at its real, unmodified threshold.
The DRC claim above is bounded by this coverage: a `"clean"` verdict from
this deck would still not mean "DRC-clean against the full sky130 design
rule manual," and this run is not even that clean a verdict.

## LVS

Resolved the reference-netlist question issue #8 raised: `klt extract`
gained cell-instance-level (black-box + pins) abstraction
(`--abstract-cells`, klayout-tools#620/#622) in direct response to this
issue being filed, and it works — option (b) from the issue body. A golden
reference was built from `klt synthesize`'s gate-level netlist (the exact
netlist #7's P&R run consumed) at the same cell-instance granularity.
`klt lvs` (engine `klayout`) reports `status: "mismatch"`; every one of its
15 reported mismatches is fully attributed, with an independent
instance-by-instance DEF-vs-Verilog accounting, to two ordinary P&R
optimizations (35 CTS/timing-fixup cell insertions + 5 single-instance gate
resizes) the pre-CTS reference does not model — not a connectivity defect.
Full evidence, the exact accounting, and an important caveat on what the
comparator did and did not verify: `layout/lvs/README.md`.

**Comparison level actually achieved: cell-instance granularity
(standard-cell black boxes, 0 transistor-level devices on either side), not
transistor-level.** Power-net (`VPWR`/`VGND`/`VPB`) correspondence is
explicitly out of scope for this comparison — see below. And, per
`layout/lvs/README.md`'s "Result"/"Reading this result": `NetlistComparer`
did not get far enough, once the CTS/resize-driven circuit-type mismatches
blocked top-circuit correspondence, to attempt net-by-net correspondence on
the ~680 instances common to both sides — that claim rests on the
independent instance-accounting evidence instead, not on the comparator
having verified it directly.

**Second-engine cross-check (T1 item 4): not run.** `docs/cli/lvs.md`
documents a `netgen`-backed engine alongside the default `NetlistComparer`
one. `netgen` has no Homebrew formula and was not present on this build
host; a from-source build was not attempted within this issue's scope. This
LVS leg is therefore **one toolchain's own verdict**, not yet
cross-checked by a second, independent engine.

## What this GDS has not been through (missing flow stages)

Per `layout/README.md`'s "What this GDS does *not* contain" (unchanged by
this issue, restated here since it is directly load-bearing for both
verdicts above): **no tapcell insertion, no power-grid (PDN) generation, no
metal fill, no filler-cell insertion, and no `DONT_USE_CELLS` exclusion** —
core-only floorplanning, no IO ring. Concretely, for this design: placement
rows are sparse (e.g. one checked row is 148.22 µm wide and holds only ~20
cell instances with large unfilled gaps between them — see
`layout/lvs/README.md`), so row-level power-rail continuity between
non-adjacent placements is not guaranteed, and there is no PDN to bridge
that gap even where it exists. This is the direct, concrete reason the LVS
comparison above excludes power-net correspondence from its scope rather
than reporting an unexplained mismatch, and it is a real, prior, already-
recorded gap (`layout/README.md`, from #7) rather than a new finding.

## Reading the spec's Signoff row

`spec/modexp.md`'s Signoff row — *"DRC + LVS clean on the OpenROAD-produced
GDS"* — is **not met** by `layout/modexp.gds`. This is stated plainly, not
qualified away: neither check reports a clean verdict. What this issue's
evidence *does* establish, precisely bounded:

- Every DRC violation and every LVS mismatch is individually classified with
  supporting evidence, not asserted — none is a real geometry or
  connectivity defect in this design.
- The DRC deck's coverage gaps are enumerated above and none of the six
  approximated rules, the untranscribed `m2.6`, or the
  `li1.enclosing.licon1.1` threshold exception are implicated in the one
  rule that actually fired.
- The LVS reference-netlist question has a working answer (cell-instance
  granularity), demonstrated end-to-end against this design — the first
  time this toolchain's digital LVS path has been exercised this way.
- Both verdicts trace directly back to this GDS's already-documented,
  pre-existing missing flow stages (no filler cells, no PDN, no CTS-aware
  reference path) — not to new defects this issue discovered.

Per this issue's own acceptance criteria, `spec/modexp.md` is **not**
relaxed to accommodate this shortfall. The Signoff row staying unmet with a
documented, evidence-backed reason is the correct outcome of this issue, not
a failure of it — this is exactly the seam `README.md` names as the point
of this repo: *"the seam where digital output re-enters the layout tools."*
Closing it for real needs, at minimum, a `klt place-and-route` filler-cell/
PDN/post-CTS-netlist-export capability this toolchain does not have yet
(see "Friction filed upstream" below) — a decision-record entry tracking
that as the next input to Decision-record-worthy spec discussion is a
natural follow-up to this issue, not undertaken here.

## Friction filed upstream

Two tool/flow gaps found while producing this evidence, filed generically
(no design-specific detail beyond PDK standard-cell names) at
`2AMLogic/klayout-tools`, per `CLAUDE.md`'s friction protocol:

1. **`klt drc`'s `"enclosing"`/`"enclosed"` checks can false-positive on
   same-layer geometry drawn as multiple abutting (touching, unmerged)
   shapes**, since the checked `Region` is built directly from raw shapes
   with no `.merge()` call. Reproduced on an unmodified `sky130_fd_sc_hd`
   library cell. See `layout/drc/README.md` for the full reproduction.
   Filed as [klayout-tools#995](https://github.com/2AMLogic/klayout-tools/issues/995).
2. **`klt place-and-route` has no post-CTS/post-optimization netlist
   export** (no `write_verilog`-equivalent stage), so a gate-level LVS
   golden reference built from `klt synthesize`'s own output necessarily
   diverges from the routed layout by exactly the P&R tool's own
   timing-driven clock-tree insertions and gate resizes — with no way to
   build a truer reference without hand-deriving it from the routed DEF, as
   this issue's evidence does. See `layout/lvs/README.md` for the full
   accounting. Filed as
   [klayout-tools#996](https://github.com/2AMLogic/klayout-tools/issues/996).

## Post-route gate-level simulation (appended, issue #9)

Issue #9 re-ran the committed bit-exact suite against a gate-level netlist of
this same GDS, using the very extraction artifact this page's LVS section
describes (`layout/lvs/modexp_layout_abstracted.spice`). That is a separate
claim from the DRC/LVS verdict above and does not change it, but it is worth
recording here because it uses the same layout and inherits the same scope
caveats:

- **What it establishes**: the 718-instance netlist implied by this routed
  layout — including all 35 CTS/timing-fixup insertions and all 5 resizes
  that the LVS section above attributes — is functionally bit-exact against
  `pow(base, exp, mod)`, and returns byte-identical results to the RTL on the
  same 500 pinned vectors. That is a positive, simulation-based answer to
  part of what the LVS run could not itself confirm (the LVS comparator
  stopped short of net-by-net correspondence, per "Reading this result" in
  `layout/lvs/README.md`).
- **What it does NOT model**, carried forward verbatim from this page's LVS
  scope plus what is specific to simulation: **no parasitic extraction** (no
  R/C, no SPEF — `klt extract` was run without `--parasitics`), **no
  timing and no corner** (zero-delay logic; sky130A ships 18 liberty corners
  but one corner-independent Verilog cell-model set), **no power/ground
  network** (power pins dropped — this GDS has no PDN), and **cell-instance
  granularity, not transistor level**.
- **Not achieved**: delay-annotated (SDF) simulation at the ratified corner
  set. `klt place-and-route` has no SDF export and `klt
  functional-verification` has no SDF option — filed as
  [klayout-tools#1002](https://github.com/2AMLogic/klayout-tools/issues/1002),
  with a simulator-version precondition filed as
  [#1004](https://github.com/2AMLogic/klayout-tools/issues/1004).

Full method and scope: `verification/gate-level/README.md`. Record:
`verification/records/gate-level-sim/`.

## Evidence record

`verification/records/drc-lvs/records/<record-id>.md` (append-only
convention, `verification/README.md`), carrying the DRC deck's
`content_hash`, the LVS extraction deck's `content_hash`, and
`layout/modexp.gds`'s own `content_hash` so staleness is detectable if
either the deck or the layout changes.
