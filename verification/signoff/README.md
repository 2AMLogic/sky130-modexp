# Signoff manifest — this block's graded T1 state

This directory holds **the machine-readable verdict of record for this
block's gap to T1** (issue #130): a `klt signoff --manifest` block manifest,
the pinned tier checklist it grades against, and the committed tier-verdict
report it renders. The fleet roll-up (2AMLogic/2am#956) consumes the
manifest's `block` field to identify this repo's row.

It replaces the hand-maintained T1 checkbox list that used to live in issue
#12 — a hand-read checklist cannot survive the checklist itself changing
(the T1 list grew an eleventh item on 2026-09-17, klayout-tools#2025, which
invalidated every prior hand-read fleet-wide at a stroke). **The graded
report here is the verdict of record**; issue #12 points at it rather than
duplicating it.

## Contents

- `block-manifest.json` — the block manifest `klt signoff --manifest`
  reads: `block: sky130-modexp`, `kind: digital` (this is a digital
  RTL→GDS block — RTL, synthesis, P&R; no schematic capture, no analog
  partition), and the per-item evidence citations (below).
- `design-evidence-tiers.md` — the pinned copy of
  `2AMLogic/klayout-tools`'s `docs/design-evidence-tiers.md` the report
  grades against, byte-identical to upstream revision
  [`0882541638acaec9ceb43c4df77b47d5a1a179db`](https://github.com/2AMLogic/klayout-tools/commit/0882541638acaec9ceb43c4df77b47d5a1a179db)
  (2026-09-22, the last commit to touch that doc at pin time; sha256
  `63eeec72e3d849761cf32dcf091af5728b069b1515e32bb3138e9454303671e5`).
  Pinned — rather than resolved from the installed `klt` — because the
  tier list moves upstream (item 11 again) and a pinned copy makes each
  checklist revision a reviewable change in this repo, on the same pin
  discipline as the PDK and toolchain pins in `docs/environment.md`.
  **Bumping it**: copy the new upstream revision over this file, re-run
  `./run-signoff.sh`, and commit the refreshed report together with the
  doc; the CI `--check` leg fails until the report is regenerated.
- `tier-report.json` — the committed output of `klt signoff --manifest
  block-manifest.json --tiers-doc design-evidence-tiers.md --format json`
  on the signoff-leg klt pin (`klayout-tools==0.7.0`). Regenerate with
  `KLT=<path to a 0.7.0 klt> ./run-signoff.sh`.
- `evidence/` — the artifact-anchored `generic` envelopes for items 1, 2, 9,
  10 and the audit records they are bound to.
- `run-signoff.sh` — the runner (and the `--check` gate CI runs). Uses `$KLT`,
  else `klt` on `PATH`, and refuses any version other than 0.7.0 (the
  PDK-heavy legs' `.venv` klt is an older pin).

## Current verdict (2026-10-08, this manifest)

**6 of 11 T1 items met; `tier: null`** (was 2 of 11 before issue #165). This is the honest graded state —
an all-`unmet` manifest would have been a correct result too (issue #130);
nothing here inflates a row to green.

| Item | Status | Why |
|---|---|---|
| 3 DRC clean | **met** | `layout/drc/modexp-drc-report.json`: `status: clean`, 0 violations, input pinned by `content_hash` (freshness verified by the grader). Coverage disclosure below. |
| 4 LVS clean | unmet (`check_failed`) | `layout/lvs/modexp_lvs_report.json`: `status: mismatch` (12 errors, all P&R cell insertions and resizes the pre-CTS reference cannot model; `power_connectivity: match`). Tracked by #131. The envelope carries no `provenance.input` hash, so no freshness pin is possible on this citation — see "Citation policy" below. |
| 7 Post-layout verification | **met** | The cited gate-level `klt functional-verification` run (record `20260923-054800-e26f603`) passes **with** `environment.sdf.annotated: true` — the SDF-annotated post-layout regression item 7 requires (issue #138). Its own disclosure rides with it: the annotation is `partial`, because Icarus implements SDF `IOPATH`/`INTERCONNECT` but not `TIMINGCHECK`, so all 129 `TIMINGCHECK` sections are dropped and `$setup`/`$hold` run against the cell library's placeholder limits. **This is net-delay back-annotation, not timing-check verification** — the setup/hold question is item 5's, and item 5 is `unmet` below. |
| 5 Corner verification | unmet (`check_failed`) | **Now cited, and failing on its own evidence rather than on an absence of it** (issue #132): `verification/records/sta-corner-sweep/artifacts/20260923-093000-28a7c96/sta-corner-sweep-results.json`, one `klt sta` envelope covering all 18 ratified corners of the committed layout, pinned by the analysed DEF's `content_hash`. The grader's rule is that every reported corner must be `timing_status: "constrained"` with non-negative setup **and** hold slack; **100 MHz closes at 10 of 18** — binding corner `ss_n40C_1v28` at **22.80 MHz**, setup WNS −33.867 ns. Hold is clean at all 18. This is a disclosed, bounded FAIL carried against an unamended ratified Clock row, ratified as `spec/decision-records/0004-…`; it is deliberately **not** closed by lowering the target, and the decision record prices the measured route to 18/18. **Update (issue #141):** that route was run through committed `klt` requests and reaches **17 of 18** (`ss_n40C_1v28` at −0.574 ns / 94.57 MHz), not eighteen — `spec/decision-records/0005-…` and record `20260924-134500-1a8313b`. This row's cited evidence and verdict are unchanged: no layout, RTL or flow request moved. |
| 11 Power delivery (structural) | unmet (`check_failed`) | Cited as the compound entry the grader defines: `layout/erc/modexp-erc-supply-report.json` (issue #129's supply-island read — `erc_finding_count: 0`, `VPWR`/`VGND` one island each, input pinned to the current GDS) + the item-4 LVS report + the P&R envelope (`power.pdn: true`, `tapcell_master: sky130_fd_sc_hd__tapvpwrvgnd_1`, straps met1/met4/met5 all inside the spec's stackup). The rendered reason is the LVS half: that report still mismatches (tracked by #131) and carries no `power_connectivity` verdict at all — and past it sit the spec's deliberately-undeclared `ties[]` (klayout-tools#2169, `erc.missing_tie` not computed) — so the item stays honestly unmet on the grader's own terms; the supply-island half is met and documented in `layout/erc/README.md`. |
| 1 Design sources | **met** | Artifact-anchored `generic` envelope `evidence/item-1-design-sources.json`, bound to the committed inventory `evidence/design-sources.md` (RTL + the synthesized netlist derived from it + regeneration steps). Added by issue #165 on klt 0.7.0. |
| 2 Layout | **met** | `evidence/item-2-layout.json`, bound to `layout/modexp.gds` (same hash the DRC citation pins). **Disclosure:** the committed P&R flow exists, but the exact run behind this GDS is not bit-reproducible (`layout/README.md`, issue #55) and no as-built netlist was captured (decision record 0006); the envelope's `summary` says so. The item text asks for "reproducibly generated"; the grader reads the attestation, not that clause. |
| 9 Testbenches shipped | **met** | `evidence/item-9-testbenches.json`, bound to `evidence/testbenches.md` (each claimed functional measurement, its testbench, its cold-start invocation, and the PDK pin). Tool-run checks (DRC/LVS/STA) are stated to be outside the claim. |
| 10 Repo hygiene | **met** | `evidence/item-10-repo-hygiene.json`, bound to `evidence/repo-hygiene.md` (README, spec table, LICENSE, CI, pins). |
| 6 Monte Carlo | unmet (`no_evidence`) — unchanged by 0.7.0 | This block's ratified spec has **no statistical spec row** (functional correctness, Fmax, timing closure — none statistical), stated here explicitly per the tier doc rather than left implicit; there is no Monte-Carlo claim to evidence. |
| 8 Characterization | unmet (`no_evidence`) — unchanged by 0.7.0 | No aggregated characterization artifact (Fmax/area/power across corners) exists yet. |

## Citation policy (what is cited, and why the rest is deliberately not)

Before klt 0.7.0, `klt signoff` graded items 1, 2, 9 and 10 on *"some passing
envelope was cited"*, not on topical relevance, and rejected `generic`
evidence for them; the only way to turn them green was to borrow an unrelated
passing envelope, which this manifest refused to do (issue #165's first
attempt, PR #166, concluded "no honest citations" on that basis).
klayout-tools 0.7.0 (klayout-tools#2718) accepts an **artifact-anchored
`generic` envelope** for these four: it declares `t1_item`, names the audited
artifact in `provenance.input.path` with its `content_hash`, and the manifest
pins the same hash; the grader re-hashes the artifact (`input_verified`), so
editing the audited bytes turns the row `stale_evidence` and the CI `--check`
fails.

- **Item 1 / 9 / 10** are bound to committed, human-readable audit records
  under `evidence/` (`design-sources.md`, `testbenches.md`,
  `repo-hygiene.md`). The envelope's `status: pass` is this repo's own
  assertion — the grader does not re-audit the inventory — so each record
  states what it does and does not cover. Editing a record means re-reading it
  against the repo and re-hashing (envelope + manifest pin) in the same change.
- **Item 2** is bound to the committed routed GDS itself; see the
  reproducibility disclosure in the table above.
- `status: pass` on these is the attestation of the audit, not a tool
  measurement. A borrowed native envelope is never used for them.
- **Items 6 and 8** are unaffected by 0.7.0 and stay `unmet`/`no_evidence`
  (reasons in the table). **Items 4, 5, 11** are as before.

Freshness pins (`content_hash`) are set on every citation whose envelope
carries a checkable input hash. Item 3 pins the DRC report's input layout
hash (`sha256:9fa0dbe1…`, the current `layout/modexp.gds` as DRC'd by the
issue #81 record). Item 4's LVS envelope predates klt's provenance
population for that verb (`provenance.input: null`), so it is cited
unpinned — a pin there could never match and would render a misleading
`stale_evidence`; the freshness of that citation is instead carried by the
DRC twin's hash (both were minted from the same GDS in the issue #81
record) and by the record's own provenance block. Item 7's
`functional-verification` envelope has no provenance block by design (that
verb's verdict depends on no PDK and no deck), so no pin is possible there
either — pinning it is documented upstream to always render
`stale_evidence`.

**Manifest key gotcha:** for a non-`mixed-signal` manifest, per-kind item
keys must be the **bare** item id (`"7"`), not the partition-qualified
`"7.digital"` the upstream manifest docs describe — a partition-qualified
key on a pure-`digital` manifest is silently ignored by the grader
(renders `no_evidence` instead of grading the cited evidence). Filed
upstream as klayout-tools#2362.

## Item 3's DRC coverage disclosure (reported, not graded — read it here)

The grader renders item 3 `met` on `status: clean` alone; the deck-coverage
caveats travel with the claim, not the verdict. Quoted from the cited
envelope's own `coverage` block:

- `deck_scope`: `cap2m, capm, ct, difftap, li, licon, m1, m2, m3, m4, m5,
  nwell, poly, via, via2, via3, via4` — the deck is a **curated starter
  subset** of the sky130 DRM (17 chapters), not the full design rule
  manual; "clean" is measured inside that scope (`layout/drc/README.md`).
- `layers_in_stream_without_rules` (23): `64/5, 64/16, 64/59, 65/44,
  66/15, 67/5, 67/16, 68/5, 68/16, 69/5, 69/16, 72/5, 72/16, 78/44, 81/4,
  81/23, 83/44, 93/44, 94/20, 95/20, 122/16, 235/4, 236/0`.
- `rules_skipped` (10): `capm.enclosing.via3.1, capm.separation.via3.1,
  capm.space.1, capm.width.1, capm2.enclosing.via4.1,
  capm2.separation.via4.1, capm2.space.1, capm2.width.1,
  met3.enclosing.capm.1, met4.enclosing.capm2.1`.

Item 7's `body_bias` disclosure does not apply to the current citation:
that field rides a `klt pex` report, and item 7's citation here is a
`functional-verification` envelope (the dropped-`TIMINGCHECK` caveat in the
table above is this item's honest disclosure instead).

## Item 5's timing disclosure (reported, not graded — read it here)

The grader renders item 5 `unmet`/`check_failed` on the cited sweep's own
per-corner verdicts. What the verdict does **not** carry, and what anything
citing this row must:

- The sweep is `klt sta` with `spef` **omitted**, so it times against
  LEF/DEF-derived parasitics rather than an extracted or routing-estimated
  basis. That makes the table **optimistic**: the same DEF reads
  +4.367 ns / 177.53 MHz at `tt_025C_1v80` here against the
  +3.736 ns / 159.63 MHz the P&R record reports for it. The gap at the
  binding corner is understated, not overstated.
- Ideal (not propagated) clock, and an extrapolated rather than bisected
  `fmax_mhz` — documented limits of `klt sta` itself.
- The failure is **purely setup**; hold is clean at all eighteen corners
  (worst +0.21354 ns).

Full record: `verification/records/sta-corner-sweep/records/20260923-093000-28a7c96.md`.

## Running it

```bash
# needs klayout-tools==0.7.0, e.g. a throwaway venv:
#   uv venv /tmp/v && uv pip install --python /tmp/v/bin/python "klayout-tools==0.7.0"
KLT=/tmp/v/bin/klt ./verification/signoff/run-signoff.sh          # regenerate tier-report.json
KLT=/tmp/v/bin/klt ./verification/signoff/run-signoff.sh --check  # what CI runs
```

CI (`.github/workflows/ci.yml`, `signoff` job) installs the signoff-leg
klt pin and runs `--check`: a manifest citing an artifact that has since
changed (hash pin no longer matches) or any un-regenerated report drift
fails the build rather than rotting. The report leg's klt pin is tracked
in `docs/environment.md` alongside (and separately from) the PDK-heavy
legs' older pin — see there for the rationale.

Paths inside `block-manifest.json` are relative to the repository root;
the runner always executes `klt signoff` from the root. `source_doc` in
the committed report is the root-relative literal for the same reason.
