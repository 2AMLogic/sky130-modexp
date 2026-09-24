# Re-spin of DR-0004 Decision 2's priced exit (issue #141) — artifacts

**Read this first.** Everything here is the verbatim `klt` request/response
material for **one re-derivation attempt** of the configuration record
`20260923-093000-28a7c96`'s `candidates/` subtree calls **row 6** — the
lever-matrix row that measured **18/18 corners closed** at
**+0.489 ns / 105.14 MHz** at the binding corner `ss_n40C_1v28`.

**It is not a claim about `layout/modexp.def`.** This repository's committed
layout, its DRC/LVS/gate-level evidence and its T1 item-5 citation are all
untouched by this record; the P&R output measured here was produced in the
gitignored `flow/.klt/` scratch tree and was deliberately **not** committed
(see the record file and `spec/decision-records/0005-…` for why).

## What this run changed relative to row 6

Exactly one thing: the 209-cell standard-cell exclusion is now expressed as
a **committed `klt synthesize` request field** (`constraints.dont_use`,
landed upstream by
[klayout-tools#2429](https://github.com/2AMLogic/klayout-tools/pull/2429),
closing [klayout-tools#2382](https://github.com/2AMLogic/klayout-tools/issues/2382))
instead of by invoking Yosys directly with a hand-edited script. That was
the *first* of the two grounds on which DR-0004 Decision 1 rejected landing
row 6, and it is now discharged: `synth-request.json` here is a committed,
re-runnable request, and `klt synthesize` reproduces the hand-rolled
script's netlist **bit-identically** on this host (see "The netlist identity
check" below).

Everything else is row 6 verbatim: the frozen bit-serial RTL
(`../20260923-093000-28a7c96/candidates/rtl/modexp-bit-serial.v`),
`constraints.clock_period_ns: 10.0` at `ss_n40C_1v28`,
`flow/par-modexp.json`'s floorplan with only `pdk.corner` moved to
`ss_n40C_1v28`, and `flow/sta-modexp.json`'s eighteen ratified corners.

## Files

| File | What it is |
| --- | --- |
| `synth-request.json` | the `klt synthesize` request, verbatim — the **committed-request form of the 209-cell exclusion**, i.e. the artifact klayout-tools#2382 was filed to make possible |
| `synth-report-yosys-0.67.json` | the `klt synthesize` response under Yosys 0.67 (YoWASP `0.67.0.0.post1190`) |
| `synth-report-yosys-0.68.json` | the same request under Yosys 0.68 (YoWASP `0.68.0.0.post1208`) — **same 1105 instances, same 10158.4928 µm² area** |
| `synth_modexp.ys` | the commit-safe Yosys script `klt synthesize` generated for that request, for line-by-line comparison against `../20260923-093000-28a7c96/candidates/yosys-cell-exclusion.ys` |
| `par-request.json` / `par-report.json` | the `klt place-and-route` request/response, verbatim — including the **in-flow** post-route STA (`estimate_parasitics -global_routing`) |
| `sta-request.json` / `sta-results.json` | the `klt sta` request/response envelope over all eighteen ratified corners — **the load-bearing artifact** |
| `drc-report.json` | `klt drc --deck sky130` against the re-spun (uncommitted) GDS |

## The netlist identity check

The `abc` line `klt synthesize` generates from `synth-request.json` is
flag-for-flag identical to `candidates/yosys-cell-exclusion.ys`'s, in the
same order: the built-in per-library table's two globs
(`sky130_fd_sc_hd__lpflow_*`, `sky130_fd_sc_hd__probe*`) first, then the
209 request-supplied names, under the default
`constraints.dont_use_mode: "additive"`. Running the frozen script directly
on this host and running `klt synthesize synth-request.json` produce the
**same netlist byte for byte**:

```
f33ededc15da930f4181b0a6ca4d411d5110976cb7320fc07ba1166ca192186a  (frozen yosys-cell-exclusion.ys, run directly)
f33ededc15da930f4181b0a6ca4d411d5110976cb7320fc07ba1166ca192186a  (klt synthesize synth-request.json)
```

## The finding: 1105 cells, not 1204 — and 17/18, not 18/18

Both of the above produce **1105 instances**, where the frozen row 5/6
measurement recorded **1204**. The difference is therefore **not** between
the request field and the hand-rolled script — they agree exactly — but
between **this host's Yosys/ABC build and the one row 6 was produced on**.
It is stable across Yosys 0.67 and 0.68 here, so it is not a Yosys
*version* effect either; `abc`'s mapping is embedded in the Yosys build.

The 1105-cell netlist, placed and routed at `ss_n40C_1v28` with row 6's
floorplan verbatim, closes at **17 of 18** corners. Binding corner
`ss_n40C_1v28`: setup slack **−0.574 ns**, **94.57 MHz**, hold clean
(+2.069 ns) at that corner and at all eighteen.

The two STA methodologies that disagreed about row 6 now **agree**:

| Method | row 6 (frozen, other host) | this re-spin |
| --- | --- | --- |
| `klt sta`, `spef` omitted | **+0.489 ns / 105.14 MHz** | **−0.574 ns / 94.57 MHz** |
| in-flow P&R STA (`estimate_parasitics -global_routing`) | −1.105 ns / 90.05 MHz | **−1.160 ns / 89.60 MHz** |

The in-flow number reproduced to within 0.06 ns; the `klt sta` number did
not. Both methods now say the binding corner does **not** close at 100 MHz.

Per `spec/decision-records/0002-…` Decision 1, no claim derived from these
numbers may say this block "closes 100 MHz" without naming the corner set
it holds at — 17 of 18, failing at `ss_n40C_1v28`. Per `CLAUDE.md`'s
overclaim-trap section, no figure here is compared against any external
standard-cell library's published result.

## Reproducing

```bash
./scripts/setup-env.sh && source .venv/bin/activate
export PDK=sky130A PDK_ROOT=~/.volare

git apply verification/records/sta-corner-sweep/artifacts/20260923-093000-28a7c96/candidates/rtl/bit-serial.patch
cp verification/records/sta-corner-sweep/artifacts/20260924-134500-1a8313b/synth-request.json flow/synthesize-modexp.json
cp verification/records/sta-corner-sweep/artifacts/20260924-134500-1a8313b/par-request.json   flow/par-modexp.json

klt synthesize flow/synthesize-modexp.json --format json
python3 flow/tie_constants.py flow/.klt/synthesize/run-<id>/modexp_synth.v \
                              flow/.klt/synthesize/modexp_synth_tied.v
klt place-and-route flow/par-modexp.json --format json
cp flow/.klt/place-and-route/modexp.def layout/modexp.def   # scratch only -- NOT committed by this record
./flow/run-sta-corner-sweep.sh
```

`tie_constants.py` is a **no-op at this repo's current `klt` pin** — the
upstream fix for klayout-tools#854 emits real `sky130_fd_sc_hd__conb_1` tie
cells, so the script reports "no bare literal constants found, copied
unchanged". It is kept in the recipe because `flow/par-modexp.json`'s
`netlist` field names its output path.
