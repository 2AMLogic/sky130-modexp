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

- **#177**: Build/runtime failure on main: test-merge-pr-workflow-scope-preflight.sh needs loom-daemon but is not in ci-excluded.txt (CI red, 4th recurrence)
- **#204**: T1 item 6: record the bound not_applicable statement (no statistical spec row) so the grader stops reporting no_evidence

## Ready

Human-approved issues ready for implementation (`loom:issue`).

- **#177**: Build/runtime failure on main: test-merge-pr-workflow-scope-preflight.sh needs loom-daemon but is not in ci-excluded.txt (CI red, 4th recurrence)
- **#204**: T1 item 6: record the bound not_applicable statement (no statistical spec row) so the grader stops reporting no_evidence

## In Progress

Issues currently being built (`loom:building`).

- **#228**: Condense layout/lvs/README.md: six stacked 'Update — read this first' sections

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

- **#254**: docs: condense layout/lvs/README.md into a current-state page

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

_None._

## Proposed

Issues carrying `loom:curated`.

- **#177**: Build/runtime failure on main: test-merge-pr-workflow-scope-preflight.sh needs loom-daemon but is not in ci-excluded.txt (CI red, 4th recurrence) *(curated)*
- **#201**: Re-qualify the 18-corner P&R rebuild sweep under open_pdks f6eeac7 (split from #191) *(curated)*
- **#204**: T1 item 6: record the bound not_applicable statement (no statistical spec row) so the grader stops reporting no_evidence *(curated)*
- **#211**: Make flow/verification tooling reusable as vendored common/ copies: parametrize design name, resolve repo root without path depth *(curated)*

## Proposed (Architect / Hermit)

- **#242**: Condense docs/signoff-claim.md: superseded verdict and history sections still read 'not met' *(hermit)*
- **#253**: Condense docs/baseline.md Leg 2 section: stale 'still FAIL' contradicts gate-level README *(hermit)*

## Epics

- **#12**: Track the gap to T1 sim-validated / bronze (klayout-tools design-evidence tiers)

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 0 |
| Important | 2 |
| Ready (`loom:issue`) | 2 |
| In Progress (`loom:building`) | 1 |
| PRs awaiting review | 1 |
| Approved PRs awaiting merge | 0 |
| Curated | 4 |
| Architect / Hermit proposals | 2 |
| Active epics | 1 |
<!-- guide:plan-body:end -->
