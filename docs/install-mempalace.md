# Installing MemPalace — Bring Your Own Server

This document describes how to integrate a persistent cross-session memory layer called **MemPalace** with Claude Code or OpenCode. It is an integration guide, not a shipped component.

---

## What MemPalace is

MemPalace is an organising metaphor for a persistent, structured memory that outlives a single agent session. The metaphor is a grand palace divided into **wings** (broad domain areas), each wing containing **rooms** (topics or projects), each room containing **halls** (memory categories such as decisions, incidents, patterns, or diary entries), each hall containing **drawers** (individual memory records). A separate **agent diary** captures free-form session notes that do not fit neatly into the structured halls.

The point of the metaphor is to force a decision about *where* a new piece of knowledge belongs before it is stored. Ad-hoc chat history is cheap to write and expensive to retrieve; a well-partitioned palace is the opposite. When the agent wakes up in a new session it can query the palace for prior decisions on the current topic without scanning an entire transcript.

The backend is an external [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) server. The agent calls tools over MCP; the server owns storage, search, and any knowledge-graph layer. Anything beyond the MCP wire is an implementation detail of whichever server you point the agent at.

---

## What this bundle does NOT provide

**Everything.** There is no MemPalace code anywhere in `agent-toolkit-bundle`. In particular, the bundle does not ship:

- An MCP server implementation.
- Storage primitives (database schema, filesystem layout, embedding index, nothing).
- Ingestion hooks (`PreToolUse`, `Stop`, `SessionStart`, or otherwise).
- An OpenCode plugin for automatic ingestion.
- A Claude Code skill with palace vocabulary or activation rules.
- A slash command for manual ingestion.
- A configuration file format, YAML schema, or wing taxonomy.
- Example wing names, room names, or hall names.

This is deliberate. An earlier revision of the bundle shipped an anonymised sub-package with hooks, a plugin, a skill, and a command. Every structural decision the sub-package surfaced — which wings to create, which keywords triggered which ingestion rule, which hall a given record belonged in — was either a direct reference to a specific project or a near-tautology of one. Anonymising it produced content that was either misleading (placeholders whose shape did not match any real palace) or still identifiable (semantic patterns that mapped cleanly back to the source). The clean fix was to ship nothing and document the contract instead.

---

## What you need to bring

To wire up a MemPalace integration of your own, you need four things:

1. **A running MCP server** that implements the tool contract in the next section. How you host it is your problem — localhost subprocess, containerised service, managed endpoint, whatever.
2. **Two environment variables** exported in the shell where Claude Code or OpenCode runs:
   - `MEMPALACE_MCP_URL` — where the MCP server is reachable. Required.
   - `MEMPALACE_MCP_TOKEN` — bearer token or equivalent, if your server requires authentication. Optional.
3. **Your own ingestion hook or plugin** that calls the MCP tools at the lifecycle points you care about. The hook sketch section below shows where these calls typically land; the code itself is up to you.
4. **A taxonomy decision** — what wings exist, what counts as a room vs a hall, what goes in the diary vs a structured drawer. This is the hardest part and the reason the bundle does not ship an example: every useful taxonomy is opinionated and every opinionated taxonomy leaks project detail.

---

## The MCP tool contract

Below is the tool surface the authors of this bundle found useful in practice. Your server may implement more; it need only implement the `required` subset for a minimal conformant integration. A reader who wants the smallest viable backend can stop after the six required tools and still have a usable palace.

| MCP tool                     | Purpose                                          | Conformance |
|------------------------------|--------------------------------------------------|-------------|
| `mempalace_status`           | Health / readiness probe                         | required    |
| `mempalace_add_drawer`       | Insert a single memory record                    | required    |
| `mempalace_check_duplicate`  | Idempotency check before insert                  | required    |
| `mempalace_search`           | Full-text search across halls                    | required    |
| `mempalace_list_wings`       | Enumerate wings                                   | required    |
| `mempalace_list_rooms`       | Enumerate rooms under a wing                      | required    |
| `mempalace_delete_drawer`    | Delete a single record                            | optional    |
| `mempalace_get_taxonomy`     | Retrieve taxonomy definition for a wing           | optional    |
| `mempalace_graph_stats`      | Palace-wide structural stats                      | optional    |
| `mempalace_diary_read`       | Read agent diary entries                          | optional    |
| `mempalace_diary_write`      | Write an agent diary entry                        | optional    |
| `mempalace_kg_add`           | Add a knowledge-graph edge                        | optional    |
| `mempalace_kg_query`         | Query KG by subject / predicate / object          | optional    |
| `mempalace_kg_invalidate`    | Mark a fact as invalidated without deleting       | optional    |
| `mempalace_kg_timeline`      | Timeline view of a subject                        | optional    |
| `mempalace_kg_stats`         | KG size / density stats                           | optional    |
| `mempalace_find_tunnels`     | Cross-wing shortcuts discovered by graph analysis | optional    |
| `mempalace_traverse`         | Graph traversal with a hop limit                  | optional    |

