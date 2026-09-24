#!/usr/bin/env bash
# Regression evidence for the 3 `rm-scope-unresolved-var` deny events
# reported in issue #151 (Guard-Decision Telemetry Review, standing policy
# #3898), against `rm_scope_literal_same_command_resolve()` /
# `rm_scope_mktemp_same_command_safe()` in the vendored
# `.loom/hooks/guard-destructive-generic.sh`.
#
# DISPOSITION of #151's three reported instances (this suite covers all three,
# and the safety boundary around the one that changed):
#   - Instance 1 (one-hop literal var chain) -- REFINED. The guard now
#     resolves `NAME2="$NAME1<literal-suffix>"` one hop when NAME1 is itself
#     same-command-pure-literal-resolvable, then applies the ORDINARY scope
#     rules to the result. Asserted ALLOW below, together with the negative
#     cases that prove the hop is a false-positive refinement and not a
#     relaxation (out-of-scope resolution still denies, ambiguous/dynamic/
#     single-quoted/self-referential/too-deep chains all still deny).
#   - Instance 2 ($PWD chain) -- UNCHANGED, denied. Genuinely dynamic: the
#     value depends on runtime cwd the guard cannot observe from command text.
#     #151 explicitly proposes no refinement. This must NEVER start passing.
#   - Instance 3 (/tmp-rooted literal prefix + unresolved suffix,
#     `D=/tmp/x-$C`) -- UNCHANGED, denied, and deliberately NOT refined.
#     #151 floated it on the grounds that a `/tmp`-rooted prefix is always in
#     scope, but that does not hold: an unresolved suffix can contain `..`
#     (`C=../../etc` => `/tmp/x-../../etc` => `/etc`), and unlike a literal
#     suffix the guard cannot see the text to normalize it. Allowing it would
#     be a relaxation of the scope rule, not a false-positive refinement.
#     Asserted DENY below, with the traversal case that shows why.
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

