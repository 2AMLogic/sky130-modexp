# verification/gate-level — post-route gate-level simulation

Running the **committed, unmodified** bit-exact suite
(`verification/test_modexp.py`) against a gate-level netlist of the **routed
layout** (`layout/modexp.gds`), rather than against `rtl/modexp.v`.

Until this directory existed, every correctness claim in `docs/baseline.md`,
`README.md`, and `spec/modexp.md`'s Correctness row rested on *behavioural*
simulation of the RTL. Synthesis mapping, tie-cell insertion, CTS, and
OpenROAD's placement/timing optimizations were all unverified by simulation.

**Achieved here: Leg 1 (zero-delay gate-level equivalence) — PASS. Leg 2
(delay-annotated / SDF simulation) — ATTEMPTED, FAIL** (no longer blocked on
upstream tooling; the upstream capability now exists and was exercised, and
the fresh result is a genuine failure with root-caused evidence, not a
silent zero-delay pass) — see "Leg 2: ATTEMPTED — FAIL" below. Nothing on
this page claims otherwise.

## The netlist problem, and why the netlist here is derived, not exported

`klt place-and-route` at this repo's pinned `klt` revision has **no
post-route gate-level netlist export at all**. Its response contract carries
`def_path` and `gds_path` and nothing else — verified directly against the
installed package, transcript frozen in this experiment's artifacts.

The only Verilog artifact #7's P&R run produced is
`verification/records/place-and-route/artifacts/20260814-203901-c741877/modexp_synth_tied.v`,
which that record itself labels **"netlist (post-synthesis)"** — the netlist
*fed into* P&R, not the result of it. Issue #8's LVS work established, cell
by cell, that the routed layout has **718 instances** against that netlist's
683 (+1 tie cell): 35 CTS/timing-fixup cells (`clkbuf_*`, `clkload*`,
`load_slew*`, every one carrying OpenROAD's own DEF `+ SOURCE TIMING`
annotation) plus 5 drive-strength resizes. Pointing a simulation at
`modexp_synth_tied.v` and labelling the result "post-route" would therefore
be a silent overclaim of exactly the kind `CLAUDE.md` forbids — and it would
*pass*, so no test failure would ever surface it.

So the netlist simulated here is **derived from the routed layout itself**:

```
layout/modexp.gds
  --( klt extract --abstract-cells, issue #8 )-->
layout/lvs/modexp_layout_abstracted.spice          718 X-cards, 59 cell types
  --( verification/gate-level/spice_to_verilog.py )-->
verification/gate-level/modexp_post_route.v        718 instantiations
```

`spice_to_verilog.py` is the converse of `layout/lvs/build_reference_netlist.py`
(gate-level Verilog → SPICE, for `klt lvs`) and follows its conventions: it
binds each positional `X`-card argument to the pin name from that cell type's
own `.SUBCKT` declaration, the same per-type pin order the reference side
reuses.

### Provenance guards (the 718 check, and four more)

A plausible-looking-but-wrong netlist is the failure mode this whole
directory exists to avoid, so the converter validates and, under `--check`,
refuses to write evidence:

| Guard | What it catches |
|---|---|
| per-cell-type instance counts vs `modexp_layout_extract_report.json` | a dropped or duplicated instance (total must be **718**, not 683+1) |
| `pin_count` vs the report (**68**) | a lost or invented top-level pin |
| every net named in the netlist appears in the report's `nets[]` | a fabricated net |
| at most one driver per net | a two-cell-output short in the extraction or the layout |
| every cell input has a driver | a floating input that would simulate as `x` |
| `X`-card arity vs `.SUBCKT` arity | a mis-bound positional argument (hard error) |

Measured on the committed artifacts: 718 instances, 59 distinct cell types,
68 top-level pins, 770 signal nets + 444 power-pin nets = 1214 nets, which is
exactly the extraction report's own `net_count`. Zero shorts, zero floating
inputs.

`test_spice_to_verilog.py` is the converter's own self-test (7 cases: a
synthetic-fixture happy path, one executable negative case per guard above,
and a consistency check of the **committed** `modexp_post_route.v` against
the extraction report — which is what catches a stale committed netlist). It
needs no PDK and no simulator, so it runs in CI alongside
`test_check_records.py`.

## Cell models: which file, which defines

| What | Value |
|---|---|
| Library | `<sky130A>/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v` (+ `primitives.v` for the UDPs) |
| Defines | `` `define FUNCTIONAL ``, `` `define UNIT_DELAY #1 `` (see `sky130_fd_sc_hd_sim_defines.v`) |
| `USE_POWER_PINS` | **not** defined |
| PDK | sky130A, `open_pdks c6d73a35f524070e85faff4a6a9eef49553ebc2b` (the pin in `docs/environment.md`) |

