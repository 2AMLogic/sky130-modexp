#!/usr/bin/env bash
# dep-recheck-prior-marker.sh — resolve the FRESHEST prior re-check marker
# comment on an issue, from a provably COMPLETE comment read, and fail CLOSED
# when the read cannot be proven complete (sky130-modexp #154).
#
# This is the missing half of `dep-recheck-fingerprint.sh decide`. That script
# answers "given a prior hash and its age, should this pass post?" — pure,
# deterministic, and (verified on 2026-09-27) correct. It does NOT answer
# "which comment IS the prior one, and how old is it?" Until this script,
# every Curator pass re-derived that read from the inline `gh issue view
# --json comments | jq ... | last` snippet in curator.md, by hand.
#
# THE INCIDENT THIS EXISTS FOR (sky130-modexp #12, 2026-08-25 .. 2026-09-27)
#
# 44 `<!-- curator:operator-premise-recheck:... -->` comments landed on one
# issue; 27 of the 43 gaps were under the 24h idempotency window, the smallest
# 23 minutes. Every one of them reported the SAME conclusion hash
# (94285bc12d499dbb) that `decide` would have told them to skip.
#
# The cause was not `decide` and not a lock: **19 of the 22 post-2026-09-11
# spam comments name the same stale predecessor, "2026-09-10 12:46 UTC"** —
# which is exactly the 30th comment on that issue, i.e. the last entry on page
# one of `GET /repos/{o}/{r}/issues/{n}/comments` at its DEFAULT `per_page=30`.
# The three that named the true predecessor are the three that went through
# the GraphQL path and saw the whole thread.
#
# Loom tells agents to route around GraphQL exhaustion via REST
# (`.loom/CLAUDE.md` § "REST vs GraphQL for forge queries"), and that advice is
# right — but the REST substitute for "all comments" is silently the OLDEST 30.
# The prior-marker read then reports a marker hundreds of hours old, `decide`
# correctly answers `heartbeat` on wrong inputs, and the pass posts. A mutual
# exclusion cannot fix this: a second pass running strictly AFTER the first
# still cannot see the first's comment, because that comment is on page 2.
#
# WHAT THIS SCRIPT GUARANTEES
#
#   1. COMPLETE READ OR NOTHING. Every read carries a proof that it is
#      sufficient to name the freshest marker, and refuses to answer otherwise:
#      `READ_OK=false`, exit 1 — never "no prior marker found", which is the
#      shape that makes a caller post. Two proofs are accepted:
#        * the read holds the whole thread (`COMMENTS_READ >= COMMENTS_TOTAL`),
#          or
#        * the read holds the NEWEST slice of the thread AND found a marker in
#          it — any marker outside a newest-N window is necessarily older, so
#          the freshest one is inside it. (A newest-window read that finds NO
#          marker proves nothing: an older one may sit just outside.)
#   2. FRESHEST BY TIMESTAMP, not by array position. The marker is chosen by
#      `max(createdAt)` over every marker-bearing comment, so neither API
#      ordering nor page-boundary effects can pick a stale one.
#   3. BOTH forge paths are implemented HERE, correctly, so there is no
#      "fallback" left for a caller to get wrong. `--via auto` (the default)
#      tries GraphQL — `comments(last: 100)` returns `totalCount` alongside the
#      newest window, which is both cheaper and exactly the slice this question
#      needs — then REST `--paginate` at `per_page=100`. Either budget being
#      exhausted degrades to the other rather than to a wrong answer; both
#      exhausted fails closed and the next pass retries. This matters: the two
#      budgets are separate and, during heavy dispatch, one is routinely at
#      zero while the other is nearly untouched (observed live 2026-09-27:
#      REST core 0/6550, GraphQL 6494/6550).
#   4. eval-SAFE, like `claim-staleness.sh` / `dep-recheck-fingerprint.sh`.
#      Emitted values are a fixed enum, integers, a `[0-9a-f]+` hash and an
#      ISO-8601 timestamp validated against a strict regex. No forge-authored
#      text can reach a caller's shell through `eval`.
#
# It deliberately does NOT decide anything and does NOT post. Feed PRIOR_HASH /
# PRIOR_AGE_H straight into `dep-recheck-fingerprint.sh decide`.
#
# Usage:
#   dep-recheck-prior-marker.sh --marker PREFIX (--issue N [--repo OWNER/NAME]
#       [--via auto|graphql|rest] | --stdin [--total-comments N]
#       [--newest-window]) [--now EPOCH] [--json]
#
#   --marker PREFIX   Marker prefix without the HTML-comment wrapper or the
#                     trailing colon, e.g. `curator:operator-premise-recheck`
#                     or `curator:dep-recheck`. Matched as
#                     `<!-- PREFIX:<hash> -->`. A prefix that is a strict
#                     prefix of another marker (`curator:dep-recheck` vs
#                     `curator:dep-recheck-extra`) cannot cross-match, because
#                     the colon and hash pattern are part of the match.
#   --issue N         Live mode: read the thread from the forge.
#   --repo OWNER/NAME Defaults to the current repo (`gh repo view`).
#   --via MODE        `auto` (default) tries graphql then rest; `graphql` or
#                     `rest` pins one path (diagnostics, and tests of a single
#                     budget's behaviour).
#   --stdin           Fixture mode: read a JSON array of comment objects on
#                     stdin. Each element needs a body (`body`) and a creation
#                     timestamp (`createdAt` or `created_at`).
#   --total-comments N  Fixture mode completeness assertion: the authoritative
#                     number of comments the thread HAS. A payload shorter
#                     than N is an incomplete read and fails closed exactly as
#                     in live mode. Omit it only when the payload is the whole
#                     thread by construction.
#   --newest-window   Fixture mode: declare the payload to be the NEWEST slice
#                     of the thread rather than an arbitrary one, enabling the
#                     second sufficiency proof above.
#   --now EPOCH       Override "now" for age arithmetic (tests).
#   --json            Emit a JSON object instead of KEY=VALUE lines.
#
# Output keys (KEY=VALUE, `eval`-safe):
#   READ_OK          true|false — false means DO NOT POST, whatever else says.
#   READ_ERROR       ''|incomplete-read|unreadable|bad-timestamp — enum.
#   READ_VIA         graphql|rest|stdin|none — which path answered.
#   COMMENTS_READ    how many comments this read actually holds.
#   COMMENTS_TOTAL   how many the thread has (authoritative), '' if unknown.
#   MARKER_COUNT     how many marker-bearing comments were found.
#   PRIOR_HASH       freshest marker's hash, or '' when there is none.
#   PRIOR_AT         freshest marker's createdAt (ISO-8601 Z), or ''.
#   PRIOR_AGE_H      floor(hours since PRIOR_AT), or ''. Floor matches the
#                    arithmetic curator.md has always used, and floors toward
#                    "inside the window" — the non-spamming direction.
#
# Exit codes:
#   0  the read is complete and the answer is trustworthy (PRIOR_HASH may be
#      legitimately empty: a thread with no marker yet).
#   1  the read could not be proven complete, or a value failed validation.
#      Fail closed: the caller must treat this as "do not post this pass".
#   2  usage error.
#   3  missing dependency (jq, or gh in live mode).

