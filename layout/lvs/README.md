# layout/lvs

LVS evidence for the routed GDS (`layout/modexp.gds`, from #7) — see
`docs/signoff-claim.md` for the overall claim and the comparison level this
establishes.

## Update (issue #55, 2026-08-16): a true as-built reference now exists, run
## against a fresh build — read this before the historical section below

Everything below this note, through "Reading this result," describes the
**original** (2026-08-15) comparison against a pre-CTS reference built from
`klt synthesize`'s output — kept verbatim as history, per
`verification/README.md`'s append-only convention. It is now superseded for
freshness by `verification/records/drc-lvs/records/20260816-174310-5e656e5.md`,
which:

- Bumped `docs/environment.md`'s `klt` pin past
  [klayout-tools#997](https://github.com/2AMLogic/klayout-tools/pull/997)
  ("feat(place-and-route): export as-built netlist via `write_verilog`"),
  closing the exact gap this page's "Reading this result" section named as
  the blocker to a truer reference.
- Discovered, and evidences, a load-bearing fact: **re-running `klt
  place-and-route` with the bumped `klt`, even against the identical frozen
  netlist/floorplan/seed, does not reproduce `layout/modexp.gds` byte-for-byte**
  (722 vs 718 instances, Fmax 158.8 vs 149.7 MHz — see that record for the
  full comparison table). So the as-built reference below is compared
  against a **fresh, self-consistent build's own extraction** — not against
  `layout/modexp.gds` itself, which is deliberately left unchanged.
- With the as-built reference, `klt lvs` gets **past** the circuit-type-level
  block this page's original result describes (every cell type now has a
  same-named counterpart on both sides) and attempts real net/instance
  correspondence for the first time — still `status: "mismatch"` (1324
  mismatches: 888 topology, 434 net.split, 2 net.merged), now attributed to
  `klt extract`'s net-name correlation (`--def-net-names` improves but does
  not close it) and to the `sky130` extraction deck's own documented
  layer-coverage limits (dead metal / ignored layers), not to CTS/resize.
- `build_reference_netlist.py`'s Verilog parser was generalized to also
  parse OpenROAD's own `write_verilog` instantiation styling (verified
  byte-identical behavior on the old styling first).

Full detail: `verification/records/drc-lvs/records/20260816-174310-5e656e5.md`.
`docs/signoff-claim.md`'s LVS section is the current authoritative summary.

## The reference-netlist question, answered

Issue #8 named three options for the missing Verilog-gate-netlist LVS
reference path: (a) transistor-level extraction against a resolved
transistor reference, (b) cell-instance-level comparison if the extraction
deck can be made to recognise cells, (c) "not supported today, filed." The
answer is **(b), and it works** — `klt extract` gained
`--abstract-cells`/`--abstract-cell-lef` (klayout-tools#620, merged
2026-08-08, in direct response to this issue being filed — see
`docs/cli/extract.md`'s "Cell-level (black-box + pins) abstraction," which
cites this issue by number) exactly for "comparing an OpenROAD-produced,
placed-and-routed GDS against its synthesized gate-level netlist … at the
standard-cell boundary, not the transistor level."

