# sky130-modexp — agent instructions

Open-source canary block: an RSA modular-exponentiation core on the sky130
PDK, designed and verified by AI agents. This is the program's first
**digital** block — the flow here is RTL→GDS, not schematic→layout.

- **PDK**: sky130 (open PDK). Open-source flow: cocotb + Icarus for
  functional verification, Yosys for synthesis, OpenROAD for place-and-route,
  klayout-tools (`klt`) for DRC/LVS on the produced GDS. `klt synthesize`,
  `klt functional-verification`, and `klt drc` are the entry points — drive
  the engines through `klt` rather than around it, since dogfooding that
  surface is half the point of this repo.
- **Friction protocol (the canary's job)**: every time klayout-tools is
  awkward, missing a capability, or wrong for what you need, file an issue at
  `2AMLogic/klayout-tools` describing the tool gap generically — that tracker
  is scoped to the tool, so keep design-specific detail (spec values, this
  repo's content) out of it and describe the gap, not the design.
- **Correctness gates everything.** No optimization result counts unless the
  bit-exact cocotb suite passes at every verified `WIDTH` on the same commit.
  A smaller cell count on a design that fails verification is not a result.
- **Verification is the product**: no claim without a testbench. Recorded
  results in `verification/` are append-only evidence.
- Spec changes go through `spec/` with a decision record; agents do not relax
  the ratified spec to make results pass.

## The overclaim trap — read before writing any number down

This block's task was chosen because an external lab published cell counts
for the same task. **Their numbers and ours are not comparable.** Yosys cell
counts depend on the standard-cell library; their work used Nangate45 and
this repo uses sky130. Nothing in this repo, its issues, its PRs, or any copy
derived from it may state or imply that we beat, matched, or fell short of
their figure. Directional statements about the *task* and the *class of flow*
are fine; number-to-number comparisons are not. See `docs/baseline.md`.

## Harness bootstrap

The RTL, the cocotb testbench, and the measured synthesis baseline were
produced in `2AMLogic/klayout-tools` before this repo existed (PR #488).
Migrate them here rather than rewriting them — see issue #2.

<!-- BEGIN LOOM ORCHESTRATION -->
This repository uses [Loom](https://github.com/rjwalters/loom) for AI-powered development orchestration — see the Loom repository for the full guide (roles, labels, worktrees, configuration). When installed, Loom also writes a locally-substituted copy of that guide to `.loom/CLAUDE.md`.
<!-- END LOOM ORCHESTRATION -->
