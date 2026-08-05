# `modexp` — ratified specification

**Status: ratified, 2026-08-05.** This document is the authoritative
specification for the `modexp` block, superseding the DRAFT spec table
previously carried in `README.md`. It closes issue #1.

## Design

Square-and-multiply modular exponentiation (`base^exp mod m`) over a shared
MSB-first interleaved ("Blakley") modular multiplier — one real modular
multiplier, reused across exponent bits, rather than an unrolled datapath.
Parameterized on `WIDTH`.

## Ratified spec table

| Parameter | Target | Stretch |
|---|---|---|
| Operation | `base^exp mod m`, square-and-multiply | Montgomery variant — deferred, see Decision 5 |
| `WIDTH` | 16 primary; 4/6/8 verified bit-exact | 32 — deferred, see Decision 1 |
| Correctness | bit-exact vs `pow(b, e, m)`, randomized, on every commit | formal equivalence check |
| Cell count @ `WIDTH=16` | no fixed number — see Decision 3 | meaningful reduction with correctness (and, once set, timing) held |
| Clock | 100 MHz, Phase 2 target — see Decision 2 | 500 MHz |
| Signoff | DRC + LVS clean on the OpenROAD-produced GDS | — |
| Area | unset — see Decision 4 | — |

Maturity ladder (unchanged): RTL + bit-exact verification → synthesis
baseline → place-and-route with timing closure → DRC/LVS-clean GDS →
shuttle seat → measured silicon.

## Decision record

Each decision below was open at issue filing time. Each is now either
resolved or explicitly deferred with a named trigger for revisiting.

### 1. `WIDTH` set — is 32 in scope?

**Deferred.** 32 remains a stretch item, not part of the primary/verified
`WIDTH` set (16 primary; 4, 6, 8 verified). The design is already described
as "parameterized on `WIDTH`," so admitting 32 is expected to be
bookkeeping (a parameterization extension) rather than a microarchitecture
change — but that is a claim, not yet a verified fact, and the spec does
not ratify unverified claims.

**Revisit trigger:** a `WIDTH=32` bit-exact verification run (cocotb and/or
the deterministic Icarus cross-check used for the other widths) passes with
0 mismatches. At that point 32 is promoted from stretch to the verified
set as a parameterization extension; if verification instead surfaces
microarchitectural issues (timing, datapath width limits, etc.), this
decision is reopened.

### 2. Clock target

**Resolved.** 100 MHz is the Phase 2 target for OpenROAD timing closure on
sky130. 500 MHz remains a stretch goal. Neither has been attempted as of
ratification.

**Revisit trigger:** the first OpenROAD timing-closure run reports an
achievable Fmax. That measured result — not this target — becomes the
number future work is held to.

### 3. Cell-count objective

**Resolved: no fixed target number or percentage.** Phase 2's objective is
"whatever falls out with correctness held" (and, once Decision 2's timing
closure lands, timing held too) — not a target cell count and not a
percentage-reduction goal. The measured synthesis baseline this optimizes
from is recorded in [`docs/baseline.md`](../docs/baseline.md); that
document's overclaim framing (why the external Nangate45-based figure is
not comparable to any sky130 count produced here) applies unchanged to
every Phase 2 result and is not restated here — it is carried forward by
reference, not re-derived.

**Revisit trigger:** none required — this framing does not carry a target
to expire. Revisit only if Phase 2 priorities change (e.g., a specific
target number becomes strategically useful), in which case update this
document with a new decision record entry rather than editing this one.

### 4. Area target

**Deferred**, as the pre-ratification draft already stated. No area target
is set.

**Revisit trigger:** the first place-and-route run through OpenROAD lands
and reports an achievable area. That measurement — not a pre-set target —
becomes the number future work is held to.

### 5. Montgomery variant

**Deferred / out of scope for Phase 2.** Phase 2 priorities are cell-count
and timing work on the existing Blakley core described in
[`docs/baseline.md`](../docs/baseline.md); no Montgomery-variant design work
is planned alongside it.

**Revisit trigger:** a comparison arm against the Blakley core becomes a
stated program goal. Until then this remains an unstarted stretch item, not
a committed deliverable.

## Constraints (not up for negotiation, carried forward from the issue)

- Bit-exact correctness against `pow(base, exp, mod)` gates every result. A
  smaller cell count on a design that fails verification is not a result.
- External figures from other standard-cell libraries (e.g. the Nangate45
  figure referenced in `docs/baseline.md`) are not comparable to sky130
  counts produced in this repo and must not appear as targets. See
  `CLAUDE.md`'s "overclaim trap" section and `docs/baseline.md`.
