# 0012: LVS item 4 is met against the as-built netlist, and the `VPB` `power_connectivity` mismatch was an extraction artifact of the earlier klt build

- **Status**: proposed
- **Date**: 2026-10-27
- **Decided by**: Builder, issue #233. No spec value is relaxed or changed. Ratification follows the same two-key step as the other records.

## Context

Decision 0006 kept T1 item 4 `unmet` because no as-built post-route netlist existed for the GDS; issue #232 committed one (`layout/modexp.v`) together with a regenerated GDS. Decision 0010 recorded `power_connectivity: mismatch` (pin `VPB` reaching 26 nets) under klt `0.6.0+gdac2b5daceb6` and left its cause "not established" (extraction-model limit vs layout defect), declining to declare anything that would read the verdict `match` without evidence. Issue #233 asks for the LVS of the new GDS against its as-built netlist and for that cause to be established.

## Decision

1. **LVS result.** `layout/lvs/` is regenerated from the #232 GDS with the repo-pinned klt `d1dc0fc0`. Against `layout/modexp.v` (gate-level-verilog form) the klayout engine reports `status: match`, 0 errors, 2 disclosed warnings (`topology.power_only_pruned`: the 5 filler/tap masters; `topology.top_level_pins_anchored`: 68 pins), and `power_connectivity.status: match`. T1 item 4 reads `met`.
2. **The `VPB` cause is established, and it is not a layout defect.** A flat (non-abstracted) extraction puts every one of the 4127 pfet bulks of the new GDS (4122 of the previous GDS) on one net carrying the `VPWR` rail, so each n-well that holds a p-device reaches the rail. The earlier `mismatch` came from the abstracted extraction of the `dac2b5da` build, which left the `VPB` position of each cell on a per-row anonymous net; re-extracting the *same new GDS* with `dac2b5da` reproduces it (23 distinct nets across 721 cards), and the repo pin does not (all `VDD`). The statement in 0010 item 3 that the cause was not established is superseded by this; the rest of 0010 stands as the history of what was measured then.
3. **No `expected_nets` is declared.** `power_connectivity: match` is the tool's own consistency verdict at the pin, not a declared expectation, so there is nothing to disclaim. No new upstream issue is filed: the gap was already tracked (`2AMLogic/klayout-tools#2082`) and the pinned build does not exhibit it.
4. **The netgen cross-check is reported as it is.** The netgen engine on the gate-level-verilog form is `mismatch` (matched 0; 2 umbrella errors), as it was on every previous layout: it cannot pair cells whose layout side has `VGND/VPB/VPWR` ports and whose reference has none. It is not read as a disagreement about this layout. The independent engine's concurrence is taken on a power-bearing SPICE form of the same as-built netlist (netgen `match`, 777/777 nets, 70/70 pins); that form ties `VPB` to `VDD` by construction, so it cross-checks signal connectivity and instance binding, not `VPB`. Item 4 is graded on the klayout report; the netgen gate-level mismatch stays on the record and in `layout/lvs/modexp_lvs_report_netgen.json`.
5. **Dependents.** The extraction-derived gate-level leg is re-run (`gate-level-sim/20261027-030100-1c651cc`, 2/2) and supersedes `20261016-010100-713829b`; the committed `verification/gate-level/modexp_post_route.v` is intentionally not rewritten because the live item-7 record `20261017-200000-79564a8` pins its hash (#236 owns item 7). `tier-report.json` is regenerated: item 4 `met` (7 -> 8 of 11); item 11 stays `unmet`, its reason moving `check_failed` -> `supply_spec_incomplete` now that the report it cites no longer fails. Decisions 0006 and 0010 are not edited.

## Alternatives considered

- **Declare `expected_nets` to force `match`** -- unnecessary, and exactly what the ruling on 0010 forbade without evidence. The pinned tool reaches `match` unaided.
- **Treat the netgen gate-level mismatch as blocking item 4** -- the tool grades item 4 on the report cited; the mismatch is a structural property of that engine/form pairing shown on both layouts, and the independent concurrence is supplied on the form that can carry it. Both are disclosed rather than one hidden.
- **Re-mint the item-7 SDF record to refresh `modexp_post_route.v`** -- would claim an SDF replay that was not re-run.

## Consequences

- Item 4's `met` rests on one engine's gate-level report plus a netgen concurrence on a derived reference; a reader wanting netgen to concur on the gate-level form needs a tool change (netgen leg that accepts a signal-only reference), which is a generic upstream gap.
- `layout/lvs/README.md` and `docs/signoff-claim.md` carry dated amendments; their older sections remain history.
  - *Amendment (issue #242, operator ruling 2026-10-28):* the superseded verdict/LVS sections were later removed from `docs/signoff-claim.md`; that history remains in git (`git show a5d8839:docs/signoff-claim.md`) and in the records above.
- A re-pin of klt can move `power_connectivity` again; that is a new record.