set -uo pipefail

MARKER=""
ISSUE=""
REPO=""
USE_STDIN=0
TOTAL_COMMENTS=""
NOW_EPOCH=""
AS_JSON=0
VIA="auto"
NEWEST_WINDOW=0
READ_VIA="none"

die_usage() {
    echo "ERROR: $1" >&2
    echo "Usage: dep-recheck-prior-marker.sh --marker PREFIX (--issue N [--repo OWNER/NAME] [--via auto|graphql|rest] | --stdin [--total-comments N] [--newest-window]) [--now EPOCH] [--json]" >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --marker)         MARKER="${2:-}"; shift 2 || die_usage "--marker needs a value" ;;
        --issue|--number) ISSUE="${2:-}"; shift 2 || die_usage "--issue needs a value" ;;
        --repo)           REPO="${2:-}"; shift 2 || die_usage "--repo needs a value" ;;
        --stdin)          USE_STDIN=1; shift ;;
        --via)            VIA="${2:-}"; shift 2 || die_usage "--via needs a value" ;;
        --newest-window)  NEWEST_WINDOW=1; shift ;;
        --total-comments) TOTAL_COMMENTS="${2:-}"; shift 2 || die_usage "--total-comments needs a value" ;;
        --now)            NOW_EPOCH="${2:-}"; shift 2 || die_usage "--now needs a value" ;;
        --json)           AS_JSON=1; shift ;;
        -h|--help)        sed -n '2,110p' "$0"; exit 0 ;;
        *)                die_usage "unknown argument '$1'" ;;
    esac