- **`FUNCTIONAL` is required, not preferred.** The `` `ifndef FUNCTIONAL ``
  branch is the `specify`-block *timing* model, and Icarus does not implement
  the delayed-signal output arguments of `$setuphold`/`$recrem`. Compiling
  those models emits `warning: Timing checks are not supported and delayed
  signal "D_delayed" will not be driven.` — 620 of them for this netlist —
  and since those `_delayed` nets are what each cell's UDP is wired to, the
  entire design then simulates as `x`. Measured both ways; the transcript is
  in this experiment's artifacts.
- **`UNIT_DELAY #1`** gives the sequential UDPs a 1 ns output delay (the
  models are `timescale 1ns/1ps`; the design's clock period is 10 ns).
  Combinational cells are unaffected. This is the standard way to keep a
  zero-delay gate-level netlist free of D/Q races at the clock edge. It is
  **not** a timing model of the routed design.
- **`USE_POWER_PINS` is deliberately not defined**, and the derived netlist
  carries no `VPWR`/`VGND`/`VPB`/`VNB` connections. This is not a shortcut:
  `layout/README.md` records that this GDS has **no PDN**, so the extracted
  rail connectivity is fragmented per placement row (444 distinct "power"
  nets across 718 cells) and is not a power network worth simulating. The
  same scope caveat #8 documented for LVS carries forward here verbatim.

## Running it

```bash
./scripts/setup-env.sh                                   # klt + cocotb + sky130A

# Leg 1a -- the committed klt suite, unmodified testbench:
./verification/gate-level/run-gate-level-sim.sh          # regenerates the netlist, then runs klt

# Leg 1b -- the deep 500-case run, matched to the RTL cross-check's vectors:
python3 verification/gate-level/gate_level_cross_check.py \
  --compare-rtl verification/records/width-cross-check/artifacts/20260808-031948-5488082/width-16.jsonl

# the converter's self-test (no PDK, no simulator needed):
python3 verification/gate-level/test_spice_to_verilog.py
```

`run-gate-level-sim.sh` resolves the PDK with `klt pdk find` and links its two
cell-model files into this directory as `pdk-primitives.v` /
`pdk-sky130_fd_sc_hd.v` (gitignored), so the committed request can name them
with machine-independent relative paths. Run the script rather than invoking
`klt functional-verification` on the request directly from a fresh checkout;
the links will not exist yet otherwise. This mirrors the precedent
`flow/par-modexp.json` already sets (its `netlist` path is a scratch artifact
an earlier step produces).

## What was run, and what it showed

### Leg 1a — `klt functional-verification`, unmodified `test_modexp.py`

`test_modexp.py` is **read-only** here. `verification/gate-level/test_modexp.py`
is a git **symlink** to `../test_modexp.py`, not a copy — `klt
functional-verification` requires the testbench module to sit next to the
request document, and copying it would have destroyed the very property the
run exists to demonstrate (that *one* file passes against both views). Verify
with `git ls-files -s verification/gate-level/test_modexp.py` (mode `120000`).

Result: `status: "pass"`, 2/2 tests, `failed_count: 0`. The simulated time is
**identical** to the RTL run's (`test_modexp_known_vectors` 23750.0 ns,
`test_modexp_random` 180480.0 ns) — the routed design is not merely
functionally correct, it is cycle-for-cycle identical to the RTL.

### Leg 1b — 500-case deep run, byte-identical vectors

47 vectors (7 directed + 40 random) is what `test_modexp.py` contains, but
the RTL correctness claim recorded in `verification/records/width-cross-check/`
is 500 randomized cases per `WIDTH`. Running only the 47 at gate level would
be a silent narrowing, so `gate_level_cross_check.py` reuses
`verification/cross_check_tb.py` **unmodified** at the same pinned seed
(`20260807 * 1000 + 16`) to draw the identical 500-vector stream.

Result: 500/500 match, 0 mismatches — **and the per-vector JSONL transcript is
byte-identical** to the committed RTL transcript
`verification/records/width-cross-check/artifacts/20260808-031948-5488082/width-16.jsonl`.
That is a sharper claim than "both runs passed": the routed netlist returned
exactly the same 500 results, in the same order, as the RTL did.

### The `WIDTH` reduction, stated and justified

The RTL cross-check covers `WIDTH` = 4, 6, 8, 16. This leg covers **`WIDTH` =
16 only**, and cannot cover more: the netlist is an extraction of one fixed
physical layout of one elaboration. `WIDTH` is a Verilog parameter of
`rtl/modexp.v`; it does not survive synthesis, let alone place-and-route.
Covering another `WIDTH` at gate level would require synthesizing, routing,
and DRC/LVS-ing a second macro — a different issue's work, not a narrowing of
this one. The case count is **not** reduced (500, matching the RTL claim).

