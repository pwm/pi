# pi + local Qwen3.8-27B

TLDR — serve the model, then use pi anywhere:

```bash
cd ~/work/pi && ./llama-server.sh --bg   # llama-server on :11434 (screen session "llama")
pi                                        # any directory; defaults point at the local model
```

Experiment repo for running the [pi coding agent](https://github.com/badlogic/pi-mono)
against a local Qwen3.8-27B via llama.cpp. The llama.cpp binary comes from the
niv-pinned nixpkgs (direnv + `shell.nix`); the server script carries measured
defaults (Q8_K_XL quant, MTP speculation, fixed chat template, thinking off,
262K context — see the setup notes below for why).

## Layout

- `llama-server.sh` — the server, tuned defaults inline; `QUANT=`, `LLAMA_PORT=`,
  `LLAMA_EXTRA_ARGS=` to override; refuses to start a second instance (GPU OOM)
- `templates/qwen-fixed-v22.jinja` — fixed Qwen chat template (committed;
  [source](https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates))
- `models/` — GGUFs, gitignored; this repo is the canonical home
  (`~/work/brossa/brossa-mcp/models/` symlinks here)
- `nix/` + `shell.nix` + `.envrc` — niv-pinned toolchain (`niv update nixpkgs`
  to bump llama.cpp)

## pi config

Everything declarative about this stack lives in the
[nix-home](https://github.com/pwm/nix-home) repo (`~/nix-home` locally):
pi itself (hm packages), the provider registry, and the oMLX CLI shim.
Change = edit there + `hm switch`.

- Provider registry:
  [`hm/programs/pi/models.json`](https://github.com/pwm/nix-home/blob/master/hm/programs/pi/models.json)
  (home-manager deploys it to `~/.pi/agent/models.json`)
- Defaults (so bare `pi` works): `~/.pi/agent/settings.json` — plain file,
  deliberately not hm-managed (`pi install` mutates it). Default thinking
  level is **medium** on both engines, delivered via the identical `compat`
  blocks in models.json (both entries send `chat_template_kwargs` — the plain
  `reasoning_effort` param does NOT survive llama's `--reasoning off`);
  `--thinking off` / the TUI switch for the fast no-thinking mode
- Installed plugins (2026-08-17, all pinned; pi-managed, not hm — see
  [PLUGINS.md](./PLUGINS.md) for tiers, rationale, and config):
  - `pi-mcp-adapter@2.26.0` — MCP client (target: brossa-mcp)
  - `pi-lens@4.0.1` — LSP/lint feedback on edits
  - `pi-web-access@0.23.0` — web search/fetch; configured in
    `~/.pi/web-search.json` for raw results (`workflow: none` — no curator
    approval UI, no summary-model call; qwen summarizes if one is requested)
  - `pi-hermes-memory@0.9.6` — cross-session memory
  - Plugin tax on llama, measured: system prompt ~15.3k tokens, first turn
    ~6 min cold, ~3s warm (prefix cache); run `pi install`/`pi update` from
    this repo (npm lives in its nix shell)

## Running Claude (Fable) instead of the local model

pi ships a built-in `anthropic` provider — no `models.json` entry needed:

```bash
# The key lives in .envrc.private (gitignored, direnv-sourced) — so this works
# from inside this repo; elsewhere, export ANTHROPIC_API_KEY yourself:
pi --provider anthropic --model claude-fable-5
```

Notes:

- Pricing is $10/$50 per MTok (input/output) — the local model is free; use
  Fable where judgment matters more than tokens
- Fable API quirks: thinking is always on (no off switch), and it rejects
  `temperature`/`top_p` outright. If pi's model registry predates Fable and
  sends sampling params (400 errors), add a custom model entry with a
  `compat` block instead of using the built-in registry
- Effort: pi's `--thinking` maps to Fable's `effort` param —
  minimal/low→low, medium→medium, high→high, xhigh→**max** (Anthropic's
  literal xhigh tier is unreachable from pi). Applies in `-p` mode too:
  `-p` follows `defaultThinkingLevel` and honors `--thinking` (verified
  2026-08-17; the earlier "`-p` sends nothing" was an artifact of the
  then-default off, which genuinely sends nothing)
- Why bother: same-task runs across qwen-in-pi, fable-in-pi, and
  fable-in-Claude-Code form a model × harness 2×2 — it isolates what the
  harness contributes from what the model contributes

## Second engine: oMLX (MLX)

[oMLX](https://omlx.ai/) is an alternative inference engine (Apple MLX instead
of llama.cpp) for A/B testing — installed manually as a menubar app (not nix;
accepted for the experiment), configured CLI/file-only:

```bash
omlx start | stop | restart | diagnose        # managed background server
```

The `omlx` CLI is on PATH via nix-home's
[`hm/home/default.nix`](https://github.com/pwm/nix-home/blob/master/hm/home/default.nix)
(`home.file` symlinks `~/.local/bin/omlx` to the app's own bootstrap shim at
`~/.omlx/bin/omlx`, which survives app updates) — no manual `ln -s`.

- **Config**: `~/.omlx/settings.json` (the UI writes here too — we treat it as
  file-only). Mirrors the llama defaults where a mapping exists: 262144
  context, temp 1.0 / top-p 0.95 / top-k 20, HF-cache model discovery.
  No equivalents for q8_0 KV quant or MTP speculation (llama keeps its decode
  edge)
- **Thinking control**: the ONLY knob that works on both engines is
  per-request `chat_template_kwargs` (`enable_thinking`, `reasoning_effort`,
  `preserve_thinking` — all reach the jinja template; verified on oMLX by
  making the model quote the injected effort sentence, and verified on llama
  to override `--reasoning off`). The plain OpenAI `reasoning_effort` param
  works on NEITHER: oMLX ignores it outright, and llama's `--reasoning off`
  beats it (verified 2026-08-17 — a full "medium" pi run produced zero
  thinking before the fix; the earlier belief that the param overrides the
  flag was wrong). So BOTH model entries in models.json carry the same
  `"compat"` block (`thinkingFormat: "chat-template"` with `$var`-substituted
  `chatTemplateKwargs`), mapping pi's thinking level to
  `enable_thinking: <level != off>` + `reasoning_effort: <level>`, plus
  `thinkingLevelMap: { minimal: low, max: xhigh }` since the template only
  knows low/medium/high/xhigh (unknown values silently fall back to xhigh).
  Keep the server-side defaults as they are: the explicit
  `enable_thinking: false` the compat sends at level off is what makes off
  actually off, and llama's `--reasoning off` covers non-pi clients
- **Model**: `mlx-community/Qwen3.8-27B-8bit` in the HF cache
  (`~/.cache/huggingface/hub/`) — oMLX discovers it there. The `-MTP-8bit`
  variant was broken upstream (451MB stub) as of 2026-08-16
- **Fixed chat template**: MLX repos ship the official template (fast-mode
  crash bug) — swap `chat_template.jinja` inside the model's snapshot dir for
  `templates/qwen-fixed-v22.jinja` from this repo; redo after any re-download
  (cache eviction loses it)
- **pi provider**: `omlx-local` @ `127.0.0.1:12121` (API key in models.json;
  registry owned by nix-home) — switch engines with `/model`
- **Parallel engines — residency yes, both active no**: llama + oMLX can be
  resident together on this 96GB machine (memory pressure normal, zero swap;
  llama's weights are evictable mmap, oMLX's are owned buffers). But after
  oMLX loaded and served its model, llama-server decode started failing
  ("Compute error", ggml ret -3, even on tiny requests) while its `/health`
  still said ok — restart llama (ideally after `omlx stop`) to recover.
  Nothing guards across engines, and a second *llama* instance still OOMs

## Permissions

pi has **no approval prompts and no sandbox, by design** (full YOLO: it runs
bash/write/edit with your user's permissions, unasked). Controls are upfront,
not interactive:

- **Tool allow/deny per invocation**: `pi --tools read,grep,find,ls` for a
  read-only agent in real repos; `--exclude-tools bash,write,edit` or
  `--no-builtin-tools` to strip execution entirely
- **Extensions** for prompts/sandboxing if ever wanted:
  [pi-permission-system](https://github.com/MasuRii/pi-permission-system),
  [pi-sandbox](https://github.com/carderne/pi-sandbox)
- **Environment**: full-capability sessions only in scratch/committed dirs

Regime for this experiment: read-only allowlist when pointing pi at real
repos; unrestricted only in throwaway directories.

## Notes

- One model instance at a time — a second llama-server or llama-cli OOMs the
  GPU (weights share page cache via mmap; KV/compute buffers do not)
- First pi turn in a session is slow (~1-2 min): system prompt + tool schemas
  prefill at ~50-60 tok/s; later turns ride the server's prefix cache
- Experiment plan + task ladder: [PLAN.md](./PLAN.md)
- pi-fable vs claude-fable feature matrix: [COMPARISON.md](./COMPARISON.md)
- Curated plugin install list: [PLUGINS.md](./PLUGINS.md)
- Full setup reference (flags, measurements, thinking control): [SETUP.md](./SETUP.md)
