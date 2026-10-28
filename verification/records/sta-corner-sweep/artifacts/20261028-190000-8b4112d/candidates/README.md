# Kernels for record 20261028-190000-8b4112d (issue #271)

**Nothing in this directory is landed.** `rtl/modexp.v` is unchanged. Figures
are in `../../../records/20261028-190000-8b4112d.md`.

- `rtl/p4-*`, `rtl/p5-*`: Montgomery carry-save **timing-probe kernels** named
  `modexp` only so the committed `flow/` requests apply (different interface
  from the real block; no exponentiation, no conversions).
- `tools/`: `eval.sh` (identical to the 20261027-120000 harness; run from a
  `.scratch/` dir at the worktree root with `summ.py` beside it), `path.sh`
  (worst-path report), `tb_kernel_1cycle.v` (kernel arithmetic check).
- `results/`: raw `klt sta` / `klt synthesize` envelopes and worst-path text
  for P4, P5 and the P1 re-run (`p1-rerun-*`).
