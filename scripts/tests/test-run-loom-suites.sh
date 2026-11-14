#!/usr/bin/env bash
# Test suite for scripts/run-loom-suites.sh (issue #338).
#
# Usage: ./scripts/tests/test-run-loom-suites.sh
#
# The suite-classification algorithm this exercises used to exist only as two
# near-identical heredocs inside `.github/workflows/ci.yml`, which made it the
# one piece of classification logic in the repo with no self-test -- while being
# the logic that decides whether the `guard-hooks` and `merge-pr-suites` jobs
# actually ran anything. #338 extracted it to a repo-owned script; this is the
# self-test that makes the extraction worth having, in the same spirit as
# `verification/test_check_records.py` and `verification/test_check_pins.py`.
#
# Everything runs in a `mktemp -d` sandbox with synthetic suites and synthetic
# manifests -- no vendored Loom suite is executed, nothing touches the real
# repo, and the whole suite finishes in well under a second.
#
# What is pinned here, and why each one matters:
#
#   A. the happy path: every suite runs, `::group::` framing, exit 0
#   B. THE #107 INVARIANT: a suite failing in the middle must not stop the
#      ones after it -- that is the `set +e` override's entire purpose, and the
#      blind spot (a false "did not run" pass) the two jobs exist to close
#   C. skip classification by the upstream manifest, with and without
#      --manifest-prefix, including that a prefix confines matching
#   D. skip classification by the repo-owned consumer supplement (#185)
#   E. reasons printed verbatim, including `#NNNN` in the reason text, and the
#      `<no reason given>` fallback
#   F. the four fail-closed exits a green build can never exercise: either
#      manifest missing, the glob matching nothing, and every suite skipped
#   G. argument validation
#
# Exit 0 = all pass, 1 = one or more failures.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run-loom-suites.sh"

PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

ok()  { PASS=$((PASS + 1)); printf "  ${GREEN}✓${NC} %s\n" "$1"; }
bad() { FAIL=$((FAIL + 1)); printf "  ${RED}✗${NC} %s\n" "$1"; [[ -n "${2:-}" ]] && printf "      %s\n" "$2"; }

assert_eq() { # <label> <expected> <actual>
    if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi
}
assert_contains() { # <label> <needle> <haystack>
    if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain [$2], got [$3]"; fi
}
assert_not_contains() { # <label> <needle> <haystack>
    if [[ "$3" != *"$2"* ]]; then ok "$1"; else bad "$1" "expected NOT to contain [$2], got [$3]"; fi
}

