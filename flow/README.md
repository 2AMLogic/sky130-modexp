# flow

Synthesis and place-and-route recipes (Yosys, OpenROAD), driven through
`klt`. Two committed request documents, run in sequence:

1. `synthesize-modexp.json` — `klt synthesize` (Yosys), unconstrained,
   reproducing `docs/baseline.md`'s 682-cell figure byte-for-byte.
2. `par-modexp.json` — `klt place-and-route` (OpenROAD), the nominal-corner
   (`tt_025C_1v80`), 100 MHz-constrained floorplan → place → cts → route run
   whose artifacts land in `layout/` and whose measurements are recorded
   under `verification/records/place-and-route/`.

## Cold start

```bash
./scripts/setup-env.sh          # provisions klt, sky130A (volare), openroad
source .venv/bin/activate

# 1. Synthesize (unconstrained, reproduces docs/baseline.md's 682 cells)
PDK=sky130A klt synthesize flow/synthesize-modexp.json --format json

# 2. Work around klayout-tools#854 (see "Known upstream gaps" below) --
#    turns the synthesized netlist's bare constant-tie literals into a real
#    sky130_fd_sc_hd__conb_1 tie-cell instance, which OpenROAD's router can
#    route (the untouched netlist fails detailed_route with DRT-0305).
python3 flow/tie_constants.py \
  flow/.klt/synthesize/modexp_synth.v \
  flow/.klt/synthesize/modexp_synth_tied.v

# 3. Place and route (nominal corner, 100 MHz, seed pinned in the request)
PDK=sky130A klt place-and-route flow/par-modexp.json --format json
```

Step 3's artifacts land in `flow/.klt/place-and-route/` (gitignored scratch,
like every other `klt` working directory — see `.gitignore`'s `.klt/`
entry): `modexp.def` / `modexp.gds`, one `pnr_modexp_<stage>.tcl` script and
`<stage>.odb` checkpoint per stage, and the per-stage `-metrics` JSON dumps.
The committed copies of the routed DEF/GDS (with their provenance) live in
`layout/`; the measurement is recorded under
`verification/records/place-and-route/`.

## Re-running a single corner, or the full ratified corner set

`flow/par-modexp.json` is pinned to the nominal corner
(`tt_025C_1v80`) that Decision 2 of
`spec/decision-records/0001-input-domain-interface-and-corner-matrix.md`
holds the 100 MHz Phase 2 target to. `flow/run-corner-sweep.sh` runs the
*same* floorplan/IO/clock/seed request at every corner in that record's
Decision 4 corner matrix (all eighteen installed `sky130_fd_sc_hd` liberty
corners), or at whichever corner names you pass it:

```bash
./flow/run-corner-sweep.sh                     # all 18 ratified corners
./flow/run-corner-sweep.sh tt_025C_1v80         # just the nominal corner
./flow/run-corner-sweep.sh ss_100C_1v40 ff_100C_1v65   # a named subset
```

Each corner gets its own `flow/corners/<corner>/` scratch directory (request
JSON + `klt` output, gitignored) so runs never clobber each other. The
aggregated summary lands at `flow/corner-sweep-results.json` (also
gitignored — regenerate on demand; the frozen evidence lives under
`verification/records/place-and-route/artifacts/`).

**Cost**: each corner is an independent full `floorplan → place → cts →
route` OpenROAD run — there is currently no `klt` capability to re-time an
already-routed design at a different corner without rebuilding it (see
"Known upstream gaps" below) — so the full 18-corner sweep takes on the
order of an hour or more (each corner run measured at roughly 5–10 minutes
in this environment: Docker Desktop's `linux/amd64` emulation on a macOS/
arm64 host, see `docs/environment.md`).

## What this flow does *not* produce

Per `klt place-and-route`'s own documented scope, the routed DEF/GDS this
flow produces has: **no tapcell insertion, no power-grid (PDN) generation,
no metal fill, no filler-cell insertion, and no `DONT_USE_CELLS`
exclusion** — core-only floorplanning, no IO ring. It is evidence toward
Decision 2/4's revisit triggers (`spec/modexp.md`), not a signoff-ready
macro; DRC/LVS-clean signoff on this GDS is a later issue's job.

## Known upstream gaps (friction protocol, `CLAUDE.md`)

