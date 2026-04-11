# Install — MemPalace

MemPalace is an opt-in sub-package of `agent-toolkit-bundle`. The default
install does not enable it. Follow the steps below to wire up the bundled
integration against an MCP server — recommended upstream first, then
alternatives.

---

## Quick start (recommended: upstream backend)

### 1. Install the upstream server

```bash
pip install mempalace
mempalace init ~/my-project
```

This installs the upstream [`milla-jovovich/mempalace`](https://github.com/milla-jovovich/mempalace)
Python package (MIT-licensed) and initialises a palace for the project at
`~/my-project`. Upstream creates:

| Path | Purpose |
|------|---------|
| `~/.mempalace/config.json` | Server-level configuration |
| `~/.mempalace/wing_config.json` | Wing / room / hall taxonomy |
| `~/.mempalace/identity.txt` | L0 identity layer (always loaded) |
| `~/.mempalace/palace/` | ChromaDB-backed palace storage |
| `~/.mempalace/agents/` | Per-agent diary directories |
| `~/.mempalace/knowledge_graph.db` | Knowledge-graph SQLite database |

### 2. Wire the server into your agent runtime

For **Claude Code**, upstream ships its own Claude plugin via the
marketplace:

```bash
claude plugin install --scope user mempalace
```

For any other MCP client (OpenCode, Cursor, Codex, etc.), register the
generic MCP server entry point:

```bash
claude mcp add mempalace -- python -m mempalace.mcp_server
```

### 3. Install the bundle integration layer

From the cloned `agent-toolkit-bundle` directory:

```bash
./install.sh --components mempalace
```

Or, to add mempalace on top of an existing install:

```bash
./install.sh --components agents,skills,hooks,plugins,tools,commands,mempalace
```

The installer creates symlinks into the tool-specific install roots. For
Claude Code this means `~/.claude/skills/mempalace` pointing at
`mempalace/skill/`, plus per-file symlinks in `~/.claude/hooks/` and
`~/.claude/commands/`. For OpenCode, per-file symlinks in
`~/.config/opencode/plugin/`, `~/.config/opencode/tools/`, and
`~/.config/opencode/command/`. The repo itself is the source of truth —
`git pull` propagates changes instantly.

### 4. Set `MEMPAL_DIR` for upstream auto-ingest

Upstream's save hook reads `MEMPAL_DIR` to know which project directory to
watch. Set it to your planning / spec / design docs root:

```bash
export MEMPAL_DIR=~/my-project/docs_local
```

The bundle integration reads the same variable and adds a per-project
`docs_local/openspec/` scanning convention on top. Upstream and bundle
hooks use different filename prefixes (`mempal_*` upstream, `mempalace-*`
bundle) and do not collide.

### 5. Verify

```bash
mempalace status
```

Inside a Claude Code or OpenCode session, call the upstream
`mempalace_status` MCP tool, or use the bundle's `mempalace_query` custom
tool (OpenCode) to confirm reachability. Run `/mempalace-mine` to force a
re-scan of the configured paths.

---

## Other MCP clients

If you use a non-Claude MCP client, the recipe is:

1. `pip install mempalace` — same as the quick-start.
2. Register the server with your client's MCP configuration:
   ```bash
   claude mcp add mempalace -- python -m mempalace.mcp_server
   ```
   Or start the server directly via `python -m mempalace.mcp_server` and
   wire it into your client's MCP layer using whatever registration
   command that client supports.
3. Point `MEMPALACE_MCP_URL` at the resulting server URL so the bundle's
   integration layer can reach it:
   ```bash
   export MEMPALACE_MCP_URL="http://localhost:8765"
   export MEMPALACE_MCP_TOKEN="..."       # optional, if auth is required
   ```
4. `./install.sh --components mempalace` to drop the integration symlinks.

The bundle integration treats the MCP server as opaque. It does not care
whether the server is upstream's Python implementation, a custom Go
reimplementation, a managed service, or a hosted endpoint — only that the
server honours the MCP tool contract in [`mcp-contract.md`](mcp-contract.md).

---

## Bring your own backend

If you have a backend that is not upstream — your own implementation, a
fork, a fresh reimplementation — point the bundle's integration layer at
it via `MEMPALACE_MCP_URL`:

```bash
export MEMPALACE_MCP_URL="http://your-host:your-port"
export MEMPALACE_MCP_TOKEN="..."       # optional
```

The contract is in [`mcp-contract.md`](mcp-contract.md). A backend that
implements the six-tool minimum-conformance subset (status, add_drawer,
check_duplicate, search, list_wings, list_rooms) is fully compatible with
every bundled hook, plugin, and custom tool in this sub-package.
Everything else in the contract is optional and degrades gracefully.

The upstream `milla-jovovich/mempalace` project is **not** required if you
supply your own backend. Upstream is the recommended default, not a hard
dependency.

---

## Wire up the Claude Code hooks (Claude Code only)

Edit `~/.claude/settings.json` and merge the following entries into the
existing `hooks` block:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/hooks/mempalace-wake-up.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/hooks/mempalace-ingest.sh" }
        ]
      }
    ]
  }
}
```

Restart your Claude Code session. The wake-up hook runs once at session
start and prints `mempalace-wake-up: palace connected (status=...)` to
stderr if everything is healthy.

If you are also using upstream's Claude marketplace plugin
(`claude plugin install --scope user mempalace`), both hook sets can run
side by side — upstream's `mempal_save_hook.sh` and `mempal_precompact_hook.sh`
use different filenames from the bundle's `mempalace-*.sh` and do not
collide.

---

## Wire up the OpenCode plugin and custom tools (OpenCode only)

OpenCode auto-loads plugins from `~/.config/opencode/plugin/` and custom
tools from `~/.config/opencode/tools/`. The installer drops symlinks in
both:

- `~/.config/opencode/plugin/mempalace-ingest.ts` → bundle plugin
- `~/.config/opencode/tools/mempalace_ingest.ts` → bundle custom tool
- `~/.config/opencode/tools/mempalace_query.ts` → bundle custom tool

Restart OpenCode to pick them up. The plugin registers two hooks
(`tool.execute.before` for a one-shot connectivity probe, `tool.execute.after`
for incremental ingestion on edit/write calls); the two custom tools are
LLM-callable wrappers around `mempalace_add_drawer` and `mempalace_search`.

---

## Environment variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `MEMPAL_DIR` | upstream | Directory for the upstream server's auto-ingest during save hooks. |
| `MEMPALACE_MCP_URL` | bundle | HTTP URL the bundle integration should talk to. |
| `MEMPALACE_MCP_TOKEN` | bundle | Optional bearer token. Never logged. |
| `MEMPALACE_CONFIG` | bundle | Override path to the bundle config file (default `~/.agents/mempalace/config/mempalace.conf`). |
| `MEMPALACE_CLI` | bundle | Override CLI wrapper used by the bundle's shell hooks (default `mempalace`). |

All are optional. The bundle integration degrades silently if unset — it
will not break your session.

---

## Troubleshooting

- **`MEMPALACE_MCP_URL not set`** in stderr — the env var is missing and
  the config file doesn't carry an `MCP_URL` line either. Fix one of them.
- **`palace unreachable at ...`** — the server is not listening on the
  configured URL, or is refusing the request. Check the server logs and
  confirm the URL is reachable with `curl -v $MEMPALACE_MCP_URL/tools/call`.
- **`jq not found`** — install jq. The bundle shell hooks use jq to build
  JSON payloads and cannot fall back to raw string concatenation safely.
- **Nothing gets ingested** — check that `MEMPAL_DIR` (upstream) or the
  bundle's `SCAN_PATHS` config key points at a real directory containing
  files that match `INGEST_GLOBS`. Run
  `bash ~/.claude/hooks/mempalace-ingest.sh scan` manually and watch
  stderr.
