#!/usr/bin/env bash
# usage: cc.sh <cand>  -- run verification/cross_check.py against .scratch/cand/<cand>.v
set -euo pipefail
W=/home/ubuntu/GitHub/sky130-modexp/.loom/worktrees/issue-234
D=$W/.scratch/cc_$1
mkdir -p "$D/rtl"
cp "$W/.scratch/cand/$1.v" "$D/rtl/modexp.v"
ln -sfn "$W/.venv" "$D/.venv"
cd "$W"
REPO_ROOT=$D "$W/.venv/bin/python3" verification/cross_check.py 2>&1 | tail -6
