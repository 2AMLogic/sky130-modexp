#!/usr/bin/env bash
# Test suite for guard-destructive-generic.sh's qsplit() backslash-newline
# line-continuation join (issue #71).
#
# Background: an Auditor guard-decision telemetry review
# (.loom/logs/guard-decisions.log) found the base `worktree-write-
# confinement` pattern firing a false-positive `deny` on a multi-source `cp`
# whose destination (the last argument, on its own `\`-continued line) was
# correctly and fully confined inside the acting worktree, while every
# *source* argument (reads, not writes) resolved outside it under
# /tmp/issue60-artifacts/... .
#
# The `cp`/`mv` branch in extract_write_targets() (guard-destructive-
# generic.sh) already only ever treats the LAST non-flag argument as the
# write target when it sees >= 2 non-flag arguments in one segment -- that
# part was correct before this fix and is unchanged by it. The actual root
# cause (confirmed by direct reproduction, matching the Champion review note
# on this issue) is upstream, in the shared `qsplit()` command-segmentation
# helper: it copied an embedded `\n` through to the segment splitter
# (`n = split($0, segs, "\n")`) for EVERY reason except the ;/&/| separators
# -- including the newline half of a real shell `\`-continuation, which is
# not a statement boundary at all. That stranded each physical line of a
# `\`-continued `cp`/`mv` invocation into its own bogus one-line "segment":
# the real destination argument never reached the cp/mv branch's token list
# (it sat alone on its own line, with no `cp`/`mv` command word), while an
# EARLIER line ending in `cp <source-path> \` was read as a two-non-flag-
# argument cp invocation (the source path, and the literal trailing `\` as a
# second "argument") -- so the cp/mv branch picked the bogus trailing `\` as
# "the last argument", resolved it relative to curcwd, and denied it as a
# worktree-isolation bypass.
#
# The fix makes qsplit() elide an UNQUOTED `\` immediately followed by `\n`
# (matching real shell line-continuation semantics: both characters are
# simply deleted, joining the two physical lines into the one logical
# command a real shell would execute) -- see that function's header comment
# in guard-destructive-generic.sh for the full contract, including why this
# can only ever narrow a false positive/negative, never widen a deny into an
# allow of something that was never proven safe.
#
# Usage: ./.loom/hooks/tests/test-guard-destructive-generic-cp-mv-continuation.sh
# Exit 0 = all pass, 1 = fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SRC_HOOK="$REPO_ROOT/.loom/hooks/guard-destructive-generic.sh"

PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
git init -q "$TMPROOT"
git -C "$TMPROOT" config user.email "test@example.com"
git -C "$TMPROOT" config user.name "test"
touch "$TMPROOT/README.md"
git -C "$TMPROOT" add README.md
git -C "$TMPROOT" commit -q -m "init"
mkdir -p "$TMPROOT/.loom/hooks"
cp "$SRC_HOOK" "$TMPROOT/.loom/hooks/guard-destructive-generic.sh"
chmod +x "$TMPROOT/.loom/hooks/guard-destructive-generic.sh"
HOOK="$TMPROOT/.loom/hooks/guard-destructive-generic.sh"

# One managed worktree at $TMPROOT/.loom/worktrees/issue-60, tracked as a
# real git worktree so git-common-dir / rev-parse resolve exactly like a live
# builder session (mirrors the issue-60 record the #71 incident was
# building: verification/records/gate-level-sim).
WT="$TMPROOT/.loom/worktrees/issue-60"
git -C "$TMPROOT" worktree add -q -b "feature/issue-60" "$WT" >/dev/null 2>&1
mkdir -p "$WT/verification/records/gate-level-sim/artifacts/20260816-175146-a084639"
cat > "$WT/.loom-managed" <<'EOF'
# Loom-managed worktree marker
EOF

pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); printf "${GREEN}PASS${NC} %s\n" "$1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); printf "${RED}FAIL${NC} %s\n" "$1"; }

