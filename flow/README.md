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
netlist (`modexp.v`) and the raw `par-output.json` envelope alongside them,
so always run `flow/run-par.sh` for a run you intend to pin: it captures
the DEF, GDS, as-built netlist and envelope into one directory and fails if
any is missing. The committed `layout/modexp.{def,gds,v}` were produced
that way and the flow was shown reproducible — two sequential
`flow/run-par.sh` runs gave byte-identical outputs (issue #232, record
`verification/records/place-and-route/records/20261027-013900-98bf55d.md`).

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

`flow/par-modexp.json` carries a `power` block (tapcell + PDN + filler-cell
insertion, added upstream by
[klayout-tools#1120](https://github.com/2AMLogic/klayout-tools/pull/1120)),
so the committed nominal-corner DEF/GDS has all three;
`flow/run-corner-sweep.sh`'s archived sweep recipe does **not** carry the
block and its layouts have none of them. Also absent from this flow:
routing-layer CMP metal (density) fill — not the same thing as
standard-cell row fillers — plus `DONT_USE_CELLS` exclusion, and
core-only floorplanning means no IO ring. The current DRC/LVS verdict for
the committed GDS is stated once in `docs/signoff-claim.md`; this page does
not restate it.

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
  merged 2026-08-14). One `klt
  place-and-route` request used to resolve exactly one liberty corner
  (`request.pdk.corner`), with no way to re-run only the post-route STA
  stage against an already-routed design at a different corner, so
  `flow/run-corner-sweep.sh`'s N-independent-full-builds loop (each corner
  a full `floorplan → place → cts → route` run) was the local interim
  substitute. **Closed at the current pin** (`klayout-tools==0.8.0`) on
  both halves: `klt sta`'s `pdk.corners` list re-times one physical build
  at N corners in a single request (`flow/run-sta-corner-sweep.sh` +
  `flow/sta-modexp.json` above), and one `klt place-and-route` request
  carrying `pdk.rebuild_corners` (from
  [klayout-tools#3550](https://github.com/2AMLogic/klayout-tools/pull/3550);
  verified against the `0.8.0` release's `docs/cli/place-and-route.md`,
  "Physical rebuild per corner") re-runs the whole flow once per named
  corner into one aggregated `corner_runs[]` report, with `--backend batch`
  sending those units to the Spot fleet. The script's loop is therefore an
  interim substitute whose exit condition is met — no equivalence between
  the native sweep and the script's loop is claimed here. The migration and
  the re-run stay with #201 (the 18-corner rebuild re-qualification); the
  script stays byte-identical until then, because live record
  `verification/records/place-and-route/records/20260816-072918-d8eafca.md`
  hashes its content. One caveat for whoever migrates, unverified here: the
  aggregated `rebuild_corners` response may lack per-unit wall-clock — the
  script computes `elapsed_s` itself (`run-corner-sweep.sh:152`) — so
  per-corner timing may surface as a friction-protocol item.

The gate-level re-simulation (issue #9) found further upstream gaps —
netlist/SDF export, compile-time defines, testbench search path, and the
Icarus version — and their residuals; those filings are documented once,
in `verification/gate-level/README.md`'s "Known upstream gaps" table.
