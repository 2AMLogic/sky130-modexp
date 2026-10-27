# layout/lvs

LVS evidence for the routed GDS (`layout/modexp.gds`) — see
`docs/signoff-claim.md` for the overall claim and the comparison level this
establishes.

## Current state (issue #233, 2026-10-27)

**LVS `match` against the as-built netlist; `power_connectivity` `match`; T1
item 4 is `met`.**

`modexp_layout_abstracted.spice`, `modexp_layout_extract_report.json`,
`modexp_lvs_report.json` and `modexp_lvs_report_netgen.json` are regenerated from
the #232 GDS with the repo-pinned klt (`0.7.1.dev1127+gd1dc0fc090d4`). The
reference is the as-built netlist `layout/modexp.v` itself (gate-level-verilog
form; it holds no `assign`, so no `expand_concat_assigns.py` step is needed).

| Leg | Engine | Reference | `status` | mismatches / errors | `power_connectivity` |
|---|---|---|---|---|---|
| committed (`modexp_lvs_report.json`) | `klayout` | `layout/modexp.v`, `gate-level-verilog` | **`match`** | 2 / **0** (warnings only) | **`match`** |
| gate-level cross-check (`modexp_lvs_report_netgen.json`) | `netgen` 1.5.133 | `layout/modexp.v`, `gate-level-verilog` | `mismatch` | 3 / 2 | `match` |
| power-bearing cross-check | `netgen` | as-built SPICE with power pins, `plain-element` | `match` (777/777 nets, 70/70 pins) | 0 / 0 | n/a |

Warnings listed with the claim (klayout leg): `topology.power_only_pruned`
(5 physical-only masters: `fill_{1,2,4,8}`, `tapvpwrvgnd_1`) and
`topology.top_level_pins_anchored` (68 top-level pins anchored by name).

What the verdicts do and do not say:

- **The netgen gate-level leg does not match, and that is stated, not hidden.**
  netgen is handed layout cells with `VGND/VPB/VPWR` ports against a signal-only
  gate-level reference whose cells have none, so it pairs no instance (`matched
  0`); it did the same on every earlier layout. The independent-engine
  concurrence is taken on the power-bearing SPICE form of the same netlist (third
  row). That row ties `VPB` to `VDD` by construction, so it cross-checks signal
  connectivity and instance/pin binding only, nothing about `VPB`.
