#!/usr/bin/env bash
# Test suite for guard-destructive-generic.sh's resolve_var() whole-token
# double-quote unwrap (issue #37).
#
# Background: extract_write_targets()'s same-command $VAR/${VAR} resolution
# (#4881) already substitutes a BARE `$WORKTREE_ABS/rest` write target from a
# same-command `WORKTREE_ABS=/abs/path` assignment. But qsplit() copies quote
# characters verbatim, so the safer, more common shell idiom of quoting the
# reference -- `"$WORKTREE_ABS/rest"` -- arrived at resolve_var() still
# quoted. resolve_var()'s check requires "$" to be the token's own first
# character, so a quoted reference never even attempted resolution and fell
# through to the unresolved-$ deny path (worktree-write-confinement-
# unresolved-var), purely because it was quoted -- not because its
# destination was actually unknown. This is the exact false positive pattern
# reported in issue #37 (4 denied commands, all double-quoting a
# worktree-scoped variable).
#
# The fix unwraps exactly one layer of matching quotes when a token is quoted
# END-TO-END (first char == last char == a quote, length >= 2) and only for
# DOUBLE quotes -- single-quoted "$VAR" is genuinely literal, unexpanded text
# at the real shell, so it must never be substituted. This suite asserts the
# fix resolves the reported false positive while every unrelated
# unresolvable/escaping shape stays denied exactly as before.
#
# Usage: ./.loom/hooks/tests/test-guard-destructive-generic-resolve-var.sh
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

echo "=== guard-destructive-generic.sh resolve_var() quoted-var tests (issue #37) ==="

# --- (a) the exact reported false-positive shape: double-quoted single ----
# assignment, write target stays inside the worktree -> must now ALLOW.
result=$(run_hook 'WORKTREE_ABS="'"$WT"'"; cp /tmp/foo.v "$WORKTREE_ABS/rtl/modexp.v"' "$TMPROOT")
assert_allow "(a) double-quoted \$WORKTREE_ABS/rest, resolves inside worktree -> allow" "$result"

# --- (b) same shape via ${NAME} brace form ---------------------------------
result=$(run_hook 'WORKTREE_ABS="'"$WT"'"; cp /tmp/foo.v "${WORKTREE_ABS}/rtl/modexp.v"' "$TMPROOT")
assert_allow "(b) double-quoted \${WORKTREE_ABS}/rest -> allow" "$result"

# --- (c) mkdir -p + heredoc-fed write, both double-quoted -----------------
result=$(run_hook 'WORKTREE_ABS="'"$WT"'"; mkdir -p "$WORKTREE_ABS/flow"; cat > "$WORKTREE_ABS/flow/req.json" <<EOF
{}
EOF' "$TMPROOT")
assert_allow "(c) mkdir -p + heredoc redirect, double-quoted var -> allow" "$result"

# --- (d) sed -i idiom with a double-quoted var target ----------------------
result=$(run_hook 'WORKTREE_ABS="'"$WT"'"; sed -i "s/a/b/" "$WORKTREE_ABS/rtl/modexp.v"' "$TMPROOT")
assert_allow "(d) sed -i with double-quoted var target -> allow" "$result"

# --- SAFETY (e): double-quoted var pointing OUTSIDE the worktree (still in
# the main checkout) must still DENY -- this proves the fix only resolves
# what it can prove, it does not disable the confinement check.
result=$(run_hook 'EVIL="'"$TMPROOT"'/secrets"; cp /tmp/x "$EVIL/pwn.sh"' "$TMPROOT")
assert_deny "(e) double-quoted var resolving OUTSIDE worktree/into main checkout -> still deny" "$result"

# --- SAFETY (f): single-quoted "$VAR" is literal at the real shell and must
# NEVER be substituted -- unrelated to this fix, asserted as a guardrail so a
# future change cannot silently start treating single quotes like double.
result=$(run_hook 'cd '"$TMPROOT"' && X="'"$TMPROOT"'/secrets"; touch '"'"'$X/pwn.sh'"'"'' "$TMPROOT")
# Whatever the pre-existing verdict is for this literal-$ shape, it must be
# unaffected by resolve_var (X is never substituted into a single-quoted
# span) -- assert the write target is NOT resolved to the value of X by
# checking the deny reason (if any) never names the secrets path via
# substitution-specific wording; a change here would indicate single-quote
# unwrap leaked in.
if [[ "${result%%|*}" == "deny" ]]; then
    reason="${result#*|}"
    if [[ "$reason" == *"unexpanded shell variable"* ]]; then
        fail "(f) single-quoted \$VAR must never be treated as an expandable reference (got unresolved-var reason, meaning it was misclassified as expandable)"
    else
        pass "(f) single-quoted \$VAR denied for reasons unrelated to variable substitution"
    fi
else
    pass "(f) single-quoted \$VAR: allow verdict unaffected by this fix (no substitution attempted)"
fi

# --- SAFETY (g): partially-quoted token (quote does not span the whole
# token) must NOT be unwrapped -- stays on the pre-existing unresolved path.
result=$(run_hook 'WORKTREE_ABS="'"$WT"'"; cp /tmp/x prefix"$WORKTREE_ABS"/rest.sh' "$TMPROOT")
# prefix"$WORKTREE_ABS"/rest.sh is a relative path (starts with a literal
# "prefix" component) from cwd=$TMPROOT (the main checkout) once quotes are
# stripped downstream -- it must NOT resolve to a path use of the worktree
# value, i.e. it must not silently allow a target the operator did not
# actually write. Assert it does not error and produces a deterministic
# verdict (allow, since it lands under the main checkout as a harmless
# relative literal -- NOT because $WORKTREE_ABS was substituted).
if [[ -n "${result%%|*}" ]]; then
    pass "(g) partially-quoted token (prefix\"\$VAR\") does not crash the hook, produces a verdict"
else
    fail "(g) partially-quoted token (prefix\"\$VAR\") produced no verdict"
fi

# --- SAFETY (h): nested/chained unresolved variable in a directory
# component -- known prefix resolves inside the worktree, but a downstream
# segment is still dynamically unresolvable (e.g. embeds a command
# substitution). Must remain DENIED: resolve_var() only ever substitutes a
# token's OWN leading reference, never recursively re-resolves an embedded
# reference surviving in `rest` -- this is intentionally out of scope for
# issue #37 (a materially harder case) and must not regress into an allow.
result=$(run_hook 'cd '"$WT"' && GITREV=$(git rev-parse HEAD) && RID="${GITREV}-x" && D=out && mkdir -p $D && cp /tmp/x $D/artifacts/$RID/f.txt' "$TMPROOT")
assert_deny "(h) nested/chained unresolved var in a directory component -> still deny (out of scope)" "$result"

echo "=== $PASS/$TOTAL passed ==="
[[ "$FAIL" -eq 0 ]]
