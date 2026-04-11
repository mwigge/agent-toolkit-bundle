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
| `0` | Allow / approve — proceed normally |
| `2` | Block / deny — stderr message is fed back to Claude as an error |
| Other | Treated as allow (fail-open) |

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
  1. no-ai-attribution.sh (5s timeout)  -- blocks AI mentions in commits
  2. security-guard.sh   (10s timeout)  -- blocks destructive commands

PreToolUse on all tools:
  4. observe.sh          (async)        -- audit trail, never blocks

PostToolUse on Edit|Write:
  1. format-on-save.sh   (30s timeout)  -- auto-format
  2. inline-quality.sh   (15s timeout)  -- immediate feedback

PostToolUse on all tools:
  3. observe.sh          (async)        -- audit trail
```

---

## Hook Reference

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

**Bash blocks**: `rm -rf /`, `git push --force main`, `DROP TABLE`, `TRUNCATE TABLE`

**File blocks**: Writing to `.env`, `.env.*`, `migrations/*.sql`, `pdm.lock`, `package-lock.json`, `.claude/settings.json`

**Secret detection**: Scans edited files for `api_key=`, `password=`, `token=` with literal values (8+ chars).

**Audit**: Logs every tool call to `.claude/audit.log` regardless of outcome.

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
| **YELLOW** | `pip install`, `git commit`, `docker build`, editing `.py/.ts/.sql` | Auto-approve + audit log |
| **RED** | `rm -rf /`, `git push --force main`, `DROP TABLE`, writing `.env` | Deny with explanation |
| **Unmatched** | SSH to remote, production docker-compose, unknown egress | Escalate to human |

The tier rules are defined inline at the top of the script — edit them there to adjust policy. There is no external policy file.

---

### transcript-backup.sh (PreCompact, async)

**Event**: PreCompact
**Timeout**: 10 seconds (async)
**Purpose**: Saves conversation transcript before context compaction.

Writes to `.claude/backups/transcript-<session_id>-<timestamp>.jsonl`. Keeps only the 10 most recent backups.

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
            "command": "bash ~/.claude/hooks/security-guard.sh",
            "timeout": 10
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

1. Create the script in `agent-toolkit-bundle/.claude/hooks/my-hook.sh`
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
Plugins live in `plugins/*.ts` in this bundle and install to `~/.config/opencode/plugin/`.
See [plugins.md](plugins.md) for the OpenCode-specific plugin authoring guide.

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
  1. session-init.ts        once per process — dirs, audit.log
  2. no-ai-attribution.ts   blocks AI attribution in commits/PRs
  3. security-guard.ts      destructive commands, protected files, secret detection
  4. observe.ts             NDJSON audit event (risk 0-3)

tool.execute.after:
  1. format-on-save.ts      ruff/black/prettier/sqlfluff
  2. inline-quality.ts      advisory quality hints (console.warn to model)
  3. quality-gate.ts        blocking checks: print(), bare except, tsc, ESLint
  4. observe.ts             NDJSON audit event
```

### opencode.json plugin registration

OpenCode auto-loads any `.ts` file in `~/.config/opencode/plugin/` on startup. There is no manual registration required — placing a plugin file in that directory is enough. Restart OpenCode after installing a new plugin so the runtime picks it up.

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

1. Create a new `.ts` file under `plugins/` in this bundle.
2. Export a `Plugin` (default or named export).
3. Install: copy to `~/.config/opencode/plugin/` (or re-run `install.sh --profile opencode`).
4. Restart OpenCode.

The plugin SDK is in `@opencode-ai/plugin`. Import with:

```typescript
import type { Plugin } from "@opencode-ai/plugin";
```

### Key behavioural differences from Claude Code hooks

- **Blocking**: throw an `Error` instead of `exit 2`. The error message is fed back to the model.
- **Advisory feedback**: `console.warn(msg)` — OpenCode captures stderr/stdout from plugins and shows it in the model's context. There is no `additionalContext` JSON envelope.
- **No exit codes**: return `undefined` to allow, throw to block.
- **No `$CLAUDE_PROJECT_DIR`**: use `process.cwd()` for the project root.
- **No `$CLAUDE_SESSION_ID`**: generate your own session token if needed (`crypto.randomUUID()`).
- **Async**: plugins are async functions. `await` is safe. Keep blocking plugins fast (< 5s).
- **Order**: plugins fire in the order listed in `opencode.json`. First throw wins.