[[ -x "$RUNNER" ]] || { printf "${RED}FATAL${NC}: %s is missing or not executable\n" "$RUNNER"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# ---------------------------------------------------------------------------
# Sandbox: a fake consumer repo with a fake suite directory and both manifests.
# ---------------------------------------------------------------------------
SANDBOX="$TMPROOT/repo"
mkdir -p "$SANDBOX/suites"

make_suite() { # <name> <exit-code> [marker]
    local name=$1 rc=$2 marker=${3:-}
    cat >"$SANDBOX/suites/$name" <<EOF
#!/usr/bin/env bash
echo "output of $name"
${marker:+touch "\$MARKER_DIR/$marker"}
exit $rc
EOF
    chmod +x "$SANDBOX/suites/$name"
}

# Glob order is lexical, so these names fix the execution order:
#   test-a (pass) -> test-b (FAIL) -> test-c (pass) -> test-d (pass)
make_suite test-a.sh 0 ran-a
make_suite test-b.sh 1 ran-b
make_suite test-c.sh 0 ran-c
make_suite test-d.sh 0 ran-d

cat >"$SANDBOX/excluded.txt" <<'EOF'
# Upstream exclusion manifest (synthetic). Comment lines and blanks are ignored.

test-c.sh  Needs a built loom-daemon; wired in the "Native Port Suites" job (#7952).
other/path/test-d.sh  A prefixed entry under a DIFFERENT prefix.
prefix/dir/test-a.sh  Prefixed entry, reason mentions #4455 and #185.
prefix/dir/test-noreason.sh
EOF

cat >"$SANDBOX/consumer.txt" <<'EOF'
# Repo-owned consumer carve-out supplement (synthetic, #185).

test-d.sh  Consumer hook/suite version skew (#185); retire when a resync fixes it.
EOF

# Shared invocation. Runs from inside the sandbox so the glob is relative, the
# way the CI jobs run it from the repo root.
run_runner() { # [extra args...]
    (
        cd "$SANDBOX" || exit 99
        MARKER_DIR="$MARKER_DIR" "$RUNNER" \
            --glob 'suites/test-*.sh' \
            --label 'suites/test-*.sh' \
            --missing-manifest-note 'cannot tell which suites are daemon-backed' \
            --skip-note 'daemon-backed or consumer carve-out, see #185' \
            --empty-note 'every one is in a skip list' \
            --excluded-manifest excluded.txt \
            --consumer-skips consumer.txt \
            "$@" 2>&1
    )
}

# Each phase gets a FRESH marker directory rather than a cleared one, so no
# phase can be polluted by a previous phase's markers and nothing here has to
# delete a path held in a variable.
MARKER_SEQ=0
fresh_markers() {
    MARKER_SEQ=$((MARKER_SEQ + 1))
    MARKER_DIR="$TMPROOT/markers-$MARKER_SEQ"
    mkdir -p "$MARKER_DIR"
}

# Markers are fixed alphanumeric names created by make_suite, so a glob is both
# safe and sufficient -- no `ls` output parsing.
marker_list() {
    local m out=
    for m in "$MARKER_DIR"/*; do
        [[ -e "$m" ]] || continue
        out+="${m##*/} "
    done
    printf '%s' "$out"
}
assert_no_markers() { # <label>
    if [[ -z "$(marker_list)" ]]; then ok "$1"; else bad "$1" "markers: $(marker_list)"; fi
}

fresh_markers
export MARKER_DIR

# ---------------------------------------------------------------------------
echo "(A) happy path: no skips, every suite runs, exit 0"
# ---------------------------------------------------------------------------
fresh_markers
printf '# empty\n' >"$SANDBOX/empty-excluded.txt"
printf '# empty\n' >"$SANDBOX/empty-consumer.txt"
make_suite test-b.sh 0 ran-b   # temporarily make the failing suite pass
out=$(run_runner --excluded-manifest empty-excluded.txt --consumer-skips empty-consumer.txt)
rc=$?
assert_eq "(a) exit 0 when every suite passes" "0" "$rc"
assert_contains "(b) summary reports 4 ran, 0 skipped" \
    "Summary: ran 4 suite(s), skipped 0 suite(s)" "$out"
assert_contains "(c) ::group:: framing is emitted per suite" "::group::suites/test-a.sh" "$out"
assert_contains "(d) ::endgroup:: framing is emitted" "::endgroup::" "$out"
assert_contains "(e) suite stdout is relayed" "output of test-a.sh" "$out"
assert_not_contains "(f) no SKIPPED line" "SKIPPED" "$out"
assert_not_contains "(g) no ::error:: line" "::error::" "$out"
for m in ran-a ran-b ran-c ran-d; do
    if [[ -f "$MARKER_DIR/$m" ]]; then ok "(h) $m executed"; else bad "(h) $m executed" "marker absent"; fi
done
make_suite test-b.sh 1 ran-b   # restore the failing suite

# ---------------------------------------------------------------------------
echo "(B) the #107 invariant: a mid-list failure must not stop later suites"
# ---------------------------------------------------------------------------
fresh_markers
out=$(run_runner --excluded-manifest empty-excluded.txt --consumer-skips empty-consumer.txt)
rc=$?
assert_eq "(a) exit 1 when a suite fails" "1" "$rc"
assert_contains "(b) the failing suite is named with its rc" \
    "FAILED: suites/test-b.sh (exit 1)" "$out"
if [[ -f "$MARKER_DIR/ran-c" && -f "$MARKER_DIR/ran-d" ]]; then
    ok "(c) suites AFTER the failing one still ran (set +e override holds)"
else
    bad "(c) suites AFTER the failing one still ran (set +e override holds)" \
        "ran-c/ran-d markers: $(marker_list)"
fi
assert_contains "(d) they are still counted as ran, not silently dropped" \
    "Summary: ran 4 suite(s), skipped 0 suite(s)" "$out"
assert_not_contains "(e) a passing suite is not reported FAILED" \
    "FAILED: suites/test-c.sh" "$out"

# ---------------------------------------------------------------------------
echo "(C) skip classification via the upstream exclusion manifest"
# ---------------------------------------------------------------------------
fresh_markers
out=$(run_runner)
rc=$?
assert_eq "(a) exit 1 (test-b still fails) with skips applied" "1" "$rc"
assert_contains "(b) bare-basename entry skips the suite" \
    "SKIPPED (listed in excluded.txt): test-c.sh --" "$out"
if [[ ! -f "$MARKER_DIR/ran-c" ]]; then ok "(c) a skipped suite is NOT executed"; else
    bad "(c) a skipped suite is NOT executed" "marker ran-c exists"; fi
assert_contains "(d) summary counts 2 ran / 2 skipped" \
    "Summary: ran 2 suite(s), skipped 2 suite(s)" "$out"
assert_contains "(e) skip-note is rendered in the trailing list" \
    "  not run (daemon-backed or consumer carve-out, see #185): test-c.sh" "$out"

echo "(C2) --manifest-prefix confines which manifest entries can match"
fresh_markers
out=$(run_runner --manifest-prefix 'prefix/dir/')
rc=$?
assert_contains "(a) a prefixed entry skips by basename" \
    "SKIPPED (listed in excluded.txt): test-a.sh --" "$out"
assert_not_contains "(b) a bare-basename entry does NOT match under a prefix" \
    "SKIPPED (listed in excluded.txt): test-c.sh" "$out"
assert_not_contains "(c) an entry under a different prefix does NOT match" \
    "SKIPPED (listed in excluded.txt): test-d.sh" "$out"
if [[ -f "$MARKER_DIR/ran-c" ]]; then ok "(d) the unprefixed suite therefore runs"; else
    bad "(d) the unprefixed suite therefore runs" "marker ran-c absent"; fi

# ---------------------------------------------------------------------------
echo "(D) skip classification via the repo-owned consumer supplement (#185)"
# ---------------------------------------------------------------------------
fresh_markers
out=$(run_runner)
assert_contains "(a) consumer-skips entry skips the suite, naming that file" \
    "SKIPPED (listed in consumer.txt): test-d.sh --" "$out"
if [[ ! -f "$MARKER_DIR/ran-d" ]]; then ok "(b) it is not executed"; else
    bad "(b) it is not executed" "marker ran-d exists"; fi

# ---------------------------------------------------------------------------
echo "(E) reasons are printed verbatim from the manifest"
# ---------------------------------------------------------------------------
out=$(run_runner)
assert_contains "(a) upstream reason kept verbatim, including its #NNNN" \
    'test-c.sh -- Needs a built loom-daemon; wired in the "Native Port Suites" job (#7952).' "$out"
assert_contains "(b) consumer reason kept verbatim, including its #NNNN" \
    'test-d.sh -- Consumer hook/suite version skew (#185); retire when a resync fixes it.' "$out"
out=$(run_runner --manifest-prefix 'prefix/dir/')
assert_contains "(c) a prefixed reason with two #NNNN survives comment-stripping" \
    'test-a.sh -- Prefixed entry, reason mentions #4455 and #185.' "$out"

echo "(E2) an entry with no reason falls back to <no reason given>"
make_suite test-noreason.sh 0 ran-noreason
out=$(run_runner --manifest-prefix 'prefix/dir/')
assert_contains "(a) <no reason given> placeholder" \
    "SKIPPED (listed in excluded.txt): test-noreason.sh -- <no reason given>" "$out"
rm -f "$SANDBOX/suites/test-noreason.sh"

# ---------------------------------------------------------------------------
echo "(F) fail-closed paths a green build can never exercise"
# ---------------------------------------------------------------------------
out=$(run_runner --excluded-manifest does-not-exist.txt)
rc=$?
assert_eq "(a) missing upstream manifest exits 1" "1" "$rc"
assert_contains "(b) ...with an ::error:: naming the file and the note" \
    "::error::missing does-not-exist.txt -- cannot tell which suites are daemon-backed" "$out"

out=$(run_runner --consumer-skips does-not-exist.txt)
rc=$?
assert_eq "(c) missing consumer supplement exits 1" "1" "$rc"
assert_contains "(d) ...with its own ::error::" \
    "::error::missing does-not-exist.txt -- cannot tell which suites are carved out for this repo" "$out"

out=$(run_runner --glob 'suites/no-such-prefix-*.sh')
rc=$?
assert_eq "(e) a glob matching nothing exits 1 rather than running a literal" "1" "$rc"
assert_contains "(f) ...with an ::error:: naming the glob" \
    "::error::no file matched suites/no-such-prefix-*.sh" "$out"

echo "(F2) every suite skipped must fail, never go green having run nothing"
cat >"$SANDBOX/all-skipped.txt" <<'EOF'
test-a.sh  skipped for this test
test-b.sh  skipped for this test
test-c.sh  skipped for this test
test-d.sh  skipped for this test
EOF
fresh_markers
out=$(run_runner --excluded-manifest all-skipped.txt)
rc=$?
assert_eq "(a) exits 1 with nothing run" "1" "$rc"
assert_contains "(b) ::error:: names the label and the empty-note" \
    "::error::no suites/test-*.sh suite was run -- every one is in a skip list" "$out"
assert_contains "(c) the summary still reports 0 ran / 4 skipped first" \
    "Summary: ran 0 suite(s), skipped 4 suite(s)" "$out"
assert_no_markers "(d) no suite was executed"

# ---------------------------------------------------------------------------
echo "(G) --dry-run classifies identically without executing anything"
# ---------------------------------------------------------------------------
fresh_markers
dry=$(run_runner --dry-run)
dry_rc=$?
assert_eq "(a) exit 0 -- no suite ran, so no suite could fail" "0" "$dry_rc"
assert_no_markers "(b) no suite was executed"
assert_contains "(c) the same summary counts as a real run" \
    "Summary: ran 2 suite(s), skipped 2 suite(s)" "$dry"
assert_not_contains "(d) no suite output is relayed" "output of test-a.sh" "$dry"
# The classification half must match a real run line-for-line -- that property
# is what makes --dry-run usable as a before/after comparison against the old
# inline runners.
fresh_markers
real=$(run_runner)
real_class=$(printf '%s\n' "$real" | grep -E '^(SKIPPED|Summary:|  not run)' || true)
dry_class=$(printf '%s\n' "$dry" | grep -E '^(SKIPPED|Summary:|  not run)' || true)
assert_eq "(e) dry-run classification is byte-identical to a real run" "$real_class" "$dry_class"

# ---------------------------------------------------------------------------
echo "(H) argument validation"
# ---------------------------------------------------------------------------
out=$("$RUNNER" --label x --missing-manifest-note x --skip-note x --empty-note x 2>&1)
rc=$?
assert_eq "(a) a missing --glob exits 2" "2" "$rc"
assert_contains "(b) ...naming the flag" "--glob is required" "$out"

out=$("$RUNNER" --glob 'x' --missing-manifest-note x --skip-note x --empty-note x 2>&1)
assert_contains "(c) a missing --label is reported" "--label is required" "$out"

out=$("$RUNNER" --glob 'x' --label x --skip-note x --empty-note x 2>&1)
assert_contains "(d) a missing --missing-manifest-note is reported" \
    "--missing-manifest-note is required" "$out"

out=$("$RUNNER" --glob 'x' --label x --missing-manifest-note x --empty-note x 2>&1)
assert_contains "(e) a missing --skip-note is reported" "--skip-note is required" "$out"

out=$("$RUNNER" --glob 'x' --label x --missing-manifest-note x --skip-note x 2>&1)
assert_contains "(f) a missing --empty-note is reported" "--empty-note is required" "$out"

out=$("$RUNNER" --nonsense 2>&1)
rc=$?
assert_eq "(g) an unknown flag exits 2" "2" "$rc"
assert_contains "(h) ...naming it" "unknown argument: --nonsense" "$out"

out=$("$RUNNER" --glob 2>&1)
rc=$?
assert_eq "(i) a flag with no value exits 2" "2" "$rc"
assert_contains "(j) ...saying so" "--glob requires a value" "$out"

out=$("$RUNNER" --help 2>&1)
rc=$?
assert_eq "(k) --help exits 0" "0" "$rc"
assert_contains "(l) --help prints usage" "Usage: scripts/run-loom-suites.sh" "$out"

# ---------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0
