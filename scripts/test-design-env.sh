#!/usr/bin/env bash
#
# scripts/test-design-env.sh -- regression suite for scripts/design-env.sh and
# for the three shell runners that source it.
#
# Why this exists (issue #337): the `$DESIGN` and `$KLT` contracts used to have
# three implementations between them, and they had already drifted -- one
# runner answered an unresolvable design with `exit 1` where the other two said
# `exit 2`, and two of the three ignored `$KLT` entirely, so pointing `$KLT` at
# a throwaway `klayout-tools` pin silently ran a different klt than the caller
# asked for. Consolidating onto one sourced helper makes that drift
# structurally impossible; this suite makes a *regression* of it loud, by
# asserting the resolution matrix and asserting all three runners agree on the
# design-failure exit code.
#
# Tool-light by construction: no PDK, no simulator, no real klt. The `klt`
# executables it resolves are one-line stubs in a per-test sandbox, so this
# runs anywhere `bash` does.
#
# Usage: ./scripts/test-design-env.sh      (exit 0 all passed, 1 otherwise)
# The repo root is $REPO_ROOT, else `git rev-parse --show-toplevel`, so the
# same bytes work from any directory depth.

set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
HELPER="${REPO_ROOT}/scripts/design-env.sh"

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n       %s\n' "$1" "$2" >&2; }

# Assert the helper, sourced in a clean shell with the given environment,
# resolves to the expected "DESIGN=<d> KLT=<k>" and exit status.
# usage: expect_helper <name> <want_rc> <want_stdout> <fn> [env assignments...]
expect_helper() {
  local name="$1" want_rc="$2" want_out="$3" fn="$4"; shift 4
  local out rc
  out="$(env -u DESIGN -u KLT "$@" bash -c '
    set -uo pipefail
    . "${HELPER}"
    '"${fn}"'
    printf "DESIGN=%s KLT=%s" "${DESIGN:-}" "${KLT:-}"
  ' 2>/dev/null)"
  rc=$?
  if [ "${rc}" -ne "${want_rc}" ]; then
    no "${name}" "exit ${rc}, wanted ${want_rc}"
  elif [ "${out}" != "${want_out}" ]; then
    no "${name}" "got '${out}', wanted '${want_out}'"
  else
    ok "${name}"
  fi
}

