#!/usr/bin/env bash
# Build and run the issue-#280 cycle-counting testbench with Icarus. Prints one
# ROW per case and a RESULT line; exits nonzero unless RESULT is PASS.
# Usage: verification/cycle-price/run.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -o "$out/sim" "$repo/rtl/modexp.v" \
  "$here/schedule_model.v" "$here/cycle_price_tb.v"
vvp "$out/sim" | tee "$out/log"
grep -q '^RESULT: PASS' "$out/log"
