# flow

Synthesis and place-and-route recipes (Yosys, OpenROAD), driven through
`klt`. Two committed request documents, run in sequence:

1. `synthesize-modexp.json` — `klt synthesize` (Yosys), unconstrained,
   giving **717** instances under the pinned toolchain. `docs/baseline.md`'s
   682-cell figure was measured with klt 0.2.0 and is *not* reproduced by the
   pinned klt (see `docs/baseline.md#the-measurement` and record
   `20261015-210722-a4653a5`).
2. `par-modexp.json` — `klt place-and-route` (OpenROAD), the nominal-corner
   (`tt_025C_1v80`), 100 MHz-constrained floorplan → place → cts → route run
   whose artifacts land in `layout/` and whose measurements are recorded
   under `verification/records/place-and-route/`.

## Cold start

```bash
./scripts/setup-env.sh          # provisions klt, sky130A (ciel), openroad
source .venv/bin/activate

# 1. Synthesize (unconstrained; 717 instances under the pinned klt --
#    docs/baseline.md's 682 is the klt 0.2.0 figure)
PDK=sky130A klt synthesize flow/synthesize-modexp.json --format json

# 2. Retained no-op at the current pin (issue #308). klayout-tools#854 is
#    fixed in the pinned klt, which emits real sky130_fd_sc_hd__conb_1 tie
#    cells itself, so this finds no bare literal and copies the netlist
#    through unchanged. Still run it: flow/par-modexp.json names the
#    _tied.v path as its input (as does flow/run-corner-sweep.sh), and
#    those bytes are hashed by live evidence records. See "Known upstream
#    gaps" below.
python3 flow/tie_constants.py \
  flow/.klt/synthesize/modexp_synth.v \
  flow/.klt/synthesize/modexp_synth_tied.v

# 3. Place and route (nominal corner, 100 MHz, seed pinned in the request).
#    Use the wrapper, not bare `klt place-and-route`: it captures the DEF,
#    the GDS AND the as-built post-route netlist (`verilog_path`) into one
#    directory and fails if any of the three is missing.
flow/run-par.sh <out_dir>
```

