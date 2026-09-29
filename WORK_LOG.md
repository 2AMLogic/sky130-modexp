# Work Log

Chronological record of merged PRs and closed issues, maintained automatically
by the Guide triage agent. Entries are grouped by date (UTC), newest first.

### 2026-09-27

- **Issue #156** (closed): CI: 'Loom merge-pr.sh regression suites' job red on main since resync 31aa731 (daemon-backed suites have no loom-daemon)
- **PR #157**: ci: skip daemon-backed merge-pr suites listed in ci-excluded.txt

### 2026-09-24

- **Issue #151** (closed): Auditor guard-telemetry: rm-scope-unresolved-var denies 3 same-session rm -rf calls — 1 refinable, 2 correctly flagged
- **PR #153**: fix(guard): resolve one-hop literal variable chains in rm-scope (#151)
- **PR #152**: test(guard): add rm-scope-unresolved-var regression evidence for issue #151
- **Issue #146** (closed): Auditor guard-telemetry: worktree-write-confinement denies sweep's own main-clean baseline snapshot
- **PR #150**: fix(guard): exempt .loom/sweep-checkpoint/ from worktree-write-confinement (#146)
- **Issue #148** (closed): Nothing checks that scripts/setup-env.sh's pin constants match docs/environment.md's pinned-versions table
- **PR #149**: feat(lint): check setup-env.sh pin constants against docs/environment.md's pinned-versions table
- **Issue #143** (closed): Pin the Yosys/ABC build: unpinned mapper moved slow-corner setup slack by 1.06 ns across the closure threshold
- **PR #147**: feat(env): pin the Yosys/ABC mapper by content, and record what it maps to
- **Issue #141** (closed): Land the measured 18/18 slow-corner closure (DR-0004 Decision 2's priced exit) — blocked on klayout-tools#2382
- **PR #145**: evidence(sta): run DR-0004 Decision 2's priced exit — 17/18, not 18/18

### 2026-09-23

- **Issue #132** (closed): T1 item 5: 100 MHz closes at only 10/18 corners — binding corner ss_n40C_1v28 at 22.80 MHz
- **PR #142**: feat(signoff): cite T1 item 5's failing 18-corner sweep, and ratify the disclosed exception with its measured exit
- **Issue #131** (closed): T1 item 4: LVS reports mismatch (17, all physical-only/fixup cells) — attribution is complete but item 4 needs status: match
- **PR #140**: feat(lvs): gate-level-verilog reference — power connectivity match, filler/tap pruned with disclosure, second engine cross-checked
- **Issue #133** (closed): T1 item 7: no SDF-annotated post-layout regression exists (a zero-delay run renders not_post_layout)
- **PR #138**: feat(verification): pass the SDF-annotated post-route regression as net-delay back-annotation
- **Issue #129** (closed): T1 item 11 (power delivery, structural): no klt erc supply spec or report in this repo
- **PR #137**: feat(layout): add klt erc supply evidence for T1 item 11
- **Issue #130** (closed): Commit a klt signoff block manifest so this block's T1 state is graded, not hand-read
- **PR #136**: feat(signoff): commit klt signoff block manifest as the graded T1 verdict of record

### 2026-09-16

- **Issue #96** (closed): test-guard-destructive-generic-resolve-var.sh: cases (i)/(j) ($(mktemp -d) chain) unexpectedly ALLOW under macOS's bwk-awk
- **PR #128**: test: flip resolve-var (i)/(j) to allow and drop the CI carve-out
- **Issue #126** (closed): CI does not run .loom/scripts/tests/ — resync commits can revert a fix AND its regression test with CI green
- **PR #127**: ci: add CI job for .loom/scripts/tests/test-merge-pr-*.sh suites
- **Issue #124** (closed): merge-pr.sh crashes on almost every merge: resync 9118550 also reverted the champion:hold-state `|| true` fix (#110)
- **PR #125**: fix(scripts): restore merge-pr.sh champion:hold-state `|| true` guard reverted by resync
- **Issue #118** (closed): Loom guard-hook regression suites: case (k) failing on main's own CI, unrelated to any diff
- **PR #120**: fix(guard): restore resolve_var() mid-token $VAR substitution reverted by resync (#98)
- **Issue #121** (closed): guard-hooks CI red on main: resync 9118550 also reverted the qsplit line-continuation (#99) and mkdir-confinement (#100) fixes, not just resolve_var
- **PR #123**: fix(guard): restore qsplit continuation join and mkdir write-confinement
- **Issue #119** (closed): test-guard-destructive-generic-resolve-var.sh's "BACKPORT, NOT A LOCAL INVENTION" header is wrong for cases (k)-(p)
- **PR #122**: fix(docs): scope resolve_var backport claim to cases (a)-(j) only

