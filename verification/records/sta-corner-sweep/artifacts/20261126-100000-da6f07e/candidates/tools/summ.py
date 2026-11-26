import json,sys
d=sys.argv[1]
s=json.load(open(d+"/sta.json"))
for c in s.get("corners",[]):
    print(c["corner"],"WNS",c["worst_slack_ns"],"hold",c["worst_hold_slack_ns"],"fmax",c["fmax_mhz"],c["timing_status"])
y=json.load(open(d+"/synth.json"))
print("instances",y["instance_count"],"area",y["area_um2"])
