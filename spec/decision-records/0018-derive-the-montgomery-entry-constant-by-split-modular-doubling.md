# 0018: Derive the Montgomery entry constant by split modular doubling

- **Status**: proposed
- **Date**: 2026-11-20
- **Decided by**: Builder proposal for issue #401, pending EE key, market key and operator ratification.

## Context

DR-0017 prices two pipelined column halves assuming the entry conversions
already have `R² mod m` at `start`. Let `W = WIDTH`, `n = W+2` and
`R = 2^n`. One product costs `MP₂ = 2 + 2n + ceil(n/2)` cycles. With the
constant available, DR-0017 counts `cycles₂ = 2 + W + (W+3+popcount(exp_in))·MP₂`
from an accepted `start` to `done`. Each price below adds a prefix to that
schedule once per modexp, including when the previous job used the same modulus.
[DR-0017](0017-pipelined-column-halves-cost-two-cycles-per-montgomery-iteration-a-priced-contingent-supersession-of-the-0001-latency-clause.md)

## Decision

**Propose two-cycle modular doubling on chip.** It preserves the existing
ports, computes the constant for the sampled modulus, and has the lower
cycle cost of the two on-chip options at every verified width.

1. Capture the operands and initialize a `W`-bit residue `r = 1` on the
   accepted start edge. This is `2^0 mod m` for every legal `m > 1`.
   After `i` modular doublings, `r = 2^i mod m`. Reaching `R² = 2^(2n)`
   therefore takes **`2n` doublings** from this seed.
2. Form the `W+1`-bit wire `t = 2r`. Since `0 ≤ t < 2m`, one conditional
   subtraction suffices. Split `t − m` at `h = ceil((W+1)/2)` bits. On the
   first edge save the low `h` difference bits and borrow. On the second,
   subtract the high halves with that borrow. If the high subtraction
   borrows, write `t` to `r`. Otherwise write the joined difference.
   Hold `r` stable through both halves so the original `t` is available
   for selection. Either selection fits in `W` bits.
3. On the last high edge the residue becomes the constant for both entry
   products. The next edge is DR-0017's first operand load. Added latency
   is **`2·2n = 4(W+2)` cycles**. State comprises the residue, `h` scratch
   bits and a borrow, a low/high phase and a counter capable of holding
   `2n`. The product countdown is available during this prefix.

The longest new arithmetic chain spans one half-word. The high half also
drives a result mux across the word. The register cut removes the full-width
borrow chain from the single-cycle compare/subtract identified by DR-0011.
Mux fanout and placed delay still require measurement.

## Alternatives considered

**Caller-supplied constant.** The exact delta to the DR-0001 Decision 3
port table is one additional input and the inclusion of that input in the
`start` sampling contract.

| Port | Direction | Width | Valid value on accepted `start` | Function |
| --- | --- | --- | --- | --- |
| `r2_in` | in | `WIDTH` | `0 ≤ r2_in < mod_in` and `r2_in = 2^(2n) mod mod_in` | Capture with `base_in`, `exp_in` and `mod_in` on the rising edge that samples `start` high while idle. |

The caller may change `r2_in` after that edge. The block holds its sampled
`W` bits for both entries. A busy-time pulse is ignored. An out-of-range
value or a wrong in-range value violates the precondition. The block still
completes on the scheduled edge, with no correctness or range guarantee and
no error indication. Added latency is **zero core cycles**. Computing,
storing and associating the residue with the correct modulus become caller
responsibilities. There is no new arithmetic path on chip.
[DR-0001, Decision 3](0001-input-domain-interface-and-corner-matrix.md#decision-3--interface-contract)

**Bootstrap with the Montgomery kernel.** For odd `m`, let
`MP(a,b) ≡ ab/R (mod m)`, using DR-0017's representative below `2m`.

1. From ordinary 1, perform `n+1` split doublings to obtain the canonical
   seed `s = 2R mod m`. This is the Montgomery representation of 2.
   Keep the seed and initialize the running product to it on the same edge.
2. Scan the binary representation of the public integer `n`, skipping its
   leading one. Square the running product with `MP` for every bit and
   multiply by `s` with `MP` for each set bit. After a prefix of value
   `j`, the product represents `2^j R mod m`. Squaring doubles `j` and
   multiplying by the seed increments it. At the last bit, `2^n R = R²`.
   The complete scan takes `floor(log₂ n)` squares and `popcount(n)−1`
   multiplies, using the existing load, iteration, conversion and commit
   cycles for each.
3. Reduce the last product once with the same low/high subtract, feeding
   the unshifted product to it. Intermediate products may use the full
   `[0, 2m)` range since `R > 4m`. This final pair of edges yields the
   canonical `W`-bit constant even when the raw product exceeds `m−1`.

Added latency is **`2(n+1) + (floor(log₂ n) + popcount(n) − 1)·MP₂ + 2`
cycles**. Phase and public bit-index state steer the shared kernel. Its
running-product register must retain `W+1` bits, while the saved seed needs
`W` bits. The split reducer and countdown serve both the seed and final
reduction. The new paths are operand selection and the same half-width
subtraction and mux as above. Kernel reuse adds no full-width compare/subtract,
but spends more cycles and needs both seed and product live during the scan.

## Consequences

Each pair below gives total cycles for a zero exponent / an all-ones exponent.
The caller column is also the DR-0017 baseline. Added cycles apply to every
exponent at that width.

| `W` | Caller total (+0) | Split doubling added | Split doubling total | Kernel added | Kernel total |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 4  | 125 / 193  | 24 | 149 / 217  | 67  | 192 / 260 |
| 6  | 206 / 338  | 32 | 238 / 370  | 86  | 292 / 424 |
| 8  | 307 / 523  | 40 | 347 / 563  | 132 | 439 / 655 |
| 16 | 911 / 1663 | 72 | 983 / 1735 | 275 | 1186 / 1938 |

**Evidence.** Icarus counted all five schedules across the four widths and
six DR-0017 exponent patterns. All 120 counts match, including the shipped
RTL calibration against DR-0001. The proposed datapaths have schedule
evidence only. [Append-only cycle-price record](../../verification/records/cycle-price/records/20261120-220957-238f5a3.md)

**Modulus limits.** Ordinary doubling gives 0 at `m=2`, 1 at `m=3`, and
`16 mod m` at `m=2^W−1`, where `2^W ≡ 1`. The radix-2 Montgomery kernel
requires odd `m` for `R⁻¹` to exist. The kernel-reuse prefix and all three
full Montgomery totals apply to that path. DR-0001 also admits even moduli.
A full implementation must handle them before it can satisfy that contract.

**Latency side channel.** At a fixed width the added latency for each option
is independent of both `m` and `exp_in`. Borrow only selects data, and the
kernel bootstrap branches only on bits of `W+2`. On the priced path each
set bit of `exp_in` still adds exactly `MP₂` cycles, so the time to `done`
still discloses the exponent popcount.

**Next steps toward T1 item 5.** Obtain the EE key for the proposed price,
then the market key, then the operator's ratification decision. Only after
approval, run the separate pipelined-halves probe at `ss_n40C_1v28`. If
that clears the ratified target, verify the integrated RTL against `pow`
at every verified width, remeasure its cycles, and pass the full 18-corner
sweep at the ratified clock under both parasitic bases. Mint the evidence
and rerun `klt signoff --manifest` to grade item 5.