**Version note**: this repo's pinned `klt` revision
(`af5791b557fc7c669c3981335a294256ccf37e6f`, `docs/environment.md`,
2026-08-04) predates klayout-tools#622 (merged 2026-08-08) and does not have
`--abstract-cells` — confirmed directly (`klt extract --help` on the pinned
install has no such flag). The extraction step below (only) was run against
klayout-tools git revision `f9e1ea5cd4ab0ad4d0cb5c05ea97cce4cb457232` (the
#622 merge commit) via `uvx --from
"klayout-tools @ git+https://github.com/2AMLogic/klayout-tools@f9e1ea5cd4ab0ad4d0cb5c05ea97cce4cb457232"
klt extract …`, without touching this repo's pin (`docs/environment.md`) or
its normal `.local`/`.venv` install — that stays out of scope for this
issue, per the precedent `flow/README.md`'s "Known upstream gaps" section
already sets for using a local, interim path around a fix that landed after
the pin. `klt lvs` itself (the comparison step, which needs nothing from
#620/#622) ran against the repo's normally pinned/installed `klt`, both
`klt 0.2.0` either way (`klayout` 0.30.10).

## Contents

- `modexp_layout_abstracted.spice` — the layout side: `klt extract
  layout/modexp.gds --deck sky130 --abstract-cells 'sky130_fd_sc_hd__*'
  --abstract-cell-lef <sky130_fd_sc_hd.lef>`. Every standard-cell instance
  becomes an opaque `X<instance>` call into an empty `.SUBCKT <cell type>
  <pins...> .ENDS` block (0 transistor-level devices — by design, everything
  is abstracted at the cell boundary); `modexp` itself is the flat top
  circuit. 718 instances, 59 distinct cell types, 1214 nets, 68 top-level
  pins. All 59 cell types' pins resolved from **in-cell labels** (the
  standard-cell GDS views' own drawn pin text) — the `--abstract-cell-lef`
  fallback was available but never needed (`modexp_layout_extract_report.json`'s
  `abstracted_cells[].resolution_source` is `"in_cell_labels"` for every
  entry).
- `modexp_layout_extract_report.json` — the full `klt extract --format json`
  response: `abstracted_cells[]` (per-type instance/pin counts + resolution
  source), `ignored_layers[]`, `provenance` (deck `content_hash`, input
  `content_hash` — matches `layout/drc/`'s, confirming both checks ran
  against the same GDS content).
- `modexp_reference.spice` — the golden reference: every standard-cell
  instance from `klt synthesize`'s gate-level netlist
  (`verification/records/place-and-route/artifacts/20260814-203901-c741877/modexp_synth_tied.v`,
  the exact netlist #7's `klt place-and-route` run was given — same
  `content_hash`,
  `sha256:67a218e16cf51e4f3010e5f87404b829f0574d9765b2569278abd54a4fdc7486`),
  rewritten as `X<instance> … <cell type>` calls against the **same**
  per-cell-type `.SUBCKT … .ENDS` pin declarations
  `modexp_layout_abstracted.spice` already wrote (reused verbatim, so both
  sides bind positional SPICE arguments to the same pin order for the same
  cell type — a cell type the synthesis netlist uses but the routed layout
  never instantiates falls back to that type's own PIN order straight from
  the sky130_fd_sc_hd LEF, since there is no layout-side declaration to stay
  consistent with).
- `build_reference_netlist.py` — the script that writes
  `modexp_reference.spice` from the two inputs above. Run it cold with:

  ```bash
  python3 layout/lvs/build_reference_netlist.py \
    verification/records/place-and-route/artifacts/20260814-203901-c741877/modexp_synth_tied.v \
    layout/lvs/modexp_layout_abstracted.spice \
    "$(klt pdk find --pdk sky130A 2>/dev/null | ...)/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef" \
    /tmp/modexp_reference.spice   # or overwrite the committed copy
  ```

  (resolve the LEF path per `klt pdk find`/`docs/environment.md`'s volare
  install; on the environment this evidence was produced on it is
  `~/.volare/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef`).
- `modexp_lvs_report.json` — `klt lvs`'s `--format json` response, engine
  `"klayout"` (`NetlistComparer`).

## Reproducing the comparison cold

```bash
klt lvs '{"schema":"klt.lvs.request/1","engine":"klayout",
  "layout":{"netlist":"layout/lvs/modexp_layout_abstracted.spice","top":"modexp"},
  "reference":{"netlist":"layout/lvs/modexp_reference.spice","top":"modexp"}}' \
  --format json
