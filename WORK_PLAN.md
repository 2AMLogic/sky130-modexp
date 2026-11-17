# Work Plan

Prioritized roadmap generated from current GitHub label state, maintained
automatically by the Guide triage agent. Everything between the markers below
is machine-generated and overwritten wholesale on each update; do not
hand-edit that region.

<!-- guide:plan-body:start -->
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs under a hold (`loom:blocked` or `loom:operator`) — only a human merge decision is missing.

_None._

## Very Important

`loom:very-important` (one counts per workspace); every stage takes these first.

_None._

## Important

`loom:important`; taken before unlabelled work.

- **#201**: Re-qualify the 18-corner P&R rebuild sweep under open_pdks f6eeac7 (split from #191)

## Ready

Human-approved issues ready for implementation (`loom:issue`).

- **#319**: Correct verification/gate-level/README.md: stale 718-instance / 'no PDN' / 'no netlist export' claims contradict the committed netlist
- **#320**: Retire the gate-level testbench symlinks via testbench.search_path, and correct the stale klt gap lists
- **#321**: Remove two retired entries from .github/ci-suites-consumer-skips.txt: upstream ci-excluded.txt now lists both suites
- **#327**: Item 8 characterization report still says LVS `mismatch`: update the Signoff row to the DR-0012 verdict and regenerate the envelope
- **#330**: Remove spec/README.md's per-record prose index: 11 of 17 decision records unlisted, stale since 0007

## In Progress

Issues currently being built (`loom:building`).

- **#314**: Route verification/cross_check.py's per-WIDTH runs through klt functional-verification: the parameter-override gap is closed at the pinned klt
- **#338**: Deduplicate the two identical Loom suite-runners in ci.yml: 43 of ~50 code lines are byte-identical across guard-hooks and merge-pr-suites

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

_None._

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

- **#309**: docs(flow): record klayout-tools#854 closed at the current klt pin
- **#333**: refactor(verification): resolve the repo root and content hashes through _repo_utils
- **#339**: docs: correct README status to the graded DRC/LVS verdict and 10-of-18 corners
- **#345**: refactor(shell): give $DESIGN and $KLT one implementation in scripts/design-env.sh

## Proposed

Issues carrying `loom:curated`.

- **#201**: Re-qualify the 18-corner P&R rebuild sweep under open_pdks f6eeac7 (split from #191) *(curated)*
- **#211**: Make flow/verification tooling reusable as vendored common/ copies: parametrize design name, resolve repo root without path depth *(curated)*
- **#319**: Correct verification/gate-level/README.md: stale 718-instance / 'no PDN' / 'no netlist export' claims contradict the committed netlist *(curated)*
- **#320**: Retire the gate-level testbench symlinks via testbench.search_path, and correct the stale klt gap lists *(curated)*
- **#327**: Item 8 characterization report still says LVS `mismatch`: update the Signoff row to the DR-0012 verdict and regenerate the envelope *(curated)*
- **#328**: README status paragraph is stale: it says a clean DRC/LVS verdict is still open and cites 17/18 corners for the shipped layout *(curated)*
- **#350**: gate_level_cross_check.py ignores $KLT when resolving the klt binary, so the documented pin-check recipe does not reach that leg *(curated)*

## Proposed (Architect / Hermit)

- **#310**: Remove the unused LVS plain-element control leg: layout/lvs/modexp_reference.spice and build_reference_netlist.py *(hermit)*
- **#336**: Make evidence-record `supersedes` a list: the twin-record workaround now needs five records per re-run *(hermit)*

## Epics

- **#12**: Track the gap to T1 sim-validated / bronze (klayout-tools design-evidence tiers)

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 0 |
| Important | 1 |
| Ready (`loom:issue`) | 5 |
| In Progress (`loom:building`) | 2 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 4 |
| Curated | 7 |
| Architect / Hermit proposals | 2 |
| Active epics | 1 |
<!-- guide:plan-body:end -->
