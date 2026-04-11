# Claude Code / OpenCode Compatibility Matrix

This document tracks which components work on which tool, where the semantic boundaries are, and where the bundle intentionally ships asymmetric content.

---

## Component matrix

| Component        | Claude Code | OpenCode | Source dir               |
|------------------|-------------|----------|--------------------------|
| System prompt    | `~/CLAUDE.md` (project) | `~/AGENTS.md` (project) | `templates/` |
| Agents           | `~/.claude/agents/` | `~/.config/opencode/agent/` | `agents/{claude,opencode}/` |
| Commands         | `~/.claude/commands/` | `~/.config/opencode/command/` | `commands/{claude,opencode}/` |
| Skills           | `~/.claude/skills/` | not supported | `skills/` |
| Hooks (shell)    | `~/.claude/hooks/` | not supported | `hooks/` |
| Plugins (TS)     | not supported | `~/.config/opencode/plugin/` | `plugins/` |
| Settings         | `~/.claude/settings.json` (merged by user) | `~/.config/opencode/opencode.json` | docs snippets in `installation.md` |

---

## Install profiles

- **`claude`** — installs `agents/claude/`, `commands/claude/`, `skills/`, `hooks/`. Skips `plugins/`, `agents/opencode/`, `commands/opencode/`. Result: zero TypeScript artefacts on disk.
- **`opencode`** — installs `agents/opencode/`, `commands/opencode/`, `plugins/`. Skips `skills/`, `hooks/`, `agents/claude/`, `commands/claude/`. Result: zero shell-hook artefacts on disk.
- **`both`** (default when both tools are detected) — installs everything.
- **`auto`** — detect which tools exist and install what fits.

---

## Semantic asymmetries

Even within components that install on both tools, some features have no 1:1 equivalent.

### Skills are a Claude Code concept

Claude Code supports a skill library at `~/.claude/skills/` — each skill is a directory containing `SKILL.md` with activation metadata. The runtime routes keyword-matched skill hits into the agent context.

OpenCode does not have a skill system. Skill content can still be useful as inline guidance, but it does not auto-activate. Several agents in this bundle reference skills by name (e.g. "use the `python` skill"); on Claude Code those references resolve through the skill loader, on OpenCode they become plain prose that the model reads alongside the rest of the agent body.

### Hooks (shell) vs plugins (TypeScript)

Claude Code ships an event-driven shell-hook system: one shell script per event, invoked per tool call. OpenCode ships an event-driven TypeScript plugin system: one long-lived module per concern, with per-event callbacks.

They are **not** 1:1. Some patterns translate cleanly (format-on-save, security-guard, no-AI-attribution). Others don't (skill activation on Claude Code has no OpenCode analogue). The bundle ships both sides independently — neither is a wrapper around the other.

### Agent frontmatter

- **Claude Code** agents use a YAML frontmatter with fields like `name`, `description`, `allowed-tools`.
- **OpenCode** agents use a different YAML frontmatter contract (different field names, different defaults).

This is why `agents/claude/` and `agents/opencode/` are separate directories rather than shared files with templated frontmatter. A flat dual-copy is boring and boring is correct for a reference repo.

### Commands

Commands are defined identically on both tools — a markdown file with a top-level `#` heading and a body. The same file theoretically works on both, but the bundle still ships dual copies under `commands/{claude,opencode}/` to keep the layout symmetric and the parity check simple.

---

## One-sided content

Some content is legitimately one-sided and lives only on one tool. This section lists every such case so drift is explained, not accidental.

| File                            | Side     | Reason |
|---------------------------------|----------|--------|
| `agents/opencode/refactor.md`   | OpenCode | Ships as OpenCode-only in the source tree. The Claude Code side does not have a `refactor` agent — use `/refactor` in OpenCode, or `@coder-tdd` plus `/review` in Claude Code. |
| `skills/**`                     | Claude   | OpenCode does not ship a skill system. The skills directory is never installed on the OpenCode side. |
| `hooks/**`                      | Claude   | OpenCode does not use shell hooks. |
| `plugins/**`                    | OpenCode | Claude Code does not use TypeScript plugins. |

One-sided content is an explicit contributor choice, not drift. If you add a new one-sided file, add a row here so reviewers can tell the difference.

---

## Not shipped: mode guard

The dual-context mode guard (the thing that blocks cross-contamination between employer and personal contexts) is **not** in this bundle. It lives in the sibling repo [`agent-circuit-breaker`](https://github.com/mwigge/agent-circuit-breaker) along with its shared config file and shell helper. If you want it, install that repo separately; the two bundles do not overlap.

---

## Editing rules for contributors

- **Bug in an agent's behaviour for *both* tools** → edit `agents/claude/X.md` AND `agents/opencode/X.md`. The parity check in CI flags single-side edits.
- **Bug specific to one tool's runtime** → edit only the affected side. Add a note in this file if the drift is intentional.
- **New agent** → must land in both subdirs in the same PR, OR be tagged one-sided in the table above.
- **New command** → same rule as agents.
- **Hooks ↔ plugins** are **not** required to be paired. They are different mechanisms and may legitimately diverge.
