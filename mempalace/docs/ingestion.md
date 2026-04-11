# Ingestion — How files get into the palace

The bundled hooks and plugins are **location-based**: they decide whether
to ingest a file based on where it lives on disk, not what it contains.
No keyword matching, no semantic classification, no heuristics.
Classification is owned entirely by the BYO MCP backend.

## What triggers ingestion

There are three trigger paths. Each ends up calling the same
`mempalace_add_drawer` MCP tool (after a `mempalace_check_duplicate`
probe).

### 1. Incremental — on every Edit/Write tool call

- **Claude Code**: the `PostToolUse` hook
  `mempalace-ingest.sh` reads the tool payload from stdin, extracts
  `tool_input.file_path`, and ingests that single file if it lives inside
  a configured scan root.
- **OpenCode**: the `tool.execute.after` event of
  `mempalace-ingest.ts` does the same check.

This is the path that keeps the palace fresh as you work. It only touches
files the tool pipeline just wrote.

### 2. Full scan — on demand

- **Claude Code**: `bash ~/.claude/hooks/mempalace-ingest.sh scan` (called
  by the `/mempalace-mine` slash command).
- **OpenCode**: the `mempalace_ingest` custom tool, called with no
  arguments.

Walks every directory in `SCAN_PATHS` + `EXTRA_PATHS`, plus any
`openspec/` subtrees discovered at depth 3 or shallower inside the
project. Every matching file is hashed and either skipped (duplicate) or
inserted.

### 3. Targeted scan — single path

- **OpenCode**: `mempalace_ingest(path="./subdir")` in a session.

Same walk as the full scan but scoped to the given directory via the
`EXTRA_PATHS` environment variable. Useful after adding a new notes dir
that you want to prime without touching your config file.

## What gets scanned

The `SCAN_PATHS` config key is a comma-separated list of directories,
interpreted relative to `$CLAUDE_PROJECT_DIR` (or cwd). Defaults:

```
docs_local,docs_local/openspec
```

Additional directories are added via `EXTRA_PATHS` (same syntax) or
discovered dynamically — any `openspec/` directory inside the project at
depth 3 or shallower is always scanned, regardless of config.

## What matches

The `INGEST_GLOBS` config key is a comma-separated list of `find -name`
patterns. Default:

```
*.md,*.yaml,*.yml
```

Only files matching one of those globs are considered. Binary files,
source code, and unknown extensions are ignored.

## Size and content limits

- Files larger than 1 MiB are skipped with a stderr log line. Memory
  records are meant to be short notes, not blobs.
- File contents are read as UTF-8. Non-UTF-8 bytes are not re-encoded —
  they reach the backend as whatever Node's `readFileSync(p, "utf8")` or
  bash's `jq --rawfile` emit for them.
- No per-file rate limit. High-volume scans are the backend's problem to
  rate-limit via the `rate-limited` error code.

## Idempotency

Every ingestion is gated by a `mempalace_check_duplicate` call with the
content's SHA-256. If the backend reports `{ "duplicate": true }`, the
insert is skipped and nothing else happens. The backend is therefore the
source of truth for "have I seen this content before".

The client does not maintain a local cache of seen hashes. This keeps the
client stateless but means the check-duplicate tool is called on every
scan, even for unchanged files. Backends should make it cheap.

## Classification — not done here

The hooks and plugins in this sub-package never send a `wing`, `room`, or
`hall` field to the backend. The argument is always:

```ts
{
  source_path: "<relative path from project root>",
  content_hash: "<hex sha256>",
  content: "<utf-8 file bytes>"
}
```

How the backend decides which wing or room to file the record under is
entirely its problem. One reasonable implementation is to read the
`source_path` and map path prefixes to wings (`docs_local/decisions/` →
the `decisions` wing, etc). Another is to run a local classifier over
`content`. A third is to put everything in a single catch-all wing and
rely on full-text search for retrieval. None of those decisions live in
this bundle.

## What is explicitly not ingested

- Files outside `SCAN_PATHS` / `EXTRA_PATHS` / discovered `openspec/`
  dirs.
- Files larger than 1 MiB.
- Files whose extension is not in `INGEST_GLOBS`.
- Hidden files and directories (`.git/`, `.venv/`, etc.) — the `find`
  walk does not pass `-name '.*'`, but hidden subdirs below a scan root
  are not excluded on purpose. If you want them skipped, add them to your
  scan root's own `.gitignore` and rely on `find` not traversing them,
  or keep them out of `SCAN_PATHS` in the first place.
- Files with no read permission — silently skipped.

## Failure mode

If the MCP server is unreachable mid-scan, every subsequent tool call in
that scan will silently fail and log a stderr line. The scan continues
through the remaining files. When the server comes back, the next scan
picks up where the previous one left off — `check_duplicate` short-circuits
the already-inserted subset.