For each tool you implement, define:

- **Input schema** — parameter names, types, required-vs-optional markers.
- **Output schema** — return shape; pagination rules if the result set can be large.
- **Error codes** — at minimum: `not_found`, `duplicate`, `invalid_input`, `backend_unavailable`.
- **Idempotency semantics** — which calls are safe to retry blind, and which should call `check_duplicate` first.

The contract is intentionally open. Any backend — a local SQLite file, a managed vector database, a custom graph engine — is compatible if it exposes these schemas over MCP.

---

## Hook sketch

The following are pseudo-code fragments showing where a MemPalace ingestion hook typically calls which tool. They are **not working code**. They are oriented around three lifecycle events most agent runtimes expose: session start, post-tool-use, and stop.

### Session start

On session start, query the palace for any open diary entries or unresolved decisions related to the current working directory. Inject the result as context the agent can read.

```
on session_start:
    recent = mempalace_diary_read(limit=5, wing=infer_wing_from_cwd())
    emit_context("Recent diary entries:\n" + format(recent))
```

### Post tool use

After a write-type tool call, inspect the input for signals that a memory should be ingested — a new decision, a resolved bug, a pattern worth recording. The check-then-insert pattern avoids duplicates.

```
on post_tool_use(tool, input, output):
    if is_significant(tool, input, output):
        key = hash(normalise(input))
        if not mempalace_check_duplicate(key):
            mempalace_add_drawer(
                wing=classify_wing(input),
                room=classify_room(input),
                hall=classify_hall(input),
                content=summarise(input, output),
                metadata={"source": tool, "key": key}
            )
```

The `is_significant` and `classify_*` functions are where your taxonomy lives. They are also where most of the integration effort goes — a keyword-matching heuristic is fast to build and brittle in practice; an LLM classifier is slower and far more robust.

### Stop

On session stop, write a diary entry summarising the session. Free-form text, no taxonomy required.

```
on stop:
    summary = summarise_session(transcript)
    mempalace_diary_write(
        wing=primary_wing_for_session(),
        content=summary,
        metadata={"session_id": session_id}
    )
```

That's it. Three hooks, six tool calls, and a taxonomy function you design yourself.

---

## Wing design guidance

Wings are the top-level partition. Their names determine what future-you can and cannot find quickly. A few trade-offs:

- **Domain wings vs project wings.** Domain wings (the abstract area of knowledge: architecture, operations, data, whatever) survive project turnover; project wings do not. Domain wings age better. Project wings are easier to populate because classification is trivial — if you're in the project, the wing is fixed.
- **Team wings vs function wings.** Team wings are stable if your org is stable and painful if it isn't. Function wings (what was *done* rather than *who did it*) are more forgiving.
- **Coarse vs fine.** Five big wings retrieve badly when they're full — search is the only navigation that works. Fifty small wings retrieve well but require constant taxonomy upkeep. A reasonable middle is 8–15 wings, each holding around 5–20 rooms.
- **Halls are categories, not topics.** Use a small, finite set of halls — decisions, incidents, patterns, references, diary — that every wing shares. Do not let halls become a second layer of topic partitioning; that is what rooms are for.
- **Ingestion rules follow taxonomy, not the other way around.** Decide what you want to store and retrieve, then write the classifier to match. Writing a classifier first and letting the taxonomy emerge from it produces a palace nobody can reason about.

The bundle does not ship an example wing list. Every example the authors considered was either too generic to be useful (`general`, `projects`, `misc`) or too specific to share without leaking context.

---

## Security

- **Treat `MEMPALACE_MCP_TOKEN` like any other bearer token.** Never log it. Never echo it in a diary entry. Never include it in an error message that might land in a transcript backup.
- **Scope the MCP server to the narrowest network possible.** Localhost is best. A private network is acceptable. A public endpoint is a footgun waiting to discharge — the palace is a durable record of everything the agent has ever done, and exfiltration of that record is a far worse outcome than the convenience of remote access.
- **Audit what the ingestion hook sends.** A careless `add_drawer` call can serialise the full tool input, which can include file contents, database rows, or secrets inlined by the user. Strip or redact before the MCP call, not after.
- **Version the taxonomy.** Breaking changes to wing or hall names will scramble retrieval. Either migrate explicitly or never rename.

---

## Pointers

- The Model Context Protocol specification: https://modelcontextprotocol.io/
- A survey of MCP server implementations is a fast-moving target; the general-purpose directories linked from the spec site are the most current reference.
- If a public MemPalace implementation becomes available in future, this section will point at it. Until then, every working MemPalace is something somebody built themselves against the contract above.

That is the entire guide. If you are looking for a `palace.yaml` to drop into a directory and `it just works`, the answer is: that does not exist in this bundle, and was removed on purpose. Build your own or go without.
