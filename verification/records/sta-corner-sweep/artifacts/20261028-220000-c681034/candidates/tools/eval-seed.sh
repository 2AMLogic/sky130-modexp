#!/usr/bin/env bash
# usage: eval.sh <name> <rtl.v>   -> synth, tie, par, single-corner sta
set -euo pipefail
R=$(cd "$(dirname "$0")/.." && pwd); N=$1; RTL=$(readlink -f "$2")
D=$R/.scratch/$N; rm -rf "$D"; mkdir -p "$D/rtl" "$D/flow" "$D/layout"
cp "$RTL" "$D/rtl/modexp.v"; cp $R/flow/*.json $R/flow/tie_constants.py "$D/flow/"
cd "$D/flow"; export PDK=sky130A; [ -n "${SEED:-}" ] && sed -i "s/\"seed\": *[0-9]*/\"seed\": $SEED/" par-modexp.json
klt synthesize synthesize-modexp.json --format json > synth.json
NL=$(python3 -c "import json;print(json.load(open('synth.json'))['netlist_path']['path'])")
cp "$R/$NL" .klt/synthesize/modexp_synth.v 2>/dev/null || cp "$NL" .klt/synthesize/modexp_synth.v
python3 tie_constants.py .klt/synthesize/modexp_synth.v .klt/synthesize/modexp_synth_tied.v
klt place-and-route par-modexp.json --format json > par.json
DEF=$(python3 -c "import json;p=json.load(open('par.json'))['def_path'];print(p['path'] if isinstance(p,dict) else p)")
cp "$R/$DEF" ../layout/modexp.def 2>/dev/null || cp "$DEF" ../layout/modexp.def
python3 - <<'PY'
import json
r=json.load(open('sta-modexp.json')); r['pdk']['corners']=['ss_n40C_1v28']
json.dump(r,open('sta-one.json','w'),indent=1)
PY
cd "$R"; klt sta .scratch/$N/flow/sta-one.json --format json > "$D/flow/sta.json"
python3 "$R/.scratch/summ.py" "$D/flow"
