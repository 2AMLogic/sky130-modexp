# Work Plan

Backlog snapshot from current GitHub label state, maintained by the Guide role.

The body below is a snapshot of GitHub label state as of the last merged docs-maintenance PR — it may lag live labels until the next one merges. Date the snapshot with `git log -1 -- WORK_PLAN.md`.

<!-- Maintained automatically by the Guide triage agent. Manual edits are fine but may be overwritten. -->

<!-- guide:plan-body:start -->
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs under a hold (`loom:blocked` or `loom:operator`) — only a human merge decision is missing.

- **#402**: docs: ratify DR-0017 via the two-key step (status-only flip)

## Very Important

`loom:very-important` (one counts per workspace); every stage takes these first.

_None._

## Important

`loom:important`; taken before unlabelled work.

- **#201**: Re-qualify the 18-corner P&R rebuild sweep under open_pdks f6eeac7 (split from #191)

## Ready

Human-approved issues ready for implementation (`loom:issue`).

_None._

## In Progress

Issues currently being built (`loom:building`).

- **#400**: T1 item 5: open the ratification PR for DR-0017 (status flip only) so the EE key, market key and operator have a PR to act on

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

_None._

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

- **#402**: docs: ratify DR-0017 via the two-key step (status-only flip)

## Proposed

Issues carrying `loom:curated`.

- **#201**: Re-qualify the 18-corner P&R rebuild sweep under open_pdks f6eeac7 (split from #191) *(curated)*
- **#211**: Make flow/verification tooling reusable as vendored common/ copies: parametrize design name, resolve repo root without path depth *(curated)*
- **#374**: cross_check_tb.py docstring still says it is driven by cocotb's Runner API, not klt *(curated)*
- **#400**: T1 item 5: open the ratification PR for DR-0017 (status flip only) so the EE key, market key and operator have a PR to act on *(curated)*

## Proposed (Architect / Hermit)

- **#310**: Remove the unused LVS plain-element control leg: layout/lvs/modexp_reference.spice and build_reference_netlist.py *(hermit)*
- **#336**: Make evidence-record `supersedes` a list: the twin-record workaround now needs five records per re-run *(hermit)*

## Epics

- **#12**: Track the gap to T1 sim-validated / bronze (klayout-tools design-evidence tiers)

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 1 |
| Very important | 0 |
| Important | 1 |
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 1 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 1 |
| Curated | 4 |
| Architect / Hermit proposals | 2 |
| Active epics | 1 |
<!-- guide:plan-body:end -->
