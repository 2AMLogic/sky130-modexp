# Signoff claim: DRC + LVS on the routed GDS

**This is the single authoritative statement of what this repo's DRC/LVS
evidence establishes and does not establish**, per issue #8 (and re-verified
by issue #55). It answers `spec/modexp.md`'s Signoff row — *"DRC + LVS clean
on the OpenROAD-produced GDS"* — against `layout/modexp.gds` (from #7).

## Verdict (updated 2026-08-16, issue #55): **not met** — DRC is now clean;
LVS is the sole remaining gap, evidenced more deeply than before

**DRC is now clean** (below) — a genuine, unqualified improvement over the
prior 10-violation result, fixed by an upstream `klt` change, not by any
change to this design. **LVS still reports `status: "mismatch"`**, so
`spec/modexp.md`'s Signoff row (*"DRC + LVS clean"*, both conjuncts required)
remains **not met** overall — stated plainly, not "met with caveats." What
follows is why neither the historical DRC violations nor the current LVS
mismatches indicate a real defect in this design; every reported finding on
both sides is classified with evidence, not asserted.

## DRC — **CLEAN** (was: 10 violations)

`klt drc layout/modexp.gds --deck sky130 --format json` → **`status:
"clean"`, `violation_count: 0`**, against the same, unmodified
`layout/modexp.gds` (identical content hash to the prior run). Full report
and provenance: `layout/drc/README.md` and `layout/drc/modexp-drc-report.json`.

**What changed**: the prior 10 violations (all `diff.enclosing.licon.1`, all
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

## LVS — still `status: "mismatch"`, now with a true as-built reference and a
different, deeper-diagnosed cause (updated 2026-08-16, issue #55)

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

## Reading the spec's Signoff row (updated 2026-08-16, issue #55)

`spec/modexp.md`'s Signoff row — *"DRC + LVS clean on the OpenROAD-produced
GDS"* — is **still not met** by `layout/modexp.gds`, stated plainly: LVS
does not report a clean verdict. **DRC now does.** What this repo's evidence
establishes, precisely bounded:

- **DRC is clean against `layout/modexp.gds`** as of the bumped `klt` pin —
  the prior 10-violation result was a check-engine limitation, now fixed
  upstream, not a real geometry defect; see "DRC" above.
- LVS gets, for the first time, past the circuit-type-level block a pre-CTS
  reference always produced, and every LVS mismatch remaining (net-name
  correlation, extraction-deck layer coverage) is individually classified
  with supporting evidence, not asserted — neither is a real connectivity
  defect in this design.
- The LVS reference-netlist question now has a genuinely as-built answer
  (`write_verilog`, cell-instance granularity), demonstrated end-to-end
  against a self-consistent fresh build — the deepest this toolchain's
  digital LVS path has been exercised against this design so far.
- The remaining LVS gap traces to the `sky130` extraction deck's own
  documented layer-coverage limits and to `klt extract`'s net-naming
  defaults (worked around, not fully solved, by `--def-net-names`) — not to
  the previously-blocking CTS/resize divergence, which is fully resolved.
- A separate, load-bearing finding from this update: a `klt` pin bump is
  **not** a P&R-reproducibility guarantee (see
  `verification/records/drc-lvs/records/20260816-174310-5e656e5.md`) — the
  as-built reference above had to be compared against a fresh build, not
  `layout/modexp.gds` itself, for that reason.

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
   (merged 2026-08-15); this repo's `klt` pin was bumped past it and DRC is
   now clean (see "DRC" above).
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
   [klayout-tools#1056](https://github.com/2AMLogic/klayout-tools/issues/1056).
   See "Post-route gate-level simulation" below.

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
- **Leg 2 (delay-annotated SDF simulation), updated 2026-08-16, issue #55:
  ATTEMPTED — FAIL, no longer blocked.** `klayout-tools#1002` (no SDF export,
  no SDF option) is closed upstream, fixed by
  [klayout-tools#1007](https://github.com/2AMLogic/klayout-tools/pull/1007)
  (merged 2026-08-15); this repo's `klt` pin was bumped past it and Leg 2 was
  exercised end to end (build, SDF load, regression run) against a fresh
  post-route build's own `write_verilog` netlist and `write_sdf` output.
  Result: `klt`'s own SDF diagnostic gate reports the run failed — 200 of
  ~753 `INTERCONNECT` entries (every one top-level-port-attached, every one
  carrying zero delay regardless) could not be resolved by Icarus 13.0's
  `$sdf_annotate`, and the regression itself reports a uniform, constant-zero
  result on every test case. New, generic finding filed as
  [klayout-tools#1056](https://github.com/2AMLogic/klayout-tools/issues/1056).
  Full evidence:
  `verification/records/gate-level-sim/records/20260816-174310-5e656e5.md`.

Full method and scope: `verification/gate-level/README.md`. Records:
`verification/records/gate-level-sim/`.

## Evidence record

`verification/records/drc-lvs/records/<record-id>.md` (append-only
convention, `verification/README.md`), carrying the DRC deck's
`content_hash`, the LVS extraction deck's `content_hash`, and
`layout/modexp.gds`'s own `content_hash` so staleness is detectable if
either the deck or the layout changes.
