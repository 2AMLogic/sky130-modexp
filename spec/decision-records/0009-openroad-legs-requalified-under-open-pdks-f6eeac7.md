# 0009: OpenROAD legs re-qualified under `open_pdks f6eeac7` — place-and-route and STA reproduce; the re-synthesized netlist does not

- **Status**: proposed
- **Date**: 2026-10-15
- **Decided by**: Builder, issue #191. Completes decision record 0008, which
  listed these legs as "not re-qualified" because `openroad` was not usable on
  the worker that ran it. No spec value is relaxed; ratification follows the
  same two-key step as the other records.

## Context

Decision record 0008 re-qualified synthesis, DRC/LVS and the SDF gate-level
replay and left `place-and-route` and `sta-corner-sweep` open. A later worker
has a native `openroad` (`26Q3-1510-g6cb3f2b704`) on `$PATH`, so both legs
were run through `klt` (one `klt place-and-route` run per leg, one 18-corner
`klt sta` request; no hand-launched grid).

## Decision

### 1. Supersession map

| Kind | New record | Supersedes | Outcome |
|---|---|---|---|
| `place-and-route` | `20261015-205402-4d8d397` | `20260911-052542-d5e43d3` | Leg A (frozen netlist): reproduces; `modexp.def` byte-identical to `layout/modexp.def`, GDS per-layer XOR empty, all headline numbers equal. Leg B (re-synthesized): different 717-cell design, disclosed only. |
| `sta-corner-sweep` | `20261015-205405-4d8d397` | `20260923-093000-28a7c96` | Unchanged at all 18 corners (10 closed, worst `ss_n40C_1v28` −33.867 ns); the item-5 exception of 0004 is unchanged. |

### 2. What moved

Nothing past tolerance on leg A or STA. Two variables changed together on leg
A (PDK pin and OpenROAD build: native `26Q3-1510` vs the Docker image's
`26Q3-1260`); the byte-identical DEF shows neither moved this route, but they
are not separated. Leg B differs from the committed layout only because the
recipe as committed now synthesizes 717 cells (see 0008 §2, #195); it is
reported, not adopted, and `layout/` is not regenerated.

### 3. Still not re-qualified

- `place-and-route` `20260816-072918-d8eafca` (18-corner per-corner rebuild
  sweep): needs a native multi-corner `klt` P&R request or the batch fleet;
  not hand-looped.
- `gate-level-sim` `20260909-230216-92e00f2`: superseded in intent by
  `20261015-205300-4d8d397` (0008); not re-minted.
- `verification/signoff/block-manifest.json` item 5 still cites the old STA
  record (identical numbers); re-pointing is a manifest regeneration.

### 4. Reading the old provenance

As in 0008 §6: decision records 0004/0005 and
`verification/signoff/evidence/testbenches.md` are not edited and are read as
true of the `c6d73a3` revision; the records above are the live evidence for
the same claims under `f6eeac7d…`.

## Consequences

- Every cited kind now has an `f6eeac7d…` successor except the 18-corner
  rebuild sweep in §3, which stays `c6d73a3`-era until a native multi-corner
  request exists; it should be filed as its own issue rather than keep #191
  open.
- `scripts/setup-env.sh` gaps (only `sky130_fd_pr` enabled; `python3 -m venv`
  unavailable on the worker) are tracked in #193, not changed here.
