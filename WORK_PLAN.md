# Work Plan

Prioritized roadmap generated from current GitHub label state, maintained
automatically by the Guide triage agent. Everything between the markers below
is machine-generated and overwritten wholesale on each update; do not
hand-edit that region.

<!-- guide:plan-body:start -->
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs stuck under a `loom:operator` merge-risk hold — implementation work is done, only a human merge decision is missing.

- **#155**: fix(curator): read the prior heartbeat marker completely, confirm under the claim (#154)
- **#159**: fix(guard): honor same-command cd for installed-file-write target normalization

## Operator Priority

Issues the operator starred (`loom:operator-priority`); land these first.

_None._

## Ready

Human-approved issues ready for implementation (`loom:issue`).

_None._

## In Progress

Issues currently being built (`loom:building`).

_None._

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

_None._

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

- **#155**: fix(curator): read the prior heartbeat marker completely, confirm under the claim (#154)
- **#159**: fix(guard): honor same-command cd for installed-file-write target normalization

## Proposed

Issues carrying `loom:curated`.

- **#135**: README: embed the fleet burndown chart (one line) *(curated)*
- **#139**: LVS item 4: the last 12 mismatches need an as-built post-route netlist, which this GDS does not have *(curated)*
- **#144**: Decide whether to land the 17/18 bit-serial re-spin (DR-0005 Decision 1 left it unlanded) *(curated)*
- **#154**: Curator's operator-premise idempotency check is spamming #12 with duplicate heartbeats (27/43 gaps <24h, min 23min) *(curated)*

## Proposed (Architect / Hermit)

_None._

## Epics

- **#12**: Track the gap to T1 sim-validated / bronze (klayout-tools design-evidence tiers)

## Backlog Balance

| Tier | Count |
|------|-------|
| Operator merge-risk holds | 2 |
| Operator priority | 0 |
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 0 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 2 |
| Curated | 4 |
| Architect / Hermit proposals | 0 |
| Active epics | 1 |
<!-- guide:plan-body:end -->
