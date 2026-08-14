#!/usr/bin/env bash
#
# scripts/openroad-smoke-test.sh -- trivial end-to-end proof that `openroad`
# actually executes on this host (issue #13's acceptance criterion: "not
# merely that the binary answers -version").
#
# Drives OpenROAD's Tcl engine through a real (if tiny) slice of the P&R
# flow -- LEF parse, netlist link, floorplan initialization, DEF write --
# against a hand-written one-cell netlist (scripts/openroad-smoke/smoke_top.v),
# not this repo's RTL. This is toolchain verification only; it produces no
# P&R measurement for rtl/modexp.v (that is issue #7's job) and writes
# nothing under verification/ or layout/.
#
# Usage:
#   ./scripts/openroad-smoke-test.sh
#
# Uses `openroad` from $PATH if present (native install or a
# scripts/openroad-docker.sh symlink from scripts/setup-env.sh); otherwise
# falls back to scripts/openroad-docker.sh directly.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_DIR="${REPO_ROOT}/scripts/openroad-smoke"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

cp "${SMOKE_DIR}/smoke.tcl" "${SMOKE_DIR}/smoke_top.v" "${WORK_DIR}/"

if command -v openroad >/dev/null 2>&1; then
  OPENROAD_CMD=(openroad)
  echo "using openroad from \$PATH: $(command -v openroad)"
else
  OPENROAD_CMD=("${REPO_ROOT}/scripts/openroad-docker.sh")
  echo "openroad not on \$PATH; using ${OPENROAD_CMD[0]} (Docker route)"
fi

export PLATFORM_DIR="/OpenROAD-flow-scripts/flow/platforms/sky130hd"
export OPENROAD_DOCKER_MOUNT="${WORK_DIR}"

echo "== running smoke.tcl in ${WORK_DIR} =="
LOG_FILE="${WORK_DIR}/smoke.log"
if ! ( cd "${WORK_DIR}" && "${OPENROAD_CMD[@]}" -no_init -exit smoke.tcl ) >"${LOG_FILE}" 2>&1; then
  echo "FAIL: openroad exited non-zero. Full log:" >&2
  cat "${LOG_FILE}" >&2
  exit 1
fi

cat "${LOG_FILE}"

MISSING=0
for marker in "SMOKE-OK: die_area=" "SMOKE-OK: block=smoke_top" "SMOKE-OK: wrote smoke.def"; do
  if ! grep -qF "${marker}" "${LOG_FILE}"; then
    echo "FAIL: expected marker not found in output: ${marker}" >&2
    MISSING=1
  fi
done

if [ ! -s "${WORK_DIR}/smoke.def" ]; then
  echo "FAIL: smoke.def was not written (or is empty)." >&2
  MISSING=1
fi

if [ "${MISSING}" -ne 0 ]; then
  exit 1
fi

echo
echo "PASS: openroad executed a real LEF-read/link_design/initialize_floorplan/write_def sequence and wrote a non-empty DEF."