**Commit the as-built netlist (issue #139, decision record 0006).** Every
P&R run whose DEF/GDS may be committed must commit its `verilog_path`
netlist (`modexp.v`) and the raw `par-output.json` envelope alongside them.
The run behind the current `layout/modexp.gds` wrote such a netlist but it
was left in scratch and lost, and the run cannot be reproduced (issue #55),
so that GDS has no LVS-able reference. `flow/run-par.sh` makes the capture
mechanical; do not bypass it for a run you intend to pin.

**Update (issue #232):** the committed `layout/modexp.{def,gds,v}` were
regenerated this way and the flow was shown reproducible — two sequential
`flow/run-par.sh` runs gave byte-identical outputs (record
`verification/records/place-and-route/records/20261027-013900-98bf55d.md`).
The paragraph above describes the state before that; the as-built netlist is
now committed next to the DEF and GDS.

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
*same* IO/clock/seed request at every corner in that record's Decision 4
corner matrix (all eighteen installed `sky130_fd_sc_hd` liberty corners), or
at whichever corner names you pass it. **Archived/frozen:** this script is
kept deliberately but is no longer the recommended path — `klt sta`
(`flow/run-sta-corner-sweep.sh` + `flow/sta-modexp.json`, next section) now
answers the corner question for the committed `layout/modexp.def`. See
"Both scripts are kept, deliberately" below for the frozen evidence copy.
**Floorplan note (issue #56):** the
script's `floorplan` block is no longer byte-identical to
`flow/par-modexp.json`'s — as of issue #56 it carries a revised, mapping-
only floorplan (utilization 55%, `core_margin_um` 2) explored per
`spec/decision-records/0002-slow-corner-timing-closure-and-mm-red-critical-path.md`
Decision 3's named first step, while `flow/par-modexp.json` itself is left
byte-identical to the floorplan that produced the still-current
`layout/modexp.def`/`layout/modexp.gds` (whose DRC/LVS evidence cites that
file's content hash — changing it would invalidate provenance for evidence
this issue does not own). See
`verification/records/place-and-route/` for the fresh sweep this revised
floorplan produced, and how much of the slow-corner gap it closes:

```bash
./flow/run-corner-sweep.sh                     # all 18 ratified corners
./flow/run-corner-sweep.sh tt_025C_1v80         # just the nominal corner
./flow/run-corner-sweep.sh ss_100C_1v40 ff_100C_1v65   # a named subset
```

Archived/frozen — this usage is kept for the record; `klt sta`
(`flow/run-sta-corner-sweep.sh`, next section) is the current path.

Each corner gets its own `flow/corners/<corner>/` scratch directory (request
JSON + `klt` output, gitignored) so runs never clobber each other. The
aggregated summary lands at `flow/corner-sweep-results.json` (also
gitignored — regenerate on demand; the frozen evidence lives under
`verification/records/place-and-route/artifacts/`).

**Cost**: each corner is an independent full `floorplan → place → cts →
route` OpenROAD run, so the full 18-corner sweep takes on the order of an
hour or more (each corner run measured at roughly 5–10 minutes in the
environment that record was produced on: Docker Desktop's `linux/amd64`
emulation on a macOS/arm64 host, see `docs/environment.md`).

## Multi-corner STA of the committed layout (`run-sta-corner-sweep.sh`)

**Added by issue #86; rewritten as a single `klt sta` envelope by issue
#132.** `flow/run-sta-corner-sweep.sh` answers a different question from
`run-corner-sweep.sh` above, and is the one to reach for when you want
per-corner timing **of the layout this repo actually ships**:

```bash
./flow/run-sta-corner-sweep.sh                  # all 18 ratified corners
./flow/run-sta-corner-sweep.sh -o /tmp/out.json # write the envelope elsewhere
```

It runs `klt sta` — a standalone OpenSTA analysis of an already-routed DEF
(klayout-tools#1099, available at this repo's pinned `klt` revision; see
`docs/cli/sta.md`) — against the committed `layout/modexp.def`. It never
places, routes, or runs CTS, so **the geometry is byte-identical across all
eighteen corners**: the table it produces characterizes one design at
eighteen corners, rather than measuring eighteen differently-optimized
designs the way a per-corner rebuild necessarily does. It also needs no
synthesis netlist and no P&R run, and completes in seconds per corner
rather than minutes.

**One envelope, not eighteen (issue #132).** The script used to shell out
to `klt sta` once per corner with the scalar `pdk.corner` and staple the
eighteen responses into a hand-rolled JSON array. That array is not a
`klt sta` envelope, so `klt signoff --manifest` could not read it as T1
item-5 evidence — the gap `verification/signoff/README.md` named
explicitly. The committed request `flow/sta-modexp.json` now carries
`pdk.corners` (a list —
[klayout-tools#1871](https://github.com/2AMLogic/klayout-tools/issues/1871)),
which characterizes the same loaded geometry at N corners inside one
request/response round trip and whose response **is** a signoff-readable
envelope with a `corners[]` array. The script is now a thin wrapper around
that single invocation, plus a pass/fail summary printed to stdout. Because
the corner list lives in the committed request rather than in the script's
argv, there is no longer a per-corner-subset CLI form; edit the request (or
point `-o` somewhere scratch) if you want a subset.

Both scripts are kept, deliberately, but `run-corner-sweep.sh` is
**archived/frozen**: kept for the record, not the recommended path —
`klt sta` (`run-sta-corner-sweep.sh` + `flow/sta-modexp.json` above) is
the current answer to the corner question for the committed
`layout/modexp.def`. `run-corner-sweep.sh` is how issue #56's "how much
of the slow-corner gap is mapping-attributable" question was answered
(that one genuinely needs per-corner rebuilds), and its evidence record
stays live and unedited; the live script is byte-identical to its frozen
copy at
[`verification/records/place-and-route/artifacts/20260816-072918-d8eafca/run-corner-sweep.sh`](../verification/records/place-and-route/artifacts/20260816-072918-d8eafca/run-corner-sweep.sh).
Results:
[`verification/records/sta-corner-sweep/`](../verification/records/sta-corner-sweep/)
and `docs/baseline.md`.

Requires an `openroad` on `$PATH` and a resolvable `sky130A`. On a host that
has both a `~/.ciel` directory and a legacy `~/.volare` PDK install, set
`PDK_ROOT` explicitly (`PDK_ROOT=~/.ciel`) so `scripts/openroad-docker.sh`
bind-mounts the same root `klt pdk find` resolves — see issue #90. The
wrapper also checks that root's `sky130A/SOURCES` against the pin in
`scripts/setup-env.sh` and refuses to run on a mismatch (a stray `~/.volare` at the
previous pin is never silently used).

The response lands in `flow/sta-corner-sweep-results.json` (gitignored;
`verification/records/sta-corner-sweep/artifacts/` freezes the copy
`verification/signoff/block-manifest.json` cites for T1 item 5).

## What this flow does *not* produce

**Updated, issue #81 (2026-09-11)**: `flow/par-modexp.json` now carries a
`power` block, driving `klt place-and-route`'s `request.power` field
(tapcell + PDN + filler-cell insertion, added upstream by
[klayout-tools#1120](https://github.com/2AMLogic/klayout-tools/pull/1120))
— the routed DEF/GDS this flow produces for the committed nominal-corner
recipe now has all three. `flow/run-corner-sweep.sh`'s separate 18-corner
sweep recipe does **not** carry this block (unaffected by issue #81) and
still produces layouts with none of the three. **Still absent either way**:
metal (density) fill (a routing-layer CMP-density pass, not the same thing
as standard-cell row fillers) and `DONT_USE_CELLS` exclusion — core-only
floorplanning, no IO ring. It is evidence toward Decision 2/4's revisit
triggers (`spec/modexp.md`); DRC is now clean against the committed
nominal-corner GDS (`docs/signoff-claim.md`), but LVS is not, so it is not
yet a fully signoff-ready macro.

## Known upstream gaps (friction protocol, `CLAUDE.md`)

Both gaps below were filed and **fixed upstream** at
`2AMLogic/klayout-tools`, in commits later than the pin that was in force
when they were written (`af5791b557fc7c669c3981335a294256ccf37e6f`,
2026-08-04) — so each bullet describes a local workaround this repo needed
at *that* pin.

**Both gaps are now closed at the current pin.** `docs/environment.md` pins
`klt` to PyPI release `0.8.0` (commit `c572046be644`), several re-pins past
both fixes. The per-bullet `Update` notes below record what that means for
each workaround; neither workaround is still required for correctness. Read
the rest of each bullet as the historical account of the gap, not as a
current requirement.

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
  with no pointer back to the actual cause. `flow/tie_constants.py` was the
  local, interim substitute for the now-merged upstream fix: it rewrites
  every bare literal into a reference to a real
  `sky130_fd_sc_hd__conb_1` tie-cell instance, bit by bit, before the
  netlist reaches `klt place-and-route`.

  **Update (issue #308, 2026-11-13): this gap is closed at the current pin.**
  `klt synthesize` emits real `sky130_fd_sc_hd__conb_1` tie cells itself at
  `klt` 0.8.0, so `flow/tie_constants.py` has nothing left to rewrite. Run
  against the netlist behind the committed layout
  (`verification/records/place-and-route/artifacts/20261027-013900-98bf55d/modexp_synth_tied.v`)
  it prints "no bare literal constants found, copied unchanged" and writes a
  byte-identical file; that netlist carries four `sky130_fd_sc_hd__conb_1`
  instances and none of the script's `_tie_cell_` / `_tie_zero_` /
  `_tie_one_` markers. `layout/README.md` and
  `verification/signoff/evidence/design-sources.md` record the same finding
  for the run that produced it. The DRT-0305 failure described above is
  therefore no longer reachable from this flow, and cold-start step 2 is a
  no-op. The script is retained for now not because the flow needs it, but
  because live evidence records hash its bytes and because
  `flow/par-modexp.json` and `flow/run-corner-sweep.sh` name the
  `modexp_synth_tied.v` path it writes: dropping it means re-pointing those
  at `modexp_synth.v`, which stales every live record that hashes them, so
  it waits for the next record re-mint rather than a run of its own.

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

  **Update (issue #86, 2026-09-15): this gap is closed at the current pin.**
  `docs/environment.md`'s pin has since moved to `f77036bf...`
  (2026-09-09), well past #955, and separately gained `klt sta`
  (klayout-tools#1099) — a standalone OpenSTA analysis of an already-routed
  DEF. `flow/run-sta-corner-sweep.sh` (above) uses it; the eighteen-corner
  analysis it drives takes seconds per corner instead of minutes, and needs
  no rebuild. The remaining residue is smaller and separately filed:
  `klt sta` still analyses one corner per invocation
  ([klayout-tools#1871](https://github.com/2AMLogic/klayout-tools/issues/1871)),
  and hold-side WNS/TNS landed upstream
  ([klayout-tools#1634](https://github.com/2AMLogic/klayout-tools/pull/1634))
  later than this repo's pin, so only a hold *violation count* is available
  here.

  **Update (issue #352, 2026-11-17): the per-corner-rebuild half is closed
  at the current pin too.** The #86 note above closed the re-timing half
  (`klt sta` against one physical build); the other half — the
  N-independent-full-builds loop this bullet describes — is now also
  expressible natively at the pinned `klt` (`klayout-tools==0.8.0`): one
  `klt place-and-route` request carrying `pdk.rebuild_corners` (a corner
  list, mutually exclusive with `pdk.corner`) re-runs the whole flow once
  per named corner into one aggregated `corner_runs[]` report, and
  `--backend batch` sends those units to the Spot batch fleet. Verified
  against the `0.8.0` release's `docs/cli/place-and-route.md` ("Physical
  rebuild per corner"), not `--help`; `docs/environment.md` records the
  lineage (the field from
  [klayout-tools#3550](https://github.com/2AMLogic/klayout-tools/pull/3550);
  the pin then moved past
  [klayout-tools#3605](https://github.com/2AMLogic/klayout-tools/pull/3605)'s
  merge specifically so #201's rebuild could go to the batch fleet).
  `flow/run-corner-sweep.sh`'s loop is therefore an interim substitute
  whose exit condition is met — no equivalence between the native sweep
  and the script's loop is claimed here. The migration and the re-run stay
  with #201 (the 18-corner rebuild re-qualification), and the script stays
  byte-identical until then: live record
  `verification/records/place-and-route/records/20260816-072918-d8eafca.md`
  hashes its content. One caveat for whoever migrates, unverified here:
  the aggregated `rebuild_corners` response may lack per-unit wall-clock —
  the script computes `elapsed_s` itself (`run-corner-sweep.sh:152`) — so
  per-corner timing may surface as a friction-protocol item.

Also fixed in the same window, load-bearing for this run but owned by this
repo rather than `klayout-tools`: `scripts/openroad-docker.sh` (from issue
#13) originally bind-mounted the host working directory at a fixed
container-internal `/workspace`, which works for a relative-path-only
script but silently breaks any `klt place-and-route` run, since every stage
script `klt` generates bakes in **absolute host paths** (the netlist, the
LEF/liberty deck — which for the PDK lives *outside* the repo entirely at
`~/.ciel` — and every stage's `write_db`/`write_def`/`-metrics` output
path). This issue's PR fixes the wrapper to bind-mount both the repo tree
and the resolved PDK root at their own identical absolute paths, so those
paths resolve the same way inside the container as they do on the host; see
that script's own header comment for the detail. `scripts/openroad-smoke-
test.sh`'s fixture (`scripts/openroad-smoke/smoke.tcl`) was updated to use
relative paths accordingly.

### Gaps found by the post-route gate-level re-simulation (issue #9)

Three further gaps, same format and same friction protocol, found while
re-running the bit-exact suite against a gate-level netlist of the routed
layout (`verification/gate-level/`). All three are now **fixed upstream and
past this repo's pin** (the SDF export/option, the defines field, and the
testbench search path, below); what remains on delay-annotated gate-level
simulation is the residual caveats noted on the first bullet, not a missing
capability:

- **`klt place-and-route` SDF export was missing; the netlist half is
  closed at the current pin (corrected by issue #139).** *Originally written
  as "no post-route netlist export: the response carries `def_path` and
  `gds_path` only" — that is stale: the envelope also carries `verilog_path`
  (see `verification/records/place-and-route/artifacts/20260911-052542-d5e43d3/par-nominal-output.json`),
  and `flow/run-par.sh` now commits it on every run.* The netlist half is
  [klayout-tools#996](https://github.com/2AMLogic/klayout-tools/issues/996)
  (filed by #8, **fixed** by
  [#997](https://github.com/2AMLogic/klayout-tools/pull/997), merged
  2026-08-15 — this repo's `klt` pin bumped past it by issue #55, and in
  any case describing a *re-run* of P&R rather than the committed
  `layout/modexp.gds`). The SDF
  half is [klayout-tools#1002](https://github.com/2AMLogic/klayout-tools/issues/1002)
  (**fixed** by
  [#1007](https://github.com/2AMLogic/klayout-tools/pull/1007), merged
  2026-08-15 — this repo's `klt` pin bumped past it by issue #55, and the
  fix also wired `options.sdf` onto `klt functional-verification`).
  Delay-annotated (per-corner) gate-level simulation therefore runs on the
  current pin; two residual caveats remain —
  [klayout-tools#2363](https://github.com/2AMLogic/klayout-tools/issues/2363)'s
  zero-delay `INTERCONNECT` residual (worked around by the record's
  disclosed 4-entry exclusion) and the fact that an SDF run still describes
  a fresh *re-run* of P&R, not byte-reproducible against the committed
  `layout/modexp.gds` — see `verification/gate-level/README.md`. Local
  substitute for the netlist half:
  `verification/gate-level/spice_to_verilog.py`, which derives
  the netlist from #8's `klt extract --abstract-cells` output — see
  `verification/gate-level/README.md`.
- **`klt functional-verification` had no compile-time defines / build-args
  field** ([klayout-tools#1001](https://github.com/2AMLogic/klayout-tools/issues/1001)),
  so a PDK's `` `ifdef ``-gated Verilog cell library
  (`USE_POWER_PINS`, `FUNCTIONAL`, `UNIT_DELAY`) could not be selected
  through the request. **Fixed upstream** by
  [#1006](https://github.com/2AMLogic/klayout-tools/pull/1006) (closed as
  completed 2026-08-15); this repo's `klt` pin is past it and the gate-level
  request carries `options.defines` (`{"FUNCTIONAL": null, "UNIT_DELAY":
  "#1"}`), with `gate_level_cross_check.py` passing the same two defines
  through cocotb's own Runner API. The local substitute
  `verification/gate-level/sky130_fd_sc_hd_sim_defines.v` — which used to be
  listed first in `request.sources` so its `` `define ``s were in effect for
  every later source in the same compilation unit — is gone; a live evidence
  record hashed that file as a provenance input, so removing it minted a
  superseding record (`20261027-013940-98bf55d` →
  `20261117-112523-2abccc2`, #322).
- **`klt functional-verification` required the cocotb testbench module to sit
  next to the request document**
  ([klayout-tools#1003](https://github.com/2AMLogic/klayout-tools/issues/1003)),
  so one unmodified testbench could not serve several requests. **Fixed
  upstream** by [#1005](https://github.com/2AMLogic/klayout-tools/pull/1005)
  (closed as completed 2026-08-15); this repo's `klt` pin is past it, and
  `verification/gate-level/request-modexp-gate-level.json` now reaches
  `verification/test_modexp.py` through `testbench.search_path` (`".."`,
  resolved against the request's own directory). The committed stand-in that
  used to substitute for the field — a second `test_modexp.py` entry in
  `verification/gate-level/` pointing at `../test_modexp.py` — is gone.
  Copying the testbench would have destroyed the property the gate-level run
  exists to demonstrate, and now nothing has to.

Also filed, environment- rather than klt-shaped:
[klayout-tools#1004](https://github.com/2AMLogic/klayout-tools/issues/1004) —
the accepted SDF re-simulation recipe is conditional on Icarus >= 13, and
Icarus 12.0 (what the current Debian/Ubuntu archive ships) cannot simulate
`ifdef`-gated standard-cell *timing* models at all.
