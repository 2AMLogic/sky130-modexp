# Synthesis baseline

**Status: measured, 2026-08-04.** This is the number every later optimization
claim is measured against. It was produced in `2AMLogic/klayout-tools`
(PR #488) before this repo existed; the RTL and testbench migrate here under
issue #2, and this document is the record that travels with them.

## The measurement

`klt synthesize` (Yosys 0.67+post) against
`sky130_fd_sc_hd` / `tt_025C_1v80`, with `sky130A` fetched via `volare`.
`instance_count` is the post-`abc` mapped standard-cell count.

| Design | `WIDTH` | sky130 cells |
| --- | --- | --- |
| `modexp.v` — square-and-multiply over one shared Blakley modular multiplier | 16 | **682** |
| `gcd.v` — minimal iterative-subtractor GCD (a separate, much smaller design) | 16 | 384 |

A behavioral naive variant (unrolled multiply with a runtime-modulus divider
per step) was also measured and did not finish `abc` mapping within 120 s —
a different regime entirely, and the one that reaches thousands of cells.

Correctness at the time of measurement: `test_modexp.py` passes 2/2 through
`klt functional-verification`, and `modexp.v` is bit-exact against Python
`pow(base, exp, mod)` across `WIDTH` = 4, 6, 8, 16 at 500 random cases each,
0 mismatches, via a deterministic Icarus cross-check outside the cocotb
harness.

## Reproducing it

```bash
# 682 cells for modexp, 384 for gcd
for src in gcd modexp; do
  tmp=$(mktemp -d); cp rtl/$src.v "$tmp/"
  cat > "$tmp/req.json" <<JSON
{ "schema": "klt.synthesize.request/1", "engine": "yosys",
  "sources": ["$src.v"], "hdl_toplevel": "$src",
  "pdk": { "cell_library": "sky130_fd_sc_hd", "corner": "tt_025C_1v80" },
  "constraints": { "clock_period_ns": null } }
JSON
  ( cd "$tmp" && PDK=sky130A klt synthesize req.json --format json ) \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["instance_count"])'
done

# bit-exact functional verification
klt functional-verification verification/request-modexp.json --format json
```

## Why the external comparison is not a comparison

The task was chosen after Alibaba's Qwen3.8-Max post
([2026-08-02](https://qwen.ai/blog?id=qwen3.8)) reported an agent optimizing
a GCD/RSA modexp accelerator from 8,298 to 678 Yosys cells over ~500 turns,
on a comparable open stack (cocotb / Icarus / Yosys / OpenROAD) — but against
**Nangate45**.

Yosys cell counts are standard-cell-library dependent. A sky130 count and a
Nangate45 count are not the same measurement, so **682 and 678 cannot be
compared in either direction.** We did not beat 678, we do not claim to have,
and our proximity to it is not evidence that their optimization was small.
Nothing in this repo or derived from it may state or imply otherwise.

## The structural finding, which is real

A naturally-written correct core lands near their *optimized* scale, not
their *starting* scale. Their 8,298 figure therefore describes a deliberately
un-optimized starting RTL rather than a natural implementation — plausibly
behavioral, divider-based, and unrolled, the regime the naive variant above
reaches.

That starting RTL was not published ("no golden reference design"), so its
microarchitecture — algorithm variant, datapath width, degree of unrolling,
whether it is a combined GCD+RSA block — is not recoverable. Reconstructing
it would mean writing intentionally bloated RTL tuned to a number that is not
comparable to ours anyway.

## What this repo does instead (operator ruling, 2026-08-04)

Recreating an artificial ~8k-cell starting point to harvest a large reduction
ratio was considered and rejected: manufacturing the hole we then climb out of
is a rigged demo, and a fragile one, since any reconstruction is a guess at
someone else's handicap.

So the program is:

- **Phase 2** — micro-optimization from the 682-cell core, correctness held
  by the bit-exact suite on every commit. Area and timing gains are reported
  against our own baseline, which is the only honest denominator available.
- **Phase 3** — place-and-route through OpenROAD and a DRC/LVS-clean gate on
  the produced GDS. sky130 makes this meaningful in a way Nangate45 could
  not: a real PDK has a real rule deck, and the resulting block is eligible
  to progress up the maturity ladder.

The load-bearing argument was never the external number. It is that a
mixed-signal design system requires a digital flow underneath it, which makes
this block a prerequisite rather than a detour.
