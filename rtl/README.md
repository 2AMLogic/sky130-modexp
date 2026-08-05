# rtl

Verilog sources.

- `modexp.v` — RSA-style modular-exponentiation accelerator (square-and-multiply
  over a shared Blakley modular multiplier), parameterized by `WIDTH`. Migrated
  from `2AMLogic/klayout-tools` (PR #488) and relicensed Apache-2.0 by the
  copyright holder; see issue #2. The measured synthesis baseline for this
  design (682 sky130 cells at `WIDTH=16`) is recorded in `docs/baseline.md`.
