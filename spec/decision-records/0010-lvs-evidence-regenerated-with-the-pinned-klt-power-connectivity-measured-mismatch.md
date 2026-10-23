# 0010: LVS evidence regenerated with the pinned klt — `power_connectivity` is a measured `mismatch`, and the earlier `match` is retired as a claim

- **Status**: proposed
- **Date**: 2026-10-16
- **Decided by**: Builder, issue #194, executing the operator's option (a)
  ruling on that issue (2026-10-16). No spec value is relaxed or changed.
  Ratification follows the same two-key step as the other records.

## Context

`layout/lvs/modexp_layout_abstracted.spice` and the LVS reports built on it
were produced by klt `0.4.0` (extraction deck `sha256:5afac7ab…`). Issue #191
found that the pinned klt (`0.6.0+gdac2b5daceb6`, deck `sha256:d7a9ddfa…`)
extracts a different netlist from the same, unchanged `layout/modexp.gds`
(798 nets / 61 cell types vs 771 / 59), identically under both `open_pdks`
revisions, and that on it `power_connectivity` is `mismatch`, not the `match`
that `docs/signoff-claim.md` and `layout/lvs/README.md` cite. Decision 0006
deferred regeneration to the next re-pin; #190/#191 were that re-pin. The
operator ruled (issue #194) for a bounded, append-only regeneration that states
the measured result honestly, investigates `VPB` without presuming a cause, keeps
signoff item 4 unmet absent independent evidence, and does not derive a
circular DEF-based reference, replace the layout, or relax signoff.

## Decision

1. **`layout/lvs/` is regenerated with the pinned klt.** The extraction, its
   report, and both gate-level LVS reports (`klayout`, `netgen`) are now the
   pinned-toolchain output. The files they replace are preserved verbatim at
   `verification/records/drc-lvs/artifacts/20261016-010000-713829b/superseded-layout-lvs/`.
   The extraction is deterministic (two runs, byte-identical) and byte-identical
   to the one #191 froze.
2. **The measured result is the claim.** `power_connectivity.status` is
   `mismatch` on both engines: one finding, pin `VPB` reaching 26 distinct nets
   across 2809 instances. `status` stays `mismatch` (klayout 13 mismatches / 12
   errors; netgen 3 / 2), unchanged. The previous statement "power connectivity
   verified, `match`" is **retired as a claim about the current toolchain**; it
   remains true only as a description of the klt-0.4.0 extraction it was
   measured on (still in the append-only history).
3. **No inference about the cause is ratified.** What was measured: the 26 `VPB`
   nets coincide with the 26 placement-row nwells (the GDS `nwell` layer merges
   to exactly 26 polygons, each containing tap diffusion); the tap master is
   abstracted with ports `VGND VPWR` only, so the abstracted netlist holds no
   element joining a row's `VPB` net to `VDD`. What was **not** established:
   whether the n-tap contact physically reaches the `VPWR` rail (needs a flat
   extraction of the tap cell or independent rail-continuity evidence), hence
   whether this is an extraction-model limitation or a layout defect. A single
   exploratory run with an unpinned `klayout-tools==0.7.0` produced a netlist with
   `VDD` on the `VPB`/`VPWR` positions and `power_connectivity: match`, alongside
   a different topology residue (82 / 80) that was not investigated; that is
   consistent with the shape of the closed upstream report
   `2AMLogic/klayout-tools#2082` but is not evidence at the pinned toolchain and
   is not relied on. No new klt issue was filed, since the tool gap is already
   tracked.
4. **Signoff item 4 stays `unmet`.** `status` is `mismatch` on both engines,
   and no independent as-built reference is used. Decision 0006's premise that
   no as-built netlist can be regenerated is noted as appearing stale at this
   pin (issue #194's evidence, from #191: a `flow/run-par.sh` re-run reproduced
   `layout/modexp.def` byte-for-byte); it is **not** acted on here, because an
   as-built netlist whose names derive from the same DEF the layout extraction
   reads would be the circular reference the ruling forbids. Whether and how to
   use it independently is a separate decision. 0006 itself is not edited.
5. **Claim text.** `docs/signoff-claim.md` and `layout/lvs/README.md` each get a
   dated amendment at the top stating items 2–4; their older sections are left
   as retained history and read as such.
6. **Dependents.** `verification/gate-level/modexp_post_route.v` is re-derived
   (differs from its predecessor only in renumbered anonymous nets); the
   zero-delay gate-level leg passes 2/2. `verification/signoff/block-manifest.json`
   cites the LVS reports by path without a content hash, so its pins need no
   edit, and `tier-report.json` re-renders byte-identically.

Supersession of the affected evidence records: `20261015-205200-4d8d397` →
`20261016-010000-713829b`; the DRC/plain-element twin pair `20261015-205210-4d8d397`
and `20261015-205220-4d8d397` → `20261016-010010-713829b` and `20261016-010020-713829b`;
gate-level `20261015-205300-4d8d397` → `20261016-010100-713829b`. The SDF replay in
the last one is not re-run (its netlist and SDF are the frozen ones); T1 item 7
keeps citing `20260923-054800-e26f603`.

## Alternatives considered

- **Keep the klt-0.4.0 record and footnote the claim** (option b) — rejected by
  the ruling: the headline would rest on evidence the pinned toolchain cannot
  reproduce.
- **Diagnose `VPB` to a cause first** (option c) — partially done as far as the
  evidence reaches; stopping at "not established" is the honest outcome rather than
  a reason to delay stating the measurement.
- **Use the `run-par.sh` as-built netlist as the reference now** — not done; see
  item 4.

## Consequences

- The signoff claim now says `power_connectivity: mismatch` at the pinned klt. If
  a later pin bump (or a flat/independent check) changes it, that is a new record.
- The diagnosis of `VPB` remains open; it is the highest-value follow-up (flat
  extraction of the tap cell, or a pin bump to a klt that carries the upstream
  fix, then re-measuring — including the unexplained topology residue).
- Cost: five tracked files in `layout/lvs/` and `verification/gate-level/` change
  in place; their prior content is retained in the artifacts directory and git history.
