---
name: mempalace
description: >
  Persistent cross-session memory backed by a Bring-Your-Own MCP-compatible server.
  Ingests content from configured paths (default the project's docs_local/ and any
  openspec/ subdirs). Exposes add, search, and list operations via the MCP tool
  contract. Use when a session needs to recall prior context, ingest new notes, or
  write a diary entry.
---

# MemPalace

Persistent cross-session memory for Claude Code. Backed by an external
MCP server that implements the tool contract documented in
`../docs/mcp-contract.md`. This bundle ships the integration layer only —
you bring the server.

## Concept

Think of memory as a palace:

- **wings** — top-level domain partitions
- **rooms** — topics inside a wing
- **halls** — memory types inside a room (e.g. notes, decisions, references)
- **drawers** — individual records inside a hall
- **diary** — free-form, append-only session notes, separate from the
  structured hierarchy

The bundled integration never chooses wing or room names on your behalf.
Classification is fully owned by the MCP backend. The hooks in this
sub-package are a dumb pipe: they walk configured directories on disk and
forward file contents to the server. How the server organises what arrives
is up to it.

## When to activate

Activate the skill when the user:

- asks what was decided about X in a previous session
- wants to record a decision, diary entry, or note for later recall
- wants to ingest a batch of files (e.g. after a long editing session)
- asks to list wings, rooms, or drawers — the read API surface
- runs `/mempalace-mine` to force a re-scan of the configured paths

Do **not** activate for one-off factual lookups that belong in web search
or the current session context. Mempalace is for persistent, cross-session
memory.

## Operations

The skill is a thin wrapper around the MCP tool contract. Every
user-facing operation maps to a single tool call:

| Operation                      | MCP tool                       | Required? |
|--------------------------------|--------------------------------|-----------|
| Health check                   | `mempalace_status`             | yes       |
| Insert a memory record         | `mempalace_add_drawer`         | yes       |
| Idempotency check before add   | `mempalace_check_duplicate`    | yes       |
| Full-text search               | `mempalace_search`             | yes       |
| Enumerate wings                | `mempalace_list_wings`         | yes       |
| Enumerate rooms inside a wing  | `mempalace_list_rooms`         | yes       |
| Delete a record                | `mempalace_delete_drawer`      | optional  |
| Knowledge-graph add / query    | `mempalace_kg_*`               | optional  |
| Graph traversal / tunnels      | `mempalace_traverse`, etc.     | optional  |
| Diary read / write             | `mempalace_diary_read/write`   | optional  |

See `../docs/mcp-contract.md` for full input and output schemas, error
codes, and idempotency semantics.

## Activation rules

1. Do not invoke any `mempalace_*` tool until a `mempalace_status` call
   succeeds at least once in the session. The wake-up hook handles the
   initial probe; the skill assumes it has run.
2. Always call `mempalace_check_duplicate` before `mempalace_add_drawer`
   unless the backend documents native upsert semantics.
3. Never write credentials, access tokens, or secrets into a drawer.
4. Diary entries are append-only — never try to edit a past entry; add a
   new one that supersedes it.

## Configuration

Scan paths, ingestion globs, and server URL are configured via environment
variables and an optional config file. Defaults are a per-project
`docs_local/` directory plus any `openspec/` subdirectories discovered
inside the project. Full reference: `../docs/configuration.md`.

## Degrading mode

If the MCP server is unreachable, the skill surfaces the failure once per
session and then no-ops every subsequent call. Mempalace is never a hard
dependency — a broken backend must not break the session.

## Reference implementation

The bundled skill describes the pattern; the recommended BYO backend
implementation is [`milla-jovovich/mempalace`](https://github.com/milla-jovovich/mempalace)
(MIT, `pip install mempalace`). Every structural concept referenced above —
wings, rooms, halls, drawers, the diary, the 19 MCP tools — comes from
upstream, and the bundled integration is written to target that shape
exactly. Any MCP-compatible backend that implements the contract in
`../docs/mcp-contract.md` will work; upstream is the default choice because
it is installable, maintained, and already implements every tool the skill
references.
