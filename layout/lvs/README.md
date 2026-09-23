# layout/lvs

LVS evidence for the routed GDS (`layout/modexp.gds`, from #7) — see
`docs/signoff-claim.md` for the overall claim and the comparison level this
establishes.

## Update (issue #131, 2026-09-23): the comparison now runs against a
## `gate-level-verilog` reference — power connectivity verified, filler/tap
## cells pruned by the tool, second engine run; **still `mismatch` (12
## errors, was 17)**. Read this first.

**The headline has not changed: `klt lvs` reports `status: "mismatch"`, so
T1 item 4 is still `unmet` and `spec/modexp.md`'s Signoff row is still not
met.** What changed is that three things the previous comparison could not
answer are now answered, and the residue is smaller and entirely one
named cause.

### What changed

`klt lvs` grew a `reference.form: "gate-level-verilog"` surface
(`docs/cli/lvs.md`) that reads a gate-level Verilog netlist directly as the
LVS reference, instead of the hand-built SPICE reference
`build_reference_netlist.py` produces. Two capabilities exist **only** on
that form, and both are exactly what the sections below spent two issues
describing as structurally unreachable:

- **`topology.power_only_pruned`** — the compare removes every layout-side
  circuit whose *every* declared pin is a power/ground pin of the reference
  library, and every instance of it, **before** `NetlistComparer` runs, and
  emits a `severity: "warning"` `mismatches[]` entry naming each one. For
  this block that is exactly the five physical-only masters the sections
  below classify by hand: `sky130_fd_sc_hd__tapvpwrvgnd_1` and
  `__fill_{1,2,4,8}`. They are no longer 5 of the 17 mismatches — they are
  a disclosed, auditable line in the report. This is klt's own rule, keyed
  off the PDK library's pin-order data, not a filter this repo applied.
- **`power_connectivity`** — a separate verdict block beside `status`,
  which every other `reference.form` reports as `"unchecked"` (a
  power-bearing SPICE reference has its power nets compared as ordinary
  connectivity, so the check does not apply). **It now reports
  `status: "match"` over all 3074 placed instances**, zero findings.

The comparison is otherwise the same one: the same committed, unchanged
`layout/modexp.gds`, the same committed, unchanged
`modexp_layout_abstracted.spice` extracted from it, and the same frozen,
pre-CTS `klt synthesize` netlist on the reference side.

### The numbers

| Leg | Engine | Reference form | `status` | `mismatch_count` | `error_count` | `power_connectivity` |
|---|---|---|---|---|---|---|
| control | `klayout` | `plain-element` (the old one) | `mismatch` | 17 | 17 | `unchecked` |
| **committed** | `klayout` | `gate-level-verilog` | `mismatch` | 13 | **12** | **`match`** |
| cross-check | `netgen` 1.5.133 | `gate-level-verilog` | `mismatch` | 3 | 2 | **`match`** |

The control leg — the old `plain-element` comparison, re-run unchanged on
the current `klt` pin — reproduces **17** exactly, so the whole 17 → 12
change is the reference form, not tool drift.

Of the committed leg's 13 `mismatches[]` entries, 12 are `severity:
"error"` and 1 is the `topology.power_only_pruned` disclosure warning.

### What the 12 remaining errors are

All 12 are `"circuit could not be matched to a counterpart"`, and all 12
are the P&R logic transform the pre-CTS reference cannot model:

- **10 `side: "layout"`** — `BUF_4`, `BUFINV_16`, `CLKINV_2`, `CLKINV_4`,
  `INV_1`, `INV_6`, `NOR2_2` (CTS/timing-fixup insertions), `DIODE_2`
  (antenna fixup), `O21AI_2`, `O22AI_2` (post-resize drive strengths).
- **1 `side: "reference"`** — `O22AI_1`, the pre-resize drive strength the
  routed layout no longer instantiates.
- **1 `side: "both"`** — the top `MODEXP` circuit, cascading from the above.

Still zero `net.split` / `net.merged` / `device.*` on the klayout engine.
Note `DIODE_2` is **not** pruned even though it is a physical-only fixup
cell: its PDK pin list includes a non-power `DIODE` pin, and klt's prune
stops exactly where the evidence does — an un-pruned cell costs a reported
mismatch, a wrongly-pruned one would mask a real defect.

### What `power_connectivity: "match"` does and does not say

```json
"power_connectivity": {
  "status": "match",
  "power_pins": ["VGND", "VPB", "VPWR"],
  "power_pins_derivation": { "rule": "declared-by-every-instantiated-master",
                             "master_count": 47, "corroborated": true },
  "instance_count": 3074,
  "findings": [], "finding_count": 0
}
```

- **It is a per-instance pin-to-net consistency verdict**: every master's
  `VGND`/`VPB`/`VPWR` pin reaches the same net every other instance's
  same-named pin reaches, across all 3074 placed instances, with no
  `power.inconsistent_pin_net` / `power.unexpected_pin_net` /
  `power.unconnected_pin` finding.
- **The 2352 physical-only instances are inside this verdict, not excluded
  from it.** The check runs *before* the filler/tap prune, by design —
  power connectivity is the only thing about a tapcell or filler any check
  can verify, so pruning first would have thrown away the answer.
- **It is not geometric rail continuity and not an IR-drop result.**
  Whether a rail is an unbroken island is `klt erc`'s question — see
  `layout/erc/` for this block's supply-island evidence — and current-carrying
  capacity is `klt power`'s. A reader must not upgrade this to "the power
  grid is verified".
- **`VNB` is absent from the derived pin universe** because the committed
  abstracted extraction resolved no `VNB` pin on any master (zero
  occurrences in `modexp_layout_abstracted.spice`). That is an
  extraction-coverage fact, disclosed here rather than read as a clean
  verdict on a pin nothing checked.

`body_verification.status` is `"unchecked"` in both legs, for the reason
klt states: the pre-extracted `layout.netlist` request form carries no
extraction deck, so nothing can tell a drawn body tie from a synthesized
one. Recorded as `"unchecked"`, never as `"verified"`.

### Second-engine cross-check: run, and it concurs

`docs/signoff-claim.md` previously recorded *"Second-engine cross-check (T1
item 4): not run."* It has now been run:
`layout/lvs/modexp_lvs_report_netgen.json` is the identical request with
`"engine": "netgen"`, against netgen 1.5.133.

**netgen also reports `mismatch`.** It fails differently, which is the
interesting part: where `NetlistComparer` stops at the circuit-type level,
netgen proceeds to instance/net partitioning and reports `device.unmatched`
+ `net.unmatched`. Its raw side-by-side fragments (embedded verbatim in
`mismatches[].details.raw`) show why — every layout-side instance carries
`VGND`/`VPB`/`VPWR` terminals the signal-only gate-level reference has no
counterpart for, so netgen's fanout-class refinement cannot converge. The
two engines **agree on the verdict and disagree on the diagnosis**, which
is the honest form of a cross-check: it rules out "one toolchain agreeing
with itself" as the explanation, and independently confirms nothing here is
silently passing.

### Two disclosed deviations, both upstream tool gaps

1. **The reference netlist is a mechanically rewritten copy.** `klt lvs`'s
   Verilog reader accepts only a plain `assign <net> = <net>;` and rejects
   a concatenation right-hand side. `modexp_synth_tied.v` carries exactly
   three, all Yosys's normal rendering of a vector assignment.
   `expand_concat_assigns.py` expands those three into 52 per-bit plain
   `assign`s and copies every other line through byte for byte; the result
   is committed as `modexp_synth_expanded.v`. Verified: every non-`assign`
   line of the two files is identical, and all three rewritten nets
   (`mm_p2`, `mm_m1`, `mm_m2`) are **dead** in the frozen netlist — zero
   bit-select references from any cell instance — so the expansion cannot
   change the compared connectivity even in principle. The frozen evidence
   file under `verification/records/` is not edited. Filed upstream,
   generically:
   [klayout-tools#2372](https://github.com/2AMLogic/klayout-tools/issues/2372).
2. **The netgen binary was reached through a `PATH` shim.** `klt lvs`
   invokes the netgen engine as the literal name `netgen`; Ubuntu's
   `netgen-lvs` package installs it as `/usr/bin/netgen-lvs`. The binary is
   the stock distribution build, unpatched. Filed upstream, generically:
   [klayout-tools#2373](https://github.com/2AMLogic/klayout-tools/issues/2373).

### What would make this `status: "match"` — and why it is not done here

The reference would have to be the **as-built** post-route netlist (CTS
buffers, antenna diodes and resized cells included), not the pre-CTS
synthesis netlist. Every one of the 12 remaining errors is a cell the
router inserted or resized; none is a connectivity defect.

`klt place-and-route` did write that netlist for the run that produced the
committed layout —
`verification/records/place-and-route/artifacts/20260911-052542-d5e43d3/par-nominal-output.json`
records a `verilog_path` alongside the `def_path`/`gds_path` — **but only
the DEF and the GDS were committed from that run**, and issue #55
established that re-running `klt place-and-route` against the identical
frozen netlist/floorplan/seed does *not* reproduce `layout/modexp.gds` (722
vs 718 instances). So no as-built netlist for *this* GDS exists in the tree
and none can be regenerated.

Deriving one from `layout/modexp.def` is possible but deliberately **not**
done here: the layout-side extraction already takes its net *names* from
that same DEF (`--def-net-names --def-pins`, see the issue #83 note below),
so the resulting `match` would sound far stronger than the comparison
actually is. Tracked as
[sky130-modexp#139](https://github.com/2AMLogic/sky130-modexp/issues/139)
rather than forced into this pass — which also carries the
independently-worthwhile half: **`flow/` should commit
`par-nominal-output.json`'s `verilog_path` artifact on every P&R run**, the
way it already commits the DEF and the GDS. Discarding it is what turned a
one-command LVS reference into a blocked issue.

### Reproducing this comparison cold

```bash
# 1. Rebuild the expanded reference from the frozen synthesis netlist
python3 layout/lvs/expand_concat_assigns.py \
  verification/records/place-and-route/artifacts/20260814-203901-c741877/modexp_synth_tied.v \
  layout/lvs/modexp_synth_expanded.v

# 2. The committed comparison (run from the repository root, so the
#    report's echoed paths stay repo-relative)
klt lvs '{"schema":"klt.lvs.request/1","engine":"klayout",
  "layout":{"netlist":"layout/lvs/modexp_layout_abstracted.spice","top":"modexp"},
  "reference":{"netlist":"layout/lvs/modexp_synth_expanded.v","top":"modexp",
               "form":"gate-level-verilog","library":"sky130_fd_sc_hd","pdk":"sky130A"}}' \
  --format json > layout/lvs/modexp_lvs_report.json

