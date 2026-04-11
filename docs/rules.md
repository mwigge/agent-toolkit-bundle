# Global Rules (`AGENTS.md` / `CLAUDE.md`)

**Purpose**: These two files are the always-loaded system prompt for each tool. Every agent, every skill, every command inherits them. They are where project-wide discipline (TDD, conventional commits, no AI attribution, no secrets) lives.

The bundle ships example starters — [`templates/CLAUDE.md.example`](../templates/CLAUDE.md.example) and [`templates/AGENTS.md.example`](../templates/AGENTS.md.example) — containing the non-negotiable rules from this repo's own style guide, minus anything project-specific. Copy one or both into your project root, then edit to taste.

The installer does **not** copy these files by default. They are user-owned. Pass `--templates` to drop them into the current directory:

```bash
cd ~/my-project && /path/to/agent-toolkit-bundle/install.sh --templates
```

---

## Which tool reads which file

- **Claude Code** reads `CLAUDE.md` (project-level) and `~/.claude/CLAUDE.md` (user-level).
- **OpenCode** reads `AGENTS.md` (project-level) and `~/.config/opencode/AGENTS.md` (user-level). OpenCode also supports **Claude Code compatibility mode**, which additionally discovers `CLAUDE.md` and `~/.claude/CLAUDE.md` so that a project already set up for Claude Code works on OpenCode without duplication.

OpenCode's discovery order (earlier entries override later entries for overlapping rules):

1. `./AGENTS.md` — project-local, highest priority
2. `./CLAUDE.md` — project-local, Claude Code compat mode
3. `~/.config/opencode/AGENTS.md` — user-level, OpenCode native
4. `~/.claude/CLAUDE.md` — user-level, Claude Code compat mode

If both a local `AGENTS.md` and a local `CLAUDE.md` exist, OpenCode reads both and concatenates them. That is useful when migrating from Claude Code — you can keep the old file intact and layer OpenCode-specific rules in the new one — and footgun-y when the two files disagree. Pick one as the source of truth.

---

## Why two files at all

The short answer: the two tools disagree on the filename and neither is willing to change. The longer answer is that the filename also implies the audience — `CLAUDE.md` advertises "rules for Claude specifically", `AGENTS.md` advertises "rules for any agent". In practice, 95% of the content is identical. The bundle's two example templates are kept in lock-step, and contributors are expected to edit both when a rule changes.

If you only use one tool, delete the other file. The installer does not care.

---

## Using the bundled templates

The templates are **starters**, not drop-in configs. Each one includes:

- A customisation header block pointing at placeholders to replace.
- Stack defaults (Python, TypeScript, Rust, Node — delete whichever you do not use).
- Non-negotiable rules (no AI attribution, no secrets, no `print()` in library code, no bare `except:`, no `any` without justification).
- Conventional commit format.
- Branch rules (feature branches, no direct pushes to `main`).
- Observability standards (OTel spans, structured logging, no credentials in output).
- A short reference to skills and agents by name.
- A `## Project-Specific Rules` section with a placeholder comment telling you to add your own.

After running `install.sh --templates`, grep for placeholders:

```bash
grep -n '<your-' CLAUDE.md AGENTS.md
```

and substitute your real values. The placeholder table is in the top-level [`README.md`](../README.md#placeholder-table).

---

## Disabling Claude Code compatibility in OpenCode

If you want OpenCode to **ignore** `CLAUDE.md` — for example because you are intentionally running two different rule sets in two different tools — OpenCode exposes environment variables:

| Variable | Effect |
|----------|--------|
| `OPENCODE_DISABLE_CLAUDE_CODE=1` | Disable the entire Claude Code compatibility layer. OpenCode will not read `CLAUDE.md`, will not discover skills from `~/.claude/skills/`, and will not read `~/.claude/CLAUDE.md`. |
| `OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1` | Disable only the prompt-discovery part of the compat layer. `CLAUDE.md` and `~/.claude/CLAUDE.md` are ignored; skills are still discovered from `~/.claude/skills/`. |
| `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` | Disable only the skill-discovery part of the compat layer. Skills from `~/.claude/skills/` are ignored; `CLAUDE.md` is still read. |

Set one in your shell profile:

```bash
export OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1
```

Then restart OpenCode. The default (all three unset) is the most permissive: everything Claude Code-shaped is picked up.

---

## Interaction with the bundle's agents

Every agent in this bundle is written to be **additive** to `CLAUDE.md` / `AGENTS.md`, not a replacement. An agent like `@coder-python` assumes the non-negotiable rules (no `print()` in library code, pytest for tests, mypy strict) are already loaded from the global rules file. The agent body then adds role-specific behaviour (TDD Red phase, parameterised fixtures, hexagonal architecture).

If you delete a non-negotiable rule from `CLAUDE.md`, the agent will not re-establish it from inside its own prompt. The agent trusts the global rules are in place.

For that reason: **do not** delete the "No AI attribution" rule from the templates. The bundle's own `no-ai-attribution.sh` hook (Claude Code) and `no-ai-attribution.ts` plugin (OpenCode) enforce it deterministically, but both gates assume the user has been informed that the rule exists. Deleting the textual rule and then being surprised by a pre-commit block is avoidable.

---

## Multiple projects, one machine

If you work across several projects and want different rules per project:

- Put the **shared** rules in `~/.claude/CLAUDE.md` and `~/.config/opencode/AGENTS.md`.
- Put the **per-project** rules in the project root's `CLAUDE.md` and `AGENTS.md`.
- Both tools merge the two layers at session start, with the project layer winning on conflict.

The bundle's templates are written assuming they land in the project root. If you want them at user level instead, copy manually rather than using `--templates` (which writes to `$(pwd)`).

---

## See also

- [`templates/CLAUDE.md.example`](../templates/CLAUDE.md.example) — Claude Code starter.
- [`templates/AGENTS.md.example`](../templates/AGENTS.md.example) — OpenCode starter.
- [`agents.md`](agents.md) — how agents interact with the global rules file.
- [`skills.md`](skills.md) — how skills interact with the global rules file.
- [`compatibility.md`](compatibility.md) — which tool reads which file.
