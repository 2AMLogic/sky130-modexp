#!/usr/bin/env bash
# Render this block's T1 tier-verdict report from the committed block
# manifest, via `klt signoff --manifest` (issue #130).
#
# Usage:
#   ./verification/signoff/run-signoff.sh           # regenerate tier-report.json
#   ./verification/signoff/run-signoff.sh --check   # regenerate to a temp file and
#                                                   # byte-compare against the committed
#                                                   # tier-report.json; exit 1 on drift
#
# `--check` is what CI runs (the `signoff` job in .github/workflows/ci.yml):
# if a cited evidence envelope changes -- e.g. a re-run DRC report whose new
# input content_hash no longer matches the manifest's pin -- the fresh report
# renders that item `stale_evidence`, differs from the committed report, and
# CI fails instead of letting the committed verdict rot.
#
# Toolchain: this is a tool-light, read-only report leg -- it re-runs no PDK
# job, it only reads committed JSON envelopes. It therefore pins its OWN klt
# revision (see docs/environment.md -> "Pinned versions", the signoff-report
# row), newer than the PDK-heavy legs' pin, because the report leg needs the
# digital-flow evidence kinds (`klt sta` / `klt functional-verification`
# recognition, item 11 in the tier doc) that the older pin predates. Locally
# the runner prefers `.venv/bin/klt` (what scripts/setup-env.sh provisions)
# and falls back to whatever `klt` is on PATH; CI installs the pinned
# revision directly.
#
# Exit codes: `klt signoff --manifest` exits 3 when the report rendered fine
# but at least one T1 item is unmet -- which is this block's honest current
# state and exactly what the committed report records -- so 0 and 3 are both
# "ran clean" here; only exit 1/2 (unreadable manifest, unparseable tier
# doc, usage error) fail this script.
#
# The report embeds its producing klt's build block (`build.git_commit`,
# `grading_ruleset_id`) and the tier doc's content hash, so the committed
# tier-report.json is reproducible byte-for-byte only on the pinned klt
# revision and committed doc -- bumping either pin requires regenerating the
# report with this script on the new pin (the `--check` CI leg enforces
# exactly that).
#
# Paths inside block-manifest.json are relative to the repository root, so
# this script always runs `klt signoff` from the root (never from this
# directory). `--tiers-doc` is likewise passed as a root-relative literal so
# the report's echoed `source_doc` field is checkout-independent and the
# `--check` byte comparison is stable across machines.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

MANIFEST="verification/signoff/block-manifest.json"
TIERS_DOC="verification/signoff/design-evidence-tiers.md"
REPORT="verification/signoff/tier-report.json"

if [[ -x ".venv/bin/klt" ]]; then
  KLT=".venv/bin/klt"
else
  KLT="$(command -v klt)" || { echo "FATAL: no klt on PATH and no .venv/bin/klt" >&2; exit 1; }
fi
echo "klt: $KLT ($("$KLT" --version 2>/dev/null || echo 'version unknown'))" >&2

run_report() { # $1 = output file
  set +e
  "$KLT" signoff --manifest "$MANIFEST" --tiers-doc "$TIERS_DOC" --format json > "$1"
  rc=$?
  set -e
  # 0 = every T1 item met; 3 = rendered fine but >=1 item unmet (the normal
  # state for a block still climbing the ladder). Anything else is a real
  # failure and must abort -- the report on disk is then an error envelope.
  if [[ "$rc" != 0 && "$rc" != 3 ]]; then
    echo "FATAL: klt signoff exited $rc (see its stderr above)" >&2
    exit "$rc"
  fi
}

summarize() { # $1 = report file
  python3 - "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(f"tier={d.get('tier')!r}  T1 items met: {d.get('t1_met_count')}/{d.get('t1_item_count')}")
for i in d.get("items", []):
    if i.get("tier") == "T1":
        print(f"  item {i['id']:>2}  {i['status']:<5}  {i.get('reason') or ''}")
PY
}

if [[ "${1:-}" == "--check" ]]; then
  TMP="$(mktemp)"
  trap 'rm -f "$TMP"' EXIT
  run_report "$TMP"
  if cmp -s "$TMP" "$REPORT"; then
    echo "OK: committed tier-report.json matches a fresh klt signoff run" >&2
    summarize "$TMP" >&2
  else
    echo "FAIL: committed tier-report.json does not match a fresh klt signoff run." >&2
    echo "  The manifest, a cited evidence envelope, or the tier doc changed without" >&2
    echo "  regenerating the report (or an evidence pin went stale). Re-run" >&2
    echo "  ./verification/signoff/run-signoff.sh and commit the refreshed report." >&2
    diff <(python3 -m json.tool "$REPORT") <(python3 -m json.tool "$TMP") >&2 || true
    exit 1
  fi
else
  run_report "$REPORT"
  echo "wrote $REPORT" >&2
  summarize "$REPORT"
fi
