# layout/drc

`klt drc` run against the routed GDS (`layout/modexp.gds`, from #7). See
`docs/signoff-claim.md` for the overall DRC/LVS claim this substantiates and
the deck's documented coverage gaps.

## Contents

- `modexp-drc-report.json` — the full `klt drc --deck sky130 --format json`
  report for the committed `layout/modexp.gds`, including the `coverage` block
  and `provenance` (deck `content_hash`, `klt`/`klayout` versions, input
  `content_hash`).

## Reproducing cold

```bash
./scripts/setup-env.sh && source .venv/bin/activate
klt drc layout/modexp.gds --deck sky130 --format json
```

Exit code `0` (`status: "clean"`), 0 violations.

## Current result (issue #232): CLEAN — 0 violations

Taken from `modexp-drc-report.json`:

- `status`: `"clean"`, `violation_count`: `0`.
- Input (`layout/modexp.gds`) `content_hash`:
  `sha256:cc970173409a1fcb28f6bc8c1c916f90d0f5fedf88fff3690cb91102f2734372`.
- Deck (`sky130`) `content_hash`:
  `sha256:776cd39e5f70e2c6c28de92e8351a2bf2c0ecb1f4e34e362310d156a63b6ffc1`.
- `klt` `0.7.1.dev1127+gd1dc0fc090d4`, klayout `0.30.12`.

## Deck coverage

The deck is a curated subset of the sky130 design rules, not the full design
rule manual. `klt deck info --format json` reports the installed build's own
current coverage; `docs/signoff-claim.md`'s "Deck coverage gaps" section lists
the documented gaps.

## Evidence record

The DRC run for this GDS is
`verification/records/drc-lvs/records/20261027-013910-98bf55d.md` (twins
`20261027-013920-98bf55d`, `20261027-013930-98bf55d`); its artifact report is
byte-identical to `modexp-drc-report.json`. The newest `drc-lvs` record is
`20261027-030000-1c651cc`, the LVS re-closure on the same GDS hash. Records are
append-only (`verification/README.md`); each names the one it supersedes.

## History

Earlier results (the 10-violation run of issue #8, the clean run of issue #55,
the 234 `nwell` violations of issue #79 and their closure in issue #81) are
preserved in `verification/records/drc-lvs/` (per-run reports and
`classification.json`), in `git log -- layout/drc/README.md`, and in the "DRC"
section of `docs/signoff-claim.md`.
