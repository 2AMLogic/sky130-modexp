# verification/ — evidence record format

**This file is the authoritative convention.** The scripts under
`verification/` (`cross_check.py`, `cross_check_tb.py`, `check_records.py`)
implement it; if a script and this document ever disagree, this document
wins and the script is the thing that gets fixed. This adapts the record
convention used by the analog canaries (`2AMLogic/gf180-bandgap`'s
`sim/README.md`) for a digital RTL→GDS flow — a reader who knows one
convention should recognize the other. The parts that differ are the parts
where a digital flow genuinely differs: no ngspice, no PVT corner sweep; the
klt `provenance` block (klt version, resolved PDK, deck/input content
hashes) takes the place of a swept-corner matrix.

This directory holds the cocotb testbenches, the multi-`WIDTH` cross-check
driver, and their results. Results are **append-only evidence**: once a
record is written, it is never edited or deleted. A re-run — even one that
corrects a mistake — mints a new record with a new ID; a correction
references the prior record it supersedes rather than overwriting it.

This convention exists because `CLAUDE.md` commits this repo to rules that
need a concrete schema to be checkable rather than aspirational:

- **Correctness gates everything.** No optimization result counts unless
  the bit-exact cocotb suite passes at every verified `WIDTH` on the same
  commit.
- **Verification is the product.** No claim without a testbench.
- **`verification/` is append-only evidence.** Re-runs get new records;
  records are never edited or deleted.

## Contents

- `test_modexp.py` — width-adaptive cocotb testbench for `rtl/modexp.v`,
  bit-exact against Python `pow(base, exp, mod)`. Driven by
  `klt functional-verification` (see `request-modexp.json`). Migrated from
  `2AMLogic/klayout-tools` (PR #488) and relicensed Apache-2.0 by the
  copyright holder; see issue #2.
- `request-modexp.json` — `klt functional-verification` request driving
  `test_modexp.py` against `modexp.v` (default `WIDTH=16`) via Icarus.
- `cross_check.py` / `cross_check_tb.py` — the deterministic multi-`WIDTH`
  cross-check (see "Why a separate cross-check driver" below).
- `gate-level/` — post-route **gate-level** simulation: the derived netlist
  of the routed layout, the `klt functional-verification` request that runs
  `test_modexp.py` (unmodified, via a symlink) against it, and the converter
  that produces the netlist. See "Gate-level simulation: the netlist
  derivation gap" below and `verification/gate-level/README.md`.
- `check_records.py` — the evidence-record linter (see "Enforcement").
- `test_check_records.py` — the linter's own self-test: one executable
  negative case per violation class named below, run against a throwaway
  fixture repo. A linter that silently stops catching a violation is worse
  than no linter, so the enforcement is itself tested.
- `records/` — the append-only evidence records this convention produces.

Run the klt-driven suite (default `WIDTH=16`, 2 directed + randomized tests)
with:

```bash
klt functional-verification verification/request-modexp.json --format json
```

Run the multi-`WIDTH` cross-check (`WIDTH` = 4, 6, 8, 16 at 500 random cases
each, pinned seed) with:

```bash
python3 verification/cross_check.py          # report only (what `npm run test` runs)
python3 verification/cross_check.py --mint-record   # also write a new evidence record

# prove the seed is pinned rather than defaulted: two runs, identical bytes
python3 verification/cross_check.py --widths 4 6 --cases 40 --transcript-dir /tmp/a
python3 verification/cross_check.py --widths 4 6 --cases 40 --transcript-dir /tmp/b
cmp /tmp/a/width-4.jsonl /tmp/b/width-4.jsonl
```

`cross_check.py` re-executes itself under `.venv/bin/python3` when the
invoking interpreter cannot import cocotb but the venv provisioned by
`scripts/setup-env.sh` can — so `npm run test` works from a clean checkout
without the caller having to activate anything. If neither interpreter has
cocotb, or `iverilog` is not on `$PATH`, it says so and points at
`scripts/setup-env.sh` rather than raising an ImportError.

See `docs/baseline.md` for the full reproduction recipe, including the
synthesis cell-count measurement, and `docs/environment.md` for the pinned
tool/PDK versions.

## Why a separate cross-check driver (the klt gap)

`klt functional-verification`'s request schema
(`klt.functional_verification.request/1`) has no field to override a
Verilog `parameter`, so a checked-in request can only elaborate a design's
*default* parameterization — `request-modexp.json` only ever exercises
`WIDTH=16`. `modexp.v`'s bit-exactness at `WIDTH` = 4, 6, 8, 16 (the claim in
`docs/baseline.md` and the revisit trigger in `spec/modexp.md`) therefore
cannot be reproduced through `klt` alone today.

