---
title: Local Qwen3.8-27B on the M2 Max — llama.cpp setup, flags, and measurements
date: 2026-08-15
tags: [local-llm, llama-cpp, qwen, pi]
---

# Local Qwen3.8-27B setup

TLDR: `./llama-server.sh` (this repo) serves Qwen3.8-27B at its best measured
configuration on this machine (M2 Max, 96GB). Everything below was measured or
verified on 2026-08-14/15 with llama.cpp release b10431; this repo's
niv-pinned nix llama.cpp (b10273+) runs the identical stack.

## The model

- File: `models/Qwen3.8-27B-UD-Q8_K_XL.gguf` (~31GB, unsloth dynamic 8-bit;
  most tensors q8_0). This repo is the canonical home;
  `~/work/brossa/brossa-mcp/models/` symlinks here
- Dense 27B reasoning model, native context 262,144 tokens (per GGUF metadata
  `qwen35.context_length`), vision-capable (mmproj not loaded in our setup)
- Architecture tag is `qwen35` — needs a recent llama.cpp. Here that comes
  from the niv-pinned nixpkgs (`niv update nixpkgs` to bump); the brossa-mcp
  sibling predates this and uses downloaded release binaries instead
- Re-download: `huggingface-cli download unsloth/Qwen3.8-27B-GGUF
  Qwen3.8-27B-UD-Q8_K_XL.gguf --local-dir models`

## The server flags (what `llama-server.sh` runs)

```
llama-server
  -m …/Qwen3.8-27B-UD-Q8_K_XL.gguf         # weights
  --host 127.0.0.1 --port 11434             # localhost only
  -ngl 99                                   # all layers on Metal
  -c 262144                                 # full native context
  -ctk q8_0 -ctv q8_0                       # 8-bit KV cache (halves KV memory)
  --jinja                                   # use the jinja chat template
  --chat-template-file …/qwen-fixed-v22.jinja   # fixed template (see below)
  --reasoning off                           # DEFAULT: thinking hard-off (b10431+
                                            #   deprecates the enable_thinking kwarg
                                            #   server-side; per-request kwargs still work)
  --reasoning-format deepseek               # parse <think> → reasoning_content
  --spec-type draft-mtp                     # MTP self-speculation (lossless)
  -a qwen3.8-27b                            # API model name
  --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0  # sampler defaults for clients
                                            #   that send no sampling params
```

Env knobs: `QUANT=` (other quant), `LLAMA_PORT=`, `LLAMA_EXTRA_ARGS=` (appended
last, so it overrides), `MODEL_DIR=`. Every llama.cpp flag also exists as a
`LLAMA_ARG_*` environment variable.

Note on the sampler defaults: temp 1.0 / top-p 0.95 is Qwen's *thinking-mode*
recommendation. The default is thinking-off, where Qwen recommends 0.7 / 0.8
with presence penalty 1.5. This only affects clients that send no sampling
params; `brossa-mcp/chat.sh` picks the matching set automatically.

## The fixed chat template

`templates/qwen-fixed-v22.jinja` — committed in this repo
(`~/work/brossa/brossa-mcp/models/templates/` symlinks here), from
[froggeric/Qwen-Fixed-Chat-Templates](https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates).

Why it replaces the GGUF's embedded template (all verified locally):

- `enable_thinking: false` works (true fast mode, 2-3 token replies). The
  official 3.8 template raises an exception on it
- `reasoning_effort: "none"` no longer throws (but see nuance below)
- Dedupes blank `<think></think>` blocks in history (the suspected cause of
  empty replies we observed at temp 1.0)
- minijinja-safe filters; tool calls, reasoning separation verified identical

`llama-server.sh` uses it only when the file exists, so the server still works
on the GGUF's embedded template if the file is removed.

## Controlling thinking

Per-request, via `chat_template_kwargs` in any `/v1/chat/completions` body:

| Setting | Effect |
|---|---|
| *(nothing)* | Server default: thinking OFF |
| `{"enable_thinking": true, "reasoning_effort": "medium"}` | Thinking on at medium |
| `reasoning_effort`: `xhigh` (template default) / `high` (alias of xhigh) / `medium` / `low` | Graded depth |
| `{"enable_thinking": false}` | Hard off (2-3 token replies) |
| `{"preserve_thinking": true}` | Keep prior turns' reasoning in history (client must echo `reasoning_content` back) |

Nuances learned the hard way:

- Template-level `reasoning_effort: "none"` only *reduces* thinking (~136 chars
  leaked in tests). `enable_thinking: false` is the true zero. The top-level
  OpenAI param `reasoning_effort: "none"` also fully suppresses (llama.cpp
  intercepts it before the template)
- Server-side, the b10431+ spelling for the default is `--reasoning on|off|auto`
  (setting `enable_thinking` via `--chat-template-kwargs` warns as deprecated);
  per-request `chat_template_kwargs: {"enable_thinking": …}` still works and
  overrides the server default (verified both directions)
