# layout/drc

`klt drc` run against the routed GDS (`layout/modexp.gds`, from #7), plus a
per-violation classification with the evidence behind each classification —
see `docs/signoff-claim.md` for the overall DRC/LVS claim this substantiates
and the deck's documented coverage gaps.

## Contents

- `modexp-drc-report.json` — the full `klt drc --deck sky130 --format json`
  report, including the `coverage` block and `provenance` (deck
  `content_hash`, `klt`/`klayout` versions, input `content_hash`).

## Reproducing cold

```bash
./scripts/setup-env.sh && source .venv/bin/activate
klt drc layout/modexp.gds --deck sky130 --format json
```

Exit code `3` (`status: "violations"`), matching this report — see
"Verdict and classification" below for why that is not the same as "DRC is
broken" or "the layout has a real defect."

## Result summary

- `status`: `"violations"`, `violation_count`: **10**, all under a single
  rule: `diff.enclosing.licon.1` (minimum `diff` enclosure of `licon1`,
  0.04 µm, transcribed from the official sky130 rule `licon.5` — see
  `docs/signoff-claim.md`'s coverage-gap enumeration for which of the deck's
  17 rules are approximations; `licon.5` is **not** one of them).
- Deck `content_hash`: `sha256:cc62ce576bd65c127270fda943443493529f6e0a9f7ff85c7e9595938698e73e`.
- Input (`layout/modexp.gds`) `content_hash`: `sha256:229ed6a5f92938699acc969f757d84b9348731bacbe12a485473161e917c8d10`.

## Verdict and classification

All 10 violations are classified **(iii) — a `klt drc` check-engine
limitation firing on correct-by-construction geometry**, not a real defect
in this layout and not a P&R flow-artifact of the kind #8's own issue body
anticipated (missing filler/tapcell insertion at row boundaries). The
evidence, not just the classification, follows.

### What the report shows

Every one of the 10 violations has `"source_cell":
"sky130_fd_sc_hd__and3_1"` — and `layout/modexp.def` places exactly 10
instances of `sky130_fd_sc_hd__and3_1` in this design (`_0608_`, `_0614_`,
`_0615_`, `_0627_`, `_0630_`, `_0633_`, `_0636_`, `_0638_`, `_0648_`,
`_0784_`). One violation per instance, no other cell type affected.

### Reproduces in complete isolation — not a P&R/abutment artifact

`klt drc`'s own documentation (`docs/cli/drc.md`, "Macro-scale,
machine-generated (standard-cell) layout") describes a *different*, already
-known class of `diff.enclosing.licon.1` finding: violations that "cluster
at row boundaries between adjacent standard-cell instances," caused by
`klt place-and-route` running no filler-cell insertion stage (exactly the
"no filler cells" gap `layout/README.md` already documents for this GDS).
That is **not** what this report shows. Extracting the single
`sky130_fd_sc_hd__and3_1` cell from the PDK's own unmodified
`sky130_fd_sc_hd.gds` library view — no synthesis, no place-and-route, no
neighbouring cell, no row, nothing this repo produced — and running the
identical `klt drc --deck sky130` check against that single-cell GDS
reproduces exactly 1 violation, at the same local coordinates as one of the
10 (`bbox` `(1035, 1584)`–`(1060, 1816)` in the cell's own frame). This is a
property of the sky130_fd_sc_hd standard-cell library's own `and3_1` GDS
view, unrelated to anything this design's synthesis or place-and-route did.

### Root cause: `klt drc` does not merge same-layer touching shapes before an `"enclosing"` check

The cell's `diff.drawing` (layer 65/20) geometry near the violation is drawn
as **two separate, abutting (touching, non-overlapping) rectangles** —
`(135,1500)-(1035,1920)` and `(1035,1500)-(1505,1920)`, sharing the vertical
edge at `x=1035` — rather than one merged polygon. This is an ordinary GDS
authoring/tiling choice (confirmed as the *only* `sky130_fd_sc_hd` cell out
of 437 checked that draws its `diff` this way near a `licon1` cut close
enough to matter — see "Library-wide scope" below), not a drawn defect.

`klt drc`'s `"enclosing"` check (`src/klayout_tools/drc.py`, `run_drc`)
builds the checked region directly from the raw shape iterator —
`region = kdb.Region(cell.begin_shapes_rec(layer_index))` — with no
`.merge()` call before `region.enclosing_check(other_region, threshold)`
runs. Checked directly against this cell's actual geometry (`klayout.db`,
same `pip install klayout` engine `klt` itself wraps):

```python
diff_raw = kdb.Region(cell.begin_shapes_rec(diff_layer))       # 6 polygons
diff_raw.enclosing_check(licon_region, 40, False).count()      # -> 1 (the reported violation)

diff_merged = diff_raw.dup(); diff_merged.merge()               # 2 polygons
diff_merged.enclosing_check(licon_region, 40, False).count()   # -> 0
```

The unmerged check measures the `licon1` cut's distance to the nearest edge
of *one* of the two abutting rectangles (25 nm on its left edge, short of
the 40 nm threshold) and never "sees" that the touching neighbour rectangle
extends the real, physically continuous diffusion another 900 nm further —
because that neighbour is a separate `Region` element, not merged into the
same polygon. The merged region (what any real DRC signoff tool computes
first) shows the cut is enclosed with 925 nm of margin on that side —
nowhere close to a violation. This is a `klt drc` check-primitive
limitation, not a deck-authoring approximation (`licon.5` is transcribed at
its real, unmodified 0.04 µm threshold — this is not one of the two
compound-layer approximations or four bound approximations `docs/cli/drc.md`
"Coverage" enumerates) and not a flow artifact of this repo's P&R run.

### Library-wide scope

Checked (with the same raw-vs-merged comparison) against every cell in
`sky130_fd_sc_hd.gds` (437 cells): only `sky130_fd_sc_hd__and3_1` shows a
discrepancy. This is a narrow, specific finding — one library cell's
particular `diff` tiling choice interacting with this check-engine gap — not
a claim that the gap is widespread across the library.

### Filed upstream

[`2AMLogic/klayout-tools#995`](https://github.com/2AMLogic/klayout-tools/issues/995)
— generic tool-gap report (no design-specific detail from this repo beyond
the reproducing standard-cell name, which is PDK content).
