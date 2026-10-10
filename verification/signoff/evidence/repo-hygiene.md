# Repo-hygiene checklist (T1 item 10)

The audited artifact for T1 item 10. `klt signoff` binds the sibling
`item-10-repo-hygiene.json` attestation to the exact bytes of this file.
Audited on the commit that introduced this file.

- [x] `README.md`: states what the block is, its status ("early"), the
  target specification, how to reproduce it, the repo layout and the
  license.
- [x] Spec table: `spec/modexp.md` carries the parameter/target table
  (operation, `WIDTH`, correctness, cell count, clock, signoff, area) with
  decision records under `spec/decision-records/`.
- [x] License: `LICENSE` (Apache License 2.0).
- [x] CI: `.github/workflows/ci.yml` runs the evidence-record lint, the
  multi-`WIDTH` cross-check and the signoff-report `--check` on every pull
  request and push to `main`.
- [x] Pinned environment: `docs/environment.md`, kept in sync with
  `scripts/setup-env.sh` by `verification/check_pins.py`.

## Not asserted

This checklist says these files exist and cover the stated content. It does
not assert that the T1 items with their own evidence (3, 4, 5, 7, 11) are
met; the graded report is the verdict of record for those.
