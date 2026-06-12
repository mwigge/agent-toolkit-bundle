# Hook System

**Purpose**: Deterministic enforcement of development rules. CLAUDE.md gives advice; hooks enforce rules.

```
CLAUDE.md    -->  advisory  (Claude may or may not follow)
hooks/*.sh   -->  enforcement  (always runs, can block Claude)
```

Hooks are shell scripts that run at specific lifecycle events in Claude Code. They receive JSON input via stdin and control behaviour via exit codes.

---

## Hook Lifecycle Events

| Event | When it fires | Can block? | Input |
|-------|--------------|------------|-------|
| `SessionStart` | Claude Code starts or resumes after compaction | Yes | `{}` or `{"compact": true}` |
| `UserPromptSubmit` | User submits a prompt, before Claude processes it | Yes | `{"prompt": "..."}` |
| `PreToolUse` | Before Claude executes any tool (Bash, Edit, Write, Read, etc.) | Yes | `{"tool_name": "...", "tool_input": {...}}` |
| `PostToolUse` | After a tool call completes | Yes (via additionalContext) | `{"tool_name": "...", "tool_input": {...}, "tool_output": {...}}` |
| `Stop` | Claude declares it is finished | Yes (can force continuation) | `{"stop_hook_active": bool}` |
| `PreCompact` | Before context compaction | No (async) | Conversation context payload |
| `PermissionRequest` | Claude requests permission for a tool call | Yes | `{"tool_name": "...", "tool_input": {...}}` |
| `Notification` | Claude emits a notification | No (async) | `{"message": "..."}` |

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0`, no stdout | No opinion — falls through to the normal permission flow (may still prompt the human) |
| `0` + `hookSpecificOutput` JSON | Explicit decision — see below |
| `2` | Block / deny — stderr message is fed back to Claude as an error, any stdout is ignored |
| Other | Treated as allow (fail-open) |

### Signaling an explicit allow/deny decision

A hook can signal "allow" (or "deny"/"ask") on exit 0 by printing JSON to stdout. The
`hookEventName` should echo the `hook_event_name` field from the hook's own input so the
decision always matches the event the hook is registered under:

```bash
printf '{"hookSpecificOutput":{"hookEventName":"%s","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' \
  "$HOOK_EVENT" "why this is safe"
```

`permission-autoapprove.sh` uses this to distinguish its GREEN/YELLOW "auto-approve" tiers
(emit the JSON above) from its UNMATCHED tier (bare `exit 0`, no stdout — escalate to a human).
A bare `exit 0` with no stdout is *not* the same as an allow decision.

### additionalContext

PostToolUse hooks can emit JSON to stdout to inject feedback into Claude's context:

```json
{"additionalContext": "INLINE QUALITY FEEDBACK:\n  Line 24: print() in library code"}
```

Claude sees this before writing the next file and can self-correct.

---

## Execution Order

Hooks within the same event fire **in order** (array order in `settings.json`). The chain stops at the first blocking failure (exit 2).

```
PreToolUse on Bash|Edit|Write:
  1. mode-guard.sh      (5s timeout)    -- company/private path guard
  2. no-ai-attribution.sh (5s timeout)  -- blocks AI mentions in commits
  3. security-guard.sh   (10s timeout)  -- blocks destructive commands

PreToolUse on all tools:
  4. observe.sh          (async)        -- audit trail, never blocks

PostToolUse on Edit|Write:
  1. format-on-save.sh   (30s timeout)  -- auto-format
  2. inline-quality.sh   (15s timeout)  -- immediate feedback

PostToolUse on Bash:
  3. codegraph-sync.sh   (15s, async)   -- sync code knowledge graph on git add

PostToolUse on all tools:
  4. observe.sh          (async)        -- audit trail

Stop:
  1. quality-gate.sh     (120s timeout) -- blocking quality sweep
  2. model-usage-summary.sh (10s)       -- advisory: prints tier table to stderr
  3. observe.sh          (async)        -- audit trail
