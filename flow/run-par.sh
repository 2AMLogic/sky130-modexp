#!/usr/bin/env bash
# Run `klt place-and-route` and capture ALL THREE layout outputs -- the
# routed DEF, the merged GDS, and the as-built post-route Verilog netlist
# (`verilog_path`) -- into one directory meant to be committed together.
#
# Why this exists (issue #139, decision record 0006): the run that produced
# the committed layout/modexp.gds wrote a verilog_path netlist, but only the
# DEF and GDS were committed. With no as-built netlist for that GDS, an LVS
# against it is unreachable, and the run cannot be regenerated (issue #55).
# Never again: every P&R run whose output may be committed goes through this
# script, which FAILS if the envelope lacks any of the three paths or any of
# the three files is missing/empty.
#
# Usage:
#   flow/run-par.sh <out_dir> [request.json]
#     <out_dir>     destination for modexp.def, modexp.gds, modexp.v and
#                   par-output.json (the raw envelope). Commit all four.
#     request.json  defaults to flow/par-modexp.json
#
# Prereqs: flow/README.md's cold start steps 1-2 (synthesize + tie_constants).
# Run from the repository root.
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 <out_dir> [request.json]" >&2
  exit 2
fi
out_dir="$1"
request="${2:-flow/par-modexp.json}"

mkdir -p "${out_dir}"
envelope="${out_dir}/par-output.json"

PDK="${PDK:-sky130A}" klt place-and-route "${request}" --format json > "${envelope}"

python3 - "${envelope}" "${out_dir}" <<'PYEOF'
import json
import shutil
import sys
from pathlib import Path

envelope, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
data = json.loads(envelope.read_text(encoding="utf-8"))
if data.get("status") != "ok":
    sys.exit(f"place-and-route status is {data.get('status')!r}, not 'ok'")

dest = {"def_path": "modexp.def", "gds_path": "modexp.gds", "verilog_path": "modexp.v"}
for key, name in dest.items():
    src = data.get(key)
    if not src:
        sys.exit(f"envelope has no {key}; refusing to capture a partial run")
    src = Path(src)
    if not src.is_file() or src.stat().st_size == 0:
        sys.exit(f"{key} {src} is missing or empty")
    shutil.copyfile(src, out_dir / name)
    print(f"captured {key}: {src} -> {out_dir / name}", file=sys.stderr)
PYEOF
echo "captured DEF + GDS + as-built netlist into ${out_dir}; commit all of them" >&2
