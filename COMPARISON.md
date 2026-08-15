---
title: pi-fable vs claude-fable — feature comparison
date: 2026-08-15
tags: [pi, claude-code, fable, comparison]
---

# pi-fable vs claude-fable

Same model (claude-fable-5), two harnesses: pi 0.84.x vs Claude Code.
Legend: ✅ present · ➕ present, richer · ❌ absent (by design where noted) ·
❓ unverified. Sources: two days of hands-on use, pi docs, session evidence.

## Model control

| Feature | pi-fable | claude-fable |
|---|---|---|
| Effort levels | ✅ `--thinking` → effort (xhigh maps to **max**; literal xhigh tier unreachable) | ➕ full ladder incl. xhigh (its default) |
| Mid-session level change | ✅ `/settings` | ✅ |
| Model switching mid-session | ➕ `/model`, Ctrl+P — across providers, incl. LOCAL models | ✅ Anthropic models only |
| Non-Anthropic / local models | ➕ any OpenAI-compatible endpoint (the whole point of this repo) | ❌ |

## Context & memory

| Feature | pi-fable | claude-fable |
|---|---|---|
| Project context files | ✅ AGENTS.md + CLAUDE.md auto-load (global → parents → cwd); AGENTS.override.md; SYSTEM.md replacement | ✅ CLAUDE.md/AGENTS.md chain + imports |
| Persistent cross-session memory | ✅ via `pi-hermes-memory` (24K/mo) | ➕ native auto-memory, curated across sessions |
| Compaction | ✅ auto + `/compact` | ✅ auto + manual |
| Skills / reusable prompts | ✅ (extensions/skills/prompts, `/reload`) | ➕ mature skills system w/ auto-discovery |

## Tools & orchestration

| Feature | pi-fable | claude-fable |
|---|---|---|
| Core tools (read/bash/edit/write, grep/glob) | ✅ | ✅ |
| Web search / fetch | ✅ via `pi-web-access` (222K/mo) | ✅ built-in |
| MCP client | ✅ via `pi install npm:pi-mcp-adapter` | ➕ full ecosystem (connectors, local servers) |
| Sub-agents / parallel fan-out | ✅ via `pi-subagents` (214K/mo), `pi-dynamic-workflows` | ➕ native agents, workflows, teams |
| Background tasks + monitors | ✅ via `pi-background-tasks` (27K/mo) | ➕ native (ran the embers/chess sessions) |
| Plan mode / to-dos | ✅ via `rpiv-todo` (43K/mo), `pi-goal` (30K/mo) | ✅ native |
| Scheduled / cloud sessions | ❌ | ✅ (cron routines, remote sessions) |
| Hooks on tool use | ❌ (extensions can intercept) | ✅ (treefmt/shellcheck gate fired all session) |

## Safety

| Feature | pi-fable | claude-fable |
|---|---|---|
| Permission prompts | ❌ core (YOLO) — ✅ via `pi-permission-system` (27K/mo) | ✅ native modes + allowlists |
| Sandbox | ❌ (community: pi-sandbox) | ✅ sandboxed bash available |
| Upfront tool allow/deny | ✅ `--tools` / `--exclude-tools` | ✅ |

## Sessions & UX

| Feature | pi-fable | claude-fable |
|---|---|---|
| Session persistence | ✅ plain JSONL per project | ✅ |
| Branch/fork/tree navigation | ➕ `/tree`, `/fork`, `/clone` | ✅ rewind/checkpoints |
| Export/share | ➕ `/export`, `/share` (gist), `/import` | ✅ (transcripts; artifacts publishing) |
| Scripting mode | ✅ `-p`, `--mode json/rpc` (NB: `-p` sends no thinking level) | ✅ `-p`, JSON output, full SDK |
| Live telemetry | ➕ ribbon: ↑↓ tokens, R reasoning, cache %, ctx % | ✅ /context, /cost views |
| Footprint / startup | ➕ minimal, instant | heavier |

## Cost & ops

| Feature | pi-fable | claude-fable |
|---|---|---|
| Billing | API pay-per-token ($10/$50 MTok on Fable) | subscription or API |
| Prompt caching on Anthropic | ❓ verify (ribbon shows cache % on llama.cpp; Anthropic cache_control unconfirmed) | ✅ aggressive, automatic |
| Zero-cost fallback | ➕ one `/model` away (local qwen) | ❌ |

## Ecosystem check (pi.dev/packages, 2026-08-15)

5,300+ packages; the top-25 by downloads re-adds nearly every deliberate core
omission: `pi-mcp-adapter` 354K/mo, `pi-web-access` 222K, `pi-subagents` 214K,
`context-mode` 73K, `rpiv-ask-user-question` 52K, `rpiv-todo` 43K, `pi-lens`
(LSP/lint feedback) 41K, `pi-goal` 30K, `pi-permission-system` 27K,
`pi-background-tasks` 27K, `pi-hermes-memory` 24K. The market voted to rebuild
the fat harness on top of the thin one.

## Reading

- **pi's core omissions are a manifesto, and the ecosystem filled them
  anyway** — every ❌-in-core row above has a popular package. The real
  deltas are therefore not features but *depth and trust*: native
  integrations (CC's background tasks feed its agent loop; its hooks gate
  every edit; its memory is curated by the same vendor as the model) vs
  third-party bolt-ons of varying maintenance, each of which is arbitrary
  code you `pi install` into a YOLO harness — vetting them is on you.
- **claude-fable's missing list is one item, but it's structural**: no
  non-Anthropic models — no local, no free, no confidential-on-device.
- **Where the gap bites, per our evidence**: orchestration-heavy work,
  cross-session memory, and safety rails are native-and-integrated on
  claude-fable, assembled-and-self-vetted on pi-fable. Model quality is
  identical by construction — so pi-fable is a *fine* Fable client for
  single-threaded interactive coding, plausibly more with curated packages,
  and the 2×2 (qwen/fable × pi/CC) measures how much the difference matters.