# A sandbox repo: one rtl/<design>.v, a .venv klt and a PATH klt, each stub
# announcing which one it is.
make_sandbox() {
  local dir="$1" design="${2:-widget}"
  mkdir -p "${dir}/scripts" "${dir}/rtl" "${dir}/layout" "${dir}/flow" \
           "${dir}/.venv/bin" "${dir}/bin"
  cp "${HELPER}" "${dir}/scripts/design-env.sh"
  : > "${dir}/rtl/${design}.v"
  : > "${dir}/layout/${design}.def"
  : > "${dir}/flow/sta-${design}.json"
  local tag
  for tag in pinned venv path; do
    printf '#!/bin/sh\necho "STUB-%s"\nexit 0\n' "${tag}" > "${dir}/bin/klt-${tag}"
    chmod +x "${dir}/bin/klt-${tag}"
  done
  cp "${dir}/bin/klt-venv" "${dir}/.venv/bin/klt"
  cp "${dir}/bin/klt-path" "${dir}/bin/klt"
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "${SANDBOX}"' EXIT
make_sandbox "${SANDBOX}/repo"
R="${SANDBOX}/repo"

export HELPER

echo "-- design_env_require_design --"

expect_helper "explicit \$DESIGN wins over the rtl/ stem" \
  0 "DESIGN=override KLT=" design_env_require_design \
  REPO_ROOT="${R}" DESIGN=override

expect_helper "one rtl/*.v resolves DESIGN to its stem" \
  0 "DESIGN=widget KLT=" design_env_require_design \
  REPO_ROOT="${R}"

mkdir -p "${SANDBOX}/empty/rtl"
expect_helper "zero rtl/*.v is fatal with exit 2" \
  2 "" design_env_require_design \
  REPO_ROOT="${SANDBOX}/empty"

mkdir -p "${SANDBOX}/several/rtl"
: > "${SANDBOX}/several/rtl/a.v"; : > "${SANDBOX}/several/rtl/b.v"
expect_helper "several rtl/*.v is fatal with exit 2" \
  2 "" design_env_require_design \
  REPO_ROOT="${SANDBOX}/several"

expect_helper "missing \$REPO_ROOT is fatal with exit 2" \
  2 "" design_env_require_design \
  REPO_ROOT=

echo "-- design_env_require_klt --"

expect_helper "\$KLT wins over .venv/bin/klt and PATH" \
  0 "DESIGN= KLT=${R}/bin/klt-pinned" design_env_require_klt \
  REPO_ROOT="${R}" KLT="${R}/bin/klt-pinned" PATH="${R}/bin:/usr/bin:/bin"

expect_helper ".venv/bin/klt wins over PATH when \$KLT is unset" \
  0 "DESIGN= KLT=${R}/.venv/bin/klt" design_env_require_klt \
  REPO_ROOT="${R}" PATH="${R}/bin:/usr/bin:/bin"

mv "${R}/.venv/bin/klt" "${R}/.venv/bin/klt.disabled"
expect_helper "PATH klt is the last resort" \
  0 "DESIGN= KLT=${R}/bin/klt" design_env_require_klt \
  REPO_ROOT="${R}" PATH="${R}/bin:/usr/bin:/bin"

expect_helper "no klt anywhere is fatal with exit 1" \
  1 "" design_env_require_klt \
  REPO_ROOT="${R}" PATH="/usr/bin:/bin"
mv "${R}/.venv/bin/klt.disabled" "${R}/.venv/bin/klt"

echo "-- the three runners agree (the drift issue #337 found) --"

# All three answer an unresolvable design with the SAME exit code. Before the
# consolidation, run-gate-level-sim.sh said 1 while the other two said 2.
mkdir -p "${SANDBOX}/nodesign/rtl" "${SANDBOX}/nodesign/scripts"
cp "${HELPER}" "${SANDBOX}/nodesign/scripts/design-env.sh"
for runner in flow/run-par.sh flow/run-sta-corner-sweep.sh \
              verification/gate-level/run-gate-level-sim.sh; do
  env -u DESIGN -u KLT REPO_ROOT="${SANDBOX}/nodesign" PATH="/usr/bin:/bin" \
    "${REPO_ROOT}/${runner}" scratch >/dev/null 2>&1
  rc=$?
  if [ "${rc}" -eq 2 ]; then
    ok "${runner}: unresolvable design -> exit 2"
  else
    no "${runner}: unresolvable design -> exit 2" "got exit ${rc}"
  fi
done

# Each runner refuses clearly when the helper does not travel with it, rather
# than failing with a bare bash "No such file or directory".
mkdir -p "${SANDBOX}/nohelper/rtl"
: > "${SANDBOX}/nohelper/rtl/widget.v"
for runner in flow/run-par.sh flow/run-sta-corner-sweep.sh \
              verification/gate-level/run-gate-level-sim.sh; do
  out="$(env -u DESIGN -u KLT REPO_ROOT="${SANDBOX}/nohelper" PATH="/usr/bin:/bin" \
    "${REPO_ROOT}/${runner}" scratch 2>&1)"
  rc=$?
  if [ "${rc}" -eq 2 ] && printf '%s' "${out}" | grep -q 'must travel with this script'; then
    ok "${runner}: missing helper -> exit 2 and says why"
  else
    no "${runner}: missing helper -> exit 2 and says why" "exit ${rc}: ${out}"
  fi
done

# `--help` must not require a resolvable klt: the STA sweep's own documented
# smoke check is `./flow/run-sta-corner-sweep.sh --help`, and it has to work on
# a host with no klt installed. This is why the helper exposes functions rather
# than resolving at source time.
out="$(env -u KLT PATH="/usr/bin:/bin" "${REPO_ROOT}/flow/run-sta-corner-sweep.sh" --help 2>&1)"
rc=$?
if [ "${rc}" -eq 0 ] && printf '%s' "${out}" | grep -q 'run-sta-corner-sweep.sh'; then
  ok "run-sta-corner-sweep.sh --help works with no klt present"
else
  no "run-sta-corner-sweep.sh --help works with no klt present" "exit ${rc}"
fi

# The gate-level Leg 1 wrapper's --help slices its header by sentinel (up to
# `set -uo pipefail`), not by a hardcoded line range, so header edits cannot
# silently truncate it again (issue #407). Assert the slice reaches the END of
# the header, not just line 2: the Leg 2 pointer is its final block.
out="$(env -u KLT PATH="/usr/bin:/bin" \
  "${REPO_ROOT}/verification/gate-level/run-gate-level-sim.sh" --help 2>&1)"
rc=$?
if [ "${rc}" -eq 0 ] && printf '%s' "${out}" | grep -q 'run-gate-level-sim.sh' \
  && printf '%s' "${out}" | grep -q 'current evidence'; then
  ok "run-gate-level-sim.sh --help prints its full header with no klt present"
else
  no "run-gate-level-sim.sh --help prints its full header with no klt present" "exit ${rc}"
fi

echo
printf '%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
