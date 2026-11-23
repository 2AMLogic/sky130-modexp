# Work Log

Chronological record of merged PRs and closed issues, maintained automatically
by the Guide triage agent. Entries are grouped by date (UTC), newest first.

## Archives

- [2026-09](work_log/WORK_LOG_2026-09.md)
- [2026-08](work_log/WORK_LOG_2026-08.md)

### 2026-11-23

- **PR #408**: docs: drop stale Leg 2 block from run-gate-level-sim.sh, slice --help by sentinel
- **PR #402**: docs: ratify DR-0017 via the two-key step (status-only flip)
- **Issue #407** (closed): Remove the stale Leg 2 FAIL block from run-gate-level-sim.sh: 4 supersessions old and truncated by --help
- **Issue #400** (closed): T1 item 5: open the ratification PR for DR-0017 (status flip only) so the EE key, market key and operator have a PR to act on

### 2026-11-20

- **PR #404**: docs: price Montgomery entry setup with split doubling and kernel reuse
- **Issue #401** (closed): T1 item 5: price the source of R^2 mod m for the Montgomery entry conversions (DR-0017's unpriced input) as a proposed decision record
- **PR #324**: ci: drop retired consumer carve-outs for two daemon-backed merge-pr suites
- **Issue #321** (closed): Remove two retired entries from .github/ci-suites-consumer-skips.txt: upstream ci-excluded.txt now lists both suites

### 2026-11-19

- **PR #397**: Grade T1 signoff against the wheel-bundled tier checklist
- **Issue #395** (closed): Use the pinned klayout-tools checklist for T1 signoff
- **Issue #335** (closed): Decide whether test_repo_utils.py belongs in T1 item 9's attestation inventory

### 2026-11-18

- **PR #391**: ci: report on merge_group events with an explicit queue base
- **Issue #390** (closed): Merge queue: add the merge_group trigger to the required-check workflow(s)
- **PR #388**: docs: mark run-corner-sweep.sh archived/frozen in flow README
- **Issue #369** (closed): Remove flow/run-corner-sweep.sh: superseded by klt sta sweep, frozen copy already in evidence

### 2026-11-17

