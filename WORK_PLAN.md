# Work Plan

Prioritized roadmap generated from current GitHub label state, maintained
automatically by the Guide triage agent. Everything between the markers below
is machine-generated and overwritten wholesale on each update; do not
hand-edit that region.

<!-- guide:plan-body:start -->
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs stuck under a `loom:operator` merge-risk hold — implementation work is done, only a human merge decision is missing.

- **#41**: fix(guard): resolve double-quoted $VAR write targets in guard-destructive-generic.sh

## Urgent

Issues flagged as highest priority (`loom:urgent`).

- **#60**: Dedup SPICE .SUBCKT/LEF MACRO parsing between build_reference_netlist.py and spice_to_verilog.py
- **#55**: Bump klayout-tools pin and re-run DRC, LVS, and post-layout SDF (Leg 2) — upstream fixes already merged

## Ready

Human-approved issues ready for implementation (`loom:issue`).

- **#60**: Dedup SPICE .SUBCKT/LEF MACRO parsing between build_reference_netlist.py and spice_to_verilog.py
- **#55**: Bump klayout-tools pin and re-run DRC, LVS, and post-layout SDF (Leg 2) — upstream fixes already merged
- **#37**: Auditor guard-telemetry: worktree-write-confinement-unresolved-var recurs as a likely false positive

## In Progress

Issues currently being built (`loom:building`).

_None._

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

_None._

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

- **#41**: fix(guard): resolve double-quoted $VAR write targets in guard-destructive-generic.sh

## Proposed

Issues carrying `loom:curated`.

- **#60**: Dedup SPICE .SUBCKT/LEF MACRO parsing between build_reference_netlist.py and spice_to_verilog.py *(curated)*
- **#55**: Bump klayout-tools pin and re-run DRC, LVS, and post-layout SDF (Leg 2) — upstream fixes already merged *(curated)*

## Proposed (Architect / Hermit)

- **#24**: Dedup DUT-driver helpers between test_modexp.py and cross_check_tb.py *(hermit)*

## Epics

- **#12**: Track the gap to T1 sim-validated / bronze (klayout-tools design-evidence tiers)

## Backlog Balance

| Tier | Count |
|------|-------|
| Operator merge-risk holds | 1 |
| Urgent | 2 |
| Ready (`loom:issue`) | 3 |
| In Progress (`loom:building`) | 0 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 1 |
| Curated | 2 |
| Architect / Hermit proposals | 1 |
| Active epics | 1 |
<!-- guide:plan-body:end -->
