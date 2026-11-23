# Work Plan

Backlog snapshot from current GitHub label state, maintained by the Guide role.

The body below is a snapshot of GitHub label state as of the last merged docs-maintenance PR — it may lag live labels until the next one merges. Date the snapshot with `git log -1 -- WORK_PLAN.md`.

<!-- Maintained automatically by the Guide triage agent. Manual edits are fine but may be overwritten. -->

<!-- guide:plan-body:start -->
_Generated: 2026-11-23T20:45:00Z (snapshot; compare against live labels)_
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs under a hold (`loom:blocked` or `loom:operator`) — only a human merge decision is missing.

_None._

## Very Important

`loom:very-important` (one counts per workspace); every stage takes these first.

_None._

## Important

`loom:important`; taken before unlabelled work.

- **#201**: Re-qualify the 18-corner P&R rebuild sweep under open_pdks f6eeac7 (split from #191) *(held)*

## Ready

Human-approved issues (`loom:issue`) ready for implementation — excluding held (`loom:blocked`/`loom:operator`/`loom:frozen`), `loom:building`, and issues closed by an open `loom:pr` PR (listed under Approved).

_None._

## In Progress

Issues currently being built (`loom:building`).

- **#310**: Remove the unused LVS plain-element control leg: layout/lvs/modexp_reference.spice and build_reference_netlist.py
- **#336**: Make evidence-record `supersedes` a list: the twin-record workaround now needs five records per re-run
- **#418**: Share transcript counting so incomplete RTL cross-checks fail

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

- **#414**: chore: remove the retired plain-element LVS control leg (modexp_reference.spice, build_reference_netlist.py)
- **#417**: feat: accept list-valued supersedes in evidence-record linter and minter
- **#419**: fix: require complete current-run transcript in RTL and gate-level cross-checks

## Approved (Awaiting Merge)

PRs that passed Judge review (`loom:pr`).

_None._

## Proposed

Issues carrying `loom:curated`.

- **#201**: Re-qualify the 18-corner P&R rebuild sweep under open_pdks f6eeac7 (split from #191) *(curated)* *(held)*
- **#211**: Make flow/verification tooling reusable as vendored common/ copies: parametrize design name, resolve repo root without path depth *(curated)* *(held)*
- **#310**: Remove the unused LVS plain-element control leg: layout/lvs/modexp_reference.spice and build_reference_netlist.py *(curated)*
- **#336**: Make evidence-record `supersedes` a list: the twin-record workaround now needs five records per re-run *(curated)*
- **#374**: cross_check_tb.py docstring still says it is driven by cocotb's Runner API, not klt *(curated)* *(held)*

## Proposed (Architect / Hermit)

_None._

## Epics

- **#12**: Track the gap to T1 sim-validated / bronze (klayout-tools design-evidence tiers)

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 0 |
| Important | 1 |
| Ready (`loom:issue`, net of holds/building/merge-pending) | 0 |
| In Progress (`loom:building`) | 3 |
| PRs awaiting review | 3 |
| Approved PRs awaiting merge | 0 |
| Curated | 5 |
| Architect / Hermit proposals | 0 |
| Active epics | 1 |
<!-- guide:plan-body:end -->