### 2026-09-15

- **Issue #113** (closed): chore: harden resync-installed.sh (or upstream) so guard-hook fixes survive future resyncs
- **PR #117**: fix(scripts): harden resync-installed.sh against silently reverting a locally-fixed installed file
- **Issue #115** (closed): mkdir worktree-confinement escape checks silently ALLOW on macOS (6/16 fail in test-guard-destructive-generic-mkdir-confinement.sh; CI-Linux shows 16/16 on the same commit)
- **PR #116**: fix(guard): resolve mkdir write-target through physical_abs_path() before main-checkout containment check
- **PR #97**: docs(lvs): confirm counts.pins.matched semantics, fix 333/333 phrasing
- **Issue #94** (closed): Auditor guard-telemetry: stash-scope:worktree-collision asked — confirm keep-flagged or allowlist
- **PR #91**: feat(verification): STA-characterize the committed layout at all 18 corners
- **Issue #86** (closed): T1/bronze checklist re-read against current evidence (2026-09-15), incl. post-#81 STA re-sweep + fresh LVS report
- **Issue #87** (closed): LVS-closure methodology decision record: recommend one route from docs/signoff-claim.md
- **PR #89**: docs(decision-records): recommend a route for LVS-closure methodology

### 2026-09-11

- **Issue #83** (closed): verification/gate-level's spice_to_verilog.py can't derive a netlist from a PDN-equipped GDS (VDD/VSS now real top-level pins)
- **PR #85**: fix(verification): recognize VDD/VSS power ports in gate-level netlist
- **Issue #81** (closed): Add filler-cell (and tapcell/PDN) insertion to close nwell.space.1/nwell.width.1 DRC violations for real
- **PR #84**: feat(flow): add tapcell/PDN/filler-cell insertion to close nwell DRC violations
- **Issue #79** (closed): Close the newly-surfaced nwell.space.1/nwell.width.1 DRC violations on layout/modexp.gds
- **PR #82**: docs(signoff): classify the 234 nwell DRC violations surfaced by issue #78

### 2026-09-10

- **Issue #78** (closed): Bump the klayout-tools pin past klayout-tools#1069 and re-run Leg 2 (SDF delay-annotated gate-level sim) — the upstream fix for #55's FAIL has been merged since 2026-08-17
- **PR #80**: Bump klt pin past klayout-tools#1069, re-run Leg 2 gate-level SDF sim

### 2026-08-27

- **PR #77**: ratification: install the two-key reviewer variant (EE key + market key)
- **Issue #76** (closed): Champion: Merge-Risk Hold Digest

### 2026-08-19

- **Issue #73** (closed): CI: 'multi-WIDTH cross-check (cocotb + Icarus)' job hangs indefinitely, no timeout-minutes set
- **PR #74**: ci: add timeout-minutes to multi-WIDTH cross-check job
- **Issue #71** (closed): Auditor guard-telemetry: worktree-write-confinement (base pattern) fires on multi-source cp reading from outside the worktree
- **PR #72**: fix(guard): join backslash-continued lines in qsplit() before segmentation (#71)
- **Issue #24** (closed): Dedup DUT-driver helpers between test_modexp.py and cross_check_tb.py

### 2026-08-18

- **Issue #37** (closed): Auditor guard-telemetry: worktree-write-confinement-unresolved-var recurs as a likely false positive
- **PR #41**: fix(guard): resolve double-quoted $VAR write targets in guard-destructive-generic.sh

### 2026-08-17

- **Issue #66** (closed): CI failing on main: drc-lvs evidence records pin a stale build_reference_netlist.py hash after PR #63 merged over PR #65
- **Issue #69** (closed): Build/runtime failure on main: evidence-record lint fails — stale build_reference_netlist.py provenance hash from PR #63/#65 merge race
- **PR #70**: fix(verification): mint twin drc-lvs records to repin stale build_reference_netlist.py hash

### 2026-08-16

- **Issue #68** (closed): Build failure on main: evidence-record provenance hash stale after PR #63 merge (npm run lint fails)
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
