#!/usr/bin/env bash
# test-dep-recheck-prior-marker.sh — the prior-marker read contract behind
# curator.md's two idempotency windows (sky130-modexp #154).
#
# WHAT THIS SUITE IS EVIDENCE FOR
#
# Issue #12 in this repo collected 44 `curator:operator-premise-recheck`
# heartbeat comments over a month, 27 of the 43 gaps under the 24h idempotency
# window, minimum gap 23 minutes — every one reporting the same conclusion
# hash. `dep-recheck-fingerprint.sh decide` was NOT wrong: re-run on 2026-09-27
# with the true prior marker it returns `ACTION=skip CLAIM=false`.
#
# The wrong value was decide's INPUT. 19 of the 22 post-2026-09-11 spam
# comments name the same predecessor — "2026-09-10 12:46 UTC" — which is the
# 30th comment on that thread, i.e. the last entry on page one of
# `GET /issues/{n}/comments` at its default `per_page=30`. Curator's prior read
# was a single unpaginated page, so a marker on page 2 was invisible and the
# age arithmetic reported hundreds of hours.
#
# Case 1 below is that exact scenario, replayed from a fixture: a thread whose
# freshest marker sits past a 30-comment page boundary. It fails against a
# single-page read and passes only against a complete one. Cases 2-4 pin the
# fail-closed contract that makes a short read un-postable rather than
# indistinguishable from "no prior marker".
#
# HERMETIC: no forge, no network, no `loom-daemon`. Every case drives the
# subject through `--stdin` with a generated payload. (The companion suite
# test-dep-recheck-heartbeat-race.sh drives the real `decide` end-to-end and
# therefore needs a built binary; this one deliberately does not, so it can be
# wired into this repo's own CI.)
#
# Usage:
#   bash .loom/scripts/tests/test-dep-recheck-prior-marker.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SUBJECT="$SCRIPTS_DIR/dep-recheck-prior-marker.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

passed=0
failed=0
pass() { echo -e "${GREEN}\xe2\x9c\x93${NC} $1"; passed=$((passed + 1)); }
fail() { echo -e "${RED}\xe2\x9c\x97${NC} $1"; failed=$((failed + 1)); }

