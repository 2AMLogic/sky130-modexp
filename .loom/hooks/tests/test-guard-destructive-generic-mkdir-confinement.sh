#!/usr/bin/env bash
# Test suite for guard-destructive-generic.sh's `mkdir` write-idiom
# recognition in extract_write_targets() (issue #95).
#
# Background: extract_write_targets() recognizes `>`/`>>` redirection, `tee`,
# `sed -i`, and `cp`/`mv` as write idioms subject to the worktree-write-
# confinement check (#4178), but NEVER recognized `mkdir` (with or without
# `-p`, or other flags like `-m`) at all. A command like
# `mkdir -p "../../../pwned-dir"` run from inside a Loom-managed worktree
# therefore silently ALLOWed directory creation outside the worktree into the
# main repo checkout, with zero ask/deny/telemetry -- a full confinement
# bypass for this one write idiom even though the equivalent
# cp/mv/>/tee/sed -i idioms were correctly confined and denied.
#
# This suite asserts:
#   (a) a literal `mkdir -p` escape into the main checkout is denied
#   (b) an in-worktree `mkdir -p` is allowed
#   (c) a same-command-resolvable variable-based `mkdir -p` target INSIDE the
#       worktree is allowed (same-command $VAR resolution, #4881, applies to
#       mkdir targets exactly like it already does for cp/tee/sed -i/>)
#   (d) a same-command-resolvable variable-based `mkdir -p` target OUTSIDE the
#       worktree (still inside the main checkout) is denied
#   (e) EVERY argument of a multi-directory `mkdir -p dir1 dir2` invocation is
#       checked, not just the first -- a safe first argument must not mask an
#       escaping second argument
#   (f)/(g) common safe `mkdir -p` idioms already used by legitimate Builder
#       workflows (bare relative dir, `-m MODE` flag, `mkdir -p "$(dirname
#       ...)"`-style nested call) do not regress into a false-positive deny
#
# Usage: ./.loom/hooks/tests/test-guard-destructive-generic-mkdir-confinement.sh
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

# One managed worktree at $TMPROOT/.loom/worktrees/issue-2, tracked as a real
# git worktree so git-common-dir / rev-parse resolve exactly like a live
# builder session.
WT="$TMPROOT/.loom/worktrees/issue-2"
git -C "$TMPROOT" worktree add -q -b "feature/issue-2" "$WT" >/dev/null 2>&1
mkdir -p "$WT/rtl" "$WT/flow"
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

echo "=== guard-destructive-generic.sh mkdir write-idiom confinement tests (issue #95) ==="

# --- (a) literal mkdir -p escape into the main checkout -> deny ------------
result=$(run_hook 'mkdir -p "../../../pwned-dir"' "$WT")
assert_deny "(a) literal 'mkdir -p ../../../pwned-dir' escaping worktree into main checkout -> deny" "$result"

# Same shape, absolute literal path into the main checkout root.
result=$(run_hook 'mkdir -p "'"$TMPROOT"'/pwned-dir"' "$WT")
assert_deny "(a2) literal absolute 'mkdir -p <main-checkout>/pwned-dir' -> deny" "$result"

# --- (b) in-worktree mkdir -p -> allow --------------------------------------
result=$(run_hook 'mkdir -p "sub/newdir"' "$WT")
assert_allow "(b) 'mkdir -p sub/newdir' relative, resolves inside worktree -> allow" "$result"

result=$(run_hook 'mkdir -p "'"$WT"'/sub/newdir2"' "$WT")
assert_allow "(b2) 'mkdir -p <worktree-abs>/sub/newdir2' -> allow" "$result"

# --- (c) same-command-resolvable variable-based mkdir -p target INSIDE the
# worktree -> allow (mirrors the cp/tee/sed -i/> #4881 same-command
# resolution already proven for those idioms).
result=$(run_hook 'WORKTREE_ABS="'"$WT"'"; mkdir -p "$WORKTREE_ABS/newdir3"' "$TMPROOT")
assert_allow "(c) same-command \$WORKTREE_ABS/newdir3 resolves inside worktree -> allow" "$result"

