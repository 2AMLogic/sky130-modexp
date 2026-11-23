#!/usr/bin/env bash
#
# verification/gate-level/run-gate-level-sim.sh -- run the committed,
# unmodified bit-exact suite (`verification/test_modexp.py`) against the
# post-route-derived gate-level netlist through `klt functional-verification`.
#
# Two things this wrapper does, and why (both are `klt` request-schema gaps,
# see verification/gate-level/README.md's "Known upstream gaps"):
#
#   1. Resolves the installed sky130A PDK (via `klt pdk find`) and links its
#      two Verilog cell-model files into this directory under fixed names, so
#      the committed request can name them with machine-independent relative
#      paths. `klt.functional_verification.request/1` has no PDK block and no
#      include-path field, so a request that names cell models must name them
#      by path.
#   2. Regenerates `modexp_post_route.v` from the layout extraction unless
#      `--no-regen` is given, so a stale committed netlist can never be what
#      the evidence is produced against.
#
# Usage:
#   ./verification/gate-level/run-gate-level-sim.sh [--no-regen] [--format json|text]
#
# <design> below is $DESIGN, else the stem of the repo's single rtl/*.v file.
# The repo root is $REPO_ROOT, else `git rev-parse --show-toplevel`, so the
# same bytes work from any directory depth. `klt` is $KLT, else
# <repo root>/.venv/bin/klt, else whatever is on $PATH -- set $KLT to run this
# leg against a specific klayout-tools pin. All three contracts are resolved
# by scripts/design-env.sh, which must travel with this script. The per-design
# request (request-<design>-gate-level.json) and netlist
# (<design>_post_route.v) sit next to this script.
#
# Exit code is `klt functional-verification`'s own.
#
# This script runs Leg 1 only (zero-delay, extraction-derived). Leg 2 (the
# delay-annotated SDF replay, `openroad`) is not a mode of it -- see
# verification/gate-level/README.md ("Leg 2") for how it is run and its
# current evidence.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "${HERE}" rev-parse --show-toplevel)}"

# shellcheck source=../../scripts/design-env.sh
. "${REPO_ROOT}/scripts/design-env.sh" || {
  echo "FATAL: cannot source ${REPO_ROOT}/scripts/design-env.sh -- it must travel with this script." >&2
  exit 2
}
design_env_require_design

FORMAT="json"
REGEN=1
for arg in "$@"; do
  case "${arg}" in
    --no-regen) REGEN=0 ;;
    --format=*) FORMAT="${arg#--format=}" ;;
    -h|--help) sed -n '2,/^set -uo/{/^set -uo/d;p;}' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: ${arg}" >&2; exit 1 ;;
  esac
done

design_env_require_klt

PY="${REPO_ROOT}/.venv/bin/python3"
[ -x "${PY}" ] || PY="$(command -v python3)"

echo "== resolving sky130A PDK =="
PDK_JSON="$("${KLT}" pdk find --pdk sky130A --format json)" || {
  echo "FATAL: 'klt pdk find --pdk sky130A' failed -- run ./scripts/setup-env.sh." >&2
  exit 1
}
LIBS_REF="$(printf '%s' "${PDK_JSON}" | "${PY}" -c 'import json,sys; print(json.load(sys.stdin)["assets"]["libs_ref"])')"
PDK_VERSION="$(printf '%s' "${PDK_JSON}" | "${PY}" -c 'import json,sys; print(json.load(sys.stdin)["version"])')"
HD="${LIBS_REF}/sky130_fd_sc_hd"
echo "  libs.ref: ${LIBS_REF}"
echo "  version:  ${PDK_VERSION}"

for f in "${HD}/verilog/primitives.v" "${HD}/verilog/sky130_fd_sc_hd.v" \
         "${HD}/lef/sky130_fd_sc_hd.lef"; do
  if [ ! -f "${f}" ]; then
    echo "FATAL: expected PDK file not found: ${f}" >&2
    exit 1
  fi
done

# Machine-independent names for the two cell-model files the committed
# request lists in `sources` (gitignored -- see .gitignore).
ln -sfn "${HD}/verilog/primitives.v" "${HERE}/pdk-primitives.v"
ln -sfn "${HD}/verilog/sky130_fd_sc_hd.v" "${HERE}/pdk-sky130_fd_sc_hd.v"
echo "  linked pdk-primitives.v, pdk-sky130_fd_sc_hd.v"

if [ "${REGEN}" -eq 1 ]; then
  echo
  echo "== regenerating ${DESIGN}_post_route.v from the layout extraction =="
  "${PY}" "${HERE}/spice_to_verilog.py" \
    "${REPO_ROOT}/layout/lvs/${DESIGN}_layout_abstracted.spice" \
    "${HD}/lef/sky130_fd_sc_hd.lef" \
    "${HERE}/${DESIGN}_post_route.v" \
    --report "${REPO_ROOT}/layout/lvs/${DESIGN}_layout_extract_report.json" \
    --top "${DESIGN}" \
    --check || {
      echo "FATAL: netlist derivation reported a validation problem -- refusing" >&2
      echo "  to simulate a netlist that does not match the extraction report." >&2
      exit 1
    }
fi

echo
echo "== klt functional-verification (post-route gate-level) =="
"${KLT}" functional-verification "${HERE}/request-${DESIGN}-gate-level.json" \
  --format "${FORMAT}"
exit $?
