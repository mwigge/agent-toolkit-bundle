# /mempalace-mine — Force a MemPalace re-ingestion

Walk every configured scan path and push matching files into the BYO
MemPalace MCP server. Use this when you have just finished a long editing
session and want to make sure the palace reflects the latest state of your
notes, or when you have added a new `docs_local/` directory that the
session-level hook has not yet picked up.

This command does not classify, summarise, or annotate. It is a dumb pipe
from disk to MCP server — the backend decides how to store what arrives.

## Steps

### 1. Confirm the palace is reachable

```bash
bash ~/.agents/mempalace/hooks/mempalace-wake-up.sh
```

If the wake-up hook reports the palace is offline, stop here. Fix
`MEMPALACE_MCP_URL` / `MEMPALACE_MCP_TOKEN` in your environment or config
file (`~/.agents/mempalace/config/mempalace.conf`) and re-run.

### 2. Run the full scan

```bash
bash ~/.agents/mempalace/hooks/mempalace-ingest.sh scan
```

The hook walks every path listed under `SCAN_PATHS` and `EXTRA_PATHS` in the
config file, plus any `openspec/` subdirectories discovered at depth 3 or
shallower inside the project. Matching files are hashed, checked against the
backend via `mempalace_check_duplicate`, and inserted via `mempalace_add_drawer`
only when new.

Every ingestion attempt is logged to stderr as a single line:

```
mempalace-ingest: ingested docs_local/notes/today.md
```

### 3. (Optional) Verify the inserts landed

Call the `mempalace_search` MCP tool for a term you know is in a file you
just ingested. The match should come back with `source_path` pointing at
the file you expected.

## Configuration reference

- Environment: `MEMPALACE_MCP_URL` (required), `MEMPALACE_MCP_TOKEN`
  (optional), `MEMPALACE_CONFIG` (overrides config path), `MEMPALACE_CLI`
  (overrides the CLI wrapper, defaults to `mempalace`).
- Config file: `~/.agents/mempalace/config/mempalace.conf`. Keys:
  `SCAN_PATHS`, `EXTRA_PATHS`, `INGEST_GLOBS`, `MCP_URL`, `MCP_TOKEN`.
  See `~/.agents/mempalace/docs/configuration.md` for the full reference.

## Exit behaviour

This command never fails the session. If the palace is unreachable, the
hook logs a warning to stderr and exits 0. A broken backend must not break
your editing flow.
