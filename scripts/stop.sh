#!/bin/bash
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/env.sh"
# Stop Project Maya: Ctrl+C to the server, wait for the engine to exit, close the tmux session.
tmux send-keys -t maya C-c 2>/dev/null
for i in $(seq 1 30); do pgrep -x strata >/dev/null || break; sleep 2; done
tmux kill-session -t maya 2>/dev/null
pgrep -x strata >/dev/null && echo "engine still running" || echo "stopped"
