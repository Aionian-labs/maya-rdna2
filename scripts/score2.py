#!/usr/bin/env python3
"""Quality of trunk-keep maps on this PC: the engine's own scoring mode (STRATA_GLM_SCORE) on ~1,200 tokens of prose
and code, each map against a dump of the unmodified model.  Run from $MAYA_HOME/src with .venv/bin/python."""
import json, os, subprocess, sys, time
from pathlib import Path
HOME = Path(os.environ.get("MAYA_HOME", str(Path.home() / "maya-rdna2")))
SRC = HOME / "src"
sys.path.insert(0, str(SRC)); sys.path.insert(0, str(SRC / "tools"))
import serve.server as SV
import strata_tokenizer as ST
cfg = json.loads((SRC / "maya-maya-s24-hip.json").read_text())
tok = ST.Tokenizer.from_dir(cfg["tokenizer"])
NL = chr(10)
prose = (SRC / "docs/DETAILS.md").read_text(errors="replace")[3000:]
code = (SRC / "serve/server.py").read_text(errors="replace")[20000:]
ids = tok.encode(prose)[:600] + tok.encode(NL + NL + code)[:600]
CTX = 200
scratch = HOME / "scratch"; scratch.mkdir(exist_ok=True)
ref = scratch / "score-ref.bin"
def band(spec):   # [(first layer, digit)], 46 layers (45 = the draft block)
    s = ""
    for il in range(46):
        s += [d for a, d in spec if il >= a][-1]
    return s
MAPS = [("exact (writes the reference)", None),
        ("P1: all to 22, keep 3 on 23-29, 1 on 30-44", band([(0, "8"), (23, "3"), (30, "1"), (45, "8")])),
        ("P2: all to 16, 5 on 17-22, 2 on 23-29, 1 on 30-44", band([(0, "8"), (17, "5"), (23, "2"), (30, "1"), (45, "8")])),
        ("P3: all to 9, 6 on 10-16, 3 on 17-23, 1 on 24-44", band([(0, "8"), (10, "6"), (17, "3"), (24, "1"), (45, "8")])),
        ("P4: all to 22, keep 1 on 23-44", band([(0, "8"), (23, "1"), (45, "8")]))]
for i, (name, m) in enumerate(MAPS):
    env = SV.child_env(cfg)
    env.pop("STRATA_GLM_TRUNK_KEEP_MAP", None)
    env["STRATA_GLM_SCORE"] = str(CTX)
    env["STRATA_GLM_USAGE"] = "0"          # every run starts from the same tiers
    if i == 0:
        env["STRATA_GLM_SCORE_DUMP"] = str(ref)
    else:
        env["STRATA_GLM_SCORE_REF"] = str(ref)
    if m:
        env["STRATA_GLM_TRUNK_KEEP_MAP"] = m
    t0 = time.time()
    p = subprocess.run([cfg["exe"]] + SV.engine_args(cfg) + ["--tokens", ",".join(map(str, ids))], env=env,
                       cwd=cfg.get("cwd") or str(SRC), capture_output=True, text=True)
    line = next((x for x in p.stdout.splitlines() if x.startswith("SCORE") or x.startswith("ERR")), "no SCORE line; rc=%d %s" % (p.returncode, p.stderr[-300:]))
    print(f"[{name}] map={m or '-'}{NL}    {line}   (run {time.time() - t0:.0f} s)", flush=True)
ref.unlink(missing_ok=True)
