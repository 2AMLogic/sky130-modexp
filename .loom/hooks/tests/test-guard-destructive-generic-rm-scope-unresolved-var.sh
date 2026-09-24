#!/usr/bin/env bash
# Regression evidence for the 3 `rm-scope-unresolved-var` deny events
# reported in issue #151 (Guard-Decision Telemetry Review, standing policy
# #3898), against `rm_scope_literal_same_command_resolve()` /
# `rm_scope_mktemp_same_command_safe()` in the vendored
# `.loom/hooks/guard-destructive-generic.sh`.
#
# SCOPE (read this before "fixing" anything here): issue #151 is a telemetry
# REPORT, not an implementation request -- its own text is explicit that it
# is "not a request to hand-edit guard-destructive-generic.sh in this repo"
# and "not proposing a specific patch". `guard-destructive-generic.sh`'s own
# header likewise says generic pattern behavior must be fixed upstream (Repo
# Skills' canonical `hooks/repo/guard-destructive.sh`), not hand-edited here.
# This suite therefore does NOT attempt the refinements #151 floats for
# instances 1 and 3 -- it only pins down TODAY's (correct, fail-closed)
# behavior for all three reported instances as regression evidence, so:
#   - a future resync/refinement that silently starts ALLOWing instance 2
#     (the genuinely-dynamic $PWD case, which #151 says must stay denied) is
#     caught immediately; and
#   - instances 1 and 3 (the "REFINABLE" / "POSSIBLY REFINABLE" candidates
#     #151 flags for Architect/Champion to evaluate upstream) have a named,
#     literal repro on record, so a future upstream-refinement pass has an
#     exact shape to validate against and this suite gets updated -- not
#     re-surprised -- if/when that lands.
#
# Usage: ./.loom/hooks/tests/test-guard-destructive-generic-rm-scope-unresolved-var.sh
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

# One managed worktree, mirroring the reported sessions' own layout
# (mirrors issue #151's own repro, a `.loom/worktrees/issue-78` session).
WT="$TMPROOT/.loom/worktrees/issue-78"
git -C "$TMPROOT" worktree add -q -b "feature/issue-78" "$WT" >/dev/null 2>&1
mkdir -p "$WT/.scratch-issue78/verify-rerun"

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

assert_deny_unresolved_var() {
    local desc="$1" result="$2"
    if [[ "${result%%|*}" != "deny" ]]; then
        fail "$desc (expected deny, got: $result)"
        return
    fi
    local reason="${result#*|}"
    if [[ "$reason" == *"rm target"*"unexpanded shell variable"* ]]; then
        pass "$desc"
    else
        fail "$desc (denied, but not via rm-scope-unresolved-var: $reason)"
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

echo "=== guard-destructive-generic.sh rm-scope-unresolved-var telemetry (issue #151) ==="

# --- Instance 1 (issue #151) -- "REFINABLE": a one-hop literal variable
# chain. REPO is itself a same-command pure-literal assignment, and WORK's
# RHS embeds "$REPO" rather than being a pure literal, so
# rm_scope_literal_same_command_resolve()'s point-2 pure-literal test
# rejects it BY DESIGN (guard-destructive-generic.sh's own doc comment).
# #151 flags this as a narrow, provably-static extension candidate for the
# UPSTREAM guard -- not implemented here. Today's (correct, fail-closed)
# behavior is pinned as DENY so a silent change either direction is caught.
result=$(run_hook 'REPO="'"$WT"'"; WORK="$REPO/.scratch-issue78"; rm -rf "$WORK"' "$TMPROOT")
assert_deny_unresolved_var \
    "(1) #151 instance 1: one-hop literal var chain (REPO -> WORK=\"\$REPO/lit\") -> still deny (upstream refinement candidate, not implemented here)" \
    "$result"

# --- Instance 2 (issue #151) -- "CORRECTLY KEPT FLAGGED": W=\$PWD is not a
# static literal -- its value depends on runtime cwd the guard cannot
# observe from command text alone. #151 explicitly says NO refinement is
# proposed for this shape; it must remain fail-closed indefinitely. This is
# the one case in this suite that should NEVER start passing.
result=$(run_hook 'cd '"$WT"' && W=$PWD && D=$W/.scratch-issue78/verify-rerun && rm -rf "$D"' "$TMPROOT")
assert_deny_unresolved_var \
    "(2) #151 instance 2: \$W=\$PWD chain -> still deny (genuinely dynamic, no refinement proposed, must never change)" \
    "$result"

# --- Instance 3 (issue #151) -- "POSSIBLY REFINABLE": a literal prefix
# unconditionally rooted at /tmp (already an always-in-scope directory for
# the mktemp fast path's own reasoning) with a trailing unresolved
# expansion. rm_scope_literal_same_command_resolve() rejects it because the
# RHS contains "$" at all (point 2's pure-literal test has no "literal
# prefix, opaque suffix" case, unlike the reattachment logic for the mirror
# shape "$NAME<literal-suffix>"). #151 flags this as a candidate for a
# narrow upstream fast path -- not implemented here.
result=$(run_hook 'for C in 5b7f282 9118550; do D=/tmp/gbisect-$C; rm -rf $D; done' "$TMPROOT")
assert_deny_unresolved_var \
    "(3) #151 instance 3: /tmp-rooted literal prefix + unresolved suffix (/tmp/gbisect-\$C) -> still deny (upstream refinement candidate, not implemented here)" \
    "$result"

# --- Contrast/control: the single-hop literal shape the guard ALREADY
# resolves today (rm_scope_literal_same_command_resolve(), #6676/#6805) --
# asserted here so a reader can see exactly where the existing fast path's
# boundary sits relative to instance 1's two-hop chain above. NOT part of
# #151's findings; a pre-existing capability, included only for contrast.
result=$(run_hook 'WT="'"$WT"'"; rm -rf "$WT/.scratch-issue78"' "$TMPROOT")
assert_allow \
    "(control) single-hop literal var (WT=<literal>; rm -rf \"\$WT/lit\") already resolves -> allow (contrast with instance 1's two-hop chain)" \
    "$result"

echo "=== $PASS/$TOTAL passed ==="
[[ "$FAIL" -eq 0 ]]
