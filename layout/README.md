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
| `klt` version | 0.2.0 |
| `klt` git revision | [`af5791b557fc7c669c3981335a294256ccf37e6f`](https://github.com/2AMLogic/klayout-tools/commit/af5791b557fc7c669c3981335a294256ccf37e6f) (`docs/environment.md`) |
| OpenROAD build | `26Q3-1260-g06a5a02279` (`openroad -version`, via the pinned `openroad/orfs:26Q3-296-gda37dce1c` Docker image — `docs/environment.md`) |
| sky130A PDK | `open_pdks` commit `c6d73a35f524070e85faff4a6a9eef49553ebc2b` |
| Deck | `sky130_fd_sc_hd__tt_025C_1v80`, content_hash `sha256:8e78e14442062dba34d414fca6490b2f6b96038d4510d1438ca44fee31487135` |
| Input netlist | `flow/.klt/synthesize/modexp_synth_tied.v` (the tie-cell-patched synthesis output — see `flow/README.md`'s "Known upstream gaps"), content_hash `sha256:67a218e16cf51e4f3010e5f87404b829f0574d9765b2569278abd54a4fdc7486` |
| `seed` | 42 |
| Design git revision | `c741877543658a0974a8a90f07cd4b37a7da4aa1` (parent commit this layout was produced against) |

The full per-corner measurement (area, utilization, wirelength, WNS, TNS,
Fmax, setup/hold violation counts, estimated power) is recorded under
`verification/records/place-and-route/`, including the raw `klt
place-and-route` JSON envelope as a frozen artifact.

## What this GDS does *not* contain

Per `klt place-and-route`'s documented scope (v1): **no tapcell insertion,
no power-grid (PDN) generation, no metal fill, no filler-cell insertion, and
no `DONT_USE_CELLS` exclusion** — floorplanning is core-only, with no IO
ring. This is evidence toward `spec/modexp.md` Decision 2 (clock target)
and Decision 4 (area target)'s revisit triggers, **not** a signoff-ready
macro — DRC/LVS-clean signoff on this GDS is a later issue's job (see
`spec/decision-records/0001-...`'s T1 evidence mapping, items 3/4).
