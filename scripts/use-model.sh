#!/bin/bash
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/env.sh"
# use-model.sh s24|abliterated : which model start.sh / use-map.sh act on, then restart.
#   s24          Maya-S24
#   abliterated  huihui-ai abliterated UD-IQ2_XXS (set up with: maya.sh --gguf-dir)
case "$1" in
  s24) echo maya-maya-s24-hip > $MAYA_HOME/current ;;
  abliterated) echo maya-ud-iq2_xxs-hip > $MAYA_HOME/current ;;
  *) echo "usage: $0 s24|abliterated   (now: $(cat $MAYA_HOME/current 2>/dev/null || echo maya-maya-s24-hip))"; exit 2 ;;
esac
"$HERE/stop.sh" && "$HERE/start.sh"
