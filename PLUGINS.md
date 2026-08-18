---
title: pi plugins worth installing
date: 2026-08-17
tags: [pi, plugins, extensions, local-llm]
---

# pi plugins worth installing

Curated from the pi.dev/packages survey in [COMPARISON.md](./COMPARISON.md)
(download counts as of 2026-08-15), filtered by what our setup actually needs
(local qwen + Fable, YOLO core, the task ladder in [PLAN.md](./PLAN.md)).

TLDR: install tier 1 before pointing pi at real repos; pull tier 2 in when a
ladder rung wants it; tier 3 mostly makes sense on Fable, not the local model.

**Vetting rule first**: pi has no sandbox and no prompts. Every package is
arbitrary code that runs with your user's permissions inside a YOLO harness.
Read the repo (pi.dev links to source) before `pi install`, pin what you
vetted, and prefer fewer packages over more.

## Install mechanics

Run installs **from this repo** — pi shells out to `npm`, which comes from
this repo's nix shell (nodejs in `shell.nix`), not from the global profile.
Already-installed plugins load everywhere without npm; only
`pi install`/`pi update` need it.

```bash
cd ~/work/pi
pi install npm:<package>@<version>   # pin! e.g. npm:pi-mcp-adapter@2.26.0
/reload                              # pick up new extensions in a running session
```

`pi install` mutates `~/.pi/agent/settings.json` — which is exactly why that
file is a plain file and not hm-managed (see README). The models.json
registry stays hm-owned; plugin state lives with pi.

## Tier 1 — before real-repo use

| Package | Downloads/mo | Why for us |
|---|---|---|
| `pi-permission-system` | 27K | The missing approval prompts. Our regime (read-only allowlist in real repos, YOLO in scratch) is coarse; prompts make full-capability sessions in real repos survivable. Evaluate against `pi-sandbox` — likely want one, not both |
| `pi-sandbox` | — | The other half of the safety gap: actual isolation instead of asking. If it composes with worktrees cleanly it may beat prompts for our use |
| `pi-mcp-adapter` | 354K | The most-downloaded package in the registry, and our concrete use case: point pi at **brossa-mcp** (the rung-5 idea) so the local model drives Brossa specs through guarded tools instead of raw bash |
| `pi-lens` | 41K | LSP/lint feedback on edits. Directly targets the local model's weak spot from the ladder (rung 3, failing-test fix): a 27B benefits far more from mechanical error feedback than from more thinking |

## Tier 2 — when a ladder rung wants it

| Package | Downloads/mo | Why for us |
|---|---|---|
| `rpiv-todo` | 43K | Plan/to-do tracking for multi-step rungs; keeps the 27B honest about what remains. Pick this **or** `pi-goal`, not both |
| `pi-goal` | 30K | Same niche, goal-oriented framing |
| `pi-web-access` | 222K | Web search + fetch. Needed the moment a task requires docs lookup; note it sends your queries out, so keep it out of confidential-on-device sessions (that being one of the reasons this local stack exists) |
| `rpiv-ask-user-question` | 52K | Structured "ask the user" tool; useful once sessions get long enough that steering matters |

## Tier 3 — Fable-mostly (skip on the local engine)

| Package | Downloads/mo | Why deferred |
|---|---|---|
| `pi-subagents` | 214K | Parallel fan-out multiplies prefill, and one GPU serves one decode at a time — on local qwen this serializes into slower, not faster (the parallel-engines experiments made that vivid). With `--provider anthropic` it becomes genuinely useful |
| `pi-background-tasks` | 27K | Same story: background turns still contend for the single local server |
| `pi-dynamic-workflows` | — | Orchestration DSL on top of subagents; same constraint |
| `pi-hermes-memory` | 24K | Cross-session memory. Nice-to-have; every injected memory is prefill at 50-60 tok/s on llama, so on the local model it taxes exactly the resource we are short of |

## Investigate before deciding

- `context-mode` (73K/mo) — top-25 by downloads but our survey did not record
  what it does; read the repo before forming an opinion.

## Can home-manager manage these?

