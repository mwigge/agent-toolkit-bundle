# openspec

Spec-driven development for AI coding assistants. This sub-package ships the
*integration layer* — skills, docs, and configuration reference — so you can
use the `@fission-ai/openspec` CLI with Claude Code, OpenCode, Codex, and 20+
other AI coding tools.

## What it does

OpenSpec adds a lightweight spec layer between you and your AI agent. Instead
of vague prompts and unpredictable results, each change gets its own folder
with a proposal, technical design, spec deltas, and a task checklist. Human and
AI align on what to build before any code is written.

```
openspec/changes/add-dark-mode/
├── proposal.md     ← why we're doing this, what's changing
├── design.md       ← technical approach and decisions
├── specs/          ← requirement deltas against main specs
└── tasks.md        ← implementation checklist
```

The workflow is three commands:

```
/opsx:propose   → agree on what to build
/opsx:apply     → implement it task by task
/opsx:archive   → promote specs, archive the change
```

## Install summary

```bash
npm install -g @fission-ai/openspec@latest
openspec --version
```

Full walkthrough: [`docs/install.md`](docs/install.md).

## Quick start

```bash
# 1. Install (once, globally)
npm install -g @fission-ai/openspec@latest

# 2. Initialize in your project (once per repo)
cd /path/to/repo
openspec init

# 3. Start a change (inside your AI coding session)
/opsx:propose add-dark-mode

# 4. Implement
/opsx:apply

# 5. Archive when done
/opsx:archive
```

## Files

```
openspec/
├── README.md                  this file
├── docs/
│   ├── install.md             end-to-end setup, platform-specific notes
│   ├── workflow.md            propose → apply → archive lifecycle
│   └── configuration.md       openspec init options, schemas, config reference
└── config/
    └── openspec.yaml.example  example openspec change configuration
```

## Skills in this bundle

Four skills in `skills/` (flat) cover the full OpenSpec workflow:

| Skill | Slash command | When to use |
|-------|--------------|-------------|
| `openspec-propose` | `/opsx:propose` | Start a new change with full artifacts |
| `openspec-apply-change` | `/opsx:apply` | Implement tasks from an existing change |
| `openspec-explore` | `/opsx:explore` | Think through a problem before committing |
| `openspec-archive-change` | `/opsx:archive` | Finalize and promote specs when done |

## Supported tools

Works natively with 25+ AI coding assistants including Claude Code, OpenCode,
Codex, Cursor, GitHub Copilot, Windsurf, Gemini CLI, and more.

See [openspec.dev](https://openspec.dev) for the full supported tool list.

## No MCP server

OpenSpec is CLI-only. It has no MCP server. The AI interacts with it through
slash commands and the `openspec` CLI. No background process required.

## Telemetry

OpenSpec collects anonymous command names and version to understand usage
patterns. No arguments, paths, content, or PII are collected.

Opt out:
```bash
export OPENSPEC_TELEMETRY=0
# or
export DO_NOT_TRACK=1
```

## Related

- `codegraph` — structural code intelligence via MCP. Pair with OpenSpec for
  context-aware planning: OpenSpec tracks *what* you're building, CodeGraph
  tracks *what* the code currently does.
