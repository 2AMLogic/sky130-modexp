# 0014: No quotient re-timing of the carry-save Montgomery kernel closes the binding corner at 100 MHz

- **Status**: proposed
- **Date**: 2026-10-28
- **Decided by**: Builder finding on issue #271, recorded for the operator.
  Ratification is pending the two-key step, not a direct status flip. This
  record changes no spec row.

## Context

Record `0013` left one lever open for T1 item 5: get the quotient (q) fan-out
of the radix-2 carry-save Montgomery kernel below ~8 in a form the flow
cannot undo, either via a hierarchy boundary or via a registered quotient with
the recurrence re-timed. Numbers are from record
`verification/records/sta-corner-sweep/records/20261028-210000-a65f037.md`
(single-corner `klt sta`, 10 ns period, klt 0.8.0). No external figure is
referenced.

| kernel | WNS (ns) | f_max (MHz) |
| --- | --- | --- |
| P4 (record 0013, best before this work) | -1.635 | 85.95 |
| P6 q registered, one flop (fan-out 44) | -6.029 | 62.39 |
| P7 q in six non-mergeable flops, naive recurrence | -4.469 | 69.11 |
| P8 q in six flops, shallow recurrence | -1.764 | 85.00 |
| P9 lower bound: next-q made trivial (wrong on purpose) | -0.087 | 99.14 |

## Decision

> **No quotient re-timing of this kernel reaches 100 MHz at `ss_n40C_1v28`.**
> The best working kernel (P8, 85.00 MHz) misses by 1.764 ns and is within
> noise of P4. Even with the next-quotient made free (P9, not a valid
> design) the kernel reaches only 99.14 MHz. The complete datapath is **not**
> built; T1 item 5 stays `unmet`; DR-0004's disclosed exception stands. The
> 100 MHz target and 18-corner matrix are untouched, and no supersession of
> record `0001` Decision 3 is proposed.

Two findings that carry forward:

1. **The fan-out half of the lever is solved without a `klt` feature.**
   Copies of the registered q that differ in polarity and flop kind survive
   Yosys/ABC; the worst-path flop fan-out drops from 44-46 to 4-5. The
   hierarchy-boundary route (`2AMLogic/klayout-tools#4538`) is therefore not
   needed for this.
2. **The binding term is now the carry-save datapath itself, plus the
   recurrence.** With q free, two chained 3:2 levels at this corner cost
   ~8.4 ns of arrival plus 1.8 ns setup. The real recurrence adds ~1.7 ns.
   P9 sits at the target with no margin, below the ~1 ns noise floor
   (record `0011`).

**Next lever** (not done here): cut the logic depth per cycle, not the fan-out.
Candidates, unmeasured: a 4:2-compressor-style cell structure written so the
mapper cannot chain two `xor3`; processing two cycles over two pipelined
columns halves (cost: cycles per multiply, which must be priced against record
`0001` Decision 3); or a different radix-2 recoding that removes one 3:2
level from the recurrence. Each needs a single-corner probe first, as here.

## Alternatives considered

- **Build the complete design anyway** -- rejected by records `0011`, `0013`
  and the issue's gate: no working kernel reaches 10 ns.
- **Lower 100 MHz or drop corners** -- ruled out (records `0004`, `0007`).
- **Treat P9 as evidence a closure is near** -- rejected: P9 is arithmetically
  wrong, has zero margin, and omits a cost (the recurrence) that was measured
  at ~1.7 ns.
- **Wait for a hierarchy-boundary option in `klt synthesize`** -- not needed
  for fan-out (finding 1) and would not remove the datapath term (finding 2).

## Consequences

- Good: the quotient fan-out hypothesis is settled; the remaining gap is
  localized to logic depth, with a measured ceiling.
- Good: the six-copy technique and the algebraic form of the next-quotient
  are reusable by any later Montgomery design.
- Bad: item 5 remains `unmet`; still no all-corner 100 MHz configuration.
- Limitation: the placer seed does not change the result (WNS stable to
  ~0.00002 ns), so variance from netlist perturbations is still
  uncharacterized; differences under ~1 ns are within noise.
