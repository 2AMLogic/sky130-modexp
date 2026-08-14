#!/usr/bin/env bash
#
# scripts/openroad-docker.sh -- invoke the pinned openroad/orfs Docker
# image's `openroad` binary as if it were a native `openroad` on $PATH.
#
# Why a container, not a native install: `openroad` has no Homebrew formula
# and no common Linux-distro package as of this writing (see
# docs/environment.md's "OpenROAD" section). OpenROAD-flow-scripts (ORFS)
# publishes an official Docker image with a matched, pinned OpenROAD +
# Yosys + KLayout toolchain -- the route
# `2AMLogic/klayout-tools`'s `docs/design/openroad-invocation-survey.md`
# (issue #397 there) already investigated from this same class of host
# (macOS/arm64 via Docker Desktop's `linux/amd64` emulation) and confirmed
# works; this script reuses that finding rather than re-deriving it.
#
# `scripts/setup-env.sh` symlinks `.venv/bin/openroad` to this script
# whenever a native `openroad` is not already on $PATH and `docker` is
# available, so `source .venv/bin/activate` makes `openroad` resolve the
# same way it does for `iverilog`/`yosys`. It can also be run directly.
#
# Usage (identical to a native `openroad` binary):
#   ./scripts/openroad-docker.sh -version
#   ./scripts/openroad-docker.sh -no_init -exit script.tcl
#
# The current working directory is bind-mounted into the container at the
# *same absolute path* it has on the host (not at a fixed /workspace) --
# both the mount source and target are ${MOUNT_DIR}, and the container's
# working directory is set to that same path. This matters beyond relative
# paths: `klt place-and-route` (klayout-tools) generates its per-stage Tcl
# scripts with **absolute host paths** baked in throughout -- the netlist,
# LEF/liberty deck, and every `-metrics`/`write_db`/`write_def` output path
# are all `os.path.abspath()`-resolved before being written into the script
# or passed as an `openroad` CLI argument. An earlier revision of this
# script bind-mounted the host directory at a container-internal
# `/workspace` instead, which works for the relative-path-only smoke test
# (`scripts/openroad-smoke-test.sh`) but silently fails any real
# `klt place-and-route` run: every absolute host path a stage script
# references (e.g. `/Users/you/.volare/sky130A/...` for the liberty/LEF
# deck, which lives *outside* the repo entirely) resolves to nothing inside
# a container whose filesystem was never given that path. Mounting
# source==target for both the repo tree and the resolved PDK root (below)
# is what makes those absolute paths resolve identically on both sides of
# the container boundary. Set OPENROAD_DOCKER_MOUNT to bind-mount a
# different host directory instead of $(pwd).
#
# -- pinned version -- keep in sync with docs/environment.md -----------------
# `openroad -version` inside this image reports 26Q3-1260-g06a5a02279.
OPENROAD_DOCKER_IMAGE="${OPENROAD_DOCKER_IMAGE:-openroad/orfs:26Q3-296-gda37dce1c}"
OPENROAD_DOCKER_DIGEST="${OPENROAD_DOCKER_DIGEST:-sha256:ebc8142da6d65d1a1e9a528aa2cedcde356243465dd859af8d3ade51075f8cb2}"
# ------------------------------------------------------------------------------

set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "FATAL: docker not found on \$PATH." >&2
  echo "  openroad is provisioned on this host only via the pinned" >&2
  echo "  ${OPENROAD_DOCKER_IMAGE} Docker image -- install Docker (or Docker" >&2
  echo "  Desktop) and re-run. See docs/environment.md's 'OpenROAD' section." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "FATAL: docker daemon is not reachable (is Docker Desktop running?)." >&2
  exit 1
fi

MOUNT_DIR="${OPENROAD_DOCKER_MOUNT:-$(pwd)}"

# Resolve the PDK root the same way klayout-tools' `find_pdk()` does
# (docs/environment.md / klayout_tools/pdk.py resolution order: $PDK_ROOT
# env var, then ~/.ciel, then ~/.volare) so it can be bind-mounted too --
# `klt place-and-route`/`klt synthesize` resolve liberty/LEF paths under
# there, and those absolute host paths need to exist inside the container
# at the identical path (see comment block above). Best-effort: if none of
# these exist, no extra mount is added and a downstream `openroad` "cannot
# read file" error will point at the same gap this comment describes.
PDK_MOUNT_DIR=""
if [ -n "${PDK_ROOT:-}" ] && [ -d "${PDK_ROOT}" ]; then
  PDK_MOUNT_DIR="${PDK_ROOT}"
elif [ -d "${HOME}/.ciel" ]; then
  PDK_MOUNT_DIR="${HOME}/.ciel"
elif [ -d "${HOME}/.volare" ]; then
  PDK_MOUNT_DIR="${HOME}/.volare"
fi

VOLUME_ARGS=(-v "${MOUNT_DIR}:${MOUNT_DIR}")
if [ -n "${PDK_MOUNT_DIR}" ] && [ "${PDK_MOUNT_DIR}" != "${MOUNT_DIR}" ]; then
  VOLUME_ARGS+=(-v "${PDK_MOUNT_DIR}:${PDK_MOUNT_DIR}")
fi

# Forward a small allowlist of ORFS/OpenROAD-relevant env vars from the host
# shell into the container, if set there -- e.g. PLATFORM_DIR (this repo's
# own scripts/openroad-smoke-test.sh sets it to point at the image's bundled
# sky130hd platform data). `docker run -e VAR` with VAR unset in the calling
# shell is a harmless no-op, not an error.
ENV_ARGS=(-e PLATFORM_DIR -e PDK_ROOT)

exec docker run --rm --platform linux/amd64 \
  "${VOLUME_ARGS[@]}" \
  -w "${MOUNT_DIR}" \
  "${ENV_ARGS[@]}" \
  "${OPENROAD_DOCKER_IMAGE}@${OPENROAD_DOCKER_DIGEST}" \
  bash -lc 'source /OpenROAD-flow-scripts/env.sh >/dev/null 2>&1 && exec openroad "$@"' bash "$@"
