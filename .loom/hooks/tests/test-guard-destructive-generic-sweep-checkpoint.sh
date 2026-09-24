#!/usr/bin/env bash
# Test suite for guard-destructive-generic.sh's `.loom/sweep-checkpoint/`
# carve-out from the base `worktree-write-confinement` check (issue #146).
#
# Background: the base confinement check denies ANY Bash-tool write that
# resolves into the main repository checkout whenever a Loom-managed worktree
# exists anywhere in the repo, because it cannot verify that worktree belongs
# to the acting session (#4245). That is correct for a worktree-confined
# Builder, but it produced a structural false positive for the sweep
# orchestrator session itself, which is never inside a worktree and IS
# documented to write its own run bookkeeping into the main checkout:
# `check-main-clean.sh --snapshot
# .loom/sweep-checkpoint/main-clean-baseline-<RUN_ID>.txt` before wave 1
# (`.claude/commands/loom/sweep-wave-lifecycle.md` step 0), preceded by a
# `mkdir -p .loom/sweep-checkpoint`. A real `deny` for exactly that command
# was captured in `.loom/logs/guard-decisions.log` on 2026-09-24 -- i.e. the
# guard blocked the very mechanism that detects main-checkout contamination.
#
# The fix is a PATH-scoped carve-out (`_wt_sweep_bookkeeping_path()`), with no
# role gate: `.loom/sweep-checkpoint/` is gitignored, run-scoped transient
# state, never repo content, so a write there cannot land the kind of edit
# #4178 exists to stop. This suite asserts BOTH halves of that claim -- the
# false positive is gone, AND the hole was not widened past that one
# directory.
#
# This suite asserts:
#   (a) the exact reported orchestrator shapes (mkdir of the directory, then
#       redirection/tee/cp writes of the baseline snapshot and the per-issue
#       checkpoints, relative and absolute spellings) are ALLOWED from the
#       main checkout while a managed worktree exists -- all were denied
#       before this fix
#   (b) every OTHER main-checkout path is still DENIED, including
#       prefix-adjacent neighbours (`.loom/hooks/`, `.loom/sweep-checkpoint2`,
#       `.loom/sweep-checkpoint-evil/`) -- the carve-out is the one directory,
#       not the `.loom/` prefix and not "the main checkout is fine"
#   (c) the genuinely dangerous case is untouched: a session sitting INSIDE a
#       managed worktree writing repo content into the main checkout still
#       hard-denies
#   (d) unrelated behaviour does not regress: in-worktree writes and /tmp
#       scratch writes still allow
#
# Usage: ./.loom/hooks/tests/test-guard-destructive-generic-sweep-checkpoint.sh
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
# builder session. Its mere existence is what arms the base confinement deny.
WT="$TMPROOT/.loom/worktrees/issue-2"
git -C "$TMPROOT" worktree add -q -b "feature/issue-2" "$WT" >/dev/null 2>&1
mkdir -p "$WT/rtl"
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

# Asserts a deny whose message carries the base confinement tag's wording
# (not one of the sibling -unresolved-var denies, which are a different,
# intentionally fail-closed case and explicitly out of scope for #146).
assert_deny_confinement() {
    local desc="$1" result="$2"
    if [[ "${result%%|*}" != "deny" ]]; then
        fail "$desc (expected deny, got: $result)"
    elif [[ "$result" == *"resolves to the main repository checkout"* ]]; then
        pass "$desc"
    else
        fail "$desc (denied, but not by the base confinement check: $result)"
    fi
}

echo "=== (a) sweep orchestrator bookkeeping writes from the main checkout (issue #146) ==="