done

[[ -n "$MARKER" ]] || die_usage "--marker is required"
# The marker prefix is used inside a jq string and inside the emitted report;
# constrain it to the shape every Loom marker actually uses so it can never
# carry quoting or shell metacharacters.
[[ "$MARKER" =~ ^[A-Za-z][A-Za-z0-9:_-]*$ ]] || die_usage "--marker must match ^[A-Za-z][A-Za-z0-9:_-]*$ (got '$MARKER')"

case "$VIA" in auto|graphql|rest) ;; *) die_usage "--via must be auto|graphql|rest (got '$VIA')" ;; esac

if [[ "$USE_STDIN" -eq 1 ]]; then
    [[ -z "$ISSUE" ]] || die_usage "--stdin and --issue are mutually exclusive"
else
    [[ -n "$ISSUE" ]] || die_usage "one of --issue or --stdin is required"
    [[ "$ISSUE" =~ ^[0-9]+$ ]] || die_usage "--issue must be a number (got '$ISSUE')"
    [[ -z "$TOTAL_COMMENTS" ]] || die_usage "--total-comments applies to --stdin only (live mode reads it from the forge)"
    [[ "$NEWEST_WINDOW" -eq 0 ]] || die_usage "--newest-window applies to --stdin only (live mode knows which path it used)"
fi
[[ -z "$TOTAL_COMMENTS" || "$TOTAL_COMMENTS" =~ ^[0-9]+$ ]] || die_usage "--total-comments must be a number"
[[ -z "$NOW_EPOCH" || "$NOW_EPOCH" =~ ^[0-9]+$ ]] || die_usage "--now must be an epoch-seconds integer"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 3; }
if [[ "$USE_STDIN" -eq 0 ]]; then
    command -v gh >/dev/null 2>&1 || { echo "ERROR: gh is required for --issue mode" >&2; exit 3; }
fi

# ---------------------------------------------------------------------------
# Reporting. Every emitted value is either a fixed enum, an integer, a hex
# hash or a regex-validated ISO-8601 timestamp — never raw forge text.
# ---------------------------------------------------------------------------
emit() {
    local read_ok="$1" read_error="$2" comments_read="$3" comments_total="$4" \
        marker_count="$5" prior_hash="$6" prior_at="$7" prior_age_h="$8"
    if [[ "$AS_JSON" -eq 1 ]]; then
        jq -n \
            --argjson read_ok "$read_ok" \
            --arg read_error "$read_error" \
            --arg read_via "$READ_VIA" \
            --arg comments_read "$comments_read" \
            --arg comments_total "$comments_total" \
            --arg marker_count "$marker_count" \
            --arg prior_hash "$prior_hash" \
            --arg prior_at "$prior_at" \
            --arg prior_age_h "$prior_age_h" \
            '{read_ok: $read_ok, read_error: $read_error, read_via: $read_via,
              comments_read: ($comments_read | tonumber?),
              comments_total: ($comments_total | tonumber?),
              marker_count: ($marker_count | tonumber?),
              prior_hash: $prior_hash, prior_at: $prior_at,
              prior_age_h: ($prior_age_h | tonumber?)}'
    else
        echo "READ_OK=$read_ok"
        echo "READ_ERROR=$read_error"
        echo "READ_VIA=$READ_VIA"
        echo "COMMENTS_READ=$comments_read"
        echo "COMMENTS_TOTAL=$comments_total"
        echo "MARKER_COUNT=$marker_count"
        echo "PRIOR_HASH=$prior_hash"
        echo "PRIOR_AT=$prior_at"
        echo "PRIOR_AGE_H=$prior_age_h"
    fi
}

# fail_closed <read_error> [comments_read] [comments_total] — the ONE shape a
# caller may never mistake for "no prior marker": READ_OK=false, every prior
# field empty, exit 1.
fail_closed() {
    emit false "$1" "${2:-0}" "${3:-}" 0 "" "" ""
    exit 1
}

