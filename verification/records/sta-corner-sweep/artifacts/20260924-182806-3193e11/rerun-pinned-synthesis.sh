#!/usr/bin/env bash
#
# Re-run record 20260924-134500-1a8313b's committed `klt synthesize` request
# at the Yosys/ABC build pinned by scripts/setup-env.sh, and print the
# mapped-instance count.
#
# This is the "something to compare against" half of issue #143: the number
# this prints is only meaningful because the mapper that produced it is
# identified by CONTENT (the sha256 of the WebAssembly module that contains
# Yosys and its embedded `abc`), not by `yosys -V`. The script refuses to run
# if that digest does not match the pin.
#
# Usage:
#   ./scripts/setup-env.sh                       # provisions the pinned build
#   .venv/bin/pip install --force-reinstall \
#     "klayout-tools @ git+https://github.com/2AMLogic/klayout-tools@c66f18fd62250c5b71046e4e2a2b0288024eaff0"
#   ./verification/records/sta-corner-sweep/artifacts/20260924-182806-3193e11/rerun-pinned-synthesis.sh
#
# The `klt` force-reinstall is the recipe docs/environment.md already
# documents for record 20260924-134500-1a8313b: this repo's `klt` pin
# (`dac2b5da`) predates `constraints.dont_use`, which this request uses.
#
# Exit codes: 0 both runs succeeded and agreed; 1 anything else.

set -uo pipefail

RECORD_ID="20260924-182806-3193e11"
# The pin, restated here so this frozen artifact asserts it independently of
# whatever scripts/setup-env.sh says at read time.
EXPECTED_WASM_SHA256="e37a7e65e3fa4efbbd64a9c1b0e906be16cdc6c4d5273109d17537f78449f38c"
KLT_REV_USED="c66f18fd62250c5b71046e4e2a2b0288024eaff0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../../../../.." && pwd)"
VENV_DIR="${REPO_ROOT}/.venv"
FROZEN_DIR="${REPO_ROOT}/verification/records/sta-corner-sweep/artifacts"
REQUEST_SRC="${FROZEN_DIR}/20260924-134500-1a8313b/synth-request.json"
RTL_SRC="${FROZEN_DIR}/20260923-093000-28a7c96/candidates/rtl/modexp-bit-serial.v"

# Scratch lives under the repo's gitignored .klt/, NOT under $TMPDIR: the
# pinned Yosys is a WASI build whose sandbox mounts a private directory over
# /tmp, so a run staged in the host temp dir cannot read its own script.
SCRATCH="${REPO_ROOT}/.klt/rerun-${RECORD_ID}"

for f in "${REQUEST_SRC}" "${RTL_SRC}"; do
  if [ ! -f "${f}" ]; then
    echo "FATAL: missing frozen input ${f}" >&2
    exit 1
  fi
done

if [ ! -x "${VENV_DIR}/bin/klt" ] || [ ! -e "${VENV_DIR}/bin/yosys" ]; then
  echo "FATAL: ${VENV_DIR} is not provisioned -- run ./scripts/setup-env.sh first." >&2
  exit 1
fi

ACTUAL_WASM_SHA256="$("${VENV_DIR}/bin/python3" - <<'PY'
import hashlib
import os

try:
    import yowasp_yosys
except Exception:
    print("")
    raise SystemExit(0)

path = os.path.join(os.path.dirname(yowasp_yosys.__file__), "yosys.wasm")
if not os.path.isfile(path):
    print("")
    raise SystemExit(0)

digest = hashlib.sha256()
with open(path, "rb") as handle:
    for chunk in iter(lambda: handle.read(1 << 20), b""):
        digest.update(chunk)
print(digest.hexdigest())
PY
)"

if [ "${ACTUAL_WASM_SHA256}" != "${EXPECTED_WASM_SHA256}" ]; then
  echo "FATAL: the Yosys/ABC build in ${VENV_DIR} is not the pinned one." >&2
  echo "  expected sha256:${EXPECTED_WASM_SHA256}" >&2
  echo "  actual   sha256:${ACTUAL_WASM_SHA256:-<no yowasp_yosys installed>}" >&2
  echo "  -> a different mapper build produces a different instance count;" >&2
  echo "     numbers from it are not comparable with this record's." >&2
  exit 1
fi
echo "pinned Yosys/ABC build: sha256:${ACTUAL_WASM_SHA256} (ok)"
echo "klt: $("${VENV_DIR}/bin/klt" --version 2>&1) (this record used ${KLT_REV_USED:0:12})"

rm -rf "${SCRATCH}"
mkdir -p "${SCRATCH}/rtl" "${SCRATCH}/flow"
cp "${RTL_SRC}" "${SCRATCH}/rtl/modexp.v"
cp "${REQUEST_SRC}" "${SCRATCH}/flow/synth-request.json"

status=0
for run in 1 2; do
  out="${SCRATCH}/response-run${run}.json"
  if ! ( cd "${SCRATCH}" \
         && PATH="${VENV_DIR}/bin:${PATH}" \
            "${VENV_DIR}/bin/klt" synthesize flow/synth-request.json \
            --format json > "${out}" ); then
    echo "FATAL: klt synthesize failed on run ${run}; response:" >&2
    cat "${out}" >&2
    echo "  -> if the error names constraints.dont_use, install the klt" >&2
    echo "     revision in this file's usage note (this repo's klt pin" >&2
    echo "     predates that request field)." >&2
    exit 1
  fi
  "${VENV_DIR}/bin/python3" - "${out}" "${run}" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1]))
print(
    f"run {sys.argv[2]}: status={response['status']} "
    f"engine_version={response['engine_version']} "
    f"instance_count={response['instance_count']} "
    f"area_um2={response['area_um2']}"
)
PY
done

"${VENV_DIR}/bin/python3" - "${SCRATCH}" "${HERE}" <<'PY' || status=1
import hashlib
import json
import pathlib
import sys

scratch, here = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
runs = [json.load(open(scratch / f"response-run{n}.json")) for n in (1, 2)]
frozen = json.load(open(here / "synth-report-pinned-run1.json"))

volatile = {"run_id", "netlist_path", "script_path", "run_script_path"}


def stable(doc):
    return {k: v for k, v in doc.items() if k not in volatile}


ok = True
if stable(runs[0]) != stable(runs[1]):
    print("MISMATCH: the two runs at the pin disagree")
    ok = False
if runs[0]["instance_count"] != frozen["instance_count"]:
    print(
        f"MISMATCH: instance_count {runs[0]['instance_count']} != "
        f"{frozen['instance_count']} recorded by this record"
    )
    ok = False

netlists = set()
for run_dir in sorted((scratch / "flow" / ".klt" / "synthesize").glob("run-*")):
    netlist = run_dir / "modexp_synth.v"
    if netlist.is_file():
        netlists.add(hashlib.sha256(netlist.read_bytes()).hexdigest())
if len(netlists) == 1:
    print(f"netlist sha256: {netlists.pop()} (identical across both runs)")
elif netlists:
    print(f"MISMATCH: the two runs produced different netlists: {sorted(netlists)}")
    ok = False

print("RESULT: reproduced this record" if ok else "RESULT: DID NOT reproduce")
raise SystemExit(0 if ok else 1)
PY

exit "${status}"
