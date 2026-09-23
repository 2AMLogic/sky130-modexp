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
  on the signoff-leg klt pin. Regenerate with `./run-signoff.sh`.
- `run-signoff.sh` — the runner (and the `--check` gate CI runs). Prefers
  `.venv/bin/klt`, falls back to `PATH`.

## Current verdict (2026-09-23, this manifest)

**1 of 11 T1 items met; `tier: null`.** This is the honest graded state —
an all-`unmet` manifest would have been a correct result too (issue #130);
nothing here inflates a row to green.

| Item | Status | Why |
|---|---|---|
| 3 DRC clean | **met** | `layout/drc/modexp-drc-report.json`: `status: clean`, 0 violations, input pinned by `content_hash` (freshness verified by the grader). Coverage disclosure below. |
| 4 LVS clean | unmet (`check_failed`) | `layout/lvs/modexp_lvs_report.json`: `status: mismatch` (17 mismatches, all physical-only/fixup cells). Tracked by #131. The envelope carries no `provenance.input` hash (klt 0.4.0 era), so no freshness pin is possible on this citation — see "Citation policy" below. |
| 7 Post-layout verification | unmet (`not_post_layout`) | The cited gate-level `klt functional-verification` run (record `20260911-071039-ce2b24c`) passed, but with `environment.sdf: null` — a zero-delay run, not the SDF-annotated post-layout regression item 7 requires. Tracked by #133. |
| 5 Corner verification | unmet (`no_evidence`) | A corner sweep exists (`verification/records/sta-corner-sweep/`, 18 corners, 100 MHz closes at 10/18 — binding corner `ss_n40C_1v28` at 22.80 MHz, tracked by #132), but it is committed as one aggregated results file, not a standalone `klt sta` envelope the grader can read; no citation is made rather than a misleading one. #132's envelope becomes the citation when it lands. |
| 11 Power delivery (structural) | unmet (`no_evidence`) | No `klt erc` supply spec or report exists in this repo. Tracked by #129. |
| 1, 2, 9, 10 | unmet (`no_evidence`) | Deliberately uncited — see "Citation policy". |
| 6 Monte Carlo | unmet (`no_evidence`) | This block's ratified spec has **no statistical spec row** (functional correctness, Fmax, timing closure — none statistical), stated here explicitly per the tier doc rather than left implicit; there is no Monte-Carlo claim to evidence. |
| 8 Characterization | unmet (`no_evidence`) | No aggregated characterization artifact (Fmax/area/power across corners) exists yet. |

## Citation policy (what is cited, and why the rest is deliberately not)

`klt signoff` grades items 1, 2, 9 and 10 on *"some passing envelope was
cited"*, not on topical relevance — the tool cannot check that a cited
artifact is about the claim. Citing them honestly is this repo's
responsibility (the grader's own docs say the same), so this manifest cites
**only** items whose cited envelope actually backs the claim, and leaves
items with no machine-checkable evidence visibly `unmet`/`no_evidence`:

- **Item 1 / 2** (design sources, layout): the real artifacts exist
  (`rtl/modexp.v`, the synthesized netlist, `layout/modexp.gds` + `modexp.def`
  from the committed P&R flow), but no recognized `klt` envelope testifies
  to them (`klt synthesize`/`klt place-and-route` responses are not
  signoff-recognized envelope kinds), and borrowing a passing DRC report to
  green these rows would be exactly the dishonest citation the issue
  forbids.
- **Item 9** (testbenches shipped): the cocotb suites are committed and CI
  runs them, but again no envelope-shaped check exists for "a third party
  can cold-start this testbench" — uncited.
- **Item 10** (repo hygiene): README/LICENSE/CI all exist; uncited for the
  same reason.

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
`functional-verification` envelope (the zero-delay caveat above is this
item's honest disclosure instead).

## Running it

```bash
./verification/signoff/run-signoff.sh          # regenerate tier-report.json
./verification/signoff/run-signoff.sh --check  # what CI runs
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
