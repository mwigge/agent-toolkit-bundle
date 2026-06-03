# Configuration — CodeGraph

CodeGraph is configured per project via `.codegraph/config.json`. The file is
created by `codegraph init` with sensible defaults and can be edited manually.

---

## File location

```
your-repo/
└── .codegraph/
    ├── config.json     ← configuration (edit this)
    └── codegraph.db    ← SQLite index (do not edit; add to .gitignore)
```

---

## Full reference

```json
{
  "version": 1,
  "languages": ["typescript", "python"],
  "exclude": [
    "node_modules/**",
    "dist/**",
    "build/**",
    ".venv/**",
    "__pycache__/**",
    "*.min.js",
    "coverage/**",
    ".codegraph/**"
  ],
  "maxFileSize": 1048576,
  "extractDocstrings": true,
  "trackCallSites": true
}
```

### `version`

Schema version. Always `1`. Do not change.

### `languages`

Array of languages to index. Supported values:

| Value | Extensions indexed |
|-------|--------------------|
| `typescript` | `.ts`, `.tsx` |
| `javascript` | `.js`, `.jsx`, `.mjs`, `.cjs` |
| `python` | `.py` |
| `rust` | `.rs` |
| `go` | `.go` |
| `java` | `.java` |
| `c` | `.c`, `.h` |
| `cpp` | `.cpp`, `.cc`, `.cxx`, `.hpp` |
| `ruby` | `.rb` |

Default: all languages detected during `codegraph init`.

### `exclude`

Array of glob patterns for paths to skip. Uses the same syntax as `.gitignore`.
Applied relative to the project root.

Common additions:

```json
"exclude": [
  "node_modules/**",
  "dist/**",
  "*.generated.ts",
  "vendor/**",
  "migrations/**"
]
```

### `maxFileSize`

Maximum file size in bytes to index. Files larger than this are skipped.
Default: `1048576` (1 MiB).

### `extractDocstrings`

When `true`, docstrings and JSDoc/TSDoc comments are extracted and stored with
symbols, making them searchable and available in context output.
Default: `true`.

### `trackCallSites`

When `true`, CodeGraph records where each function is called from (call sites),
enabling `codegraph_callers` and blast-radius analysis.
Default: `true`.

---

## Runtime behaviour

### Index location

The SQLite database lives at `.codegraph/codegraph.db`. It is local-only and
should be gitignored:

```bash
echo '.codegraph/' >> .gitignore
```

### Auto-sync

When the MCP server is running (`codegraph serve --mcp`), it uses native file
watchers to sync on save. When the server is not running, run `codegraph sync`
manually after pulling or editing files.

### Lock file

CodeGraph uses a lock file (`.codegraph/codegraph.lock`) to prevent concurrent
indexing. If a previous indexing run crashed and left a stale lock:

```bash
codegraph unlock
```

---

## Example: multi-language monorepo

```json
{
  "version": 1,
  "languages": ["typescript", "python", "go"],
  "exclude": [
    "node_modules/**",
    "dist/**",
    ".venv/**",
    "__pycache__/**",
    "vendor/**",
    "proto/**",
    "*.pb.go"
  ],
  "maxFileSize": 2097152,
  "extractDocstrings": true,
  "trackCallSites": true
}
```

## Example: TypeScript-only frontend

```json
{
  "version": 1,
  "languages": ["typescript"],
  "exclude": [
    "node_modules/**",
    "dist/**",
    "coverage/**",
    "*.stories.tsx",
    "*.test.ts",
    "*.spec.ts"
  ],
  "maxFileSize": 1048576,
  "extractDocstrings": true,
  "trackCallSites": true
}
```