```

---

## Hook Reference

### mode-guard.sh (PreToolUse, blocking)

**Event**: PreToolUse on Bash, Edit, Write
**Timeout**: 5 seconds
**Purpose**: Company/private path separation circuit breaker.

Reads `~/.claude/mode`, checks the target path against company and private regex patterns. Blocks with exit 2 if the path belongs to the wrong mode.

See [circuit-breaker.md](circuit-breaker.md) for full details.

---

### no-ai-attribution.sh (PreToolUse, blocking)

**Event**: PreToolUse on Bash
**Timeout**: 5 seconds
**Purpose**: Blocks git commits and PRs containing AI attribution.

Only checks `git commit` and `gh pr create` commands. Scans for patterns like `Co-Authored-By: Claude`, `Generated with AI`, etc. Does NOT block file edits (documentation may mention these patterns as examples).

---

### security-guard.sh (PreToolUse, blocking)

**Event**: PreToolUse on Bash, Edit, Write
**Timeout**: 10 seconds
**Purpose**: Blocks destructive commands and protects sensitive files.

**Bash blocks**: `rm -rf /`, force-pushes to `main`/`master`, `drop table`, `truncate table`, `format c:|d:` — see `policy/guard-patterns.json`'s `destructive_commands`.

**File blocks**: `.env`, `.env.*`, `migrations/*.sql|py`, `pdm.lock`, `package-lock.json`, `pnpm-lock.yaml`, `.claude/settings*.json` — see `policy/guard-patterns.json`'s `protected_files`.

**Secret detection**: Scans the *pending* content of an Edit/Write (not the file on disk) for `api_key=`, `secret_key=`, `password=`, `token=` with literal values (8+ chars) — see `policy/guard-patterns.json`'s `secret_pattern`.

**Audit**: Logs every tool call to `.claude/audit.log` regardless of outcome.

**Best-effort tripwires**: the regexes above catch common cases (`rm -rf /`, `git push --force ... main`) but are not exhaustive — variants like `rm -fr /`, `sudo rm -rf /`, or `find / -delete` can slip through. The permission system (`permission-autoapprove.sh` + human review on UNMATCHED) is the actual security boundary; treat these patterns as a cheap first filter, not a guarantee.

---

### Shared policy data: policy/guard-patterns.json

`policy/guard-patterns.json` is the single source of truth for the regexes and
data shared between the bash hooks and their OpenCode TS plugin twins:

- `secret_pattern` — used by `security-guard.sh` and `security-guard.ts`
- `destructive_commands` — used by `security-guard.sh`
- `protected_files` / `self_protect_files` — used by `security-guard.sh`,
  `permission-autoapprove.sh`, and `security-guard.ts`
- `model_tier_map` — used by `model-usage.ts`, `model-usage-summary.sh`
  (embedded Python), and documented for `model-report.py`

Every `*_pattern` / `*_patterns` / `*_commands` / `*_files` entry is written
in **ERE-compatible syntax** — the same string is valid for `grep -E` and as
the source of a JS `RegExp`. Arrays are joined with `|` to form a single
alternation. For `model_tier_map`, keys are prefix-matched against the model
ID; **more specific prefixes must be listed before the general ones they
would otherwise be swallowed by** (e.g. `claude-opus-4-8` before
`claude-opus-4`).

Each consumer resolves the file's path relative to its own (symlink-resolved)
location — `<repo>/hooks/../policy/guard-patterns.json` or
`<repo>/plugins/../policy/guard-patterns.json` — so it works whether run from
the repo checkout or via the `install.sh` symlink tree. If the file is
missing or unreadable, every consumer falls back to its previous hardcoded
values rather than failing.

Run `scripts/test-guard-patterns.sh` to check that all consumers still
reference this file (drift check) and to run a fixture-based allow/deny suite
against the bash hooks.

---

### skill-activation.sh (UserPromptSubmit, blocking)

**Event**: UserPromptSubmit
**Timeout**: 5 seconds
**Purpose**: Scans prompt for domain keywords and injects skill activation hints.

Reads `.claude/skill-rules.json` (regex pattern -> skill name mapping). If the prompt matches any pattern, emits additionalContext telling Claude to load the matching skill(s).

Example: User types "add a postgres probe" -> detects "postgres" -> activates `/postgres-patterns` and `/sre`.

---

### format-on-save.sh (PostToolUse, blocking)

**Event**: PostToolUse on Edit, Write
**Timeout**: 30 seconds
**Purpose**: Auto-format files after every write.

| Extension | Formatter |
|-----------|-----------|
| `.py` | `ruff check --fix` + `ruff format` + `black` |
| `.ts`, `.tsx`, `.js`, `.jsx` | `prettier` |
| `.json`, `.yaml`, `.yml` | `prettier` |
| `.sql` | `sqlfluff fix --dialect postgres` |

Degrades gracefully — if a formatter is not installed, it skips silently. Never blocks (always exit 0).

---

### inline-quality.sh (PostToolUse, advisory)

**Event**: PostToolUse on Edit, Write
**Timeout**: 15 seconds
**Purpose**: Immediate inline feedback so Claude self-corrects before the next file.

Emits additionalContext (not a block) for:

**Python**: `print()` in library code, bare `except:`, deprecated `typing.Dict/List/Optional`, hardcoded secrets, non-parameterised SQL.

**TypeScript**: `console.log` in src/, untyped `any` without justification comment.

---

### codegraph-sync.sh (PostToolUse, async)

**Event**: PostToolUse on Bash
**Timeout**: 15 seconds (async, non-blocking)
**Purpose**: Keep the CodeGraph knowledge graph in sync with staged changes.

Detects `git add` commands in Bash tool calls. When found, runs `codegraph sync` to incrementally update the code index (only changed files, typically under 2 seconds). Requires `codegraph` to be installed and the repo to be initialized (`codegraph init`).

Fails silently — sync is never a blocker. Skips if `codegraph` is not on PATH or if the repo has no `.codegraph/` directory.

---

### quality-gate.sh (Stop, blocking)

**Event**: Stop (when Claude declares done)
**Timeout**: 120 seconds
**Purpose**: Final quality sweep. If any check fails, Claude is forced to continue and fix.

Detects changed files via `git diff --name-only HEAD`, then runs language-specific checks:

**Python**: `print()` in library code, bare `except:`, deprecated typing, hardcoded secrets.

**TypeScript**: `console.log` in src/, `tsc --noEmit` errors.

**ESLint**: If `eslint.config.*` exists and changed files have errors.

Has an infinite-loop guard: checks `stop_hook_active` flag to prevent the Stop hook from triggering another Stop event.

---

### model-usage-summary.sh (Stop, advisory)

**Event**: Stop (after Claude finishes a response block)
**Timeout**: 10 seconds
**Purpose**: Prints a compact tiered model usage table to stderr after every Stop event.

Reads `.claude/logs/model-usage.ndjson` (written by the `model-usage.ts` OpenCode plugin),
runs `model-report.py`, and prints a tier breakdown (utility / primary / sign-off) with
token counts, cost in USD, and a routing health signal.

Also emits an `additionalContext` one-liner to stdout so the model is aware of its current
token and cost profile for the session.

Has an infinite-loop guard: skips silently if `stop_hook_active` is `true`.
Skips silently if the log file does not exist yet (first response block) or if Python/the
report script is unavailable.

**Depends on**:
- `~/.config/opencode/scripts/model-report.py` (aggregation script)
- `.claude/logs/model-usage.ndjson` (written by `model-usage.ts` plugin in OpenCode)

See [model-tier.md](model-tier.md) for full routing and instrumentation details.


---

### observe.sh (Pre/PostToolUse, async)

**Event**: PreToolUse (all), PostToolUse (all), Stop, Notification
**Timeout**: 5 seconds (async, non-blocking)
**Purpose**: Universal audit trail.

Writes one NDJSON line to `.claude/logs/events.ndjson` per event:

```json
{"ts": "2026-04-09T14:32:11Z", "session_id": "abc123", "event": "PreToolUse",
 "tool": "Bash", "input_summary": "ruff check --fix src/", "outcome": "ok", "risk": 1}
```

**Risk scores**: 0=info, 1=low, 2=medium, 3=high. Risk-3 events are also written to `.claude/audit.log`.

---

### setup-init.sh (SessionStart, blocking)

**Event**: SessionStart
**Timeout**: 30 seconds
**Purpose**: Per-session initialisation.

- Creates `.claude/logs/`, `.claude/backups/`, `.claude/cache/` directories
- Ensures `.claude/audit.log` exists
- Makes all hooks executable (`chmod +x`)
- Logs session start to events.ndjson
- Emits additionalContext reminder to read CLAUDE.md and memory.md

---

### permission-autoapprove.sh (PermissionRequest, blocking)

**Event**: PermissionRequest
**Timeout**: 30 seconds
**Purpose**: Three-tier rule-based auto-approval.

| Tier | Examples | Action |
|------|----------|--------|
| **GREEN** | Read, Glob, Grep, `git status/log/diff`, `pytest`, `ruff`, `tsc` | Auto-approve silently |
| **YELLOW** | `pip install`/`npm install` (dependency changes, audited — see below), `git commit`, `docker build`, editing `.py/.ts/.sql` inside the project tree | Auto-approve + audit log |
| **RED** | `rm -rf /`, `git push -f`/`--force`/`--force-with-lease` to `main`/`master`, `DROP TABLE`, writing `.env` or lock files | Deny with explanation |
| **Self-protection** | Edit/Write to `.claude/`, `.github/workflows/`, `hooks/*.sh`, `plugins/*.ts`, `settings*.json` | Escalate to human (no decision) — an agent must not silently widen its own permissions |
| **Unmatched** | SSH to remote, production docker-compose, unknown egress, edits outside the project tree | Escalate to human |

**Dependency installs (`pip install`, `npm install`, etc.)** are a deliberate YELLOW: they're
auto-approved (agents frequently need to add packages) but every invocation is written to
`.claude/audit.log` so supply-chain changes are reviewable after the fact. If your threat model
requires a human in the loop for every dependency change, move these patterns to the
self-protection/escalation tier instead.

See [permission-policy.md](../permission-policy.md) for the full policy definition.

---

### transcript-backup.sh (PreCompact, async)

**Event**: PreCompact
**Timeout**: 10 seconds (async)
**Purpose**: Saves conversation transcript before context compaction.

Writes to `.claude/backups/transcript-<session_id>-<timestamp>.jsonl`. Keeps only the 10 most recent backups.

---

### mempalace-wake-up.sh (SessionStart, blocking)

**Event**: SessionStart
**Timeout**: 10 seconds
**Purpose**: Injects MemPalace L0+L1 context at session start.

Detects active OpenSpec changes from memory.md and recently modified directories, maps change names to domain wings using keyword matching, then calls `mempalace wake-up --wing <primary_wing>` to load top-scored drawers.

---

### mempalace-ingest.sh (PreCompact, async)

**Event**: PreCompact
**Timeout**: 30 seconds (async)
**Purpose**: Mines recently modified OpenSpec artifacts into MemPalace before context compaction.

Scans `openspec/changes/` for directories modified in the last 7 days, mines `proposal.md`, `design.md`, `delivery.md`, and `tasks.md` (if under 150 lines). Also mines `memory.md`.

---

### notify.sh (Notification, async)

**Event**: Notification
**Timeout**: 5 seconds (async)
**Purpose**: Desktop notification on macOS (osascript) or Linux (notify-send).

---

## Configuration (settings.json)

Hooks are wired in `.claude/settings.json` under the `hooks` key. Each event maps to an array of hook groups:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/mode-guard.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

**Key fields**:
- `matcher`: Regex filter for tool names (optional — omit to match all tools)
- `type`: Always `"command"` for shell hooks
- `command`: Path to the shell script. `$CLAUDE_PROJECT_DIR` resolves to the project root.
- `timeout`: Seconds before the hook is killed
- `async`: Set to `true` for fire-and-forget hooks (observe, notify, transcript-backup)

---

## Adding a New Hook

1. Create the script in `ai_local/.claude/hooks/my-hook.sh`
2. Make it executable: `chmod +x .claude/hooks/my-hook.sh`
3. Add the wiring to `settings.json` under the appropriate event
4. Test: `echo '{"tool_name":"Bash","tool_input":{"command":"echo test"}}' | .claude/hooks/my-hook.sh`

**Template**:

```bash
#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Your logic here

exit 0  # allow
# exit 2  # block (stderr fed back to Claude)
```

---

## OpenCode Plugin System

OpenCode replaces the shell hook system with a TypeScript plugin API.
Plugins live in `ai_local/opencode/plugins/` — symlinked to `~/.config/opencode/plugins/`.
Edit files in `ai_local/opencode/plugins/`; the change is live immediately via symlink.

### Plugin events vs Claude Code hooks

| Claude Code hook event | OpenCode plugin event | Notes |
|---|---|---|
| `PreToolUse` | `tool.execute.before` | Throw to block |
| `PostToolUse` | `tool.execute.after` | Throw to force re-do |
| `PreCompact` | `experimental.session.compacting` | Async, non-blocking |
| `SessionStart` | _(none)_ | Simulate with module-level flag on first `tool.execute.before` |
| `UserPromptSubmit` | _(none)_ | Replaced by keyword table in `AGENTS.md` |
| `Stop` | _(none)_ | Run equivalent checks in `tool.execute.after` per-write |
| `PermissionRequest` | _(none)_ | Not needed — OpenCode uses `AGENTS.md` permissions |
| `Notification` | _(none)_ | Not available |

### Registered plugins (execution order)

```
tool.execute.before:
  1. session-init.ts     once per process — dirs, audit.log, wake-up hint
  2. mode-guard.ts       company/private path guard
  3. no-ai-attribution.ts  blocks AI attribution in commits/PRs
  4. security-guard.ts   destructive commands, protected files, secret detection
  5. observe.ts          NDJSON audit event (risk 0-3)

tool.execute.after:
  1. format-on-save.ts   ruff/black/prettier/sqlfluff
  2. inline-quality.ts   advisory quality hints (console.warn to model)
  3. codegraph-sync.ts   codegraph sync on git add (non-blocking)
  4. quality-gate.ts     blocking checks: print(), bare except, tsc, ESLint
  5. observe.ts          NDJSON audit event

event (model-usage.ts):
  1. model-usage.ts      record per-message tier/token/cost; flush session summary

experimental.session.compacting:
  1. mempalace-ingest.ts  mine OpenSpec artifacts into MemPalace
  2. observe.ts           backup transcript payload to .claude/backups/
```

### opencode.json plugin registration

```json
{
  "plugin": [
    "~/.config/opencode/plugins/session-init.ts",
    "~/.config/opencode/plugins/mode-guard.ts",
    "~/.config/opencode/plugins/no-ai-attribution.ts",
    "~/.config/opencode/plugins/security-guard.ts",
    "~/.config/opencode/plugins/format-on-save.ts",
    "~/.config/opencode/plugins/inline-quality.ts",
    "~/.config/opencode/plugins/codegraph-sync.ts",
    "~/.config/opencode/plugins/quality-gate.ts",
    "~/.config/opencode/plugins/observe.ts",
    "~/.config/opencode/plugins/mempalace-ingest.ts",
    "~/.config/opencode/plugins/model-usage.ts"
  ]
}
```

### Plugin template (TypeScript)

```typescript
import type { Plugin } from "@opencode-ai/plugin"

export const MyPlugin: Plugin = async () => {
  return {
    "tool.execute.before": async (input, output) => {
      const tool = input.tool                            // "bash" | "edit" | "write" | ...
      const args = output.args as Record<string, string> // tool arguments

      // Block: throw an Error
      if (/* condition */) {
        throw new Error("BLOCKED: reason")
      }
      // Allow: return undefined (implicit)
    },

    "tool.execute.after": async (input, output) => {
      // Runs after the tool completes. Throw to force the model to retry/fix.
    },

    "experimental.session.compacting": async (input, _output) => {
      // Fires before context compaction. Use for persistence tasks.
    },
  }
}
```

### How to add a new plugin

1. Create `ai_local/opencode/plugins/my-plugin.ts` (canonical location — symlinked to `~/.config/opencode/plugins/`)
2. Export a `Plugin` (named export, any name)
3. Register the path in `ai_local/opencode/opencode.json` under `"plugin"`
4. Restart OpenCode

The plugin SDK is in `~/.config/opencode/node_modules/@opencode-ai/plugin`.
Type: `import type { Plugin } from "@opencode-ai/plugin"`

### Key behavioural differences from Claude Code hooks

- **Blocking**: throw an `Error` instead of `exit 2`. The error message is fed back to the model.
- **Advisory feedback**: `console.warn(msg)` — OpenCode captures stderr/stdout from plugins and shows it in the model's context. There is no `additionalContext` JSON envelope.
- **No exit codes**: return `undefined` to allow, throw to block.
- **No `$CLAUDE_PROJECT_DIR`**: use `process.cwd()` for the project root.
- **No `$CLAUDE_SESSION_ID`**: generate your own session token if needed (`crypto.randomUUID()`).
- **Async**: plugins are async functions. `await` is safe. Keep blocking plugins fast (< 5s).
- **Order**: plugins fire in the order listed in `opencode.json`. First throw wins.