- **PR #384**: refactor(verification): consolidate duplicated klt resolution + error unwrap into _repo_utils
- **Issue #382** (closed): Consolidate duplicated _resolve_klt() (and its twin self-tests) into _repo_utils
- **PR #353**: fix(verification): honour $KLT in gate-level cross-check klt resolution
- **Issue #350** (closed): gate_level_cross_check.py ignores $KLT when resolving the klt binary, so the documented pin-check recipe does not reach that leg
- **PR #380**: docs(environment): extend depth-reuse section to the Python entry points
- **PR #333**: refactor(verification): resolve the repo root and content hashes through _repo_utils
- **Issue #349** (closed): _repo_utils.py's new coverage sentence overstates completeness: two find_repo_root() copies remain unnamed in its exception list
- **Issue #334** (closed): docs(environment): extend the depth-reuse section to the verification Python entry points
- **Issue #329** (closed): Consolidate the last path-depth repo roots and duplicate sha256 helpers onto verification/_repo_utils.py
- **PR #377**: fix: honour $KLT ahead of the venv/$PATH probe in cross_check.py klt resolution
- **PR #375**: docs: correct klayout-tools#996 pin status in flow/README gate-level gaps
- **PR #373**: fix: surface and keep failing-run evidence when the cross-check gate goes red
- **PR #372**: gate-level: drive the 500-case deep run through klt functional-verification
- **PR #371**: docs(spec): add withdrawn-claim forward pointer from 0004 to 0005 Decision 1
- **PR #345**: refactor(shell): give $DESIGN and $KLT one implementation in scripts/design-env.sh
- **Issue #378** (closed): gate_level_cross_check.py's $KLT leg silently falls back on a nonexistent pin; cross_check.py and design-env.sh do not
- **Issue #376** (closed): verification/cross_check.py ignores $KLT when resolving the klt binary, so the documented pin-check recipe does not reach the correctness gate
- **Issue #361** (closed): A failing WIDTH in the cross-check gate reports counts only: klt's own output and the run dir are discarded
- **Issue #359** (closed): flow/README.md and verification/README.md still say klayout-tools#996 was fixed 'later than this repo's pin', contradicting the gate-level gap table
- **Issue #354** (closed): Record 0004 carries no forward pointer to 0005's withdrawal of its 18/18 claim
- **Issue #337** (closed): Consolidate the duplicated DESIGN/REPO_ROOT preamble in the three shell runners, and reconcile their three different klt resolutions
- **Issue #316** (closed): Two drivers still bypass klt via cocotb's Runner API: re-check whether their stated reasons are stale
- **PR #368**: fix: align mint-test fixture with run_width's klt_pass/klt_status keys
- **PR #366**: feat(verification): enforce COCOTB_VERSION pin in ci.yml and doc table
- **PR #332**: docs(signoff): item 8 report states the DR-0012 LVS match, warnings and engine caveats
- **PR #317**: refactor(verification): drive each cross-check WIDTH through klt functional-verification
- **Issue #365** (closed): check_pins.py does not cross-check ci.yml's cocotb installs against COCOTB_VERSION
- **Issue #360** (closed): cross_check mint test fixture still carries the removed cocotb_pass key
- **Issue #327** (closed): Item 8 characterization report still says LVS `mismatch`: update the Signoff row to the DR-0012 verdict and regenerate the envelope
- **Issue #314** (closed): Route verification/cross_check.py's per-WIDTH runs through klt functional-verification: the parameter-override gap is closed at the pinned klt
- **PR #364**: gate-level: supply cell-model defines via options.defines, drop the sim-defines side file
- **PR #363**: docs: drop hard-coded instance/cell-type counts the docstring claims it never hard-codes
- **PR #358**: docs: mark klayout-tools#1002 (SDF) fixed in flow and verification gap lists
- **PR #356**: docs(flow): record the per-corner-rebuild half of the multi-corner gap as closed at pin 0.8.0
- **PR #342**: refactor: extract the duplicated Loom suite runner from ci.yml to a tested script
- **PR #323**: docs: align gate-level netlist figures with the committed artifacts
- **PR #348**: chore(loom): resync installed Loom to v0.19.1306
- **PR #344**: docs: replace run-signoff.sh's stale git-SHA toolchain header with the shared PyPI pin
- **PR #343**: docs: state current item 4/5/6/8/11 grading in signoff citation policy
- **PR #339**: docs: correct README status to the graded DRC/LVS verdict and 10-of-18 corners
- **PR #331**: docs(spec): replace per-record prose index with a complete one-line record list
- **PR #325**: refactor(verification): reach the gate-level testbench via testbench.search_path
- **PR #318**: fix(verification): scope the committed-blob check to the merge-base diff
- **PR #313**: fix: route six Loom hook entries in settings.json through hook-wiring.sh
- **PR #309**: docs(flow): record klayout-tools#854 closed at the current klt pin
- **Issue #362** (closed): spice_to_verilog.py docstring claims counts are "never hard-coded here" while hard-coding two
- **Issue #355** (closed): flow/README.md and verification/README.md still call klayout-tools#1002 (SDF) open, and say it blocks delay-annotated gate-level sim
- **Issue #352** (closed): flow/README.md: the multi-corner gap bullet never records that the per-corner physical rebuild is closed too (only the STA half is)
- **Issue #338** (closed): Deduplicate the two identical Loom suite-runners in ci.yml: 43 of ~50 code lines are byte-identical across guard-hooks and merge-pr-suites
- **Issue #322** (closed): Replace the gate-level sim-defines file with options.defines (supersedes a signoff-cited gate-level-sim record)
- **Issue #319** (closed): Correct verification/gate-level/README.md: stale 718-instance / 'no PDN' / 'no netlist export' claims contradict the committed netlist
- **Issue #341** (closed): Remove the stale klt-0.7.0 citation-policy bullet in verification/signoff/README.md: it reports items 6/8 as unmet/no_evidence against its own graded table
- **Issue #340** (closed): Remove the stale git-SHA toolchain paragraph from run-signoff.sh: it contradicts the live PyPI pin 29 lines below it
- **Issue #330** (closed): Remove spec/README.md's per-record prose index: 11 of 17 decision records unlisted, stale since 0007
- **Issue #328** (closed): README status paragraph is stale: it says a clean DRC/LVS verdict is still open and cites 17/18 corners for the shipped layout
- **Issue #320** (closed): Retire the gate-level testbench symlinks via testbench.search_path, and correct the stale klt gap lists
- **Issue #315** (closed): A new width-cross-check record cannot be minted: its transcripts collide with the legacy committed bytes
- **Issue #311** (closed): CI red on main since Loom resync 421e4b5: test-hook-wiring.sh fails 13 assertions
- **Issue #308** (closed): Retire flow/tie_constants.py: no-op at the pinned klt, and flow/README.md still says it is required

### 2026-11-12

- **PR #306**: Bump Repo Skills 0.25.10 -> 0.26.1

### 2026-11-07

