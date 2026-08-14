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
# The current working directory is bind-mounted into the container at
# /workspace (also the container's working directory), so relative paths in
# a Tcl script (read_lef, write_def, etc.) resolve the same way they would
# against a natively-installed `openroad`. Set OPENROAD_DOCKER_MOUNT to
# bind-mount a different host directory instead.
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

# Forward a small allowlist of ORFS/OpenROAD-relevant env vars from the host
# shell into the container, if set there -- e.g. PLATFORM_DIR (this repo's
# own scripts/openroad-smoke-test.sh sets it to point at the image's bundled
# sky130hd platform data). `docker run -e VAR` with VAR unset in the calling
# shell is a harmless no-op, not an error.
ENV_ARGS=(-e PLATFORM_DIR -e PDK_ROOT)

exec docker run --rm --platform linux/amd64 \
  -v "${MOUNT_DIR}:/workspace" \
  -w /workspace \
  "${ENV_ARGS[@]}" \
  "${OPENROAD_DOCKER_IMAGE}@${OPENROAD_DOCKER_DIGEST}" \
  bash -lc 'source /OpenROAD-flow-scripts/env.sh >/dev/null 2>&1 && exec openroad "$@"' bash "$@"
