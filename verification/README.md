# verification

cocotb testbenches and Icarus cross-checks. Recorded results are append-only evidence.

- `test_modexp.py` — width-adaptive cocotb testbench for `rtl/modexp.v`,
  bit-exact against Python `pow(base, exp, mod)`. Migrated from
  `2AMLogic/klayout-tools` (PR #488) and relicensed Apache-2.0 by the
  copyright holder; see issue #2.
- `request-modexp.json` — `klt functional-verification` request driving
  `test_modexp.py` against `modexp.v` (default `WIDTH=16`) via Icarus.

Run it with:

```bash
klt functional-verification verification/request-modexp.json --format json
```

See `docs/baseline.md` for the full reproduction recipe, including the
synthesis cell-count measurement and the `WIDTH` = 4/6/8/16 Icarus cross-check.
