#!/bin/bash
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/env.sh"
# Download huihui-ai/Huihui-GLM-5.3-Flash-abliterated-GGUF, UD-IQ2_XXS (4 files, 101.8 GB) into $MAYA_MODELS, resumable, then check each file's sha256 against Hugging Face's.
D=$MAYA_MODELS/Huihui-UD-IQ2_XXS
R=huihui-ai/Huihui-GLM-5.3-Flash-abliterated-GGUF
mkdir -p "$D" && cd "$D" || exit 1
curl -s -m 60 "https://huggingface.co/api/models/$R/tree/main/UD-IQ2_XXS" > tree.json
for i in 1 2 3 4; do
  f=GLM-5.3-Flash-UD-IQ2_XXS-0000$i-of-00004.gguf
  curl -L --fail --retry 8 --retry-delay 10 -C - -sS -o $f "https://huggingface.co/$R/resolve/main/UD-IQ2_XXS/$f" || { echo "DOWNLOAD_FAILED $f"; exit 1; }
  want=$(python3 -c "import json,sys;print(next((x['lfs']['oid'] for x in json.load(open('tree.json')) if x['path'].endswith('$f') and x.get('lfs')), ''))")
  have=$(sha256sum $f | cut -d' ' -f1)
  [ -n "$want" ] && [ "$want" = "$have" ] && echo "OK sha256 $f" || echo "SHA_MISMATCH_OR_UNKNOWN $f want=$want have=$have"
done
echo DL_DONE
