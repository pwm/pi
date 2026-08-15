#!/usr/bin/env bash
# Serve the local Qwen3.8-27B with llama.cpp's OpenAI-compatible server, for
# the pi coding-agent experiment. Adapted from brossa-mcp/start-llama.sh with
# the same measured defaults (see SETUP.md in this repo):
#   UD-Q8_K_XL quant     — decodes FASTER than Q6_K on this machine
#   MTP speculation      — lossless +25-40% decode
#   fixed v22 template   — working fast-mode, deduped think blocks (guarded)
#   thinking OFF default — re-enable per-request via chat_template_kwargs
#   full 262144 context  — with q8_0 KV cache to keep it affordable
#
# llama-server comes from the niv-pinned nix shell (.envrc / shell.nix):
# nixos-unstable's llama-cpp (build 10273+) knows the qwen3.8 arch and every
# flag used here — no bundled release binaries needed in this repo.
#
# Usage:
#   ./llama-server.sh [27b] [--bg]
#   QUANT=Q6_K ./llama-server.sh              # override the quant
#   LLAMA_PORT=8080 ./llama-server.sh         # override the port (default 11434)
#   LLAMA_EXTRA_ARGS="-c 32768" ./llama-server.sh   # extra/override flags (win: last)
#
# The model + template are symlinked from brossa-mcp/models (31GB, no copy);
# the download hint below covers a standalone setup.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
model_dir="${MODEL_DIR:-$script_dir/models}"
log_dir="${LOG_DIR:-$script_dir/logs}"
mkdir -p "$log_dir"

# One model instance at a time: a second full instance exhausts GPU memory
# (weights share page cache via mmap; KV/compute buffers do not — measured).
if pgrep -x llama-server >/dev/null && [[ ${FORCE:-0} != "1" ]]; then
  echo "A llama-server process is already running (any port). Stop it first; FORCE=1 to override."
  exit 1
fi

# Parse model size argument (default 27b). A leading --bg means "default size".
SIZE="${1:-27b}"
[[ $SIZE == "--bg" ]] && SIZE="27b" || shift || true

case "$SIZE" in
27b | 27B)
  MODEL_REPO="unsloth/Qwen3.8-27B-GGUF"
  MODEL_BASE="Qwen3.8-27B"
  MODEL_NAME="qwen3.8-27b"
  DEFAULT_QUANT="UD-Q8_K_XL"         # ~31GB; faster than Q6_K here (simpler q8_0 dequant) — measured
  MODEL_CTX=262144                   # full native context (q8_0 KV below makes it affordable)
  MODEL_ARGS="--spec-type draft-mtp" # lossless self-speculation via the GGUF's embedded MTP head
  MODEL_ARGS+=" -a qwen3.8-27b"      # model name reported by /v1/models
  # Qwen-recommended thinking-mode sampler DEFAULTS — apply only to requests
  # that send no sampling params of their own:
  MODEL_ARGS+=" --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0"
  MODEL_ARGS+=" -ctk q8_0 -ctv q8_0" # 8-bit KV cache
  # Thinking OFF by default (measured: reflexes faster and no worse for
  # interactive use); per-request re-enable via chat_template_kwargs
  # {"enable_thinking":true,"reasoning_effort":"medium"}.
  MODEL_ARGS+=" --reasoning off"
  # froggeric's fixed Qwen template (v22) — template-level fast mode works,
  # blank think blocks deduped. Committed in this repo (templates/); source:
  # huggingface.co/froggeric/Qwen-Fixed-Chat-Templates
  if [[ -f $script_dir/templates/qwen-fixed-v22.jinja ]]; then
    MODEL_ARGS+=" --chat-template-file $script_dir/templates/qwen-fixed-v22.jinja --reasoning-format deepseek"
  fi
  ;;
*)
  echo "Usage: $0 [27b] [--bg]   (QUANT=… to override the quant)"
  echo ""
  echo "Models:"
  echo "  27b  - Qwen3.8 27B dense (UD-Q8≈31GB + MTP; REASONING model, served thinking-off)"
  exit 1
  ;;
esac

QUANT="${QUANT:-$DEFAULT_QUANT}"
MODEL_FILE="${MODEL_BASE}-${QUANT}.gguf"
MODEL_PATH="$model_dir/$MODEL_FILE"
PORT="${LLAMA_PORT:-11434}"

if [[ ! -f $MODEL_PATH ]]; then
  echo "Error: model not found at $MODEL_PATH"
  echo ""
  echo "Symlink the existing download (preferred, no copy):"
  echo "  ln -s ~/work/brossa/brossa-mcp/models/$MODEL_FILE '$model_dir/'"
  echo "Or download it:"
  echo "  huggingface-cli download $MODEL_REPO $MODEL_FILE --local-dir '$model_dir'"
  exit 1
fi

echo "Model: $MODEL_NAME @ $QUANT ($MODEL_PATH)"
echo "Serving on http://127.0.0.1:$PORT  (OpenAI-compatible; tool calls via --jinja)"
echo "Log: $log_dir/llama.log"
echo ""

# -ngl 99: offload all layers to Metal. -c: per-model context (MODEL_CTX from
# the case above). --jinja: use the chat template so /v1/chat/completions
# emits OpenAI-style tool_calls.
llama_args=(-m "$MODEL_PATH" --port "$PORT" --host 127.0.0.1 -ngl 99 -c "${MODEL_CTX:-16384}" --jinja)

# Per-model flags from the case above.
if [[ -n ${MODEL_ARGS:-} ]]; then
  read -ra model_args <<<"$MODEL_ARGS"
  llama_args+=("${model_args[@]}")
fi

# Optional extra flags, word-split; later flags override earlier ones.
if [[ -n ${LLAMA_EXTRA_ARGS:-} ]]; then
  read -ra extra_args <<<"$LLAMA_EXTRA_ARGS"
  llama_args+=("${extra_args[@]}")
fi

if [[ ${1:-} == "--bg" ]]; then
  echo "Starting llama-server in background (screen session: llama)..."
  screen -dmS llama bash -c "llama-server ${llama_args[*]} 2>&1 | tee '$log_dir/llama.log'"
  echo "Use 'screen -r llama' to attach, Ctrl+A then D to detach."
else
  llama-server "${llama_args[@]}" 2>&1 | tee "$log_dir/llama.log"
fi
