# Work Plan

Backlog snapshot from current GitHub label state, maintained by the Guide role.

The body below is a snapshot of GitHub label state as of the last merged docs-maintenance PR — it may lag live labels until the next one merges. Date the snapshot with `git log -1 -- WORK_PLAN.md`.

<!-- Maintained automatically by the Guide triage agent. Manual edits are fine but may be overwritten. -->

<!-- guide:plan-body:start -->
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs under a hold (`loom:blocked` or `loom:operator`) — only a human merge decision is missing.

_None._

## Very Important

`loom:very-important` (one counts per workspace); every stage takes these first.

- **#446**: T1 item 5: single-corner probe of DR-0017's pipelined column halves at ss_n40C_1v28 vs the ratified 100 MHz

## Important

`loom:important`; taken before unlabelled work.

- **#201**: Re-qualify the 18-corner P&R rebuild sweep under open_pdks f6eeac7 (split from #191)
- **#446**: T1 item 5: single-corner probe of DR-0017's pipelined column halves at ss_n40C_1v28 vs the ratified 100 MHz

## Ready

Human-approved issues ready for implementation (`loom:issue`).

_None._

## In Progress

Issues currently being built (`loom:building`).

- **#423**: Condense superseded Update layers and duplicate gate-level/STA narratives in docs/signoff-claim.md
- **#446**: T1 item 5: single-corner probe of DR-0017's pipelined column halves at ss_n40C_1v28 vs the ratified 100 MHz

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

- **#425**: docs: condense superseded DRC/gate-level/timing layers in signoff-claim.md

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

_None._

## Proposed

Issues carrying `loom:curated`.

- **#201**: Re-qualify the 18-corner P&R rebuild sweep under open_pdks f6eeac7 (split from #191) *(curated)*
- **#211**: Make flow/verification tooling reusable as vendored common/ copies: parametrize design name, resolve repo root without path depth *(curated)*
- **#374**: cross_check_tb.py docstring still says it is driven by cocotb's Runner API, not klt *(curated)*
- **#446**: T1 item 5: single-corner probe of DR-0017's pipelined column halves at ss_n40C_1v28 vs the ratified 100 MHz *(curated)*

## Proposed (Architect / Hermit)

_None._

## Epics

- **#12**: Track the gap to T1 sim-validated / bronze (klayout-tools design-evidence tiers)

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 1 |
| Important | 2 |
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 2 |
| PRs awaiting review | 1 |
| Approved PRs awaiting merge | 0 |
| Curated | 4 |
| Architect / Hermit proposals | 0 |
| Active epics | 1 |
<!-- guide:plan-body:end -->
