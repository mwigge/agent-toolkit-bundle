# MCP Tool Contract — MemPalace

This contract matches the [`milla-jovovich/mempalace`](https://github.com/milla-jovovich/mempalace)
upstream project (MIT-licensed). Any backend that implements this surface
is compatible with the bundled hooks, plugin, and custom tools. The
recommended default backend is upstream itself (`pip install mempalace`);
any MCP-compatible reimplementation that honours these schemas also works.

The contract is split into a **required** subset (six tools) and an
optional superset (the remaining thirteen). A server that implements only
the required subset is fully compatible with this bundle. The full set of
nineteen tools is organised into five categories, matching upstream's own
grouping:

- **Palace (read)** — status, enumeration, search, taxonomy lookup
- **Palace (write)** — insert and delete drawer records
- **Knowledge Graph** — graph-level add, query, invalidate, stats
- **Navigation** — traversal, tunnels, graph-wide structural stats
- **Agent Diary** — append-only free-form session notes

All tools accept JSON arguments and return JSON responses. Transport is
either HTTP POST at `$MCP_URL/tools/call` with a body of
`{"tool": "<name>", "arguments": {...}}`, or a CLI wrapper invoked as
`<cli> call <tool_name>` reading the arguments JSON on stdin and writing
the response JSON on stdout. Either transport is acceptable; the client
hooks pick whichever is available.

## Error model

Every tool may return, in addition to its tool-specific success fields:

```json
{
  "error": {
    "code": "not-found" | "duplicate" | "invalid-argument"
          | "unauthorised" | "backend-unavailable"
          | "rate-limited" | "internal",
    "message": "human-readable string"
  }
}
```

Clients inspect `.error.code` before touching other fields. Absence of
`error` implies success. HTTP status should be 200 for well-formed tool
invocations even when they return a semantic error — reserve 4xx/5xx for
transport-level failures.

## Minimum-conformance subset

A server that implements these six tools is fully compatible with the
bundled integration. Everything else is optional.

| Tool                       | Category       | Purpose                            |
|----------------------------|----------------|------------------------------------|
| `mempalace_status`         | Palace (read)  | Health / readiness                 |
| `mempalace_list_wings`     | Palace (read)  | Enumerate wings                    |
| `mempalace_list_rooms`     | Palace (read)  | Enumerate rooms inside a wing      |
| `mempalace_search`         | Palace (read)  | Full-text search across records    |
| `mempalace_check_duplicate`| Palace (read)  | Idempotency check before insert    |
| `mempalace_add_drawer`     | Palace (write) | Insert a memory record             |

All nineteen tools, grouped by category:

| Category         | Tool                         | Required? |
|------------------|------------------------------|-----------|
| Palace (read)    | `mempalace_status`           | yes       |
| Palace (read)    | `mempalace_list_wings`       | yes       |
| Palace (read)    | `mempalace_list_rooms`       | yes       |
| Palace (read)    | `mempalace_get_taxonomy`     | optional  |
| Palace (read)    | `mempalace_search`           | yes       |
| Palace (read)    | `mempalace_check_duplicate`  | yes       |
| Palace (read)    | `mempalace_get_aaak_spec`    | optional  |
| Palace (write)   | `mempalace_add_drawer`       | yes       |
| Palace (write)   | `mempalace_delete_drawer`    | optional  |
| Knowledge Graph  | `mempalace_kg_query`         | optional  |
| Knowledge Graph  | `mempalace_kg_add`           | optional  |
| Knowledge Graph  | `mempalace_kg_invalidate`    | optional  |
| Knowledge Graph  | `mempalace_kg_timeline`      | optional  |
| Knowledge Graph  | `mempalace_kg_stats`         | optional  |
| Navigation       | `mempalace_traverse`         | optional  |
| Navigation       | `mempalace_find_tunnels`     | optional  |
| Navigation       | `mempalace_graph_stats`      | optional  |
| Agent Diary      | `mempalace_diary_write`      | optional  |
| Agent Diary      | `mempalace_diary_read`       | optional  |

---

## Palace (read)

Read-only operations over the palace. Safe to retry, idempotent.

### `mempalace_status`

Health and readiness probe. Called once per session by the wake-up hook.

**Input** (no arguments required):
```ts
{}
```

**Output**:
```ts
{
  status: "ok" | "degraded" | "offline"
  version?: string
  backend?: string     // free-form label identifying the server implementation
}
```

**Idempotency**: trivially safe to retry. **Required**: yes.

---

### `mempalace_list_wings`

Enumerate every wing currently present in the palace.

**Input**: `{}`

**Output**:
```ts
{
  wings: Array<{
    name: string
    drawer_count: number
    updated_at: string
  }>
}
```

**Idempotency**: read-only. **Required**: yes.

---

### `mempalace_list_rooms`

Enumerate every room inside a named wing.

**Input**:
```ts
{
  wing: string
}
```

**Output**:
```ts
{
  wing: string
  rooms: Array<{
    name: string
    drawer_count: number
    updated_at: string
  }>
}
```

**Errors**: `not-found` (unknown wing), `invalid-argument`.
**Idempotency**: read-only. **Required**: yes.

---

### `mempalace_get_taxonomy` *(optional)*

Return the backend's internal taxonomy for a wing (how rooms and halls are
organised underneath it). Purely informational; the bundled hooks never
call this, but upstream exposes it for clients that want to introspect the
wing configuration before ingesting.