- **`power_connectivity: match` is a per-instance pin-to-net consistency
  verdict** (every instance's `VGND/VPB/VPWR` pins reach one common net each).
  It is not rail continuity (`klt erc`, see `layout/erc/`) and not IR drop
  (`klt power`). `body_verification` stays `unchecked`: the pre-extracted
  netlist form carries no extraction deck.
- **The earlier `VPB` `power_connectivity: mismatch` was an extraction
  artifact** of klt `0.6.0+gdac2b5da`, not a layout defect: a flat extraction
  puts all 4127 pfet bulks on the `VPWR` net.

Evidence: `verification/records/drc-lvs/records/20261027-030000-1c651cc.md`;
decision: `spec/decision-records/0012-lvs-item-4-met-on-the-as-built-netlist-and-the-vpb-mismatch-was-an-extraction-artifact-of-the-earlier-klt-build.md`.

## Contents

- `modexp_layout_abstracted.spice` — the layout side: `klt extract` of
  `layout/modexp.gds` with `--abstract-cells 'sky130_fd_sc_hd__*'`. Every
  standard-cell instance is an opaque `X<instance>` call into an empty
  `.SUBCKT <cell type> <pins...> .ENDS`; there are no transistor-level devices
  (the comparison is at the standard-cell boundary).
- `modexp_layout_extract_report.json` — the full `klt extract --format json`
  response (`abstracted_cells[]`, `ignored_layers[]`, `provenance`).
- `modexp_lvs_report.json` — `klt lvs` response, engine `klayout`, against
  `layout/modexp.v`.
- `modexp_lvs_report_netgen.json` — the identical request with `"engine":
  "netgen"`; carries netgen's own side-by-side text in
  `mismatches[].details.raw`.
- `modexp_reference.spice`, `build_reference_netlist.py` — the hand-built
  SPICE reference (`plain-element` form) and its builder. **Not used by the
  current comparison**; kept as the control leg, which still reproduces its
  17-mismatch result (see history below).
- `expand_concat_assigns.py`, `modexp_synth_expanded.v` — expand the
  concatenation `assign`s of the frozen pre-CTS synthesis netlist into plain
  per-bit `assign`s for `klt lvs`'s Verilog reader
  ([klayout-tools#2372](https://github.com/2AMLogic/klayout-tools/issues/2372)).
  **Not used by the current comparison**; they served the #131 pre-CTS
  comparison.

## Reproducing the current comparison cold

```bash
# 1. Layout side (run from this directory, as in the evidence record):
cd layout/lvs
klt extract ../modexp.gds --deck sky130 --abstract-cells 'sky130_fd_sc_hd__*' \
  --abstract-cell-lef <pdk>/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef \
  --def-net-names --def-pins ../modexp.def \
  -o modexp_layout_abstracted.spice --format json > modexp_layout_extract_report.json
cd ../..

# 2. The committed comparison (from the repository root, so the report's
#    echoed paths stay repo-relative)
klt lvs '{"schema":"klt.lvs.request/1","engine":"klayout",
  "layout":{"netlist":"layout/lvs/modexp_layout_abstracted.spice","top":"modexp"},
  "reference":{"netlist":"layout/modexp.v","top":"modexp",
               "form":"gate-level-verilog","library":"sky130_fd_sc_hd","pdk":"sky130A"}}' \
  --format json > layout/lvs/modexp_lvs_report.json

# 3. The netgen leg: same request with "engine":"netgen". On Debian/Ubuntu,
#    shim the binary name first (klayout-tools#2373):
mkdir -p /tmp/netgen-shim && ln -sf "$(command -v netgen-lvs)" /tmp/netgen-shim/netgen
PATH=/tmp/netgen-shim:$PATH klt lvs '{… same request, "engine":"netgen" …}' \
  --format json > layout/lvs/modexp_lvs_report_netgen.json

# 4. Verify a committed report still describes its own inputs
klt lvs --check layout/lvs/modexp_lvs_report.json
```

The exact requests, the power-bearing cross-check and the `VPB` evidence are in
`verification/records/drc-lvs/artifacts/20261027-030000-1c651cc/`.

## Documented scope of this comparison

- **Cell-instance granularity, not transistor-level.** Every standard cell is
  an opaque, pin-only black box on both sides; the transistors inside each cell
  are foundry-qualified, unmodified `sky130_fd_sc_hd` library cells and are not
  what this comparison checks.
- **Reference is the as-built (post-route) netlist** written by `klt
  place-and-route` for the same run as the GDS, so CTS buffers, antenna diodes
  and resized cells are on both sides. Layout-side net *names* come from the
  DEF (`--def-net-names --def-pins`), so net-name agreement is not independent
  evidence by itself; the connectivity comparison is.
- **`counts.{nets,pins}.matched` are scoped across the whole compared
  hierarchy**, not to the top-level I/O pins
  ([klayout-tools#1887](https://github.com/2AMLogic/klayout-tools/issues/1887);
  `verification/records/drc-lvs/records/20260915-131549-c87a304.md`).
- **Two engines**: `klayout` (`NetlistComparer`) is the committed verdict;
  netgen concurs only on the power-bearing SPICE form (above).

## History

Earlier stages, newest first. Each has a dated evidence record under
`verification/records/drc-lvs/records/`; none of that evidence is edited. The
narrative that used to be stacked in this file is in git history
(`git log -- layout/lvs/README.md`).

| Issue / date | Result | Record | Decision |
|---|---|---|---|
| #194, 2026-10-16 | Regenerated with the pinned klt `0.6.0+gdac2b5da`: `power_connectivity` measured `mismatch` (`VPB` on 26 nets); T1 item 4 `unmet`. Cause later shown to be an extraction artifact of that klt build. Superseded files: `verification/records/drc-lvs/artifacts/20261016-010000-713829b/superseded-layout-lvs/`. | `20261016-010000-713829b` | `0010` |
| #131 / #139, 2026-09-23 | First `gate-level-verilog` reference against the frozen pre-CTS synthesis netlist: 12 errors (was 17), all P&R-inserted or resized cells the pre-CTS reference cannot model; `power_connectivity` `match`; netgen second engine run (`mismatch`). Item 4 stays `unmet` for that pin. | `20260923-062424-7d0dd52` | `0006` |
| #92, 2026-09-15 | Confirmed `counts.pins.matched` scope (hierarchy-wide, 333/333 was not a top-level pin match). | `20260915-131549-c87a304` | — |
| #81 / #83 / #86, 2026-09-11 to 09-15 | Tapcell/PDN/filler GDS: `plain-element` mismatches 15 → 17 (5 new physical-only types); extraction regenerated with `--def-pins`; committed report caught up with the narrative. | `20260911-053500-d5e43d3`, `20260911-053520-d5e43d3` | — |
| #55, 2026-08-16 | First as-built reference, against a fresh (non-identical) P&R rebuild: 1324 mismatches attributed to extraction net-name correlation and deck coverage. | `20260816-174310-5e656e5` | — |
| #8, 2026-08-15 | First cell-level LVS (`klt extract --abstract-cells`, klayout-tools#620/#622) against the pre-CTS synthesis netlist as hand-built SPICE: 15 `topology` mismatches, fully attributed to 35 CTS/timing inserted instances and 5 resizes. | `20260815-013937-fa169a4` | — |

The **control leg** is the original `plain-element` request (reference
`layout/lvs/modexp_reference.spice`, form omitted). It was last run against the
#131-era layout netlist, where it reproduced 17 mismatches; the committed
`modexp_layout_abstracted.spice` is now regenerated from the current GDS, so
that count describes the earlier layout, not this one. Its frozen inputs and
outputs are under `verification/records/drc-lvs/artifacts/20260923-062424-7d0dd52/`.
