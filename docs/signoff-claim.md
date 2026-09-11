# Signoff claim: DRC + LVS on the routed GDS

**This is the single authoritative statement of what this repo's DRC/LVS
evidence establishes and does not establish**, per issue #8 (and re-verified
by issue #55). It answers `spec/modexp.md`'s Signoff row — *"DRC + LVS clean
on the OpenROAD-produced GDS"* — against `layout/modexp.gds` (from #7).

## Verdict (updated 2026-09-11, issue #81): **not met** — DRC is now clean;
LVS still mismatches

**DRC is now clean, 0 violations** (issue #81): `flow/par-modexp.json`
gained a `power` block driving `klt place-and-route`'s tapcell + PDN +
filler-cell insertion (`request.power`, added upstream by
[klayout-tools#1120](https://github.com/2AMLogic/klayout-tools/pull/1120)),
and the regenerated `layout/modexp.gds`/`layout/modexp.def` close all 234
`nwell.space.1`/`nwell.width.1` violations issue #79 had classified
(121 `nwell.space.1` + all 40 `nwell.width.1`, the documented-gap class —
closed for real, as intended — **and**, incidentally, the 73 check-engine-
limitation violations too, since continuous filler-cell nwell coverage
removes the same-polygon concave notches that class depended on;
[klayout-tools#1654](https://github.com/2AMLogic/klayout-tools/issues/1654)
itself is untouched and remains open upstream on its own merits). See "DRC"
below for the full record.

**DRC's history, for context**: DRC was clean at the issue #55 pin, but
issue #78's later pin bump (taken for an unrelated reason — gate-level-sim
Leg 2's SDF fix) surfaced those same 234 violations against the
then-unmodified `layout/modexp.gds`, because the DRC deck itself grew
coverage between the two pins (`klayout-tools#1433`, merged 2026-08-26,
added `nwell.space.1`/`nwell.width.1` for the first time) — not a design
regression, a previously-invisible, never-actually-checked gap. Issue #79
individually classified all 234; issue #81 closed them by finally adding
the filler-cell/tapcell/PDN insertion issue #79's own classification named
as the real fix.

**LVS still reports `status: "mismatch"`** — re-run against the new,
tapcell/PDN/filler-cell-bearing GDS (issue #81): mismatch count grew from
15 to 17, still 100% `topology`, fully attributed to 5 new physical-only
cell types this issue's own `power` block adds (no synthesis-side
counterpart can exist for a tapcell/filler master, by construction) plus
ordinary CTS/timing/antenna-fixup churn — not a new mismatch category. See
"LVS" below. `spec/modexp.md`'s Signoff row (*"DRC + LVS clean"*, both
conjuncts required) remains **not met** overall — stated plainly, not "met
with caveats," and not relaxed: DRC is now clean, but LVS closure remains a
separate, unstarted effort (this repo's LVS methodology needs either a
`sky130` extraction-deck layer-coverage extension, `klt extract`'s
net-naming defaults resolved, or a different LVS methodology entirely — see
"LVS" below, unchanged by this update). What follows is why neither the
(now-zero) DRC violations nor the LVS mismatches indicate a defect *beyond*
what is documented below; every reported finding is classified with
evidence, not asserted.

## DRC — **CLEAN: 0 violations** (was: 234, individually classified, issue
#79; before that, clean at the issue #55 pin; before that, 10 violations)

`klt drc layout/modexp.gds --deck sky130 --format json` → **`status:
"clean"`, `violation_count: 0`**, against the regenerated
`layout/modexp.gds` (issue #81 — `flow/par-modexp.json`'s new `power`
block adds tapcell + PDN + filler-cell insertion; content hash changed from
every prior run). Full report and provenance:
`verification/records/drc-lvs/records/20260911-053500-d5e43d3.md` (and its
twin, `20260911-053520-d5e43d3.md`), superseding
`20260911-012604-6e5ac66`/`20260911-012620-6e5ac66`.

**This closes the 161 documented-gap violations (121 `nwell.space.1` + 40
`nwell.width.1`) issue #81 targeted, and the 73 check-engine-limitation
violations as an incidental consequence — not a claim that
[klayout-tools#1654](https://github.com/2AMLogic/klayout-tools/issues/1654)
itself was fixed** (it was not touched and remains open upstream; a
different design, or a future change to this one, could still trigger the
same `Region.space_check` approximation gap on a different same-polygon
notch).

### History: the 234-violation classified state (issue #79, superseded)

`klt drc layout/modexp.gds --deck sky130 --format json` previously reported
**`status: "violations"`, `violation_count: 234`** (`nwell.space.1`: 194,
`nwell.width.1`: 40), against the pre-#81 `layout/modexp.gds` (identical
content hash to every run since issue #7, before issue #81 regenerated it).
Full report, provenance, and the per-violation classification:
`verification/records/drc-lvs/records/20260911-012604-6e5ac66.md` (and its
twin, `20260911-012620-6e5ac66.md`), superseding
`20260909-230959-92e00f2`/`20260909-231045-92e00f2` — retained below as
history.

**What changed, issue #78 (2026-09-09)**: the DRC deck's own
`content_hash` changed between this repo's two most recent `klt` pins
(`sha256:2e78949d...` → `sha256:5afac7ab...`), because
[klayout-tools#1433](https://github.com/2AMLogic/klayout-tools/pull/1433)
("feat(decks): add sky130 nwell.width.1/nwell.space.1 DRC rules", merged
2026-08-26) added these two rules to the deck's curated subset between the
two pins. `layout/drc/README.md` already documented the deck as a "curated
starter subset of 17 rules, not the full sky130 design rule manual" — these
two rules were simply not among that subset before. This design's
`nwell.space.1`/`nwell.width.1` compliance was **never actually checked**
prior to this pin bump; there is no design or GDS change to explain, and no
false-positive check-engine defect to file upstream (unlike the prior two
findings below) — the new coverage is legitimate upstream feature growth,
and it revealed a genuine, previously-invisible gap in this design's own
signoff status.

**Classification (issue #79, 2026-09-11)**: all 234 violations were
individually classified by cross-referencing each violation's geometry
against the merged `nwell.drawing` region (the same region `klt drc`
itself checks) and `layout/modexp.def`'s cell-instance placement. Full
method, counts, and per-violation detail:
`verification/records/drc-lvs/records/20260911-012604-6e5ac66.md` and
`verification/records/drc-lvs/artifacts/20260911-012604-6e5ac66/classification.json`.

- **73 of 194 `nwell.space.1` violations — (iii) check-engine limitation.**
  Each touches exactly one merged `nwell.drawing` polygon (a large,
  non-box, many-vertex outline) — a concave notch within a single physical
  well, not a gap between two distinct wells. `nwell.space.1` is
  transcribed as `check="space"` (`Region.space_check`), which — unlike the
  source `sky130.lydrc` rule `nwell.2a`'s `isolated` semantics — also flags
  same-polygon notches, exactly as the rule's own docstring in
  `src/klayout_tools/decks/sky130.py` warns is possible ("no corpus
  regression found... but that doesn't rule out a false positive specific
  to this design's own nwell geometry"). Filed upstream, generic, no
  design-specific detail:
  [klayout-tools#1654](https://github.com/2AMLogic/klayout-tools/issues/1654).
- **121 of 194 `nwell.space.1` violations — (ii) accepted/documented gap.**
  Each touches two or more *distinct* merged `nwell.drawing` polygons,
  confirmed (via `layout/modexp.def` placement) to belong to two different,
  non-abutting standard-cell instances. This traces directly to
  `layout/README.md`'s already-documented "no filler-cell insertion" gap:
  without filler cells bridging sparsely-placed instances, two separate
  PMOS wells can end up closer than the 1.27 µm `nwell.2a` threshold with
  no filler-cell nwell material between them.
- **40 of 40 `nwell.width.1` violations — (ii) accepted/documented gap.**
  Every one touches exactly one merged, non-box, many-vertex polygon at a
  locally narrow "waist" formed where two or more misaligned adjacent
  standard-cell instances' `nwell` rectangles partially overlap or
  corner-touch. Not a library-cell defect (every one of the 718
  individual, per-instance, unmerged `nwell.drawing` rectangles measures
  >= 1.76 µm x 1.605 µm, well above the 0.84 µm threshold) and not a
  check-engine limitation (`nwell.width.1`'s docstring carries no
  approximation caveat) — the narrow waist is purely a merge artifact of
  the same missing-filler-cell gap as above, on the width failure mode
  rather than spacing.

**No violation was classified (i) — a newly-discovered real design defect
requiring an unplanned layout/floorplan change.** Closing the 161
documented-gap violations for real needed filler-cell (and ultimately
tapcell/PDN) insertion in the place-and-route flow — a new flow capability,
out of issue #79's scope per its own "Out of scope" section, tracked as
[sky130-modexp#81](https://github.com/2AMLogic/sky130-modexp/issues/81) —
**issue #81 has since landed this and closed all 234** (see "DRC" above);
this subsection is retained as history of the classification that made
that closure possible, not a current claim. The 73 check-engine-limitation
violations' upstream fix
([klayout-tools#1654](https://github.com/2AMLogic/klayout-tools/issues/1654))
was never landed — those 234-era violations stopped recurring only because
issue #81's filler-cell insertion happens to remove the specific
same-polygon geometry pattern this design had; #1654 itself remains open.

**History (issue #55)**: the prior 10 violations (all `diff.enclosing.licon.1`, all
on `sky130_fd_sc_hd__and3_1` instances) were classified as **(iii) — a `klt
drc` check-engine limitation firing on correct-by-construction geometry**:
`klt drc`'s `"enclosing"` check built its `Region` from raw, unmerged
same-layer shapes (`kdb.Region(cell.begin_shapes_rec(...))`, no `.merge()`),
producing a false enclosure violation where this one library cell's `diff`
geometry happens to be drawn as two abutting (not merged) rectangles — filed
as [klayout-tools#995](https://github.com/2AMLogic/klayout-tools/issues/995).
That issue is now closed upstream, fixed by
[klayout-tools#998](https://github.com/2AMLogic/klayout-tools/pull/998) ("fix(drc):
merge checked regions before running check primitives", merged 2026-08-15) —
exactly the missing `.merge()` call. Issue #55 bumped this repo's `klt` pin
past that fix and re-ran DRC against the identical GDS: the 10 violations do
not recur, and no new violation appeared. Full before/after evidence:
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

**Update (issue #78, 2026-09-09)**: this enumeration describes the deck as
it stood at issue #8's original pin. The deck has since grown — most
recently, `klayout-tools#1433` added `nwell.width.1`/`nwell.space.1` (see
"DRC" above, whose 234 violations are on exactly these two new rules) —
so both the rule count and the coverage gaps enumerated above are now
stale as a complete list; they remain accurate as a description of what
they cover, not as an exhaustive current inventory. Re-enumerating the
deck's full current rule set is not attempted here (out of this issue's
scope); `klt deck info --format json` reports the installed build's own
current coverage directly.

## LVS — still `status: "mismatch"` against the regenerated,
tapcell/PDN/filler-cell GDS (updated 2026-09-11, issue #81)

Issue #81 regenerated `layout/modexp.gds`/`layout/modexp.def` (added
`request.power`: tapcell + PDN + filler-cell insertion) to close the DRC
violations above; this re-runs issue #8's original direct-comparison LVS
methodology (below) against the new GDS to confirm it does not silently
regress. **Result: still `status: "mismatch"`, 17 mismatches (was 15),
100% `topology`, fully attributed** — 15 `side: "layout"` unmatched
circuit types (6 CTS/timing-fixup-only + 1 antenna-fixup + 3 post-resize +
**5 new physical-only types this issue's own `power` block adds**:
`sky130_fd_sc_hd__tapvpwrvgnd_1` and the four `__fill_{1,2,4,8}` filler
masters, none of which can have a synthesis-side counterpart by
construction), 1 `side: "reference"` unmatched type (same pre-resize
`o22ai_1` as before), 1 `side: "both"` (top circuit, cascading). No new
mismatch category (still 0 `net.split`/`net.merged`/`device.*`), matched
net/pin counts (333/333) unchanged. Direct instance-by-instance
DEF-vs-Verilog accounting confirms the 718 logic-bearing instances
(excluding 2356 new `TAP_*`/`FILLER_*`/`ANTENNA_*` physical-only
instances) are otherwise unchanged in kind from the pre-#81 comparison: 680
identical name+type, 3 resized, 35 new CTS/timing/antenna-fixup insertions,
0 missing. Full detail, and a confirmed (not assumed) scoping finding about
`write_verilog -remove_cells` not applying to this repo's GDS-direct
extraction methodology:
`verification/records/drc-lvs/records/20260911-053500-d5e43d3.md` (and its
twin, `20260911-053520-d5e43d3.md`), `layout/lvs/README.md`.

**This re-run does not touch or supersede** the separate "fresh
self-consistent build" comparison issue #55 introduced below (1324
mismatches) — that comparison already builds its own reference from an
independent rebuild rather than from the committed `layout/modexp.gds`, for
reasons unrelated to this issue, and remains current, unaffected evidence
in its own right.

## LVS history: a true as-built reference, a different, deeper-diagnosed
cause (issue #55, 2026-08-16)

Resolved the reference-netlist question issue #8 raised: `klt extract`
gained cell-instance-level (black-box + pins) abstraction
(`--abstract-cells`, klayout-tools#620/#622) in direct response to this
issue being filed, and it works — option (b) from the issue body.

**Issue #8's original comparison** used a golden reference built from `klt
synthesize`'s pre-CTS gate-level netlist. `klt lvs` reported `status:
"mismatch"`, 15 mismatches, every one fully attributed (independent
instance-by-instance DEF-vs-Verilog accounting) to two ordinary P&R
optimizations the pre-CTS reference could not model (35 CTS/timing-fixup
cell insertions + 5 resizes) — not a connectivity defect, but also not a
comparison that got far enough to attempt real net/instance correspondence
(`NetlistComparer` stopped at the circuit-type level).

**Issue #55 closed that gap**: `klayout-tools#997` (merged 2026-08-15) added
`klt place-and-route`'s `write_verilog` as-built export, and this repo's
`klt` pin was bumped past it. Re-running `klt place-and-route` against the
identical, frozen synthesis netlist/floorplan/seed with the bumped `klt`
does **not**, however, reproduce `layout/modexp.gds` byte-for-byte (722 vs
718 instances, materially different timing/wirelength — a real,
independently useful finding, evidenced in full in the record below) — so
the true as-built reference this record builds is compared against a
**fresh, self-consistent build's own extraction**, not against
`layout/modexp.gds` itself (deliberately left unchanged).

With that as-built reference, `klt lvs` (engine `klayout`) gets **past** the
circuit-type-level block for the first time — every cell type has a
same-named counterpart on both sides — and attempts real net/instance
correspondence. Result: still `status: "mismatch"` (1324 mismatches: 888
`topology`, 434 `net.split`, 2 `net.merged`), now attributed to two
different, evidenced causes, **neither of which is CTS/resize** (that
half of the prior gap is fully resolved): (1) `klt extract`'s default
net-naming has no correlation to the reference's own signal names —
`--def-net-names` (`klayout-tools#951`) measurably improves this
(`net.merged` 48→2) but does not close it; (2) the `sky130` extraction
deck's own documented layer-coverage limits (3367 dead-metal clusters, 1137
shapes on layers outside the deck's connectivity graph, both cited directly
in the extraction's own `warnings[]`) cause some nets to extract as multiple
disconnected pieces. Full evidence, the fresh comparison, and the
byte-identical-behavior check on `build_reference_netlist.py`'s generalized
parser: `layout/lvs/README.md` and
`verification/records/drc-lvs/records/20260816-174310-5e656e5.md`.

**Comparison level actually achieved: cell-instance granularity
(standard-cell black boxes, 0 transistor-level devices on either side), not
transistor-level.** Power-net (`VPWR`/`VGND`/`VPB`) correspondence is
explicitly out of scope for this comparison — see below.

**Second-engine cross-check (T1 item 4): not run.** `docs/cli/lvs.md`
documents a `netgen`-backed engine alongside the default `NetlistComparer`
one. `netgen` has no Homebrew formula and was not present on this build
host; a from-source build was not attempted within this issue's scope. This
LVS leg is therefore **one toolchain's own verdict**, not yet
cross-checked by a second, independent engine.

## What this GDS has not been through (missing flow stages) — updated,
issue #81

Per `layout/README.md`'s "What this GDS does *not* contain": as of issue
#81, `layout/modexp.gds` now has **tapcell insertion, power-grid (PDN)
generation, and filler-cell insertion** (`request.power`, via
`flow/par-modexp.json`'s new `power` block) — the exclusion list above no
longer applies to those three. **Still absent**: metal (density) fill (a
routing-layer CMP-density pass, unrelated to standard-cell row fillers) and
`DONT_USE_CELLS` exclusion, both out of this issue's scope. No IO ring
either way (unaffected by `request.power`).

**Consequence for the LVS `VPWR`/`VGND`/`VPB`/power-net scoping note
below** (carried forward from the pre-#81 comparisons, both the
issue-#81 re-run above and the issue-#55 fresh-build comparison): power-net
correspondence is still not attempted by either comparison, but the reason
has changed. Previously, there was no PDN at all — row-level power-rail
continuity between non-adjacent placements was not guaranteed, and there
was no PDN to bridge that gap even where it existed, so a power-net
mismatch was an *expected*, structurally-guaranteed consequence of a
documented missing-flow-stage gap. Now that issue #81 adds a real PDN,
`klt extract` reports genuine, continuous `VDD`/`VSS` top-level pins for
the first time (confirmed directly — see `layout/lvs/README.md`'s issue
#81 update) — but `NetlistComparer` still never reaches net-by-net
correspondence in either comparison, because it stops at the
circuit-type-level block (the unmatched-type mismatches described above)
before it would attempt matching any individual net, power or otherwise.
Power-net correspondence therefore remains untested, but for a *different*
structural reason than before — worth stating precisely rather than
carrying forward a now-stale rationale.

## Reading the spec's Signoff row (updated 2026-09-11, issue #81)

`spec/modexp.md`'s Signoff row — *"DRC + LVS clean on the OpenROAD-produced
GDS"* — is **still not met** by `layout/modexp.gds`, stated plainly: DRC is
now clean, but LVS is not, and the row requires both. The ratified table
itself is unchanged (this update adds a real layout regeneration plus
re-run evidence, it does not relax the target — no decision-record entry is
needed since nothing about the ratified row changes). What this repo's
evidence establishes, precisely bounded:

- **DRC is now clean against `layout/modexp.gds`** (issue #81):
  `flow/par-modexp.json`'s new `power` block drives tapcell + PDN +
  filler-cell insertion, closing all 234 previously-classified
  `nwell.space.1`/`nwell.width.1` violations (161 documented-gap, the
  intended target, plus 73 check-engine-limitation ones as an incidental
  consequence — [klayout-tools#1654](https://github.com/2AMLogic/klayout-tools/issues/1654)
  itself remains open upstream, untouched). This closes the DRC half of the
  Signoff row's requirement for the first time since issue #78's deck
  coverage bump reopened it.
- **LVS is still not clean.** Re-run against the same regenerated GDS
  (issue #81): mismatch count grew from 15 to 17 (5 new physical-only cell
  types with no possible synthesis-side counterpart + the same class of
  ordinary CTS/timing-fixup churn as before), still 100% `topology`, no new
  mismatch category. The separate "fresh self-consistent build" comparison
  (issue #55, 1324 mismatches, unaffected by this update) gets past the
  circuit-type-level block a pre-CTS reference always produced and attempts
  real net/instance correspondence — still `status: "mismatch"`, traced to
  `klt extract`'s net-naming defaults and the `sky130` extraction deck's
  own documented layer-coverage limits, neither a real connectivity defect.
- The LVS reference-netlist question has a genuinely as-built answer
  (`write_verilog`, cell-instance granularity), demonstrated end-to-end
  against a self-consistent fresh build — the deepest this toolchain's
  digital LVS path has been exercised against this design so far. This is
  unchanged by issue #81.
- A separate, load-bearing finding from issue #55, still standing: a `klt`
  pin bump is **not** a P&R-reproducibility guarantee (see
  `verification/records/drc-lvs/records/20260816-174310-5e656e5.md`).
  Issue #81's own P&R run, by contrast, **is** confirmed byte-for-byte
  reproducible across two independent cold runs at the same pin — a
  narrower, single-pin reproducibility check, not a contradiction of the
  cross-pin finding above.

Per this issue's own acceptance criteria, `spec/modexp.md` is **not**
relaxed to accommodate the remaining LVS shortfall. The Signoff row staying
unmet with a documented, evidence-backed reason is the correct outcome, not
a failure of this update — this is exactly the seam `README.md` names as the
point of this repo: *"the seam where digital output re-enters the layout
tools."* Closing LVS for real needs either a `sky130` extraction-deck
layer-coverage extension or a different LVS methodology (see "Friction filed
upstream" below) — a decision-record entry tracking that as the next input
to Decision-record-worthy spec discussion is a natural follow-up, not
undertaken here.

## Friction filed upstream

Tool/flow gaps found while producing this evidence, filed generically (no
design-specific detail beyond PDK standard-cell names) at
`2AMLogic/klayout-tools`, per `CLAUDE.md`'s friction protocol:

1. **`klt drc`'s `"enclosing"`/`"enclosed"` checks can false-positive on
   same-layer geometry drawn as multiple abutting (touching, unmerged)
   shapes**, since the checked `Region` is built directly from raw shapes
   with no `.merge()` call. Reproduced on an unmodified `sky130_fd_sc_hd`
   library cell. See `layout/drc/README.md` for the full reproduction. Filed
   as [klayout-tools#995](https://github.com/2AMLogic/klayout-tools/issues/995)
   — **closed upstream, fixed by
   [klayout-tools#998](https://github.com/2AMLogic/klayout-tools/pull/998)**
   (merged 2026-08-15); this repo's `klt` pin was bumped past it and this
   specific false positive does not recur (see "DRC" above — a *separate*,
   later pin bump, issue #78, surfaced new, genuine violations on two
   newly-added rules, unrelated to this finding).
2. **`klt place-and-route` had no post-CTS/post-optimization netlist
   export**, so a gate-level LVS golden reference built from `klt
   synthesize`'s own output necessarily diverged from the routed layout by
   the P&R tool's own timing-driven clock-tree insertions and gate resizes.
   Filed as [klayout-tools#996](https://github.com/2AMLogic/klayout-tools/issues/996)
   — **closed upstream, fixed by
   [klayout-tools#997](https://github.com/2AMLogic/klayout-tools/pull/997)**
   (merged 2026-08-15); this repo's `klt` pin was bumped past it and a true
   as-built reference is now used (see "LVS" above) — though closing this
   gap surfaced a *new* one (`klt` pin bumps are not P&R-reproducible; see
   `verification/records/drc-lvs/records/20260816-174310-5e656e5.md`), not
   yet filed as its own generic report since it may simply be expected
   version-to-version tool drift rather than a defect.
3. **Icarus `$sdf_annotate` cannot resolve a top-level-port-attached
   `INTERCONNECT` entry in a real post-route SDF, even under
   `-ginterconnect`**, while an otherwise-identical instance-pin-to-
   instance-pin entry resolves — found while attempting Leg 2's
   delay-annotated gate-level simulation (issue #55). Filed as
   [klayout-tools#1056](https://github.com/2AMLogic/klayout-tools/issues/1056)
   — **closed upstream, fixed by
   [klayout-tools#1069](https://github.com/2AMLogic/klayout-tools/pull/1069)**
   (merged 2026-08-17); this repo's `klt` pin was bumped past it (issue
   #78) and the top-level-port entries now resolve essentially completely.
   A new, narrower residual class (49 entries, a different pattern — a
   driver net's top-level-port `INTERCONNECT` entry resolves but its
   sibling internal-instance-pin entries on the same net do not) was found
   once the fix made this attempt reach that far — see "Post-route
   gate-level simulation" below for the account. Filed generically as
   [klayout-tools#1619](https://github.com/2AMLogic/klayout-tools/issues/1619).
4. **A `DrcRule` transcribed as `check="space"` to approximate a
   source rule whose real semantics is `isolated` can false-positive on a
   concave notch within a single merged polygon**, since `Region.space_check`
   (unlike `Region.isolated_check`) does not distinguish "different
   polygons" from "one polygon with a narrow inward corner." Found while
   classifying `nwell.space.1`'s 194 violations (issue #79): 73 of them
   (confirmed by direct inspection of the merged `nwell.drawing` region)
   are exactly this same-polygon case, on an unmodified `layout/modexp.gds`.
   The rule's own docstring in `src/klayout_tools/decks/sky130.py` already
   documents this as a known approximation with "no corpus regression
   found" in the deck's own test corpus — this is a concrete instance the
   corpus did not cover. Filed generically as
   [klayout-tools#1654](https://github.com/2AMLogic/klayout-tools/issues/1654).

## Post-route gate-level simulation (appended, issue #9)

**Note (issue #81, 2026-09-11): this section's evidence is against the
*pre*-#81 layout, not the current `layout/modexp.gds`.** `layout/lvs/
modexp_layout_abstracted.spice` (the extraction artifact this section's
netlist derives from) was deliberately left unchanged when issue #81
regenerated `layout/modexp.gds` — re-deriving it hits a validation gap in
`verification/gate-level/spice_to_verilog.py` when the layout has a real
PDN (genuine `VDD`/`VSS` top-level pins the script doesn't yet model as
power ports). Tracked as
[sky130-modexp#83](https://github.com/2AMLogic/sky130-modexp/issues/83);
the findings below remain correct history against the layout they were
measured against, not a current claim about the regenerated GDS.

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
- **Leg 2 (delay-annotated SDF simulation), updated 2026-09-09, issue #78:
  RE-ATTEMPTED — still FAIL, narrower failure class.** Issue #55 first
  exercised Leg 2 end to end after `klayout-tools#1007` (SDF export/option)
  landed: `klt`'s SDF diagnostic gate reported 200 of ~753 `INTERCONNECT`
  entries (every one top-level-port-attached) unresolved, filed generically
  as [klayout-tools#1056](https://github.com/2AMLogic/klayout-tools/issues/1056).
  Issue #78 bumped the pin past
  [klayout-tools#1069](https://github.com/2AMLogic/klayout-tools/pull/1069)
  (`#1056`'s fix — a generated pass-through wrapper for top-level-port
  `INTERCONNECT` entries) and re-ran Leg 2 against a fresh post-route
  build's own `write_verilog` netlist and `write_sdf` output. Result: the
  fix resolves the great majority of the prior 200 (including `done`), but
  `klt`'s own SDF diagnostic gate still reports the run failed — a new,
  narrower residual class of 49 unresolved `INTERCONNECT` entries (3 tied to
  antenna-diode filler cells, 46 tied to a specific block of flip-flop
  driver nets), and the regression itself still reports a uniform,
  constant-zero result on every test case even though `done` now resolves.
  Full evidence:
  `verification/records/gate-level-sim/records/20260909-230216-92e00f2.md`
  (supersedes `20260816-174310-5e656e5.md`).

Full method and scope: `verification/gate-level/README.md`. Records:
`verification/records/gate-level-sim/`.

## Evidence record

`verification/records/drc-lvs/records/<record-id>.md` (append-only
convention, `verification/README.md`), carrying the DRC deck's
`content_hash`, the LVS extraction deck's `content_hash`, and
`layout/modexp.gds`'s own `content_hash` so staleness is detectable if
either the deck or the layout changes.
