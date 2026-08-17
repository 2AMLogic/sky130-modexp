# Work Log

Chronological record of merged PRs and closed issues, maintained automatically
by the Guide triage agent. Entries are grouped by date (UTC), newest first.

### 2026-08-16

- **Issue #60** (closed): Dedup SPICE .SUBCKT/LEF MACRO parsing between build_reference_netlist.py and spice_to_verilog.py
- **PR #63**: refactor: dedup SPICE .SUBCKT/LEF MACRO parsing
- **Issue #55** (closed): Bump klayout-tools pin and re-run DRC, LVS, and post-layout SDF (Leg 2) — upstream fixes already merged
- **PR #65**: feat(verification): bump klayout-tools pin, re-verify DRC clean, re-attempt LVS/SDF with fresh evidence
- **Issue #56** (closed): Re-run place-and-route with revised floorplan/cell-mapping to narrow the slow-corner timing gap (no RTL change)
- **PR #61**: feat(flow): mapping-only floorplan re-run to narrow slow-corner timing gap
- **Issue #58** (closed): Auditor guard-telemetry: rm-scope-outside-repo denied $HOME/.loom token-cache rm — confirm keep-flagged
- **Issue #54** (closed): Decompose the T1 re-read's failing items (#48) into dispatchable issues
- **PR #57**: docs: record #54's decomposition of #48's FAIL items into #55 and #56

### 2026-08-15

- **Issue #52** (closed): Auditor guard-telemetry: gh-api-rawfield-body-literal-at denied — confirm keep-flagged
- **Issue #50** (closed): Auditor guard-telemetry: stash-scope:create-redirect denied — confirm keep-flagged
- **Issue #48** (closed): T1/bronze checklist re-read against current evidence (2026-08-15)
- **Issue #45** (closed): Fix stale cross-repo references in test_modexp.py's module docstring
- **PR #47**: docs: fix stale cross-repo references in test_modexp.py docstring
- **Issue #43** (closed): Dedup _reexec_into_venv_if_needed between cross_check.py and gate_level_cross_check.py
- **Issue #39** (closed): Dedup _reexec_into_venv_if_needed between cross_check.py and gate_level_cross_check.py
- **PR #42**: refactor(verification): dedup venv re-exec handshake into _repo_utils
- **Issue #35** (closed): Build/runtime failure on main: gate-level-sim evidence record has stale provenance hashes
- **PR #40**: fix(verification): mint fresh gate-level-sim record, fix _dut.py symlink gap
- **Issue #38** (closed): Build failure on main: stale provenance hash in gate-level-sim evidence record (PR #26)
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
