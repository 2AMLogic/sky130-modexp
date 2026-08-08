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
