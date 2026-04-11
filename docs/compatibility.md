# Claude Code / OpenCode / Copilot CLI Compatibility Matrix

This document tracks which components work on which tool, where the semantic boundaries are, and where the bundle intentionally ships asymmetric content.

---

## Component matrix

| Component        | Claude Code | OpenCode | Copilot CLI | Source dir               |
|------------------|-------------|----------|-------------|--------------------------|
| System prompt    | `CLAUDE.md` (project) + `~/.claude/CLAUDE.md` | `AGENTS.md` (project) + `~/.config/opencode/AGENTS.md` (also reads `CLAUDE.md` in compat mode) | planned | `templates/` |
| Agents           | `~/.claude/agents/` | `~/.config/opencode/agent/` | planned | `agents/{claude,opencode}/` |
| Commands         | `~/.claude/commands/` | `~/.config/opencode/command/` | planned | `commands/{claude,opencode}/` |
| Skills           | `~/.claude/skills/` (native) | `~/.agents/skills/` (native, 6-path discovery) | planned | `skills/` |
| Hooks (shell)    | `~/.claude/hooks/` | not supported | not supported | `hooks/` |
| Plugins (TS)     | not supported | `~/.config/opencode/plugin/` | not supported | `plugins/` |
| Custom tools (TS)| not supported | `~/.config/opencode/tools/` | not supported | `tools/` |
| Settings         | `~/.claude/settings.json` (merged by user) | `~/.config/opencode/opencode.json` | planned | docs snippets in `installation.md`, starter in `templates/opencode.json.example` |

---

## Install profiles

- **`claude`** — installs `agents/claude/`, `commands/claude/`, `skills/`, `hooks/`. Skips `plugins/`, `tools/`, `agents/opencode/`, `commands/opencode/`. Result: zero TypeScript artefacts on disk.
- **`opencode`** — installs `agents/opencode/`, `commands/opencode/`, `plugins/`, `tools/`, `skills/`. Skips `hooks/`, `agents/claude/`, `commands/claude/`. Result: zero shell-hook artefacts on disk.
- **`both`** (default when both tools are detected) — installs everything applicable to each tool.
- **`auto`** — detect which tools exist and install what fits.
- **`copilot`** — **planned**. See [`copilot.md`](copilot.md) for current status and a manual workaround.

Skills install once at the tool-neutral path `~/.agents/skills/` and are picked up natively by OpenCode (via its 6-path discovery) and via a second symlink at `~/.claude/skills/` for Claude Code. There is no third copy on disk — both tools resolve through symlinks that share a single source of truth in the cloned repo.

---

## Install model: symlinks, not copies

`install.sh` creates **symlinks** from each tool's canonical install location back into the cloned repo. The cloned repo IS the golden copy. A `git pull` in the repo instantly propagates to every installed component, on every tool, without re-running the installer.

Chain for skills (2-hop via the tool-neutral path):

```
<repo>/skills/<name>/                    (real git-tracked files)
    ^
    | symlink
    |
~/.agents/skills/<name>                  (tool-neutral, OpenCode reads natively)
    ^
    | symlink
    |
~/.claude/skills/<name>                  (Claude Code reads here)
```

Agents, commands, hooks, plugins, and tools symlink directly from the tool-specific install path to the corresponding file in the repo — no `~/.agents/` middleman, because those components have no cross-tool neutral convention yet.

Keep the repo at a persistent path. Moving it after install breaks every symlink. Re-running the installer from the new location re-creates the links.

Templates (`CLAUDE.md.example`, `AGENTS.md.example`, `opencode.json.example`) are the one exception — they are copied, not symlinked, because users are expected to edit their project-local copy.

---

## Semantic asymmetries

Even within components that install on both tools, some features have no 1:1 equivalent.

### Skills are native on both tools

Both Claude Code and OpenCode (v1.0.110+) ship a native skill system. The bundle's skills install once and are visible to both. Earlier versions of this document described "OpenCode has no skill system" as a workaround target — that is no longer true. OpenCode added native skill support, the bundle uses it, and the only remaining OpenCode-specific gap is progressive disclosure of `refs/`/`scripts/`/`templates/` subdirectories. That gap is bridged by the bundle's two custom tools (`skill_ref`, `skill_list_refs`). See [`skills.md`](skills.md) and [`tools.md`](tools.md).

### Hooks (shell) vs plugins (TypeScript) vs custom tools

Three distinct mechanisms, no 1:1 mapping:

