# mempalace

Persistent cross-session memory for Claude Code and OpenCode, backed by a
Bring-Your-Own MCP-compatible server. This sub-package ships the *integration
layer* — hooks, plugins, custom tools, a skill, a slash command, and the
documented MCP tool contract — but does **not** ship the backend. You supply
your own MCP server that implements the contract in `docs/mcp-contract.md`.

## Upstream: milla-jovovich/mempalace

The recommended (but not required) BYO backend is the upstream project at
**<https://github.com/milla-jovovich/mempalace>**. MIT-licensed. Python
package, installable via `pip install mempalace`. Ships its own Claude Code
marketplace plugin (`claude plugin install --scope user mempalace`) and a
generic MCP server entry point (`claude mcp add mempalace -- python -m
mempalace.mcp_server`) for non-Claude clients.

Every concept this sub-package assumes — the palace → wings → rooms → halls →
drawers hierarchy, the 19 MCP tools, the palace path at `~/.mempalace/palace/`,
the `MEMPAL_DIR` auto-ingest environment variable — comes from upstream. This
sub-package is an **integration layer**, not a server. The actual memory
system (storage, search, knowledge graph, agent diary, taxonomy) lives in
whichever backend you point it at; upstream is the path of least resistance
for users who do not already run one.

Any MCP-compatible backend that implements the contract in
[`docs/mcp-contract.md`](docs/mcp-contract.md) works — upstream, a fork of
upstream, a fresh reimplementation, or a custom service.

## Concept

A "palace" is organised as wings → rooms → halls → drawers, plus a free-form
agent diary. The bundled integration is strictly **location-based**: it scans
configured directories and forwards matching files to the MCP server. It does
not parse content, detect topics, run keyword heuristics, or maintain its own
taxonomy. All classification happens inside the BYO backend; the hooks in
this sub-package are a dumb pipe.

## BYO MCP server

Nothing in this directory talks to a specific database or vector store. The
hooks and plugins call the MCP tool contract described in
[`docs/mcp-contract.md`](docs/mcp-contract.md). The minimum-conformance
subset is six tools (status, add, duplicate-check, search, list-wings,
list-rooms); everything else is optional. You can ship a working backend in
a few hundred lines against the minimum subset.

A handful of open-source MCP server implementations exist; this bundle
intentionally does not recommend one. Pick whichever you can audit.

## Install summary

Opt-in component, not installed by default:

```bash
./install.sh --components mempalace
```

Then set the required environment variable in your shell:

```bash
export MEMPALACE_MCP_URL="http://localhost:8765"
export MEMPALACE_MCP_TOKEN="..."   # optional, only if your backend requires auth
```

Full walkthrough: [`docs/install.md`](docs/install.md).

## Files

```
mempalace/
├── README.md                  this file
├── skill/SKILL.md             the mempalace skill (Claude Code Skills format)
├── hooks/
│   ├── mempalace-ingest.sh    PostToolUse hook: scan configured paths, ingest via MCP
│   └── mempalace-wake-up.sh   SessionStart hook: connectivity check
├── plugins/
│   └── mempalace-ingest.ts    OpenCode plugin equivalent of the shell hooks
├── tools/
│   ├── mempalace_ingest.ts    OpenCode custom tool (LLM-callable ingestion trigger)
│   └── mempalace_query.ts     OpenCode custom tool (LLM-callable search)
├── commands/
│   ├── claude/mempalace-mine.md     /mempalace-mine slash command (Claude Code)
│   └── opencode/mempalace-mine.md   /mempalace-mine slash command (OpenCode)
├── config/
│   └── mempalace.conf.example       example config file (key=value only)
└── docs/
    ├── install.md             end-to-end setup
    ├── mcp-contract.md        MCP tool contract the backend must implement
    ├── ingestion.md           what gets ingested, how, when
    └── configuration.md       config file reference + env vars
```

## Configuration

Two layers, both optional:

1. **Environment variables** (runtime) —
   `MEMPALACE_MCP_URL`, `MEMPALACE_MCP_TOKEN`, `MEMPALACE_CONFIG`, `MEMPALACE_CLI`.
2. **Config file** (static) —
   `~/.agents/mempalace/config/mempalace.conf` (overridable via `$MEMPALACE_CONFIG`).
   Uses the same narrow key=value parser pattern as `agent-circuit-breaker` —
   only whitelisted keys are recognised, everything else ignored. A tampered
   config cannot execute arbitrary shell.

See [`docs/configuration.md`](docs/configuration.md) for the full key reference.

## Degrading mode

If the MCP server is unreachable, every bundled hook and tool logs a warning
to stderr and exits 0. Mempalace is never a hard dependency; a broken backend
must not break your Claude Code / OpenCode session.

## Not installed by the default `install.sh`

This sub-package is opt-in. The bundle's default install deliberately skips
mempalace because it pulls in an external dependency (the MCP server) that
most users will not have running. Add `--components mempalace` to opt in.

## Security

- `MEMPALACE_MCP_TOKEN` is never logged and never echoed. Hooks and plugins
  pass it via the `Authorization` header only.
- The config-file parser is key=value only, with a whitelist of recognised
  keys — it does not `source` the file.
- The custom OpenCode tools use `execFileSync` with argv arrays, never
  shell-interpolated strings.

## Related

- `agent-circuit-breaker` — the sibling repo that ships `mode-guard`, which
  this sub-package mirrors in tone and shell style.
