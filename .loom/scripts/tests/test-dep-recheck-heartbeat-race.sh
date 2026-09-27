#!/usr/bin/env bash
# test-dep-recheck-heartbeat-race.sh — two concurrent Curator heartbeat passes
# must produce exactly ONE comment (sky130-modexp #154).
#
# WHAT IS UNDER TEST
#
# curator.md's "Re-check Idempotency" / "Checking Operator-Only Premises →
# Idempotency" sequence, as a script: read the prior marker, ask
# `dep-recheck-fingerprint.sh decide`, and — this is the part #154 added —
# when the answer is "post", take the `loom:curating` mutex, **re-read the
# prior marker and re-decide under it**, and post only if the answer still
# holds.
#
# Before #154 the sequence claimed `loom:curating` only around the post
# itself, so the read-decide-post window was unprotected: two passes could
# both conclude "reportable" before either one's comment existed. Case A below
# reproduces exactly that interleaving; case D runs the SAME interleaving
# through the pre-#154 sequence and asserts it posts twice, so a future
# refactor that quietly drops the confirm step fails here instead of shipping.
#
# Cases C and E are the "do not overcorrect" half: a genuinely changed
# conclusion, and a real heartbeat past the window, must still post. A fix that
# suppressed those would trade comment spam for silent state loss.
#
# Needs a BUILT `loom-daemon`: the decision half is
# `dep-recheck-fingerprint.sh decide`, a thin stub over `loom-daemon
# dep-recheck-fingerprint`, and mocking it would test the mock. The read half
# is `dep-recheck-prior-marker.sh` (pure shell; its own hermetic suite is
# test-dep-recheck-prior-marker.sh, which is the one wired into this repo's
# CI).
#
# No forge: the "thread" is a JSON file, posting appends to it, and the
# `loom:curating` mutex is a label file. Modelling the label as a plain
# check-then-add is deliberate — `gh issue edit --add-label` is NOT a
# compare-and-swap, so the mutex alone cannot be the guarantee, and case A
# proves the confirm-read carries it even when both passes hold the label.
#
# Usage:
#   bash .loom/scripts/tests/test-dep-recheck-heartbeat-race.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
READER="$SCRIPTS_DIR/dep-recheck-prior-marker.sh"
DECIDER="$SCRIPTS_DIR/dep-recheck-fingerprint.sh"

# shellcheck source=lib/require-daemon-bin.sh
source "$SCRIPT_DIR/lib/require-daemon-bin.sh"
loom_test_require_daemon_bin "$SCRIPTS_DIR" "dep-recheck-fingerprint"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

passed=0
failed=0
pass() { echo -e "${GREEN}\xe2\x9c\x93${NC} $1"; passed=$((passed + 1)); }
fail() { echo -e "${RED}\xe2\x9c\x97${NC} $1"; failed=$((failed + 1)); }

