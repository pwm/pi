---
title: Plan — pi coding agent on local Qwen3.8-27B
date: 2026-08-15
tags: [local-llm, pi, coding-agent, llama-cpp, qwen]
---

# Plan: pi coding agent on local Qwen3.8-27B

TLDR: point pi (0.79.1, installed via nix/home-manager) at the local
llama-server stack via a custom provider in `~/.pi/agent/models.json`, smoke
the connection and tool calls, then run a graded task battery in a scratch
repo. The open risks are per-turn prefill latency (~50-60 tok/s) and pi's
unsandboxed bash/write tools; both have mitigations below.

## What is already verified (2026-08-15)

- pi 0.79.1 on PATH (`~/.nix-profile/bin/pi`); no `~/.pi/agent/models.json`
  yet; supports `--provider`, `--model`, `--thinking off..xhigh`, `-p`
  (non-interactive), `--tools/--exclude-tools`, sessions
- The server stack works end to end: Q8_K_XL + MTP + fixed template on
  llama.cpp b10431; OpenAI-style `tool_calls` verified with valid JSON args
- Speeds (measured): decode ~13-16 tok/s with MTP, prefill ~50-60 tok/s,
  fast-mode replies ~2 tokens for trivial prompts
- Server default is thinking-OFF (`--reasoning off`), per-request re-enable
  via `chat_template_kwargs`

## Step 1 — server

Run this repo's server (it already has everything pi needs):

```bash
cd ~/work/pi && ./llama-server.sh --bg
```

Notes:
- Port 11434 (script default). If a manually started :8080 instance is
  running instead, adjust `baseUrl` below — do NOT run both (GPU OOM,
  measured)
- Context 262144 + q8_0 KV is the default — right for a coding agent
  (multi-file context)
- llama-server does per-slot prefix caching: pi conversations are
  append-only, so turn N+1 only prefills the new tokens. First turn pays
  the full system-prompt + tool-schema prefill

## Step 2 — register the provider

Create `~/.pi/agent/models.json`:

```json
{
  "providers": {
    "llamacpp-local": {
      "baseUrl": "http://127.0.0.1:11434/v1",
      "api": "openai-completions",
      "apiKey": "none",
      "models": [
        {
          "id": "qwen3.8-27b",
          "name": "Qwen3.8 27B (local Q8+MTP)",
          "contextWindow": 262144,
          "maxTokens": 8192,
          "reasoning": true
        }
      ]
    }
  }
}
```

- `id` must be a string the server accepts — ours reports the alias
  `qwen3.8-27b` on `/v1/models`, so use exactly that
- `apiKey` is required by pi even though llama-server ignores it
- The file hot-reloads when opening `/model` inside pi

## Step 3 — smoke tests (cheap, in order)

1. **Connectivity**:
   `pi --provider llamacpp-local --model qwen3.8-27b -p "reply with: ready"`
2. **Tool round-trip** (in some scratch dir):
   `pi --provider llamacpp-local --model qwen3.8-27b -p "read ./README.md and state its first heading"`
   — watch the server log to confirm a `tool_calls` request/response cycle
3. **Thinking mapping probe**: run the same prompt with `--thinking off`,
   `low`, `medium`; check the server log / `timings` for whether pi sends
   `reasoning_effort` (and whether our template honors it) or does nothing.
   This decides whether thinking control lives in pi or stays server-side
4. **Sampling probe**: check whether pi sends its own `temperature`; if not,
   the server's thinking-mode defaults (temp 1.0) apply — for coding we
   likely want 0.7/0.8, either via a pi setting (investigate `pi config`)
   or by adjusting server defaults for the session

## Step 4 — task battery (scratch repo, graded)

Work in a throwaway clone (`git init` scratch or a copy of a small repo),
never the primary checkout. Suggested ladder, one rung per session:

1. **Read-only**: "summarize what chat.sh does" (copy of the file) — tests
   multi-tool read/grep without write risk
2. **Single-file edit**: "add a --version flag to this script" — tests
   edit tool + diff quality
3. **Small feature with verification**: a toy repo with a failing test:
   "make the test pass" — tests bash (run tests) + edit loop
