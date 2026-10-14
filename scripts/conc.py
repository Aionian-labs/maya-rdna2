#!/usr/bin/env python3
"""N requests at once against a running Maya server: the combined tokens/s.  usage: conc.py N [PORT] [KEY]"""
import json, sys, threading, time, urllib.request
n = int(sys.argv[1]); port = sys.argv[2] if len(sys.argv) > 2 else "8099"; key = sys.argv[3] if len(sys.argv) > 3 else ""
QS = ["Explain how a refrigerator works, step by step.", "Write a Python class for a bank account with deposit, withdraw and a transaction log.",
      "Describe the causes of the First World War.", "Explain what a hash table is and how collisions are handled.",
      "Write a short story about a lighthouse keeper.", "Explain how vaccines train the immune system."]
out = [None] * n
def one(i):
    body = {"model": "glm-5.3-flash", "messages": [{"role": "user", "content": QS[i % len(QS)]}], "max_tokens": 300, "temperature": 0, "reasoning_effort": "none"}
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json", **({"Authorization": "Bearer " + key} if key else {})})
    t0 = time.time()
    try:
        r = json.loads(urllib.request.urlopen(req, timeout=3000).read())
        out[i] = (r["usage"]["completion_tokens"], time.time() - t0, r["timings"].get("predicted_per_second"), r["choices"][0]["message"]["content"][:60].replace(chr(10), " "))
    except Exception as e:
        out[i] = (0, time.time() - t0, None, "ERROR " + str(e)[:120])
t0 = time.time(); th = [threading.Thread(target=one, args=(i,)) for i in range(n)]
[t.start() for t in th]; [t.join() for t in th]
wall = time.time() - t0; tot = sum(o[0] for o in out)
for i, o in enumerate(out): print(f"  req {i}: {o[0]} tok in {o[1]:.1f} s (server says {o[2]} tok/s) | {o[3]}")
print(f"CONCURRENT n={n}: {tot} tokens in {wall:.1f} s = {tot / wall:.1f} tok/s combined", flush=True)
