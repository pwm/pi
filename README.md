---
title: Pi and Oh My Pi model experiments
date: 2026-09-30
tags: [pi, omp, litellm, local-llm]
---

# pi + local models

TLDR — serve a model, then use pi anywhere:

```bash
cd ~/work/pi && ./llama-server.sh --bg   # llama.cpp server on :11434
pi                                        # any directory; defaults point at the local model
```

Lab repo for running the [pi coding agent](https://github.com/badlogic/pi-mono) against locally served models. It holds the runnable serving stack (pinned toolchain, tuned server script, committed chat templates, the weights) and the experiment notes. The point is not any one model: it is measuring what local inference can carry, and what the harness contributes vs the model (same task across local-in-pi, hosted-in-pi, hosted-in-Claude-Code). The current daily driver happens to be a Qwen3.8-27B; everything specific to it lives in [SETUP.md](./SETUP.md).

## Layout

- `nix/` + `shell.nix` + `.envrc`: niv-pinned toolchain
- `llama-server.sh`: llama.cpp server with measured defaults
  - `QUANT=`, `LLAMA_PORT=`, `LLAMA_EXTRA_ARGS=` to override
- `scripts/litellm`: start, stop, or check the LiteLLM Screen session
- `templates/` — committed chat templates (community fixes over upstream)
- `models/` — model weights, gitignored

## Config

Declarative config lives in my [nix-home](https://github.com/pwm/nix-home).

- pi itself (hm packages)
- the provider registry [`hm/programs/pi/models.json`](https://github.com/pwm/nix-home/blob/master/hm/programs/pi/models.json) linked to `~/.pi/agent/models.json` (why they exist: [SETUP.md](./SETUP.md))
- the oMLX CLI shim ([`hm/home/default.nix`](https://github.com/pwm/nix-home/blob/master/hm/home/default.nix))

Mutable state is pi-owned, deliberately not in hm:

- `~/.pi/agent/settings.json`, defaults so bare `pi` works (provider, model, thinking level)
- installed plugins and their config, see [PLUGINS.md](./PLUGINS.md)

## Engines

Two interchangeable OpenAI-compatible engines so far. Switch with `/model` inside pi:

- **llama.cpp** (default): `./llama-server.sh --bg`, port 11434
- **oMLX** (Apple MLX): `omlx start`, port 12121

One engine actively decoding at a time. Flags, templates, thinking control, measured performance, and the parallel-engine hazards: [SETUP.md](./SETUP.md).

## Hosted models (the other half of the experiment)

### Oh My Pi with GLM-5.3

[Oh My Pi](https://github.com/can1357/oh-my-pi) (`omp`) is installed through
nix-home from a pinned official release. It includes subagents, planning,
code review, task tracking, MCP, LSP integration, and web tools.

Run `omp` in any project. The writable global `~/.omp/agent/config.yml`
selects `litellm/glm-5.3:max` for the main agent and text-based helper roles.
Project settings or command-line options can override these defaults.
The provider registry lives in `~/nix-home/hm/programs/omp/models.yml` and
Home Manager deploys it to `~/.omp/agent/models.yml`.

Manage the LiteLLM gateway on port 4000 with:

```bash
./scripts/litellm start
./scripts/litellm status
./scripts/litellm stop
```

`start` loads direnv and runs LiteLLM in a detached Screen session. It also
checks that the gateway is healthy and reuses an existing session. Logs
append to `logs/litellm.log`. `status` exits with code 0 when healthy, or 1
when stopped or unhealthy. The script works from any directory.
The Z.ai key stays in the Git-ignored `.envrc.private`; OMP connects to the
local gateway. `stop` and `status` do not load the private environment.

Try `orchestrate` in a prompt for parallel delegation, `workflowz` for a
multi-step workflow, or `/review` for code review. `Alt+A` opens Agent Hub.
Browser/Python backends, language servers, and some external services can
need additional setup. OMP keeps global settings and sessions under `~/.omp`.
With `modelRoleStorage: global`, model-role changes are saved to
`~/.omp/agent/config.yml`. Project plugins and saved plans are Git-ignored.

### Hosted models in Pi

pi ships a built-in `anthropic` provider, no registry entry needed:

```bash
pi --provider anthropic --model claude-fable-5 # key via .envrc.private here
```

Pi's `--thinking` maps to provider effort levels (and applies in `-p` mode too, `-p` follows the settings default). Harness-vs-harness comparison: [COMPARISON.md](./COMPARISON.md).

## Permissions

pi has **no approval prompts and no sandbox, by design** (full YOLO: bash, write, and edit run with your user's permissions, unasked). Controls are upfront, not interactive: `--tools read,grep,find,ls` for read-only sessions, `--exclude-tools bash,write,edit` to strip execution, extensions ([pi-permission-system](https://github.com/MasuRii/pi-permission-system), [pi-sandbox](https://github.com/carderne/pi-sandbox)) if prompts are ever wanted.

## Docs (claude-written)

- [PLAN.md](./PLAN.md) — experiment plan, task ladder, answered open questions
- [SETUP.md](./SETUP.md) — the model/engine reference: flags, templates, thinking control, measurements, oMLX
- [COMPARISON.md](./COMPARISON.md) — pi-fable vs claude-fable harness matrix
- [PLUGINS.md](./PLUGINS.md) — plugin tiers, the installed set, plugin config
