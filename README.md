# sky130-modexp

An RSA modular-exponentiation core on the
[sky130](https://github.com/google/skywater-pdk) open PDK, taken from RTL to
DRC/LVS-clean GDS by AI agents driving
[klayout-tools](https://github.com/2AMLogic/klayout-tools) and the
open-source digital flow — cocotb + Icarus for verification, Yosys for
synthesis, OpenROAD for place-and-route.

**Status: early.** The RTL and its bit-exact testbench exist and a synthesis
baseline is measured; nothing has been placed, routed, taped out, or measured
in silicon. See the maturity ladder below for where things currently stand.

**Built agent-native.** Every line of RTL, every testbench, every decision
record and line of documentation in this repo was produced by AI agents
working from a ratified spec and an append-only evidence trail — not
human-authored work that agents merely assisted with. Verification is the
product: correctness is a bit-exact cocotb check against a reference model,
run before any optimization claim is entertained. Where the agents hit
friction with the open-source tooling — most often
[klayout-tools](https://github.com/2AMLogic/klayout-tools) itself — that
friction gets filed as a public issue against the tool, so the fix benefits
everyone using sky130, not just this repo.

## What this block is

Square-and-multiply modular exponentiation over a shared MSB-first
interleaved ("Blakley") modular multiplier — one real modular multiplier,
reused across exponent bits, rather than an unrolled datapath. Parameterized
on `WIDTH`, verified bit-exact against Python's `pow(base, exp, mod)` at
`WIDTH` = 4, 6, 8, and 16.

## Why a digital block, in a program of analog ones

The sibling canaries (`gf180-bandgap`, `gf180-pll`, and the rest) are analog
blocks on open PDKs. This one exists because **a mixed-signal design system
requires a digital flow underneath it** — you cannot build one on an
analog-only toolchain. This block is the prerequisite, not a detour: it
exercises synthesis, place-and-route, functional verification, and the seam
where digital output re-enters the layout tools, which the analog canaries
structurally cannot reach.

## The baseline, and what it is not

Our correct implementation synthesizes to **682 cells** at `WIDTH=16`
(`klt synthesize`, Yosys against `sky130_fd_sc_hd`/`tt_025C_1v80`, sky130A
via volare). That number is recorded in
[`docs/baseline.md`](docs/baseline.md) with the exact reproduction recipe.

The task was chosen after Alibaba's Qwen3.8-Max post
([2026-08-02](https://qwen.ai/blog?id=qwen3.8)) reported an agent optimizing
a GCD/RSA modexp accelerator from 8,298 to 678 Yosys cells on a comparable
open stack. **Those numbers and ours are not comparable, in either
direction.** Yosys cell counts are standard-cell-library dependent, and that
work targeted Nangate45 while this block targets sky130. We did not beat 678
and we make no claim to have; equally, our 682 is not evidence that their
optimization was small. Different libraries are simply different
measurements.

What the comparison *did* produce is a useful structural finding: a
naturally-written correct core lands near their optimized scale, not their
starting scale, which means their published 8,298 figure describes a
deliberately un-optimized starting RTL rather than a natural implementation.
That starting RTL was never published, so it cannot be reconstructed. This
repo therefore optimizes from a good core rather than recreating a bad one —
the honest version of the exercise, and the one that produces a block worth
taping out.

## Target specification

The ratified spec, with a decision record for each previously-open
question, lives in [`spec/modexp.md`](spec/modexp.md).

Maturity ladder: RTL + bit-exact verification → synthesis baseline →
place-and-route with timing closure → DRC/LVS-clean GDS → shuttle seat →
measured silicon. **Current position: synthesis baseline.**

## Repo layout

```
spec/          ratified spec + decision records
rtl/           Verilog sources
verification/  cocotb testbenches + Icarus cross-checks
flow/          synthesis + place-and-route recipes (Yosys, OpenROAD)
layout/        GDS + DRC/LVS reports (klayout-tools driven)
docs/          baseline record, environment setup
measurements/  silicon characterization (empty until tape-out)
```

## License

Apache License 2.0 — see [LICENSE](LICENSE).
