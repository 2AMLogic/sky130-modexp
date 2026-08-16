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
| `klayout-tools` (`klt`) | git revision [`a482d3934bd644b763cf925f6344ac05f54a1623`](https://github.com/2AMLogic/klayout-tools/commit/a482d3934bd644b763cf925f6344ac05f54a1623) | `pip install "klayout-tools @ git+https://github.com/2AMLogic/klayout-tools@a482d3934bd644b763cf925f6344ac05f54a1623"` (what `scripts/setup-env.sh` runs) |
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

`klt` in turn resolves `iverilog`/`yosys`/`openroad` and the PDK itself from
the host — it does not vendor them. Those are:

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
