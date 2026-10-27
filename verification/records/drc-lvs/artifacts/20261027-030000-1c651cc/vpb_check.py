#!/usr/bin/env python3
"""VPB evidence for issue #233 (stdlib only).

usage: vpb_check.py flat <flat_extraction.spice> | abstracted <abstracted.spice>

flat:       distinct nets on pfet bulk (4th terminal) of a non-abstracted
            `klt extract` netlist. One net carrying the VPWR label means every
            p-device's n-well is physically tied to the VPWR rail.
abstracted: distinct nets in the VPB position (cell pin order VGND VPB VPWR, the
            2nd of the 3 tokens before the output) of `Xsky130_fd_sc_hd__*` cards
            of an abstracted netlist, excluding the tap/filler masters.
"""
import collections, json, sys

mode, path = sys.argv[1], sys.argv[2]
lines = open(path).read().replace("\n+", " ").splitlines()
if mode == "flat":
    pf = [l.split() for l in lines if l.startswith("M") and " pfet " in l + " "]
    bulk = collections.Counter(t[4] for t in pf)
    out = {"pfet_count": len(pf), "distinct_bulk_nets": len(bulk), "bulk_nets": dict(bulk.most_common(5))}
else:
    nets = collections.Counter()
    n = 0
    for l in lines:
        if not l.startswith("Xsky130_fd_sc_hd__") or "tap" in l.split()[0] or "fill" in l.split()[0]:
            continue
        t = l.split()
        # logic cells: ... VSS <VPB> <VPWR> [outputs]; locate by the VSS token
        if "VSS" in t:
            i = t.index("VSS")
            nets[t[i + 1]] += 1
            n += 1
    out = {"logic_cell_cards": n, "distinct_vpb_position_nets": len(nets), "top": dict(nets.most_common(3))}
print(json.dumps(out, indent=2, sort_keys=True))