```

## Documented scope of this comparison

- **Cell-instance granularity, not transistor-level.** Every standard cell
  is an opaque, pin-only black box on both sides (0 devices reported on
  either side by construction) — the transistors inside each cell are
  foundry-qualified, unmodified `sky130_fd_sc_hd` library cells on both
  sides regardless, and are not what this comparison checks.
- **`VPWR`/`VGND`/`VPB`/`VNB` are tied to one ideal global net per name on
  the reference side**, because `klt synthesize`'s gate-level Verilog netlist
  carries **no power connectivity at all** (Yosys's logic-synthesis mapping
  wires only functional pins; a real supply net doesn't exist until a PDN
  stage runs). This is the textbook schematic assumption of ideal global
  supply rails. The **layout** side has no such assumption available: per
  `layout/README.md`'s "What this GDS does *not* contain," this GDS has
  **no PDN** — so whatever `VPWR`/`VGND`/`VPB` connectivity the layout
  extraction reports is exactly, and only, whatever the standard-cell rows'
  own built-in power rails happen to connect, which is fragmented by the
  same missing-filler-cell gaps `layout/drc/README.md` and
  `docs/signoff-claim.md` document (this design's placement rows are sparse
  — see `docs/signoff-claim.md`'s worked row example — so row-rail
  continuity between non-adjacent placements is not guaranteed). A
  power-net mismatch between the two sides is therefore an **expected**
  consequence of a documented, prior missing-flow-stage gap, not a new
  finding — see "Result" below for how large that mismatch actually is.
- **Engine: `klayout` (`NetlistComparer`) only.** T1 item 4 asks for a
  second, independent engine's concurring verdict where available.
  `netgen` (`docs/cli/lvs.md`'s `"netgen"` engine) has no Homebrew formula
  and was not present on this build host (`netgen -batch lvs` unavailable);
  a from-source build was not attempted within this issue's scope. This
  leg is **not cross-checked by a second engine** — recorded as a gap, not
  silently skipped.

## Result

`status: "mismatch"` (exit 3). `counts`: nets 1214 (layout) / 739
(reference) / 333 matched; devices 0/0/0 (by construction — see "Documented
scope" above); pins 68/68/333 (`NetlistComparer` counts subcircuit-pin
correspondences here, not only the 68 top-level I/O pins). 15
`category: "topology"`, `severity: "error"` mismatches, all `"circuit could
not be matched to a counterpart"` — 13 `side: "layout"`, 1
`side: "reference"`, 1 `side: "both"` (the top `modexp` circuit itself,
cascading from the 14 unmatched sub-circuit types below).

**Every one of the 15 is fully attributed**, with instance-by-instance
evidence, to two ordinary, benign P&R optimizations the pre-CTS reference
does not (and structurally cannot) model:

1. **35 new instances, present in `layout/modexp.def`'s `COMPONENTS` with
   no same-named counterpart anywhere in the synthesis netlist** — every one
   carries DEF's own `+ SOURCE TIMING` annotation (OpenROAD's own marker for
   a timing-inserted cell): 17 `clkbuf_*` clock-tree buffers + 15
   `clkload*` + 3 `load_slew*` timing/slew fix-up cells, spanning 8 cell
   types (`buf_4`, `buf_6`, `bufinv_16`, `clkinv_2`, `clkinv_4`,
   `clkinvlp_4`, `inv_6`, `probe_p_8`) that the pre-CTS synthesis netlist
   never instantiates at all — this is exactly `klt place-and-route`'s CTS
   stage doing its job.
