#!/bin/bash
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/env.sh"
# Start Project Maya with the current config (see use-model.sh) in tmux session "maya"; settings in env.sh.
tmux has-session -t maya 2>/dev/null && { echo "already running (tmux session maya)"; exit 1; }
tmux new-session -d -s maya "cd $MAYA_HOME/src && ./maya.sh --backend hip --plain --config $(cat $MAYA_HOME/current 2>/dev/null || echo maya-maya-s24-hip).json --port $MAYA_PORT --host $MAYA_HOST --api-key \"\$(cat $MAYA_API_KEY_FILE)\" </dev/null >> $MAYA_HOME/logs/serve.log 2>&1"
echo "starting; ready in a few minutes (longer from a hard disk): curl http://127.0.0.1:$MAYA_PORT/health"
