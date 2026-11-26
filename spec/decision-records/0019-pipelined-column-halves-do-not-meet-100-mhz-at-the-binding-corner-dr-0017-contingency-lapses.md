# 0019: Pipelined column halves do not meet 100 MHz at the binding corner; the DR-0017 contingent supersession lapses

- **Status**: proposed
- **Date**: 2026-11-26
- **Decided by**: Builder finding on issue #446 (the probe DR-0017 required
  before any production RTL change). Ratification is pending the two-key step,
  not a direct status flip. This record edits no spec text, and does not edit
  record `0017`; `spec/modexp.md` and record `0001` are unchanged.

## Context

DR-0017 priced the two pipelined column halves of DR-0014 candidate 2 at two
cycles per Montgomery iteration and made the supersession of record `0001`
Decision 3's latency paragraph contingent on a pipelined-halves RTL change that
clears its gates. It stated plainly that "nothing here was probed" and required
a single-corner probe at `ss_n40C_1v28` first. That probe was run once the
experiment had an owner (#446), as a single-corner `klt sta` (klt 0.8.0) on the
probe's own routed DEF at 10.0 ns, record
`verification/records/sta-corner-sweep/records/20261126-100000-da6f07e.md`.
Both kernels are arithmetically correct (0 mismatches over 2000 odd-modulus
cases at each of `WIDTH` 4, 6, 8, 16, both quotient-bit values and carries
across the cut exercised) and each result reproduces exactly on rerun.

| kernel | WNS (ns) | f_max (MHz) | hold slack (ns) |
| --- | --- | --- | --- |
| P12 (best single-cycle probe in DR-0016) | -4.081 | 71.02 | +2.496 |
| P13 column halves, one shared phase flop | -5.033 | 66.52 | +2.506 |
| P13b column halves, replicated phase control | -1.006 | 90.86 | +2.585 |

P13's miss is dominated by control fanout (one phase flop decoded into every
enable, ~8.9 ns). P13b removes that artifact and still misses: its worst path is
`xor3 -> xor2 -> xnor2 -> a22o` inside a single column, the two chained 3:2
levels, which a register between column groups does not shorten.

## Decision

> **The column-halves probe fails its pass test.** The kernel is correct and
> setup WNS at `ss_n40C_1v28` is -1.006 ns at best (identical on rerun), against
> a pass that needs nonnegative setup and hold slack at 10 ns. Therefore:
>
> - DR-0017's **contingent supersession of record `0001` Decision 3 lapses** for
>   the two-pipelined-column-halves cut: its condition (a pipelined-halves RTL
>   change that clears the gates) cannot hold when the probe misses the clock.
>   Record `0001` stays in force **unamended**; the `cycles_2` formula and
>   tables remain a stated price only, with no design built to them.
> - T1 item 5 remains `unmet`, DR-0004's disclosed exception stands, and the
>   100 MHz target and 18-corner matrix are unchanged (DR-0004/0007).
> - No production RTL issue is opened for column halves (the pass branch of the
>   probe is not taken).

This is stated for the one cut probed (`H = N/2` at `WIDTH=16`) and the two
control forms above. It is not a claim about every `h`.

## Not claimed

- **That no two-cycle iteration can close 100 MHz.** The *level* cut (a register
  between the two 3:2 levels), which DR-0017 prices at the same `K = 2`, was not
  probed; it is a different candidate from the one this decision covers.
  Whether to probe it is an operator decision and is not pre-empted here.
- Any throughput or MHz claim for a pipelined design, or any comparison to an
  external lab's figure (overclaim trap).
- A full-design result: no cocotb suite, cycle count or 18-corner sweep exists
  for these probe kernels.

## Alternatives considered

- **Leave DR-0017's contingency open** -- rejected: its only stated route to
  ratification is a design that does not exist and whose probe misses the clock;
  leaving it open implies a path the measurement does not support.
- **Edit DR-0017 in place** -- rejected: ratified text is not rewritten; a new
  record cites and extends it.
- **Sweep more cuts `h`** -- not run: the binding path (P13b) is inside one
  column, so moving the column cut does not change it.
- **Lower 100 MHz or drop corners** -- ruled out (records `0004`, `0007`).

## Consequences

- Good: the deferred DR-0017 experiment now has a measured answer with an
  owner, and the lapse is recorded rather than implied.
- Bad: item 5 remains `unmet`; still no all-corner 100 MHz configuration.
- Limitation: one cut, one placer seed, one `WIDTH`; differences under ~1 ns are
  within noise, and P13b's -1.0 ns is near that band, but P13's miss is ~5 ns
  and neither probe reaches zero.
