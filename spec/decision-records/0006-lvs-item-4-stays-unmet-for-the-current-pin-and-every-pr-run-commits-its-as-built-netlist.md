# 0006: LVS (T1 item 4) stays formally unmet for the current pin; every P&R run commits its as-built netlist

- **Status**: ratified
- **Date**: 2026-10-01
- **Decided by**: Operator ruling on issue #139 (Option 3), recorded by Builder

## Context

After issue #131, `klt lvs` on `layout/lvs/` reports `status: "mismatch"`
with 12 `severity: "error"` findings, every one a standard-cell type the
router inserted or resized that the pre-CTS synthesis reference cannot
contain. The instance-by-instance DEF-vs-Verilog accounting is **680
identical, 3 resized, 35 fixup insertions, 0 synthesis instances missing**:
the whole residue, not part of it. A signoff LVS in a digital flow compares
against the as-built post-route netlist. This block has none for its
committed GDS: the run that produced `layout/modexp.gds` wrote a
`verilog_path` (recorded in
`verification/records/place-and-route/artifacts/20260911-052542-d5e43d3/par-nominal-output.json`)
but only the DEF and GDS were committed, and issue #55 established that a
re-run against the identical frozen inputs does not reproduce that GDS.

## Decision

1. **Option 3.** T1 item 4 (LVS) stays **unmet** for the current pin
   (`layout/modexp.gds`), worded exactly as `docs/signoff-claim.md` states
   it: `klt lvs` reports `mismatch`, 12 errors, all router-inserted or
   resized cells, `power_connectivity` `match`, second engine concurs. The
   12 cannot be resolved against a GDS whose as-built netlist was never
   committed. The spec's Signoff row is not relaxed.
2. **Every P&R run commits its `verilog_path` netlist** alongside the DEF
   and GDS. Mechanism: `flow/run-par.sh`, which fails if any of the three
   outputs is absent. Needed under every option.
3. A genuine LVS match (Option 1: re-pin to a fresh self-consistent build
   with its as-built netlist, regenerating every content-hash-pinned
   downstream artifact) is deferred to the **next natural re-pin**, not a
   crash regeneration now.

## Alternatives considered

- **Option 1, re-pin now** — the only route to an honest `match`, but it
  regenerates `layout/drc/`, `layout/erc/`, `layout/lvs/`,
  `verification/gate-level/`, the STA corner sweep and the manifest pins.
  Deferred, not rejected.
- **Option 2, DEF-derived reference** — rejected. The layout-side extraction
  already takes its net names from the same DEF, so the `match` would be too
  close to circular and would sound stronger than the comparison is. #131
  declined it for the same reason.

## Consequences

- The signoff claim does not change; no verdict is upgraded.
- The current pin can never be LVS-clean; closure requires a re-pin.
- Future re-pins cannot lose their netlist silently; the stale "no post-route
  netlist export" line in `flow/README.md` is corrected.
- No RTL change; the cocotb suite is unaffected. No recorded results under
  `verification/` were modified.
