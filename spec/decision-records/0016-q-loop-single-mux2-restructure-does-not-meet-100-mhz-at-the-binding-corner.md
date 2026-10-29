# 0016: The q-loop single-mux2 restructure does not meet 100 MHz at the binding corner; probe (b) fails

- **Status**: proposed
- **Date**: 2026-10-29
- **Decided by**: Builder finding on issue #271 against the operator's
  2026-10-29 ruling ("try (b), then (c) if it fails"). Ratification is pending
  the two-key step, not a direct status flip. This record changes no spec row.

## Context

Record `0015` named one unmeasured lever: form the q-independent part
A = S1^C1^(S0|C0)^x_r first, then select q' = q ? (A^v1) : (A^u1), leaving one
mux2 on the q loop. The operator ruled this probe (b) is run once and succeeds
only if the kernel is arithmetically correct and has **positive** WNS at
`ss_n40C_1v28` at 10 ns, surviving a rerun. Measured as a single-corner `klt
sta` run (klt 0.8.0), record
`verification/records/sta-corner-sweep/records/20261029-040000-cf81741.md`.

| kernel | WNS (ns) | f_max (MHz) | self-check |
| --- | --- | --- | --- |
| P8 (best prior working kernel) | -1.764 | 85.00 | 0 errors |
| P12 q-loop single mux2 (P8 form) | -4.081 | 71.02 | 0 errors (W=8, 16) |

## Decision

> **Probe (b) fails its pass test.** P12 is arithmetically correct but WNS is
> -4.081 ns (identical on rerun), 2.3 ns worse than P8. Per the ruling, no
> further lever is probed. T1 item 5 stays `unmet`, DR-0004's disclosed
> exception stands, and the 100 MHz target and 18-corner matrix are untouched.
> The ruling's branch (c) applies: a new issue proposes the pipelined column
> halves (DR-0014 candidate 2) with a priced supersession of record `0001`
> Decision 3, through the two-key step. This record proposes no spec change.

Findings that carry forward:

1. **Taking q out of the cone does not take depth out of the path.** The worst
   path is the q-independent cone (`maj3` 3.06 ns, `xor3` 3.49 ns) feeding the
   select mux (2.53 ns). The restructure moved the depth in front of the mux
   rather than removing it.
2. **The build was the P8 form.** The `b+m` (P11) form was not used; it carries
   the `WIDTH/2 + 1` cycle price of record `0015` and P8 could host the select.
3. Seven-plus kernel variants (P4-P12) land between 62 and 86 MHz at this
   corner; the radix-2 carry-save recurrence as a single-cycle kernel does not
   reach 10 ns here.

## Alternatives considered

- **Probe more q-loop variants** -- ruled out by the operator ("no other lever
  hunt").
- **Build the complete design anyway** -- no working kernel reaches 10 ns.
- **Lower 100 MHz or drop corners** -- ruled out (records `0004`, `0007`).

## Consequences

- Good: the last unmeasured single-cycle lever in the DR-0015 list is closed
  with a measurement; the route decision is now only the pipelined halves or
  the disclosed FAIL.
- Bad: item 5 remains `unmet`; still no all-corner 100 MHz configuration.
- Limitation: one probe form and one placer seed; differences under ~1 ns are
  within noise, but this miss is ~4 ns.
