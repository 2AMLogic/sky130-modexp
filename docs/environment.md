# Environment

This document records the pinned tool/PDK versions this repo's evidence
records are produced against, and how to reproduce that environment from a
clean checkout. `verification/records/**/*.md` cite these versions (in each
record's `klt provenance` field); if you re-pin anything here, mint fresh
records rather than editing old ones (see `verification/README.md`'s
append-only rule).

## Provisioning: `scripts/setup-env.sh`

```bash
./scripts/setup-env.sh
```

This creates a local `.venv`, installs `klayout-tools` (`klt`) into it at
the pinned revision below, fetches the pinned `sky130A` PDK version via
`volare`, checks `iverilog` / `yosys` / `openroad`, and reports what's still
missing with an actionable install pointer, never a traceback. For
`openroad` specifically: if it's not already on `$PATH` and `docker` is
available, it wires up `.venv/bin/openroad` as a symlink to the pinned
Docker route automatically (see "OpenROAD" below) rather than reporting it
missing. It is safe to re-run; it reuses an existing `.venv` and an
already-fetched PDK version.

Activate the venv for interactive use with:

```bash
source .venv/bin/activate
```

## Pinned versions

| Component | Pinned to | Resolved via |
|---|---|---|
| `klayout-tools` (`klt`) | git revision [`dac2b5daceb69a2068d9d2ee190d7afe37b29af7`](https://github.com/2AMLogic/klayout-tools/commit/dac2b5daceb69a2068d9d2ee190d7afe37b29af7) | `pip install "klayout-tools @ git+https://github.com/2AMLogic/klayout-tools@dac2b5daceb69a2068d9d2ee190d7afe37b29af7"` (what `scripts/setup-env.sh` runs) |
| `klayout-tools` (`klt`, signoff-report leg) | git revision [`dac2b5daceb69a2068d9d2ee190d7afe37b29af7`](https://github.com/2AMLogic/klayout-tools/commit/dac2b5daceb69a2068d9d2ee190d7afe37b29af7) | installed directly by the CI `signoff` job (issue #136's pin, unified with the pin above by issue #133 — `scripts/setup-env.sh` now provisions the same revision, so the report leg and the PDK legs share one pin) |
| T1 tier checklist (`verification/signoff/design-evidence-tiers.md`) | upstream doc revision [`0882541638acaec9ceb43c4df77b47d5a1a179db`](https://github.com/2AMLogic/klayout-tools/commit/0882541638acaec9ceb43c4df77b47d5a1a179db) | committed byte-identical copy, passed to `klt signoff --tiers-doc` by `verification/signoff/run-signoff.sh` (never resolved from the installed `klt`) |
| `sky130A` PDK | `open_pdks` commit `c6d73a35f524070e85faff4a6a9eef49553ebc2b` | `volare enable --pdk-root ~/.volare --pdk sky130 c6d73a35f524070e85faff4a6a9eef49553ebc2b` |
| `cocotb` | 2.0.1 (pulled in as a `klayout-tools` dependency) | installed alongside `klt` by `scripts/setup-env.sh` |
| Python | <= 3.13 (cocotb 2.0.1 refuses to build on 3.14+) | `scripts/setup-env.sh` auto-selects `python3.13` > `3.12` > `3.11` > `3.10` > `python3`, whichever is the newest compatible interpreter found on `$PATH` |

**Pin rationale (issue #55, 2026-08-16)**: the previous pin
(`af5791b557fc7c669c3981335a294256ccf37e6f`, 2026-08-04) predated three merged
upstream fixes this repo's DRC/LVS/post-layout evidence depends on —
[klayout-tools#998](https://github.com/2AMLogic/klayout-tools/pull/998)
("fix(drc): merge checked regions before running check primitives", merged
2026-08-15T03:54:20Z), [klayout-tools#997](https://github.com/2AMLogic/klayout-tools/pull/997)
("feat(place-and-route): export as-built netlist via `write_verilog` at route
stage", merged 2026-08-15T03:25:31Z), and
[klayout-tools#1007](https://github.com/2AMLogic/klayout-tools/pull/1007)
("feat(sta): write post-route SDF and back-annotate it in gate-level re-sim",
merged 2026-08-15T09:26:00Z). The current pin,
`a482d3934bd644b763cf925f6344ac05f54a1623` (2026-08-16T14:25:34Z), was
re-verified live against `2AMLogic/klayout-tools` at implementation time to
be a descendant of all three fix commits
(`gh api repos/2AMLogic/klayout-tools/compare/<fix-sha>...a482d393...` →
`"status": "ahead"` for each) — not merely trusted from the issue body's
earlier snapshot, since `klayout-tools` `main` moves several commits a day.

**Pin rationale (issue #78, 2026-09-09)**: the previous pin
(`a482d3934bd644b763cf925f6344ac05f54a1623`, 2026-08-16) predated
[klayout-tools#1069](https://github.com/2AMLogic/klayout-tools/pull/1069)
("fix(functional-verification): resolve top-level-port SDF `INTERCONNECT`
entries via a generated pass-through wrapper", merged
2026-08-17T00:05:03Z at `ee10a5415f14d2a6a2f516355b276673e1700170`) — the fix
for [klayout-tools#1056](https://github.com/2AMLogic/klayout-tools/issues/1056),
which had caused Leg 2 (delay-annotated SDF gate-level simulation) to FAIL
(`verification/records/gate-level-sim/records/20260816-174310-5e656e5.md`).
The new pin, `f77036bff1eaf97b992e121acd702a98519142fb` (2026-09-09T21:50:44Z,
`klayout-tools main`'s tip at implementation time), was re-verified live to
be a descendant of `ee10a54`
(`gh api repos/2AMLogic/klayout-tools/compare/ee10a54...f77036b` →
`{"status": "ahead", "ahead_by": 424}`) — i.e. it contains #1069's fix.

**Pin rationale (issue #133, 2026-09-23)**: the previous pin
(`f77036bff1eaf97b992e121acd702a98519142fb`, 2026-09-09) predated the two
merged upstream fixes that close the SDF `INTERCONNECT` residuals Leg 2's
2026-09-09 re-attempt failed on
(`verification/records/gate-level-sim/records/20260909-230216-92e00f2.md`,
49 unresolved entries, filed as
[klayout-tools#1619](https://github.com/2AMLogic/klayout-tools/issues/1619),
closed 2026-09-15):
[klayout-tools#1857](https://github.com/2AMLogic/klayout-tools/pull/1857)
("fix(functional-verification): defer bit-selected top-level-port
`INTERCONNECT` entries to a later `$sdf_annotate` call", merged at
`53b024df53f6b83e689aeea16ea971d37d562da6`) and
[klayout-tools#2304](https://github.com/2AMLogic/klayout-tools/pull/2304)
("fix(functional-verification): drop zero-delay assign-alias port
`INTERCONNECT`s", closing
[klayout-tools#2285](https://github.com/2AMLogic/klayout-tools/issues/2285),
merged at `c0bca3f5779e6860f2b6ab94db4c8c4d1355d9f0`). The new pin,
`dac2b5daceb69a2068d9d2ee190d7afe37b29af7` (2026-09-23,
`klayout-tools main`'s tip at implementation time), was re-verified live to
be a descendant of both fix commits
(`gh api repos/2AMLogic/klayout-tools/compare/<fix-sha>...dac2b5d` →
`"status": "ahead"` for each), plus the doc attribution
[klayout-tools#1888](https://github.com/2AMLogic/klayout-tools/pull/1888)
(merged at `2c488d6b`) that names the all-tests-fail SDF shape a timing
property, not an annotation failure.

**Pin NOT bumped, deliberately (issue #141, 2026-09-24).** The capability
issue #141 needed —
[klayout-tools#2382](https://github.com/2AMLogic/klayout-tools/issues/2382),
request-level standard-cell exclusion (`constraints.dont_use`), closed by
[klayout-tools#2429](https://github.com/2AMLogic/klayout-tools/pull/2429) at
merge commit `9cabec7b02d095e3cabd2194eabfc1d8b8aa8c23` — landed upstream
**after** the `dac2b5da` pin above, which
`gh api repos/2AMLogic/klayout-tools/compare/9cabec7b...dac2b5da` (verified
2026-09-24) shows is a strict ancestor of it (`"status": "behind"`,
`behind_by: 35`). Issue #141's re-spin was therefore run against
`c66f18fd62250c5b71046e4e2a2b0288024eaff0` (11 commits ahead of `9cabec7b`)
in a throwaway venv, **without moving this file's pin**, because the
"re-pin ⇒ mint fresh records" rule above obliges re-minting the DRC/LVS/P&R
records against the newer tool — work that issue #141 deliberately did not
do, since
`spec/decision-records/0005-the-priced-exit-was-run-and-does-not-reproduce.md`
Decision 1 lands no layout change. **The bump is owned by whichever PR
lands the bit-serial re-spin**, which re-mints those records anyway and so
discharges the rule in one move.

To reproduce record
`verification/records/sta-corner-sweep/records/20260924-134500-1a8313b.md`
without moving the pin:

```bash
./scripts/setup-env.sh && source .venv/bin/activate
pip install --force-reinstall \
  "klayout-tools @ git+https://github.com/2AMLogic/klayout-tools@c66f18fd62250c5b71046e4e2a2b0288024eaff0"
```

**Yosys/ABC build identity is not pinned, and issue #141 measured that this
matters.** The table below records the `yosys` version each record's
environment *resolved*; it is not a pin, and `yosys -V`'s version string
does not identify the `abc` build embedded in the binary. Running the same
mapping script at the same nominal Yosys version on two hosts produced
netlists of **1204** and **1105** instances, moving the binding corner's
`klt sta` setup slack by **1.06 ns** — across the 100 MHz closure
threshold. See record `20260924-134500-1a8313b` and decision record `0005`
Decision 3; pinning a Yosys/ABC build is named there as being on the
critical path for any cell-exclusion-dependent timing claim, not as
housekeeping.

`klt` in turn resolves `iverilog`/`yosys`/`openroad` and the PDK itself from
the host — it does not vendor them. Those are:

**Second klt pin, signoff-report leg only (issue #130, 2026-09-23).** The
row above pins the klt that **produces evidence** (the PDK-heavy legs whose
records cite the pin in their `provenance`). The `klt signoff --manifest`
report leg (`verification/signoff/`) additionally carries its own, newer pin
(`dac2b5da`, 2026-09-23, upstream `main` tip at pin time) because the report
grader needs capabilities the evidence pin predates: `klt sta` /
`klt functional-verification` envelope recognition in tier-verdict mode
(klayout-tools#1959), the items-3/4 kind restrictions (#1987), and the
eleventh T1 item (#2025 — the checklist itself is separately pinned via the
committed tier doc, but the grader code needs to parse it). The report leg
re-runs no PDK job — it only reads committed JSON envelopes — so bumping
**its** pin does not invalidate any evidence record and requires only
regenerating `verification/signoff/tier-report.json`
(`./verification/signoff/run-signoff.sh`); the CI `signoff` job's `--check`
fails until that regeneration is committed. The two pins intentionally
remain separate: converging them means re-minting the DRC/LVS/P&R records
against the newer tool (the "re-pin ⇒ mint fresh records" rule above), which
is the evidence legs' own decision to make, not the report leg's.

| Tool | Used for | Resolved version on the environment these records were produced on |
|---|---|---|
| Icarus Verilog (`iverilog`) | `klt functional-verification`, `verification/cross_check.py` | 13.0 (stable) (`iverilog -V`) |
| Yosys (`yosys`) | `klt synthesize` | 0.68+post (`yosys -V`) |
| OpenROAD (`openroad`) | `klt place-and-route` | `26Q3-1260-g06a5a02279` (`openroad -version`), via the pinned `openroad/orfs` Docker image — see "OpenROAD" below |

Package-manager installs for the first two:

```bash
# macOS (Homebrew)
brew install icarus-verilog yosys

# Debian/Ubuntu
apt-get install iverilog yosys
```

**Icarus >= 13 is a hard requirement for SDF-annotated runs** (`klt
functional-verification` with `options.sdf` refuses an older Icarus with a
request error: `-ginterconnect`, which a post-route SDF's `INTERCONNECT`
delays require, does not exist before 13.0 —
[klayout-tools#1004](https://github.com/2AMLogic/klayout-tools/issues/1004)).
Ubuntu 24.04's `apt` still ships 12.0, so on such a host 13.0 must be built
from source (issue #133's run host did exactly this):

```bash
git clone --depth 1 --branch v13_0 https://github.com/steveicarus/iverilog.git
cd iverilog && ./autoconf.sh && ./configure --prefix="$PREFIX" \
  && make -j"$(nproc)" && make install
# -> $PREFIX/bin/iverilog reports "Icarus Verilog version 13.0 (stable)"
```

Zero-delay (RTL and Leg 1 gate-level) runs work on 12.0; only `options.sdf`
needs 13.

## OpenROAD

`openroad` has **no Homebrew formula** (`brew search openroad` returns
nothing) and no common-distro package as of this writing, so it is
provisioned differently from the two tools above: via a **pinned Docker
image**, not a host package. This was a real provisioning gap (issue #13) —
before choosing a route, `2AMLogic/klayout-tools`'s own
[`docs/design/openroad-invocation-survey.md`](https://github.com/2AMLogic/klayout-tools/blob/main/docs/design/openroad-invocation-survey.md)
(its issue #397) was read first, since it already investigated this exact
question from the same class of host (macOS/arm64, Docker Desktop). It
confirmed the `openroad/orfs` image runs real x86_64 OpenROAD/Yosys/KLayout
binaries under Docker Desktop's `linux/amd64` emulation, and flagged that
routing/CTS can crash mid-run under that emulation (an emulation gap, not an
OpenROAD defect — see that survey's "Environment limitation" section). This
repo reuses that route rather than re-deriving it; a from-source
`OpenROAD-flow-scripts` build was rejected as the default path since it is a
multi-hour, multi-dependency build with no reproducibility advantage over a
digest-pinned image.

### Pinned version

| What | Pinned to |
|---|---|
| Image | `openroad/orfs:26Q3-296-gda37dce1c` |
| Image digest | `sha256:ebc8142da6d65d1a1e9a528aa2cedcde356243465dd859af8d3ade51075f8cb2` |
| `openroad -version` (inside the image) | `26Q3-1260-g06a5a02279` |
| `yosys -V` (bundled, unused here — this repo's own `klt synthesize` uses the host `yosys` above) | `0.67` (`sha1 2d1509d1b`) |
| `klayout -v` (bundled, unused here — `klt drc`'s in-process `klayout` pip package is the tool this repo actually drives) | `0.30.7` |

`scripts/openroad-docker.sh` pins both the image tag and its digest (image
tags on Docker Hub can move; the digest cannot), so a re-run months from now
resolves the exact same binary. Re-pin both together if this is ever
updated, and record the new `openroad -version` string alongside them — P&R
numbers from issues #7/#8/#9 are only comparable across runs against the
same pinned version.

### How it's wired up

`scripts/setup-env.sh` prefers a native `openroad` already on `$PATH`; if
none is found and `docker` is available, it symlinks
`.venv/bin/openroad -> scripts/openroad-docker.sh`, so after
`source .venv/bin/activate`, `openroad` resolves exactly like `iverilog` and
`yosys` do — `klt place-and-route` (or any other caller that shells out to
`openroad` by name) does not need to know it is backed by a container. The
first invocation pulls the ~1.6 GB image; `scripts/setup-env.sh` itself does
not pull it eagerly, only wires up the symlink (no network required for
that step).

`scripts/openroad-docker.sh` can also be run directly (`./scripts/openroad-docker.sh -no_init -exit script.tcl`),
bind-mounts the current directory into the container at `/workspace` (so
relative paths in a Tcl script resolve the same as against a native
install), and forwards a small allowlist of ORFS-relevant env vars
(`PLATFORM_DIR`, `PDK_ROOT`) if set on the host.

### Smoke test

`scripts/openroad-smoke-test.sh` proves the toolchain actually executes,
not merely that it answers `-version`: it drives OpenROAD's Tcl engine
through a real LEF read, `link_design`, `initialize_floorplan`, and
`write_def` sequence against a trivial hand-written one-cell netlist
(`scripts/openroad-smoke/smoke_top.v`) and the sky130hd platform LEF the
image ships. This is toolchain verification only — it is not a P&R
measurement of `rtl/modexp.v` (that is issue #7's job) and writes nothing
under `verification/` or `layout/`. Run it with:

```bash
./scripts/openroad-smoke-test.sh
```

### Alternative: build from source

For a host where Docker isn't viable, `OpenROAD-flow-scripts` also supports
a from-source build —
[`The-OpenROAD-Project/OpenROAD-flow-scripts`](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts),
`./build_openroad.sh --local` — with its own toolchain prerequisites (see
that repo's docs). This repo does not script or pin that route: it is a
multi-hour build with its own maintenance burden, and the Docker route above
already gives a pinned, reproducible `openroad -version`. Revisit if a build
host without Docker ever needs to run this flow.

## Why local, not CI, for the PDK-heavy legs

CI (`.github/workflows/ci.yml`) does not fetch `sky130A` or provision
`openroad` — provisioning a real PDK (or a Docker-backed `openroad`, now
pinned per the "OpenROAD" section above) in a hosted CI runner on every PR
is a real, recurring cost this repo has chosen not to pay per-PR. Instead:

- CI runs the tool-light legs only: the multi-`WIDTH` cross-check
  (Icarus/cocotb, no PDK) and the evidence-record linter. CI installs
  `iverilog` from the runner's distro packages and `cocotb` at the version
  pinned above; the `iverilog` version there is therefore whatever the
  runner image ships, not the version in the table above. That is
  deliberate — the cross-check is a bit-exactness claim about the RTL, and
  a *second* simulator build agreeing is corroboration, not drift. Records
  are only ever minted locally against the pinned versions above.
- `klt synthesize` / `klt place-and-route` / `klt drc` are run locally by a
  contributor with `scripts/setup-env.sh`'s environment provisioned, and the
  result is committed as an append-only record under `verification/records/`
  (see `verification/README.md`).

This split is stated explicitly, not left implicit — see
`verification/README.md`'s "What CI runs vs. what stays local" section,
which this document is cross-referenced from.
