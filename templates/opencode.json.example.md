# `opencode.json` — recommended starter

This directory ships [`opencode.json.example`](opencode.json.example), a minimal but sane OpenCode configuration that pairs with `agent-toolkit-bundle`. Copy it to either `~/.config/opencode/opencode.json` (user-level) or `./opencode.json` (project-local), then edit to taste.

JSON does not support comments, so the annotations are here rather than inside the file itself.

## The file

```json
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["AGENTS.md", "CLAUDE.md"],
  "permission": {
    "skill": {
      "*": "allow"
    },
    "bash": "ask",
    "edit": "allow",
    "write": "allow"
  }
}
```

## Section-by-section

### `"$schema"`

Points at OpenCode's published JSON schema. Your editor's JSON language server uses this for autocompletion and in-place validation. Keep it as the first field so tooling picks it up even when the rest of the file is invalid.

### `"instructions"`

The list of markdown files OpenCode concatenates into the system prompt at session start. `AGENTS.md` is OpenCode's native filename; `CLAUDE.md` is the Claude Code compatibility filename. Listing both means a project that already has `CLAUDE.md` from prior Claude Code work still picks up its rules under OpenCode without duplication — and if you have OpenCode-specific rules that should not apply to Claude Code, put them in `AGENTS.md`.

OpenCode reads the files in order. Earlier entries override later entries when two files set the same rule. The order above (`AGENTS.md` first, `CLAUDE.md` second) makes the OpenCode-native file authoritative. See [`docs/rules.md`](../docs/rules.md) for the full discovery order and how to disable the Claude Code compatibility layer.

### `"permission"`

Controls what the agent is allowed to do without user confirmation. Each subsection maps a tool name to an enforcement mode: `"allow"` (no prompt), `"ask"` (prompt before each call), or `"deny"` (reject outright).

- `"skill": { "*": "allow" }` — allow all skill invocations without prompting. Wildcards are supported; if you want to require approval for specific skills, replace `"*"` with per-skill keys like `"python": "allow"`, `"rust": "ask"`, `"secrets-review": "deny"`. Note: this permission key exists because OpenCode's built-in `skill` tool is disabled for subagents by default, and OpenCode's permission system is how you grant it back.
- `"bash": "ask"` — prompt before every `Bash` tool call. This is the most common friction point; tightening it to `"allow"` makes the agent noticeably faster but removes the human-in-the-loop gate on shell execution. Start with `"ask"`, move to `"allow"` only when you trust the agent's judgement on the specific project.
- `"edit": "allow"` — let the agent modify existing files without prompting. Almost always what you want once you have a feature branch.
- `"write": "allow"` — let the agent create new files without prompting. Same reasoning as `edit`.

Tools not listed here fall back to OpenCode's default (currently `"ask"` for most mutating tools, `"allow"` for read-only ones). You can add more keys as you discover them; `opencode --help` and the schema file linked in `$schema` are the authoritative references.

## What is not in the starter

Things you might expect to see here but will not find:

- **No `"model"` field.** OpenCode defaults to whichever model the user has configured via `opencode auth`. Hard-coding a model in the config is a portability hazard — different users will have different API keys and different preferences. Let OpenCode auto-select.
- **No `"mcpServers"` block.** MCP servers are an orthogonal concern. If you want to wire up MemPalace or another MCP backend, do it in a separate block and read [`docs/install-mempalace.md`](../docs/install-mempalace.md) for the specifics.
- **No `"tools"` or `"plugins"` field.** OpenCode discovers custom tools and plugins from directory conventions (`~/.config/opencode/tools/`, `~/.config/opencode/plugin/`), not from config-file manifests. The bundle's installer symlinks files into those directories — no opencode.json edits required.
- **No secrets.** Never put API keys, tokens, or credentials in this file. OpenCode's credential storage is a separate system (`opencode auth`).

## Multiple projects

If you want different rules per project:

- Keep the shared baseline at `~/.config/opencode/opencode.json`.
- Override per-project at `./opencode.json` (next to the project's `AGENTS.md` / `CLAUDE.md`).
- OpenCode merges the two, with the project layer winning on conflict.

A typical per-project override is to tighten `"bash"` to `"deny"` for high-risk repos (production infrastructure, secrets management) and loosen it to `"allow"` for scratchpads.

## See also

- [`templates/AGENTS.md.example`](AGENTS.md.example) — the system-prompt starter that pairs with this config.
- [`templates/CLAUDE.md.example`](CLAUDE.md.example) — the Claude Code equivalent.
- [`docs/rules.md`](../docs/rules.md) — how `AGENTS.md` and `CLAUDE.md` get discovered.
- [`docs/tools.md`](../docs/tools.md) — how OpenCode discovers custom tools.
- [`docs/plugins.md`](../docs/plugins.md) — how OpenCode discovers plugins.
- OpenCode config schema: <https://opencode.ai/config.json>
