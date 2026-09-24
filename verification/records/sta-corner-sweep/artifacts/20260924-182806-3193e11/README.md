# The Yosys/ABC pin, measured (issue #143) — artifacts

**Read this first.** This directory is **not** an STA measurement and makes
no claim about any corner, any Fmax, or `layout/modexp.def`. It sits in
`sta-corner-sweep/` because the thing it measures — the mapped netlist — is
the *input* whose build-dependence record
[`20260924-134500-1a8313b`](../20260924-134500-1a8313b/) identified as the
root cause of a 1.06 ns swing in that sweep's binding corner.

It answers exactly two questions:

1. At the Yosys/ABC build now pinned by `scripts/setup-env.sh`, what does
   record `20260924-134500-1a8313b`'s committed `klt synthesize` request map
   to, and is that number deterministic?
2. Is the frozen row 5/6 figure of **1204** instances reachable from any
   publicly installable Yosys build at all?

Answers: **1105 instances, deterministic across four runs**; and **no** —
five distinct publicly installable mapper builds produce 1139 or 1105, none
produces 1204.

## What "pinned" means here, and why

The pin is a **PyPI wheel checked by content**: `yowasp-yosys==0.68.0.0.post1208`,
whose `yowasp_yosys/yosys.wasm` is
`sha256:e37a7e65e3fa4efbbd64a9c1b0e906be16cdc6c4d5273109d17537f78449f38c`.

That module is the whole point. YoWASP ships one `py3-none-any` wheel
containing a single WebAssembly build of Yosys **with `abc` compiled into
it**, so two hosts on the same pinned version execute a byte-identical
mapper — there is no per-host rebuild step for a per-host `abc` to come from.
A host-package Yosys has no such property, and `yosys -V` reports the Yosys
version while saying nothing about the embedded `abc` build. So
`scripts/setup-env.sh` verifies the wasm **digest**, not the version string,
and refuses to provision an environment whose mapper is not the pinned one.

## Files

| File | What it is |
| --- | --- |
| `synth-report-pinned-run1.json` / `synth-report-pinned-run2.json` | the `klt synthesize` responses for the two runs at the pin, verbatim. Identical field-for-field except `run_id` and the three run-scoped paths |
| `modexp_synth-pinned.v` | the mapped netlist at the pin, `sha256:d0785125176bc27c95adaffd25cb82dbb46da9038dfb63d5df39d7f3fb5404f7` — committed so a future re-run has bytes, not just a number, to diff against |
| `synth_modexp-pinned.ys` | the commit-safe Yosys script `klt synthesize` generated, for line-by-line comparison against `../20260924-134500-1a8313b/synth_modexp.ys` |
| `modexp_abc-pinned-log.txt` | ABC's own log for the mapping run (`.txt`, not `.log`, because the repo gitignores `*.log`) |
| `synth-report-yowasp-0.6{5,6,7,9}*.json` | the same request under four other publicly installable mapper builds — the "is 1204 reachable" sweep |
| `build-identity-sweep.json` | that sweep, summarized: one row per build, each with its wasm sha256 and resulting instance count |
| `rerun-pinned-synthesis.sh` | re-runs the frozen request at the pin, asserts the wasm digest first, and compares the result against this record |

## Method

The frozen inputs were staged into a gitignored scratch tree and left
byte-identical to what they are in the repository:

| Input | sha256 |
| --- | --- |
| `../20260924-134500-1a8313b/synth-request.json` | `fa8ed0e9b5dbd7283f49c9214726db4bd2bc7afd0ac9244b0877b9124fb7565c` |
| `../20260923-093000-28a7c96/candidates/rtl/modexp-bit-serial.v` | `b6ca7b2f4464e573d47e459ec8a1befa2068211593c0ead70c2922e65075aa85` |

