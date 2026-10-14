#!/bin/bash
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/env.sh"
# try.sh LABEL GPUS [KEY=VALUE ...]: restart Maya (localhost only, no key) with these engine settings, run bench.py, print a summary.
label=$1; gpus=$2; shift 2
L=$MAYA_HOME/logs
cd $MAYA_HOME/src
"$HERE/stop.sh" >/dev/null
envs=(--env STRATA_GLM_TIMING=1 --env STRATA_GLM_POOL_STATS=1 --env STRATA_GLM_RESERVE_MB=1024 --env STRATA_GLM_RAM_HEADROOM_GB=6)
for kv in "$@"; do envs+=(--env "$kv"); done
rm -f ${CFG:-maya-maya-s24-hip}.json    # a setup again keeps old env keys otherwise
./maya.sh --backend hip --setup --gpus $gpus --context ${CTX:-8192} --no-vision --yes --plain --no-start --port $MAYA_PORT ${MODELARGS:---model Maya-S24 --models-dir $MAYA_MODELS} "${envs[@]}" </dev/null > $L/try-$label-setup.log 2>&1 || { echo SETUP_FAILED; tail -5 $L/try-$label-setup.log; exit 2; }
: > ${CFG:-maya-maya-s24-hip}.log
tmux new-session -d -s maya "cd $MAYA_HOME/src && ./maya.sh --backend hip --plain --config ${CFG:-maya-maya-s24-hip}.json --port $MAYA_PORT </dev/null > $L/try-$label-serve.log 2>&1; echo EXIT=\$? >> $L/try-$label-serve.log"
for i in $(seq 1 ${WAITN:-330}); do c=$(curl -s -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:$MAYA_PORT/health); [ "$c" = 200 ] && break; grep -q "^EXIT=" $L/try-$label-serve.log && break; sleep 5; done
echo "health=$c"
grep -n "CPU lane\|glm split:\|ERR\|rror\|RAM tier" ${CFG:-maya-maya-s24-hip}.log | cut -c1-260 | head -24
[ "$c" = 200 ] || { tail -15 $L/try-$label-serve.log | cut -c1-250; tail -8 ${CFG:-maya-maya-s24-hip}.log | cut -c1-250; exit 3; }
timeout 3000 python3 "$HERE/bench.py" $label $MAYA_PORT > $L/try-$label-bench.log 2>&1; echo "bench rc=$?"
cp ${CFG:-maya-maya-s24-hip}.log $L/engine-$label.log
python3 - "$L/try-$label-bench.log" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line.startswith("{"):
        print(line[:400]); continue
    r = json.loads(line)
    print(r["kind"], "wall", r["wall_s"], "s | prompt", r["prompt_tokens"], "tok @", r["prompt_tok_s"], "| answer", r["completion_tokens"], "tok @", r["answer_tok_s"], "| draft", r["draft_accepted"], "/", r["draft_n"], "|", r["finish"])
    print("   ", r["glm_stat"][:300])
    print("   ", r["memory"], "|", r["text_head"][:70].replace(chr(10), " "))
PY
exit 0
