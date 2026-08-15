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

- Provider registry: `~/nix-home/hm/programs/pi/models.json` (home-manager
  deploys it to `~/.pi/agent/models.json`)
- Defaults (so bare `pi` works): `~/.pi/agent/settings.json` — plain file,
  deliberately not hm-managed (`pi install` mutates it)

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
  literal xhigh tier is unreachable from pi). Interactive sessions only;
  `-p` sends nothing (Fable then defaults to effort high)
- Why bother: same-task runs across qwen-in-pi, fable-in-pi, and
  fable-in-Claude-Code form a model × harness 2×2 — it isolates what the
  harness contributes from what the model contributes

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
- Full setup reference (flags, measurements, thinking control): [SETUP.md](./SETUP.md)
