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

_None._

## Important

`loom:important`; taken before unlabelled work.

- **#201**: Re-qualify the 18-corner P&R rebuild sweep under open_pdks f6eeac7 (split from #191)

## Ready

Human-approved issues ready for implementation (`loom:issue`).

_None._

## In Progress

Issues currently being built (`loom:building`).

- **#310**: Remove the unused LVS plain-element control leg: layout/lvs/modexp_reference.spice and build_reference_netlist.py
- **#421**: Evidence-record linter never cross-checks the **Supersedes** prose bullet against the meta value
- **#423**: Condense superseded Update layers and duplicate gate-level/STA narratives in docs/signoff-claim.md

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

- **#414**: chore: remove the retired plain-element LVS control leg (modexp_reference.spice, build_reference_netlist.py)
- **#426**: feat: cross-check Supersedes prose bullet ids against record-meta

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

_None._

## Proposed

Issues carrying `loom:curated`.

- **#201**: Re-qualify the 18-corner P&R rebuild sweep under open_pdks f6eeac7 (split from #191) *(curated)*
- **#211**: Make flow/verification tooling reusable as vendored common/ copies: parametrize design name, resolve repo root without path depth *(curated)*
- **#310**: Remove the unused LVS plain-element control leg: layout/lvs/modexp_reference.spice and build_reference_netlist.py *(curated)*
- **#374**: cross_check_tb.py docstring still says it is driven by cocotb's Runner API, not klt *(curated)*
- **#421**: Evidence-record linter never cross-checks the **Supersedes** prose bullet against the meta value *(curated)*

## Proposed (Architect / Hermit)

- **#427**: Remove seven stale, self-contradictory pre-#232/#246 passages from verification/signoff/README.md *(hermit)*

## Epics

- **#12**: Track the gap to T1 sim-validated / bronze (klayout-tools design-evidence tiers)

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 0 |
| Important | 1 |
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 3 |
| PRs awaiting review | 2 |
| Approved PRs awaiting merge | 0 |
| Curated | 5 |
| Architect / Hermit proposals | 1 |
| Active epics | 1 |
<!-- guide:plan-body:end -->
