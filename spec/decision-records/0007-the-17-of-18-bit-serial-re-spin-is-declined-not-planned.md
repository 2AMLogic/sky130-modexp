# 0007: The 17/18 bit-serial re-spin is declined ("not planned"); the search for an all-corner design without the throughput loss stays open

- **Status**: proposed
- **Date**: 2026-10-02
- **Decided by**: Operator ruling on issue #144 (2026-10-02), recorded by
  Builder. Ratification is pending the two-key step: the `2am` repo's
  `scripts/ratify-key.sh` (2am#1056), not a direct status flip.

## Context

Record `0005` Decision 1 recorded the bit-serial re-spin (issue #141, PR
#145) as a **17 of 18** result and declined to commit it on the Builder's
own authority, because the price record `0004` Decision 2 enumerated was
quoted against closure and closure did not arrive. Issue #144 exists so
that call is revisitable with the numbers visible rather than settled by
omission. Its premise-check, the Yosys/ABC pin (issue #143, PR #147), has
since landed, and PR #147's evidence re-ran the frozen re-spin synthesis
request at the pinned mapper: **1105 mapped instances, byte-identical
across four runs**. The 17/18 result is therefore stable under the pin,
not a mapper-nondeterminism artifact. Nothing remains to wait for.

**Operator ruling, issue #144 comment by `rjwalters`, 2026-10-02:**
"Record 'not planned'. The bit-serial re-spin is not landed: its ~8x
throughput loss still doesn't reach 18/18 closure. Lowering the 100 MHz
target or dropping corners stays ruled out." The agent work is this
decision record, with the search for a design that closes every corner
without the throughput loss kept open.

All numbers below are the issue #144 trade table, measured by issue #141 /
PR #145 and frozen as
`verification/records/sta-corner-sweep/records/20260924-134500-1a8313b.md`.
None is a target or projection, and no external library's or lab's figure
is referenced or compared against, per `CLAUDE.md`'s overclaim-trap
section.

| | committed layout | re-spun configuration |
| --- | --- | --- |
| mapped instances | 682 | **1105** (+423) |
| cycles @ `WIDTH=16`, all-ones exponent | 595 | **19539** (about 33x) |
| `klt sta` @ `ss_n40C_1v28` | -33.867 ns / **22.80 MHz** | -0.574 ns / **94.57 MHz** |
| in-flow P&R STA @ same corner | n/a | -1.160 ns / 89.60 MHz |
| corners closed (setup and hold) | **10/18** | **17/18** |
| net throughput | baseline | **about 8x worse** (4.15x clock against about 33x cycles) |

## Decision

> **The bit-serial 17/18 re-spin is not landed. Issue #144 is recorded as
> "not planned."** The re-spin buys 10/18 to 17/18 at a net throughput loss
> of about 8x and still fails at the same binding corner, `ss_n40C_1v28`.
> That is not worth its price: it is a closure result that is not a closure
> result, and the cost is paid in the one metric (throughput) the block
> exists to serve.
>
> **Unchanged by this record**, stated explicitly:
>
> - Record `0001` Decision 3's latency formula,
>   `cycles(WIDTH, exp_in) = WIDTH*(WIDTH + 3) + popcount(exp_in)*(WIDTH + 2) + 2`,
>   **remains ratified and unamended** (as record `0005` Decision 2 left
>   it). The bit-serial formula stays measured, unratified,
>   candidate-scoped detail; no supersession is spent.
> - `rtl/modexp.v`, `flow/synthesize-modexp.json`, `flow/par-modexp.json`,
>   `layout/*`, and `scripts/setup-env.sh`'s `KLT_REV` are unchanged. All T1
>   evidence is unchanged; no T1 row changes state in either direction.
>   Record `0004` Decision 1's disclosed T1 item 5 exception stands
>   verbatim (10 of 18, `ss_n40C_1v28` at 22.80 MHz, hold clean).
> - **The 100 MHz target is not lowered and the eighteen-corner matrix of
>   record `0001` Decision 4 is not narrowed** (record `0004` Decision
>   1(b), restated by record `0005` Decision 1). 94.57 MHz at seventeen
>   corners is a measurement, not a new target.
> - Per record `0002` Decision 1, no claim may say this block "closes
>   100 MHz" without naming the corner set.
>
> **The search stays open.** Finding a design that closes every ratified
> corner without this throughput loss remains the goal. This record
> declines one candidate; it does not close the question.

## Alternatives considered

- **Land the re-spin (issue #144's default path)** — bit-serial RTL,
  `constraints.dont_use` flow requests, `KLT_REV` bump, superseding record
  for `0001` Decision 3, and a re-mint of T1 items 3, 4, 7 and 11 (item 7,
  gate-level simulation, about 33x longer). Not chosen: a large, costly
  change set for a still-failing, 8x-slower result.
- **Land it as the new, lower target (94.57 MHz, 17 corners)** — ruled out
  by the operator and by `CLAUDE.md`: agents do not relax the ratified spec
  to make results pass.
- **Defer without a record** — not chosen: this is the settle-by-omission
  outcome the issue was filed to avoid.

## Consequences

- The shipped evidence state is exactly what it was before; nothing
  regressed and nothing new is claimed.
- Bad consequence, stated plainly: the program still has no demonstrated
  all-corner 100 MHz configuration, only a reproducible near-miss
  (17/18, -0.574 ns) that is declined, and the committed layout's 10/18
  disclosed FAIL continues.
- The frozen candidate, requests and patch under
  `verification/records/sta-corner-sweep/` remain available as evidence for
  any future attempt; this record does not touch them.
- Issues #141, #143 and #145/#147 are cross-referenced: #141 (closed, not
  planned), #143/PR #147 (mapper pin, confirmed 1105 instances stable),
  PR #145 (evidence run).
- Ratification is pending the two-key step via `2am`
  `scripts/ratify-key.sh`; until then this record is `proposed`.
