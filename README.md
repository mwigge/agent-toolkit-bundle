# ai_local — AI-Assisted Development Reference Installation

A complete, opinionated setup for AI-assisted software engineering, supporting **Claude Code**, **OpenCode**, and a **Codex reference install**. Ships with 43 skills, 17 agents, 15 hooks (Claude Code) / 11 plugins (OpenCode), 11 slash commands, MCP-backed memory and code intelligence, the OpenSpec spec-driven development workflow, and a governance layer (PII guard, egress allowlisting, tamper-evident audit, DORA + PCI-DSS compliance mappings, OTel agent tracing).

This repository is the **source of truth**. Both tools are configured to read from here via symlinks — editing a file in `ai_local/` changes it everywhere instantly.

## Codex Reference

A Codex reference install now lives in `ai_local/codex/`.

- Rules file: `ai_local/codex/AGENTS.md`
- MCP config: `ai_local/codex/config.toml`
- Installer: `ai_local/codex/install.sh`

This variant reuses `ai_local` skills, command playbooks, agent prompts, and MCP integrations.
Claude hooks and OpenCode plugins are reused as policy and workflow logic, not as native Codex
runtime integrations.

Gemini currently appears in the architecture material as a design/reference direction, but
`ai_local` does **not** yet ship a packaged Gemini installation alongside Claude Code,
OpenCode, and Codex.

| Feature | Claude Code | OpenCode | Codex |
|---------|-------------|----------|-------|
| Provider | Anthropic (Claude) | Multi-provider (Copilot, Ollama, OpenAI, Gemini, etc.) | OpenAI Codex CLI |
| Project instructions | `CLAUDE.md` | `AGENTS.md` | `AGENTS.md` |
| Config file | `~/.claude/settings.json` | `~/.config/opencode/opencode.json` | `~/.codex/config.toml` |
| Project config | `.claude/settings.local.json` | `.opencode.json` | `.codex/config.toml` |
| MCP servers | `.mcp.json` | `mcp` in `.opencode.json` | `[mcp_servers]` in `.codex/config.toml` |
| Enforcement | 14 shell hooks (deterministic) | 10 TypeScript plugins | Manual guardrails derived from hooks/plugins |
| Agents | 17 role-specific sub-agents | Same 17 agents, model-pinned | Reused as role prompts / delegation contracts |
| Skills | 43 domain knowledge modules | Via `AGENTS.md` context | Reused directly from `ai_local/skills/` |
| Memory / code intel | MemPalace + CodeGraph via MCP | MemPalace + CodeGraph via MCP | MemPalace + CodeGraph via MCP |
| OpenSpec | Native workflow support | Native workflow support | Native workflow support |
| Config source | `ai_local/.claude/` | `ai_local/opencode/` | `ai_local/codex/` |

---

## Prerequisites

### 1. OpenSpec (required for all tools)

OpenSpec is a **hard prerequisite**. The spec-driven development workflow (`/opsx:propose`, `/opsx:apply`, `/opsx:explore`, `/opsx:archive`) depends on it. Without OpenSpec, you lose the ability to plan before you implement — and agent-assisted coding without a plan devolves into guesswork.

```bash
npm install -g @fission-ai/openspec@latest
```

Then initialise it in any project:

```bash
cd ~/dev/src/my-project
openspec init --tools claude    # for Claude Code
openspec init --tools opencode  # for OpenCode
openspec init --tools codex     # for Codex
```

This creates the `openspec/` directory structure:
```
openspec/
  changes/    <- active work (proposals, designs, specs, tasks)
  specs/      <- archived specifications (promoted after implementation)
```

