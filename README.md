# agent-toolkit-bundle

A bundle of agents, skills, hooks, plugins, custom tools, commands, and global rules for [Claude Code](https://claude.com/claude-code) and [OpenCode](https://opencode.ai). One repo, one installer, two tools supported. GitHub Copilot CLI support is planned — see [`docs/copilot.md`](docs/copilot.md).

Sibling to [`agent-circuit-breaker`](https://github.com/mwigge/agent-circuit-breaker) — the companion repo that ships the dual-context mode guard. This bundle does **not** re-ship the mode guard; install the circuit breaker separately if you want it. See [`docs/ecosystem.md`](docs/ecosystem.md) for the full list of companion tools.

---

## Why

- **One source of truth.** The cloned repo IS the golden copy. The installer creates symlinks from each tool's install location back into the repo — no files are copied. `git pull` propagates instantly to every installed component, across every tool.
- **Opinionated defaults.** TDD, conventional commits, no AI attribution, structured logging, strict types. The bundle encodes a stack discipline rather than a toolbox of optional pieces.
- **Tool-selectable install.** Run the installer, pick a profile, get exactly what your tool supports. Claude Code gets hooks + skills; OpenCode gets plugins + custom tools + skills; agents and commands install to both. Skills are tool-neutral and install once under `~/.agents/skills/`.
- **Apache-2.0, no vendor lock-in.** Every file is plain text. Fork it, rename it, delete half of it — the installer still works.

This bundle is opinionated. If you want a pick-and-choose library of loose files, this is not it.

---

## What's in the bundle

| Component | Count | Tool support        |
|-----------|-------|---------------------|
| Agents    | 15 Claude / 16 OpenCode | both (dual copies; OpenCode has one extra) |
| Commands  | 10   | both (dual copies) |
| Skills    | ~40  | both (native skill support on Claude Code and OpenCode v1.0.110+) |
| Hooks     | 11   | Claude Code only (shell) |
| Plugins   | 7    | OpenCode only (TypeScript lifecycle modules) |
| Custom tools | 2 | OpenCode only (LLM-callable TypeScript functions) |
| Scripts   | 1    | OpenCode only (`delegate.sh` — orchestrator → subagent dispatch) |
| Templates | 3    | both (user-owned) |
| MemPalace | sub-package | opt-in integration for the upstream `milla-jovovich/mempalace` server |

Agents include architecture review, per-language coders (Python / TypeScript / SQL), test and TDD drivers, an adversarial reviewer, SRE, security, API designer, observability, data engineer / analyst, AI developer, product owner.

Skills cover Python, TypeScript, Rust, Go, Node, Docker, Kubernetes, Terraform, Postgres, OAuth, OTel, SRE, security, chaos engineering, data analysis, presentation, PR review, OpenSpec workflow, and ~25 more. Skills are native in both Claude Code and OpenCode and install once at the tool-neutral `~/.agents/skills/` path — see [`docs/skills.md`](docs/skills.md).

Hooks enforce: format-on-save, inline quality gates, no-AI-attribution in commits, a security guard, a setup init, a permission auto-approver, structured observability, transcript backup, skill activation, and a post-Stop quality gate.

Plugins mirror the hook surface for OpenCode where the semantics translate: format-on-save, inline quality, no-AI-attribution, observability, quality gate, security guard, session init. See [`docs/plugins.md`](docs/plugins.md).

Custom tools are OpenCode-only, LLM-callable TypeScript functions that bridge a specific gap: OpenCode's built-in `skill` tool loads `SKILL.md` but not the skill's `refs/`, `scripts/`, or `templates/` subdirectories. The bundle's `skill_ref` and `skill_list_refs` custom tools restore progressive-disclosure skill loading on OpenCode. See [`docs/tools.md`](docs/tools.md).

Templates are user-owned starter files — `CLAUDE.md.example`, `AGENTS.md.example`, and `opencode.json.example` — that land in your project root via `--templates`. See [`docs/rules.md`](docs/rules.md) for how the two system-prompt files interact.

MemPalace is an **opt-in** sub-package under `mempalace/` that ships an integration layer (hooks, plugin, custom tools, skill, slash command, contract docs) for the upstream [`milla-jovovich/mempalace`](https://github.com/milla-jovovich/mempalace) MCP server. Not installed by default. See the [Optional: MemPalace (BYO)](#optional-mempalace-byo) section below and [`docs/install-mempalace.md`](docs/install-mempalace.md).

---

## Install model — symlinks, not copies

`install.sh` creates symlinks from each tool's canonical install location back into the cloned repo. The cloned repo IS the golden copy. A `git pull` in the repo propagates to every installed component without re-running anything.

Chain for skills:

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

Agents, commands, hooks, plugins, and custom tools symlink directly into the tool-specific install dirs — no `~/.agents/` middleman, because those components have no cross-tool neutral convention yet.

**Keep the repo at a persistent path.** Moving it after install breaks every symlink. Re-running `install.sh` from the new location re-creates them. A typical place to park it is `~/src/agent-toolkit-bundle` or `~/dev/src/agent-toolkit-bundle`, somewhere you will not accidentally `rm -rf` during a disk cleanup.

Templates (`.example` files) are the one exception — they are copied, not symlinked, because users edit their project-local copy.

---

## Quick install

```bash
git clone https://github.com/mwigge/agent-toolkit-bundle.git
cd agent-toolkit-bundle
./install.sh
```

`install.sh` auto-detects which tool(s) you have installed and symlinks the right subset. Existing real files are left alone unless you pass `--force`. Existing symlinks are always replaced (safe — the repo is the source of truth).

Common variants:

```bash
# Claude Code only, agents + skills, no hooks
./install.sh --profile claude --components agents,skills

# OpenCode only, force overwrite
./install.sh --profile opencode --force

# Non-interactive CI
./install.sh --yes --profile both

# Also drop the system-prompt templates into the current project
cd ~/my-project && /path/to/agent-toolkit-bundle/install.sh --templates

# Opt in to the mempalace sub-package on top of the default install
./install.sh --components agents,skills,hooks,plugins,tools,commands,mempalace
```

See `./install.sh --help` for the full option list.

---

## Install — Claude Code only

```bash
./install.sh --profile claude
```

This symlinks:

- `agents/claude/*.md` → `~/.claude/agents/`
- `commands/claude/**/*.md` → `~/.claude/commands/`
- `skills/**` → `~/.agents/skills/` and `~/.claude/skills/`
- `hooks/*.sh` → `~/.claude/hooks/`

The installer does **not** edit `~/.claude/settings.json`. Merge the following block into your settings yourself — only the hooks you actually want to run need to be listed:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|Bash",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/hooks/security-guard.sh" },
          { "type": "command", "command": "bash ~/.claude/hooks/permission-autoapprove.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/hooks/format-on-save.sh" },
          { "type": "command", "command": "bash ~/.claude/hooks/inline-quality.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/hooks/quality-gate.sh" },
          { "type": "command", "command": "bash ~/.claude/hooks/no-ai-attribution.sh" }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/hooks/setup-init.sh" }
        ]
      }
    ]
  }
}
```

See [`docs/hooks.md`](docs/hooks.md) for a full hook-by-hook reference.

---

## Install — OpenCode only

```bash
./install.sh --profile opencode
```

This symlinks:

- `agents/opencode/*.md` → `~/.config/opencode/agent/`
- `commands/opencode/**/*.md` → `~/.config/opencode/command/`
- `plugins/*.ts` → `~/.config/opencode/plugin/`
- `tools/*.ts` → `~/.config/opencode/tools/`
- `scripts/delegate.sh` → `~/.config/opencode/scripts/delegate.sh`
- `skills/**` → `~/.agents/skills/` (OpenCode reads this natively)

OpenCode auto-loads plugins and tools from those directories at startup — no settings file to edit. Restart OpenCode after the install so the plugins and tools take effect.

For a recommended `opencode.json` starter, see [`templates/opencode.json.example`](templates/opencode.json.example) and its annotated explainer at [`templates/opencode.json.example.md`](templates/opencode.json.example.md).

See [`docs/plugins.md`](docs/plugins.md), [`docs/tools.md`](docs/tools.md), and [`docs/skills.md`](docs/skills.md) for the full reference.

---

## Configure

Every shipped file uses literal `<your-…>` placeholders where anything project-specific might otherwise leak. After installing, run a grep to find what you need to substitute in your own copies:

```bash
grep -rn '<your-' ~/.claude/agents ~/.claude/commands ~/.agents/skills 2>/dev/null
grep -rn '<your-' ~/.config/opencode/agent ~/.config/opencode/command 2>/dev/null
```

The installer does **not** rewrite placeholders. That is deliberate — you should read what you're configuring, not trust a sed-pass to guess correctly. Because the installed files are symlinks back into the repo, edit them in the repo (not through the symlinks) if you plan to version the edits in git.

### Placeholder table

| Placeholder         | Replace with                                  |
|---------------------|-----------------------------------------------|
| `<your-org>`        | Your organisation or employer name            |
| `<your-project>`    | The project this install is for               |
| `<your-dev-dir>`    | Parent directory for your source checkouts    |
| `<your-docs-dir>`   | Where your planning / spec docs live          |
| `<your-git-host>`   | Your internal Git host (if any)               |
| `<your-jira-host>`  | Your Jira / issue tracker host                |
| `<your-artifactory>`| Your private package registry host            |
| `<your-github-user>`| Your GitHub username                          |
| `<PROJ>`            | Your Jira / tracker project key               |

Placeholders are literal strings, not template variables. They render fine in the agent prompts as-is — the agent will ask you for the real values the first time it needs them.

For detail on `CLAUDE.md` / `AGENTS.md` discovery order and how to disable OpenCode's Claude Code compatibility layer, see [`docs/rules.md`](docs/rules.md).

---

## Optional: MemPalace (BYO)

MemPalace is a persistent cross-session memory pattern — wings → rooms → halls → drawers plus a per-agent diary — backed by an external MCP server. The bundle ships an opt-in **integration layer** under `mempalace/` (hooks, plugin, OpenCode custom tools, skill, slash command, MCP contract docs) that targets any MCP-compatible backend.

**Recommended backend**: [`milla-jovovich/mempalace`](https://github.com/milla-jovovich/mempalace) — the upstream project this sub-package integrates with. MIT-licensed, `pip install mempalace`, ships its own Claude Code marketplace plugin and a generic MCP server entry point. Install it once, set `MEMPAL_DIR=~/my-project/docs_local` so auto-ingest knows where to look, then run `./install.sh --components mempalace` to wire up the bundle's integration layer on top.

The bundle integration is opt-in — it is **not** installed by the default `install.sh` invocation. If you have no need for persistent cross-session memory, ignore the sub-package entirely.

Full walkthrough: [`docs/install-mempalace.md`](docs/install-mempalace.md). Sub-package internals: [`mempalace/README.md`](mempalace/README.md).

---

## Copilot CLI

GitHub Copilot CLI support is **planned** but not yet shipped. Copilot CLI is installable via `brew install copilot-cli@prerelease` and officially supports agent skills per GitHub docs, but its exact discovery paths for skills / agents / commands are not publicly confirmed in a form the bundle can safely target without risking silent breakage. See [`docs/copilot.md`](docs/copilot.md) for the status, a manual workaround, and what needs confirming before `--profile copilot` ships.

---

## Repository layout

```
agent-toolkit-bundle/
├── README.md
├── LICENSE                       # Apache-2.0 verbatim
├── install.sh                    # Symlink-based installer
├── .gitignore
│
├── agents/
│   ├── claude/                   # Claude Code agent format (.md)
│   └── opencode/                 # OpenCode agent format (.md with frontmatter)
│
├── skills/                       # Tool-neutral (both tools read natively)
│   └── <skill>/SKILL.md          # One directory per skill
│
├── hooks/                        # Claude Code only (shell)
│
├── plugins/                      # OpenCode only (TypeScript lifecycle modules)
│   ├── package.json
│   └── tsconfig.json
│
├── tools/                        # OpenCode only (LLM-callable TypeScript)
│   ├── package.json
│   └── tsconfig.json
│
├── scripts/                      # OpenCode only (shell helpers, e.g. delegate.sh)
│   └── delegate.sh
│
├── commands/                     # Slash commands (both tools)
│   ├── claude/
│   └── opencode/
│
├── templates/                    # User-owned starters
│   ├── CLAUDE.md.example
│   ├── AGENTS.md.example
│   ├── opencode.json.example
│   └── opencode.json.example.md  # annotated explainer
│
├── mempalace/                    # Opt-in sub-package (BYO MCP backend)
│   ├── README.md
│   ├── skill/SKILL.md
│   ├── hooks/ plugins/ tools/ commands/ config/
│   └── docs/install.md, mcp-contract.md, ingestion.md, configuration.md
│
└── docs/
    ├── agents.md
    ├── skills.md
    ├── hooks.md
    ├── commands.md
    ├── plugins.md
    ├── tools.md
    ├── rules.md
    ├── copilot.md
    ├── ecosystem.md
    ├── installation.md
    ├── compatibility.md
    └── install-mempalace.md
```

The per-tool subdirs under `agents/` and `commands/` are intentional: even if 80% of an agent file is identical between Claude Code and OpenCode, the frontmatter is not. A flat dual-copy is boring, and boring is correct for a reference repo. The drift is caught by a parity check in CI.

---

## Companion tools

- [`agent-circuit-breaker`](https://github.com/mwigge/agent-circuit-breaker) — a pre-tool circuit breaker that enforces hard separation between two work contexts. Install it alongside this bundle if you work in two contexts (employer + personal) and want blast-radius protection against cross-contamination.
- [`milla-jovovich/mempalace`](https://github.com/milla-jovovich/mempalace) — the upstream MCP server the bundle's mempalace sub-package integrates with.
- See [`docs/ecosystem.md`](docs/ecosystem.md) for the full list.

---

## Uninstall

```bash
# Symlinks only — safe to run without --force because the installer
# never replaces real files.
find ~/.claude/agents ~/.claude/commands ~/.claude/hooks \
     ~/.config/opencode/agent ~/.config/opencode/command \
     ~/.config/opencode/plugin ~/.config/opencode/tools \
     ~/.config/opencode/scripts \
     ~/.agents/skills ~/.claude/skills \
     -maxdepth 1 -type l -delete 2>/dev/null

# Then remove the settings.json block you added for the hooks, and
# the mempalace section if you installed it.
```

Because the installer creates symlinks, uninstall is just `find -type l -delete`. The cloned repo is untouched.

---

## License

Apache License 2.0. See `LICENSE`.
