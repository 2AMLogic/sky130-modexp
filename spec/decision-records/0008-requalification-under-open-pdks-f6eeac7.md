# 0008: Evidence records re-qualified under `open_pdks f6eeac7` — what moved, what could not be re-run, and how the old `c6d73a3` provenance is read

- **Status**: proposed
- **Date**: 2026-10-15
- **Decided by**: Builder, issue #191 (split from #190). No spec value is
  relaxed or changed; this record is an index and a disclosure of
  movements. Ratification follows the same two-key step as the other records.

## Context

Issue #190 re-pinned the `sky130A` PDK from `open_pdks`
`c6d73a35f524070e85faff4a6a9eef49553ebc2b` to
`f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7` (`ciel` 2.6.1). Evidence records are
append-only (`verification/README.md`), so every existing record stays true for
the revision it ran under; issue #191 re-runs the **cited** PDK-dependent kinds
under the new pin and mints new records that `supersede` the old ones.

This pass ran on a shared worker where `openroad` (a Docker wrapper) is not
usable: the worker user is not in the `docker` group, so `klt place-and-route`
and `klt sta` fail with `permission denied ... /var/run/docker.sock`. Changing
that is a worker-spec change, not something an issue may do on the host.
Every leg that needs no OpenROAD was re-run; the rest is listed as **not
re-qualified**, not silently skipped. Nothing was hand-looped: the only
multi-corner leg that could run is a single `klt` request, and the 18-rebuild
`flow/run-corner-sweep.sh` was not run.

## Decision

### 1. Supersession map

| Kind | New record | Supersedes | Outcome |
|---|---|---|---|
| `synthesis-baseline` | `20261015-205100-4d8d397` | `20260808-032045-5488082` | **Moved**: 717 instances (was 682). PDK ruled out, see 2. |
| `drc-lvs` (gate-level LVS ×2 engines + control) | `20261015-205200-4d8d397` | `20260923-062424-7d0dd52` | Reproduces: 17 / 12 / 2 errors, verdicts unchanged. Supplementary extraction finding, see 3. |
| `drc-lvs` (DRC + plain-element LVS) | `20261015-205210-4d8d397` | `20260911-053500-d5e43d3` | DRC clean 0; LVS 17. Unchanged. |
| `drc-lvs` (twin) | `20261015-205220-4d8d397` | `20260911-053520-d5e43d3` | Twin of the above. |
| `gate-level-sim` (SDF replay + Leg 1) | `20261015-205300-4d8d397` | `20260923-054800-e26f603` | Pass ×3, `annotated: true`. Simulation only, see 4. |

### 2. Synthesis: the PDK did not move the count; the legacy 682 does not reproduce

