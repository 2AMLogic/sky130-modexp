#!/usr/bin/env bash
#
# flow/run-corner-sweep.sh -- run the full `klt place-and-route` flow
# (floorplan -> place -> cts -> route) independently at every corner in the
# ratified sky130_fd_sc_hd corner matrix (spec/decision-records/0001-...,
# Decision 4), and collect each run's route-stage metrics into one JSON
# summary.
#
# Why a full independent run per corner, not a single physical build re-
# timed at each corner: `klt place-and-route` (klayout-tools 0.2.0) always
# runs its own floorplan->place->cts->route sequence from scratch for a
# given request -- there is no request field or CLI flag to re-run only the
# post-route STA stage against an already-produced routed database at a
# different liberty corner. That is a real capability gap (filed generically
# at 2AMLogic/klayout-tools per this repo's CLAUDE.md friction protocol);
# this script's workaround is the only thing `klt place-and-route` currently
# supports -- N independent full builds, one per corner, each with the same
# pinned seed. Each run typically takes several minutes; expect the full
# 18-corner sweep to take on the order of an hour or more.
#
# Every corner directory under flow/corners/<corner>/ is its own klt
# request (netlist/floorplan/io/constraints/seed identical to the committed
# flow/par-modexp.json, only `pdk.corner` varies), each producing its own
# `.klt/place-and-route/` scratch output (gitignored, like every other klt
# scratch directory) -- so runs never clobber each other and can be re-run
# individually.
#
# Usage:
#   ./flow/run-corner-sweep.sh                    # all 18 ratified corners
#   ./flow/run-corner-sweep.sh tt_025C_1v80        # a single named corner
#   ./flow/run-corner-sweep.sh ss_100C_1v40 ff_100C_1v65
#
# Requires: `klt synthesize flow/synthesize-modexp.json` and
# `python3 flow/tie_constants.py ...` already run (flow/README.md's
# cold-start recipe) so flow/.klt/synthesize/modexp_synth_tied.v exists.
#
# Writes flow/corner-sweep-results.json (the aggregated summary this
# script's own stdout table is derived from) -- not committed as-is; the
# evidence record under verification/records/place-and-route/ freezes a
# copy as an artifact.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLOW_DIR="${REPO_ROOT}/flow"
TIED_NETLIST="${FLOW_DIR}/.klt/synthesize/modexp_synth_tied.v"

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

if [ ! -f "${TIED_NETLIST}" ]; then
  echo "FATAL: ${TIED_NETLIST} not found." >&2
  echo "  Run first: PDK=sky130A klt synthesize flow/synthesize-modexp.json" >&2
  echo "  then:      python3 flow/tie_constants.py flow/.klt/synthesize/modexp_synth.v ${TIED_NETLIST}" >&2
  exit 1
fi

RESULTS_FILE="${FLOW_DIR}/corner-sweep-results.json"
echo "[" > "${RESULTS_FILE}"
first=1

for corner in "${CORNERS[@]}"; do
  corner_dir="${FLOW_DIR}/corners/${corner}"
  mkdir -p "${corner_dir}"
  request_path="${corner_dir}/par-modexp.json"
  python3 - "${request_path}" "${corner}" "${TIED_NETLIST}" <<'PYEOF'
import json
import os
import sys

request_path, corner, netlist_abs = sys.argv[1], sys.argv[2], sys.argv[3]
request_dir = os.path.dirname(request_path)
netlist_rel = os.path.relpath(netlist_abs, request_dir)

request = {
    "schema": "klt.place-and-route.request/1",
    "engine": "openroad",
    "netlist": netlist_rel,
    "hdl_toplevel": "modexp",
    "pdk": {"cell_library": "sky130_fd_sc_hd", "corner": corner},
    "floorplan": {
        "method": "utilization",
        "utilization_pct": 35,
        "aspect_ratio": 1,
        "core_margin_um": 4,
        "site": "unithd",
    },
    "io": {"layer_h": "met3", "layer_v": "met2"},
    "constraints": {"clock_port": "clk", "clock_period_ns": 10.0},
    "seed": 42,
    "target_stage": "route",
}
with open(request_path, "w", encoding="utf-8") as handle:
    json.dump(request, handle, indent=2)
    handle.write("\n")
PYEOF

  echo "== ${corner} ==" >&2
  start_ts=$(date +%s)
  if PDK=sky130A klt place-and-route "${request_path}" --format json > "${corner_dir}/par-output.json" 2> "${corner_dir}/par-output.log"; then
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
  python3 - "${corner}" "${corner_dir}/par-output.json" "${status}" "${elapsed}" >> "${RESULTS_FILE}" <<'PYEOF'
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
