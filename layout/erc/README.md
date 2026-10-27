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
klt erc layout/modexp.gds layout/erc/erc-supply-spec.json --pdk sky130 \
  --format json > layout/erc/modexp-erc-supply-report.json
```

**Updated by issue #232**: re-run on the regenerated `layout/modexp.gds` with
`klt 0.7.1.dev1127+gd1dc0fc090d4` (the `scripts/setup-env.sh` pin), klayout
`0.30.12`. The report's `provenance.input.content_hash` is
`sha256:cc970173409a1fcb28f6bc8c1c916f90d0f5fedf88fff3690cb91102f2734372`, the
committed GDS. Result: `erc_status: clean`, `erc_finding_count: 0`, `VPWR` and
`VGND` one island each, 1842 gate nets. The command gained `--pdk sky130`:
without it this klt reports the top-level `status` as `not_checked` (every
antenna verdict `unchecked`; the connectivity verdict `erc_status` is `clean`
either way), whereas the previous klt reported a plain `clean`. With it the
top-level `status` is `clean_partial` (every gate `pass_partial`: the built-in
antenna table covers only part of the rules) -- a different vocabulary from the
`clean` of the klt 0.5.0 report this replaces, not a weaker connectivity
result. The label-text and gate-net counts quoted below were measured on the
previous GDS (1848 gate nets); the current ones are in the report itself.

**Updated by issue #235**: the report was regenerated with the `nwell_tap`
tie declared (same klt, klayout and command). The GDS hash is unchanged.
`erc_finding_count` stays 0 and `erc_status` stays `clean`; the `no_ties_declared`
inapplicable entry is replaced by the checked `nwell_tap` tie.

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

## Well ties: `erc.missing_tie` (issue #235)

`erc-supply-spec.json` declares one tie, `nwell_tap`: every merged `nwell`
shape (64/20) must contain a `tap.drawing` (65/44) shape electrically
connected, through `li1`, to `VPWR`. 65/44 is a tap-only layer in sky130, so
the tie carries `tap_is_dedicated: true` and is graded as checked work:
`erc_coverage.checked` lists `erc.missing_tie:["nwell_tap"]`,
`erc_coverage.skipped` is empty, and `erc_finding_count` is 0. This replaces
the earlier omission of `ties[]`, which was a workaround for
klayout-tools#2169 (a declared tie collapsing the design into one island and
reporting a false `erc.supply_short`); the pinned klt
(`0.7.1.dev1127+gd1dc0fc090d4`) no longer does that on this layout --
`VPWR` and `VGND` still resolve to one island each, with no
`erc.supply_short`.

Falsifiability control (variant spec, not committed): the same tie declared
against `VGND` instead of `VPWR` reports 26 `erc.missing_tie` findings (one
per nwell shape), so the zero is a computed verdict. 265 of the layout's 530
tap shapes sit inside an nwell, matching the 265 tapcell instances in the
P&R record.

What is **not** verified: the **p-substrate (`VGND`) tie**. sky130 draws no
substrate well, so the only expressible declaration is `well_layer: null`
plus a `well_boxes` assertion of the substrate region, and a region covering
this die is graded `degenerate_well_assertion` (skipped work, which item 11
renders `supply_spec_incomplete`). Narrowing the box just to pass that test
would be a different, unfalsifiable claim, so no substrate tie is declared and
no `ties_disclosure` is used. The gap is filed generically upstream as klayout-tools#4285 (see the
PR description too). Admissible evidence standing in for it: the `VGND`
island read above, and the P&R record's PDN with
`tapcell_master: sky130_fd_sc_hd__tapvpwrvgnd_1` and 265 tapcell instances.
Item 11 therefore reads `met` on the grader's terms with the nwell half
computed and the substrate half unverified here.

The P&R envelope item 11 cites is the item-2 flow run's
`verification/records/place-and-route/artifacts/20261027-013900-98bf55d/par-run1-output.json`
(`power.pdn: true`, `tapcell_master: sky130_fd_sc_hd__tapvpwrvgnd_1`, straps
met1/met4/met5). The manifest pins the `content_hash` of the evidence's
*input* (GDS for the ERC report, netlist for the P&R envelope), not of the
JSON file itself.

## Where the graded row lives

This repo's gap-to-T1 verdict of record is `verification/signoff/`
(issue #130's `klt signoff --manifest` report), which cites this
directory's report — together with the LVS report and the P&R envelope —
as item 11's compound evidence entry and renders the machine verdict
there. The hand-maintained checklist that used to live in issue #12 was
superseded by that mechanism on 2026-09-23; read the graded report, not
either prose source, for the current per-item state.

## Layer-number provenance

Every layer/datatype in the spec was resolved from the pinned sky130A
PDK's own `libs.tech/klayout/tech/sky130A.lyp` (open_pdks
`f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7`, the `docs/environment.md`
pin) and cross-checked against klayout-tools' curated sky130 deck layer
table (`decks/sky130.py`): `poly.drawing 66/20`, `diff.drawing 65/20`,
`li1.drawing 67/20`, `met1..met5.drawing 68..72/20`, `licon1 66/44`,
`mcon 67/44`, `via 68/44`, `via2 69/44`, `via3 70/44`, `via4 71/44`. The
`.label` purposes carrying pin text are `67/5` (li1), `68/5` (met1) and
`72/5` (met5), confirmed by scanning the GDS's own text labels rather
than assumed. No layer number was copied from another PDK's spec.
