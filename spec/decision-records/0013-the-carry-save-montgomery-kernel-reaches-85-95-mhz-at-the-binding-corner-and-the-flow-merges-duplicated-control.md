# 0013: The carry-save Montgomery kernel reaches 85.95 MHz at `ss_n40C_1v28`, still short of 100 MHz; the flow merges RTL-duplicated control

- **Status**: proposed
- **Date**: 2026-10-28
- **Decided by**: Builder finding on issue #271, recorded for the operator.
  Ratification is pending the two-key step, not a direct status flip. This
  record changes no spec row.

## Context

Record `0011` named one open lead for T1 item 5: a radix-2 Montgomery
datapath kept in carry-save form (P1, 80.33 MHz as a bare kernel), with a
follow-up to re-measure it with duplicated/fan-out-limited control and
pre-registered operand ANDs. Issue #271 gated the expensive complete build on
that kernel reaching 100 MHz at `ss_n40C_1v28`. Numbers are from record
`verification/records/sta-corner-sweep/records/20261028-190000-8b4112d.md`
(single-corner `klt sta`, 10 ns period, klt 0.8.0, one run each; P1 re-run
reproduced DR-0011's -2.448 ns exactly). No external figure is referenced.

| kernel | WNS (ns) | f_max (MHz) |
| --- | --- | --- |
| P1 (re-run) | -2.448 | 80.33 |
| P4 pre-registered operand AND, q per column group | -1.635 | 85.95 |
| P5 P4 + duplicated S0/C0/B0 flops | -4.431 | 69.30 |

## Decision

> **The kernel does not close `ss_n40C_1v28` at 100 MHz (best: -1.635 ns).**
> Per the issue's gate, the complete datapath (R^2 mod m, carry-save->binary,
> final reduction, modexp suite) is **not** built. T1 item 5 stays `unmet`;
> DR-0004's disclosed exception stands. The 100 MHz target and 18-corner
> matrix are untouched, and no supersession of record `0001` Decision 3 is
> proposed because no complete design exists to price.

Measured gap: 1.635 ns of a 10 ns period. The worst path is flop -> `maj3`
(q) -> `a21oi` -> one fan-out-45 buffer -> `and3` -> `nor3`: the quotient bit
and its fan-out consume the whole post-flop budget.

**Next lever** (not done here): get the quotient fan-out below ~8 in a form
the flow cannot undo. `(* keep *)` on the wires/flops did not stop the
Yosys/ABC pass from merging the copies (both P4 and P5 still show a single
fan-out 45-46 net), so the options are a hierarchy boundary the flow keeps
(`keep_hierarchy` on a q-slice module, if `klt synthesize` can request it), or
a registered quotient with the recurrence re-timed so q for step i+1 is
computed during step i (DR-0011's P2 did the naive version and was worse,
with an unbuffered 31-fan-out flop). Needs a single-corner probe before any
complete build.

## Alternatives considered

- **Build the complete design anyway** -- rejected by record `0011` and the
  issue's gate: the kernel has not reached 10 ns.
- **Lower 100 MHz or drop corners** -- ruled out (records `0004`, `0007`).
- **Declare P5's result the cost of duplication** -- rejected: its netlist
  merged the copies, so it does not test duplication.

## Consequences

- Good: the follow-up (1) lever is measured for what it can deliver in RTL
  alone (+0.81 ns, 5.6 MHz) and the remaining gap is localized to the q net.
- Good: P1's number is reproducible across klt 0.7.1.dev -> 0.8.0.
- Bad: item 5 remains `unmet`; still no all-corner 100 MHz configuration.
- Limitation: one run per kernel; no seed variance estimate, and differences
  under ~1 ns are within placement/buffering noise (record `0011`).
- Tool gap filed upstream (`2AMLogic/klayout-tools#4538`): no way via `klt synthesize` to prevent the
  mapper merging intentionally duplicated logic for fan-out control.
