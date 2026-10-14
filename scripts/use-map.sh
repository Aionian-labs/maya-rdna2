#!/bin/bash
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/env.sh"
# use-map.sh exact|m1|p1|m3 : choose how many low-ranked, not-in-VRAM experts the late layers skip, then restart Maya.
#   exact  nothing skipped                      ~10 tok/s   identical to the unmodified model
#   m1     keep 5 on layers 23-29, 4 on 30-44   ~12-13      97.1% same top token
#   p1     keep 3 on layers 23-29, 1 on 30-44   ~14.5       95.6%
#   m3     keep 4 on 10-16, 2 on 17-23, 1 on 24-44  ~16     88.4%
case "$1" in
  exact) M="" ;;
  m1) M=8888888888888888888888855555554444444444444448 ;;
  p1) M=8888888888888888888888833333331111111111111118 ;;
  m3) M=8888888888444444422222221111111111111111111118 ;;
  *) echo "usage: $0 exact|m1|p1|m3"; exit 2 ;;
esac
python3 - "$M" <<'PY'
import json, sys
import os
cur = os.environ["MAYA_HOME"] + "/current"
p = os.environ["MAYA_HOME"] + "/src/" + (open(cur).read().strip() if os.path.exists(cur) else "maya-maya-s24-hip") + ".json"
c = json.load(open(p)); e = c.setdefault("env", {})
e.pop("STRATA_GLM_TRUNK_KEEP_MAP", None)
if sys.argv[1]: e["STRATA_GLM_TRUNK_KEEP_MAP"] = sys.argv[1]
json.dump(c, open(p, "w"), indent=1)
print("trunk-keep map:", sys.argv[1] or "off (exact)")
PY
"$HERE/stop.sh" && "$HERE/start.sh"