- `--reasoning-budget 0` is a silent no-op for this model's template — don't use
- `preserve_thinking` did NOT provide mistake-memory in testing (an agent
  repeated the identical fatal game choice with its own prior reasoning in
  context). Rejected as a default

### Thinking from pi (both engines)

pi transmits NOTHING at thinking level off, and the plain OpenAI
`reasoning_effort` param otherwise — which works on neither engine here:
oMLX ignores the param outright, and llama's `--reasoning off` beats it
(proven 2026-08-17 by a full pi-"medium" run with zero thinking blocks).
The fix: both model entries in models.json carry the same `compat` block
(`thinkingFormat: "chat-template"` with `$var`-substituted
`chatTemplateKwargs`), so every pi level maps to per-request
`chat_template_kwargs`: `enable_thinking: <level != off>`,
`reasoning_effort: <level>`, `preserve_thinking: true` — plus
`thinkingLevelMap: { minimal: low, max: xhigh }` because the template only
knows low/medium/high/xhigh (unknown values silently fall back to xhigh).
Keep the server default `--reasoning off`: the explicit
`enable_thinking: false` the compat sends at level off is what makes off
actually off, and the server default covers non-pi clients. Verified on
oMLX by making the model quote the injected effort sentence, and on llama
in both directions.

## Measurements (M2 Max 96GB, b10431)

| What | Number |
|---|---|
| Decode, Q8_K_XL plain | ~10.4 tok/s |
| Decode, Q6_K_XL plain | ~9.9 tok/s (Q8 is *faster*: simpler q8_0 dequant kernel) |
| Decode, Q8 + MTP | ~13-16 tok/s (lossless speculation, draft head ships in the GGUF) |
| Prefill | ~50-60 tok/s (compute-bound; the real interactive bottleneck) |
| Embers game, thinking off | won in 73 s (39 turns, ~1.9 s/turn) |
| Embers game, medium + preserve | won in 10m55s (48 turns, ~14 s/turn) |
| Cold prefill, 16k agent prompt (2026-08-18 A/B) | llama **~155 tok/s**, oMLX ~100 tok/s |
| Decode of a 4k-token answer at ~22k context (2026-08-18 A/B) | llama+MTP **~4.5 tok/s**, oMLX **~7.6 tok/s** |

The two prefill rows disagree (50-60 vs ~155 tok/s); they were measured months
of config apart and the discrepancy is unresolved — trust the dated A/B pair
for current behaviour. The context-depth row is the important asymmetry:
llama+MTP's 13-16 tok/s decode holds only near-empty; at ~22k it sags below
oMLX, which degrades more gracefully.

Conclusions baked into the defaults: Q8 weakly dominates Q6 (quality ≥, speed ≥);
MTP is free speed at shallow context; thinking off is the right default for
reflex-style interactive use, with per-request opt-in when a task deserves
deliberation — and for agentic multi-step tasks, medium thinking measured
strictly better wall-clock (fewer, better tool calls: 15-20 min vs 39 min-2h
on the same review task).

## Second engine: oMLX (MLX)

