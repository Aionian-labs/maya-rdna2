# Settings shared by every script here. Edit them, or export them before running a script.
MAYA_HOME=${MAYA_HOME:-$HOME/maya-rdna2}                    # holds src/ (the patched project-maya checkout), logs/, scratch/, current
MAYA_MODELS=${MAYA_MODELS:-$MAYA_HOME/models}               # GGUF model folders; needs ~100 GB per model
MAYA_API_KEY_FILE=${MAYA_API_KEY_FILE:-$MAYA_HOME/API_KEY}  # one line; create it with: openssl rand -hex 24 > "$MAYA_API_KEY_FILE"
MAYA_HOST=${MAYA_HOST:-127.0.0.1}                           # 0.0.0.0 serves your network (the API key is always required)
MAYA_PORT=${MAYA_PORT:-8099}
ROCM_PATH=${ROCM_PATH:-/opt/rocm}
export MAYA_HOME MAYA_MODELS MAYA_API_KEY_FILE MAYA_HOST MAYA_PORT ROCM_PATH
mkdir -p "$MAYA_HOME/logs" "$MAYA_HOME/scratch"
