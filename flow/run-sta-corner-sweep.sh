#!/usr/bin/env bash
#
# flow/run-sta-corner-sweep.sh -- run a standalone multi-corner static timing
# analysis (`klt sta`) over the **one committed, already-routed**
# layout/modexp.def, at every corner in the ratified sky130_fd_sc_hd corner
# matrix (spec/decision-records/0001-..., Decision 4), and collect each run's
# timing/power metrics into one JSON summary.
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
# this repo actually signs off. `klt sta` (klayout-tools#1099, available at
# this repo's pinned klt revision) closes that gap: it reads one fixed
# routed DEF and runs a fresh OpenSTA session per corner, never placing,
# routing, or running CTS. That is what makes this sweep evidence *about
# layout/modexp.def itself* -- including the post-#81 tapcell/PDN/filler-cell
# content that flow/run-corner-sweep.sh's own recipe does not carry.
#
# Both scripts are kept: run-corner-sweep.sh remains the record of how much
# of the slow-corner gap a mapping-only floorplan change closes (issue #56,
# a question that genuinely needs per-corner rebuilds); this script is the
# corner characterization of the committed layout.
#
# Usage:
#   ./flow/run-sta-corner-sweep.sh                    # all 18 ratified corners
#   ./flow/run-sta-corner-sweep.sh tt_025C_1v80        # a single named corner
#   ./flow/run-sta-corner-sweep.sh ss_100C_1v40 ff_100C_1v65
#
# Requires: an `openroad` binary on $PATH (docs/environment.md's "OpenROAD"
# section -- scripts/openroad-docker.sh is the pinned route) and a resolvable
# sky130A PDK (PDK_ROOT / $PDK, per docs/environment.md). Needs **no**
# synthesis netlist and no place-and-route run: the routed DEF is committed.
#
# Writes flow/sta-corner-sweep-results.json (gitignored; the evidence record
# under verification/records/place-and-route/artifacts/ freezes a copy).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLOW_DIR="${REPO_ROOT}/flow"
ROUTED_DEF="${REPO_ROOT}/layout/modexp.def"

ALL_CORNERS=(
  ff_100C_1v65 ff_100C_1v95 ff_n40C_1v56 ff_n40C_1v65 ff_n40C_1v76
  ff_n40C_1v95 ff_n40C_1v95_ccsnoise
  tt_025C_1v80 tt_100C_1v80
  ss_100C_1v40 ss_100C_1v60 ss_n40C_1v28 ss_n40C_1v35 ss_n40C_1v40
  ss_n40C_1v44 ss_n40C_1v60 ss_n40C_1v60_ccsnoise ss_n40C_1v76
)

CORNERS=("$@")
if [ "${#CORNERS[@]}" -eq 0 ]; then
  CORNERS=("${ALL_CORNERS[@]}")
fi

if [ ! -f "${ROUTED_DEF}" ]; then
  echo "FATAL: ${ROUTED_DEF} not found." >&2
  exit 1
fi

RESULTS_FILE="${FLOW_DIR}/sta-corner-sweep-results.json"
echo "[" > "${RESULTS_FILE}"
first=1

for corner in "${CORNERS[@]}"; do
  corner_dir="${FLOW_DIR}/sta-corners/${corner}"
  mkdir -p "${corner_dir}"
  request_path="${corner_dir}/sta-modexp.json"
  python3 - "${request_path}" "${corner}" "${ROUTED_DEF}" <<'PYEOF'
import json
import os
import sys

request_path, corner, def_abs = sys.argv[1], sys.argv[2], sys.argv[3]
request_dir = os.path.dirname(request_path)
def_rel = os.path.relpath(def_abs, request_dir)

request = {
    "schema": "klt.sta.request/1",
    "def": def_rel,
    "hdl_toplevel": "modexp",
    "pdk": {"cell_library": "sky130_fd_sc_hd", "corner": corner},
    "constraints": {"clock_port": "clk", "clock_period_ns": 10.0},
}
with open(request_path, "w", encoding="utf-8") as handle:
    json.dump(request, handle, indent=2)
    handle.write("\n")
PYEOF

  echo "== ${corner} ==" >&2
  start_ts=$(date +%s)
  if PDK="${PDK:-sky130A}" klt sta "${request_path}" --format json \
       > "${corner_dir}/sta-output.json" 2> "${corner_dir}/sta-output.log"; then
    status="ok"
  else
    status="failed"
  fi
  end_ts=$(date +%s)
  elapsed=$((end_ts - start_ts))
  echo "   status=${status} elapsed_s=${elapsed}" >&2

  if [ "${first}" -eq 0 ]; then
    echo "," >> "${RESULTS_FILE}"
  fi
  first=0
  python3 - "${corner}" "${corner_dir}/sta-output.json" "${status}" "${elapsed}" >> "${RESULTS_FILE}" <<'PYEOF'
import json
import sys

corner, output_path, status, elapsed = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    with open(output_path, encoding="utf-8") as handle:
        data = json.load(handle)
except (OSError, json.JSONDecodeError):
    data = None
entry = {"corner": corner, "run_status": status, "elapsed_s": int(elapsed), "response": data}
print(json.dumps(entry, indent=2), end="")
PYEOF
done

echo "]" >> "${RESULTS_FILE}"
python3 -c "import json; json.load(open('${RESULTS_FILE}'))" && echo "wrote ${RESULTS_FILE}" >&2
