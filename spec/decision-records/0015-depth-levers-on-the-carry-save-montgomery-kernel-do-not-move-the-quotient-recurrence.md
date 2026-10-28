# 0015: Logic-depth levers on the carry-save Montgomery kernel do not close the binding corner; the quotient recurrence binds

- **Status**: proposed
- **Date**: 2026-10-28
- **Decided by**: Builder finding on issue #271, recorded for the operator.
  Ratification is pending the two-key step, not a direct status flip. This
  record changes no spec row.

## Context

Record `0014` left logic depth per cycle as the open lever for T1 item 5 and
named three candidates. Two were probed here, as single-corner `klt sta` kernel
runs at `ss_n40C_1v28` (10 ns period, klt 0.8.0), per
`verification/records/sta-corner-sweep/records/20261028-220000-c681034.md`.
The pipelined-halves candidate (it changes cycles per multiply and needs a
priced supersession of record `0001` Decision 3) was not probed. No external
figure is referenced.

| kernel | WNS (ns) | f_max (MHz) |
| --- | --- | --- |
| P8 (record 0014, best working kernel) | -1.764 | 85.00 |
| P10 4:2 compressor datapath | -1.803 | 84.73 |
| P11b one 3:2 level, `b+m` added 2 bits/cycle over `WIDTH/2` prep cycles | -1.875 | 84.21 |
| P11c P11b with four q copies | -1.854 | 84.36 |
| (P11a, `b+m` in one cycle: -13.845, the adder, not the kernel) | | |

## Decision

> **Neither depth lever reaches 100 MHz at `ss_n40C_1v28`.** The best new
> working kernel (P10, 84.73 MHz, reproduced identically and across a second
> placer seed) misses by 1.803 ns and is within noise of P8. No working kernel
> is within ~1 ns of 10 ns, so the stop rule of the issue applies: the complete
> datapath is **not** built, T1 item 5 stays `unmet`, and DR-0004's disclosed
> exception stands. The 100 MHz target and 18-corner matrix are untouched; no
> supersession of record `0001` Decision 3 is proposed.

Findings that carry forward:

1. **The binding endpoints are the quotient copies, not the datapath.** In P8,
   P10 and P11c the worst endpoints are the q flops (-1.1 to -1.9 ns); the S/C
   endpoints are 0.6 to 1.1 ns behind them. A shallower datapath therefore
   cannot move the result by itself, which is why removing a 3:2 level (P11c)
   and restructuring it (P10) both left WNS where P8 had it.
2. **The recoding that removes a 3:2 level has a cycle price.** Forming `b+m`
   needs a carry-propagate add per Montgomery product; one cycle is 22 ns
   (P11a), and 2 bits per cycle (the widest that fit) costs `WIDTH/2 + 1`
   extra cycles per product. Even if its kernel had closed, it would not have
   been a "no throughput loss" design.
3. **Copy-flop kind is not the limit.** Removing the async-set q copies moved
   WNS by 0.02 ns (P11b -> P11c).

## Next lever and the operator's choice

This record asks the operator to choose the route for item 5 rather than open
another probe hunt. The options, best first by what the evidence supports:

1. **Leave item 5 as the disclosed FAIL (DR-0004).** Seven kernel variants
   (P4-P11c) across records `0011`, `0013`, `0014` and this one land between
   62 and 86 MHz; none has margin above the noise floor at 100 MHz.
2. **Probe the q-loop restructure (one more single-corner run, cheap).**
   q' = S1^C1^add1^(S0|C0)^x_r, and add1 depends on q only through a 2:1
   select. Forming A = S1^C1^(S0|C0)^x_r first and then q' = q ? (A^v1) : (A^u1)
   leaves a single mux2 on the q loop. **Not measured, and P9's lower bound
   (record `0014`, free q: 99.14 MHz, zero margin) says even a free q leaves
   the datapath at the target with no margin**, so this is expected to land at
   or just below 100 MHz at best, not to close with margin. It would need the
   `b+m` form (P11) or the P8 form plus the select, and the former carries the
   cycle price above.
3. **Two pipelined column halves** (DR-0014 candidate 2): changes cycles per
   multiply and needs a priced supersession proposal for record `0001`
   Decision 3 and the two-key step. Unprobed.

The target is not lowered and no corner is dropped under any option.

## Alternatives considered

- **Build the complete design anyway** -- rejected by records `0011`, `0013`,
  `0014`: no working kernel reaches 10 ns.
- **Keep probing depth variants** -- rejected by the issue's stop rule; the
  three probes here point at the q loop, which is option 2 above and needs the
  operator's choice, not another unprompted iteration.
- **Lower 100 MHz or drop corners** -- ruled out (records `0004`, `0007`).

## Consequences

- Good: the depth hypothesis is settled for the 4:2 and `b+m` forms; the
  remaining gap is localized to the q loop plus a zero-margin datapath.
- Good: the chunked-add and registered-adding-flag probe techniques are
  reusable if a later design needs `b+m` operands.
- Bad: item 5 remains `unmet`; still no all-corner 100 MHz configuration.
- Limitation: the placer seed does not change the result (WNS stable to
  0.00001 ns), so variance from netlist perturbations is still uncharacterized;
  differences under ~1 ns are within noise.