# Runs the hook with a Bash tool_input.command + cwd. Prints "<decision>|<reason>".
# decision is "allow" (empty output) or "deny".
run_hook() {
    local cmd="$1" cwd="$2"
    local out
    out=$(jq -n --arg cmd "$cmd" --arg cwd "$cwd" \
        '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd}' | bash "$HOOK" 2>/dev/null)
    if [[ -z "$out" ]]; then
        printf 'allow|'
    else
        local reason
        reason=$(echo "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null || true)
        printf 'deny|%s' "$reason"
    fi
}

assert_allow() {
    local desc="$1" result="$2"
    if [[ "${result%%|*}" == "allow" ]]; then
        pass "$desc"
    else
        fail "$desc (expected allow, got: $result)"
    fi
}

assert_deny() {
    local desc="$1" result="$2"
    if [[ "${result%%|*}" == "deny" ]]; then
        pass "$desc"
    else
        fail "$desc (expected deny, got: $result)"
    fi
}

echo "=== guard-destructive-generic.sh cp/mv line-continuation tests (issue #71) ==="

# --- (a) the exact reported false-positive shape: multi-source cp, sources
# outside the worktree (reads), destination (last arg, own continuation
# line) inside the worktree -> must ALLOW.
CMD_A='mkdir -p /tmp/issue60-artifacts/gate-level-sim
cp /tmp/issue60-artifacts/gate-level-sim/run-console.txt \
   /tmp/issue60-artifacts/gate-level-sim/klt-functional-verification.json \
   /tmp/issue60-artifacts/gate-level-sim/gate-level-width-16.jsonl \
   /tmp/issue60-artifacts/gate-level-sim/cross-check-console.txt \
   /tmp/issue60-artifacts/gate-level-sim/modexp_post_route.v \
   '"$WT"'/verification/records/gate-level-sim/artifacts/20260816-175146-a084639/'
result=$(run_hook "$CMD_A" "$TMPROOT")
assert_allow "(a) #71 reported shape: multi-source continuation-line cp into in-worktree dest -> allow" "$result"

# --- (b) same shape via `mv` -----------------------------------------------
CMD_B='mv /tmp/issue60-artifacts/gate-level-sim/run-console.txt \
   /tmp/issue60-artifacts/gate-level-sim/klt-functional-verification.json \
   '"$WT"'/verification/records/gate-level-sim/artifacts/20260816-175146-a084639/'
result=$(run_hook "$CMD_B" "$TMPROOT")
assert_allow "(b) same shape via mv -> allow" "$result"

# --- (c) a SINGLE-source continuation-line cp (still 2 real arguments once
# joined: one source, one destination) into the worktree -> allow. This is
# the minimal case that isolates the mechanism: before the fix, the
# continuation newline stranded the destination on its own line (no `cp`
# command word) while the source-only line was misread as a 1-argument cp
# whose sole path became the bogus "last argument" write target.
CMD_C='cp /tmp/issue60-artifacts/gate-level-sim/run-console.txt \
   '"$WT"'/verification/records/gate-level-sim/artifacts/20260816-175146-a084639/'
result=$(run_hook "$CMD_C" "$TMPROOT")
assert_allow "(c) single-source continuation-line cp into in-worktree dest -> allow" "$result"

# --- SAFETY (d): multi-source continuation-line cp whose ACTUAL destination
# (still the last argument, still on its own continuation line) resolves
# OUTSIDE the worktree -- into the main checkout -- must still DENY. Proves
# the fix only removes the phantom mid-invocation split; it does not weaken
# detection of a genuine out-of-worktree cp/mv destination.
CMD_D='cp /tmp/a.txt \
   /tmp/b.txt \
   '"$TMPROOT"'/evil-dest/'
result=$(run_hook "$CMD_D" "$TMPROOT")
assert_deny "(d) SAFETY: continuation-line cp, real destination outside worktree -> still deny" "$result"

# --- SAFETY (e): same as (d) via mv -----------------------------------------
CMD_E='mv /tmp/a.txt \
   /tmp/b.txt \
   '"$TMPROOT"'/evil-dest/'
result=$(run_hook "$CMD_E" "$TMPROOT")
assert_deny "(e) SAFETY: continuation-line mv, real destination outside worktree -> still deny" "$result"

# --- SAFETY (f): a single-line (non-continued) cp/mv whose destination is
# outside the worktree must still deny, completely unaffected by this fix
# (baseline sanity -- no backslash-newline involved at all).
CMD_F='cp /tmp/a.txt /tmp/b.txt '"$TMPROOT"'/evil-dest/'
result=$(run_hook "$CMD_F" "$TMPROOT")
assert_deny "(f) SAFETY: single-line cp, real destination outside worktree -> still deny (baseline, unaffected)" "$result"

# --- SAFETY (g): a `\` that is NOT immediately followed by a newline (e.g. a
# real escaped space in a path) must be left completely untouched -- this
# proves the join is narrowly `\` + `\n` only, never a generic backslash
# strip.
CMD_G='cp /tmp/a\ b.txt '"$WT"'/verification/records/gate-level-sim/artifacts/20260816-175146-a084639/'
result=$(run_hook "$CMD_G" "$TMPROOT")
assert_allow "(g) escaped-space path (backslash not followed by newline) -> allow, untouched by the join" "$result"

# --- SAFETY (h): a `\` + newline embedded INSIDE a plain (no command
# substitution) single-quoted span must be preserved verbatim -- the join
# only ever applies OUTSIDE a quoted span. Uses a multi-line single-quoted
# sed script (unrelated to any write target) ahead of a same-line cp whose
# own destination is outside the worktree, so a DENY here proves the quoted
# span's embedded "\\\n" was never touched (if it had been misjoined into
# the surrounding text, the sed script's own trailing `/tmp/evil` text could
# spill out and be misread, changing the verdict away from a clean deny on
# the real cp destination).
CMD_H='sed "s/a\
b/c/" /tmp/x.txt; cp /tmp/a.txt '"$TMPROOT"'/evil-dest/'
result=$(run_hook "$CMD_H" "$TMPROOT")
assert_deny "(h) SAFETY: backslash-newline inside a quoted span is untouched; real cp dest outside worktree -> still deny" "$result"

# --- (i) instance-1 REGRESSION GUARD (not this issue's scope): the OTHER
# guard-decisions.log finding evaluated alongside #71, a `sed -i` write to a
# bare /tmp path with no relation to any worktree. The issue explicitly
# scopes this fix to the cp/mv multi-argument parsing gap and calls out that
# this instance must NOT change. It has no `\`-continuation at all, so
# qsplit()'s new branch (`c == "\\" && next == "\n"`) cannot ever match
# inside it -- assert the fixed hook's verdict is BYTE-IDENTICAL to the
# pre-#71 hook's verdict for the exact multi-line command quoted in the
# issue, proving this fix does not alter it either way.
PRE71_HOOK="$TMPROOT/.loom/hooks/guard-destructive-generic.pre71.sh"
git -C "$REPO_ROOT" show main:.loom/hooks/guard-destructive-generic.sh > "$PRE71_HOOK" 2>/dev/null || cp "$SRC_HOOK" "$PRE71_HOOK"
chmod +x "$PRE71_HOOK"
CMD_I="sed -i '' 's/from cocotb.runner import get_runner/from cocotb_tools.runner import get_runner/' /tmp/run_modexp_test.py
cat /tmp/run_modexp_test.py | head -3"
out_fixed=$(jq -n --arg cmd "$CMD_I" --arg cwd "$TMPROOT" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd}' | bash "$HOOK" 2>/dev/null || true)
out_pre71=$(jq -n --arg cmd "$CMD_I" --arg cwd "$TMPROOT" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd}' | bash "$PRE71_HOOK" 2>/dev/null || true)
if [[ "$out_fixed" == "$out_pre71" ]]; then
    pass "(i) instance-1 (sed -i /tmp, no continuation) verdict unchanged by this fix"
else
    fail "(i) instance-1 (sed -i /tmp, no continuation) verdict CHANGED by this fix (pre71=[$out_pre71] fixed=[$out_fixed])"
fi

echo "=== $PASS/$TOTAL passed ==="
[[ "$FAIL" -eq 0 ]]
