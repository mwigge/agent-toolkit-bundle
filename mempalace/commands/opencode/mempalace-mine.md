# /mempalace-mine — Force a MemPalace re-ingestion

Walk every configured scan path and push matching files into the BYO
MemPalace MCP server. Use this when you have just finished a long editing
session and want to make sure the palace reflects the latest state of your
notes, or when you have added a new `docs_local/` directory that the
session-level plugin has not yet picked up.

This command does not classify, summarise, or annotate. It is a dumb pipe
from disk to MCP server — the backend decides how to store what arrives.

## Steps

### 1. Call the `mempalace_ingest` custom tool

Invoke the OpenCode custom tool with no arguments to trigger a full scan of
every configured path:

```
mempalace_ingest()
```

Or scope the scan to a specific subtree by passing a path:

```
mempalace_ingest(path="./docs_local/notes")
```

The tool shells out to `mempalace-ingest.sh scan` under the hood. Paths
with `..` segments are rejected, oversize files (>1 MiB) are skipped, and
duplicate content (by SHA-256) is short-circuited via
`mempalace_check_duplicate`.

### 2. Verify with a search

Use the `mempalace_query` custom tool to confirm a known fragment came
through:

```
mempalace_query(query="the thing you just ingested", limit=5)
```

Look for a `source_path` field in the response that matches the file you
expected.

### 3. If the palace is unreachable

Run the shell wake-up hook directly to see the failure message:

```bash
bash ~/.agents/mempalace/hooks/mempalace-wake-up.sh
```

Fix `MEMPALACE_MCP_URL` / `MEMPALACE_MCP_TOKEN` in your shell profile or in
`~/.agents/mempalace/config/mempalace.conf` and retry.

## Configuration reference

- Environment: `MEMPALACE_MCP_URL` (required), `MEMPALACE_MCP_TOKEN`
  (optional), `MEMPALACE_CONFIG` (overrides config path), `MEMPALACE_CLI`
  (overrides the CLI wrapper, defaults to `mempalace`).
- Config file: `~/.agents/mempalace/config/mempalace.conf`. Keys:
  `SCAN_PATHS`, `EXTRA_PATHS`, `INGEST_GLOBS`, `MCP_URL`, `MCP_TOKEN`.
  See `~/.agents/mempalace/docs/configuration.md` for the full reference.

## Exit behaviour

The command never fails the session. If the MCP server is unreachable, the
custom tool returns an error message and the plugin logs the failure to
`.claude/logs/events.ndjson`. A broken backend must not break your
editing flow.