# Denied, but deliberately NOT via rm-scope-unresolved-var -- used for the
# cases that must be caught by the ORDINARY scope check after a successful
# resolution, which is what distinguishes a refinement from a relaxation.
assert_deny() {
    local desc="$1" result="$2"
    if [[ "${result%%|*}" != "deny" ]]; then
        fail "$desc (expected deny, got: $result)"
        return
    fi
    local reason="${result#*|}"
    if [[ "$reason" == *"unexpanded shell variable"* ]]; then
        fail "$desc (denied as UNRESOLVED rather than by the scope check: $reason)"
    else
        pass "$desc"
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

# --- Instance 1 (issue #151) -- REFINED: a one-hop literal variable chain.
# REPO is itself a same-command pure-literal assignment; WORK's RHS embeds
# "$REPO" rather than being a pure literal, which the original #6676 point-2
# test rejected. rm_scope_literal_same_command_resolve() now takes exactly one
# extra hop, resolves this to <WT>/.scratch-issue78, and hands THAT to the
# ordinary scope check (which admits it: it is inside a managed worktree).
result=$(run_hook 'REPO="'"$WT"'"; WORK="$REPO/.scratch-issue78"; rm -rf "$WORK"' "$TMPROOT")
assert_allow \
    "(1) #151 instance 1: one-hop literal var chain (REPO -> WORK=\"\$REPO/lit\") -> resolves, in scope, allow" \
    "$result"

# The live second sighting of the same shape, from this repo's own
# .loom/logs/guard-decisions.log on 2026-09-24 (an evidence-staging script:
# W=<worktree literal>; S="$W/.klt/..."; rm -rf "$S"), with the ${NAME} brace
# spelling and an unquoted target to cover the other quoting paths.
result=$(run_hook 'W='"$WT"'
S="$W/.klt/issue143-synth"
rm -rf ${S}' "$TMPROOT")
assert_allow \
    "(1b) #151 instance 1, live repro: newline-separated chain, \${S} brace spelling, unquoted target -> allow" \
    "$result"

# --- The hop is a FALSE-POSITIVE refinement, not a relaxation: a chain that
# resolves OUTSIDE the repo/worktree/tmp scope is still denied, by the ordinary
# out-of-scope check rather than by fail-closed unresolvability. This is the
# single most important assertion in this suite -- it is what proves the hop
# only ever moves a target from "cannot resolve" to "judged normally".
result=$(run_hook 'R=/etc; W="$R/nginx"; rm -rf "$W"' "$TMPROOT")
assert_deny \
    "(1c) chain resolving out of scope (R=/etc; W=\"\$R/nginx\") -> still denied by the ordinary scope check" \
    "$result"

# ...and `..` inside the literal suffix is COLLAPSED by the caller's
# normalize_abs_path() before that scope check, so the suffix cannot be used to
# dress an out-of-scope destination up as an in-scope-looking path. Anchored at
# a fixed absolute path rather than at $WT on purpose: the hermetic test repo
# lives under /tmp, which is itself in scope (the ephemeral allowlist), so a
# traversal test rooted there would depend on mktemp's directory depth.
result=$(run_hook 'R=/etc/nginx/conf.d; W="$R/../../sites-enabled"; rm -rf "$W"' "$TMPROOT")
assert_deny \
    "(1d) .. in the literal suffix is normalized (/etc/nginx/sites-enabled), then denied by the scope check" \
    "$result"

# --- Fail-closed conditions on the hop (block-comment conditions (a)-(d)).
# (a) depth cap: three assignments deep is one hop too many.
result=$(run_hook 'A="'"$WT"'"; B="$A/x"; C="$B/y"; rm -rf "$C"' "$TMPROOT")
assert_deny_unresolved_var \
    "(1e) three-deep chain exceeds the one-hop cap -> still deny (fail closed)" \
    "$result"

# (b) ambiguity: a second assignment to the INNER name poisons the resolution
# even though each individual value would be admissible on its own.
result=$(run_hook 'R="'"$WT"'"; R=/etc; W="$R/x"; rm -rf "$W"' "$TMPROOT")
assert_deny_unresolved_var \
    "(1f) two assignments to the inner var -> ambiguous, still deny (fail closed)" \
    "$result"

# (c) the outer RHS single-quoted as a whole: `$R` is literal text there, so
# the shell deletes a RELATIVE path named "\$R/x" -- following it as a variable
# would be a mis-resolution, so the hop declines.
result=$(run_hook 'R="'"$WT"'"; W='"'"'$R/x'"'"'; rm -rf "$W"' "$TMPROOT")
assert_deny_unresolved_var \
    "(1g) outer RHS wholly single-quoted (W='\$R/x') -> not an expansion, still deny (fail closed)" \
    "$result"

# (d) self-referential append: the exactly-one rule makes this the only
# assignment to W, so the \$W on its own RHS is inherited from OUTSIDE the
# command -- precisely the unresolvable case this deny exists for.
result=$(run_hook 'W="$W/.scratch"; rm -rf "$W"' "$TMPROOT")
assert_deny_unresolved_var \
    "(1h) self-referential chain (W=\"\$W/.scratch\") -> inherited value, still deny (fail closed)" \
    "$result"

# The inner hop must resolve to a LITERAL absolute path -- a command
# substitution one hop in is not static text and must not be followed.
result=$(run_hook 'R=$(cat /tmp/where); W="$R/x"; rm -rf "$W"' "$TMPROOT")
assert_deny_unresolved_var \
    "(1i) inner hop is a command substitution -> not provably static, still deny (fail closed)" \
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

# --- Instance 3 (issue #151) -- reported as "POSSIBLY REFINABLE" on the
# grounds that the literal prefix is unconditionally /tmp-rooted and /tmp is
# always in scope. DELIBERATELY NOT REFINED: that reasoning does not hold,
# because the UNRESOLVED suffix can traverse back out of /tmp and the guard
# cannot see the text to normalize it (see the next case). Note the target
# here is `$D` from the path root down but the ASSIGNMENT's RHS carries the
# unresolved expansion -- so neither the pure-literal test nor the one-hop
# chain admits it, and it correctly stays fail-closed.
result=$(run_hook 'for C in 5b7f282 9118550; do D=/tmp/gbisect-$C; rm -rf $D; done' "$TMPROOT")
assert_deny_unresolved_var \
    "(3) #151 instance 3: /tmp-rooted literal prefix + unresolved suffix (/tmp/gbisect-\$C) -> still deny (refinement rejected as a relaxation)" \
    "$result"

# Why instance 3 must stay denied, made concrete: the very same shape with a
# traversing value escapes /tmp entirely. The guard cannot distinguish this
# command's text from the benign one above, which is exactly why "the prefix
# is /tmp-rooted" proves nothing about where the rm lands.
result=$(run_hook 'C=../../etc; D=/tmp/gbisect-$C; rm -rf $D' "$TMPROOT")
assert_deny_unresolved_var \
    "(3b) same shape, traversing suffix (C=../../etc => /etc) -> deny; demonstrates why /tmp-rootedness is not sufficient" \
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
