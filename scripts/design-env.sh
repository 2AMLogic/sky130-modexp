# shellcheck shell=bash
#
# scripts/design-env.sh -- the one implementation of the `$DESIGN` and `$KLT`
# input contracts shared by this repo's shell runners.
#
# This is the shell counterpart of `verification/_repo_utils.py`, and exists
# for the same reason that module's docstring gives: centralizing the logic
# means a future change "only needs to happen once instead of being replayed
# -- and silently drifting -- across multiple files."
#
# That drift was not hypothetical (issue #337). PR #212 parametrized three
# runners on `$DESIGN` by pasting the same twelve-line block into each. Two
# copies stayed byte-identical; the third had already drifted to `exit 1`
# where the others said `exit 2`, so two scripts told a caller
# "unambiguous-design failure = 2" and the third said 1. The three `klt`
# resolutions had drifted further: one honoured `$KLT`, one ignored it and
# overwrote it, and one did not resolve `klt` at all. `$KLT` is a real
# contract -- `verification/signoff/run-signoff.sh` documents pointing it at a
# throwaway venv as the supported way to check a `klayout-tools` pin bump --
# so a runner that ignores it silently reports a version the caller did not
# ask for.
#
# SOURCED, NEVER EXECUTED (hence no shebang and mode 644, as with
# `verification/_repo_utils.py`). Each caller still resolves `$REPO_ROOT`
# itself, on one line, before sourcing this file: a sourced file cannot
# resolve the root by which it is being located.
#
#   REPO_ROOT="${REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
#   . "${REPO_ROOT}/scripts/design-env.sh"
#   design_env_require_design
#
# Both helpers are deliberately *functions*, not work done at source time, so
# a caller can resolve each contract at the point it actually needs it. That
# matters for `klt`: `flow/run-sta-corner-sweep.sh --help` must keep working
# on a host with no `klt` installed, which it would not if sourcing this file
# resolved `klt` fatally before argument parsing.
#
# Like the scripts that source it, this file is written so a byte-identical
# copy works from any directory depth -- but it must TRAVEL WITH THEM. A
# vendored `common/` copy of `flow/run-par.sh`,
# `flow/run-sta-corner-sweep.sh` or
# `verification/gate-level/run-gate-level-sim.sh` needs this file at
# `${REPO_ROOT}/scripts/design-env.sh`; the pair travels together, the same
# constraint `docs/environment.md` records for `verification/_repo_utils.py`.
#
# `verification/signoff/run-signoff.sh` deliberately does NOT use
# `design_env_require_klt`: its PATH-only lookup is tied to the
# `SIGNOFF_KLT_VERSION` assertion right below it, which must refuse a
# `.venv/bin/klt` of any other version rather than silently prefer it.

# Resolve the design name into $DESIGN: the caller's $DESIGN if set, else the
# stem of the repo's one rtl/*.v file. With zero or several RTL files there is
# no unambiguous default, so fail loudly (exit 2) rather than guess.
#
# Requires $REPO_ROOT. Sets $DESIGN. Exits 2 on an unresolvable design.
design_env_require_design() {
  if [ -n "${DESIGN:-}" ]; then
    return 0
  fi
  if [ -z "${REPO_ROOT:-}" ]; then
    echo "FATAL: design_env_require_design needs \$REPO_ROOT set by the caller." >&2
    exit 2
  fi
  local -a _rtl
  _rtl=("${REPO_ROOT}"/rtl/*.v)
  if [ "${#_rtl[@]}" -eq 1 ] && [ -f "${_rtl[0]}" ]; then
    DESIGN="$(basename "${_rtl[0]}" .v)"
  else
    echo "FATAL: DESIGN not set and ${REPO_ROOT}/rtl does not hold exactly one .v file." >&2
    exit 2
  fi
}

# Resolve the `klt` executable into $KLT: the caller's $KLT if set (the
# documented way to run a leg against a specific klayout-tools pin), else the
# repo's own .venv/bin/klt, else whatever is on $PATH.
#
# Requires $REPO_ROOT. Sets $KLT. Exits 1 when no klt can be found.
design_env_require_klt() {
  if [ -n "${KLT:-}" ]; then
    return 0
  fi
  if [ -z "${REPO_ROOT:-}" ]; then
    echo "FATAL: design_env_require_klt needs \$REPO_ROOT set by the caller." >&2
    exit 2
  fi
  if [ -x "${REPO_ROOT}/.venv/bin/klt" ]; then
    KLT="${REPO_ROOT}/.venv/bin/klt"
  elif command -v klt >/dev/null 2>&1; then
    KLT="$(command -v klt)"
  else
    echo "FATAL: no 'klt' found -- set \$KLT, or run ./scripts/setup-env.sh first." >&2
    exit 1
  fi
}