## Leg 2: ATTEMPTED — FAIL, no longer blocked (updated 2026-08-16, issue #55)

Delay-annotated (SDF) simulation — **not achieved as of the original 2026-08-15
run of this experiment**, for two independent, verified blockers documented
below for history. Issue #55 bumped this repo's `klt` pin past the upstream
fixes for both, then exercised Leg 2 end to end for the first time. **The
capability now exists and runs; the fresh result is a FAIL, not a pass, with
concrete new evidence** — replacing "blocked" with an honest, evidenced
result is exactly what changed.

### What changed, and the fresh result

1. `klayout-tools#1002` (no SDF export, no SDF option) closed upstream,
   fixed by [klayout-tools#1007](https://github.com/2AMLogic/klayout-tools/pull/1007)
   ("feat(sta): write post-route SDF and back-annotate it in gate-level
   re-sim", merged 2026-08-15). `klt place-and-route`'s response now carries
   `verilog_path` (`write_verilog`) and `spef_sta.sdf_path` (`write_sdf`)
   when `post_route_spef`/`post_route_sdf` are requested; `klt
   functional-verification` now accepts `options.sdf: {"file": ..., "corner":
   "min"|"typ"|"max"}`.
2. This host's Icarus is 13.0 (stable) — `-ginterconnect` exists and
   `klayout-tools#1004`'s version blocker does not apply.
3. **The netlist and SDF for this attempt come from a fresh, self-consistent
   `klt place-and-route` re-run** (same frozen synthesis netlist / floorplan
   / seed as the layout below, but the bumped `klt`) — **not** from
   `layout/modexp.gds`/`modexp_post_route.v` (Leg 1's netlist above), because
   re-running P&R with the bumped `klt` does not reproduce
   `layout/modexp.gds` byte-for-byte (a separate, load-bearing finding — see
   `verification/records/drc-lvs/records/20260816-174310-5e656e5.md`).
   `verilog_path` and `spef_sta.sdf_path` are outputs of the **same** OpenSTA
   session, so their instance/pin naming is guaranteed mutually consistent.
4. **Result: `klt`'s own SDF-diagnostic gate reports the run FAILED.** Of
   ~753 `INTERCONNECT` entries in the SDF, **200 could not be resolved**
   (`SDF ERROR: ... Could not find intermodpath!`) — every one an entry where
   one endpoint is a **top-level module port**, never a purely internal
   instance-pin-to-instance-pin entry (all of those resolve). Every one of
   the 200 failing entries carries `(0.000:0.000:0.000)` in the SDF itself
   (zero delay either way), but `klt`'s gate is deliberately conservative:
   any unresolved entry fails the run, regardless of whether it would have
   mattered for timing, so a partial annotation is never silently reported
   as a full one. Independently reproduced with a hand-driven
   `iverilog -gspecify -ginterconnect ...`/`vvp` invocation against the same
   sources — same failure class both times.
5. **The regression's own values corroborate a real problem, not merely a
   conservative gate**: both the directed and randomized tests report a
   uniform, constant-zero result on every case (not an occasional
   single-bit mismatch consistent with a marginal timing violation) —
   consistent with a broken control-path signal (`done` is among the 200
   failing interconnects). Root-causing this precisely, beyond the
   diagnostic-gate failure (sufficient on its own to fail the run), is not
   attempted here.
6. **New finding filed generically**, per `CLAUDE.md`'s friction protocol:
   [klayout-tools#1056](https://github.com/2AMLogic/klayout-tools/issues/1056)
   — Icarus `$sdf_annotate` cannot resolve a top-level-port-attached
   `INTERCONNECT` entry even under `-ginterconnect`.

Full evidence: `verification/records/gate-level-sim/records/20260816-174310-5e656e5.md`.

### The original (2026-08-15) blockers, for history

1. **No artifact carrying post-route delays existed.** `klt place-and-route`
   had no `write_sdf`-equivalent output (response contract: `def_path`,
   `gds_path` only), and `klt functional-verification`'s request schema had
   no SDF option. Both verified directly against the then-installed package;
   transcript in this experiment's artifacts. **Fixed by `#1007` above.**
2. **The simulator on this host could not run the annotatable models
   anyway.** Icarus 12.0 rejected `-ginterconnect` outright, and could not
   drive the timing models' `$setuphold`/`$recrem` delayed signals with or
   without `-gspecify`. **Not applicable here** — this host's Icarus is
   13.0.

Note also that the sky130A PDK ships **18 liberty corners but exactly one,
corner-independent set of Verilog cell models**. Corner-dependence enters a
simulation only through SDF. So Leg 1's zero-delay functional run has no
corner attribute at all — it is not "the nominal corner", it is
*corner-free*, and saying otherwise would be the overclaim this record is
careful to avoid. Leg 2's fresh attempt above used the nominal
(`tt_025C_1v80`) corner's SPEF/SDF session only — extending to the binding
slow corner (`ss_n40C_1v28`) and a fast corner is a natural follow-up, not
attempted here (each would require its own independent P&R re-route, per
`flow/run-corner-sweep.sh`'s own documented cost, on top of the
per-corner functional-mismatch investigation item 6 above already
identifies as open).

## Known upstream gaps (friction protocol, `CLAUDE.md`)

| Gap | Upstream |
|---|---|
| `klt place-and-route` exports no as-built (post-CTS/post-resize) netlist | [klayout-tools#996](https://github.com/2AMLogic/klayout-tools/issues/996) — filed by #8, **fixed** by [#997](https://github.com/2AMLogic/klayout-tools/pull/997) (merged 2026-08-15) — this repo's `klt` pin bumped past it by issue #55 |
| `klt place-and-route` has no SDF export; `klt functional-verification` has no SDF option | [klayout-tools#1002](https://github.com/2AMLogic/klayout-tools/issues/1002) — **fixed** by [#1007](https://github.com/2AMLogic/klayout-tools/pull/1007) (merged 2026-08-15) — this repo's `klt` pin bumped past it by issue #55; Leg 2's fresh attempt fails for a *different* reason, see above |
| `klt functional-verification` has no compile-time defines / build-args field, so an `ifdef`-gated Verilog cell library cannot be selected through the request | [klayout-tools#1001](https://github.com/2AMLogic/klayout-tools/issues/1001) (open) — worked around by `sky130_fd_sc_hd_sim_defines.v` |
| The accepted SDF re-sim recipe is conditional on Icarus >= 13; 12.0 has no `-ginterconnect` and cannot simulate `ifdef`-gated timing models at all | [klayout-tools#1004](https://github.com/2AMLogic/klayout-tools/issues/1004) (filed by this issue) — not a blocker on this repo's host (Icarus 13.0) |
| `klt functional-verification` requires the testbench module to sit next to the request, so one unmodified testbench cannot serve several requests | [klayout-tools#1003](https://github.com/2AMLogic/klayout-tools/issues/1003) (filed by this issue) — worked around by the symlink above |
| Icarus `$sdf_annotate` cannot resolve a top-level-port-attached `INTERCONNECT` entry even under `-ginterconnect` | [klayout-tools#1056](https://github.com/2AMLogic/klayout-tools/issues/1056) (filed by issue #55) — **this is Leg 2's fresh blocker**, found only once #1002/#1007 made the attempt possible |

A `klt` pin bump is **not** a P&R-reproducibility guarantee: re-running P&R
with the bumped `klt`, even against the identical frozen netlist/floorplan/
seed, does not reproduce `layout/modexp.gds` byte-for-byte (see
`verification/records/drc-lvs/records/20260816-174310-5e656e5.md`). So the
as-built netlist export (`#997`) and Leg 2's fresh SDF attempt (`#1007`)
above both describe a **fresh re-run** of P&R, not the committed
`layout/modexp.gds`. The extraction-derived Leg 1 path here stays the one
with provenance tied to the GDS that was actually DRC'd and LVS'd, and
should be kept as a cross-check.

## What this does and does not model

**Does:**

- every standard-cell instance actually present in the routed GDS, including
  all 35 CTS/timing-fixup cells and all 5 resized instances;
- the signal connectivity `klt extract` recovered from the drawn geometry —
  i.e. the routing, not the router's intent;
- the tie cell (`conb_1`) as a real instance, not a Verilog constant;
- boolean/sequential behaviour of each cell, from the PDK's own models.

**Does not:**

- **no parasitic extraction.** No R, no C, no coupling — `klt extract` was run
  without `--parasitics`, and nothing here reads a SPEF.
- **no timing.** Zero-delay logic; the only delay in the run is the 1 ns
  `UNIT_DELAY` on flop outputs, which is a race-avoidance device, not a
  characterized delay. No setup/hold check is exercised. Timing evidence
  remains `verification/records/place-and-route/`'s OpenSTA corner sweep.
- **no power/ground network.** Power pins are dropped; this GDS has no PDN.
- **no corner dependence** (see above).
- **cell-instance granularity, not transistor level** — carried forward from
  #8: each cell is the PDK's behavioural model, and the transistors inside it
  are foundry-qualified library content, unmodified on both sides.
- **not an independent check of the extraction itself.** Leg 1 passing is
  strong evidence that the extracted connectivity is functionally right, but
  extraction and simulation share `klt extract`'s output as a common input.

## Evidence record

`verification/records/gate-level-sim/` — the append-only record for this
experiment, with the raw `klt` JSON envelope, the 500-vector transcript, a
frozen copy of the simulated netlist, and the Leg 2 blocker transcript as
artifacts. `verification/README.md` is the authoritative description of that
record format.
