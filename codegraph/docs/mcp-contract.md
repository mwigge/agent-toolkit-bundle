# MCP Contract — CodeGraph

**Transport**: stdio
**Server command**: `codegraph serve --mcp`

The CodeGraph MCP server exposes 8 tools. All tools are read-only — the server
never writes to the project. Indexing is managed by the CLI separately.

---

## Tools

### `codegraph_search`

Find symbols by name or pattern.

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `query` | string | yes | Search term or pattern (supports partial match) |
| `kind` | string | no | Filter by symbol kind: `function`, `class`, `method`, `variable`, `interface`, `type`, `enum`, `module` |
| `limit` | number | no | Max results to return. Default: `20` |

**Example**:

```json
// Request
{ "query": "parseConfig", "kind": "function", "limit": 5 }

// Response
{
  "symbols": [
    {
      "id": "ts:src/config/parser.ts:parseConfig:42",
      "name": "parseConfig",
      "kind": "function",
      "file": "src/config/parser.ts",
      "line": 42,
      "signature": "function parseConfig(raw: unknown): Config",
      "docstring": "Parses and validates raw input into a Config object."
    }
  ],
  "total": 1
}
```

---

### `codegraph_context`

Build an AI-ready markdown context block for a task description. Searches for
relevant symbols and returns a structured summary the agent can include in its
reasoning.

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `task` | string | yes | Natural-language description of the task |
| `limit` | number | no | Max symbols to include. Default: `10` |

**Example**:

```json
// Request
{ "task": "add retry logic to the HTTP client" }

// Response
{
  "context": "## CodeGraph Context: add retry logic to the HTTP client\n\n### Relevant symbols\n\n**HttpClient** (class) — `src/http/client.ts:15`\n  Manages HTTP request lifecycle.\n\n**request** (method) — `src/http/client.ts:34`\n  `async request(opts: RequestOptions): Promise<Response>`\n  Core request dispatcher.\n\n**RetryPolicy** (interface) — `src/http/types.ts:8`\n  Defines retry behaviour contract.\n",
  "symbolCount": 3
}
```

---

### `codegraph_callers`

Find all symbols that call a given symbol (reverse call graph).

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `symbol` | string | yes | Symbol name or ID to look up callers for |
| `limit` | number | no | Max callers to return. Default: `20` |

**Example**:

```json
// Request
{ "symbol": "parseConfig" }

// Response
{
  "symbol": "parseConfig",
  "callers": [
    {
      "name": "loadAppConfig",
      "kind": "function",
      "file": "src/bootstrap.ts",
      "line": 18,
      "callLine": 22
    },
    {
      "name": "reloadConfig",
      "kind": "function",
      "file": "src/config/watcher.ts",
      "line": 45,
      "callLine": 51
    }
  ],
  "total": 2
}
```

---

### `codegraph_callees`

Find all symbols that a given symbol calls (forward call graph).

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `symbol` | string | yes | Symbol name or ID to look up callees for |
| `limit` | number | no | Max callees to return. Default: `20` |

**Example**:

```json
// Request
{ "symbol": "parseConfig" }

// Response
{
  "symbol": "parseConfig",
  "callees": [
    { "name": "validateSchema", "kind": "function", "file": "src/config/schema.ts", "line": 10 },
    { "name": "applyDefaults",  "kind": "function", "file": "src/config/defaults.ts", "line": 5 }
  ],
  "total": 2
}
```

---

### `codegraph_impact`

Blast-radius analysis: find all symbols transitively affected by changing a
given symbol or file.

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `symbol` | string | yes | Symbol name, ID, or file path |
| `depth` | number | no | Traversal depth. Default: `3` |

**Example**:

```json
// Request
{ "symbol": "src/config/parser.ts", "depth": 2 }

// Response
{
  "target": "src/config/parser.ts",
  "affectedSymbols": [
    { "name": "loadAppConfig", "file": "src/bootstrap.ts",       "distance": 1 },
    { "name": "reloadConfig",  "file": "src/config/watcher.ts",  "distance": 1 },
    { "name": "startApp",      "file": "src/index.ts",           "distance": 2 }
  ],
  "affectedFiles": ["src/bootstrap.ts", "src/config/watcher.ts", "src/index.ts"],
  "total": 3
}
```

---

### `codegraph_node`

Retrieve full details for a specific symbol node by ID.

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `id` | string | yes | Symbol ID (from search or callers results) |

**Example**:

```json
// Request
{ "id": "ts:src/config/parser.ts:parseConfig:42" }

// Response
{
  "id": "ts:src/config/parser.ts:parseConfig:42",
  "name": "parseConfig",
  "kind": "function",
  "file": "src/config/parser.ts",
  "line": 42,
  "endLine": 67,
  "signature": "function parseConfig(raw: unknown): Config",
  "docstring": "Parses and validates raw input into a Config object.\n@throws {ValidationError} if raw does not conform to the schema.",
  "language": "typescript",
  "callerCount": 2,
  "calleeCount": 2
}
```

---

### `codegraph_status`

Return index stats and server health.

**Parameters**: none

**Example**:

```json
// Response
{
  "version": "0.9.9",
  "project": "/home/user/my-project",
  "symbols": 1247,
  "files": 89,
  "languages": { "typescript": 72, "python": 17 },
  "lastIndexed": "2026-06-03T10:15:42Z",
  "status": "ready"
}
```

Status values: `ready` | `indexing` | `stale` (index exists but files changed
since last sync) | `uninitialized` (no `.codegraph/` directory).

---

### `codegraph_files`

Return the project file structure from the index, optionally filtered.

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `path` | string | no | Subdirectory path to scope the listing |
| `filter` | string | no | Glob pattern to filter files |

**Example**:

```json
// Request
{ "path": "src/config" }

// Response
{
  "files": [
    { "path": "src/config/defaults.ts", "symbols": 3, "language": "typescript" },
    { "path": "src/config/parser.ts",   "symbols": 5, "language": "typescript" },
    { "path": "src/config/schema.ts",   "symbols": 2, "language": "typescript" },
    { "path": "src/config/watcher.ts",  "symbols": 4, "language": "typescript" }
  ],
  "total": 4
}
```

---

## Error responses

All tools return a consistent error shape on failure:

```json
{
  "error": {
    "code": "INDEX_NOT_READY",
    "message": "No index found. Run `codegraph init -i` in the project root."
  }
}
```

| Code | Meaning |
|------|---------|
| `INDEX_NOT_READY` | No `.codegraph/` directory or index is uninitialized |
| `INDEX_STALE` | Index exists but is stale — run `codegraph sync` |
| `SYMBOL_NOT_FOUND` | The requested symbol ID does not exist in the index |
| `INVALID_PARAMS` | Missing or malformed parameters |