- **Hooks** (Claude Code) — one shell script per event, invoked once per tool call. See [`hooks.md`](hooks.md).
- **Plugins** (OpenCode) — one long-lived TypeScript module per concern, with per-event lifecycle callbacks. See [`plugins.md`](plugins.md).
- **Custom tools** (OpenCode) — LLM-callable TypeScript functions that the agent invokes as first-class tools. See [`tools.md`](tools.md).

Plugins and hooks serve the same role (run something around tool calls); they are not the same mechanism and cannot share code. Custom tools are a fourth extension point entirely — they are called *by the LLM*, not *around* the LLM. The bundle ships both sides independently; neither is a wrapper around the other.

### Agent frontmatter

- **Claude Code** agents use a YAML frontmatter with fields like `name`, `description`, `allowed-tools`.
- **OpenCode** agents use a different YAML frontmatter contract (different field names, different defaults). OpenCode agents in this bundle additionally set `tools: { skill: true }` to re-enable the skill tool for subagents — see [`skills.md`](skills.md#the-subagent-caveat).

This is why `agents/claude/` and `agents/opencode/` are separate directories rather than shared files with templated frontmatter. A flat dual-copy is boring and boring is correct for a reference repo.

### Commands

Commands are defined identically on both tools — a markdown file with a top-level `#` heading and a body. The same file theoretically works on both, but the bundle still ships dual copies under `commands/{claude,opencode}/` to keep the layout symmetric and the parity check simple.

### System prompt filename

Claude Code reads `CLAUDE.md`; OpenCode reads `AGENTS.md` but also reads `CLAUDE.md` in its Claude Code compatibility mode. See [`rules.md`](rules.md) for the full discovery order and the env vars that disable compat mode (`OPENCODE_DISABLE_CLAUDE_CODE`, `OPENCODE_DISABLE_CLAUDE_CODE_PROMPT`, `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS`).

---

## One-sided content

Some content is legitimately one-sided and lives only on one tool. This section lists every such case so drift is explained, not accidental.

| File                            | Side     | Reason |
|---------------------------------|----------|--------|
| `agents/opencode/refactor.md`   | OpenCode | Ships as OpenCode-only in the source tree. The Claude Code side does not have a `refactor` agent — use `/refactor` in OpenCode, or `@coder-tdd` plus `/review` in Claude Code. |
| `hooks/**`                      | Claude   | OpenCode does not use shell hooks. |
| `plugins/**`                    | OpenCode | Claude Code does not use TypeScript plugins. |
| `tools/**`                      | OpenCode | Claude Code has no equivalent of OpenCode's in-process custom tool loader. |

Skills are **not** one-sided any more — they install once and both tools pick them up. Earlier versions of this matrix listed `skills/**` as Claude-only; that is no longer correct.

One-sided content is an explicit contributor choice, not drift. If you add a new one-sided file, add a row here so reviewers can tell the difference.

---

## Not shipped: mode guard

The dual-context mode guard (the thing that blocks cross-contamination between employer and personal contexts) is **not** in this bundle. It lives in the sibling repo [`agent-circuit-breaker`](https://github.com/mwigge/agent-circuit-breaker) along with its shared config file and shell helper. If you want it, install that repo separately; the two bundles do not overlap.

The mode guard is excluded deliberately. `install.sh` does not ship `hooks/mode-guard.sh` or `plugins/mode-guard.ts`, does not ship `docs/circuit-breaker.md`, and does not offer an option to install the sibling repo. Users who want both install each separately — which keeps the two release cycles independent.

---

## Editing rules for contributors

- **Bug in an agent's behaviour for *both* tools** → edit `agents/claude/X.md` AND `agents/opencode/X.md`. The parity check in CI flags single-side edits.
- **Bug specific to one tool's runtime** → edit only the affected side. Add a note in this file if the drift is intentional.
- **New agent** → must land in both subdirs in the same PR, OR be tagged one-sided in the table above.
- **New command** → same rule as agents.
- **Hooks ↔ plugins** are **not** required to be paired. They are different mechanisms and may legitimately diverge.
- **Custom tools** (OpenCode-only) have no Claude Code counterpart. Feel free to add more without touching the Claude side.

---

## See also

- [`skills.md`](skills.md) — skill discovery, subagent caveat, frontmatter requirements.
- [`tools.md`](tools.md) — OpenCode custom tools, `skill_ref`, `skill_list_refs`.
- [`plugins.md`](plugins.md) — OpenCode plugin lifecycle vs Claude Code hooks.
- [`rules.md`](rules.md) — `CLAUDE.md` / `AGENTS.md` discovery order.
- [`copilot.md`](copilot.md) — GitHub Copilot CLI status and manual workaround.
- [`ecosystem.md`](ecosystem.md) — companion tools that pair with this bundle.