2. **5 instances present under the identical name in both netlists, but
   resized** (upsized during OpenROAD's placement/timing optimization) to a
   different drive-strength variant of the same logic function:
   `_0565_` (`nor2_1`→`nor2_2`), `_0731_` (`o31ai_1`→`o31ai_2`), `_0785_`
   (`o22ai_1`→`o22ai_2`), `_0894_` (`o21ai_0`→`o21ai_1`), `_0913_`
   (`o21ai_0`→`o21ai_2`).

Cross-checked against `klt lvs`'s own report: the 13 `side: "layout"`
unmatched circuit types are exactly the 8 CTS/timing-fixup-only types above
plus the 5 *new* (post-resize) types from item 2; the 1 `side: "reference"`
unmatched type is `sky130_fd_sc_hd__o22ai_1`, the *pre*-resize type that no
longer exists anywhere in the routed layout once OpenROAD upsized its one
instance. (One 36th DEF-only instance, `clkload1`, uses
`sky130_fd_sc_hd__clkinv_1` — a type also used by ordinary, unresized logic
elsewhere in the design, so it does not add a 14th unmatched *type*; its
extra-instance effect folds into the net-correspondence count instead.) Both
sides' instance-name/cell-type accounting is otherwise a complete,
zero-unexplained-residual match: every one of the 683 non-tie synthesis
instances (+1 tie cell) appears in the routed layout under the identical
instance name and, apart from the 5 resizes above, the identical cell type.

**No `net.unmatched`/`device.*` mismatch category is reported at all** — the
15 mismatches are exclusively the `topology` "circuit could not be matched"
class from the 14 unmatched cell-type declarations (plus the cascading
top-circuit failure).

**`net_correspondence`'s 333 entries are not what they might look like at a
glance.** Inspecting them (`modexp_lvs_report.json`) shows every entry is a
*local pin-name* pair (`{"layout": "A", "reference": "A", "pin": true}`,
repeated) from the 46 **matched** per-cell-type `.SUBCKT` declarations —
true, but trivially so, since `build_reference_netlist.py` reused those
declarations verbatim (see "Contents" above), so a cell type's own pin names
agree by construction, not by anything `klt lvs` discovered. **None of the
333 entries name a top-level `modexp` internal net** (no `$1921`-style
layout net or `_0202_`-style reference net appears anywhere in
`net_correspondence`). `NetlistComparer` did not get far enough to attempt
that deeper, actually-informative comparison: once the top `modexp` circuits
themselves could not be judged equivalent (the `side: "both"` entry above —
a direct consequence of the 14 unmatched sub-circuit types), it stopped
short of resolving net-by-net correspondence across the 1214-vs-739 internal
nets. **This run does not, by itself, positively confirm that the ~680
non-CTS/non-resized instances' internal wiring is topologically identical**
— that claim instead rests on the direct, independent instance-by-instance
DEF-vs-Verilog accounting above (100% of 683 non-tie synthesis instances
present under the same name in the routed layout, with the same cell type
except the 5 named resizes), not on `klt lvs`'s own graph algorithm having
verified it.

## Reading this result

**Not a clean LVS match, and not claimed as one — and, per the paragraph
above, not a full independent confirmation of internal net-by-net
correctness either.** What this run *does* establish: running gate-level,
cell-instance-granularity LVS against this toolchain works mechanically end
to end (the reference-netlist question in issue #8 has a working answer, the
extraction and comparison both run and produce structured output), and the
entire mismatch it reports is accounted for by two well-understood, expected
consequences of comparing a **pre-CTS** synthesis netlist against a
**post-route** layout — not a connectivity defect this design or this P&R
run introduced. `klt place-and-route` has no post-CTS/post-optimization
netlist export (no `write_verilog` stage) to use as a truer golden reference
instead, which would let `NetlistComparer` get past the circuit-level
mismatch and actually exercise net-by-net correspondence on the ~680 shared
instances; that gap is filed upstream as
[klayout-tools#996](https://github.com/2AMLogic/klayout-tools/issues/996)
(see `docs/signoff-claim.md`). A
buffer/resize-normalized supplementary comparison that could exercise that
deeper check is a natural follow-up, not attempted here. The
`VPWR`/`VGND`/`VPB` power-net comparison is separately out of this run's
honest scope, for the reason stated above (no PDN in this GDS).
