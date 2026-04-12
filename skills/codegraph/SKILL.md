---
name: codegraph
description: >
  Semantic code knowledge graph — symbol search, call graphs, blast radius, impact analysis.
  Uses tree-sitter AST parsing + SQLite/FTS5. Runs as MCP server exposing codegraph_search,
  codegraph_context, codegraph_callers, codegraph_callees, codegraph_impact, codegraph_node,
  codegraph_status, codegraph_files. Use when exploring unfamiliar code, tracing call chains,
  assessing change impact, or building context for code review.
  Trigger: /codegraph, "search symbols", "call graph", "what calls this", "impact analysis",
  "blast radius", "trace callers".
---

# CodeGraph Skill

Semantic code knowledge graph for structural code understanding. Complements MemPalace:
**CodeGraph answers "what is the code"**, **MemPalace answers "why was it built this way"**.

## When to Activate

- Exploring unfamiliar code — symbol lookup instead of grepping
- Tracing call chains — who calls this function, what does it call
- Change impact analysis — blast radius before modifying code
- Code review context — pull structural context for affected files
- Architecture overview — file structure and dependency mapping

## MCP Tools

The CodeGraph MCP server exposes these tools:

```
codegraph_search(query, kind?, limit?)     -- find symbols by name/pattern
codegraph_context(task)                     -- build AI-ready context for a task
codegraph_callers(symbol)                   -- who calls this symbol
codegraph_callees(symbol)                   -- what does this symbol call
codegraph_impact(symbol)                    -- blast radius analysis
codegraph_node(id)                          -- full details for a specific node
codegraph_status()                          -- index stats and health
codegraph_files(path?, filter?)             -- file structure overview
```

## CLI Commands

```bash
codegraph init -i              # initialize + index current project
codegraph index                # full re-index
codegraph sync                 # incremental update (changed files only)
codegraph status               # show index stats
codegraph query <search>       # search symbols (--kind, --limit, --json)
codegraph context <task>       # build context for a task
codegraph affected [files]     # find affected test files
codegraph files                # show file structure
```

## Project Setup

Each repo needs initialization once:

```bash
cd /path/to/repo
codegraph init -i
```

Creates `.codegraph/` directory with `codegraph.db` (SQLite) and `config.json`.

## Configuration

Edit `.codegraph/config.json` per project:

```json
{
  "version": 1,
  "languages": ["python", "typescript"],
  "exclude": ["node_modules/**", "dist/**", ".venv/**", "__pycache__/**"],
  "maxFileSize": 1048576,
  "extractDocstrings": true,
  "trackCallSites": true
}
```

## Combo Pattern: CodeGraph + MemPalace

| Question | Tool | Example |
|----------|------|---------|
| "What calls `run_experiment()`?" | CodeGraph | `codegraph_callers("run_experiment")` |
| "Why was `run_experiment` designed this way?" | MemPalace | `mempalace_search(query="run_experiment design decision")` |
| "What breaks if I change `store.py`?" | CodeGraph | `codegraph_impact("store.py")` |
| "What did we decide about the store refactor?" | MemPalace | `mempalace_search(query="store refactor", wing="wing_cls_infra")` |
| "Show me the auth middleware call chain" | CodeGraph | `codegraph_callees("auth_middleware")` |
| "Why did we choose this auth approach?" | MemPalace | `mempalace_search(query="auth middleware decision")` |

## Keeping the Index Fresh

- `codegraph sync` after pulling changes (incremental, fast)
- `codegraph index --force` if the index seems stale
- Native file watchers auto-sync on save when the MCP server is running

## Boundaries

- CodeGraph indexes structure, not semantics — it knows call graphs, not business logic
- For "why" questions, always use MemPalace
- Index size is proportional to codebase — large monorepos may take longer on first index
- `.codegraph/` directories should be gitignored
