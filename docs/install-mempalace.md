# Installing MemPalace

Persistent cross-session memory for Claude Code and OpenCode, backed by an external MCP server. This document covers the **recommended path**: installing the upstream [`milla-jovovich/mempalace`](https://github.com/milla-jovovich/mempalace) MCP server as the backend and wiring it up via the bundle's `mempalace/` sub-package. Both the upstream server and the bundle integration layer are opt-in; neither is installed by default.

If you already run a different MCP-compatible memory backend, skip to [Bring your own backend](#bring-your-own-backend).

---

## What is shipped, and where

The bundle does **not** ship an MCP server. It ships an **integration layer** under `mempalace/` — hooks, plugins, custom tools, a skill, a slash command, and the documented MCP tool contract — that targets any server implementing the contract in [`../mempalace/docs/mcp-contract.md`](../mempalace/docs/mcp-contract.md). The actual memory system (storage, search, knowledge graph, agent diary, taxonomy) lives in the backend you point it at.

Recommended backend: **[`milla-jovovich/mempalace`](https://github.com/milla-jovovich/mempalace)**. MIT-licensed. Python package. Ships its own Claude Code plugin via the Claude marketplace and a generic MCP server entry point for everything else. Every concept the bundle integration assumes — wings, rooms, halls, drawers, the 19 MCP tools, the palace directory at `~/.mempalace/palace/`, the `MEMPAL_DIR` auto-ingest convention — comes from upstream.

The division is deliberate: the bundle does not reinvent the memory system, and upstream does not ship OpenCode custom tools or a per-project `docs_local/openspec` scanning convention. The two layers compose.

---

## Quick start (recommended path)

### 1. Install the upstream mempalace server

```bash
pip install mempalace
```

This installs the `mempalace` CLI and the Python module `mempalace.mcp_server` (the MCP server entry point). Initialise a palace for a project:

```bash
mempalace init ~/my-project
```

The upstream server creates the palace storage at `~/.mempalace/palace/` (ChromaDB-backed) plus a handful of sibling files and directories:

| Path | Purpose |
|------|---------|
| `~/.mempalace/config.json` | Server-level configuration |
| `~/.mempalace/wing_config.json` | Wing / room / hall taxonomy |
| `~/.mempalace/identity.txt` | L0 identity layer (~50 tokens always loaded) |
| `~/.mempalace/palace/` | ChromaDB-backed palace storage |
| `~/.mempalace/agents/` | Per-agent diary directories |
| `~/.mempalace/knowledge_graph.db` | Knowledge-graph SQLite database |

See upstream README for the full reference. The bundle does not manage any of these files directly.

### 2. Wire the server into your agent runtime

For **Claude Code**, upstream ships its own Claude plugin via the marketplace:

```bash
claude plugin install --scope user mempalace
```

For everything else (OpenCode, Codex, Cursor, generic MCP clients), use the generic entry point:

```bash
claude mcp add mempalace -- python -m mempalace.mcp_server
```

This registers the upstream MCP server with Claude Code's MCP layer. OpenCode has its own MCP wiring — check OpenCode's docs for the equivalent command.

### 3. Install the bundle integration layer

From the cloned `agent-toolkit-bundle` directory:

```bash
./install.sh --components mempalace
```

Or, to add mempalace on top of an existing bundle install:

```bash
./install.sh --components agents,skills,hooks,plugins,tools,commands,mempalace
```

This drops symlinks at:

- `~/.agents/mempalace/` — the sub-package root (tool-neutral)
- `~/.claude/skills/mempalace/` → `mempalace/skill/` (Claude Code)
- `~/.claude/hooks/mempalace-*.sh` (Claude Code)
- `~/.claude/commands/mempalace-mine.md` (Claude Code)
- `~/.config/opencode/plugin/mempalace-ingest.ts` (OpenCode)
- `~/.config/opencode/tools/mempalace_ingest.ts`, `mempalace_query.ts` (OpenCode)
- `~/.config/opencode/command/mempalace-mine.md` (OpenCode)

Symlinks, not copies — `git pull` in the bundle repo propagates to every installed integration file instantly.

### 4. Configure auto-ingest via `MEMPAL_DIR`

The upstream server reads `MEMPAL_DIR` to discover which project directory it should watch during save hooks. Set it to the directory containing your project's planning / design / spec docs:

```bash
export MEMPAL_DIR=~/my-project/docs_local
```

Upstream's save hook (`mempal_save_hook.sh`) and precompact hook (`mempal_precompact_hook.sh`) use this variable to ingest files when Claude Code fires its `Stop` and `PreCompact` events. The bundle's own ingestion hooks (`mempalace-ingest.sh`, `mempalace-ingest.ts`) read the same variable and add a per-project `docs_local/openspec/` scanning convention on top.

Upstream and bundle hooks use **different filenames** and do not collide:

| Source | Claude Code hook filename | OpenCode plugin filename |
|--------|---------------------------|--------------------------|
| Upstream | `mempal_save_hook.sh`, `mempal_precompact_hook.sh` | (Claude marketplace plugin) |
| Bundle | `mempalace-ingest.sh`, `mempalace-wake-up.sh` | `mempalace-ingest.ts` |

Both can be wired up in the same `settings.json` / `opencode.json` without conflict.

### 5. Verify

Run a quick health check:

```bash
mempalace status
```

Inside a Claude Code or OpenCode session, call the upstream `mempalace_status` MCP tool, or invoke the bundle's `mempalace_query` custom tool (OpenCode) to confirm the server is reachable and the bundle integration sees it.

If everything is green, the `/mempalace-mine` slash command (shipped by the bundle) force-scans `$MEMPAL_DIR` and ingests any files that match the configured globs.

---

## What the bundle adds beyond upstream

The upstream project is a complete memory system on its own. The bundle sub-package adds three things that upstream does not ship:

1. **OpenCode custom tools** (`mempalace_ingest`, `mempalace_query`) — LLM-callable wrappers around the MCP tool surface, usable from any OpenCode agent without an MCP client configuration. Plain file reads and HTTP calls, no MCP wire format to worry about.
2. **An OpenCode plugin** (`mempalace-ingest.ts`) — an incremental ingestion hook that runs on `tool.execute.after` for Edit/Write calls, mirroring what upstream's Claude marketplace plugin does for Claude Code.
3. **A per-project `docs_local/openspec` scanning convention** — a unified convention that treats any `docs_local/openspec/*.md` file as first-class memory content, plus a single `/mempalace-mine` slash command that force-scans the configured paths and produces a human-readable summary of what was ingested.

None of these replace the upstream server. They compose on top of it. If you uninstall the bundle sub-package, the upstream server keeps working unchanged; if you uninstall upstream, the bundle sub-package degrades silently (see [Degrading mode](#degrading-mode)).

---

## Other MCP clients

If you use a non-Claude MCP client (OpenCode's MCP wiring, Cursor, Codex, a custom client), the recipe is:

1. `pip install mempalace` — same as the quick-start.
2. Start the upstream server directly via its module entry point:
   ```bash
   python -m mempalace.mcp_server
   ```
   Or register it with your client's MCP configuration using whatever command that client uses for registering MCP servers.
3. Point `MEMPALACE_MCP_URL` at the resulting server URL (typically `http://localhost:<port>` if the server exposes HTTP) so the bundle's integration layer can reach it:
   ```bash
   export MEMPALACE_MCP_URL="http://localhost:8765"
   export MEMPALACE_MCP_TOKEN="..."    # optional, only if auth is required
   ```
4. `./install.sh --components mempalace` to drop the bundle's integration symlinks into place.

The bundle integration treats the MCP server as opaque — it does not care whether the server is upstream's Python implementation, a custom Go reimplementation, a managed service, or a hosted endpoint. The only thing it cares about is that the server honours the MCP tool contract.

---

## Bring your own backend

If you want to run a different memory backend — one you wrote yourself, one you forked from upstream, or a fresh reimplementation — the contract is documented in full at [`../mempalace/docs/mcp-contract.md`](../mempalace/docs/mcp-contract.md). A server that implements the six-tool minimum-conformance subset is fully compatible with every bundled hook, plugin, and custom tool.

Minimum-conformance subset:

| Tool | Purpose |
|------|---------|
| `mempalace_status` | Health / readiness probe |
| `mempalace_add_drawer` | Insert a single memory record |
| `mempalace_check_duplicate` | Idempotency check before insert |
| `mempalace_search` | Full-text search |
| `mempalace_list_wings` | Enumerate wings |
| `mempalace_list_rooms` | Enumerate rooms under a wing |

Everything else in the contract (knowledge graph, navigation, agent diary, taxonomy) is optional and degrades gracefully if the backend does not expose it. See the contract doc for the full set of input/output schemas, error codes, and idempotency semantics.

To point the bundle at your own backend:

```bash
export MEMPALACE_MCP_URL="http://your-host:your-port"
export MEMPALACE_MCP_TOKEN="..."            # optional
export MEMPALACE_CONFIG=~/.agents/mempalace/config/mempalace.conf   # optional
```

The bundle's integration hooks / plugins / custom tools read these variables and route traffic accordingly. The upstream mempalace project is **not** required if you supply your own backend — the bundle treats it as the recommended default, not a hard dependency.

---

## Environment variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `MEMPAL_DIR` | upstream | Directory for the upstream server's auto-ingest during save hooks. Set to your project's planning / spec / design docs root. |
| `MEMPALACE_MCP_URL` | bundle | HTTP URL of the MCP server the bundle's integration layer should talk to. Default: unset (bundle integration noops if missing). |
| `MEMPALACE_MCP_TOKEN` | bundle | Optional bearer token. Never logged, never echoed. |
| `MEMPALACE_CONFIG` | bundle | Override path to the bundle's integration config file (default `~/.agents/mempalace/config/mempalace.conf`). |
| `MEMPALACE_CLI` | bundle | Override the CLI wrapper used by the bundle's shell hooks (default `mempalace`). |

All variables are optional. The bundle integration degrades silently if they are unset — it will not break your session.

---

## Degrading mode

If the MCP server is unreachable, every bundled hook, plugin, and custom tool logs a warning to stderr and exits 0. Mempalace is never a hard dependency; a broken backend must not break your Claude Code or OpenCode session. The skill surfaces the failure once per session and then no-ops every subsequent call.

If upstream's server is running but the bundle integration is misconfigured (e.g., wrong `MEMPALACE_MCP_URL`), you will see warnings in stderr on session start but the rest of the bundle continues to function. Fix the env var, reload the session.

---

## Troubleshooting

- **`MEMPALACE_MCP_URL not set`** in stderr — the env var is missing and the config file doesn't carry an `MCP_URL` line either. Fix one of them.
- **`palace unreachable at ...`** — the server is not listening on the configured URL or is refusing the request. Check upstream server logs and confirm reachability with `curl -v $MEMPALACE_MCP_URL/tools/call`.
- **`jq not found`** — install jq. The bundle's shell hooks use jq to build JSON payloads and do not fall back to raw string concatenation.
- **Nothing gets ingested** — check that `MEMPAL_DIR` (upstream) or the bundle's `SCAN_PATHS` config key points at a real directory containing files that match the configured ingest globs.
- **Upstream and bundle hook filename collision** — should not happen; upstream uses `mempal_*` prefixes, bundle uses `mempalace-*` prefixes. If a collision appears, check for a local rename somewhere in your `~/.claude/hooks/` or `~/.config/opencode/plugin/`.

---

## Security

- `MEMPALACE_MCP_TOKEN` is never logged and never echoed. Bundle hooks and plugins pass it via the `Authorization` header only.
- Bind the upstream server to localhost by default. A public endpoint is a footgun — the palace is a durable record of everything the agent has ever done, and exfiltration of that record is far worse than the convenience of remote access.
- Never write credentials, access tokens, or secrets into a drawer. Upstream does not scrub them for you; the bundle's hooks do not scrub them either. Redact before the ingestion call, not after.
- Version the taxonomy. Breaking changes to wing or hall names in `wing_config.json` will scramble retrieval. Migrate explicitly or never rename.

---

## Uninstall

### Bundle integration only (keep upstream server)

```bash
# Remove the symlinks the bundle installer created.
rm -f ~/.claude/skills/mempalace
rm -f ~/.claude/hooks/mempalace-ingest.sh ~/.claude/hooks/mempalace-wake-up.sh
rm -f ~/.claude/commands/mempalace-mine.md
rm -f ~/.config/opencode/plugin/mempalace-ingest.ts
rm -f ~/.config/opencode/tools/mempalace_ingest.ts ~/.config/opencode/tools/mempalace_query.ts
rm -f ~/.config/opencode/command/mempalace-mine.md
rm -rf ~/.agents/mempalace
```

The upstream server stays untouched.

### Everything (bundle integration + upstream server)

```bash
# Bundle integration symlinks (see above) +
pip uninstall mempalace
rm -rf ~/.mempalace
```

`rm -rf ~/.mempalace` deletes the palace, diary, knowledge graph, and config. There is no undo.

---

## See also

- Upstream project: <https://github.com/milla-jovovich/mempalace>
- [`../mempalace/README.md`](../mempalace/README.md) — the bundle sub-package overview.
- [`../mempalace/docs/install.md`](../mempalace/docs/install.md) — the sub-package's own install guide with the same information in more detail.
- [`../mempalace/docs/mcp-contract.md`](../mempalace/docs/mcp-contract.md) — the MCP tool contract the backend must implement.
- [`../mempalace/docs/ingestion.md`](../mempalace/docs/ingestion.md) — what gets ingested, how, when.
- [`../mempalace/docs/configuration.md`](../mempalace/docs/configuration.md) — config file reference and env vars.
- [`ecosystem.md`](ecosystem.md) — other tools that pair with the bundle.
- [Model Context Protocol specification](https://modelcontextprotocol.io/) — the wire protocol the server speaks.
