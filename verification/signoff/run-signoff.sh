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
# release (see docs/environment.md -> "Pinned versions", the signoff-report
# row), newer than the PDK-heavy legs' pin: 0.7.0 on PyPI, whose grader binds
# T1 items 1/2/9/10 to artifact-anchored evidence (klayout-tools#2718).
# Locally the runner uses $KLT, else `klt` on PATH, and refuses any other
# version; CI installs `klayout-tools==0.7.0` directly.
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

# The signoff-report leg pins its OWN klt release (issue #165): 0.7.0, the
# first release whose grader can bind T1 items 1/2/9/10 to audited artifacts
# (klayout-tools#2718). The PDK-heavy legs' `.venv` klt is an older pin, so
# this script does NOT silently fall back to it: set KLT to a 0.7.0 `klt`
# (e.g. `uv venv /tmp/v && uv pip install --python /tmp/v/bin/python
# "klayout-tools==0.7.0"`, then `KLT=/tmp/v/bin/klt`), or have one on PATH.
SIGNOFF_KLT_VERSION="0.7.0"

if [[ -n "${KLT:-}" ]]; then
  :
else
  KLT="$(command -v klt)" || { echo "FATAL: no klt on PATH and KLT unset (need klayout-tools==${SIGNOFF_KLT_VERSION})" >&2; exit 1; }
fi
KLT_VERSION_LINE="$("$KLT" --version 2>/dev/null || echo 'version unknown')"
echo "klt: $KLT ($KLT_VERSION_LINE)" >&2
case "$KLT_VERSION_LINE" in
  "klt ${SIGNOFF_KLT_VERSION}"|"klt ${SIGNOFF_KLT_VERSION}+"*) ;;
  *)
    echo "FATAL: signoff leg is pinned to klayout-tools==${SIGNOFF_KLT_VERSION}; got '${KLT_VERSION_LINE}'." >&2
    echo "  Point KLT at a ${SIGNOFF_KLT_VERSION} install (see the comment above)." >&2
    exit 1
    ;;
esac

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