`verification/cross_check.py` closes that gap the same way any client of
cocotb's own `Runner` API would: it drives Icarus directly via
`cocotb_tools.runner`, which *does* accept a `parameters=` mapping, to
elaborate `rtl/modexp.v` at each `WIDTH` and run `cross_check_tb.py`
(a purpose-built cocotb test module, distinct from `test_modexp.py`) against
it. This is a stopgap, not a preferred pattern — `klt` is still the driven
entry point for synthesis and for the default-parameterization functional
run, per `CLAUDE.md`'s "drive engines through klt" rule. The missing
parameter override itself is filed as a friction-protocol issue, generic and
design-detail-free, at
[`2AMLogic/klayout-tools#610`](https://github.com/2AMLogic/klayout-tools/issues/610)
— once `klt functional-verification` gains a parameter override, this
driver script should be retired in favor of a plain klt request per `WIDTH`.

## Gate-level simulation: the netlist derivation gap (and the workaround)

The `gate-level-sim` experiment re-runs `test_modexp.py` — the same file,
byte for byte, reached through a git symlink rather than a copy — against a
gate-level netlist of the **routed layout** instead of against
`rtl/modexp.v`. That requires a netlist of what P&R actually built, and
there is no such artifact:

- `klt place-and-route`'s response contract carries `def_path` and
  `gds_path` **only**. There is no `write_verilog`-equivalent netlist export
  at this repo's pinned `klt` revision, and no SDF export either.
- The one Verilog artifact #7's run produced,
  `verification/records/place-and-route/artifacts/20260814-203901-c741877/modexp_synth_tied.v`,
  is that record's own **"netlist (post-synthesis)"** — the netlist fed
  *into* P&R. #8 established that the routed layout has 718 instances
  against its 683 (+1 tie): 35 CTS/timing-fixup insertions and 5 resizes.
  Simulating it and calling the result "post-route" would be an overclaim
  that *passes*, so no test failure would ever surface it.

The workaround, and the reason this experiment's netlist has provenance
worth trusting: **derive the netlist from the layout itself**.
`verification/gate-level/spice_to_verilog.py` converts #8's
`layout/lvs/modexp_layout_abstracted.spice` (the `klt extract
--abstract-cells` abstraction of `layout/modexp.gds`) into structural
Verilog instantiating `sky130_fd_sc_hd` cells, and refuses to write output
that disagrees with `layout/lvs/modexp_layout_extract_report.json` on
instance counts (718), cell types (59), pin count (68), or net membership —
or that contains a two-driver short or a floating cell input.

**What that netlist does and does not model** — restating #8's own scope
caveat, which carries forward here verbatim, plus what is specific to
simulation:

- **No parasitic extraction.** No R, no C, no coupling; `klt extract` was
  run without `--parasitics` and nothing here reads a SPEF.
- **No timing, and no corner.** Zero-delay logic (the only delay is a 1 ns
  `UNIT_DELAY` on flop outputs, a race-avoidance device, not a
  characterized delay). sky130A ships 18 liberty corners but a single,
  corner-independent set of Verilog cell models, so corner-dependence enters
  a simulation only via SDF — which is the blocked leg. Timing evidence
  remains `verification/records/place-and-route/`'s OpenSTA corner sweep.
- **No power/ground network.** Power pins are dropped (`USE_POWER_PINS`
  undefined); this GDS has no PDN, so extracted rail connectivity is
  fragmented per placement row.
- **Cell-instance granularity, not transistor level** — each cell is the
  PDK's own behavioural model; its transistors are foundry-qualified library
  content.
- **Not an independent check of the extraction.** Extraction and simulation
  share `klt extract`'s output as a common input.

The upstream gaps are filed:
[klayout-tools#1001](https://github.com/2AMLogic/klayout-tools/issues/1001)
(no compile-time defines in the `functional-verification` request),
[#1002](https://github.com/2AMLogic/klayout-tools/issues/1002) (no SDF
export / no SDF option — the blocker for delay-annotated runs),
[#1003](https://github.com/2AMLogic/klayout-tools/issues/1003) (testbench
module must sit next to the request),
[#1004](https://github.com/2AMLogic/klayout-tools/issues/1004) (the accepted
SDF re-sim recipe needs Icarus >= 13), and
[#996](https://github.com/2AMLogic/klayout-tools/issues/996) (no as-built
netlist export — filed by #8, fixed upstream later than this repo's pin).

## Directory / naming convention

Each distinct claim being verified gets its own experiment directory under
`verification/records/`:

```
verification/records/
  <experiment-slug>/                 # e.g. width-cross-check, synthesis-baseline
    records/
      <record-id>.md                 # append-only summary record
    artifacts/
      <record-id>/                   # frozen inputs/outputs for this run
        ...                          # e.g. per-WIDTH vector transcripts,
                                      # the raw klt JSON envelope, a mapped
                                      # netlist snapshot
```

- **`<experiment-slug>`** — short, descriptive, kebab-case name for the
  claim being verified (`width-cross-check`, `synthesis-baseline`, and
  future entries such as `place-and-route`, `drc-lvs`, `gate-level-sim`).
  One directory per distinct claim, not per run.
- **`<record-id>`** — unique and traceable:
  `<YYYYMMDD>-<HHMMSS>-<short-git-sha>` (e.g. `20260808-031948-5488082`),
  identical grammar to the analog canaries' convention. Re-runs mint a new
  `<record-id>`; nothing under `records/` or `artifacts/` is ever edited in
  place. `<short-git-sha>` is the design's git revision at the time the
  record was minted (necessarily the parent commit, since the commit that
  adds the record cannot cite its own hash).
- **`artifacts/<record-id>/`** is not a "corner" directory in the analog
  sense (a digital run has no PVT sweep) — it holds whatever raw outputs
  substantiate that specific record: per-`WIDTH` JSONL vector transcripts
  for a cross-check record, the raw `klt synthesize` JSON envelope plus a
  mapped-netlist snapshot for a synthesis record, and (once the P&R issue
  lands) the equivalent for place-and-route / DRC / LVS records.

## Record format

Each record is a markdown file, `records/<record-id>.md`, with two parts:

1. A machine-readable `<!-- record-meta ... -->` HTML-comment block
   containing JSON (invisible in a rendered preview, trivially parseable
   with the stdlib `json` module — no YAML dependency). Required keys:

   - `record_id` — must equal the filename stem.
   - `experiment` — the experiment-slug this record belongs to.
   - `supersedes` — `null`, or the `record_id` of a prior record in the
     same experiment directory this one corrects/replaces.
   - `git_revision` — the full design git revision this record was
     produced against.
   - `provenance` — the klt provenance block:
     - `klt_version`
     - `pdk.name` / `pdk.version` — the resolved PDK name/version, or
       `"n/a"` when the run has no PDK dependency (e.g. the Icarus-only
       cross-check, which never touches a standard-cell library).
     - `deck.content_hash` — the liberty/PDK deck's content hash klt
       reports, or `"n/a"` when not applicable.
     - `inputs` — a non-empty list of `{"path": ..., "content_hash": ...}`
       for every source file this record's claim depends on (at minimum,
       the RTL under test). Hashes use klt's own `"sha256:<hex>"` format.

2. Human-readable prose bullets, each a **required field**:

   - **Record ID** — matches the metadata block and the filename.
   - **Claim** — which spec/doc line this record substantiates (e.g.
     `docs/baseline.md#the-measurement`, or once available,
     `spec/modexp.md#<anchor>`).
   - **Design provenance** — `rtl` (`rtl/<file>.v` @ `<git-sha>`) today;
     once post-synthesis/post-P&R records exist, `netlist` (post-synthesis)
     or `layout` (post-P&R, extracted) analogous to the analog convention's
     schematic/extracted distinction.
   - **Run configuration** — the exact tool invocation and settings (engine,
     `WIDTH` set, case count, seed, PDK corner, clock constraint, ...).
   - **Statistical convention** — sample size / seed for a randomized claim,
     or `N/A` for a single deterministic run (e.g. one synthesis pass).
   - **Result** — the measured outcome(s) and an overall pass/fail against
     the claim.
   - **klt provenance** — human-readable echo of the metadata block's
     `provenance`, including the informational case where klt did not drive
     the run (see "Why a separate cross-check driver").
   - **Links** — paths to the driver/testbench script(s), the design under
     test, and the raw artifacts under `artifacts/<record-id>/`.
   - **Timestamp / author** — ISO-8601 UTC timestamp and who (human or
     agent) minted the record.
   - **Supersedes** — `none`, or the prior `<record-id>` this corrects.

## Append-only rule

`records/*.md` and `artifacts/**` are never edited or deleted after
creation. A re-run or correction always mints a new record with a new
`<record-id>`; a correction references the record it supersedes via the
**Supersedes** field rather than overwriting it in place. This applies even
to typo fixes — the append-only guarantee is what makes `verification/`
usable as an evidence trail.

## Provenance staleness (the point of the klt hash block)

A record's `provenance.inputs[].content_hash` pins the exact source content
the claim was measured against. `check_records.py` recomputes those hashes
from the current working tree for every **live** record (a record no other
record's `supersedes` field names) and fails if they no longer match — the
RTL changed since the record was minted, so the record's claim can no longer
be trusted at `HEAD` and a fresh record is required. Superseded records are
exempt from this re-check: they are frozen history describing what was true
at the commit they cite, not a live claim about the current tree.

## What CI runs vs. what stays local (explicit split)

CI (`.github/workflows/ci.yml`) runs the **tool-light legs only**:

- the multi-`WIDTH` cross-check (`verification/cross_check.py`) under
  Icarus/cocotb — no PDK required, since RTL/behavioral simulation has no
  standard-cell dependency;
- a re-run of the cross-check at a reduced case count with
  `--transcript-dir`, asserting the two runs' vector transcripts are
  byte-identical — the pinned seed is verified, not just asserted;
- the record linter (`verification/check_records.py`), including the
  append-only check against `origin/main`, and the linter's own self-test
  (`verification/test_check_records.py`);
- the post-route netlist converter's self-test
  (`verification/gate-level/test_spice_to_verilog.py`), which needs no PDK
  and no simulator — its synthetic fixture cases run anywhere, and its
  committed-artifact case is what catches a *stale* `modexp_post_route.v`;
- basic Python syntax checks over the scripts in this directory, and
  `bash -n` over `scripts/setup-env.sh`.

CI does **not** run `klt synthesize`, `klt place-and-route`, `klt drc`, or
the gate-level simulation legs under `verification/gate-level/` (those need
the PDK's own Verilog cell models) —
those legs need a fetched `sky130A` PDK (and, for place-and-route,
`openroad`), which are pinned and installed locally per
`scripts/setup-env.sh` / `docs/environment.md` rather than provisioned in
CI. Those legs are **run locally and recorded**: a contributor with the
pinned environment runs `klt synthesize` (or the future P&R/DRC entry
points), verifies the result, and mints a record with `--mint-record` (or
by hand, following the format above) exactly as the two backfilled records
in `verification/records/` were produced. This split is a stated,
deliberate design choice, not an omission — see the issue that introduced
this document (#5) for the cost rationale.

## Enforcement

This convention is checked, not merely documented.
`verification/check_records.py` runs as `npm run lint` (see `package.json`)
and as the `records` job in `.github/workflows/ci.yml`. It needs nothing but
Python 3 and `git`, reads tracked files only, and fails on:

- a record missing a required field (metadata key or prose bullet), or with
  a placeholder/empty value;
- a filename or metadata `record_id` that is not a well-formed
  `<record-id>`, or the two disagreeing;
- a `supersedes` value naming a record that does not exist in the same
  experiment directory;
- a live record whose `provenance.inputs[].content_hash` no longer matches
  the current working tree (see "Provenance staleness" above);
- **append-only violations**: any file under `verification/records/`
  modified, renamed, or deleted relative to the merge base with
  `origin/main` (`--base-ref` to override, `--require-append-only` to turn
  an unresolvable base ref into a failure instead of a `SKIP` — this is how
  CI runs it). Deleting *every* record does not exempt a change from this
  check: an absent or empty records tree is itself reported as an error and
  the append-only diff still runs, so a wholesale deletion is named as the
  violation it is rather than misdiagnosed as a missing directory.

`npm run lint` additionally runs
`verification/gate-level/test_spice_to_verilog.py`, the post-route netlist
converter's own self-test — same rationale as the linter's: a converter that
silently stops noticing that its output disagrees with the layout extraction
would produce a *passing* gate-level run against the wrong netlist, with no
test failure attached to it.

`verification/test_check_records.py` (also run by `npm run lint`) holds one
executable negative case per bullet above — plus positive controls that a
valid record passes, that *adding* a record is allowed, and that a
superseded record is exempt from the freshness re-check. Run it directly
with `python3 verification/test_check_records.py`; it builds a throwaway
fixture repo in a temp directory and invokes the real linter as a
subprocess, so it exercises the shipped entry point rather than a stand-in.
Adding a new rule to this document means adding its negative case there.

If the checker and this document ever disagree, this document wins and the
checker is the thing that gets fixed. The evidence is never the thing that
gets fixed.

## Worked example

The two backfilled records under `verification/records/` (produced when
this convention was introduced) illustrate the format:

- `verification/records/synthesis-baseline/records/<record-id>.md` —
  reproduces the 682-cell `WIDTH=16` synthesis measurement `docs/baseline.md`
  describes, driven through `klt synthesize` unmodified. `provenance.pdk`
  and `provenance.deck.content_hash` are populated from klt's own JSON
  envelope.
- `verification/records/width-cross-check/records/<record-id>.md` —
  reproduces the `WIDTH` = 4/6/8/16 x 500-case bit-exact cross-check, driven
  by `cross_check.py` (bypassing klt for the reason above).
  `provenance.pdk` is `"n/a"` — an Icarus/cocotb-only run has no PDK
  dependency — and `provenance.inputs` covers both `rtl/modexp.v` and
  `cross_check_tb.py`, since the testbench's own content is part of what
  makes the recorded vectors reproducible.

A future post-synthesis or post-P&R re-run of either claim would live under
the same experiment directory with its own `<record-id>`, a `Design
provenance` of `netlist` or `layout` instead of `rtl`, and a `Supersedes`
field naming the record it extends or corrects.
