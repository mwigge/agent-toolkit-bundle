# agent-toolkit-bundle

A bundle of agents, skills, hooks, commands, and plugins for [Claude Code](https://claude.com/claude-code) and [OpenCode](https://opencode.ai). One repo, one installer, two tools supported.

Sibling to [`agent-circuit-breaker`](https://github.com/mwigge/agent-circuit-breaker) — the companion repo that ships the dual-context mode guard. This bundle does **not** re-ship the mode guard; install the circuit breaker separately if you want it.

---

## Why

- **One source of truth** for agents, skills, and commands across Claude Code and OpenCode. Change an agent once; dual copies stay in lock-step.
- **Opinionated defaults.** TDD, conventional commits, no AI attribution, structured logging, strict types. The bundle encodes a stack discipline rather than a toolbox of optional pieces.
- **Tool-selectable install.** Run the installer, pick a profile, get exactly what your tool supports. Claude Code gets hooks + skills; OpenCode gets plugins; agents and commands install to both.
- **Apache-2.0, no vendor lock-in.** Every file is plain text. Fork it, rename it, delete half of it — the installer still works.

This bundle is opinionated. If you want a pick-and-choose library of loose files, this is not it.

---

## What's in the bundle

| Component | Count | Tool support        |
|-----------|-------|---------------------|
| Agents    | 15 Claude / 16 OpenCode | both (dual copies; OpenCode has one extra) |
| Commands  | 10   | both (dual copies) |
| Skills    | 43   | Claude Code only    |
| Hooks     | 11   | Claude Code only    |
| Plugins   | 7    | OpenCode only       |
| Templates | 2    | both (user-owned)   |

Agents include architecture review, per-language coders (Python / TypeScript / SQL), test and TDD drivers, an adversarial reviewer, SRE, security, API designer, observability, data engineer / analyst, AI developer, product owner.

Skills cover Python, TypeScript, Rust, Go, Node, Docker, Kubernetes, Terraform, Postgres, OAuth, OTel, SRE, security, chaos engineering, data analysis, presentation, PR review, OpenSpec workflow, and ~25 more.

Hooks enforce: format-on-save, inline quality gates, no-AI-attribution in commits, a security guard, a setup init, a permission auto-approver, structured observability, transcript backup, skill activation, and a post-Stop quality gate.

Plugins mirror the hook surface for OpenCode where the semantics translate: format-on-save, inline quality, no-AI-attribution, observability, quality gate, security guard, session init.

---

## Quick install

```bash
git clone https://github.com/mwigge/agent-toolkit-bundle.git
cd agent-toolkit-bundle
./install.sh
```

`install.sh` auto-detects which tool(s) you have installed and copies the right subset. Existing files are left alone unless you pass `--force`. Re-runs are idempotent.

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
```

See `./install.sh --help` for the full option list.

---

## Install — Claude Code only

```bash
./install.sh --profile claude
```

This copies:

- `agents/claude/*.md` → `~/.claude/agents/`
- `commands/claude/**/*.md` → `~/.claude/commands/`
- `skills/**` → `~/.claude/skills/`
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

This copies:

- `agents/opencode/*.md` → `~/.config/opencode/agent/`
- `commands/opencode/**/*.md` → `~/.config/opencode/command/`
- `plugins/*.ts` → `~/.config/opencode/plugin/`

OpenCode auto-loads plugins from that directory at startup — no settings file to edit. Restart OpenCode after the install so the plugins take effect.

See [`docs/plugins.md`](docs/plugins.md) for the plugin lifecycle.

---

## Configure

Every shipped file uses literal `<your-…>` placeholders where anything project-specific might otherwise leak. After installing, run a grep to find what you need to substitute in your own copies:

```bash
grep -rn '<your-' ~/.claude/agents ~/.claude/commands ~/.claude/skills 2>/dev/null
grep -rn '<your-' ~/.config/opencode/agent ~/.config/opencode/command 2>/dev/null
```

The installer does **not** rewrite placeholders. That is deliberate — you should read what you're configuring, not trust a sed-pass to guess correctly.

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

---

## Optional: MemPalace

MemPalace is a persistent cross-session memory pattern backed by an external MCP server, organised as wings → rooms → halls → drawers plus a per-agent diary. **This bundle ships zero MemPalace code** — no hooks, no plugin, no skill, no command.

If you want to wire up your own MemPalace integration, [`docs/install-mempalace.md`](docs/install-mempalace.md) describes the MCP tool contract, hook sketches, and wing design trade-offs in enough detail to implement your own ingestion layer from scratch. A reader who understands the pattern can build a working hook in under an hour; a reader who doesn't would not be helped by shipped templates anyway.

---

## Repository layout

```
agent-toolkit-bundle/
├── README.md
├── LICENSE                       # Apache-2.0 verbatim
├── install.sh                    # Selective installer
├── .gitignore
│
├── agents/
│   ├── claude/                   # Claude Code agent format (.md)
│   └── opencode/                 # OpenCode agent format (.md with frontmatter)
│
├── skills/                       # Claude Code only
│   ├── SKILL.md                  # Skill index
│   └── <skill>/SKILL.md          # One directory per skill
│
├── hooks/                        # Claude Code only (shell)
│
├── plugins/                      # OpenCode only (TypeScript)
│   ├── package.json
│   └── tsconfig.json
│
├── commands/                     # Slash commands (both tools)
│   ├── claude/
│   └── opencode/
│
├── templates/                    # System-prompt starters (user-owned)
│   ├── CLAUDE.md.example
│   └── AGENTS.md.example
│
└── docs/
    ├── agents.md
    ├── skills.md
    ├── hooks.md
    ├── commands.md
    ├── plugins.md
    ├── installation.md
    ├── compatibility.md
    └── install-mempalace.md
```

The per-tool subdirs under `agents/` and `commands/` are intentional: even if 80% of an agent file is identical between Claude Code and OpenCode, the frontmatter is not. A flat dual-copy is boring, and boring is correct for a reference repo. The drift is caught by a parity check in CI.

---

## Companion tools

- [`agent-circuit-breaker`](https://github.com/mwigge/agent-circuit-breaker) — a pre-tool circuit breaker that enforces hard separation between two work contexts. Install it alongside this bundle if you work in two contexts (employer + personal) and want blast-radius protection against cross-contamination.

---

## Uninstall

```bash
# Claude Code
rm -rf ~/.claude/agents ~/.claude/commands ~/.claude/skills ~/.claude/hooks

# OpenCode
rm -rf ~/.config/opencode/agent ~/.config/opencode/command ~/.config/opencode/plugin

# Then remove the settings.json block you added for the hooks.
```

---

## License

Apache License 2.0. See `LICENSE`.
