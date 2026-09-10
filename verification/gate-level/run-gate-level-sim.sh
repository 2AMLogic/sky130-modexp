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
# Exit code is `klt functional-verification`'s own.
#
# ---------------------------------------------------------------------------
# Leg 2 (delay-annotated / SDF) -- NOT run by this script, invocation below
# ---------------------------------------------------------------------------
#
# This script runs Leg 1 only (zero-delay, extraction-based). Leg 2 is not a
# mode of it, for reasons that are properties of the run rather than of this
# wrapper:
#
#   * Leg 2 does not simulate this repo's committed layout at all. Leg 1's
#     netlist is derived from `layout/modexp.gds`; Leg 2 needs a netlist and
#     an SDF from the *same* OpenSTA session, which only a fresh `klt
#     place-and-route` re-run (`post_route_spef`/`post_route_sdf`) produces
#     -- and that re-run is not byte-reproducible against the committed GDS
#     (README.md, "Known upstream gaps").
#   * That re-run needs `openroad` (minutes of container time); Leg 1 needs
#     only `iverilog`.
#   * At this repo's pinned `klt` it FAILS, at `klt`'s own SDF-diagnostic
#     gate -- an expected non-zero exit, not a regression to be repaired.
#
# The full, literal, copy-pasteable cold-start sequence that produced the
# current Leg 2 evidence -- `./scripts/setup-env.sh` -> the P&R request
# carrying `post_route_spef`/`post_route_sdf` -> the `klt
# functional-verification` request carrying `options.sdf`, plus the scratch
# directory assembly those two calls need -- is the "Reproducing this run
# (cold start)" section of:
#
#   verification/records/gate-level-sim/records/20260909-230216-92e00f2.md
#
# Its two `klt` calls, for orientation (they are NOT runnable on their own --
# follow the record for the scratch-directory setup around them):
#
#   PDK=sky130A klt place-and-route "$PAR_DIR/par-modexp-sdf.json" --format json
#   klt functional-verification "$SIM/request-modexp-gate-level-sdf.json" --format json
#
# The frozen inputs both calls consume (the SDF-leg request document and its
# `FUNCTIONAL`-undefined defines file, the Leg 1 counterparts of which live
# next to this script) are artifacts of that same record:
#
#   verification/records/gate-level-sim/artifacts/20260909-230216-92e00f2/
#     request-modexp-gate-level-sdf.json
#     sky130_fd_sc_hd_sdf_defines.v

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../.." && pwd)"

FORMAT="json"
REGEN=1
for arg in "$@"; do
  case "${arg}" in
    --no-regen) REGEN=0 ;;
    --format=*) FORMAT="${arg#--format=}" ;;
    -h|--help) sed -n '2,65p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: ${arg}" >&2; exit 1 ;;
  esac
done

KLT="${KLT:-}"
if [ -z "${KLT}" ]; then
  if [ -x "${REPO_ROOT}/.venv/bin/klt" ]; then
    KLT="${REPO_ROOT}/.venv/bin/klt"
  elif command -v klt >/dev/null 2>&1; then
    KLT="$(command -v klt)"
  else
    echo "FATAL: no 'klt' found -- run ./scripts/setup-env.sh first." >&2
    exit 1
  fi
fi

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
  echo "== regenerating modexp_post_route.v from the layout extraction =="
  "${PY}" "${HERE}/spice_to_verilog.py" \
    "${REPO_ROOT}/layout/lvs/modexp_layout_abstracted.spice" \
    "${HD}/lef/sky130_fd_sc_hd.lef" \
    "${HERE}/modexp_post_route.v" \
    --report "${REPO_ROOT}/layout/lvs/modexp_layout_extract_report.json" \
    --check || {
      echo "FATAL: netlist derivation reported a validation problem -- refusing" >&2
      echo "  to simulate a netlist that does not match the extraction report." >&2
      exit 1
    }
fi

echo
echo "== klt functional-verification (post-route gate-level) =="
"${KLT}" functional-verification "${HERE}/request-modexp-gate-level.json" \
  --format "${FORMAT}"
exit $?
