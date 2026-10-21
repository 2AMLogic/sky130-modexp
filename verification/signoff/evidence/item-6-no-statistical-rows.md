# T1 item 6 — no statistical spec row (`not_applicable`)

Source of truth for the graded claim. The graded form is
[`item-6-na-statement.json`](item-6-na-statement.json), bound to the row index
[`modexp-spec-rows.json`](modexp-spec-rows.json), whose `source_hash` pins
`spec/modexp.md`. `run-signoff.sh --check` verifies that the index hash still
matches the spec and that every row id below appears in both JSON files.

This statement covers the digital partition. Every row of the ratified table in
`spec/modexp.md` (status: ratified, 2026-08-05) is listed, Stretch column
included.

| Row id | Spec row | Why it is not statistical |
|---|---|---|
| `operation` | Operation | Defines the computation; no numeric bound. The Montgomery stretch is deferred and carries none either. |
| `width` | `WIDTH` | A discrete set of verified configurations (16 primary; 4, 6, 8 verified), not a measured distribution. The 32 stretch is deferred and unverified. |
| `correctness` | Correctness | Bit-exact equality against `pow(b, e, m)`; a deterministic pass/fail with no tolerance. The formal-equivalence stretch is exact too. |
| `cell-count` | Cell count @ `WIDTH=16` | No fixed target (Decision 3). A cell count is a deterministic integer for a given netlist and library. |
| `clock` | Clock | Corner-bounded by STA at the PDK's characterised corners, including the exceptions carried by decision records 0004, 0005 and 0007. Per-corner slack is deterministic, not a Monte Carlo quantity. The 500 MHz stretch is graded the same way. |
| `signoff` | Signoff | DRC and LVS clean on the produced GDS; rule-deck pass/fail, zero violations. |
| `area` | Area | Unset (Decision 4). Layout area is a deterministic measurement. |

## Claim

No accuracy, offset, matching, yield, sigma or Cpk bound appears anywhere in
`spec/modexp.md`, including its decision record. Item 6 therefore has no Monte
Carlo claim to evidence. This is a recorded `not_applicable`, not a `met`: it
asserts that the item does not apply to this spec, not that a statistical
property was demonstrated. If a statistical row is ever added to the spec, this
statement stops covering it and item 6 must be re-graded.