[[ -x "$READER" ]] || { echo "FATAL: missing $READER" >&2; exit 1; }
[[ -x "$DECIDER" ]] || { echo "FATAL: missing $DECIDER" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dep-recheck-race-test-XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

MARKER="curator:operator-premise-recheck"
HASH="94285bc12d499dbb"
CHANGED_HASH="3239fee217fc13fb"
NOW=1790510400   # 2026-09-27T12:00:00Z
NOW_ISO="2026-09-27T12:00:00Z"

# ---------------------------------------------------------------------------
# The simulated forge.
# ---------------------------------------------------------------------------

# new_thread <file> <prior_marker_iso|-> — a thread with one prior marker
# comment (or none), plus filler so the count is non-trivial.
new_thread() {
    local file="$1" prior_at="$2"
    jq -n --arg at "$prior_at" --arg m "$MARKER" --arg h "$HASH" '
        [ {created_at: "2026-08-01T00:00:00Z", body: "opening comment"},
          {created_at: "2026-08-02T00:00:00Z", body: "a human note"} ]
        + (if $at == "-" then []
           else [ {created_at: $at,
                   body: ("Operator-parked, premise possibly stale: heartbeat re-check.\n\n<!-- " + $m + ":" + $h + " -->")} ]
           end)' >"$file"
}

thread_total() { jq 'length' "$1"; }

marker_count() {
    jq --arg m "$MARKER" '[.[] | select(.body | test("<!-- " + $m + ":"))] | length' "$1"
}

# post_comment <thread> <hash> — what `gh issue comment` would do.
post_comment() {
    local file="$1" hash="$2" tmp
    tmp="$(mktemp "$WORK/thread-XXXXXX.json")"
    jq --arg at "$NOW_ISO" --arg m "$MARKER" --arg h "$hash" \
        '. + [{created_at: $at, body: ("Operator-parked, premise possibly stale: heartbeat re-check.\n\n<!-- " + $m + ":" + $h + " -->")}]' \
        "$file" >"$tmp" && mv "$tmp" "$file"
}

# label_add <labels_file> <name> / label_has / label_remove — `loom:curating`,
# modelled exactly as the forge behaves: add is idempotent and is NOT a
# compare-and-swap, so two passes can both end up believing they hold it.
label_add()    { printf '%s\n' "$2" >>"$1"; sort -u "$1" -o "$1"; }
label_has()    { [[ -f "$1" ]] && grep -qx "$2" "$1"; }
label_remove() { [[ -f "$1" ]] && grep -vx "$2" "$1" >"$1.tmp" 2>/dev/null; mv -f "$1.tmp" "$1" 2>/dev/null || :; }

# ---------------------------------------------------------------------------
# The Curator sequence, in two stages so a test can interleave two passes.
# ---------------------------------------------------------------------------

# read_and_decide <thread> <own_hash> — the unclaimed read + decide. Echoes
# "ACTION CLAIM". A read that cannot be proven complete yields "read-failed
# false": fail closed, exactly as curator.md now requires.
read_and_decide() {
    local file="$1" own_hash="$2" out total
    total="$(thread_total "$file")"
    out="$("$READER" --marker "$MARKER" --stdin --total-comments "$total" --now "$NOW" <"$file" 2>/dev/null)"
    local read_ok prior_hash prior_age
    read_ok="$(sed -n 's/^READ_OK=\(.*\)$/\1/p' <<<"$out")"
    prior_hash="$(sed -n 's/^PRIOR_HASH=\(.*\)$/\1/p' <<<"$out")"
    prior_age="$(sed -n 's/^PRIOR_AGE_H=\(.*\)$/\1/p' <<<"$out")"
    if [[ "$read_ok" != "true" ]]; then
        echo "read-failed false"
        return 0
    fi
    local decided
    if [[ -n "$prior_hash" ]]; then
        decided="$("$DECIDER" decide --hash "$own_hash" --prior-hash "$prior_hash" \
            --prior-age-hours "$prior_age" 2>/dev/null)"
    else
        decided="$("$DECIDER" decide --hash "$own_hash" 2>/dev/null)"
    fi
    echo "$(sed -n 's/^ACTION=\(.*\)$/\1/p' <<<"$decided") $(sed -n 's/^CLAIM=\(.*\)$/\1/p' <<<"$decided")"
}

# pass_confirm_and_post <thread> <labels> <own_hash> — the #154 sequence:
# take the mutex, RE-READ + RE-DECIDE under it, post only if it still holds.
# Echoes posted|stood-down|skipped-on-confirm.
pass_confirm_and_post() {
    local file="$1" labels="$2" own_hash="$3"
    if label_has "$labels" "loom:curating"; then
        echo "stood-down"
        return 0
    fi
    label_add "$labels" "loom:curating"
    local again claim action
    again="$(read_and_decide "$file" "$own_hash")"
    action="${again%% *}"; claim="${again##* }"
    if [[ "$claim" == "true" ]]; then
        post_comment "$file" "$own_hash"
        label_remove "$labels" "loom:curating"
        echo "posted:$action"
    else
        label_remove "$labels" "loom:curating"
        echo "skipped-on-confirm:$action"
    fi
}

# pass_post_legacy <thread> <labels> <own_hash> — the PRE-#154 sequence: claim,
# post, release, with no re-read. Present only as case D's counterfactual.
pass_post_legacy() {
    local file="$1" labels="$2" own_hash="$3"
    label_add "$labels" "loom:curating"
    post_comment "$file" "$own_hash"
    label_remove "$labels" "loom:curating"
    echo "posted"
}

# ---------------------------------------------------------------------------
# Case A — THE RACE. Both passes read the same prior state (a marker 401h old,
# read completely, so `heartbeat` is the correct answer for whichever pass
# gets there first) and both are told to post. Exactly one comment may land.
# ---------------------------------------------------------------------------
T="$WORK/a.json"; L="$WORK/a.labels"; : >"$L"
new_thread "$T" "2026-09-10T12:46:26Z"
BEFORE="$(marker_count "$T")"

A1="$(read_and_decide "$T" "$HASH")"
B1="$(read_and_decide "$T" "$HASH")"   # interleaved: B read before A posted

if [[ "$A1" == "heartbeat true" && "$B1" == "heartbeat true" ]]; then
    pass "both passes independently decide heartbeat from the same prior state (the race window exists)"
else
    fail "expected both passes to decide 'heartbeat true'; got A='$A1' B='$B1'"
fi

A2="$(pass_confirm_and_post "$T" "$L" "$HASH")"
B2="$(pass_confirm_and_post "$T" "$L" "$HASH")"
AFTER="$(marker_count "$T")"

if [[ "$AFTER" -eq $((BEFORE + 1)) ]]; then
    pass "exactly ONE comment landed from two racing passes (markers $BEFORE -> $AFTER)"
else
    fail "two racing passes produced $((AFTER - BEFORE)) comments (want 1): A2='$A2' B2='$B2'"
fi

if [[ "$A2" == posted:* && "$B2" == skipped-on-confirm:skip ]]; then
    pass "the loser skips on its confirm re-read (A='$A2', B='$B2')"
else
    fail "unexpected outcomes: A='$A2' B='$B2'"
fi

if ! label_has "$L" "loom:curating"; then
    pass "loom:curating is released by both passes (never left behind)"
else
    fail "loom:curating left on the issue"
fi

# ---------------------------------------------------------------------------
# Case B — mutex stand-down. When the other pass is still holding
# `loom:curating`, the second pass stands down without posting.
# ---------------------------------------------------------------------------
T="$WORK/b.json"; L="$WORK/b.labels"; : >"$L"
new_thread "$T" "2026-09-10T12:46:26Z"
BEFORE="$(marker_count "$T")"
label_add "$L" "loom:curating"          # pass A is mid-post
B2="$(pass_confirm_and_post "$T" "$L" "$HASH")"
AFTER="$(marker_count "$T")"
if [[ "$B2" == "stood-down" && "$AFTER" -eq "$BEFORE" ]]; then
    pass "a pass that finds loom:curating already held stands down and posts nothing"
else
    fail "stand-down failed: B='$B2' markers $BEFORE -> $AFTER"
fi

# ---------------------------------------------------------------------------
# Case C — a genuinely changed conclusion still posts, even immediately after
# another pass's comment. The fix must not swallow a real state transition.
# ---------------------------------------------------------------------------
T="$WORK/c.json"; L="$WORK/c.labels"; : >"$L"
new_thread "$T" "2026-09-10T12:46:26Z"
A2="$(pass_confirm_and_post "$T" "$L" "$HASH")"
BEFORE="$(marker_count "$T")"
C2="$(pass_confirm_and_post "$T" "$L" "$CHANGED_HASH")"
AFTER="$(marker_count "$T")"
if [[ "$C2" == "posted:comment" && "$AFTER" -eq $((BEFORE + 1)) ]]; then
    pass "a DIFFERENT conclusion posts immediately after another pass's comment (no swallowing)"
else
    fail "changed conclusion did not post: C='$C2' markers $BEFORE -> $AFTER"
fi

# ---------------------------------------------------------------------------
# Case D — counterfactual. The pre-#154 sequence (claim around the post only,
# no confirm re-read) posts TWICE from case A's interleaving. This is what
# gives case A's assertion teeth.
# ---------------------------------------------------------------------------
T="$WORK/d.json"; L="$WORK/d.labels"; : >"$L"
new_thread "$T" "2026-09-10T12:46:26Z"
BEFORE="$(marker_count "$T")"
A1="$(read_and_decide "$T" "$HASH")"
B1="$(read_and_decide "$T" "$HASH")"
[[ "$A1" == "heartbeat true" && "$B1" == "heartbeat true" ]] || fail "case D setup: A='$A1' B='$B1'"
pass_post_legacy "$T" "$L" "$HASH" >/dev/null
pass_post_legacy "$T" "$L" "$HASH" >/dev/null
AFTER="$(marker_count "$T")"
if [[ "$AFTER" -eq $((BEFORE + 2)) ]]; then
    pass "counterfactual: the pre-#154 sequence posts twice on the same interleaving"
else
    fail "counterfactual did not reproduce the double post (markers $BEFORE -> $AFTER)"
fi

# ---------------------------------------------------------------------------
# Case E — the incomplete-read path. A pass whose prior read cannot be proven
# complete must post NOTHING, even though the truncated view would have looked
# like a 401h-overdue heartbeat. This is the #12 mechanism itself.
# ---------------------------------------------------------------------------
# #12's shape exactly: an OLD marker early in the thread, a FRESH marker at the
# end, and page-1 of the unpaginated read stopping before the fresh one.
T="$WORK/e.json"; L="$WORK/e.labels"; : >"$L"
jq -n --arg m "$MARKER" --arg h "$HASH" '
    [ {created_at: "2026-08-01T00:00:00Z", body: "opening comment"},
      {created_at: "2026-09-10T12:46:26Z",
       body: ("stale heartbeat\n\n<!-- " + $m + ":" + $h + " -->")},
      {created_at: "2026-09-20T00:00:00Z", body: "a human note"},
      {created_at: "2026-09-26T00:00:00Z", body: "another human note"},
      {created_at: "2026-09-27T06:46:29Z",
       body: ("fresh heartbeat\n\n<!-- " + $m + ":" + $h + " -->")} ]' >"$T"
BEFORE="$(marker_count "$T")"

# The truncated view the unpaginated REST read produced on #12: a short prefix
# of the thread, whose newest visible marker is the ancient one.
TRUNC="$WORK/e-trunc.json"
jq '.[0:3]' "$T" >"$TRUNC"
TRUNC_OUT="$("$READER" --marker "$MARKER" --stdin --total-comments "$(thread_total "$T")" \
    --now "$NOW" <"$TRUNC" 2>/dev/null)"
if grep -qx "READ_OK=false" <<<"$TRUNC_OUT" && grep -qx "READ_ERROR=incomplete-read" <<<"$TRUNC_OUT"; then
    pass "a truncated view of the thread is rejected before decide ever sees it"
else
    fail "truncated view was not rejected: $TRUNC_OUT"
fi

# And the complete read of the same thread is a plain skip — no comment.
E1="$(read_and_decide "$T" "$HASH")"
if [[ "$E1" == "skip false" && "$(marker_count "$T")" -eq "$BEFORE" ]]; then
    pass "the complete read of a 5h-old same-hash prior is ACTION=skip CLAIM=false (issue #12 today)"
else
    fail "complete read of #12's current state gave '$E1' (want 'skip false')"
fi

# ---------------------------------------------------------------------------
# Case F — a real heartbeat past the window still fires on a first pass.
# ---------------------------------------------------------------------------
T="$WORK/f.json"; L="$WORK/f.labels"; : >"$L"
new_thread "$T" "-"                       # no prior marker at all
BEFORE="$(marker_count "$T")"
F1="$(read_and_decide "$T" "$HASH")"
F2="$(pass_confirm_and_post "$T" "$L" "$HASH")"
AFTER="$(marker_count "$T")"
if [[ "$F1" == "comment true" && "$F2" == "posted:comment" && "$AFTER" -eq $((BEFORE + 1)) ]]; then
    pass "a first-ever check still posts exactly one comment (suppression is not blanket)"
else
    fail "first-ever check: decide='$F1' post='$F2' markers $BEFORE -> $AFTER"
fi

echo
echo "passed: $passed, failed: $failed"
[[ "$failed" -eq 0 ]]