# 3. The second-engine cross-check (same request, "engine": "netgen").
#    On Debian/Ubuntu, shim the binary name first — see klayout-tools#2373:
mkdir -p /tmp/netgen-shim && ln -sf "$(command -v netgen-lvs)" /tmp/netgen-shim/netgen
PATH=/tmp/netgen-shim:$PATH klt lvs '{… same request, "engine":"netgen" …}' \
  --format json > layout/lvs/modexp_lvs_report_netgen.json

# 4. Verify a committed report still describes its own inputs
klt lvs --check layout/lvs/modexp_lvs_report.json
```

Full evidence, per-leg detail and provenance:
`verification/records/drc-lvs/records/20260923-062424-7d0dd52.md`.

**Everything below this section is retained history**, describing the
`plain-element` comparison this section supersedes for freshness. Its
17-mismatch result is still reproducible and is committed as the control
leg in that record's artifacts; `modexp_reference.spice` and
`build_reference_netlist.py` are left in place unchanged (the latter is
also the sibling of `verification/gate-level/spice_to_verilog.py`, whose
own pipeline is unaffected by this issue).

## Update (issue #81, 2026-09-11): re-run against the tapcell/PDN/filler-cell
## GDS — still `mismatch`, count grew from 15 to 17 for a fully-attributed
## reason, read this first

Issue #81 added `request.power` (tapcell + PDN + filler-cell insertion) to
`flow/par-modexp.json` and regenerated `layout/modexp.def`/`layout/modexp.gds`
(closing all 234 previously-open `nwell` DRC violations, see
`layout/drc/README.md`). This section documents a **fresh** re-run of the
same extraction/reference/comparison methodology issue #8's original
comparison used (below), against the **new** GDS — not the "fresh
self-consistent build" methodology issue #55 introduced (further below),
which remains a separate, unrelated, still-current evidence chain against
its own independently-rebuilt reference.

**Result: still `status: "mismatch"`, now 17 mismatches (was 15), 100%
`category: "topology"`, `"circuit could not be matched to a counterpart"`
— no new mismatch category, `net_correspondence` still 333 entries
(reported identically as `counts.nets.matched`/`counts.pins.matched` —
see "Result" below and issue #92's confirmed root cause) unchanged.**
Fully attributed, by the same direct instance-by-instance DEF-vs-Verilog
accounting issue #8's comparison used: of `layout/modexp.def`'s new 3074
`COMPONENTS`, 718 remain logic-bearing (excluding `TAP_*`/`FILLER_*`/
`ANTENNA_*` physical-only instances) — 680 present under an identical
instance name and cell type vs. the same, unchanged frozen synthesis
netlist, 3 resized, 35 new CTS/timing/antenna-fixup insertions, 0
synthesis instances missing. The other 2356 instances are this issue's own
new physical-only cells (265 tapcells + 2087 fillers + 4 antenna-fixup
diodes) — by construction, none has a synthesis-side counterpart. `klt
lvs`'s 15 `side: "layout"` unmatched circuit types are exactly: 6
CTS/timing-fixup-only types + 1 antenna-fixup type + 3 post-resize types +
the 5 new physical-only types (`sky130_fd_sc_hd__tapvpwrvgnd_1`,
`__fill_1`, `__fill_2`, `__fill_4`, `__fill_8`); the 1 `side: "reference"`
unmatched type is the same pre-resize `sky130_fd_sc_hd__o22ai_1` the
superseded comparison found. Full narrative, per-type detail, and the
`write_verilog -remove_cells` scoping finding (this repo's own LVS
methodology extracts directly from the GDS, a code path that flag does not
touch, so the 5 new physical-only types are **not** automatically filtered
and require the same manual classification as ordinary CTS-buffer
insertions):
`verification/records/drc-lvs/records/20260911-053500-d5e43d3.md` (and its
twin, `20260911-053520-d5e43d3.md`).

**A separate, unattempted finding, not part of this comparison**: this
issue's new, PDN-equipped `layout/modexp.gds` gives `klt extract` a
genuine top-level `VDD`/`VSS` pin pair for the first time (a real,
continuous power net now reaches the die boundary). `layout/lvs/`'s
committed `modexp_layout_abstracted.spice`/`modexp_layout_extract_report.json`
below are **deliberately left unchanged** (still describing the *pre*-#81,
no-PDN GDS) because `verification/gate-level/`'s own gate-level-simulation
pipeline (a separate claim, `docs/baseline.md#post-route-gate-level-simulation`)
regenerates its simulated netlist directly from these same two files, and
`verification/gate-level/spice_to_verilog.py`'s netlist-derivation
validator — written before any GDS in this repo had a PDN — rejects the
new `VDD`/`VSS` top-level pins as validation errors rather than recognizing
them as legitimate power ports. Regenerating these two files (and the
gate-level-sim pipeline that depends on them) for the new, PDN-equipped GDS
is tracked as a dedicated follow-up, explicitly out of issue #81's own
DRC/LVS-focused scope: [sky130-modexp#83](https://github.com/2AMLogic/sky130-modexp/issues/83).

## Update (issue #83, 2026-09-11): the two files above are now regenerated
## — LVS-neutral, read this if you came from the paragraph above

Issue #83 taught `verification/gate-level/spice_to_verilog.py` to recognize
`VDD`/`VSS` as real top-level power ports and regenerated
`modexp_layout_abstracted.spice`/`modexp_layout_extract_report.json` against
the current, PDN-equipped `layout/modexp.gds` (content_hash unchanged from
the issue #81 record above, `sha256:9fa0dbe1...`). One refinement was needed
beyond the recipe the paragraph above and issue #81's own record cite:
without `klt extract`'s `--def-pins <path-to-def>` (issue #1390 upstream),
an unrestricted `--def-net-names` extraction over-promotes every internal,
DEF-net-named net to top-level-pin status (`pin_count` 756, not the correct
70 — the real 68 functional I/O + `VDD`/`VSS`) — `--def-pins
../modexp.def` restricts pin promotion back to the DEF's own genuine
`PINS` section, exactly as upstream's docs prescribe for this scenario.
**This is a metadata-only refinement, not a connectivity change**: the two
extractions' `X`-card instance bodies are byte-identical with or without
`--def-pins` (verified directly, diffed sorted), so this does **not**
reopen or alter this section's own LVS mismatch-count claim above (17
mismatches) — that comparison's own connectivity graph is unchanged.
`verification/gate-level/README.md` and
`verification/records/gate-level-sim/` carry the regenerated Leg 1 result;
this page's own LVS narrative above is untouched.

## Update (issue #86, 2026-09-15): `modexp_lvs_report.json` is now the
## post-#81 run it describes — the artifact caught up with the narrative

Until this issue, the two sections above described the 17-mismatch post-#81
result while the **committed `modexp_lvs_report.json` was still the original
2026-08-14 run** (15 mismatches, `layout`/`reference` paths pointing at a
`/tmp/issue8/` scratch directory). A reader who opened the JSON rather than
the prose got a stale answer. Issue #86 re-ran the comparison against the
current committed netlist pair and overwrote the report, so the artifact and
the prose now agree.

The re-run **reproduces the recorded result exactly** — it is a
confirmation, not a new finding, so no new evidence record is minted for it
(`verification/records/drc-lvs/records/20260911-053500-d5e43d3.md` and its
twin remain the live records, unedited):

- `status: "mismatch"`, `mismatch_count: 17`, `category_counts: {"topology":
  17}` — 15 `side: "layout"` unmatched circuit types (`BUF_4`, `BUFINV_16`,
  `CLKINV_2`, `CLKINV_4`, `DIODE_2`, `FILL_1`, `FILL_2`, `FILL_4`, `FILL_8`,
  `INV_1`, `INV_6`, `NOR2_2`, `O21AI_2`, `O22AI_2`, `TAPVPWRVGND_1`), 1
  `side: "reference"` (`O22AI_1`), 1 `side: "both"` (the top circuit,
  cascading).
- `counts.nets.matched` / `counts.pins.matched` **333/333**, unchanged —
  **not** a top-level-I/O-pin match count; see "Result" below and issue
  #92 for the confirmed root cause (`klt lvs`'s `matched` tallies are
  scoped across the whole compared hierarchy, `layout`/`reference` tallies
  to the top circuit only). The layout-side `nets` (771) and `pins` (70)
  figures differ from the 2026-08-14 report's (1214 / 68) because the
  layout netlist itself was regenerated by issue #83 with
  `--def-net-names --def-pins`; that was already recorded as a metadata-only
  refinement (see the issue #83 note above) and does not change the
  comparison's own connectivity graph.
- `environment.layout_sha256` / `reference_sha256` in the new report now pin
  the *committed* `modexp_layout_abstracted.spice` /
  `modexp_reference.spice`, so a future divergence between the report and
  those inputs is detectable from the report alone.

`layout/drc/modexp-drc-report.json` was re-run at the same time as a
freshness check and is **byte-identical** to the committed copy (`status:
"clean"`, `violation_count: 0`, same deck and GDS content hashes), so it is
left untouched.

**`spec/modexp.md`'s Signoff row is unchanged by this**: LVS is still not
clean, for exactly the reasons the sections below already document.

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
  `"klayout"` (`NetlistComparer`). **Since issue #131 this is the
  `gate-level-verilog`-reference run described at the top of this page**,
  not the `plain-element` run this history section describes; the
  `plain-element` run is committed as the control leg under
  `verification/records/drc-lvs/artifacts/20260923-062424-7d0dd52/`.
- `expand_concat_assigns.py` (issue #131) — expands a gate-level Verilog
  netlist's concatenation-RHS `assign` statements into one plain
  `assign <net> = <net>;` per bit, the shape `klt lvs`'s
  `reference.form: "gate-level-verilog"` reader accepts. Mechanical and
  bit-exact; everything else in the netlist is copied through byte for
  byte. Retire it once
  [klayout-tools#2372](https://github.com/2AMLogic/klayout-tools/issues/2372)
  lands.
- `modexp_synth_expanded.v` (issue #131) — that script's output, run over
  the frozen `modexp_synth_tied.v`. The reference side of the current
  comparison.
- `modexp_lvs_report_netgen.json` (issue #131) — the second-engine
  cross-check: the identical request with `"engine": "netgen"`, against
  netgen 1.5.133. Carries netgen's own side-by-side report text verbatim
  in `mismatches[].details.raw`.

## Reproducing the comparison cold

**This is the superseded `plain-element` comparison** (issue #131 moved the
committed report onto a `gate-level-verilog` reference — see "Reproducing
this comparison cold" at the top of this page for the current invocation).
Kept because it is still the control leg, and still reproduces 17.

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
correspondences here, not only the 68 top-level I/O pins — **confirmed**,
not merely hypothesized, by issue #92's synthetic-netlist test against the
pinned `klt` revision: `counts.{nets,pins}.matched` is scoped across the
*whole* compared hierarchy, while `counts.{nets,pins}.{layout,reference}`
are scoped to the top circuit only, filed upstream as
[klayout-tools#1887](https://github.com/2AMLogic/klayout-tools/issues/1887);
see `verification/records/drc-lvs/records/20260915-131549-c87a304.md`). 15
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

**`counts.devices` (0/0/0) is not suspected of the same scope confusion**
(issue #92's stretch check, not deeply investigated): every device count
here is genuinely `0` on both `layout`/`reference` and `matched` — no
transistor-level devices exist on either side by construction (every
standard cell is an opaque pin-only black box, see "Documented scope"
above) — so, unlike `pins`, there is no nonzero `matched` figure to
misread against a smaller `layout`/`reference` figure in the first place.

**`net_correspondence`'s 333 entries are not what they might look like at a
glance.** Inspecting them (`modexp_lvs_report.json`) shows every entry is a
*local pin-name* pair (`{"layout": "A", "reference": "A", "pin": true}`,
repeated) from the 46 **matched** per-cell-type `.SUBCKT` declarations —
true, but trivially so, since `build_reference_netlist.py` reused those
declarations verbatim (see "Contents" above), so a cell type's own pin names
agree by construction, not by anything `klt lvs` discovered. This is also
why `counts.nets.matched` and `counts.pins.matched` are both exactly 333 —
issue #92's synthetic-netlist test confirmed that once the top `modexp`
circuit itself fails to match (as here), **zero** top-level net/pin
correspondence entries survive, so every remaining `net_correspondence`
entry is one of these subcircuit-local pins (`pin: true`), making the two
counts coincide by construction rather than by a tool-side field mix-up
— see `verification/records/drc-lvs/records/20260915-131549-c87a304.md`.
**None of the
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