**Input**: `{ wing: string }`

**Output**:
```ts
{
  wing: string
  rooms: Array<{
    name: string
    halls: string[]
  }>
}
```

**Errors**: `not-found`, `invalid-argument`.
**Idempotency**: read-only.

---

### `mempalace_search`

Full-text search across all drawers.

**Input**:
```ts
{
  query: string
  limit?: number        // default 10, max 100 in the bundled tool
  wing?: string         // optional filter
}
```

**Output**:
```ts
{
  results: Array<{
    drawer_id: string
    wing: string
    room: string
    hall: string
    source_path: string
    score: number
    snippet: string     // <= 500 chars
  }>
  total: number         // total matches (may exceed results.length)
}
```

**Errors**: `invalid-argument` (empty query), `unauthorised`,
`backend-unavailable`, `rate-limited`, `internal`.

**Idempotency**: read-only. **Required**: yes.

---

### `mempalace_check_duplicate`

Cheap idempotency probe before a `mempalace_add_drawer` call.

**Input**:
```ts
{
  content_hash: string
  source_path?: string
}
```

**Output**:
```ts
{
  duplicate: boolean
  drawer_id?: string    // populated when duplicate is true
}
```

**Idempotency**: read-only, always safe. **Required**: yes.

---

### `mempalace_get_aaak_spec` *(optional)*

Return upstream's AAAK (dialect / compression) specification — the
description of how the server compresses L1 critical facts into a minimal
token budget. Purely informational; clients that want to know whether the
server is running in raw or compressed mode can inspect the response.
Upstream defaults to raw mode because AAAK currently regresses LongMemEval
vs raw.

**Input**: `{}`

**Output**:
```ts
{
  dialect: "raw" | "aaak"
  token_budget?: number
  spec_version?: string
  notes?: string
}
```

**Idempotency**: read-only.

---

## Palace (write)

Mutating operations on drawer records.

### `mempalace_add_drawer`

Insert a single memory record.

**Input**:
```ts
{
  source_path: string    // the path the record was derived from, as a hint
  content_hash: string   // hex SHA-256 of content, used as dedup key
  content: string        // the raw bytes (UTF-8)
  wing?: string          // optional server-side placement hint
  room?: string          // optional server-side placement hint
  hall?: string          // optional server-side placement hint
}
```

The bundled ingestion hooks never populate `wing`, `room`, or `hall`.
Classification is owned by the backend. Accept the hints if present, ignore
them otherwise.

**Output**:
```ts
{
  drawer_id: string
  wing: string
  room: string
  hall: string
  created_at: string    // ISO 8601
}
```

**Errors**: `duplicate` (content_hash already exists), `invalid-argument`,
`unauthorised`, `backend-unavailable`, `internal`.