[oMLX](https://omlx.ai/) is the second inference engine (Apple MLX instead of
llama.cpp), used for engine A/Bs. Installed manually as a menubar app (not
nix); managed via `omlx start | stop | restart | diagnose` — the CLI is on
PATH via nix-home's
[`hm/home/default.nix`](https://github.com/pwm/nix-home/blob/master/hm/home/default.nix)
(symlink to the app's own `~/.omlx/bin/omlx` bootstrap shim).

- **Config**: `~/.omlx/settings.json` (the UI writes it too — we treat it as
  file-only). Mirrors the llama defaults where a mapping exists: 262144
  context, temp 1.0 / top-p 0.95 / top-k 20, HF-cache model discovery. No
  equivalents for q8_0 KV quant or MTP speculation
- **Model**: `mlx-community/Qwen3.8-27B-8bit` in the HF cache
  (`~/.cache/huggingface/hub/`) — oMLX discovers it there. The `-MTP-8bit`
  variant was a broken 451MB stub upstream as of 2026-08-16
- **Fixed chat template**: MLX repos ship the official template (fast-mode
  crash bug) — swap `chat_template.jinja` inside the model's snapshot dir for
  `templates/qwen-fixed-v22.jinja` from this repo; redo after any re-download
- **pi provider**: `omlx-local` @ `127.0.0.1:12121` (registry in nix-home) —
  switch engines with `/model`
- **Parallel engines — residency yes, both active no**: llama + oMLX can sit
  resident together on 96GB (llama's weights are evictable mmap, oMLX's are
  owned buffers), but both actively decoding thrashes (12GB swap in ~2 min),
  and after oMLX loads and serves, llama-server decode can wedge permanently
  ("Compute error", ggml ret -3, on every request while `/health` still says
  ok) — restart llama, ideally after `omlx stop`. A second *llama* instance
  still OOMs outright

## Config surfaces (it is not just flags + template)

1. **GGUF metadata** — arch, context, tokenizer, embedded template, quant.
   Overridable at load with `--override-kv`
2. **Server flags / `LLAMA_ARG_*` env** — the list above
3. **Chat template + `--chat-template-kwargs`** — prompt rendering; the kwargs
   flag sets template-variable *defaults*
4. **Per-request API params** — sampling, `chat_template_kwargs`, tools,
   `max_tokens`; overrides layers 2-3 for that request
5. **Wrapper env knobs** — `start-llama.sh` (`QUANT`, `LLAMA_PORT`,
   `LLAMA_EXTRA_ARGS`) and the brossa-mcp harnesses (`LLM_TEMPERATURE`,
   `LLM_REASONING_EFFORT`, `LLM_PRESERVE_THINKING`, `LLM_API_KEY`, `LLAMA_URL`)
6. **OS level** — macOS Metal wired-memory limit (`iogpu.wired_limit_mb`),
   relevant only near ~72GB of GPU allocations

Mental model: the model file proposes, flags dispose, the template phrases, and
the request gets the last word.

## Terminal chat: `chat.sh` (lives in the brossa repo)

The standalone llama-cli chat script is `~/work/brossa/brossa-mcp/chat.sh` — a
companion from the same measurement sessions; it consumes this repo's model
and template via the brossa-side symlinks:

```bash
cd ~/work/brossa/brossa-mcp
./chat.sh                      # fast mode: thinking off, non-thinking samplers
THINK=1 ./chat.sh              # thinking on (raw <think> visible — the CLI does
                               #   not separate reasoning like the server does)
EFFORT=xhigh THINK=1 ./chat.sh # deeper thinking
CTX=32768 ./chat.sh            # smaller context (default 262144 = model max)
```

Extra args pass through to `llama-cli` (e.g. `--single-turn -p "hi"`). Exit with
Ctrl-D.

Manual copy-paste equivalent of the default (fast mode) — no server-running
guard, so stop the server first. The `` `# …` `` comments are no-op command
substitutions, so the block pastes as-is into bash/zsh; fish does not support
them — there, strip the comments or run the block via `bash -c '…'`:

```bash
cd /Users/pwm/work/pi   # llama-cli comes from the nix shell via direnv
llama-cli \
  --model models/Qwen3.8-27B-UD-Q8_K_XL.gguf `# the weights: unsloth dynamic 8-bit, ~31GB` \
  --n-gpu-layers 99 `# offload every layer to the Metal GPU` \
  --ctx-size 262144 `# full native context window (the model's maximum)` \
  --cache-type-k q8_0 `# 8-bit K cache — halves KV memory, negligible quality cost` \
  --cache-type-v q8_0 `# 8-bit V cache — same` \
  --jinja `# render with the jinja chat template (required for clean chat/tools)` \
  --chat-template-file templates/qwen-fixed-v22.jinja `# fixed v22 template: working fast-mode, deduped think blocks` \
  --reasoning off `# thinking hard-off, fast mode (b10431+ spelling)` \
  --spec-type draft-mtp `# MTP self-speculation: lossless +25-40% decode speed` \
  --temp 0.7 `# Qwen non-thinking-mode sampler recommendations from here down` \
  --top-p 0.8 `# nucleus sampling cutoff` \
  --top-k 20 `# candidate pool size` \
  --min-p 0.0 `# no minimum-probability filter` \
  --presence-penalty 1.5 `# discourage repetition (Qwen rec for non-thinking mode)`
```

Thinking variant: swap the `--reasoning off` line for
`--reasoning on --chat-template-kwargs '{"reasoning_effort":"medium"}'`,
use `--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0`, and drop the presence
penalty. Raw `<think>` text will be visible (the CLI does not separate
reasoning).

**Gotcha (measured):** the 256K-KV server and a chat.sh instance do not fit on
the GPU together — weights share page cache via mmap, but each process wires its
own KV/compute buffers, and the second instance dies with a Metal
out-of-memory. `chat.sh` detects the running server and refuses (override with
`FORCE=1`). Use the server's web UI (`http://127.0.0.1:11434/`) when the server
is up; use `chat.sh` when it isn't.

## Endpoints and clients

- Web UI: `http://127.0.0.1:11434/` (per-message settings via its custom-params
  JSON box)
- OpenAI-compatible API: `http://127.0.0.1:11434/v1` — works with pi (custom
  provider in `~/.pi/agent/models.json`, `api: "openai-completions"`), aider,
  `llm`, curl, and the brossa-mcp demo harnesses
- Tool calling works out of the box (`--jinja` + the template); verified
  OpenAI-style `tool_calls` with valid JSON arguments
