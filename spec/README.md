# spec

Ratified specification and decision records.

- [`modexp.md`](modexp.md) — the ratified `modexp` block specification,
  including the decision record for the open questions closed by issue #1.
- [`decision-records/`](decision-records/) — post-ratification decisions
  that extend `modexp.md` without editing its ratified text (per
  `modexp.md` Decision 3). Each record cites the spec text it extends.
  - [`TEMPLATE.md`](decision-records/TEMPLATE.md) — copy this to start a
    new decision record.
  - [`0001-input-domain-interface-and-corner-matrix.md`](decision-records/0001-input-domain-interface-and-corner-matrix.md)
    — qualifies the Correctness row's input domain (with a reproducible
    mismatch measurement), defines out-of-domain behavior, ratifies the
    port/interface contract, names the `sky130_fd_sc_hd` corner matrix,
    maps the T1 evidence checklist to this digital block, and ratifies
    operating conditions. Closes issue #6.
  - [`0002-slow-corner-timing-closure-and-mm-red-critical-path.md`](decision-records/0002-slow-corner-timing-closure-and-mm-red-critical-path.md)
    — holds Decision 2's 100 MHz target at the nominal corner as ratified,
    requires every "closes 100 MHz" claim in this repo to name its corner
    set, records the measured all-corner Fmax, and recommends (does not
    mandate) an ordered follow-up on the `mm_red` critical path. Issue #16.
  - [`0003-lvs-closure-methodology-recommendation.md`](decision-records/0003-lvs-closure-methodology-recommendation.md)
    — recommends a `sky130` extraction-deck layer-coverage extension as the
    route to LVS closure; changes neither `spec/modexp.md` nor
    `docs/signoff-claim.md`'s verdict. Issue #87.
  - [`0004-slow-corner-closure-is-cell-selection-bound-and-the-disclosed-t1-item-5-exception.md`](decision-records/0004-slow-corner-closure-is-cell-selection-bound-and-the-disclosed-t1-item-5-exception.md)
    — discharges `0002` Decision 3's deferred follow-ups with measurements,
    identifies standard-cell family selection (not logic depth) as the
    dominant slow-corner lever, ratifies T1 item 5 as a **disclosed,
    bounded FAIL** carried against an unamended 100 MHz Clock row (10 of 18
    corners; binding corner `ss_n40C_1v28` at 22.80 MHz), and prices the
    measured route to 18/18 rather than lowering the target. Closes
    issue #132. **Its 18/18 claim is withdrawn by `0005`** — see below.
  - [`0005-the-priced-exit-was-run-and-does-not-reproduce.md`](decision-records/0005-the-priced-exit-was-run-and-does-not-reproduce.md)
    — runs `0004` Decision 2's priced exit now that its blocking dependency
    (klayout-tools#2382) has landed. The reproducibility objection is
    discharged (`constraints.dont_use` reproduces the frozen script's
    netlist byte for byte), but the 18/18 does **not** reproduce: 17 of 18
    corners, `ss_n40C_1v28` at −0.574 ns / 94.57 MHz, with both STA
    methodologies now agreeing against closure. Withdraws `0004`'s
    reachability claim, **declines** to supersede `0001` Decision 3's
    latency formula (the shipped RTL is unchanged), re-prices the exit, and
    names unpinned Yosys/ABC build identity as a newly-visible obstacle.
    Lands no layout, RTL, or flow change; no T1 row changes state.
    Issue #141.