- **PR #303**: chore(erc): regenerate supply report without per-gate antenna tables
- **Issue #301** (closed): Shrink committed ERC report: regenerate with --omit-antenna-tables (3.5 MB of ungraded antenna data)
- **PR #300**: Bump Repo Skills 0.25.1 -> 0.25.10

### 2026-11-06

- **PR #298**: ci: skip daemon-backed test-merge-pr-release-hold.sh in merge-pr job
- **Issue #297** (closed): CI red on main: test-merge-pr-release-hold.sh needs loom-daemon, not in ci-excluded.txt

### 2026-11-04

- **PR #293**: fix(ci): exclude daemon-backed merge-pr suites from toolchain-free job
- **Issue #177** (closed): Build/runtime failure on main: test-merge-pr-workflow-scope-preflight.sh needs loom-daemon but is not in ci-excluded.txt (CI red, 4th recurrence)

### 2026-11-02

- **PR #291**: chore(lvs): remove unused concat-expansion script and expanded netlist
- **Issue #225** (closed): Retire expand_concat_assigns.py LVS workaround: upstream fix is merged and in our klt pin
- **PR #289**: feat(signoff): grade T1 item 6 not_applicable via manifest citation
- **Issue #204** (closed): T1 item 6: record the bound not_applicable statement (no statistical spec row) so the grader stops reporting no_evidence

### 2026-11-01

- **PR #286**: Bump Repo Skills 0.24.7 -> 0.25.1

### 2026-10-30

- **Issue #271** (closed): T1 item 5: build out the carry-save Montgomery datapath (DR-0011's open lead) and measure ss_n40C_1v28 at 100 MHz

### 2026-10-29

- **PR #282**: docs: price pipelined column halves at 2 cycles per Montgomery iteration, propose contingent 0001 latency supersession (DR-0017)
- **Issue #280** (closed): T1 item 5: price pipelined column halves and propose supersession of 0001 Decision 3 (operator ruling branch c)
- **PR #281**: docs: record q-loop single-mux2 kernel probe P12 and DR-0016; probe (b) fails
- **PR #279**: docs: condense layout/README to current state and fix stale no-PDN citation
- **Issue #278** (closed): Condense layout/README.md: stale 'LVS mismatch / signoff not met' and superseded-layout history contradict the current verdict
- **Issue #135** (closed): README: embed the fleet burndown chart (one line)

### 2026-10-28

- **PR #277**: docs: record depth-lever kernel probes P10-P11c; quotient recurrence binds, no kernel closes
- **PR #275**: docs: remove stale LVS-mismatch and no-PDN claims from baseline
- **PR #274**: docs: record registered-quotient kernel probes and DR-0014 (no re-timing closes 100 MHz)
- **Issue #268** (closed): docs/baseline.md: stale 'LVS not clean' and 'no PDN' claims contradict the current verdict
- **PR #272**: docs: record P1 kernel re-measure (best 85.95 MHz, misses 100 MHz); gate complete build
- **PR #265**: docs: update signoff-claim Signoff-row and missing-stages sections to current verdict
- **Issue #263** (closed): docs: update remaining stale 'still not met' wording in signoff-claim.md
- **PR #269**: feat: attest T1 items 1, 9, 10 with klt signoff --attest and refresh tiers doc to v0.8.0
- **PR #264**: docs: condense stale signoff-claim sections to the current verdict
- **Issue #266** (closed): T1 grading: re-grade items 1, 9, 10 against the current tiers doc with klt signoff --attest envelopes
- **Issue #262** (closed): docs/signoff-claim.md: 'Reading the spec's Signoff row' and 'What this GDS has not been through' still say 'still not met'
- **PR #261**: docs: condense signoff-claim.md to the current DRC/LVS verdict
- **Issue #242** (closed): Condense docs/signoff-claim.md: superseded verdict and history sections still read 'not met'

### 2026-10-27

