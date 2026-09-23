# layout/erc/ — structural power delivery (T1 item 11, supply read)

The `klt erc` supply-spec evidence for **T1 item 11 (power delivery,
structural)** against `../modexp.gds` (issue #129): every declared supply
resolves to exactly **one** electrical island, and the two supplies are
distinct islands. This is the digital column's `klt erc` half of the item;
the PDN-existence half (`power.pdn`, `power.tapcell_master`, strap
coverage) is cited from the committed place-and-route record below.

## Contents

```
layout/erc/
  erc-supply-spec.json            the klt erc spec (every field justified
                                  in its inline _comment block)
  modexp-erc-supply-report.json   the committed klt erc --format json run
  README.md                       this file
```

Regenerate the report:

```bash
klt erc layout/modexp.gds layout/erc/erc-supply-spec.json \
  --format json > layout/erc/modexp-erc-supply-report.json
```

`klt 0.5.0` (git revision `2f64ab88bfcc` — a working-tree build ahead of
`docs/environment.md`'s `f77036bf` pin; the report's own
`provenance.klt_version` records `0.5.0`), klayout `0.30.10`. The
committed report's `provenance.input.content_hash` is
`sha256:9fa0dbe1dafa4aa4b09bec781817e118d7b1c7d2fe9b8a7688a4b34e9191ef79`,
which is the sha256 of the committed `layout/modexp.gds` on this branch —
the report pins exactly the GDS it was run against (and its
`provenance.spec.content_hash` pins the spec the same way, per
klayout-tools#2036).

## Reading the verdict

`status: clean`, `erc_finding_count: 0` over 1848 gate nets — and zero
*is* the verdict, not an absence of one:

- `erc.unconnected_net` fires when a declared net matches **zero** islands
  (nothing carries that label) **or more than one** (the rail is split
  into pieces that never touch). The spec declares `VPWR` and `VGND`
  (`kind: "supply"`), whose label set — 3095 `VPWR` + 3095 `VGND` texts
  across `li1.label` (67/5) and `met1.label` (68/5), i.e. every
  standard-cell and tap-cell PG pin in the design — resolves to exactly
  one island each. The split-rail case is the no-PDN failure mode this
  read exists to catch.
- `erc.supply_short` fires when two declared supply names resolve to the
  same island. `VPWR` and `VGND` do not.

Two falsifiability controls were run (variant specs, not committed) to
prove the zero is a computed verdict rather than a silent match failure —
each fires exactly the finding it should:

| Control | Expectation | Result |
| --- | --- | --- |
| Declare a bogus `VBOGUS` supply | `erc.unconnected_net` (zero islands) | fired, as expected |
| Declare `VDD` alongside `VPWR` (with met5 `label_layer: 72/5` added so the top-level pin text is matchable) | `erc.supply_short VDD × VPWR` — the DEF `SPECIALNETS` join (`- VDD ( * VPB ) ( * VPWR )`) makes them one island | fired, as expected |
| Declare `VSS` alongside `VGND` (same added label layer) | `erc.supply_short VGND × VSS` | fired, as expected |

The controls also document why the committed spec declares the cell-side
spellings (`VPWR`/`VGND`) and not the top-level `VDD`/`VSS`: they are two
label spellings of the same two islands by the DEF's own join, and `klt
erc` correctly reports two declared names on one island as a short — so
declaring both would misreport the intended join. The cell-side spelling
is the stronger test (3095 labels per supply must all stitch into one
island, not just the one top-level pin text).

The report's antenna verdicts are all `"unchecked"` (`--pdk` deliberately
omitted, matching the worked example this spec follows): item 11 grades
the supply findings, not the antenna ratios — an antenna verdict or a
floating-gate finding would be a real defect but is not this item's
subject (klayout-tools#1994).

## What is NOT verified here: `erc.missing_tie` (klayout-tools#2169)

`erc-supply-spec.json` deliberately declares no `ties[]`, so the committed
report **does not compute** `erc.missing_tie` at all — klayout-tools
`docs/cli/erc.md` is explicit that omitting `ties[]` means the rule is
never computed. Its zero count in the report is an **absence of evidence,
not evidence of absence**, and must not be cited as a well-tie verdict.

The reason it is omitted is a real tool gap, filed upstream as
**klayout-tools#2169**: declaring `ties[]` on a real routed standard-cell
layout joins the well/tap regions into the primary connectivity graph,
collapses the whole design into one electrical island, and reports a
false `erc.supply_short` (reproduced four ways in `gf180-drone-fc`'s
FRICTION F-034).

What **is** admissible evidence that the well ties exist and reach the
rails, standing in for the uncomputed rule:

1. **The PDN was actually built, with tapcells**: the committed
   place-and-route record
   (`verification/records/place-and-route/records/20260911-052542-d5e43d3.md`,
   raw envelope `artifacts/20260911-052542-d5e43d3/par-nominal-output.json`)
   records `power.pdn: true`, `power.global_connect: true`, `power_net:
   "VDD"`, `ground_net: "VSS"`, `tapcell_master:
   sky130_fd_sc_hd__tapvpwrvgnd_1`, and **265 tapcell instances** —
   issue #81's run. Every `power.straps[].layer` (met1 followpins, met4,
   met5) is covered by this spec's own stackup.
2. **PG pin labels in the merged GDS**: the tap cells' well pins are
   labelled in the stream itself — 2810 `VPB` texts on `nwell.label`
   (64/5) and 2810 `VNB` texts on `pwell.label` (64/59) — and the DEF
   SPECIALNETS join wires `VPB` into `VDD` and `VNB` into `VSS`.
3. **The supply-island verdict itself covers the tap cells' rail side**:
   the tap cells' `VPWR`/`VGND` met1 pins are part of the 3095-label set
   that resolves to one island per polarity.

What is **missing** from this repo's evidence, stated plainly: the
committed LVS report (`layout/lvs/modexp_lvs_report.json`, run before
`power_connectivity` existed in the installed `klt`) carries **no
`power_connectivity` verdict at all** — not `"match"`, not even
`"unchecked"`; the field is absent. Item 11's digital column requires
`power_connectivity.status: "match"` for a *met* citation, so the
standing-in list above is what this repo has today, and a fresh
`klt lvs` re-run on the current `klt` pin is the follow-up that would
close that half. Until both the tie rule (#2169) and the LVS
power-connectivity re-run land, this directory establishes the
supply-island read only — the strongest single structural-power statement
this repo's pinned toolchain can compute.

## Layer-number provenance

Every layer/datatype in the spec was resolved from the pinned sky130A
PDK's own `libs.tech/klayout/tech/sky130A.lyp` (open_pdks
`c6d73a35f524070e85faff4a6a9eef49553ebc2b`, the `docs/environment.md`
pin) and cross-checked against klayout-tools' curated sky130 deck layer
table (`decks/sky130.py`): `poly.drawing 66/20`, `diff.drawing 65/20`,
`li1.drawing 67/20`, `met1..met5.drawing 68..72/20`, `licon1 66/44`,
`mcon 67/44`, `via 68/44`, `via2 69/44`, `via3 70/44`, `via4 71/44`. The
`.label` purposes carrying pin text are `67/5` (li1), `68/5` (met1) and
`72/5` (met5), confirmed by scanning the GDS's own text labels rather
than assumed. No layer number was copied from another PDK's spec.