**Idempotency**: the client is expected to call `mempalace_check_duplicate`
first. Direct retries after a successful insert MUST produce a `duplicate`
error, not a second record. **Required**: yes.

---

### `mempalace_delete_drawer` *(optional)*

Remove a single drawer record.

**Input**:
```ts
{ drawer_id: string }
```

**Output**:
```ts
{ deleted: boolean }
```

**Errors**: `not-found`, `unauthorised`. **Idempotency**: second delete
returns `{ deleted: false }`, not an error.

---

## Knowledge Graph

Optional knowledge-graph layer. Upstream stores edges in a separate SQLite
database (`~/.mempalace/knowledge_graph.db`) and exposes CRUD-plus-timeline
semantics. None of the bundled hooks call the knowledge graph directly;
the tools are here for clients that want to use it.

### `mempalace_kg_query` *(optional)*

**Input**:
```ts
{
  subject?: string
  predicate?: string
  object?: string
  limit?: number
}
```

**Output**:
```ts
{
  edges: Array<{
    edge_id: string
    subject: string
    predicate: string
    object: string
    created_at: string
    invalidated_at?: string
  }>
}
```

**Idempotency**: read-only.

---

### `mempalace_kg_add` *(optional)*

Add a knowledge-graph edge.

**Input**:
```ts
{
  subject: string
  predicate: string
  object: string
  metadata?: Record<string, unknown>
}
```

**Output**:
```ts
{ edge_id: string }
```

---

### `mempalace_kg_invalidate` *(optional)*

Mark a fact as no longer true without deleting its history.

**Input**: `{ edge_id: string, reason?: string }`
**Output**: `{ invalidated: boolean }`

---

### `mempalace_kg_timeline` *(optional)*

**Input**: `{ subject: string, limit?: number }`
**Output**: `{ events: Array<{ ts: string, kind: string, edge_id: string }> }`

---

### `mempalace_kg_stats` *(optional)*

**Input**: `{}`
**Output**: `{ edge_count: number, subject_count: number, predicate_count: number }`

---

## Navigation

Optional graph-level navigation primitives. Upstream implements these on
top of the palace storage; custom backends may skip the category entirely
and still be compatible.

### `mempalace_traverse` *(optional)*

Graph traversal with a hop limit.

**Input**:
```ts
{
  start: string        // drawer_id or wing name — backend decides
  hops: number         // max 5
  limit?: number
}
```

**Output**:
```ts
{
  nodes: Array<{ id: string, kind: "wing" | "room" | "drawer" }>
  edges: Array<{ from: string, to: string, kind: string }>
}
```

---

### `mempalace_find_tunnels` *(optional)*

Cross-wing shortcuts — drawers in one wing that reference drawers in
another wing. Semantics are backend-defined.

**Input**: `{ from_wing: string, limit?: number }`
**Output**: `{ tunnels: Array<{ from: string, to: string, weight: number }> }`

---

### `mempalace_graph_stats` *(optional)*

Palace-wide structural stats.

**Input**: `{}`
**Output**: `{ wing_count: number, room_count: number, drawer_count: number }`

---

## Agent Diary

Append-only free-form session notes, separate from the structured drawer
hierarchy. Upstream stores diary entries per agent under
`~/.mempalace/agents/<agent>/diary/`.

### `mempalace_diary_write` *(optional)*

**Input**: `{ text: string }`
**Output**: `{ id: string, ts: string }`

**Idempotency**: no dedup — multiple identical entries are legal.

---

### `mempalace_diary_read` *(optional)*

Read agent diary entries.

**Input**: `{ since?: string, limit?: number }`
**Output**: `{ entries: Array<{ id: string, ts: string, text: string }> }`

---

## Versioning

This contract is versioned by document. Breaking changes bump the
top-level version in the front matter of this file. A server and client
built against the same version of this document are compatible by
definition. The required subset is frozen — any future version will
maintain backwards compatibility for the six tools above.

The nineteen tool names above match [upstream](https://github.com/milla-jovovich/mempalace)
verbatim. If upstream adds a new tool, this contract grows to match; if
upstream renames an existing tool, both names are kept for at least one
release cycle before the old one is removed.
