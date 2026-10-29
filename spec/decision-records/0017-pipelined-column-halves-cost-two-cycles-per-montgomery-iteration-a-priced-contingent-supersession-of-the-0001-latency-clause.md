# 0017: Pipelined column halves cost two cycles per Montgomery iteration; a priced, contingent supersession of the record 0001 latency clause

- **Status**: proposed
- **Date**: 2026-10-29
- **Decided by**: Builder proposal on issue #280 (the operator's 2026-10-29
  ruling on #271, branch (c)). Ratification is pending the two-key step (EE key,
  then market key, then the operator), not a direct status flip. This record
  edits no spec text; `spec/modexp.md` and record `0001` are unchanged.

## Context

T1 item 5 (100 MHz) is a disclosed FAIL (DR-0004). Seven single-cycle
carry-save Montgomery kernels (records `0011`, `0013`-`0016`) land between 62
and 86 MHz at `ss_n40C_1v28`; probe (b), the q-loop mux2 restructure, scored
-4.081 ns (DR-0016, record `20261029-040000-cf81741`). The operator ruled that
no further single-cycle lever is probed and that branch (c), the two pipelined
column halves of DR-0014 candidate 2, comes next. DR-0014 and DR-0015 both note
this candidate "changes cycles per multiply" and must be priced against record
`0001` Decision 3 first. That number did not exist; this record derives it and
confirms it by simulation. No external figure is referenced.

## The datapath being priced

The kernel is the radix-2 carry-save Montgomery kernel of records `0011`-`0016`
(`S`, `C` vectors of `WIDTH+2` columns, quotient bit `q` from column 0, two
chained 3:2 levels, right shift by one per iteration).

- **Where the register sits.** Between a low column group (columns `0..h-1`,
  which holds column 0 and so produces `q`) and a high group (`h..WIDTH+1`).
  The signals crossing it are the carries out of the top low column, `q`, and
  the one-bit right-shift feedback from the high group's lowest column back into
  the low group's top column.
- **What it does to the schedule.** That loop (low group, high group, back to
  the low group through the shift feedback) contains exactly one iteration
  register. One register in the loop means one half can run per cycle: cycle 1
  advances the low group, cycle 2 the high group, and the next iteration cannot
  start until both are done. **Two cycles per iteration, serialized, no overlap.**
  The price depends only on the cycles per iteration `K`, not on where the cut
  is: cutting the two 3:2 levels instead of the columns has the same `K = 2`.
  Which cut shortens the binding path is a timing question (see "Not claimed").
- **Overlap is not available inside one exponentiation.** Hiding the second
  cycle needs two independent products in flight (e.g. a right-to-left
  square/multiply pair), which doubles the state registers and changes the
  exponentiation algorithm. Not priced here; see Alternatives.

## Price

Schedule per Montgomery product (MP), the same in the `K = 1` reference and
the `K = 2` proposal except for the iteration term:

```
MP_K(WIDTH) = 1 (load) + K*(WIDTH+2) (iterations) + ceil((WIDTH+2)/2) (carry-save -> binary,
              2 bits/cycle) + 1 (commit)
cycles_K(WIDTH, e) = 2 + WIDTH + (WIDTH + 3 + popcount(e)) * MP_K(WIDTH)
```

`WIDTH+2` iterations (`R = 2^(WIDTH+2) > 4m`) keep inputs and outputs below
`2m` with no final subtraction. The modexp is `3 + WIDTH + popcount(e)`
products (entry `x~`, entry accumulator, `WIDTH` squarings, one multiply per set
bit, exit) plus one step cycle per exponent bit, plus the same 2 start/finish
cycles as record `0001`.

Cycles per Montgomery product:

| `WIDTH` | shipped modular multiply (`WIDTH+2`) | `K=1` single-cycle kernel | `K=2` pipelined halves |
| --- | --- | --- | --- |
| 4 | 6 | 11 | 17 |
| 6 | 8 | 14 | 22 |
| 8 | 10 | 17 | 27 |
| 16 | 18 | 29 | 47 |

`MP_1 = 3*WIDTH/2 + 5` and `MP_2 = 5*WIDTH/2 + 7` for even `WIDTH`.

Cycles per modexp, `start` to `done`, at the two bounds record `0001` uses
(`exp_in == 0` / all-ones):

| `WIDTH` | shipped (record `0001`) | `K=1` | `K=2` | `K=2` / shipped, all-ones |
| --- | --- | --- | --- | --- |
| 4 | 30 / 54 | 83 / 127 | 125 / 193 | 3.57x |
| 6 | 56 / 104 | 134 / 218 | 206 / 338 | 3.25x |
| 8 | 90 / 170 | 197 / 333 | 307 / 523 | 3.08x |
| 16 | 306 / 594 | 569 / 1033 | 911 / 1663 | 2.80x |

`K=2` costs 1.51x-1.61x the `K=1` cycles over these cases. Both
Montgomery rows are slower in cycles than the shipped design, which has no
domain conversion and no carry-save resolution.

