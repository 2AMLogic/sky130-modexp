# layout

The routed DEF and merged GDS produced by `klt place-and-route` against
`flow/par-modexp.json` — the nominal `sky130_fd_sc_hd` / `tt_025C_1v80`
corner, 100 MHz clock constraint, `seed: 42`, `target_stage: "route"`. See
`flow/README.md` for the cold-start recipe that reproduces these files, and
`verification/records/place-and-route/` for the measurement (area,
utilization, wirelength, timing, power) these artifacts back — this
directory holds the layout artifacts, not the evidence record itself.

## Contents

- `modexp.def` — the routed DEF `klt place-and-route`'s `route` stage wrote
  (`write_def`).
- `modexp.gds` — the same layout merged with the resolved
  `sky130_fd_sc_hd` standard-cell GDS views (`klt`'s in-process
  `klayout.db`-based DEF→GDS merge — never a `klayout` subprocess).

## Provenance

| Field | Value |
| --- | --- |
| `klt` version | 0.4.0 |
| `klt` git revision | [`f77036bff1eaf97b992e121acd702a98519142fb`](https://github.com/2AMLogic/klayout-tools/commit/f77036bff1eaf97b992e121acd702a98519142fb) (`docs/environment.md`) |
| OpenROAD build | `26Q3-1260-g06a5a02279` (`openroad -version`, via the pinned `openroad/orfs:26Q3-296-gda37dce1c` Docker image — `docs/environment.md`) |
| sky130A PDK | `open_pdks` commit `c6d73a35f524070e85faff4a6a9eef49553ebc2b` |
| Deck | `sky130_fd_sc_hd__tt_025C_1v80`, content_hash `sha256:8e78e14442062dba34d414fca6490b2f6b96038d4510d1438ca44fee31487135` |
| Input netlist | `flow/.klt/synthesize/modexp_synth_tied.v` (the tie-cell-patched synthesis output — see `flow/README.md`'s "Known upstream gaps"), content_hash `sha256:67a218e16cf51e4f3010e5f87404b829f0574d9765b2569278abd54a4fdc7486` (unchanged — no RTL/synthesis change) |
| `seed` | 42 |
| Design git revision | `d5e43d3ba64ad967a9d35fd4c2907b4ef8df8961` (parent commit this layout was produced against) |

**Updated by issue #81** (2026-09-11): `flow/par-modexp.json` gained a
`power` block (`request.power`) driving `klt place-and-route`'s tapcell +
PDN + filler-cell insertion — see "What this GDS does *not* contain" below
for what changed and `verification/records/place-and-route/records/20260911-052542-d5e43d3.md`
for the full measurement, superseding
`verification/records/place-and-route/records/20260814-203901-c741877.md`
for this single-corner recipe. The `floorplan`/`io`/`constraints`/`seed`
blocks of `flow/par-modexp.json` are byte-identical to that superseded
record's — only the new `power` block is additive.

The full per-corner measurement (area, utilization, wirelength, WNS, TNS,
Fmax, setup/hold violation counts, estimated power) is recorded under
`verification/records/place-and-route/`, including the raw `klt
place-and-route` JSON envelope as a frozen artifact.

## What this GDS does *not* contain

**Updated by issue #81**: `klt place-and-route`'s `request.power` field
(added upstream by [klayout-tools#1120](https://github.com/2AMLogic/klayout-tools/pull/1120))
now drives real **tapcell insertion, power-grid (PDN) generation, and
filler-cell insertion** — `flow/par-modexp.json`'s `power` block enables
all three via one `tapcell`/`pdngen`/`filler_placement` pipeline. **Still
absent**: metal (density) fill (a separate OpenROAD `add_fill`-class pass
over the routing layers for CMP density rules — `request.power` inserts
standard-cell row fillers, not routing-layer density fill) and
`DONT_USE_CELLS` exclusion, both unrelated to this issue's change. This is
evidence toward `spec/modexp.md` Decision 2 (clock target) and Decision 4
(area target)'s revisit triggers, **not** yet a fully signoff-ready macro —
DRC is now clean against this GDS (see "Signoff status" below), but LVS is
not, and metal fill / `DONT_USE_CELLS` remain open items for a future
issue.

## Signoff status (#8, updated #79, #81)

DRC and LVS have been run against this GDS — see `docs/signoff-claim.md`
for the single authoritative claim. Verdict: `spec/modexp.md`'s Signoff row
is **not met** (both DRC and LVS must be clean; LVS is not), stated
plainly. **DRC is now clean, 0 violations** — issue #81's tapcell/PDN/
filler-cell insertion closed all 234 previously-classified
`nwell.space.1`/`nwell.width.1` violations (`layout/drc/`). LVS still
reports `status: "mismatch"` (17 mismatches, up from 15 — fully attributed
to 5 new physical-only cell types this issue's own `power` block adds, plus
ordinary CTS/timing/antenna-fixup churn; not a new mismatch category) —
see `layout/lvs/` and `docs/signoff-claim.md` for the full classification.
