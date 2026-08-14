#!/usr/bin/env bash
#
# scripts/setup-env.sh -- pin and provision this repo's verification
# environment.
#
#   1. Creates a local .venv (Python) and installs `klayout-tools` (`klt`)
#      into it at the pinned git revision below.
#   2. Fetches the pinned `sky130A` PDK version via `volare` into
#      `${PDK_ROOT:-$HOME/.volare}`.
#   3. Reports -- with an actionable message, never a Python traceback --
#      which of `iverilog`, `yosys`, `openroad` are missing from `$PATH`.
#
# Exit codes:
#   0  venv + klt + PDK provisioned. iverilog/yosys/openroad may still be
#      individually reported missing (see step 3's summary) -- this is not
#      itself a failure, since PDK-heavy legs (synthesis, P&R) are
#      documented as locally-run-and-recorded, not a CI/setup requirement.
#      P&R specifically needs `openroad`; see docs/environment.md.
#   1  venv creation, klt install, or PDK fetch failed.
#
# Usage:
#   ./scripts/setup-env.sh
#   ./scripts/setup-env.sh --pdk-root /custom/path
#
# The resolved versions this script pins are recorded in
# docs/environment.md -- update both together if you re-pin.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}" || exit 1

# --- pinned versions -- keep in sync with docs/environment.md -------------
KLT_REPO="https://github.com/2AMLogic/klayout-tools"
KLT_REV="af5791b557fc7c669c3981335a294256ccf37e6f"
VOLARE_PDK_FAMILY="sky130"
VOLARE_SKY130_VERSION="c6d73a35f524070e85faff4a6a9eef49553ebc2b"
# ----------------------------------------------------------------------------

PDK_ROOT="${PDK_ROOT:-${HOME}/.volare}"
VENV_DIR="${REPO_ROOT}/.venv"

for arg in "$@"; do
  case "${arg}" in
    --pdk-root)
      echo "error: --pdk-root requires a value, e.g. --pdk-root=/path" >&2
      exit 1
      ;;
    --pdk-root=*)
      PDK_ROOT="${arg#--pdk-root=}"
      ;;
    -h|--help)
      sed -n '2,26p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "unknown option: ${arg}" >&2
      exit 1
      ;;
  esac
done

status=0

echo "== 1/3 python venv =="
# cocotb 2.0.1 (pinned by klt) refuses to build on Python > 3.13 with a
# RuntimeError, not a graceful skip -- pick a compatible interpreter up
# front so that failure surfaces here, as an actionable message, rather
# than as a pip build-backend traceback in step 2.
PYTHON_BIN=""
for candidate in python3.13 python3.12 python3.11 python3.10 python3; do
  found="$(command -v "${candidate}" || true)"
  if [ -z "${found}" ]; then
    continue
  fi
  ver="$("${found}" -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")' 2>/dev/null)"
  major="${ver%%.*}"
  minor="${ver##*.}"
  if [ "${major}" = "3" ] && [ "${minor}" -le 13 ] 2>/dev/null; then
    PYTHON_BIN="${found}"
    break
  fi
done

if [ -z "${PYTHON_BIN}" ]; then
  echo "FATAL: no Python <= 3.13 interpreter found on \$PATH."
  echo "  cocotb 2.0.1 (the version klt/verification/cross_check.py pin)"
  echo "  refuses to build on Python 3.14+."
  echo "  -> install a compatible interpreter, e.g.:"
  echo "       brew install python@3.13   (macOS/Homebrew)"
  echo "       uv python install 3.13     (if 'uv' is available)"
  echo "       apt-get install python3.13 (Debian/Ubuntu with deadsnakes/backports)"
  echo "     then re-run this script; it prefers python3.13 > 3.12 > 3.11 >"
  echo "     3.10 > plain python3 automatically once one exists on \$PATH."
  exit 1
fi
echo "python3: $(${PYTHON_BIN} --version 2>&1) (${PYTHON_BIN})"

if [ ! -d "${VENV_DIR}" ]; then
  if ! "${PYTHON_BIN}" -m venv "${VENV_DIR}"; then
    echo "FATAL: 'python3 -m venv ${VENV_DIR}' failed."
    echo "  -> on Debian/Ubuntu this usually means the venv module is"
    echo "     missing: 'apt-get install python3-venv'."
    exit 1
  fi
  echo "created ${VENV_DIR}"
else
  echo "reusing existing ${VENV_DIR}"
fi

VENV_PY="${VENV_DIR}/bin/python3"
VENV_PIP="${VENV_DIR}/bin/pip"
if [ ! -x "${VENV_PY}" ]; then
  echo "FATAL: ${VENV_PY} not found after venv creation -- venv looks corrupt."
  echo "  -> remove ${VENV_DIR} and re-run this script."
  exit 1
fi

echo
echo "== 2/3 klayout-tools (klt) @ ${KLT_REV:0:12} =="
if ! "${VENV_PY}" -m pip --version >/dev/null 2>&1; then
  echo "FATAL: pip is not available inside ${VENV_DIR}."
  echo "  -> remove ${VENV_DIR} and re-run this script (venv bootstrap likely"
  echo "     failed partway through)."
  exit 1
fi

if ! "${VENV_PIP}" install --quiet --upgrade pip; then
  echo "WARNING: could not upgrade pip in ${VENV_DIR}; continuing with the"
  echo "  version venv bundled."
fi