**How obtained.** Derived from the schedule above, then confirmed by counting
clock edges from the `start`-sampling edge to the `done` pulse in Icarus:
`verification/cycle-price/` (a schedule-only model, no datapath, and a
testbench) over `WIDTH` 4/6/8/16 and six `exp_in` values each (zero, all-ones,
alternating, single low bit, single high bit, `0111..1`), 24 cases, 0
mismatches for all three columns (record `20261029-034500-9962eb8`). The
counting method is calibrated on the shipped `rtl/modexp.v`, which reproduces
record `0001`'s ratified formula exactly in all 24 cases (that formula was
previously cross-checked at `WIDTH=4` only). The model is a transcription of the
stated schedule, so the check shows the closed form and the control sequence
agree and that the count convention matches `0001`; it does not show a datapath
exists or closes timing.

## Decision

> **Proposed, contingent.** Record `0001` Decision 3's "Latency -- exact, and
> data-dependent" paragraph (the formula and its two bounds only; not the
> interface table, reset contract, `start`-while-busy hazard, or the statement
> that latency is a side channel) is to be superseded by the `cycles_2` formula
> and tables above **if and only if** a pipelined-halves RTL change lands that
> clears the gates below. Until then record `0001` stays in force unamended and
> the shipped design is described by it.
>
> The price is stated; no throughput or MHz claim is made for the pipelined
> design, and none may be made without citing it.

Gates for the follow-on issue (separate, not this one): the bit-exact cocotb
suite at every verified `WIDTH` on the same commit; the 18-corner sweep under
both parasitic bases; the cycle count re-measured on that RTL and the formula
here corrected if it disagrees.

**Side channel (unchanged in kind).** `cycles_2` is still `A + popcount(exp_in) *
MP_2`: latency depends on `popcount(exp_in)` exactly as under `0001`, and the
entry and exit conversion products add only constants. The observer learns the
same quantity; the per-set-bit step grows from `WIDTH+2` to `MP_2` cycles
(18 to 47 at `WIDTH=16`). No countermeasure is proposed or implied, and this
record does not alter that property (`rtl-security.md` bar).

## Not claimed

- **That the halves close 100 MHz.** Nothing here was probed. DR-0015 finding 1
  puts the binding endpoints at the q flops, with the S/C endpoints 0.6-1.1 ns
  behind; DR-0014's free-q bound (P9, invalid on purpose) was 99.14 MHz with no
  margin. A two-cycle iteration relaxes the q loop only if `q'` is formed from
  registered state in the second cycle, and the column cut alone does not
  shorten the depth of a column. The follow-on issue must run a single-corner
  probe first, as every earlier lever did.
- **A conditional break-even, for orientation only.** The shipped design's
  best-effort figure under this repo's pin is 24.79 MHz at 594 cycles
  (record `20261027-120000-98bf55d`, C0). At the all-ones bound and
  `WIDTH=16`, `K=2` matches that throughput only if the clock is `1663/594 = 2.80x`
  higher, about 69.4 MHz; at 100 MHz it would complete in 16.63 us against 23.96 us.
  This holds only if the unbuilt design reaches the clock, and ignores area.
- **The source of `R^2 mod m`.** The entry conversions need it, and this record
  prices the products, not its source. Options: a caller-supplied input (an
  interface change, needing its own record) or on-chip modular doublings (each
  a carry-propagate compare-subtract, the path that fails at this clock when done
  in one cycle). **Unpriced**; the tables assume it is available at `start`.
- **Any comparison to an external lab's figure** (overclaim trap).

## Alternatives considered

- **Leave item 5 as the disclosed FAIL** (DR-0004). Still the default if the
  operator declines; this record changes nothing in that case.
- **Interleave two products (right-to-left exponentiation) to hide the second
  cycle.** Would make every exponent bit cost the same cycles, removing the
  popcount dependence as a side effect, but needs a second state set and a
  different control algorithm. Not priced; a candidate for its own record.
- **`K = 3` or more** (deeper cuts). Price follows `MP_K` above; not evaluated
  for timing.
- **Lower 100 MHz or drop corners** -- ruled out (records `0004`, `0007`).

## Consequences

- Good: the cycle price the earlier records deferred now exists, with a method
  anyone can re-run (`verification/cycle-price/run.sh`).
- Good: the shipped latency formula (record `0001`) is now confirmed at
  `WIDTH` 4/6/8/16, not only 4.
- Bad: even the one-cycle Montgomery reference is 1.7x-2.4x the shipped design's
  cycles at the all-ones bound, and pipelining adds roughly 1.6x more. The clock
  must rise by about 2.8x over the shipped 24.79 MHz just to break even at
  `WIDTH=16`.
- Bad: the timing benefit is unmeasured, so this may buy a price with no closure.
- Next, in order: (1) EE key, (2) market key, (3) only then a request to the
  operator. None of the three is done by this record. If ratified, a separate
  scoped issue covers the single-corner probe, then RTL and the gates above.
