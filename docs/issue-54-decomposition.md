# Decomposition of #48's T1 re-read FAIL items (issue #54)

This note records how issue #54 decomposed #48's closing verdict table
(2026-08-15, read against `main` @ `2d1814a`) into dispatchable issues. It is
not itself a spec, a decision record, or a grant — it is a pointer between
#48's table and the issues filed against it, kept for anyone reading the git
history rather than the issue tracker.

## #48's verdict table (for reference)

| # | Item | Verdict |
|---|---|---|
| 1 | Design sources | PASS |
| 2 | Layout | PASS |
| 3 | DRC clean | **FAIL** |
| 4 | LVS clean | **FAIL** |
| 5 | Full corner verification vs ratified spec | **FAIL** (partial evidence) |
| 6 | Statistical (Monte Carlo) claims | N/A (no statistical spec row) |
| 7 | Post-layout verification (Leg 2 / SDF) | **FAIL** |
| 8 | Characterization report | PASS |
| 9 | Testbenches shipped | PASS |
| 10 | Repo hygiene | PASS |

5/10 pass, 1 N/A, 4 FAIL (items 3, 4, 5, 7). See #48's closing comment for the
full citation-backed table.

## Issues filed against the FAIL items

| Item(s) | Issue | Grouping rationale |
|---|---|---|
| 3 (DRC), 4 (LVS), 7 (post-layout SDF/Leg 2) | #55 | Grouped: all three FAILs trace to one root cause — this repo's `klayout-tools` pin (`docs/environment.md`, `af5791b557...`, 2026-08-04) predates the upstream fixes for all three blockers ([klayout-tools#995](https://github.com/2AMLogic/klayout-tools/issues/995)/[#998](https://github.com/2AMLogic/klayout-tools/pull/998), [#996](https://github.com/2AMLogic/klayout-tools/issues/996)/[#997](https://github.com/2AMLogic/klayout-tools/pull/997), [#1002](https://github.com/2AMLogic/klayout-tools/issues/1002)/[#1007](https://github.com/2AMLogic/klayout-tools/pull/1007)), all merged upstream 2026-08-15. Verified live against the forge on 2026-08-16: all three fix PRs are merged and all three upstream tracking issues are closed. Filed as a "bump the pin + re-run + update verdict" issue, not an upstream-blocked tracking issue. |
| 5 (full 18-corner timing closure) | #56 | Separate issue: pure in-repo design work with no upstream blocker. Follows `spec/decision-records/0002-slow-corner-timing-closure-and-mm-red-critical-path.md`'s named first step — a floorplan/cell-mapping-only place-and-route re-run, no RTL change, no new decision record. The record's Step 2 (RTL restructuring of the `mm_sum`/`mm_red` critical path) is explicitly deferred to its own, separate, decision-record-gated issue — not bundled here. |
| 6 (N/A) | — | Correctly N/A per #48; no issue needed. |

Both #55 and #56 are filed unlabeled (per #54's guardrail — Curator/Champion
promote through the normal pipeline) and link back to epic #12 (this block's
gap-to-T1 tracker).

Neither item failed on a spec-level/ratification question, so neither routes
as an operator-decision request — #54's spec-gated-item branch does not apply
here.
