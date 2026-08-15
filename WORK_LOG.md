# Work Log

Chronological record of merged PRs and closed issues, maintained automatically
by the Guide triage agent. Entries are grouped by date (UTC), newest first.

### 2026-08-15

- **Issue #9** (closed): Re-run the bit-exact suite against the post-route gate-level netlist across the corner set
- **PR #26**: Simulate the routed layout's own gate-level netlist against the unmodified bit-exact suite
- **Issue #29** (closed): Remove duplicated git/sha256 helpers in verification/check_records.py and cross_check.py
- **PR #32**: refactor: extract shared git/sha256 helpers into verification/_repo_utils.py
- **Issue #25** (closed): bug: cross_check.py never re-execs into .venv, so npm run test fails on a provisioned local checkout
- **PR #30**: fix: compare interpreter directory, not resolved path, in venv re-exec guard
- **Issue #23** (closed): Remove duplicated reset/run_modexp DUT helpers across verification test files
- **PR #27**: refactor: extract shared DUT reset/run_modexp helpers into verification/_dut.py
- **Issue #20** (closed): Remove unused base_dir_for_relpaths parameter from check_hash_freshness
- **PR #22**: refactor: drop unused base_dir_for_relpaths param from check_hash_freshness
- **Issue #8** (closed): DRC and LVS the routed GDS, with the deck's coverage gaps stated as part of the verdict
- **PR #19**: docs+layout: DRC and LVS the routed GDS, with deck coverage gaps in the verdict
- **Issue #16** (closed): Decision record: 100 MHz closes at tt/ff corners but fails at every ss corner (issue #7's full 18-corner P&R sweep)
- **PR #18**: Record decision 0002: slow-corner timing closure status and the mm_red critical path

### 2026-08-14

- **Issue #7** (closed): Place and route to a routed GDS, and report the Fmax and area the spec's deferred decisions are waiting on
- **PR #17**: Place and route modexp to a routed GDS at 100 MHz, sweep the full corner matrix
- **Issue #15** (closed): Guard false-positive: worktree-write-confinement-unresolved-var blocks legitimate variable-path writes into the worktree
- **Issue #13** (closed): Provision openroad on the build host — unblocks P&R (#7), DRC/LVS (#8), and the post-route bit-exact re-run (#9)
- **PR #14**: Provision openroad via a pinned Docker route

### 2026-08-08

- **Issue #5** (closed): Bootstrap the digital evidence harness: ship the multi-WIDTH cross-check, pin the tool/PDK environment, and enforce it in CI
- **PR #11**: feat(verification): add multi-WIDTH cross-check, append-only record convention, and CI
- **Issue #6** (closed): Spec gap: the ratified correctness claim is unconditional, the design has an input-domain precondition, and there is no corner matrix
- **PR #10**: docs(spec): ratify input-domain, interface, and corner-matrix decision record

### 2026-08-05

- **Issue #2** (closed): Migrate the RTL, testbench, and baseline from klayout-tools
- **PR #4**: feat: migrate modexp RTL and cocotb testbench from klayout-tools
- **Issue #1** (closed): Ratify the target spec
- **PR #3**: docs: ratify modexp target spec with decision record