Both gaps below are already filed and **fixed upstream** at
`2AMLogic/klayout-tools`, but in commits later than this repo's pinned `klt`
revision (`docs/environment.md`: `af5791b557fc7c669c3981335a294256ccf37e6f`,
2026-08-04) — so this repo still needs the local workarounds below until
that pin is bumped past both fixes (tracked as a natural follow-up, not
undertaken by this issue: bumping a pinned tool revision that every existing
evidence record's `provenance.klt_version` cites is its own decision, out of
this issue's scope).

- **`klt synthesize` emits unroutable bare constant-tie literals**
  ([klayout-tools#854](https://github.com/2AMLogic/klayout-tools/issues/854),
  fixed by [klayout-tools#864](https://github.com/2AMLogic/klayout-tools/pull/864),
  merged 2026-08-12). `rtl/modexp.v`'s zero-extension of the reduction
  datapath (`mm_p2`/`mm_m1`/`mm_m2`) constant-propagates through Yosys's
  `synth`/`abc` passes to a bare `1'h0`/`2'h0` Verilog literal in the mapped
  netlist. OpenROAD's `link_design` accepts that literal as an implicit,
  unnamed net without complaint, but `detailed_route` (TritonRoute)
  classifies it as an inferred power/ground *special* net and refuses to
  route it (`[ERROR DRT-0305] Net zero_ of signal type GROUND is not
  routable by TritonRoute`) — four stages after the netlist that caused it,
  with no pointer back to the actual cause. `flow/tie_constants.py` is the
  local, interim substitute for the now-merged upstream fix: it rewrites
  every bare literal into a reference to a real
  `sky130_fd_sc_hd__conb_1` tie-cell instance, bit by bit, before the
  netlist reaches `klt place-and-route`.
- **No multi-corner timing sweep in `klt place-and-route`**
  ([klayout-tools Epic #700](https://github.com/2AMLogic/klayout-tools/issues/700)
  Phase 3, [klayout-tools#949](https://github.com/2AMLogic/klayout-tools/issues/949),
  fixed by [klayout-tools#955](https://github.com/2AMLogic/klayout-tools/pull/955),
  merged 2026-08-14). At this repo's pinned revision, one `klt
  place-and-route` request resolves exactly one liberty corner
  (`request.pdk.corner`) and there is no way to re-run only the post-route
  STA stage against an already-routed design at a different corner —
  `report_worst_slack_metric -setup` has no `-hold` counterpart either, so
  there is no `worst_hold_slack_ns` field at all pre-#955. `flow/run-
  corner-sweep.sh`'s N-independent-full-builds approach is the local,
  interim substitute for the now-merged upstream native sweep (which does
  this in one OpenSTA session against one physical build, and adds the
  missing hold-slack field) — expect a large wall-clock/engineering-cost
  reduction once this repo's pin moves past #955.

Also fixed in the same window, load-bearing for this run but owned by this
repo rather than `klayout-tools`: `scripts/openroad-docker.sh` (from issue
#13) originally bind-mounted the host working directory at a fixed
container-internal `/workspace`, which works for a relative-path-only
script but silently breaks any `klt place-and-route` run, since every stage
script `klt` generates bakes in **absolute host paths** (the netlist, the
LEF/liberty deck — which for the PDK lives *outside* the repo entirely at
`~/.volare` — and every stage's `write_db`/`write_def`/`-metrics` output
path). This issue's PR fixes the wrapper to bind-mount both the repo tree
and the resolved PDK root at their own identical absolute paths, so those
paths resolve the same way inside the container as they do on the host; see
that script's own header comment for the detail. `scripts/openroad-smoke-
test.sh`'s fixture (`scripts/openroad-smoke/smoke.tcl`) was updated to use
relative paths accordingly.

### Gaps found by the post-route gate-level re-simulation (issue #9)

Three further gaps, same format and same friction protocol, found while
re-running the bit-exact suite against a gate-level netlist of the routed
layout (`verification/gate-level/`). Unlike the two above, these are **not**
yet fixed upstream:

- **`klt place-and-route` has no post-route netlist or SDF export.** Its
  response contract carries `def_path` and `gds_path` only — verified
  directly against the pinned install. The netlist half is
  [klayout-tools#996](https://github.com/2AMLogic/klayout-tools/issues/996)
  (filed by #8, **fixed** by
  [#997](https://github.com/2AMLogic/klayout-tools/pull/997), merged
  2026-08-15 — later than this repo's pin, and in any case describing a
  *re-run* of P&R rather than the committed `layout/modexp.gds`). The SDF
  half is [klayout-tools#1002](https://github.com/2AMLogic/klayout-tools/issues/1002)
  (open), which also covers the missing `options.sdf` on `klt
  functional-verification`. **This is what blocks delay-annotated
  (per-corner) gate-level simulation entirely.** Local substitute for the
  netlist half: `verification/gate-level/spice_to_verilog.py`, which derives
  the netlist from #8's `klt extract --abstract-cells` output — see
  `verification/gate-level/README.md`. There is no local substitute for the
  SDF half.
- **`klt functional-verification` has no compile-time defines / build-args
  field** ([klayout-tools#1001](https://github.com/2AMLogic/klayout-tools/issues/1001),
  open), so a PDK's `` `ifdef ``-gated Verilog cell library
  (`USE_POWER_PINS`, `FUNCTIONAL`, `UNIT_DELAY`) cannot be selected through
  the request. Local substitute: `verification/gate-level/sky130_fd_sc_hd_sim_defines.v`,
  listed first in `request.sources` so its `` `define ``s are in effect for
  every later source in the same compilation unit.
- **`klt functional-verification` requires the cocotb testbench module to sit
  next to the request document**
  ([klayout-tools#1003](https://github.com/2AMLogic/klayout-tools/issues/1003),
  open), so one unmodified testbench cannot serve several requests. Local
  substitute: `verification/gate-level/test_modexp.py` is a git **symlink**
  to `../test_modexp.py`, never a copy — copying would have destroyed the
  property the gate-level run exists to demonstrate.

Also filed, environment- rather than klt-shaped:
[klayout-tools#1004](https://github.com/2AMLogic/klayout-tools/issues/1004) —
the accepted SDF re-simulation recipe is conditional on Icarus >= 13, and
Icarus 12.0 (what the current Debian/Ubuntu archive ships) cannot simulate
`ifdef`-gated standard-cell *timing* models at all.
