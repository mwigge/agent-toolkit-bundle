# codegraph

Local-first code intelligence for AI agents, backed by an MCP server. This
sub-package ships the *integration layer* — docs, configuration reference, and
MCP contract — so you can wire `@colbymchenry/codegraph` into Claude Code,
OpenCode, or any MCP-compatible AI client.

## What it does

CodeGraph builds a semantic knowledge graph of your codebase using tree-sitter
AST parsing + SQLite/FTS5. It exposes the graph as an MCP server so AI agents
can answer structural questions without grepping:

- **Symbol search** — find any function, class, or variable by name or pattern
- **Call graphs** — who calls this function, what does it call
- **Blast radius** — which symbols are affected if I change this file
- **Context building** — AI-ready markdown context for a task or set of files
- **File structure** — project layout from the index

**CodeGraph answers "what is the code". MemPalace answers "why was it built
this way".** Used together they give an agent both structural and historical
context.

## Install summary

```bash
npm install -g @colbymchenry/codegraph@latest
codegraph --version
```

Full walkthrough: [`docs/install.md`](docs/install.md).

## Quick start

```bash
# 1. Install (once, globally)
npm install -g @colbymchenry/codegraph@latest

# 2. Initialize and index a project (once per repo)
cd /path/to/repo
codegraph init -i

# 3. Wire the MCP server into your agent config (once per agent)
# See docs/install.md for Claude Code / OpenCode / Codex recipes.

# 4. Keep the index fresh
codegraph sync          # after git pull or file changes
```

## Files

```
codegraph/
├── README.md                  this file
├── docs/
│   ├── install.md             end-to-end setup, platform-specific notes
│   ├── configuration.md       .codegraph/config.json reference
│   └── mcp-contract.md        MCP tool contract (8 tools)
└── config/
    └── config.json.example    example .codegraph/config.json
```

## MCP server

CodeGraph runs as a stdio MCP server:

```bash
codegraph serve --mcp
```

The server exposes 8 tools. See [`docs/mcp-contract.md`](docs/mcp-contract.md)
for the full contract with parameter schemas and example responses.

## CLI reference

```bash
codegraph init -i              # initialize + index current project
codegraph index                # full re-index
codegraph sync                 # incremental update (changed files only)
codegraph status               # show index stats
codegraph query <search>       # search symbols (--kind, --limit, --json)
codegraph context <task>       # build AI-ready context for a task
codegraph affected [files]     # find test files affected by changed sources
codegraph files                # show project file structure
codegraph serve --mcp          # start MCP server (stdio transport)
codegraph visualize            # open interactive graph in browser
```

## Configuration

Each project gets a `.codegraph/` directory with `config.json`. See
[`docs/configuration.md`](docs/configuration.md) for the full key reference.
See [`config/config.json.example`](config/config.json.example) for a working
starting point.

## Degrading mode

If the MCP server is not running, agents fall back to CLI tools or filesystem
searches. CodeGraph is never a hard dependency — a missing index must not break
your session.

## Security

- The index is local-only — no data leaves the machine.
- `.codegraph/` directories should be added to `.gitignore`.
- The SQLite database contains only symbol metadata extracted from source files,
  not the source files themselves.

## Related

- `mempalace` — the sibling sub-package for persistent cross-session memory.
  CodeGraph (structural) + MemPalace (semantic) cover the full context picture.
