#!/usr/bin/env python3
"""Step 8 benchmark against a running Maya server: 3 answers of ~500 tokens, one ~4K-token prompt.
usage: bench.py LABEL [PORT] [API_KEY]"""
import json, os, subprocess, sys, time, urllib.request
from pathlib import Path

label = sys.argv[1]
port = sys.argv[2] if len(sys.argv) > 2 else "8099"
key = sys.argv[3] if len(sys.argv) > 3 else ""
HOME = Path(os.environ.get("MAYA_HOME", str(Path.home() / "maya-rdna2")))
SRC = HOME / "src"
ENGINE_LOG = SRC / (os.environ.get("CFG", "maya-maya-s24-hip") + ".log")
NL = chr(10)
TOPICS = [
    "Write a Python function that parses a CSV file into a list of dictionaries, with type hints and a docstring. Then explain each part in detail.",
    "Explain how photosynthesis works, step by step, for a high-school student. Be thorough.",
    "Write a complete HTML page with a canvas that draws a bouncing ball animation in JavaScript, and explain the code.",
]

def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout

def chat(content, max_tokens):
    body = {"model": "glm-5.3-flash", "messages": [{"role": "user", "content": content}], "max_tokens": max_tokens,
            "temperature": 0, "reasoning_effort": "none"}
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions", json.dumps(body).encode(),
                                 {"Content-Type": "application/json", **({"Authorization": "Bearer " + key} if key else {})})
    t0 = time.time()
    r = json.loads(urllib.request.urlopen(req, timeout=7200).read())
    return r, time.time() - t0

def last_stat():
    lines = [x for x in ENGINE_LOG.read_text(errors="replace").splitlines() if x.startswith("glm stat")]
    return lines[-1] if lines else ""

def memory():
    vram = [int(x.split(":")[-1]) / 2**30 for x in sh("rocm-smi --showmeminfo vram").splitlines() if "Used" in x][:2]
    rss = sh("ps -C strata -o rss=").split()
    free = sh("free -m").splitlines()[1].split()
    return {"vram_gib": [round(v, 2) for v in vram], "strata_rss_gib": round(sum(map(int, rss)) / 2**20, 2),
            "ram_used_mib": int(free[2]), "ram_shared_mib": int(free[4]), "ram_available_mib": int(free[6])}

out = {"label": label, "started": time.strftime("%Y-%m-%d %H:%M:%S"), "runs": []}
def record(kind, r, wall):
    time.sleep(3)   # the engine writes its stat line just after the response
    t, u = r.get("timings", {}), r.get("usage", {})
    row = {"kind": kind, "wall_s": round(wall, 1), "prompt_tokens": u.get("prompt_tokens"),
           "completion_tokens": u.get("completion_tokens"), "prompt_tok_s": t.get("prompt_per_second"),
           "answer_tok_s": t.get("predicted_per_second"), "draft_n": t.get("draft_n"),
           "draft_accepted": t.get("draft_n_accepted"), "finish": r["choices"][0].get("finish_reason"),
           "glm_stat": last_stat(), "memory": memory(), "text_head": (r["choices"][0]["message"].get("content") or "")[:160]}
    out["runs"].append(row)
    print(json.dumps(row), flush=True)

r, w = chat("Say hello in five languages.", 64)          # warm-up, as --bench does
record("warmup", r, w)
for q in TOPICS:
    r, w = chat(q, 500)
    record("answer500", r, w)
docs = (NL + NL).join(p.read_text(errors="replace") for p in [SRC / "README.md"] + sorted((SRC / "docs").glob("*.md")))
r, w = chat("Here is some documentation." + NL + NL + docs[:14500] + NL + NL + "In one sentence, what is this project?", 48)
record("prompt4k", r, w)
r, w = chat("Explain how a four-stroke petrol engine works, step by step.", 300)   # how fast is it right after a long prompt?
record("after_prompt300", r, w)
(HOME / "logs" / f"bench-{label}.json").write_text(json.dumps(out, indent=1))
print("BENCH_DONE", flush=True)