[[ -x "$SUBJECT" ]] || { echo "FATAL: subject not executable: $SUBJECT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dep-recheck-prior-marker-test-XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

MARKER="curator:operator-premise-recheck"
HASH="94285bc12d499dbb"     # the real #12 conclusion hash
OTHER_HASH="3239fee217fc13fb"
NOW=1790510400              # 2026-09-27T12:00:00Z, fixed so ages are exact

# ---------------------------------------------------------------------------
# Fixture builder. Produces a comments array shaped like the REST response:
# `created_at` + `body`, oldest first. `mk_comment <iso> <body>`.
# ---------------------------------------------------------------------------
mk_comment() {
    jq -n --arg at "$1" --arg body "$2" '{created_at: $at, body: $body}'
}

marker_body() {
    printf 'Operator-parked, premise possibly stale: heartbeat re-check.\n\n<!-- %s:%s -->' "$MARKER" "$1"
}

# The #12 thread shape, reduced to what matters: 40 comments, a marker at
# index 29 (the last entry of a 30-item first page) and a FRESHER marker at
# index 39 (page two).
build_thread() {
    local out="$1" i
    {
        echo '['
        for i in $(seq 0 39); do
            [[ "$i" -eq 0 ]] || echo ','
            local at
            at="$(printf '2026-09-%02dT12:46:26Z' $(( 1 + i / 2 )) )"
            if [[ "$i" -eq 29 ]]; then
                mk_comment "2026-09-10T12:46:26Z" "$(marker_body "$HASH")"
            elif [[ "$i" -eq 39 ]]; then
                mk_comment "2026-09-27T06:46:29Z" "$(marker_body "$HASH")"
            else
                mk_comment "$at" "ordinary comment $i"
            fi
        done
        echo ']'
    } >"$out"
}

THREAD="$WORK/thread.json"
build_thread "$THREAD"
PAGE1="$WORK/page1.json"
jq '.[0:30]' "$THREAD" >"$PAGE1"

read_keys() { sed -n 's/^\([A-Z_]*\)=\(.*\)$/\1=\2/p'; }
get() { sed -n "s/^$1=\(.*\)$/\1/p" "$2"; }

# ---------------------------------------------------------------------------
# Case 1 — THE #12 REGRESSION. A complete read must resolve the marker past
# the 30-comment page boundary, not the page-1 one.
# ---------------------------------------------------------------------------
OUT="$WORK/out.txt"
"$SUBJECT" --marker "$MARKER" --stdin --total-comments 40 --now "$NOW" <"$THREAD" >"$OUT" 2>&1
rc=$?
if [[ "$rc" -eq 0 && "$(get PRIOR_AT "$OUT")" == "2026-09-27T06:46:29Z" ]]; then
    pass "complete read resolves the FRESHEST marker (page 2), not the page-1 one"
else
    fail "complete read picked PRIOR_AT=$(get PRIOR_AT "$OUT") rc=$rc (want 2026-09-27T06:46:29Z, rc 0)"
    cat "$OUT"
fi

if [[ "$(get PRIOR_AGE_H "$OUT")" == "5" ]]; then
    pass "PRIOR_AGE_H is computed from the freshest marker (5h, inside the 24h window)"
else
    fail "PRIOR_AGE_H=$(get PRIOR_AGE_H "$OUT") (want 5 — the age of the 06:46 marker at the fixed NOW)"
fi

if [[ "$(get MARKER_COUNT "$OUT")" == "2" && "$(get COMMENTS_READ "$OUT")" == "40" ]]; then
    pass "read reports its own completeness (COMMENTS_READ=40, MARKER_COUNT=2)"
else
    fail "COMMENTS_READ=$(get COMMENTS_READ "$OUT") MARKER_COUNT=$(get MARKER_COUNT "$OUT") (want 40 / 2)"
fi

# ---------------------------------------------------------------------------
# Case 2 — the page-1-only read (the live bug) must FAIL CLOSED, not answer
# with the stale marker. This is the assertion that would have caught #12: the
# old inline snippet's answer here was PRIOR_AT=2026-09-10, age 412h ->
# decide -> heartbeat -> post.
# ---------------------------------------------------------------------------
"$SUBJECT" --marker "$MARKER" --stdin --total-comments 40 --now "$NOW" <"$PAGE1" >"$OUT" 2>&1
rc=$?
if [[ "$rc" -eq 1 && "$(get READ_OK "$OUT")" == "false" && "$(get READ_ERROR "$OUT")" == "incomplete-read" ]]; then
    pass "a 30-of-40 page-1 read fails closed (READ_OK=false, READ_ERROR=incomplete-read, exit 1)"
else
    fail "page-1 read: rc=$rc READ_OK=$(get READ_OK "$OUT") READ_ERROR=$(get READ_ERROR "$OUT") (want 1/false/incomplete-read)"
    cat "$OUT"
fi

if [[ -z "$(get PRIOR_HASH "$OUT")" && -z "$(get PRIOR_AT "$OUT")" && -z "$(get PRIOR_AGE_H "$OUT")" ]]; then
    pass "a failed read emits NO prior values — it cannot be mistaken for a fresh answer"
else
    fail "failed read leaked PRIOR_HASH=$(get PRIOR_HASH "$OUT") PRIOR_AT=$(get PRIOR_AT "$OUT") PRIOR_AGE_H=$(get PRIOR_AGE_H "$OUT")"
fi

# A truncated read must NOT be confusable with "no marker at all" — the shape
# that makes `decide` answer `comment` (first-ever check). Assert the two
# outcomes are distinguishable by READ_OK alone.
NOMARKER="$WORK/nomarker.json"
jq '[.[] | select((.body | test("curator:")) | not)]' "$THREAD" >"$NOMARKER"
NOMARKER_N="$(jq 'length' "$NOMARKER")"
"$SUBJECT" --marker "$MARKER" --stdin --total-comments "$NOMARKER_N" --now "$NOW" <"$NOMARKER" >"$OUT" 2>&1
rc=$?
if [[ "$rc" -eq 0 && "$(get READ_OK "$OUT")" == "true" && "$(get MARKER_COUNT "$OUT")" == "0" && -z "$(get PRIOR_HASH "$OUT")" ]]; then
    pass "a genuinely marker-free thread reports READ_OK=true + MARKER_COUNT=0 (the real first-check signal)"
else
    fail "marker-free thread: rc=$rc READ_OK=$(get READ_OK "$OUT") MARKER_COUNT=$(get MARKER_COUNT "$OUT")"
    cat "$OUT"
fi

# ---------------------------------------------------------------------------
# Case 2b — the NEWEST-window sufficiency proof. A read holding only the newest
# slice of a long thread is sufficient WHEN a marker is inside it (anything
# outside a newest-N window is necessarily older), and insufficient when it is
# not (an older marker may sit just outside). This is what lets the GraphQL
# path answer from `comments(last: 100)` on a 500-comment thread without
# reopening the #12 hole.
# ---------------------------------------------------------------------------
NEWEST="$WORK/newest.json"
jq '.[30:40]' "$THREAD" >"$NEWEST"          # holds the 2026-09-27 marker
"$SUBJECT" --marker "$MARKER" --stdin --total-comments 40 --newest-window --now "$NOW" <"$NEWEST" >"$OUT" 2>&1
rc=$?
if [[ "$rc" -eq 0 && "$(get PRIOR_AT "$OUT")" == "2026-09-27T06:46:29Z" ]]; then
    pass "a newest-window read WITH a marker in it answers (10 of 40 comments, freshest marker present)"
else
    fail "newest-window read: rc=$rc PRIOR_AT=$(get PRIOR_AT "$OUT")"
    cat "$OUT"
fi

jq '[.[30:39][] | select((.body | test("curator:")) | not)]' "$THREAD" >"$NEWEST"
"$SUBJECT" --marker "$MARKER" --stdin --total-comments 40 --newest-window --now "$NOW" <"$NEWEST" >"$OUT" 2>&1
rc=$?
if [[ "$rc" -eq 1 && "$(get READ_ERROR "$OUT")" == "incomplete-read" ]]; then
    pass "a newest-window read with NO marker in it still fails closed (an older one may be outside)"
else
    fail "markerless newest-window read: rc=$rc READ_ERROR=$(get READ_ERROR "$OUT") (want 1/incomplete-read)"
    cat "$OUT"
fi

# The same short payload WITHOUT --newest-window is an arbitrary slice and must
# fail closed even though it does contain the freshest marker: nothing proves
# there is not a newer one outside it.
jq '.[30:40]' "$THREAD" >"$NEWEST"
"$SUBJECT" --marker "$MARKER" --stdin --total-comments 40 --now "$NOW" <"$NEWEST" >"$OUT" 2>&1
if [[ "$?" -eq 1 && "$(get READ_ERROR "$OUT")" == "incomplete-read" ]]; then
    pass "an arbitrary short slice fails closed even when it happens to hold the freshest marker"
else
    fail "arbitrary short slice was accepted: READ_ERROR=$(get READ_ERROR "$OUT")"
fi

# READ_VIA is reported so a caller (or a log) can tell which budget answered.
"$SUBJECT" --marker "$MARKER" --stdin --total-comments 40 --now "$NOW" <"$THREAD" >"$OUT" 2>&1
[[ "$(get READ_VIA "$OUT")" == "stdin" ]] && pass "READ_VIA names the path that answered" \
    || fail "READ_VIA=$(get READ_VIA "$OUT") (want stdin)"

# ---------------------------------------------------------------------------
# Case 3 — freshest-by-timestamp, not by array position. A forge that returns
# comments in any other order must not change the answer.
# ---------------------------------------------------------------------------
SHUFFLED="$WORK/shuffled.json"
jq 'reverse' "$THREAD" >"$SHUFFLED"
"$SUBJECT" --marker "$MARKER" --stdin --total-comments 40 --now "$NOW" <"$SHUFFLED" >"$OUT" 2>&1
if [[ "$(get PRIOR_AT "$OUT")" == "2026-09-27T06:46:29Z" ]]; then
    pass "selection is by max(createdAt), not array position (reversed payload, same answer)"
else
    fail "reversed payload gave PRIOR_AT=$(get PRIOR_AT "$OUT") (want 2026-09-27T06:46:29Z)"
fi

# ---------------------------------------------------------------------------
# Case 4 — unreadable payloads fail closed too. A read that errors is not an
# empty thread; this is the second way #12's shape can recur (GraphQL
# exhaustion returning an error body that jq parses as nothing useful).
# ---------------------------------------------------------------------------
printf '%s' '{"message":"API rate limit exceeded"}' >"$WORK/error.json"
"$SUBJECT" --marker "$MARKER" --stdin --now "$NOW" <"$WORK/error.json" >"$OUT" 2>&1
rc=$?
if [[ "$rc" -eq 1 && "$(get READ_ERROR "$OUT")" == "unreadable" ]]; then
    pass "a rate-limit error body fails closed as unreadable (not as an empty thread)"
else
    fail "error body: rc=$rc READ_ERROR=$(get READ_ERROR "$OUT") (want 1/unreadable)"
    cat "$OUT"
fi

printf '%s' 'not json at all' >"$WORK/garbage.json"
"$SUBJECT" --marker "$MARKER" --stdin --now "$NOW" <"$WORK/garbage.json" >"$OUT" 2>&1
if [[ "$?" -eq 1 && "$(get READ_OK "$OUT")" == "false" ]]; then
    pass "a non-JSON payload fails closed"
else
    fail "non-JSON payload did not fail closed"
fi

# ---------------------------------------------------------------------------
# Case 5 — marker discrimination. `curator:dep-recheck` and
# `curator:operator-premise-recheck` must stay separable (curator.md requires
# it so a later pass can tell which check produced which comment), and a
# prefix must not cross-match a longer marker name.
# ---------------------------------------------------------------------------
MIXED="$WORK/mixed.json"
{
    echo '['
    mk_comment "2026-09-20T00:00:00Z" "$(printf 'dep re-check\n\n<!-- curator:dep-recheck:%s -->' "$OTHER_HASH")"
    echo ','
    mk_comment "2026-09-21T00:00:00Z" "$(marker_body "$HASH")"
    echo ']'
} >"$MIXED"

"$SUBJECT" --marker "$MARKER" --stdin --total-comments 2 --now "$NOW" <"$MIXED" >"$OUT" 2>&1
if [[ "$(get PRIOR_HASH "$OUT")" == "$HASH" && "$(get MARKER_COUNT "$OUT")" == "1" ]]; then
    pass "operator-premise marker read ignores curator:dep-recheck comments"
else
    fail "operator-premise read saw PRIOR_HASH=$(get PRIOR_HASH "$OUT") MARKER_COUNT=$(get MARKER_COUNT "$OUT")"
fi

"$SUBJECT" --marker "curator:dep-recheck" --stdin --total-comments 2 --now "$NOW" <"$MIXED" >"$OUT" 2>&1
if [[ "$(get PRIOR_HASH "$OUT")" == "$OTHER_HASH" && "$(get MARKER_COUNT "$OUT")" == "1" ]]; then
    pass "dep-recheck marker read ignores operator-premise comments (no prefix cross-match)"
else
    fail "dep-recheck read saw PRIOR_HASH=$(get PRIOR_HASH "$OUT") MARKER_COUNT=$(get MARKER_COUNT "$OUT")"
fi

# ---------------------------------------------------------------------------
# Case 6 — eval-safety. The output is `eval`ed by curator.md, so a comment
# body full of shell metacharacters must not be able to reach a caller's
# shell. Nothing forge-authored is emitted: the hash is [0-9a-f]+ and the
# timestamp is regex-validated.
# ---------------------------------------------------------------------------
HOSTILE="$WORK/hostile.json"
{
    echo '['
    mk_comment "2026-09-21T00:00:00Z" "$(printf 'x`touch %s/pwned`$(touch %s/pwned2); rm -rf /\n\n<!-- %s:%s -->' "$WORK" "$WORK" "$MARKER" "$HASH")"
    echo ']'
} >"$HOSTILE"
eval "$("$SUBJECT" --marker "$MARKER" --stdin --total-comments 1 --now "$NOW" <"$HOSTILE" | read_keys)"
if [[ ! -e "$WORK/pwned" && ! -e "$WORK/pwned2" && "${PRIOR_HASH:-}" == "$HASH" ]]; then
    pass "eval of the output is inert against a hostile comment body"
else
    fail "eval-safety breach (pwned=$([[ -e "$WORK/pwned" ]] && echo yes || echo no), PRIOR_HASH=${PRIOR_HASH:-})"
fi

# A body whose "timestamp" is junk must fail closed rather than emit it.
BADTS="$WORK/badts.json"
jq -n --arg m "$MARKER" --arg h "$HASH" \
    '[{created_at: "not-a-timestamp; echo hi", body: ("x <!-- " + $m + ":" + $h + " -->")}]' >"$BADTS"
"$SUBJECT" --marker "$MARKER" --stdin --total-comments 1 --now "$NOW" <"$BADTS" >"$OUT" 2>&1
if [[ "$?" -eq 1 && "$(get READ_ERROR "$OUT")" == "bad-timestamp" ]]; then
    pass "an unparseable createdAt fails closed as bad-timestamp (never emitted verbatim)"
else
    fail "bad timestamp: READ_ERROR=$(get READ_ERROR "$OUT") (want bad-timestamp, exit 1)"
    cat "$OUT"
fi

# ---------------------------------------------------------------------------
# Case 7 — usage errors are exit 2 (not 0, not 1). Exit 1 MEANS "fail closed
# on a read", and a caller that conflated the two would treat a typo as a
# suppressed heartbeat forever.
# ---------------------------------------------------------------------------
"$SUBJECT" --marker "$MARKER" >"$OUT" 2>&1
[[ "$?" -eq 2 ]] && pass "no --issue and no --stdin is a usage error (exit 2)" \
    || fail "missing mode did not exit 2"
"$SUBJECT" --stdin --marker 'bad marker; rm -rf /' </dev/null >"$OUT" 2>&1
[[ "$?" -eq 2 ]] && pass "a marker with shell metacharacters is rejected (exit 2)" \
    || fail "hostile --marker was not rejected"

# ---------------------------------------------------------------------------
# Case 8 — a genuinely changed conclusion must still be reportable: the fix
# must not swallow real state transitions. The reader's job here is to hand
# back the PRIOR hash unchanged so `decide` can see it differs.
# ---------------------------------------------------------------------------
CHANGED="$WORK/changed.json"
{
    echo '['
    mk_comment "2026-09-27T10:00:00Z" "$(marker_body "$OTHER_HASH")"
    echo ']'
} >"$CHANGED"
"$SUBJECT" --marker "$MARKER" --stdin --total-comments 1 --now "$NOW" <"$CHANGED" >"$OUT" 2>&1
if [[ "$(get PRIOR_HASH "$OUT")" == "$OTHER_HASH" && "$(get PRIOR_AGE_H "$OUT")" == "2" ]]; then
    pass "a 2h-old prior with a DIFFERENT hash is reported as-is (decide still sees a change)"
else
    fail "changed-conclusion case: PRIOR_HASH=$(get PRIOR_HASH "$OUT") PRIOR_AGE_H=$(get PRIOR_AGE_H "$OUT")"
fi

echo
echo "passed: $passed, failed: $failed"
[[ "$failed" -eq 0 ]]