- **PR #259**: docs: update signoff-claim Leg 2 bullet to current PASS
- **Issue #258** (closed): docs: update stale Leg 2 FAIL text in docs/signoff-claim.md (follow-on from PR #257)
- **PR #257**: docs: replace stale Leg 2 FAIL status in baseline.md with current PASS pointer
- **PR #254**: docs: condense layout/lvs/README.md into a current-state page
- **Issue #253** (closed): Condense docs/baseline.md Leg 2 section: stale 'still FAIL' contradicts gate-level README
- **Issue #228** (closed): Condense layout/lvs/README.md: six stacked 'Update — read this first' sections
- **Issue #249** (closed): layout/README.md pin table cites removed KLT_REV constant
- **Issue #248** (closed): Condense verification/gate-level/README.md: superseded Leg 2 history sections
- **PR #252**: docs: mark layout README klt revision as historical KLT_REV pin
- **PR #251**: docs: condense superseded Leg 2 history in gate-level README
- **Issue #246** (closed): Bump klayout-tools pin 7755612adb51, d1dc0fc090d4 → 0.8.0
- **PR #247**: chore(env): pin klayout-tools==0.8.0 from PyPI for all legs
- **Issue #243** (closed): Condense layout/drc/README.md: superseded result sections and a stale evidence-record pointer
- **Issue #236** (closed): Re-run the SDF-annotated gate-level replay (T1 item 7) against the regenerated layout
- **Issue #235** (closed): T1 item 11 (power delivery): re-cite the power-delivery row once LVS power_connectivity reads match
- **Issue #234** (closed): T1 item 5 (corner verification): find a microarchitecture that closes ss_n40C_1v28 at the ratified 100 MHz without the bit-serial throughput loss
- **Issue #233** (closed): T1 item 4 (LVS clean): LVS match against the committed as-built netlist, and root-cause the VPB power_connectivity mismatch
- **Issue #232** (closed): T1 item 2 (layout): reproducible P&R re-run of layout/modexp.gds with its as-built netlist committed, so the item-2 envelope can pass
- **PR #244**: docs(drc): condense layout/drc README to current result and record pointer
- **PR #241**: evidence(gate-level): replay SDF on the committed layout and re-point T1 item 7
- **PR #240**: evidence(erc): declare a checked n-well tie and re-grade T1 item 11 as met
- **PR #239**: evidence(lvs): LVS match on the as-built netlist; VPB mismatch was an extraction artifact of the earlier klt build
- **PR #238**: evidence: candidate study finds no microarchitecture closing ss_n40C_1v28 at 100 MHz
- **PR #237**: feat(layout): regenerate routed layout with as-built netlist, show P&R reproducible

### 2026-10-24

- **Issue #227** (closed): CI red on main: test-merge-pr-feature-branch-close.sh needs a built loom-daemon (blocks docs PRs, e.g. #226)
- **PR #229**: ci: skip daemon-backed merge-pr feature-branch-close suite in consumer CI

### 2026-10-23

- **Issue #220** (closed): Remove docs/issue-54-decomposition.md: finished, unreferenced process note
- **Issue #218** (closed): Move the signoff-report klt pin off PyPI 0.7.0 to a git SHA with the item 6 not_applicable grader, unblocking #204
- **Issue #217** (closed): Bump the evidence-leg klt pin (KLT_REV) past klayout-tools PR #3605 so #201 can submit the 18-corner rebuild to the batch fleet
- **Issue #216** (closed): Adopt the common artifact store for sim evidence (manifests in git, bytes via klt artifact)
- **PR #223**: docs: remove finished issue-54 decomposition note
- **PR #222**: build: pin signoff-report klt to the SHA with the item 6 not_applicable grader
- **PR #221**: build: bump evidence-leg klt pin to klayout-tools#3605 merge commit
- **PR #219**: feat(verification): keep new run evidence bytes in the artifact store, commit manifests

### 2026-10-21

- **Issue #214** (closed): CI red on main: test-guard-installed-file-writes.sh classifies checkout as 'consumer' after v0.19.1201 resync
- **PR #215**: ci: skip layout-bound guard installed-file-writes suite in consumer CI
- **PR #213**: Bump Repo Skills 0.24.3 -> 0.24.7
- **PR #181**: fix(ci): repair Loom guard-hook regression suites (#180)

### 2026-10-20

- **Issue #193** (closed): setup-env.sh enables only sky130_fd_pr, so a fresh provision cannot run klt synthesize (no sky130_fd_sc_hd)
- **PR #197**: fix(setup-env): fetch sky130_fd_sc_hd and fail when it is missing

### 2026-10-17

- **Issue #206** (closed): Bump the evidence-leg klt pin (KLT_REV) past klayout-tools#3443 and #3550 to unblock #199 (T1 item 7) and #201
- **Issue #205** (closed): T1 item 8: aggregated characterization report (Fmax, area, power across corners) with a generated generic envelope
- **Issue #199** (closed): Gate-level SDF leg (T1 item 7) is blocked at open_pdks f6eeac7: klt rejects an interleaved SDF warning
- **PR #212**: feat(flow): resolve repo root via git and take design name from DESIGN for vendored reuse
- **PR #210**: feat(verification): record annotated SDF gate-level pass at open_pdks f6eeac7
- **PR #209**: feat(signoff): add hash-bound item 6 not_applicable statement and spec-drift guard
- **PR #208**: chore(env): bump evidence-leg KLT_REV to 36956c6
- **PR #207**: feat(signoff): add T1 item 8 characterization report with generated envelope