if ! "${VENV_PIP}" install --quiet \
    "klayout-tools @ git+${KLT_REPO}@${KLT_REV}" cocotb volare; then
  echo "FATAL: failed to install klayout-tools/cocotb/volare into ${VENV_DIR}."
  echo "  -> common causes: no network access to ${KLT_REPO}, or no C/C++"
  echo "     toolchain for a dependency's native build (install Xcode CLI"
  echo "     tools on macOS: 'xcode-select --install'; build-essential on"
  echo "     Debian/Ubuntu)."
  echo "  -> re-run with the venv's own pip for a full traceback:"
  echo "       ${VENV_PIP} install \"klayout-tools @ git+${KLT_REPO}@${KLT_REV}\" cocotb volare"
  exit 1
fi
INSTALLED_KLT_VERSION="$("${VENV_PY}" -m klayout_tools.cli --version 2>/dev/null || true)"
INSTALLED_KLT_VERSION="${INSTALLED_KLT_VERSION#klt }"
echo "installed: klt ${INSTALLED_KLT_VERSION:-(version unknown)} from ${KLT_REPO}@${KLT_REV:0:12}"
echo "activate with: source ${VENV_DIR}/bin/activate"

echo
echo "== 3/3 sky130A PDK (volare ${VOLARE_SKY130_VERSION:0:12}) =="
mkdir -p "${PDK_ROOT}"
if "${VENV_DIR}/bin/volare" enable \
    --pdk-root "${PDK_ROOT}" --pdk "${VOLARE_PDK_FAMILY}" \
    "${VOLARE_SKY130_VERSION}"; then
  echo "sky130A ready under ${PDK_ROOT}"
else
  echo "FATAL: 'volare enable' failed to fetch sky130 ${VOLARE_SKY130_VERSION:0:12}."
  echo "  -> common causes: no network access to GitHub releases, or a rate"
  echo "     limit on unauthenticated GitHub API requests -- set GITHUB_TOKEN"
  echo "     and re-run, or run manually:"
  echo "       ${VENV_DIR}/bin/volare enable --pdk-root ${PDK_ROOT} --pdk ${VOLARE_PDK_FAMILY} ${VOLARE_SKY130_VERSION}"
  status=1
fi

echo
echo "== toolchain check (iverilog / yosys / openroad) =="
missing=()
for tool in iverilog yosys; do
  if command -v "${tool}" >/dev/null 2>&1; then
    case "${tool}" in
      iverilog) echo "  iverilog: $(iverilog -V 2>&1 | head -1)" ;;
      yosys)    echo "  yosys:    $(yosys -V 2>&1 | head -1)" ;;
    esac
  else
    missing+=("${tool}")
  fi
done

# openroad: prefer a native install already on $PATH. Otherwise, openroad has
# no Homebrew formula or common-distro package (see docs/environment.md), so
# fall back to the pinned openroad/orfs Docker image via
# scripts/openroad-docker.sh, symlinked into .venv/bin so activating the venv
# makes `openroad` resolve the same way iverilog/yosys do. This only installs
# the symlink (no network needed); the image itself is pulled lazily on first
# `openroad` invocation.
if command -v openroad >/dev/null 2>&1; then
  echo "  openroad: $(openroad -version 2>&1 | head -1) (native, on \$PATH)"
elif command -v docker >/dev/null 2>&1; then
  ln -sf "../../scripts/openroad-docker.sh" "${VENV_DIR}/bin/openroad"
  chmod +x "${VENV_DIR}/bin/openroad"
  echo "  openroad: not native, but docker is available -- symlinked"
  echo "    ${VENV_DIR}/bin/openroad -> scripts/openroad-docker.sh (pinned"
  echo "    openroad/orfs image; see docs/environment.md). After"
  echo "    'source ${VENV_DIR}/bin/activate', 'openroad -version' resolves"
  echo "    through Docker (first call pulls the image)."
else
  missing+=("openroad")
fi

if [ "${#missing[@]}" -gt 0 ]; then
  echo
  echo "MISSING TOOLS: ${missing[*]}"
  for tool in "${missing[@]}"; do
    case "${tool}" in
      iverilog)
        echo "  - iverilog (Icarus Verilog): 'brew install icarus-verilog' (macOS)"
        echo "    or 'apt-get install iverilog' (Debian/Ubuntu). Required for"
        echo "    'klt functional-verification' and verification/cross_check.py."
        ;;
      yosys)
        echo "  - yosys: 'brew install yosys' (macOS) or 'apt-get install yosys'"
        echo "    (Debian/Ubuntu). Required for 'klt synthesize'."
        ;;
      openroad)
        echo "  - openroad: no package-manager formula on macOS or common Linux"
        echo "    distros as of this writing, and no 'docker' found on \$PATH"
        echo "    either, so scripts/openroad-docker.sh's fallback route"
        echo "    couldn't be wired up automatically. Install Docker (or"
        echo "    Docker Desktop), then re-run this script -- or see"
        echo "    docs/environment.md's 'OpenROAD' section for the pinned"
        echo "    image, its digest, and a from-source alternative."
        echo "    Required for 'klt place-and-route' -- see docs/environment.md."
        ;;
    esac
  done
  echo
  echo "This is expected and non-fatal for this script: the cross-check and"
  echo "record linter (npm run test / npm run lint) need only iverilog and"
  echo "python3+git. synthesis needs yosys; place-and-route additionally"
  echo "needs openroad -- see verification/README.md's CI-split section for"
  echo "which legs run where."
else
  echo "all of iverilog/yosys/openroad resolve (natively or, for openroad,"
  echo "  via the pinned Docker route)."
fi

echo
if [ "${status}" -eq 0 ]; then
  echo "RESULT: environment provisioned (venv + klt + sky130A)."
else
  echo "RESULT: environment provisioning incomplete -- see FATAL messages above."
fi
exit "${status}"
