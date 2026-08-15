# Work Plan

Prioritized roadmap generated from current GitHub label state, maintained
automatically by the Guide triage agent. Everything between the markers below
is machine-generated and overwritten wholesale on each update; do not
hand-edit that region.

<!-- guide:plan-body:start -->
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs stuck under a `loom:operator` merge-risk hold — implementation work is done, only a human merge decision is missing.

_None._

## Urgent

Issues flagged as highest priority (`loom:urgent`).

_None._

## Ready

Human-approved issues ready for implementation (`loom:issue`).

_None._

## In Progress

Issues currently being built (`loom:building`).

- **#23**: Remove duplicated reset/run_modexp DUT helpers across verification test files
- **#9**: Re-run the bit-exact suite against the post-route gate-level netlist across the corner set

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

- **#27**: refactor: extract shared DUT reset/run_modexp helpers into verification/_dut.py

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

- **#26**: Simulate the routed layout's own gate-level netlist against the unmodified bit-exact suite

## Proposed

Issues carrying `loom:curated`.

- **#25**: bug: cross_check.py never re-execs into .venv, so npm run test fails on a provisioned local checkout *(curated)*
- **#9**: Re-run the bit-exact suite against the post-route gate-level netlist across the corner set *(curated)*

## Proposed (Architect / Hermit)

- **#9**: Re-run the bit-exact suite against the post-route gate-level netlist across the corner set *(architect)*
- **#24**: Dedup DUT-driver helpers between test_modexp.py and cross_check_tb.py *(hermit)*

## Epics

- **#12**: Track the gap to T1 sim-validated / bronze (klayout-tools design-evidence tiers)

## Backlog Balance

| Tier | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Urgent | 0 |
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 2 |
| PRs awaiting review | 1 |
| Approved PRs awaiting merge | 1 |
| Curated | 2 |
| Architect / Hermit proposals | 2 |
| Active epics | 1 |
<!-- guide:plan-body:end -->
