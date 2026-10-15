# Ablation of the klt 0.6.0 Yosys script (host Yosys 0.67+post, PDK open_pdks c6d73a35)

Start from the klt 0.6.0 `synth_modexp.run.ys` and delete one flag group at a
time; `num_cells` / `area` are Yosys `stat -liberty -json` (`design` block).
Every variant keeps `setundef -zero` + `hilomap` (4 `sky130_fd_sc_hd__conb_1`).

| variant | abc flags kept | num_cells | area_um2 |
| --- | --- | --- | --- |
| full klt 0.6.0 script | `-constr` + `-dont_use lpflow_*,probe*` | 717 | 7144.352 |
| no `-dont_use` | `-constr` | 719 | 7149.3568 |
| no `-constr` | `-dont_use` | 684 | 6910.3776 |
| neither | (plain `abc -liberty`) | 686 | 6892.8608 |

klt 0.2.0 (no hilomap, plain `abc -liberty`): 682 / 6877.8464.
"neither" minus the 4 conb tie cells: 682 cells, 6892.8608 - 4 x 3.7536 = 6877.8464.