### 2026-10-16

- **Issue #194** (closed): Committed layout/lvs abstracted extraction is not reproducible with the pinned klt (power_connectivity match depends on it)
- **Issue #191** (closed): Re-qualify PDK-dependent evidence records under open_pdks f6eeac7 (split from #190)
- **PR #203**: Bump Repo Skills 0.24.1 -> 0.24.3
- **PR #202**: verification: regenerate layout/lvs with the pinned klt; power_connectivity recorded as measured mismatch

### 2026-10-15

- **Issue #195** (closed): docs/baseline.md and flow/README.md say synthesis reproduces 682 cells; pinned toolchain gives 717
- **Issue #190** (closed): Re-pin open_pdks to f6eeac7 (ciel) — fleet retires volare c6d73a3
- **Issue #180** (closed): CI red on main: Loom guard-hook regression suites fail (4 suites), blocking merges
- **Issue #165** (closed): T1 signoff manifest: wire evidence for items 1, 2, 6, 8, 9, 10 (currently graded no_evidence)
- **PR #200**: docs: attribute 682 to 717 synthesis delta to the klt-generated Yosys script
- **PR #198**: verification: re-qualify place-and-route and STA corner sweep under open_pdks f6eeac7
- **PR #196**: verification: re-qualify synthesis, DRC/LVS and gate-level sim records under open_pdks f6eeac7
- **PR #192**: build: re-pin sky130 PDK to open_pdks f6eeac7 via ciel and verify resolved revision
- **PR #189**: Bump Repo Skills 0.19.5 -> 0.24.1
- **PR #176**: feat(signoff): klayout-tools 0.7.0 pin + artifact-anchored evidence for T1 items 1, 2, 9, 10

### 2026-10-14

- **Issue #185** (closed): CI: carve out daemon-backed and consumer-layout-skewed Loom suites so the two regression jobs can go green (unblocks #182)
- **PR #188**: fix(loom): replace retired label names in the pinned curator.md copies (2am#4345)
- **PR #187**: ci: carve out test-guard-loom-workspace.sh (hook/suite skew) (#185)

### 2026-10-13

- **Issue #182** (closed): Guard-hook regression suites red on main: forge-egress, installed-file-writes, mcp-tools, hook-wiring
- **PR #186**: chore(loom): drop onIdle [auditor] — follow the fleet idle-role setting
- **PR #183**: fix(guard): port upstream forge-egress block into pinned guard-loom-workflow.sh (part of #182)

### 2026-10-08

- **Issue #172** (closed): Audit .loom/resync-ignore pins (12 files): drop what is upstream, upstream or keep the rest
- **PR #174**: chore: audit .loom/resync-ignore pins; retire resync-installed pins (#172)
- **Issue #170** (closed): Main CI red: test-merge-pr-help.sh and test-merge-pr-merge-method.sh need loom-daemon but are not in ci-excluded.txt
- **PR #171**: fix: exclude test-merge-pr-help/-merge-method from toolchain-free CI (#170)

### 2026-10-07

- **Issue #167** (closed): Build/runtime failure on main: 3 daemon-backed merge-pr suites missing from ci-excluded.txt (CI red since resync)
- **PR #168**: fix: exclude 3 daemon-backed merge-pr suites from CI job (#167)

### 2026-10-03

- **Issue #144** (closed): Decide whether to land the 17/18 bit-serial re-spin (DR-0005 Decision 1 left it unlanded)
- **PR #164**: docs(spec): record 0007 declining the 17/18 bit-serial re-spin (not planned)

### 2026-10-02

- **Issue #139** (closed): LVS item 4: the last 12 mismatches need an as-built post-route netlist, which this GDS does not have
- **PR #163**: LVS item 4 stays unmet (DR-0006); P&R runs commit as-built netlist

### 2026-10-01

- **Issue #162** (closed): PR #155 head SHA not updating on GitHub despite branch ref correctly moving (persistent forge-sync anomaly)

### 2026-09-30

- **Issue #158** (closed): Auditor guard-telemetry: loom:installed-file-write denies writes into a mktemp scratch dir's own .loom/ subtree
- **Issue #154** (closed): Curator's operator-premise idempotency check is spamming #12 with duplicate heartbeats (27/43 gaps <24h, min 23min)
- **PR #159**: fix(guard): honor same-command cd for installed-file-write target normalization
- **PR #155**: fix(curator): read the prior heartbeat marker completely, confirm under the claim (#154)
- **PR #88**: docs: point CLAUDE.md's review bar at klt wave's debugging guide

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

