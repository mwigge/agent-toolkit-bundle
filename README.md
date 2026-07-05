# agent-toolkit-bundle

**The single source-of-truth for engineering rules, skills, hooks, agents, commands, and governance — symlinked into every AI coding tool you use.**

One repository holds the standards your agents must follow (`CLAUDE.md` + templates), the domain knowledge they load on demand (`skills/`), the deterministic guardrails that enforce the rules (`hooks/` + `plugins/`), the role-specific sub-agents (`agents/`), the workflow commands (`commands/`), the shared policy data (`policy/`), and the MCP integrations for memory and code intelligence. `install.sh` symlinks it into Claude Code and OpenCode, and the same corpus is consumed by Codex and Gemini. Edit a file here once — it changes everywhere.

---

## Why this exists (the differentiators)

Most agent-asset collections are a pile of advisory skills. This one is a governed, enforced, multi-tool platform:

- **Governance & compliance layer.** A PII guard that blocks PANs/IBANs/national IDs before they reach a tool call; an egress allowlist; a **tamper-evident, hash-chained audit log** (each entry commits to the previous entry's hash); DORA and PCI-DSS 4.0 control mappings (`skills/compliance`, `docs/data-classification.md`); and OpenTelemetry agent tracing (`docs/otel-agent-tracing.md`). Nothing else in the ecosystem ships this.
- **Deterministic enforcement, not suggestions.** Rules are enforced by **blocking hooks** (Claude Code) with **TypeScript plugin twins** (OpenCode) that share one policy source (`policy/guard-patterns.json`). Skills advise; hooks *stop* you — non-parameterised SQL, `print()` in library code, force-pushes to `main`, secret literals, and unformatted files are caught at the tool boundary.
- **No-AI-attribution + mode circuit-breaker.** Commits and PRs are scrubbed of AI attribution deterministically. A company/private "mode" guard hard-separates work and personal paths at every tool call.
- **Spec-driven workflow.** OpenSpec (`/opsx:*`) gives every non-trivial change a paper trail: explore → propose → apply → archive.
- **Persistent memory + code intelligence over MCP.** **MemPalace** (cross-session memory: wings/rooms/halls/drawers) and **CodeGraph** (symbol search, call graphs, blast-radius) are wired as MCP servers for all tools.
- **Multi-tool source-of-truth.** One repo drives **Claude Code**, **OpenCode**, **Codex**, and **Gemini** agents — no divergent copies.
- **The deepest reliability vertical in the ecosystem.** First-class SRE, observability, multi-cloud (AWS/Azure/GCP), and Datadog skills — SLO/error-budget, incident response, capacity forecasting, runbooks, alerting, dashboards.

---

## What's inside (verified against the tree)

| Asset | Count | Location |
|-------|-------|----------|
| **Skills** | 166 skill directories (159 top-level loadable `SKILL.md` + nested sub-skills; **194** `SKILL.md` files total) | `skills/` |
| **Agents — Claude Code** | 19 | `agents/claude/` |
| **Agents — OpenCode** | 21 (the 19 + `opsx`, `refactor`) | `agents/opencode/` |
| **Agents — Gemini** | 15 (agents-only, experimental) | `agents/gemini/` |
| **Hooks (shell)** | 18 | `hooks/` |
| **Plugins (TypeScript)** | 13 | `plugins/` |
| **Commands — Claude Code** | 13 | `commands/claude/` |
| **Commands — OpenCode** | 14 (the 13 + `model-report`) | `commands/opencode/` |
| **Shared policy data** | guard patterns, model-tier map | `policy/` |
| **MCP sub-packages** | MemPalace, CodeGraph, OpenSpec | `mempalace/`, `codegraph/`, `openspec/` |

The exhaustive, categorised skill catalogue lives in **[docs/skills.md](docs/skills.md)**; auto-activation keyword mappings live in **[skill-rules.json](skill-rules.json)**.

---

## Multi-tool support

| | Claude Code | OpenCode | Codex | Gemini |
|---|---|---|---|---|
| Instructions file | `CLAUDE.md` | `AGENTS.md` | `AGENTS.md` | `GEMINI.md` |
| Agents | 19 (`agents/claude/`) | 21 (`agents/opencode/`) | reused as role prompts | 15 (`agents/gemini/`) |
| Enforcement | 18 blocking shell hooks | 13 TypeScript plugins | advisory (no native hook runtime) | advisory (no native hook runtime) |
| Commands | 13 native slash commands | 14 native slash commands | markdown playbooks | reused as playbooks |
| Skills | shared from `skills/` | shared from `skills/` | shared from `skills/` | shared from `skills/` |
| Memory / code intel | MemPalace + CodeGraph (MCP) | MemPalace + CodeGraph (MCP) | MemPalace + CodeGraph (MCP) | via MCP where supported |
| Install | `install.sh` symlinks | `install.sh` symlinks | starter templates (below) | agent files + `GEMINI.md` template |

**Codex** consumes the shared corpus directly: use `templates/AGENTS.md.example` as your project `AGENTS.md`, and create a `config.toml` from `templates/codex.config.toml.example` (which wires MemPalace and CodeGraph as `[[mcp_servers]]`). Codex has no native hook/plugin runtime here, so the hooks and plugins act as documented policy rather than deterministic enforcement — see **[docs/codex.md](docs/codex.md)**.

**Gemini** ships **15 agent definitions** in `agents/gemini/` (frontmatter uses Gemini tool names: `read_file`, `write_file`, `replace`, `glob`, `grep_search`, `run_shell_command`). It is **agents-only and experimental** — there is no Gemini hook/plugin runtime and the installer does not auto-symlink Gemini. Use `templates/GEMINI.md.example` for project instructions and read shared `skills/` on demand.

---

## Install

```bash
git clone https://github.com/mwigge/agent-toolkit-bundle.git
cd agent-toolkit-bundle
./install.sh --help     # inspect options first
./install.sh            # symlink into Claude Code + OpenCode
```

`install.sh` creates symlinks from `~/.claude/` and `~/.config/opencode/` into this checkout (agents, commands, hooks, plugins, tools, and skills), so edits here are live everywhere immediately. It is idempotent and backs up any existing non-symlink files. Optional flags:

- `--templates` copies `CLAUDE.md.example`, `AGENTS.md.example`, `GEMINI.md.example`, and a Codex `.codex/config.toml` into the current directory.
- `--components a,b,c` installs a subset (`agents,skills,hooks,plugins,tools,scripts,commands,mempalace,codegraph,openspec`).

`settings.json` for Claude Code is **copied, not symlinked** (it carries per-machine hook paths). See **[docs/installation.md](docs/installation.md)** for the full cross-platform guide, prerequisites, and the mode circuit-breaker shell function.

> **Hooks fail open.** Every hook that depends on an external tool (`jq`, `python3`, formatters, `codegraph`, `mempalace`) guards on it and exits cleanly if it is absent — a fresh box never errors, it just enforces less.

---

## Slash commands

Native in Claude Code (`commands/claude/`) and OpenCode (`commands/opencode/`):

| Command | Purpose |
|---------|---------|
| `/commit` | Analyse the diff, draft a conventional commit, validate, commit |
| `/pr` | Validate branch, push, fill the MR/PR template, open the request |
| `/story` | INVEST check, draft a user story with ACs, hand off to `@jira-story` |
| `/review` | Four-lens adversarial review of the current branch |
| `/test` | Generate and run tests for a target, closing coverage gaps |
| `/debug` | Systematic root-cause debugging of an error (reproduce -> isolate -> fix -> verify) |
| `/refactor` | Safe, behaviour-preserving refactor of a target, one verified step at a time |
| `/docs` | Generate or update docs (README, reference, docstrings, ADR) for a target |
| `/index` | Update the docs index and `memory.md` after a work session |
| `/opsx:propose` | OpenSpec — create a change with proposal, design, specs, tasks |
| `/opsx:explore` | OpenSpec — thinking mode, no implementation |
| `/opsx:apply` | OpenSpec — implement the next unchecked task |
| `/opsx:archive` | OpenSpec — promote specs, archive the change |
| `/model-report` | OpenCode only — tiered model usage / cost summary |

MemPalace ships an opt-in `/mempalace-mine` command in its sub-package (`mempalace/commands/`) — installed only when you enable the `mempalace` component.

---

## Agents

19 Claude Code agents, 21 in OpenCode (adds `opsx` and `refactor`), 15 in Gemini. Read-only-by-design agents are scoped to least privilege: `@architect` gets `Read, Grep, Glob`; `@debugger`, `@reviewer`, and `@security` get `Read, Grep, Glob, Bash` (no write); coder/tester agents keep their write tools. In Claude Code agents are leaf nodes (human-triggered handoffs); in OpenCode the orchestrator can spawn `mode: subagent` agents autonomously. Full inventory and collaboration flow: **[docs/agents.md](docs/agents.md)**. Per-agent model routing for OpenCode: **[docs/model-tier.md](docs/model-tier.md)** and **[docs/local-models.md](docs/local-models.md)**.

---

## Enforcement: hooks and plugins

18 shell hooks (Claude Code) and 13 TypeScript plugins (OpenCode) enforce the same rules from one policy source (`policy/guard-patterns.json`). Highlights: `mode-guard`, `no-ai-attribution`, `security-guard`, `pii-guard` (PreToolUse, blocking); `format-on-save`, `inline-quality`, `codegraph-sync`, `mempalace-ingest` (PostToolUse); `quality-gate` (Stop, blocking); `observe` (tamper-evident audit chain); `permission-autoapprove` (GREEN/YELLOW/RED tiers). Lifecycle, exit codes, and the plugin API: **[docs/hooks.md](docs/hooks.md)** and **[docs/plugins.md](docs/plugins.md)**.

---

## OpenSpec workflow

Every non-trivial change gets a paper trail:

```
/opsx:explore   →  think before committing to a solution
/opsx:propose   →  proposal.md, design.md, specs/, tasks.md
/opsx:apply     →  implement the next unchecked task
/opsx:archive   →  promote specs, archive the change
```

OpenSpec is a prerequisite: `npm install -g @fission-ai/openspec@latest`, then `openspec init --tools <claude|opencode|codex>` in a project. See [openspec.dev](https://openspec.dev) and `openspec/docs/`.

---

## MemPalace & CodeGraph (MCP)

- **MemPalace** — persistent cross-session memory (facts, events, discoveries, preferences, advice) backed by ChromaDB, entirely local. Setup: **[docs/install-mempalace.md](docs/install-mempalace.md)**.
- **CodeGraph** — structural code intelligence: `codegraph_search`, `codegraph_callers`, `codegraph_impact` (blast radius). Prefer it over Grep/Glob in large repos. See `codegraph/docs/`.

Both are wired as MCP servers for Claude Code, OpenCode, and Codex.

---

## Further reading

- **[docs/installation.md](docs/installation.md)** — full install guide, prerequisites, mode circuit-breaker
- **[docs/skills.md](docs/skills.md)** — the complete skill catalogue by domain
- **[docs/agents.md](docs/agents.md)** — all agents, when to invoke, handoff patterns
- **[docs/hooks.md](docs/hooks.md)** / **[docs/plugins.md](docs/plugins.md)** — enforcement lifecycle
- **[docs/commands.md](docs/commands.md)** — slash commands
- **[docs/codex.md](docs/codex.md)** — Codex reference setup
- **[docs/model-tier.md](docs/model-tier.md)** / **[docs/local-models.md](docs/local-models.md)** — model routing
- **[docs/data-classification.md](docs/data-classification.md)** / **[docs/otel-agent-tracing.md](docs/otel-agent-tracing.md)** — governance & tracing
- **[CLAUDE.md](CLAUDE.md)** — the engineering rules every project inherits