`klt` was `0.6.0+gc66f18fd6225` — the **same revision record
`20260924-134500-1a8313b` used** — precisely so the mapper build is the only
variable between that record's synthesis leg and this one. (This repo's
standing `klt` pin, `dac2b5da`, predates `constraints.dont_use` and cannot
run this request at all; `docs/environment.md` already documents the
force-reinstall recipe for that.)

The scratch tree lives under the repo's gitignored `.klt/`, **not** under
`$TMPDIR`: the pinned Yosys is a WASI build whose sandbox mounts a private
directory over `/tmp`, so a run staged in the host temp directory cannot
read back its own generated script. `rerun-pinned-synthesis.sh` encodes
that.

## Result

**At the pin: 1105 instances, 10158.4928 µm².**

The response is identical **field for field** to
`../20260924-134500-1a8313b/synth-report-yosys-0.68.json` — same
`instance_count`, same `area_um2`, same `sequential_area_um2`, same
`instance_counts_by_type` histogram, same `leakage_by_type_nw` — with the
only differences being `run_id` and the three run-scoped output paths.

Four runs at the pin (two here, two more by `rerun-pinned-synthesis.sh`)
produced a byte-identical netlist,
`sha256:d0785125176bc27c95adaffd25cb82dbb46da9038dfb63d5df39d7f3fb5404f7`.

**One loose end, stated rather than smoothed over.** Record
`20260924-134500-1a8313b` reports its netlist digest as
`sha256:f33ededc…`; the netlist here digests to `d0785125…` even though every
*reported* synthesis metric matches that record exactly and the generated
`abc` line is flag-for-flag identical. That record committed the digest but
not the netlist, so the difference cannot be diffed after the fact — the
likeliest explanation is that the two digests were taken over differently
derived file forms, which the issue #141 Builder pass already flagged as a
possibility for its own third digest (`5750f29a…`) in a comment on issue
#143. This record commits `modexp_synth-pinned.v` itself so the next
comparison is a diff, not a digest mismatch with no bytes behind it.

## The 1204 question

| Mapper build | `yosys.wasm` sha256 | instances |
| --- | --- | --- |
| `yowasp-yosys==0.65.0.0.post1154` | `27996f8c…` | 1139 |
| `yowasp-yosys==0.66.0.0.post1165` | `975361da…` | 1139 |
| `yowasp-yosys==0.67.0.0.post1190` | `dfad61b9…` | 1105 |
| **`yowasp-yosys==0.68.0.0.post1208` (the pin)** | **`e37a7e65…`** | **1105** |
| `yowasp-yosys==0.69.0.0.post1233` | `77fe957b…` | 1105 |

Five builds, five digests, two distinct answers — and **1204 is not one of
them**. A sixth, differently-built data point (a native Homebrew Yosys
0.69+post on macOS arm64) is reported in a comment on issue #143 and also
lands on 1105; it is cited, not re-derived here, and this record does not
stand on it.

Two things follow, and both are stated plainly in `docs/environment.md`:

- The frozen **1204**-instance netlist is **not reproducible at the pin**,
  and not reachable from any publicly installable build tried. It is treated
  as an artifact of the build on the host that produced record
  `20260923-093000-28a7c96`'s candidate rows — a build that is not
  identified by anything that record captured, and so cannot be re-obtained.
- Record `20260923-093000-28a7c96`'s candidate rows **2, 5 and 6** cell
  counts are therefore **host-specific**, and any timing verdict derived
  from them is too. That is the same conclusion record
  `20260924-134500-1a8313b` reached from one contrasting build; this record
  extends it from "another host disagrees" to "no publicly installable build
  agrees".

Note also that the count is not even stable *within* the pinned family:
0.65/0.66 map to 1139 and 0.67/0.68/0.69 to 1105. Pinning the Yosys *version
series* would not have been enough; pinning the mapper by content is.

Per `CLAUDE.md`'s overclaim-trap section, no figure here is compared against
any external standard-cell library's published result.