Run twice with everything fixed except `PDK_ROOT`, both give 717 instances /
7144.352 µm² with a **byte-identical mapped netlist**, and the `tt_025C_1v80`
liberty deck hash equals the superseded record's. The 682 → 717 change
therefore arose between the superseded record and now from something other than
the PDK (klt `0.2.0` → `0.6.0`, and/or the Yosys/ABC build, which issue #143
pinned by content after the fact). **Which of those two is responsible is not
isolated**; isolating it is the follow-up (#195). `docs/baseline.md` and
`flow/README.md` still describe 682 as reproducing byte-for-byte; they are
living docs outside this issue's file scope and are not edited here. Per
`docs/baseline.md`'s overclaim rule, none of these numbers is compared to any
other lab's figure.

### 3. LVS: the committed layout-side extraction is not what the pinned klt extracts

`layout/lvs/modexp_layout_abstracted.spice` was extracted by klt `0.4.0`
(deck `5afac7ab…`). Re-extracting the committed GDS with the pinned klt
(deck `d7a9ddfa…`) gives a different netlist (798 nets vs 771; no `VDD VDD`
power-pin tokens on the cell cards), **identical under the old and new PDK**
(the two `sky130_fd_sc_hd.lef` files are byte-identical), so this is tool
drift, not a PDK effect. Run through the `gate-level-verilog` LVS it keeps the
13/12 mismatch counts but turns `power_connectivity` from `match` into
`mismatch` (`VPB` reaches 26 nets). The committed `power_connectivity: match`
(`docs/signoff-claim.md`, `layout/lvs/README.md`) is thus a property of the
older extraction. No verdict is upgraded or downgraded here: T1 item 4 is
`unmet` either way. `layout/lvs/` is deliberately not regenerated (that is the
re-extraction/regeneration the next re-pin owns, per decision 0006; tracked in #194).

### 4. Gate-level: simulation re-qualified, place-and-route not

The SDF replay re-ran the unmodified bit-exact suite against the **frozen**
netlist/SDF under the new PDK's Verilog cell models (pass 3/3, 2/2 tests,
`environment.sdf.annotated: true`). It does not regenerate the netlist or SDF,
which come from a `klt place-and-route` run under the old pin.

### 5. Not re-qualified (blocked on OpenROAD in this environment)

| Kind | Live record(s) still at `c6d73a3` | Why not |
|---|---|---|
| `place-and-route` | `20260816-072918-d8eafca` (18-corner rebuild sweep), `20260911-052542-d5e43d3` (nominal run) | `klt place-and-route` needs `openroad` |
| `sta-corner-sweep` | `20260923-093000-28a7c96` (the T1 item-5 citation) | `klt sta` needs `openroad` |
| `gate-level-sim` | `20260909-230216-92e00f2` | needs a fresh P&R + SDF export |

Scoped out deliberately: `sta-corner-sweep` `20260924-134500-1a8313b` and
`20260924-182806-3193e11` (measurements of an **uncommitted** bit-serial
candidate in a scratch tree, not the committed design) and `drc-lvs`
`20260915-131549-c87a304` (synthetic netlist pair, `pdk: null`, no PDK
dependency). The `18-corner rebuild sweep` also should not be re-run as
hand-launched builds; it needs a native `klt` multi-corner P&R request or the
batch fleet.

### 6. How the old `c6d73a3` provenance is read

Decision records 0004 and 0005 and
`verification/signoff/evidence/testbenches.md` cite `open_pdks c6d73a35…`.
Their text is not edited. **They are to be read as true of the revision they
ran under.** Where this record's table above shows a superseding record, the
newer one is the live evidence for the same claim under `f6eeac7d…`; where it
shows "not re-qualified", the old citation remains the live one and is
`c6d73a3`-era. The T1 manifest (`verification/signoff/block-manifest.json`)
keeps citing the old item-5 record for exactly that reason.

## Alternatives considered

- **Edit the old records/decision text to the new pin** — rejected: forbidden
  by the append-only rule, and it would assert evidence that was not run.
- **Run OpenROAD legs via a different route (sudo/docker group/other host)** —
  rejected: changing the worker's group membership or host tooling is a worker
  spec change; an off-host run is a fleet operation this issue does not own.
- **Hand-loop the 18-corner rebuild sweep locally** — rejected: the host rules
  and the issue's own criterion route grids through `klt` requests.
- **Regenerate `layout/lvs/` from the pinned klt now** — rejected: it
  cascades into the gate-level netlist derivation, the manifest pins and the
  LVS verdicts; decision 0006 already assigns that to the next re-pin.

## Consequences

- Five new records are live under `f6eeac7d…`; **four live records remain at
  `c6d73a3`** (three PDK-dependent kinds above plus the OpenROAD-dependent
  gate-level attempt), so #191 is only partly discharged by this record and
  stays open for the OpenROAD legs.
- `docs/baseline.md`'s 682 headline needs reconciling against the pinned
  toolchain's 717; until then the two disagree and the reader should rely on
  the superseding record's attribution.
- `scripts/setup-env.sh` (from #190) enables only `sky130_fd_pr`, not
  `sky130_fd_sc_hd`, so a fresh provision cannot run `klt synthesize`; this
  pass worked around it locally with `ciel enable ... -l sky130_fd_sc_hd` into
  a worktree-local PDK root. Filed as #193; not changed here (out of scope).
- No RTL change; the bit-exact cocotb suite passes on the same commit
  (`klt functional-verification` 2/2; `cross_check.py` 2000/2000 across
  `WIDTH` 4, 6, 8, 16).