**Decision (2026-08-17): no — pi manages its own plugins.** Path of least
resistance and correct for the churn phase: the pinned `packages` list +
pi's install-missing-on-startup already give reproducibility, and hm-switch
per plugin experiment is friction with no payoff. Discipline instead of
machinery: pin versions (`npm:pkg@x.y.z`), read source before first install.
Revisit hm only if a vetted single-file extension becomes load-bearing
(e.g. a safety gate) — then vendor it via `home.file` into
`~/.pi/agent/extensions/`. Mechanics below kept for that future case
(verified against pi 0.84.1 source, `core/package-manager.js`):

- **Single-file extensions → hm, cleanly.** pi auto-discovers
  `~/.pi/agent/extensions/*.ts` (and `*/index.ts`) and only ever reads them.
  Deploy vetted files from nix-home via `home.file`, exactly like
  models.json. Vendoring the file IS the security review: the audited bytes
  are the running bytes, updates are git diffs. Hot-reload with `/reload`.
- **npm registry packages → stay pi-owned, but pin versions.** `pi install`
  writes a `packages` entry into settings.json (pi-owned, cannot be a store
  symlink) plus a disposable tree under `~/.pi/agent/npm/`. pi auto-installs
  anything missing from that tree at startup, and `npm:pkg@x.y.z` specs are
  pinned (skipped by `pi update --all`). Pinned list + disposable cache =
  reproducible without hm. Vet at pin-bump time.
- **Hybrid for critical packages: local path sources.** `pi install
  /absolute/path` registers a path re-resolved on every load, no install
  step. Point it at a vendored package dir in `~/nix-home` (stable
  out-of-store path, NOT a per-generation store path) for npm-style packages
  under git/hm control. Impractical for dep-heavy plugins (node_modules).

## Local-engine caveat that applies to ALL of these

Every extension that registers tools or injects prompt text grows the system
prompt, and on llama that is prefill at ~45-60 tok/s. **Measured 2026-08-17**
with 4 plugins installed (mcp-adapter, lens, web-access, hermes-memory):
system prompt + schemas = **~16k tokens** (~3x the bare harness). The very
first run after install took 5m48s (likely including one-time extension
bundling); clean cold-prefill measurements from the 2026-08-18 A/B pair:
llama **~103s** (~155 tok/s), oMLX **~162s** (~100 tok/s). Warm (prefix
cache): **~3s**. So the tax is paid once per llama-server lifetime per plugin set:
restarting the server, changing the plugin set, or anything else that edits
the system prompt re-pays the ~6 minutes. Watch `pi-hermes-memory`
specifically: if its injected memories change between sessions, the prefix
diverges early and the cache hit shrinks. On Fable the same bytes are cheap.
Working rule stands: keep the local set lean, let Fable carry the fat
harness.

## Installed (2026-08-17)

`pi-mcp-adapter@2.26.0`, `pi-lens@4.0.1`, `pi-web-access@0.23.0`,
`pi-hermes-memory@0.9.6` — all pinned. (hermes-memory promoted from tier 3
by pwm; see the caveat above for what to watch.)

### pi-web-access config (`~/.pi/web-search.json`, pi-owned)

Out of the box every search opens a local approval UI (the "curator") and
summarizes with `anthropic/claude-haiku-4-5`. Ours skips both — no UI, no
summary-model call, raw results go straight to the main agent:

```json
{
  "workflow": "none",
  "summaryModel": "llamacpp-local/qwen3.8-27b",
  "summaryGenerationDeadlineMs": 180000
}
```

- `workflow`: `summary-review` (default, curator UI) | `auto-summary`
  (no UI, model summary) | `none` (no UI, raw results — chosen because a
  second local-model call per search adds minutes for little gain; the main
  model reads the results itself). Runtime toggle: `/curator on|off|auto-summary`
- `summaryModel` + deadline are kept for when a summary IS requested
  (per-call `workflow: "auto-summary"`, or `/curator` toggles): local qwen,
  180s instead of the Haiku-sized 30s default — on timeout the tool silently
  falls back to a deterministic summary, which looks like the config being
  ignored
- The curator UI also writes this file (provider switches persist here),
  hence pi-owned, not hm
