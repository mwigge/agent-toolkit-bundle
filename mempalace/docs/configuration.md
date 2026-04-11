# Configuration — MemPalace

Two layers, both optional. Environment variables override the config file.
The config file overrides the built-in defaults.

## Environment variables

| Variable              | Default                                                    | Purpose |
|-----------------------|------------------------------------------------------------|---------|
| `MEMPALACE_MCP_URL`   | *(none)*                                                   | Base URL of the BYO MCP server. HTTP POSTs go to `$MEMPALACE_MCP_URL/tools/call`. Required unless `MEMPALACE_CLI` is set to a wrapper binary. |
| `MEMPALACE_MCP_TOKEN` | *(none)*                                                   | Bearer token, sent as `Authorization: Bearer $TOKEN`. Leave unset if the server doesn't require auth. |
| `MEMPALACE_CONFIG`    | `~/.agents/mempalace/config/mempalace.conf`                | Override the config file path. Useful for running against multiple palaces without touching the default. |
| `MEMPALACE_CLI`       | `mempalace`                                                | Override the CLI wrapper binary. The hooks prefer the CLI over HTTP whenever it is on `$PATH`; the CLI contract is `<cli> call <tool_name>` reading JSON args on stdin. |

The hooks and plugins resolve config in this order, first writer wins:

1. Environment variables above.
2. The config file (next section).
3. Built-in defaults baked into the hook / plugin.

## Config file

Default path: `~/.agents/mempalace/config/mempalace.conf`. Override via
`$MEMPALACE_CONFIG`.

Format is `key=value`, one per line, with `#` for comments. Values may be
wrapped in single or double quotes; the quotes are stripped. The parser
is whitelist-only — any key not listed below is silently dropped. The
file is never `source`'d by the shell, so a tampered config cannot execute
arbitrary code.

### Recognised keys

| Key            | Type          | Default                          | Purpose |
|----------------|---------------|----------------------------------|---------|
| `SCAN_PATHS`   | CSV of paths  | `docs_local,docs_local/openspec` | Directories walked during ingestion. Each entry is absolute or relative to `$CLAUDE_PROJECT_DIR` (or cwd). Missing dirs are silently skipped. |
| `EXTRA_PATHS`  | CSV of paths  | *(empty)*                        | Additional dirs unioned with `SCAN_PATHS`. Use this when you want to add something without modifying the default list. |
| `INGEST_GLOBS` | CSV of globs  | `*.md,*.yaml,*.yml`              | `find -name` patterns. Only simple `*.ext` globs are supported. |
| `MCP_URL`      | URL           | *(empty)*                        | Same meaning as `MEMPALACE_MCP_URL`. Environment wins if both are set. |
| `MCP_TOKEN`    | bearer token  | *(empty)*                        | Same meaning as `MEMPALACE_MCP_TOKEN`. Environment wins if both are set. |

Example:

```
# ~/.agents/mempalace/config/mempalace.conf
SCAN_PATHS=docs_local,docs_local/openspec,notes
EXTRA_PATHS=
INGEST_GLOBS=*.md,*.yaml,*.yml,*.txt
MCP_URL=http://localhost:8765
MCP_TOKEN=
```

### Permissions

If `MCP_TOKEN` is populated, `chmod 0600` the file. The hooks never log
the token, but a leaked config file is still a leaked token.

## Adding a scan path

Three ways, in order of increasing permanence:

1. **One-off, one directory** (OpenCode only):
   ```
   mempalace_ingest(path="./some/dir")
   ```
2. **Per-shell, multiple runs**:
   ```bash
   EXTRA_PATHS=./some/dir bash ~/.claude/hooks/mempalace-ingest.sh scan
   ```
3. **Permanent**: edit `mempalace.conf` and add the directory to either
   `SCAN_PATHS` or `EXTRA_PATHS`. Both are unioned; the distinction is
   purely convention (SCAN_PATHS = baseline, EXTRA_PATHS = personal
   additions on top).

## Changing what extensions get ingested

Edit `INGEST_GLOBS`:

```
INGEST_GLOBS=*.md,*.yaml,*.yml,*.txt,*.org
```

The patterns are passed to `find -name`, so full glob features like `**`
or `{a,b}` are **not** supported. Only literal `*.ext` patterns work.

## Changing the MCP transport

By default, the hooks prefer the CLI wrapper (`$MEMPALACE_CLI`) over HTTP
when both are available. To force HTTP, unset `MEMPALACE_CLI` or point it
at a non-existent binary:

```bash
export MEMPALACE_CLI=/nonexistent
export MEMPALACE_MCP_URL=http://localhost:8765
```

To force the CLI and refuse to fall back to HTTP, leave `MEMPALACE_MCP_URL`
empty so HTTP has nowhere to dial.

## Changing the config path

```bash
export MEMPALACE_CONFIG=~/projects/palaces/work.conf
```

Useful when you want to run two palaces side by side (e.g. personal and
work) without mixing their scan paths or tokens.

## Where defaults come from

Built-in defaults live in the hook/plugin source, not in any auto-generated
file. If every config file is absent and every env var is unset, the hooks
fall back to:

- `SCAN_PATHS = docs_local, docs_local/openspec`
- `EXTRA_PATHS = (empty)`
- `INGEST_GLOBS = *.md, *.yaml, *.yml`
- `MCP_URL = (empty — causes the hook to no-op and log a warning)`
- `MCP_TOKEN = (empty)`
- `MEMPALACE_CLI = mempalace`

The empty `MCP_URL` default is deliberate. An unconfigured install is a
silent no-op, not a footgun that starts POSTing to a random local port.