# ---------------------------------------------------------------------------
# Acquire the comment payload.
# ---------------------------------------------------------------------------
PAYLOAD=""

# read_graphql — `comments(last: 100)` hands back the NEWEST window plus the
# authoritative `totalCount` in ONE request, which is both cheaper than the
# REST pair and exactly the slice this question needs. Sets PAYLOAD /
# TOTAL_COMMENTS / NEWEST_WINDOW on success.
read_graphql() {
    local owner="${REPO%%/*}" name="${REPO##*/}" out
    out="$(gh api graphql \
        -F owner="$owner" -F name="$name" -F number="$ISSUE" \
        -f query='query($owner:String!,$name:String!,$number:Int!){
                    repository(owner:$owner,name:$name){
                      issue(number:$number){
                        comments(last:100){ totalCount nodes { createdAt body } } } } }' \
        2>/dev/null)" || return 1
    local total nodes
    total="$(printf '%s' "$out" | jq -r '.data.repository.issue.comments.totalCount // empty' 2>/dev/null)"
    nodes="$(printf '%s' "$out" | jq -c '.data.repository.issue.comments.nodes // empty' 2>/dev/null)"
    [[ "$total" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "$nodes" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    TOTAL_COMMENTS="$total"
    PAYLOAD="$nodes"
    NEWEST_WINDOW=1
    READ_VIA="graphql"
    return 0
}

# read_rest — the authoritative count, then the WHOLE thread. `--paginate` is
# the whole point: without it this endpoint answers with the OLDEST 30 comments
# and nothing in the response says more exist (sky130-modexp #12).
#
# The count is read FIRST on purpose: a comment landing mid-read then makes
# TOTAL look smaller than READ (harmless), whereas the other order would let a
# mid-read arrival masquerade as truncation.
read_rest() {
    local total raw payload
    total="$(gh api "repos/$REPO/issues/$ISSUE" --jq '.comments' 2>/dev/null)"
    [[ "$total" =~ ^[0-9]+$ ]] || return 1
    raw="$(gh api --paginate "repos/$REPO/issues/$ISSUE/comments?per_page=100" 2>/dev/null)" || return 1
    # Pages arrive as consecutive JSON arrays; `jq -s add` concatenates them.
    payload="$(printf '%s' "$raw" | jq -s 'map(select(type == "array")) | add // []' 2>/dev/null)" || return 1
    printf '%s' "$payload" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    TOTAL_COMMENTS="$total"
    PAYLOAD="$payload"
    NEWEST_WINDOW=0
    READ_VIA="rest"
    return 0
}

if [[ "$USE_STDIN" -eq 1 ]]; then
    READ_VIA="stdin"
    PAYLOAD="$(cat)"
    # An unparseable or non-array payload is an unreadable thread, not an
    # empty one.
    if ! printf '%s' "$PAYLOAD" | jq -e 'type == "array"' >/dev/null 2>&1; then
        fail_closed unreadable 0 "$TOTAL_COMMENTS"
    fi
else
    if [[ -z "$REPO" ]]; then
        REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"
        [[ -n "$REPO" ]] || fail_closed unreadable
    fi
    [[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die_usage "--repo must be OWNER/NAME (got '$REPO')"

    case "$VIA" in
        graphql) read_graphql || fail_closed unreadable ;;
        rest)    read_rest    || fail_closed unreadable ;;
        auto)    read_graphql || read_rest || fail_closed unreadable ;;
    esac
fi

COMMENTS_READ="$(printf '%s' "$PAYLOAD" | jq 'length' 2>/dev/null)"
[[ "$COMMENTS_READ" =~ ^[0-9]+$ ]] || fail_closed unreadable 0 "$TOTAL_COMMENTS"

