# Work Log Archive — 2026-09

Sections moved byte-for-byte from [WORK_LOG.md](../WORK_LOG.md) by `loom-daemon work-docs archive`.

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

- **Issue #114** (closed): merge-pr.sh: champion:hold-state grep pipeline silently kills the script under pipefail when no hold marker exists
- **Issue #109** (closed): test-guard-loom-workspace.sh / test-methodology-inject.sh / test-guard-worktree-paths.sh / test-skill-router.sh: '.loom/ hook byte-identical to defaults/' check is now a tautological self-diff
- **Issue #107** (closed): chore: resync installed Loom surfaces silently reverts merged guard-hook fixes (#71/#72, #98, #100)
- **Issue #104** (closed): merge-pr.sh: _check_champion_hold_state_staleness() silently crashes the whole script under set -euo pipefail (no champion:hold-state comment = merge fails)
- **Issue #103** (closed): 5 vendored .loom/hooks/tests/*.sh files reference a defaults/hooks/ dir that doesn't exist in this (consumer) repo
- **Issue #102** (closed): guard-destructive-generic.sh: cp/mv continuation-line dest false-DENY when preceded by a leading mkdir/other-command line
- **Issue #101** (closed): guard-destructive-generic.sh: cp into "$tmp/" (mktemp -d) now ALLOWS, was denied -- confinement bypass regression from #98
- **Issue #99** (closed): guard-destructive-generic.sh: continuation-line cp/mv into in-worktree dest incorrectly DENIES (cross-platform, not macOS-specific)
- **Issue #95** (closed): guard-destructive-generic.sh: mkdir is never scanned for worktree-write-confinement (full confinement bypass)
- **Issue #93** (closed): Auditor guard-telemetry: worktree-write-confinement-unresolved-var denied a same-command-declared, relative-path $REC write
- **Issue #92** (closed): LVS report's counts.pins.matched (333) exceeds both sides' pin counts (70/68) — likely klt field mix-up
- **Issue #90** (closed): scripts/openroad-docker.sh re-implements PDK-root discovery instead of asking `klt pdk find`, and mounts the wrong root
- **PR #112**: fix(guard): restore #98/#100 guard-hook fixes, wire regression suites into CI
- **PR #111**: fix(hooks): gate defaults/-sync subtests on defaults/ existing
- **PR #110**: fix(scripts): merge-pr.sh champion:hold-state check no longer crashes with no hold markers
- **PR #108**: fix(hooks): resolve vendored hook tests against .loom/hooks, not defaults/hooks
- **PR #106**: fix(guard): restore qsplit() backslash-newline line-continuation join
- **PR #105**: fix: resolve PDK root via klt pdk find in openroad-docker.sh
- **PR #100**: fix(guard): recognize mkdir as a write idiom in worktree-write-confinement
- **PR #98**: fix(guard): resolve_var() now substitutes a mid-token embedded $VAR reference

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