result=$(run_hook 'cd '"$WT"' && REC=abc123 && mkdir -p "artifacts/$REC/sub"' "$TMPROOT")
assert_allow "(c2) mid-path \$REC after literal prefix, resolves inside worktree -> allow" "$result"

# --- (d) same-command-resolvable variable-based mkdir -p target OUTSIDE the
# worktree (still inside the main checkout) -> deny.
result=$(run_hook 'EVIL="'"$TMPROOT"'/secrets"; mkdir -p "$EVIL/pwned"' "$TMPROOT")
assert_deny "(d) same-command \$EVIL/pwned resolves OUTSIDE worktree/into main checkout -> deny" "$result"

# --- (e) EVERY argument of a multi-directory mkdir -p is checked -----------
# A safe FIRST argument must not mask an escaping SECOND argument.
result=$(run_hook 'mkdir -p "sub/dir1" "'"$TMPROOT"'/dir2"' "$WT")
assert_deny "(e) 'mkdir -p dir1 <escaping-dir2>' -- second (escaping) argument still checked -> deny" "$result"

# The reverse order too -- an escaping FIRST argument must not be missed
# because a later argument happens to be safe.
result=$(run_hook 'mkdir -p "'"$TMPROOT"'/dir1" "sub/dir2"' "$WT")
assert_deny "(e2) 'mkdir -p <escaping-dir1> dir2' -- first (escaping) argument caught -> deny" "$result"

# Both arguments safe (inside worktree) -> allow.
result=$(run_hook 'mkdir -p "sub/dir1" "sub/dir2"' "$WT")
assert_allow "(e3) 'mkdir -p dir1 dir2' both inside worktree -> allow" "$result"

echo "=== guard-destructive-generic.sh mkdir false-positive regression guards (issue #95) ==="

# --- (f) bare relative mkdir -p, the overwhelmingly common Builder idiom ---
result=$(run_hook 'mkdir -p verification/records/foo' "$WT")
assert_allow "(f) bare relative 'mkdir -p verification/records/foo' inside worktree -> allow" "$result"

# --- (g) -m MODE flag (separate-argument form) must not be mistaken for a
# directory target, and must not cause the REAL directory argument that
# follows to be skipped either.
result=$(run_hook 'mkdir -m 0755 -p sub/newdir4' "$WT")
assert_allow "(g) 'mkdir -m 0755 -p sub/newdir4' -- mode value not treated as a target, real dir still allowed -> allow" "$result"

result=$(run_hook 'mkdir -m 0755 -p "'"$TMPROOT"'/pwned-dir4"' "$WT")
assert_deny "(g2) 'mkdir -m 0755 -p <escaping-dir>' -- mode value skipped, escaping dir still caught -> deny" "$result"

# Attached -m0755 form -- must not consume the following token as a mode
# value (there isn't one to consume).
result=$(run_hook 'mkdir -m0755 -p sub/newdir5' "$WT")
assert_allow "(g3) 'mkdir -m0755 -p sub/newdir5' attached mode form -> allow" "$result"

# --- (h) combined short-flag spelling (`-pv`) and a trailing `&&`-chained
# real command, mirroring the common `mkdir -p <dir> && cp ... <dir>/...`
# Builder idiom -- must not regress.
result=$(run_hook 'mkdir -pv sub/newdir6 && cp /tmp/x.txt sub/newdir6/x.txt' "$WT")
assert_allow "(h) 'mkdir -pv sub/newdir6 && cp ... sub/newdir6/x.txt' chained idiom, both inside worktree -> allow" "$result"

result=$(run_hook 'mkdir -pv sub/newdir7 && cp /tmp/x.txt "'"$TMPROOT"'/pwned7/x.txt"' "$WT")
assert_deny "(h2) same chained idiom, but the chained cp destination escapes into the main checkout -> deny" "$result"

echo "=== $PASS/$TOTAL passed ==="
[[ "$FAIL" -eq 0 ]]