See [openspec.dev](https://openspec.dev) for full documentation.
See [`openspec/docs/install.md`](openspec/docs/install.md) for the full
cross-platform install guide including Linux, pnpm, yarn, bun, and nix.

### 2. Claude Code CLI

```bash
npm install -g @anthropic-ai/claude-code
claude --version
```

Requires an Anthropic API key or Claude Max subscription. See [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code).

### 3. OpenCode CLI

```bash
# Option A: Install script
curl -fsSL https://raw.githubusercontent.com/opencode-ai/opencode/refs/heads/main/install | bash

# Option B: Homebrew
brew install opencode-ai/tap/opencode

# Option C: npm
npm i -g opencode-ai@latest

# Option D: Go
go install github.com/opencode-ai/opencode@latest
```

Requires at least one provider API key (OpenAI, Gemini, Copilot, Groq, etc.) or a local model via Ollama. See [OpenCode docs](https://opencode.ai/docs/).

### 4. Development tools

The hooks and skills assume these tools are available:

| Tool | Purpose | Install |
|------|---------|---------|
| `git` | Version control | Pre-installed on macOS (`xcode-select --install`); `apt install git` on Debian/Ubuntu |
| `node` 20+ | JS runtime (required by OpenSpec + CodeGraph) | `brew install node@22` / `nvm install 20` / NodeSource |
| `python` 3.10+ | Python projects | `brew install python@3.12` / `pyenv install 3.12` / `apt install python3` |
| `ruff` | Python linting + formatting | `pip install ruff` |
| `black` | Python formatting | `pip install black` |
| `mypy` | Python type checking | `pip install mypy` |
| `pytest` | Python testing | `pip install pytest pytest-cov` |
| `prettier` | TS/JSON/YAML formatting | `npm install -g prettier` |
| `gh` | GitHub CLI | `brew install gh` / [cli.github.com](https://cli.github.com) |
| `glab` | GitLab CLI (optional) | `brew install glab` / [gitlab.com/gitlab-org/cli](https://gitlab.com/gitlab-org/cli) |
| `jq` | JSON processing | `brew install jq` / `apt install jq` |

Not all tools are required. Hooks degrade gracefully — if `ruff` is not installed, the Python format-on-save hook skips silently.

### 5. Codex CLI

Codex uses a project `AGENTS.md` plus `.codex/config.toml` for MCP wiring.
This repository provides a Codex reference installation in `ai_local/codex/`.

Project-level install:

```bash
cd ~/dev/src/ai_local
bash codex/install.sh
```

That copies:

- `ai_local/codex/AGENTS.md` -> `~/dev/src/AGENTS.md`
- `ai_local/codex/config.toml` -> `~/dev/src/.codex/config.toml`

The Codex reference setup explicitly uses:

- **MemPalace** for cross-session memory and decision recovery
- **CodeGraph** for structural code analysis and impact tracing
- **OpenSpec** as the planning layer

---

## Installation

### Step 1: Clone the repository

```bash
mkdir -p ~/dev/src
cd ~/dev/src
git clone https://github.com/<github-user>/ai_local.git
```

### Step 2: Run install.sh

```bash
cd ~/dev/src/ai_local
bash install.sh
```

This single script wires up **both** Claude Code and OpenCode by creating symlinks from their config directories to `ai_local/`:

| Symlink created | Points to |
|----------------|-----------|
| `~/.claude/agents` | `ai_local/.claude/agents` |
| `~/.claude/commands` | `ai_local/.claude/commands` |
| `~/.claude/hooks` | `ai_local/.claude/hooks` |
| `~/.claude/skills` | `ai_local/skills` |
| `~/.config/opencode/agents` | `ai_local/opencode/agents` |
| `~/.config/opencode/plugins` | `ai_local/opencode/plugins` |
| `~/.config/opencode/commands` | `ai_local/opencode/commands` |
| `~/.config/opencode/AGENTS.md` | `ai_local/opencode/AGENTS.md` |
| `~/.config/opencode/opencode.json` | `ai_local/opencode/opencode.json` |
| `~/.config/opencode/package.json` | `ai_local/opencode/package.json` |

The script is idempotent — safe to re-run. Existing non-symlink files are backed up with a timestamp before replacement.

### Step 3: Copy settings.json (Claude Code)

```bash
cp ~/dev/src/ai_local/.claude/settings.json ~/.claude/settings.json
```

**Why copy, not symlink?** `settings.json` contains hook paths with `$HOME` references that differ per machine, and you may add personal permission overrides. Edit the copy to set your absolute hook paths.

### Step 4: Create the root CLAUDE.md

```bash
cp ~/dev/src/ai_local/CLAUDE.md ~/dev/src/CLAUDE.md
```

Edit `~/dev/src/CLAUDE.md` to match your team's standards. This file cascades to all projects under `~/dev/src/`.

### Step 5: Install plugin dependencies (OpenCode)

```bash
npm install --prefix ~/.config/opencode
```

This installs `@opencode-ai/plugin` used by the TypeScript enforcement plugins. `install.sh` does this automatically if `node_modules/` is absent.

### Step 6: Configure local models (OpenCode, optional)

If you want to run local models via Ollama:

```bash
brew install ollama
brew services start ollama
ollama pull devstral:24b          # ~9.6GB — primary model (thinking + tools + 128K context)
ollama pull devstral:24b   # ~9GB   — fast tasks (title, summary, compaction)
```

> **Zscaler note**: If `ollama pull` returns a 403, use the manual manifest injection workaround — see `docs_local/ollama_zscaler.md`.

The `opencode.json` is pre-configured for both. See [docs/local-models.md](docs/local-models.md) for the full model routing table.

### Step 7: Set your provider API key

```bash
export GITHUB_TOKEN="..."            # GitHub Copilot (default cloud model)
# or
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
```

### Step 8: Verify

```bash
# Claude Code
cd ~/dev/src/ai_local
claude
# Inside: /opsx:explore "test the setup" — @architect should load and respond

# OpenCode
cd ~/dev/src/ai_local
opencode
# Inside: ask anything — should respond via Qwen 14B (local) or Copilot (cloud)

# Codex
cd ~/dev/src
codex
# In this repo/project root: AGENTS.md + .codex/config.toml should be detected
# and MemPalace / CodeGraph should be available via MCP when configured
```

---

## Setup — Mode Circuit Breaker (Claude Code / OpenCode, shared with Codex reference)

The company/private mode guard prevents accidental cross-contamination between work and personal projects. Add this to your `~/.zshrc` (or `~/.bashrc`):

```bash
# AI dev mode circuit breaker
mode() {
  if [[ -z "$1" ]]; then
    cat ~/.claude/mode 2>/dev/null || echo "company"
    return
  fi
  if [[ "$1" != "company" && "$1" != "private" ]]; then
    echo "Usage: mode [company|private]"
    return 1
  fi
  echo "$1" > ~/.claude/mode
  echo "Mode: $1"
}

# Initialise mode file if missing
[[ ! -f ~/.claude/mode ]] && echo "company" > ~/.claude/mode
```

Then reload:
```bash
source ~/.zshrc
```

**Note**: The mode guard hook (`mode-guard.sh`) is enforced by Claude Code's hook system. OpenCode does not have a native hook system, so mode enforcement relies on discipline when using OpenCode. The Codex reference setup also relies on `AGENTS.md` guidance rather than deterministic hook enforcement. The `AGENTS.md` file can include a reminder: "Check `~/.claude/mode` before writing to any path."

---

## What's Inside

### Directory structure

```
ai_local/
  .claude/
    agents/          17 role-specific sub-agents (Claude Code)
    commands/        11 slash commands (/commit, /pr, /story, /review, /spec, /index, /mine, /opsx:*)
    hooks/           15 deterministic hooks (security, quality, formatting, observability, codegraph)
    settings.json    Hook wiring and permission config (reference copy — not symlinked)
    settings.local.json  Machine-specific overrides (not for sharing)
    skill-rules.json     Keyword-to-skill activation mapping
    permission-policy.md Three-tier auto-approve policy
  opencode/
    agents/          17 agent definitions with model: routing (OpenCode)
    plugins/         10 TypeScript enforcement plugins (OpenCode)
    commands/        11 slash commands (OpenCode)
    AGENTS.md        Global instructions + skill activation table
    opencode.json    Provider config, model routing, MCP servers
    package.json     @opencode-ai/plugin dependency
  skills/            43 domain knowledge modules (shared by both tools)
  docs/

    local-models.md              Model routing table, Ollama setup
    agents.md / hooks.md / commands.md / skills.md / circuit-breaker.md / codex.md
  install.sh         One-shot symlink wiring for Claude Code + OpenCode
  codex/             Codex reference install (AGENTS.md, config.toml, installer)
  CLAUDE.md          Project-level Claude Code instructions
  AGENTS.md          Project-level Codex instructions (installed in workspace root)
  memory.md          Session memory (active branch, pending work)
  mr-description-template.md    MR template for projects without one
```

### Three-layer cascade

```
Layer 1: ai_local/                Source of truth (this repo)
              ↓ symlinks (install.sh)
Layer 2: ~/.claude/               Claude Code global config
         ~/.config/opencode/      OpenCode global config
         ~/dev/src/CLAUDE.md      Generic dev standards (cascades to all repos)
         ~/dev/src/AGENTS.md      Codex project rules
         ~/dev/src/.codex/        Codex project MCP config
              ↓ overrides
Layer 3: <project>/CLAUDE.md      Project-specific rules
         <project>/AGENTS.md      Project-specific Codex/OpenCode rules
         <project>/.claude/       Project-specific settings, MCP servers
         <project>/.codex/        Project-specific Codex config
         <project>/openspec/      Project-specific specs and changes
```

### Agents (17)

All 17 agents are available in both Claude Code and OpenCode. In OpenCode each agent is pinned to a model tier via frontmatter — see [docs/local-models.md](docs/local-models.md) for the full routing table.

In the Codex reference setup, the same agent definitions are reused as **role contracts** and
source prompts rather than as a native Codex agent registry. See [docs/codex.md](docs/codex.md).

| Agent | Role | Model tier |
|-------|------|-----------|
| `@coder-python` | Python feature implementation (TDD) | Devstral 24B |
| `@coder-sql` | SQL / database implementation | Devstral 24B |
| `@coder-tdd` | TDD Red phase — writes failing tests only | Devstral 24B |
| `@coder-typescript` | TypeScript feature implementation (TDD) | Devstral 24B |
| `@architect` | Design review, interface specs, ADRs | Devstral 24B |
| `@data-analyst` | Data analysis, stats, visualisation | Devstral 24B |
| `@data-engineer` | Pipelines, dbt, Airflow, Spark | Devstral 24B |
| `@refactor` | Safe incremental refactoring (Python, TS, SQL) | Devstral 24B |
| `@jira-story` | Create structured Jira stories | Devstral 24B |
| `@product-owner` | Stories, INVEST, RICE, OKR | Devstral 24B |
| `@observability` | OTel instrumentation | Devstral 24B |
| `@sre` | Deployment safety, OTel, runbooks | Devstral 24B |
| `@tester` | Test strategy, coverage analysis | Devstral 24B |
| `@api` | API design, OpenAPI 3.1 | Devstral 24B |
| `@ai-developer` | LLM, RAG, MCP servers, evals | Devstral 24B |
| `@reviewer` | Adversarial 4-lens code review | Claude Sonnet |
| `@security` | Security review, OWASP, secrets audit | Claude Sonnet |

In Claude Code all agents are leaf agents — no agent spawns another, handoffs are human-triggered. In OpenCode, agents can be spawned autonomously by the orchestrator.

### Slash commands (11)

| Command | Purpose |
|---------|---------|
| `/commit` | Analyse diff, draft conventional commit message, validate, commit |
| `/pr` | Validate branch, push, fill MR template, create PR/MR |
| `/story` | INVEST check, draft user story with ACs, hand off to @jira-story |
| `/review` | 4-lens adversarial code review on current branch |
| `/spec` | Generate OpenAPI 3.1 path entry for a new endpoint |
| `/index` | Update docs index and memory after a work session |
| `/mine` | Manually ingest OpenSpec artifacts into MemPalace |
| `/opsx:propose` | OpenSpec — create proposal, design, tasks |
| `/opsx:explore` | OpenSpec — thinking mode, no implementation |
| `/opsx:apply` | OpenSpec — implement next unchecked task |
| `/opsx:archive` | OpenSpec — promote specs, archive the change |

Claude Code and OpenCode expose these as native slash commands. In the Codex reference setup,
the same markdown command definitions are reused as workflow playbooks rather than native Codex
slash commands.

### Claude Code hooks (15)

| Hook | Event | Purpose |
|------|-------|---------|
| `setup-init.sh` | SessionStart | Create dirs, chmod hooks, inject context |
| `skill-activation.sh` | UserPromptSubmit | Detect keywords, inject skill hints |
| `mode-guard.sh` | PreToolUse | Company/private path separation |
| `security-guard.sh` | PreToolUse | Block destructive commands, secret patterns |
| `no-ai-attribution.sh` | PreToolUse | Block AI attribution in commits/code |
| `observe.sh` | Pre/PostToolUse | Async audit trail to events.ndjson |
| `format-on-save.sh` | PostToolUse | Auto-format (ruff, black, prettier, sqlfluff) |
| `inline-quality.sh` | PostToolUse | Immediate feedback on code issues |
| `quality-gate.sh` | Stop | Final quality sweep before session ends |
| `transcript-backup.sh` | PreCompact | Save conversation before context compaction |
| `permission-autoapprove.sh` | PermissionRequest | GREEN/YELLOW/RED tier auto-approve |
| `notify.sh` | Notification | Desktop notification (macOS/Linux) |
| `mempalace-ingest.sh` | PostToolUse | Auto-ingest to MemPalace on write |
| `codegraph-sync.sh` | PostToolUse | Async codegraph sync on `git add` |
| `mempalace-wake-up.sh` | SessionStart | Initialise MemPalace connection |

### OpenCode plugins (10)

TypeScript plugins replace shell hooks. Loaded via `opencode.json`.

| Plugin | Event | Purpose |
|--------|-------|---------|
| `session-init.ts` | First tool call | mkdir, audit.log, MemPalace wake-up |
| `mode-guard.ts` | tool.execute.before | Company/private path separation |
| `no-ai-attribution.ts` | tool.execute.before | Block AI attribution in commits/code |
| `security-guard.ts` | tool.execute.before | Block destructive commands, secret patterns |
| `quality-gate.ts` | tool.execute.after | Blocking checks: print(), bare except, tsc, ESLint |
| `format-on-save.ts` | tool.execute.after | Auto-format on every write |
| `inline-quality.ts` | tool.execute.after | Advisory quality hints |
| `codegraph-sync.ts` | tool.execute.after | Async codegraph sync on `git add` |
| `observe.ts` | tool.execute.before/after | NDJSON event log, risk scoring 0–3 |
| `mempalace-ingest.ts` | session.compacting | Mine OpenSpec artifacts before compaction |

### Skills (43)

Organised by domain:

- **Python** (5): `/python`, `/python-developer`, `/python-patterns`, `/python-testing`, `/python-architect`
- **TypeScript** (4): `/typescript`, `/typescript-developer`, `/typescript-tdd`, `/typescript-architect`
- **Node.js** (3): `/nodejs`, `/nodejs-fastify`, `/nodejs-nestjs`
- **Data** (5): `/data-analyst`, `/data-engineer`, `/statistical-analysis`, `/time-series`, `/data-visualisation`
- **Platform** (4): `/sre`, `/observability`, `/ci-cd`, `/incident-response`
- **Database** (1): `/postgres-patterns`
- **API** (1): `/api-designer`
- **Security** (3): `/security-review`, `/compliance`, `/oauth`
- **AI** (1): `/ai-developer`
- **Process** (5): `/tdd-workflow`, `/verification-loop`, `/pr-review`, `/documentation`, `/presentation`
- **Product** (1): `/product-owner`
- **Specialist** (5): `/golang-patterns`, `/pdm-expert`, `/multi-tenancy`, `/web-design-guidelines`, `/mempalace`
- **OpenSpec** (4): `/openspec-propose`, `/openspec-apply-change`, `/openspec-explore`, `/openspec-archive-change`

---

## OpenSpec workflow

OpenSpec is the spec-driven development framework that ensures every non-trivial change has a paper trail: decision, design, tasks, commits, archive.

```
/opsx:explore     Think about a problem before committing to a solution
      |
/opsx:propose     Create proposal.md, design.md, specs/, tasks.md
      |
/opsx:apply       Implement tasks — picks the next unchecked task
      |
/opsx:archive     Promote specs, archive the change
```

Typical session:

```bash
mode company                              # or: mode private
cd ~/dev/src/my-project

# Think first
# Claude: /opsx:explore "should we use Redis or SQLite for caching?"

# Commit to a plan
# Claude: /opsx:propose "add SQLite-based query cache"
#   -> creates openspec/changes/sqlite-query-cache/{proposal,design,tasks}.md

# Implement
# Claude: /opsx:apply
#   -> reads tasks.md, picks next unchecked task, implements it, marks complete

# Archive when done
# Claude: /opsx:archive
```

---

## MemPalace — Persistent Cross-Session Memory

[MemPalace](https://github.com/milla-jovovich/mempalace) gives AI coding agents persistent memory across sessions. It stores decisions, discoveries, preferences, and session events in a structured "palace" backed by ChromaDB for semantic search. Everything stays on your machine — no cloud APIs.

Without MemPalace, every new session starts from zero context. With it, your agent recalls past decisions, design rationale, and session history.

### Quick start (complete first-time setup)

Run these commands in a **regular terminal** (not inside Claude Code/OpenCode — `mempalace init` requires interactive input):

```bash
# 1. Install
pip install mempalace

# 2. Initialise the palace for your project directory
#    Press Enter twice (accept entities, accept rooms)
mempalace init ~/dev/src/my-project

# 3. Copy the wing config template
cp ~/dev/src/ai_local/skills/mempalace/templates/wing_config.json ~/.mempalace/wing_config.json
# Edit ~/.mempalace/wing_config.json to match your domain areas

# 4. Mine your documents (first run downloads ~80MB embedding model)
mempalace mine ~/dev/src/my-project --wing my_wing

# 5. Wire the MCP server — Claude Code:
cat > ~/dev/src/my-project/.mcp.json << 'EOF'
{
  "mcpServers": {
    "mempalace": {
      "command": "python3",
      "args": ["-m", "mempalace.mcp_server"]
    }
  }
}
EOF

# 6. Verify — start Claude Code or OpenCode and ask:
#    "What's the status of the memory palace?"
```

### Detailed steps

#### Step 1: Install MemPalace

```bash
pip install mempalace
```

Requires Python 3.10+. Installs `chromadb` and `pyyaml` as dependencies.

If using pyenv:
```bash
~/.pyenv/versions/3.12.13/bin/pip install mempalace
```

#### Step 2: Initialise the palace

Run this in a **regular terminal** (not inside Claude Code/OpenCode — it requires interactive input):

```bash
mempalace init ~/dev/src/my-project
```

This does two things:
1. **Entity detection** — scans files for people and projects. Press Enter to accept defaults.
2. **Room detection** — proposes rooms based on directory structure. Press Enter to accept.

Creates:
- `~/.mempalace/` — global palace directory (ChromaDB embeddings, config, knowledge graph)
- `~/dev/src/my-project/mempalace.yaml` — per-directory room mapping
- `~/dev/src/my-project/entities.json` — detected entities

Repeat for each project directory you want to mine.

#### Step 3: Configure wings

Copy the wing config template:

```bash
cp ~/dev/src/ai_local/skills/mempalace/templates/wing_config.json ~/.mempalace/wing_config.json
```

Edit `~/.mempalace/wing_config.json` to match your domain areas. The template ships with:

| Wing | Contains |
|------|---------|
| `wing_cls_architecture` | MCP, SSO, auth, multi-tenancy, org-role |
| `wing_cls_platform` | Early-adopter, feedback loop, admin, tester-first |
| `wing_cls_resilience` | Resilience maturity, score methodology, ontology |
| `wing_cls_infra` | Postgres refactor, pgbouncer, observability |
| `wing_ai_dev` | Session diary, hook evolution, skill/agent meta-work |

#### Step 4: Mine your documents

Mine a directory that has been initialised (has `mempalace.yaml`):

```bash
mempalace mine ~/dev/src/my-project --wing my_wing
```

This reads all files, chunks them into drawers, and stores embeddings in ChromaDB. First run downloads the embedding model (~80MB).

Other mining modes:
```bash
mempalace mine ~/chats/ --mode convos                    # conversation exports
mempalace mine ~/chats/ --mode convos --extract general  # auto-classify into 5 memory types
```

#### Step 5: Configure the MCP server

Both Claude Code and OpenCode connect to MemPalace via MCP.

**Claude Code** — add to `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "mempalace": {
      "command": "python3",
      "args": ["-m", "mempalace.mcp_server"]
    }
  }
}
```

Or register via CLI:
```bash
claude mcp add mempalace -- python3 -m mempalace.mcp_server
```

**OpenCode** — add to `.opencode.json` in your project root:

```json
{
  "mcpServers": {
    "mempalace": {
      "type": "stdio",
      "command": "python3",
      "args": ["-m", "mempalace.mcp_server"]
    }
  }
}
```

If using pyenv, replace `"python3"` with the full path (e.g. `"~/.pyenv/versions/3.12.13/bin/python3"`).

#### Step 6: Verify

Start Claude Code or OpenCode and ask:

```
What's the status of the memory palace?
```

This triggers `mempalace_status`. You should see wing/room counts and drawer totals.

### Palace structure

```
~/.mempalace/                        Global palace directory
  palace/                            ChromaDB embeddings
  config.json                        Palace configuration
  wing_config.json                   Wing keyword mapping
  knowledge_graph.sqlite3            Temporal entity-relationship triples

WING  (domain area)
  +-- ROOM  (topic — usually a change name or module)
        +-- HALL  (memory type)
              |  hall_facts        — decisions, locked-in choices
              |  hall_events       — sessions, milestones
              |  hall_discoveries  — breakthroughs, insights
              |  hall_preferences  — approaches preferred
              |  hall_advice       — recommendations, solutions
              +-- DRAWER  (verbatim text chunk in ChromaDB)
```

### Hooks (Claude Code only)

| Hook | Event | Purpose |
|------|-------|---------|
| `mempalace-wake-up.sh` | SessionStart | Initialise MemPalace connection, load palace status |
| `mempalace-ingest.sh` | PostToolUse | Auto-ingest to MemPalace on write |

Included in `.claude/hooks/` and wired in `settings.json`. OpenCode lacks native hooks — use `mempalace mine` or `/mine` manually.

### MCP tools (19 total)

Key tools your agent calls automatically:

| Tool | Purpose |
|------|---------|
| `mempalace_search` | Semantic search across all drawers |
| `mempalace_kg_query` | Knowledge graph entity queries |
| `mempalace_kg_timeline` | Chronological story of an entity |
| `mempalace_diary_write` / `diary_read` | Agent diary entries |
| `mempalace_traverse` | Navigate wing > room > hall > drawer |
| `mempalace_list_wings` / `list_rooms` | Explore palace structure |
| `mempalace_status` | Palace health check |
| `mempalace_graph_stats` | Knowledge graph statistics |

### Populating via `/mine` (Claude Code)

```
/mine                           # mine all recently modified OpenSpec changes
/mine early-adopter-onboarding  # mine a specific change
```

---

## Company/Private mode circuit breaker

Hard separation between company and personal work, enforced by the `mode-guard.sh` hook at every tool call.

```bash
mode company      # Block private paths, allow company paths
mode private      # Block company paths, allow private paths
```

Customise the path patterns in `.claude/hooks/mode-guard.sh` to match your directory layout. The default assumes:

- **Company paths**: `ghorg/`, `docs_local/`, `chaostooling*/`, `tokens/`, `scripts/`
- **Private paths**: `pprojects/`, `api_projects/`
- **Neutral (both)**: `ai_local/`, `~/.ssh/`, `~/.claude/`, system paths

---

## Customisation

### Adding a project-specific CLAUDE.md

Each project can have its own `CLAUDE.md` that adds rules on top of the root one:

```bash
cd ~/dev/src/my-project
cat > CLAUDE.md << 'EOF'
# My Project — Claude Code Setup

## Stack
- Python 3.12, FastAPI, PostgreSQL
- Tests: pytest, >=95% coverage

## Rules
- All SQL must use parameterised queries
- No raw SQL outside store.py
EOF
```

### Adding project-specific settings

Create `.claude/settings.local.json` in your project for MCP servers and project-specific permissions:

```json
{
  "permissions": {
    "allow": ["Read", "Glob", "Grep", "Bash(git *)"]
  },
  "mcpServers": {
    "my-server": {
      "command": "node",
      "args": ["path/to/server.js"]
    }
  }
}
```

### Modifying hooks

Edit the hooks in `ai_local/.claude/hooks/`. Changes propagate to `~/.claude/hooks/` via symlink.

### Adding skills

Create a new directory under `ai_local/skills/<skill-name>/` with a `SKILL.md`. Add keyword mappings to `.claude/skill-rules.json` for auto-activation.

---

## Further reading

### Deep dives

- [docs/circuit-breaker.md](docs/circuit-breaker.md) — Company/private mode guard: path ownership, hook mechanics, shell function, test examples
- [docs/hooks.md](docs/hooks.md) — All 15 hooks + 9 OpenCode plugins: lifecycle events, execution order, exit codes, how to add new hooks
- [docs/agents.md](docs/agents.md) — All 17 agents: when to invoke, skills loaded, handoff patterns, collaboration flow
- [docs/skills.md](docs/skills.md) — All 43 skills: catalogue by domain, auto-activation, how to add new skills
- [docs/commands.md](docs/commands.md) — All 11 slash commands: what each does, examples, workflows
- [docs/local-models.md](docs/local-models.md) — Ollama setup, model routing table, per-agent model assignments, decision flowchart

### Reference

- [docs/ai_dev.md](docs/ai_dev.md) — Full architecture reference (deployment model, three-layer cascade, end-to-end lifecycle)
- [CLAUDE.md](CLAUDE.md) — The root Claude Code instructions file
- [install.sh](install.sh) — One-shot setup script for both tools
- [OpenSpec documentation](https://openspec.dev)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
- [OpenCode documentation](https://opencode.ai/docs/)
- [MemPalace](https://github.com/milla-jovovich/mempalace) — Persistent cross-session memory