# The exact command shape from the captured guard-decisions.log deny: the
# orchestrator creating its own checkpoint directory in the main checkout.
# `--snapshot <file>` itself is not a recognized write idiom -- the `mkdir -p`
# is what tripped the guard.
result=$(run_hook 'RUN_ID=$(cat /tmp/sweep_run_id_141.txt)
MAIN_CLEAN_BASELINE=".loom/sweep-checkpoint/main-clean-baseline-${RUN_ID}.txt"
mkdir -p .loom/sweep-checkpoint
./.loom/scripts/check-main-clean.sh --snapshot "$MAIN_CLEAN_BASELINE" 2>&1
echo "RUN_ID=$RUN_ID"' "$TMPROOT")
assert_allow "(a) exact reported shape: 'mkdir -p .loom/sweep-checkpoint' + check-main-clean.sh --snapshot -> allow" "$result"

result=$(run_hook 'mkdir -p .loom/sweep-checkpoint' "$TMPROOT")
assert_allow "(a2) minimal 'mkdir -p .loom/sweep-checkpoint' from main checkout -> allow" "$result"

result=$(run_hook 'mkdir -p "'"$TMPROOT"'/.loom/sweep-checkpoint"' "$TMPROOT")
assert_allow "(a3) same mkdir via absolute main-checkout path -> allow" "$result"

# Redirection writes of the baseline snapshot itself, relative and absolute.
result=$(run_hook 'git status --porcelain > .loom/sweep-checkpoint/main-clean-baseline-sweep-issue-146-1790282590.txt' "$TMPROOT")
assert_allow "(a4) '> .loom/sweep-checkpoint/main-clean-baseline-<RUN_ID>.txt' -> allow" "$result"

result=$(run_hook 'git status --porcelain > "'"$TMPROOT"'/.loom/sweep-checkpoint/main-clean-baseline-sweep-issue-146-1790282590.txt"' "$TMPROOT")
assert_allow "(a5) same baseline write via absolute path -> allow" "$result"

# The other RUN_ID-keyed transient in the same directory: per-issue phase
# checkpoints written by .loom/scripts/sweep-checkpoint.sh.
result=$(run_hook 'echo "{}" > .loom/sweep-checkpoint/issue-146.json' "$TMPROOT")
assert_allow "(a6) '> .loom/sweep-checkpoint/issue-146.json' phase checkpoint -> allow" "$result"

# The same target reached through the other recognized write idioms, so the
# carve-out is not accidentally redirection-only.
result=$(run_hook 'git status --porcelain | tee .loom/sweep-checkpoint/main-clean-baseline-r1.txt' "$TMPROOT")
assert_allow "(a7) 'tee .loom/sweep-checkpoint/...' -> allow" "$result"

result=$(run_hook 'cp /tmp/baseline.txt .loom/sweep-checkpoint/main-clean-baseline-r1.txt' "$TMPROOT")
assert_allow "(a8) 'cp /tmp/... .loom/sweep-checkpoint/...' -> allow" "$result"

result=$(run_hook 'sed -i.bak "s/a/b/" .loom/sweep-checkpoint/issue-146.json' "$TMPROOT")
assert_allow "(a9) 'sed -i .loom/sweep-checkpoint/issue-146.json' -> allow" "$result"

# A nested sub-path under the carved-out directory is covered too.
result=$(run_hook 'echo x > .loom/sweep-checkpoint/run-1790282590/notes.txt' "$TMPROOT")
assert_allow "(a10) nested '.loom/sweep-checkpoint/<run>/notes.txt' -> allow" "$result"

echo "=== (b) the carve-out did NOT widen: other main-checkout paths still deny ==="

# Ordinary repo content in the main checkout -- the baseline this guard exists
# for; must be unchanged by the carve-out.
result=$(run_hook 'echo "module x; endmodule" > rtl/modexp.v' "$TMPROOT")
assert_deny_confinement "(b) '> rtl/modexp.v' in main checkout -> still deny" "$result"

# Prefix-adjacency: a sibling path under `.loom/` is NOT carved out. This is
# the #4178 incident shape verbatim (a session editing live guard hooks in the
# main checkout) and must stay denied.
result=$(run_hook 'echo "# pwned" >> .loom/hooks/guard-destructive-generic.sh' "$TMPROOT")
assert_deny_confinement "(b2) '>> .loom/hooks/guard-destructive-generic.sh' -> still deny (.loom/ is not carved out)" "$result"

result=$(run_hook 'echo x > .loom/config.json' "$TMPROOT")
assert_deny_confinement "(b3) '> .loom/config.json' -> still deny" "$result"

# String-prefix confusion: `sweep-checkpoint` must match as a whole path
# component, so a neighbour whose name merely STARTS with it does not inherit
# the exemption.
result=$(run_hook 'echo x > .loom/sweep-checkpoint2/escape.txt' "$TMPROOT")
assert_deny_confinement "(b4) '.loom/sweep-checkpoint2/escape.txt' -> still deny (no prefix-match escape)" "$result"

result=$(run_hook 'mkdir -p .loom/sweep-checkpoint-evil' "$TMPROOT")
assert_deny_confinement "(b5) 'mkdir -p .loom/sweep-checkpoint-evil' -> still deny (no prefix-match escape)" "$result"

# A `..` traversal out of the carved-out directory must be normalized before
# the prefix test, not taken at face value.
result=$(run_hook 'echo x > .loom/sweep-checkpoint/../hooks/pwned.sh' "$TMPROOT")
assert_deny_confinement "(b6) '.loom/sweep-checkpoint/../hooks/pwned.sh' normalizes out of the carve-out -> still deny" "$result"

# A multi-target command whose FIRST target is the exempt path must not mask a
# second, escaping target.
result=$(run_hook 'mkdir -p .loom/sweep-checkpoint "'"$TMPROOT"'/pwned-dir"' "$TMPROOT")
assert_deny_confinement "(b7) 'mkdir -p <exempt> <escaping>' -- second target still caught -> deny" "$result"

echo "=== (c) Builder-escaping-its-worktree is untouched (the real threat) ==="

# A session sitting inside the managed worktree writing repo content into the
# main checkout: the exact escape #4178 closed. Unaffected by this carve-out.
result=$(run_hook 'echo "module x; endmodule" > "'"$TMPROOT"'/rtl/modexp.v"' "$WT")
assert_deny_confinement "(c) in-worktree session writing <main>/rtl/modexp.v -> still deny" "$result"

result=$(run_hook 'echo "# pwned" >> "'"$TMPROOT"'/.loom/hooks/guard-destructive-generic.sh"' "$WT")
assert_deny_confinement "(c2) in-worktree session editing <main>/.loom/hooks/... -> still deny" "$result"

result=$(run_hook 'cp rtl/modexp.v "'"$TMPROOT"'/rtl/modexp.v"' "$WT")
assert_deny_confinement "(c3) in-worktree session cp-ing into <main>/rtl/ -> still deny" "$result"

echo "=== (d) unrelated behaviour does not regress ==="

result=$(run_hook 'echo x > rtl/modexp.v' "$WT")
assert_allow "(d) in-worktree write to its own rtl/modexp.v -> allow" "$result"

result=$(run_hook 'echo x > .loom/sweep-checkpoint/issue-146.json' "$WT")
assert_allow "(d2) write to the WORKTREE's own .loom/sweep-checkpoint/ -> allow (already inside a worktree)" "$result"

result=$(run_hook 'echo x > /tmp/loom-scratch-146.txt' "$TMPROOT")
assert_allow "(d3) /tmp scratch write -> allow (outside everything this guard protects)" "$result"

echo "=== $PASS/$TOTAL passed ==="
[[ "$FAIL" -eq 0 ]]
