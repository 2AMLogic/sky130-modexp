#!/usr/bin/env bash
#
# flow/run-sta-corner-sweep.sh -- run a standalone multi-corner static timing
# analysis (`klt sta`) over the **one committed, already-routed**
# layout/modexp.def, at every corner in the ratified sky130_fd_sc_hd corner
# matrix (spec/decision-records/0001-..., Decision 4), and write the response
# out as a single `klt sta` JSON envelope.
#
# Why this exists alongside flow/run-corner-sweep.sh (issue #86):
# `flow/run-corner-sweep.sh` predates `klt sta` and works the only way the
# pinned-at-the-time `klt` allowed -- N independent full
# floorplan->place->cts->route builds, one per corner. That answers a
# different question from the one a T1 item-5 corner sweep asks: N builds
# produce N *different* placements and routings (global placement and
# detailed routing are seeded but not corner-invariant, and the
# timing-driven stages legitimately optimise against the corner's own
# liberty), so its table characterizes N designs rather than the one design
# this repo actually signs off. `klt sta` (klayout-tools#1099) closes that
# gap: it reads one fixed routed DEF and runs a fresh OpenSTA session per
# corner, never placing, routing, or running CTS. That is what makes this
# sweep evidence *about layout/modexp.def itself*.
#
# Both scripts are kept: run-corner-sweep.sh remains the record of how much
# of the slow-corner gap a mapping-only floorplan change closes (issue #56,
# a question that genuinely needs per-corner rebuilds); this script is the
# corner characterization of the committed layout.
#
# ONE ENVELOPE, NOT EIGHTEEN (issue #132). This script used to shell out to
# `klt sta` once per corner with the scalar `pdk.corner` and staple the
# eighteen responses into a hand-rolled JSON array. That array is not a
# `klt sta` envelope, so `klt signoff --manifest` could not read it as T1
# item 5 evidence (verification/signoff/README.md records exactly that gap).
# `request.pdk.corners` (a list, klayout-tools#1871) characterizes the same
# loaded geometry at N corners inside one request/response round trip, and
# the response IS a signoff-readable envelope with a `corners[]` array --
# so the committed request `flow/sta-modexp.json` now carries the corner
# list and this script is a thin wrapper around a single invocation.
#
# Usage:
#   ./flow/run-sta-corner-sweep.sh                # all 18 ratified corners
#   ./flow/run-sta-corner-sweep.sh -o out.json    # write elsewhere
#
# Requires: an `openroad` binary on $PATH (docs/environment.md's "OpenROAD"
# section -- scripts/openroad-docker.sh is the pinned route) and a resolvable
# sky130A PDK (PDK_ROOT / $PDK, per docs/environment.md). Needs **no**
# synthesis netlist and no place-and-route run: the routed DEF is committed.
#
# Writes flow/sta-corner-sweep-results.json (gitignored; the evidence record
# under verification/records/sta-corner-sweep/artifacts/ freezes a copy, and
# verification/signoff/block-manifest.json cites that frozen copy for T1
# item 5).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLOW_DIR="${REPO_ROOT}/flow"
REQUEST="${FLOW_DIR}/sta-modexp.json"
ROUTED_DEF="${REPO_ROOT}/layout/modexp.def"
OUT="${FLOW_DIR}/sta-corner-sweep-results.json"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--output) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "FATAL: unknown argument '$1' (see --help)" >&2; exit 2 ;;
  esac
done

if [ ! -f "${ROUTED_DEF}" ]; then
  echo "FATAL: ${ROUTED_DEF} not found." >&2
  exit 1
fi
if [ ! -f "${REQUEST}" ]; then
  echo "FATAL: ${REQUEST} not found." >&2
  exit 1
fi

if [ -x "${REPO_ROOT}/.venv/bin/klt" ]; then
  KLT="${REPO_ROOT}/.venv/bin/klt"
else
  KLT="$(command -v klt)" || { echo "FATAL: no klt on PATH and no .venv/bin/klt" >&2; exit 1; }
fi

echo "klt:  ${KLT}" >&2
echo "def:  ${ROUTED_DEF}" >&2
echo "req:  ${REQUEST}" >&2

PDK="${PDK:-sky130A}" "${KLT}" sta "${REQUEST}" --format json > "${OUT}"

python3 - "${OUT}" <<'PYEOF'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    response = json.load(handle)

corners = response.get("corners") or []
print(f"status={response.get('status')}  corners={len(corners)}")
closed = 0
for entry in corners:
    setup = entry.get("worst_slack_ns")
    hold = entry.get("worst_hold_slack_ns")
    ok = (
        entry.get("timing_status") == "constrained"
        and setup is not None
        and setup >= 0
        and hold is not None
        and hold >= 0
    )
    closed += ok
    print(
        f"  {entry.get('corner', '?'):<24} "
        f"setup={setup!s:>10}  hold={hold!s:>9}  "
        f"fmax={entry.get('fmax_mhz')!s:>9}  "
        f"{entry.get('timing_status')}  {'PASS' if ok else 'FAIL'}"
    )
print(f"closed at {closed}/{len(corners)} corners")
PYEOF

echo "wrote ${OUT}" >&2