4. **Stretch**: a real (copied) brossa-mcp task, e.g. "add a MOVES env knob
   to embers_play.ts" — tests TypeScript competence + larger context

Score each rung: task success, illegal/malformed tool calls (server log),
turns needed, wall-clock.

## Expectations (set them now, from measured numbers)

- **First turn will feel slow**: pi's system prompt + tool schemas +
  the user prompt is likely 3-6k tokens → 60-120s prefill before the first
  token. Subsequent turns ride the prefix cache and should drop to seconds
  plus decode
- **File reads are the recurring cost**: every file pi reads is prefill at
  ~50-60 tok/s (a 500-line file ≈ 20-40s). Prefer small files and targeted
  reads in prompts
- **Quality prior**: chess/embers evidence says the model executes
  memorized patterns well but has weak state tracking. Expect decent
  boilerplate and small edits; expect it to fumble multi-file invariants.
  Tool-call *format* should be near-perfect (grammar-clean tool_calls
  verified; zero nudges on the new stack)

## Risks and mitigations

- **No sandbox**: pi's bash/write/edit tools run directly on the host.
  Mitigate: scratch repo only, committed tree, review `pi config` for
  approval settings before rung 3, consider `--exclude-tools bash` for
  early rungs
- **GPU contention**: one model instance at a time (chat.sh guard exists;
  nothing guards a second server) — don't run embers/chess/chat.sh during
  pi sessions
- **Grief spirals**: if a pi turn hangs for minutes, it's the think-spiral
  failure mode from the chess/embers sessions — keep server-side thinking
  OFF (current default) unless the probe in step 3.3 shows pi manages
  effort cleanly
- **Context creep**: long pi sessions + preserved file contents can grow
  large; 262144 gives headroom but prefill cost grows with it — prefer
  fresh sessions per task rung

## Open questions (answer during steps 3-4)

1. ~~Does pi's `--thinking` flag translate to `reasoning_effort`?~~
   **ANSWERED 2026-08-15 (corrected): YES in interactive sessions, NO in
   `-p` print mode.** Interactive sessions transmit the session thinking
   level (default medium) and it overrides the server's `--reasoning off` —
   measured: R6.9k reasoning tokens vs 561 visible in the first brossa
   session (pi's status ribbon shows ↑sent ↓received R=reasoning CH=cache%).
   Control: `pi --thinking off` at launch or switch level in the TUI.
   `-p` mode sends nothing (probe showed identical 4-token replies)
2. Does pi send sampling params, or inherit server defaults? (still open;
   low stakes with thinking off)
3. ~~What approval/permission model does pi apply to bash/write?~~
   **ANSWERED 2026-08-15: none, by design (full YOLO)** — no prompts, no
   sandbox; controls are upfront allow/deny (`--tools read,grep,find,ls`,
   `--exclude-tools bash,write,edit`) or ecosystem extensions
   (pi-permission-system, pi-sandbox). Regime: read-only allowlist in real
   repos, YOLO only in scratch dirs
4. Does pi handle `reasoning_content` in responses (display thinking), or
   should the model entry set `"reasoning": false` to avoid confusion?
5. Session token accounting: does pi show per-turn token counts we can
   cross-check against server `timings` for cache-hit verification?

## Probe results (2026-08-15)

- Smoke 1 connectivity: PASS ("ready", zero flags after settings.json defaults)
- Smoke 2 tool round-trip: PASS — pi read `shell.nix` and answered with its
  exact contents; server log shows a 4-request agent loop for the one answer
- Smoke 3 thinking probe: see answered question 1 above
- Also: pi auto-loads AGENTS.md AND CLAUDE.md (global `~/.pi/agent/AGENTS.md`,
  parent dirs, cwd, concatenated; `AGENTS.override.md` replaces per-dir;
  `SYSTEM.md` replaces the system prompt)

## Done criteria

The experiment is a success if rung 3 (failing-test fix) completes without
manual code edits, in wall-clock that feels usable (~≤5 min), with zero
malformed tool calls. Then it's worth wiring a `pi-local` convenience
(shell alias or wrapper script) and trying a real task on a worktree.
