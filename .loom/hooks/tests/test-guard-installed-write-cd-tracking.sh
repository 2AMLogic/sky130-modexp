#!/usr/bin/env bash
# Regression tests for sky130-modexp #158: the loom:installed-file-write Bash
# guard in .loom/hooks/guard-loom-workflow.sh must resolve a relative write
# target against a preceding same-command `cd` (mktemp scratch dir), while real
# writes into the actual installed .loom/ tree stay denied.
#
# Usage: ./.loom/hooks/tests/test-guard-installed-write-cd-tracking.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PASS=0; FAIL=0
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
git init -q "$TMPROOT"
mkdir -p "$TMPROOT/.loom/hooks" "$TMPROOT/.loom/scripts/lib"
echo '{}' > "$TMPROOT/.loom/install-metadata.json"   # consumer marker
cp "$REPO_ROOT/.loom/hooks/guard-loom-workflow.sh" "$TMPROOT/.loom/hooks/"
cp "$REPO_ROOT/.loom/scripts/lib/"*.sh "$TMPROOT/.loom/scripts/lib/"
HOOK="$TMPROOT/.loom/hooks/guard-loom-workflow.sh"

decision() {
    local cmd="$1" out
    out=$(cd "$TMPROOT" && jq -n --arg c "$cmd" --arg d "$TMPROOT" '{tool_input:{command:$c},cwd:$d}' \
        | bash "$HOOK" 2>/dev/null) || true
    if [[ "$out" == *'"deny"'* ]]; then echo deny; else echo allow; fi
}
check() {
    local want="$1" desc="$2" cmd="$3" got
    got=$(decision "$cmd")
    if [[ "$got" == "$want" ]]; then PASS=$((PASS+1)); echo "PASS $desc"
    else FAIL=$((FAIL+1)); echo "FAIL $desc (want $want, got $got)"; fi
}

# Allowed: scratch tree's own .loom/ subtree, reached by the exact fail-closed
# idiom `VAR=$(mktemp -d) && ... && cd $VAR && <writes>`.
check allow "mktemp var + cd, relative redirect" \
  'T=$(mktemp -d) && mkdir -p $T/.loom/scripts/tests && cd $T && printf x > .loom/scripts/tests/ci-excluded.txt'
check allow "mktemp var + quoted cd, cp dest" \
  'T=$(mktemp -d) && cd "$T" && cp a .loom/scripts/x.sh'
check allow "mktemp var + braced cd, tee dest" \
  'T=$(mktemp -d) && cd ${T} && printf x | tee .loom/scripts/x.sh'

# Still denied: real installed tree.
check deny  "no cd, relative write to real tree" 'printf x > .loom/scripts/x.sh'
check deny  "absolute write to real tree" "printf x > $TMPROOT/.loom/scripts/x.sh"
check deny  "cd into real repo then write" "cd $TMPROOT && printf x > .loom/scripts/x.sh"
check deny  "mktemp var but cd elsewhere (unresolved var)" 'T=$(mktemp -d) && cd "$OTHER" && printf x > .loom/scripts/x.sh'
check deny  "write BEFORE cd into scratch" 'T=$(mktemp -d) && printf x > .loom/scripts/x.sh && cd $T'
check deny  "cd in subshell does not affect later write" 'T=$(mktemp -d) && (cd $T && true) && printf x > .loom/scripts/x.sh'
check deny  "cd inside later-closed subshell" 'T=$(mktemp -d); (true; cd $T); printf x > .loom/scripts/x.sh'
check deny  "multiple cds fall back to CWD" 'T=$(mktemp -d) && cd $T && cd .. && printf x > .loom/scripts/x.sh'
check deny  "cd var not from mktemp" 'T=/somewhere && cd $T && printf x > .loom/scripts/x.sh'
check deny  "relative write before cd still checked against CWD" \
  'T=$(mktemp -d) && mkdir -p $T/x && printf y > .loom/scripts/y.sh && cd $T && printf x > a.txt'

# Adversarial (PR #159 review): each of these lands a real write in the
# installed tree if the cd is trusted, so each must fail closed.
check deny  "ADV1 reassignment after mktemp" \
  "T=\$(mktemp -d); T=$TMPROOT; cd \$T; printf x > .loom/scripts/x.sh"
check deny  "ADV1 reassignment after mktemp, &&-chained" \
  "T=\$(mktemp -d) && T=$TMPROOT && cd \$T && printf x > .loom/scripts/x.sh"
check deny  "ADV1 read into var after mktemp" \
  "T=\$(mktemp -d) && read -r T <<< $TMPROOT && cd \$T && printf x > .loom/scripts/x.sh"
check deny  "ADV1 export-masked mktemp failure" \
  'export T=$(mktemp -d) && cd $T && printf x > .loom/scripts/x.sh'
check deny  "ADV2 mktemp -p aimed at repo" \
  "T=\$(mktemp -d -p $TMPROOT); cd \$T; printf x > .loom/scripts/x.sh"
check deny  "ADV2 mktemp -p aimed at repo, &&-chained" \
  "T=\$(mktemp -d -p $TMPROOT) && cd \$T && printf x > .loom/scripts/x.sh"
check deny  "ADV2 mktemp --tmpdir= aimed at repo" \
  "T=\$(mktemp -d --tmpdir=$TMPROOT) && cd \$T && printf x > .loom/scripts/x.sh"
check deny  "ADV2 mktemp template" \
  "T=\$(mktemp -d $TMPROOT/XXXX) && cd \$T && printf x > .loom/scripts/x.sh"
check deny  "ADV3 failed literal cd" 'cd /nonexistent; printf x > .loom/scripts/x.sh'
check deny  "ADV3 literal cd even when &&-chained (literal paths not honored)" \
  'cd /tmp/loom-scratch-158 && printf x > .loom/scripts/x.sh'
check deny  "ADV3 mktemp var cd then ; write" 'T=$(mktemp -d) && cd $T; printf x > .loom/scripts/x.sh'
check deny  "ADV3 mktemp ; then cd (mktemp failure falls through)" \
  'T=$(mktemp -d); cd $T && printf x > .loom/scripts/x.sh'
check deny  "ADV4 failed literal cd || true" 'cd /tmp/nope || true; printf x > .loom/scripts/x.sh'
check deny  "ADV4 mktemp var cd || true" 'T=$(mktemp -d) && cd $T || true && printf x > .loom/scripts/x.sh'
check deny  "ADV4 cd && x || write" 'T=$(mktemp -d) && cd $T && true || printf x > .loom/scripts/x.sh'
check deny  "cd then background & then write" 'T=$(mktemp -d) && cd $T & printf x > .loom/scripts/x.sh'
check deny  "symlink into repo inside scratch" \
  "T=\$(mktemp -d) && ln -s $TMPROOT/.loom \$T/.loom && cd \$T && printf x > .loom/scripts/x.sh"
check deny  "pushd back to repo after cd" \
  "T=\$(mktemp -d) && cd \$T && pushd $TMPROOT && printf x > .loom/scripts/x.sh"
check deny  "dot-dot escape from scratch" \
  "T=\$(mktemp -d) && cd \$T && printf x > ../../../../../../../../..$TMPROOT/.loom/scripts/x.sh"

echo "passed=$PASS failed=$FAIL"
[[ $FAIL -eq 0 ]]
