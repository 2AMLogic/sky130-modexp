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
`volare`, and reports which of `iverilog` / `yosys` / `openroad` are missing
from `$PATH` — with an actionable install pointer for each, never a
traceback. It is safe to re-run; it reuses an existing `.venv` and an
already-fetched PDK version.

Activate the venv for interactive use with:

```bash
source .venv/bin/activate
```

## Pinned versions

| Component | Pinned to | Resolved via |
|---|---|---|
| `klayout-tools` (`klt`) | git revision [`af5791b557fc7c669c3981335a294256ccf37e6f`](https://github.com/2AMLogic/klayout-tools/commit/af5791b557fc7c669c3981335a294256ccf37e6f) | `pip install "klayout-tools @ git+https://github.com/2AMLogic/klayout-tools@af5791b557fc7c669c3981335a294256ccf37e6f"` (what `scripts/setup-env.sh` runs) |
| `sky130A` PDK | `open_pdks` commit `c6d73a35f524070e85faff4a6a9eef49553ebc2b` | `volare enable --pdk-root ~/.volare --pdk sky130 c6d73a35f524070e85faff4a6a9eef49553ebc2b` |
| `cocotb` | 2.0.1 (pulled in as a `klayout-tools` dependency) | installed alongside `klt` by `scripts/setup-env.sh` |
| Python | <= 3.13 (cocotb 2.0.1 refuses to build on 3.14+) | `scripts/setup-env.sh` auto-selects `python3.13` > `3.12` > `3.11` > `3.10` > `python3`, whichever is the newest compatible interpreter found on `$PATH` |

`klt` in turn resolves `iverilog`/`yosys`/`openroad` and the PDK itself from
the host — it does not vendor them. Those are:

| Tool | Used for | Resolved version on the environment these records were produced on |
|---|---|---|
| Icarus Verilog (`iverilog`) | `klt functional-verification`, `verification/cross_check.py` | 13.0 (stable) (`iverilog -V`) |
| Yosys (`yosys`) | `klt synthesize` | 0.68+post (`yosys -V`) |
| OpenROAD (`openroad`) | `klt place-and-route` | **not installed** — see "OpenROAD" below |

Package-manager installs for the first two:

```bash
# macOS (Homebrew)
brew install icarus-verilog yosys

# Debian/Ubuntu
apt-get install iverilog yosys
```

## OpenROAD (currently missing)

`openroad` is **not on `$PATH`** on the environment this document was
written from, and there is no Homebrew formula (`brew search openroad`
returns nothing) or common-distro package for it as of this writing. This
is what blocks the place-and-route rung of the maturity ladder (issue #5's
originating problem statement, item 4) — it is a provisioning gap, not a
design decision.

Options to get `openroad` on `$PATH`, roughly in order of effort:

1. **Precompiled binaries / Docker image** — see
   [`The-OpenROAD-Project/OpenROAD` § Install](https://github.com/The-OpenROAD-Project/OpenROAD#install)
   for current release artifacts, or pull the flow-scripts image
   (`docker pull openroad/orfs`) and run OpenROAD inside the container.
2. **Build from source via OpenROAD-flow-scripts** —
   [`The-OpenROAD-Project/OpenROAD-flow-scripts`](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts),
   `./build_openroad.sh --local` (a from-source build with its own toolchain
   dependencies — see that repo's own docs for platform prerequisites).

Once `openroad` resolves on `$PATH`, `scripts/setup-env.sh`'s toolchain
check will report it found and no longer list it under "MISSING TOOLS"; no
other change to this repo's tooling is required to unblock
`klt place-and-route`.

## Why local, not CI, for the PDK-heavy legs

CI (`.github/workflows/ci.yml`) does not fetch `sky130A` or provision
`openroad` — provisioning a real PDK (and, eventually, `openroad`) in a
hosted CI runner on every PR is a real, recurring cost this repo has chosen
not to pay per-PR. Instead:

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