# ---------------------------------------------------------------------------
# Freshest marker by timestamp. ISO-8601 Z timestamps sort lexicographically,
# so `sort_by` is a correct chronological sort and does not depend on the
# order the forge returned. A body carrying several markers yields its LAST
# one, matching curator.md's historical `tail -n 1`.
# ---------------------------------------------------------------------------
SELECTED="$(printf '%s' "$PAYLOAD" | jq -r --arg m "$MARKER" '
    def ts: (.createdAt // .created_at // "");
    def hashes: [ (.body // "")
                  | scan("<!-- *" + $m + ":([0-9a-fA-F]+) *-->")
                  | .[0] ];
    [ .[] | select((.body // "") | test("<!-- *" + $m + ":[0-9a-fA-F]+ *-->")) ]
    | length as $n
    | ( [ .[] | {ts: ts, hash: (hashes | last // "")} ]
        | sort_by(.ts) | last // {ts: "", hash: ""} ) as $newest
    | "\($n)\t\($newest.hash)\t\($newest.ts)"
' 2>/dev/null)" || fail_closed unreadable "$COMMENTS_READ" "$TOTAL_COMMENTS"

MARKER_COUNT="${SELECTED%%$'\t'*}"
_rest="${SELECTED#*$'\t'}"
PRIOR_HASH="${_rest%%$'\t'*}"
PRIOR_AT="${_rest#*$'\t'}"

[[ "$MARKER_COUNT" =~ ^[0-9]+$ ]] || fail_closed unreadable "$COMMENTS_READ" "$TOTAL_COMMENTS"

# ---------------------------------------------------------------------------
# SUFFICIENCY GATE — the #12 regression. Answer only from a read that provably
# contains the freshest marker.
#
#   (a) the whole thread is in hand                      -> sufficient;
#   (b) the NEWEST window is in hand and a marker is in
#       it — anything outside a newest-N window is older  -> sufficient;
#   (c) otherwise (a short read, or a newest window with no marker in it: an
#       older marker may sit just outside)                -> fail closed.
#
# (c) is the case that spammed #12 for a month, as the OLDEST-30 shape: it
# looked exactly like "no prior marker" / "a 400h-old prior", the two inputs
# that make `decide` say post.
# ---------------------------------------------------------------------------
if [[ -n "$TOTAL_COMMENTS" ]] && (( COMMENTS_READ < TOTAL_COMMENTS )); then
    if ! (( NEWEST_WINDOW == 1 && MARKER_COUNT > 0 )); then
        fail_closed incomplete-read "$COMMENTS_READ" "$TOTAL_COMMENTS"
    fi
fi

if [[ "$MARKER_COUNT" -eq 0 ]]; then
    # Genuinely no prior marker, from a read proven complete. THIS is the
    # "first-ever check" signal `decide` is entitled to act on — and the only
    # way to produce it is a complete read.
    emit true "" "$COMMENTS_READ" "$TOTAL_COMMENTS" 0 "" "" ""
    exit 0
fi

# Validate before emitting: no unvalidated forge-derived value may be printed
# into output a caller `eval`s.
[[ "$PRIOR_HASH" =~ ^[0-9a-fA-F]+$ ]] || fail_closed bad-timestamp "$COMMENTS_READ" "$TOTAL_COMMENTS"
[[ "$PRIOR_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
    || fail_closed bad-timestamp "$COMMENTS_READ" "$TOTAL_COMMENTS"

# Portable epoch parse: GNU `date -d` first, BSD/macOS `date -j -f` second.
# Both are tried; a timestamp neither can parse fails closed rather than
# producing a bogus age.
_epoch() {
    date -u -d "$1" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null
}
PRIOR_EPOCH="$(_epoch "$PRIOR_AT")"
[[ "$PRIOR_EPOCH" =~ ^[0-9]+$ ]] || fail_closed bad-timestamp "$COMMENTS_READ" "$TOTAL_COMMENTS"

NOW="${NOW_EPOCH:-$(date -u +%s)}"
PRIOR_AGE_H=$(( ( NOW - PRIOR_EPOCH ) / 3600 ))
# A marker timestamped in the future (clock skew) is reported as age 0 rather
# than a negative number: 0 is inside every window, i.e. the non-spamming
# direction, and `decide` has no defined behaviour for a negative age.
(( PRIOR_AGE_H >= 0 )) || PRIOR_AGE_H=0

emit true "" "$COMMENTS_READ" "$TOTAL_COMMENTS" "$MARKER_COUNT" "$PRIOR_HASH" "$PRIOR_AT" "$PRIOR_AGE_H"
exit 0
