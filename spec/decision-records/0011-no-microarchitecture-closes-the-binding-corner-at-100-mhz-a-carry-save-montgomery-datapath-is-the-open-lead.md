# 0011: No complete microarchitecture closes `ss_n40C_1v28` at 100 MHz; a carry-save Montgomery datapath is the open lead

- **Status**: proposed
- **Date**: 2026-10-27
- **Decided by**: Builder finding on issue #234, recorded for the operator.
  Ratification is pending the two-key step (`2am` `scripts/ratify-key.sh`),
  not a direct status flip. This record changes no spec row.

## Context

Record `0007` declined the bit-serial 17/18 re-spin and kept the search open
for a design that closes every ratified corner without that throughput loss.
Issue #234 ran that search. Every number below is from record
`verification/records/sta-corner-sweep/records/20261027-120000-98bf55d.md`
(single-corner `klt sta` at `ss_n40C_1v28`, 10 ns period, one run each, fresh
synthesis + place-and-route under the current pin). No external library's or
lab's figure is referenced, per `CLAUDE.md`'s overclaim-trap section.

Throughput = `f_max(ss_n40C_1v28) / cycles` (WIDTH=16, all-ones exponent,
cycles as counted by the Icarus bench; `x1000`):

| candidate | WNS (ns) | f_max (MHz) | cycles | throughput | instances |
| --- | --- | --- | --- | --- | --- |
| C0 baseline, re-run under this pin | -30.332 | 24.79 | 594 | 41.7 | 717 |
| C1 speculative parallel reduction | -44.941 | 18.20 | 594 | 30.6 | 787 |
| C2 C1 + Kogge-Stone adders | -19.536 | 33.86 | 594 | 57.0 | 1601 |
| C3 two-cycle step | -17.713 | 36.08 | 1106 | 32.6 | 802 |
| P1 Montgomery carry-save kernel (probe) | -2.448 | 80.33 | not built | n/a | 420 |
| P2 P1 + registered quotient (probe) | -5.491 | 64.55 | not built | n/a | 424 |
| P3 P1 as two 3:2 stages (probe) | -3.071 | 76.51 | not built | n/a | 644 |

C1-C3 are complete designs and passed the bit-exact cross-check at WIDTH
4/6/8/16. P1-P3 are datapath-only timing probes (no exponentiation control,
no domain conversion, no carry-save-to-binary conversion, no modexp suite).

## Decision

> **No candidate that is a complete design closes `ss_n40C_1v28` at 100 MHz.**
> The issue #234 recorded finding is: no qualifying candidate. T1 item 5
> stays `unmet`; DR-0004's disclosed exception stands verbatim. No RTL is
> landed and the 100 MHz target and 18-corner matrix are untouched.
>
> The search is **not closed**. The only direction measured within 2.5 ns of
> the target is a radix-2 Montgomery datapath kept in carry-save form (P1,
> 80.33 MHz as a bare kernel), because it removes the carry-propagate adder
> and the compare/subtract from the per-cycle path. This record does **not**
> claim it can close 100 MHz: P1's best run still misses, the variants P2/P3
> were worse (and are within placement/buffering noise of each other, one
> run each), and the complete design is unbuilt.
>
> Unchanged: record `0001` Decision 3's latency formula stays ratified and
> unamended. A Montgomery design changes cycles per multiply and would need
> a supersession proposed *with its measured cycle count*; none is proposed
> here because there is no measured design to price.

## Alternatives considered

- **Land C2** — +37% throughput over C0, but 2.2x the instances and 19.5 ns
  short; it closes nothing and would re-mint items 1-4, 7 and 11.
- **Land C3 or C1** — slower than the baseline in throughput.
- **Build the full Montgomery design now** — it needs R^2 mod m (a
  compare/subtract per step, which must itself be carry-free), carry-save
  to binary conversion (a bit-serial adder per operand), a <=m final
  reduction, a changed latency formula and re-minted evidence. The probe
  shows the kernel alone has not reached 10 ns, so the cost is not justified
  until the kernel does. Not chosen for this issue.
- **Relax 100 MHz or drop corners** — ruled out (record `0007`).

## Consequences

- Good: the throughput-neutral architectures an engineer would try first
  (parallel reduction, prefix adders, a pipeline cut) are now measured and
  rejected, with frozen RTL and the harness to reproduce them.
- Good: the clock-to-Q + setup floor (2.4-5.7 ns of 10) and one `xnor3`
  (3.3-3.6 ns) show a closing datapath has about two gate levels; fanout of
  any control or quotient signal must be engineered, not left to the flow.
- Bad: item 5 remains `unmet`; the program still has no all-corner 100 MHz
  configuration.
- Open follow-ups (not done here): (1) a carry-save Montgomery kernel with
  duplicated/fan-out-limited control and pre-registered operand ANDs, the
  next measurement; (2) only if a kernel closes, an interleaved
  square/multiply two-stage design (independent lanes share `b`), whose
  cycle count must be measured before any supersession of `0001` Decision 3;
  (3) constant-time behavior (no `popcount(exp_in)` term) would be a
  by-product and must be reviewed against `rtl-security.md`.
- Limitation: one run per candidate; no variance estimate.
