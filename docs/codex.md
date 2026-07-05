# Codex Reference Installation

**Updated**: 2026-04-13

This documents the Codex variant of `ai_local`.

Codex in this setup **uses both MemPalace and CodeGraph** through MCP. They are not optional
background references in the design; they are core parts of the Codex context strategy:

- **MemPalace** for cross-session memory, decisions, and historical context
- **CodeGraph** for structural code understanding, call graphs, and impact analysis

## What Reuses Cleanly

| Area | Reuse level | How |
|------|-------------|-----|
| `CLAUDE.md` rules | High | Translated into `AGENTS.md` |
| Skills | Very high | Reused directly from `ai_local/skills/` by reading `SKILL.md` files |
| MCP servers | High | Reused in `.codex/config.toml` |
| OpenSpec workflow | High | Reused through skills + command playbooks |
| MemPalace | High | Reused through MCP + skill |
| CodeGraph | High | Reused through MCP + skill |
| Commands | Medium-high | Reused as markdown playbooks, not native slash commands |
| Agents | Medium-high | Reused as role prompts, not a native registry |
| Hooks | Medium | Reused as manual checks and policies |
| Claude hook enforcement | Low | No native equivalent in this setup |
| OpenCode plugins | Low | No direct Codex runtime integration here |

## Installed Files

There is no dedicated `codex/` install directory. Codex consumes the **shared** corpus via two
starter templates:

- `templates/AGENTS.md.example` — copy to your project `AGENTS.md` (Codex reads the same
  instructions file as OpenCode).
- `templates/codex.config.toml.example` — a documented starter that wires MemPalace and
  CodeGraph as `[[mcp_servers]]`; copy it to `.codex/config.toml` (project) or
  `~/.codex/config.toml` (global) and adjust the commands/paths for your machine.

`./install.sh --templates` copies both into the current directory for you (`AGENTS.md` and
`.codex/config.toml`). Everything else — skills, agent role prompts, command playbooks, hook
policies — is read in place from the bundle.

Project-level install target:

- `AGENTS.md`
- `.codex/config.toml`

## OpenSpec

OpenSpec should be installed from the canonical package published on the OpenSpec site:

```bash
npm install -g @fission-ai/openspec@latest
```

The OpenSpec homepage also lists **Codex** under native supported tools, so the Codex
reference setup should treat OpenSpec as a first-class workflow rather than a Claude/OpenCode
carry-over.

## Design Choice

The Codex setup does **not** try to recreate Claude hook lifecycle events or OpenCode's
plugin registry. Instead it treats `ai_local` as a shared source library:

- skills stay in `ai_local/skills/`
- commands stay in `ai_local/opencode/commands/`
- role prompts stay in `ai_local/opencode/agents/`
- hooks stay in `ai_local/.claude/hooks/`
- MemPalace and CodeGraph stay configured as MCP servers in `.codex/config.toml`

Codex then loads those assets on demand through `AGENTS.md`.

## Current Gaps

1. Hook logic is not deterministic in Codex the way it is in Claude Code.
2. `/commit`, `/review`, `/opsx:*` are not native Codex slash commands in this setup.
3. `@agent-name` files are not a native Codex registry here; they are reusable role specs.
4. Skill auto-activation from `.claude/skill-rules.json` is advisory rather than automatic.

## Why This Shape

This preserves one source of truth and avoids maintaining three divergent systems:

- Claude-native
- OpenCode-native
- Codex-native

The only Codex-specific assets are the MCP config and the top-level `AGENTS.md` that tells
Codex how to consume the shared `ai_local` corpus.
