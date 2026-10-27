# Candidates for record 20261027-120000-98bf55d (issue #234)

**Nothing in this directory is landed.** The committed design is
`rtl/modexp.v` and its numbers are those of record `20261015-205405-4d8d397`
(`ss_n40C_1v28` at -33.867 ns). Every figure for the files below is in
`../../../records/20261027-120000-98bf55d.md`.

- `rtl/c1-*`, `c2-*`, `c3-*`: full `modexp` designs (same interface and
  handshake as `rtl/modexp.v`). Each passed `verification/cross_check.py`
  (2000/2000, WIDTH 4/6/8/16) before being reported.
- `rtl/p1-*`, `p2-*`, `p3-*`: Montgomery carry-save **timing-probe kernels**
  named `modexp` only so the committed `flow/` requests apply. They are not
  designs: different interface, no exponentiation, no conversions.
- `tools/`: `eval.sh` (synth -> tie -> P&R -> single-corner STA; it ran from a
  scratch dir inside the worktree, with `klt sta` launched from the
  worktree root), `path.sh` (worst-path report), `summ.py`, `cc.sh`
  (cross-check against a candidate), and the Icarus testbenches
  (`tb_modexp.v`: bit-exact + cycle count; `tb_kernel_*.v`: kernel arithmetic).
- Stored-object names in the artifact manifest use the harness labels:
  `base`=C0, `k1`=C1, `k1b`=C2, `k3`=C3, `k2`=P1, `k2b`=P2, `k4`=P3.
