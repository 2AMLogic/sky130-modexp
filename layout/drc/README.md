# layout/drc

`klt drc` run against the routed GDS (`layout/modexp.gds`, from #7). See
`docs/signoff-claim.md` for the overall DRC/LVS claim this substantiates and
the deck's documented coverage gaps.

## Contents

- `modexp-drc-report.json` — the full `klt drc --deck sky130 --format json`
  report, including the `coverage` block and `provenance` (deck
  `content_hash`, `klt`/`klayout` versions, input `content_hash`).

## Reproducing cold

```bash
./scripts/setup-env.sh && source .venv/bin/activate
klt drc layout/modexp.gds --deck sky130 --format json
```

Exit code `0` (`status: "clean"`), matching this report.

## Result summary (fresh as of issue #55, 2026-08-16)

- `status`: **`"clean"`**, `violation_count`: **0**.
- Deck `content_hash`: `sha256:2e78949d63f03012c505528158948a250e18c2c21c8710c85a23a8243649f4d0`.
- Input (`layout/modexp.gds`) `content_hash`: `sha256:229ed6a5f92938699acc969f757d84b9348731bacbe12a485473161e917c8d10`
  — **identical** to the input hash the prior (violating) run cited: this is
  the same, unmodified GDS. Nothing about the layout changed; the verdict
  changed because the check engine did.

## What changed since the prior (10-violation) run

Issue #8's original run against this same `layout/modexp.gds` reported
`status: "violations"`, 10 violations, all `diff.enclosing.licon.1` — every
one on a `sky130_fd_sc_hd__and3_1` instance, root-caused there to `klt drc`'s
`"enclosing"` check building its `Region` from raw, **unmerged** same-layer
shapes (`kdb.Region(cell.begin_shapes_rec(...))`, no `.merge()` call), so a
cell whose `diff` geometry happens to be drawn as two abutting (not one
merged) rectangles produced a false enclosure violation. That was filed as
[`2AMLogic/klayout-tools#995`](https://github.com/2AMLogic/klayout-tools/issues/995).

`klayout-tools#995` was closed upstream, fixed by
[`klayout-tools#998`](https://github.com/2AMLogic/klayout-tools/pull/998)
("fix(drc): merge checked regions before running check primitives", merged
2026-08-15T03:54:20Z) — exactly the missing `.merge()` call the root-cause
analysis above identified. Issue #55 bumped this repo's `klt` pin
(`docs/environment.md`) to a revision at/after that fix
(`a482d3934bd644b763cf925f6344ac05f54a1623`, re-verified a descendant of the
fix commit via `gh api .../compare/...` → `"status": "ahead"`) and re-ran
`klt drc` against the same, unchanged `layout/modexp.gds` — see "Result
summary" above. The fix eliminates the false positive at its source: the
10 previously-reported violations do not recur, and no new violations
appeared in their place.

## Deck coverage (unchanged)

`klt drc --deck sky130` still runs a curated starter subset of 17 rules, not
the full sky130 design rule manual — see `docs/signoff-claim.md`'s "Deck
coverage gaps" enumeration (six approximated rules, one untranscribed rule
`m2.6`, one deliberately non-source threshold `li1.enclosing.licon1.1`).
None of those gaps are implicated in this result: a `"clean"` verdict from
this deck means clean against the 17 rules it runs, not against the full
sky130 DRM.

## Evidence record

`verification/records/drc-lvs/records/20260816-174310-5e656e5.md` (append-only
convention, `verification/README.md`) — supersedes the prior
`20260815-013937-fa169a4` record for freshness (same layout, fixed tool).
