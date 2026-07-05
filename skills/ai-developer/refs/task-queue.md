# Task Queue MCP Server (`task_queue.py`)

Complete reference for the persistent task queue and agent broadcast bus exposed as an MCP server. The SKILL.md body carries a one-line pointer to this file.

---

## Task Queue MCP Server (`task_queue.py`)

A persistent task queue and agent broadcast bus, exposed as an MCP server over stdio transport.
Lives at `~/.claude/skills/ai-developer/scripts/task_queue.py` and is registered globally in
`~/.claude/settings.json` as the `task-queue` MCP server.

### Registration (`~/.claude/settings.json`)

```json
"mcpServers": {
  "task-queue": {
    "command": "/Users/<you>/.pyenv/versions/3.12.13/bin/python3",
    "args": ["/Users/<you>/.claude/skills/ai-developer/scripts/task_queue.py"]
  }
}
```

No extra packages required for SQLite mode. For PostgreSQL mode, install `psycopg2-binary`.

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `TASK_QUEUE_DB` | `~/.agent_task_queue.db` | SQLite file path |
| `DATABASE_URL` | *(unset)* | If set, switches backend to PostgreSQL (`postgresql://user@host:port/db`) |

### Task State Machine

```
        task_post
            │
            ▼
         pending
            │  task_claim(agent_name)
            ▼
         claimed
            │  task_update(status="in_progress")
            ▼
        in_progress ──── task_update(status="failed") ──► failed
            │
            │  task_complete(result={...})
            ▼
           done
```

Any state can transition to `failed` via `task_update(status="failed")`.

### Tools Reference

#### Task Lifecycle

| Tool | Transition | Required params |
|------|-----------|-----------------|
| `task_post` | → `pending` | `title` |
| `task_claim` | `pending` → `claimed` | `task_id`, `agent_name` |
| `task_update` | `claimed` → `in_progress` **or** any → `failed` | `task_id`, `status` |
| `task_complete` | `in_progress` → `done` | `task_id` |
| `task_result` | read-only | `task_id` |
| `task_list` | read-only | *(all optional)* |

#### Agent Messaging

| Tool | Purpose | Required params |
|------|---------|-----------------|
| `agent_broadcast` | Post a message to a channel (default TTL 3600 s) | `from_agent`, `message` |
| `agent_inbox` | Read non-expired messages, newest first | `agent_name` |

### Usage Examples

**Create and work a task (orchestrator → subagent pattern)**:

```python
# Orchestrator posts a task
task = task_post(title="Build auth module", description="JWT-based auth for the API", wing="myproject")
task_id = task["id"]

# Subagent claims it
task_claim(task_id=task_id, agent_name="coder-python")

# Subagent starts work
task_update(task_id=task_id, status="in_progress", note="Starting TDD cycle")

# Subagent finishes
task_complete(task_id=task_id, result={"files_changed": ["src/auth.py"], "tests_pass": True})
```

**List all in-progress tasks for a specific agent**:

```python
tasks = task_list(status="in_progress", assigned_to="coder-python")
```

**Agent-to-agent broadcast**:

```python
# Sender
agent_broadcast(from_agent="opsx", message="Deploy gate open — proceed", channel="deploy", ttl_seconds=300)

# Receiver
messages = agent_inbox(agent_name="coder-rust", channel="deploy")
```

### Schema (SQLite / PostgreSQL)

```sql
-- Tasks table
CREATE TABLE tasks (
    id          TEXT PRIMARY KEY,        -- UUID
    title       TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    status      TEXT NOT NULL DEFAULT 'pending',  -- pending|claimed|in_progress|done|failed
    assigned_to TEXT,                    -- agent name
    wing        TEXT,                    -- optional namespace/domain label
    created_at  TEXT NOT NULL,           -- ISO 8601 UTC
    updated_at  TEXT NOT NULL,
    result      TEXT,                    -- JSON blob stored when done
    metadata    TEXT                     -- arbitrary JSON
);

-- Broadcasts table
CREATE TABLE broadcasts (
    id          TEXT PRIMARY KEY,
    from_agent  TEXT NOT NULL,
    message     TEXT NOT NULL,
    channel     TEXT NOT NULL DEFAULT '',
    created_at  TEXT NOT NULL,
    expires_at  TEXT                     -- ISO 8601 UTC; NULL = never expires
);
```

### Reinstall Checklist

If `task-queue` tools are missing from the tool list after a reinstall:

1. Confirm the script exists: `ls ~/.claude/skills/ai-developer/scripts/task_queue.py`
2. Confirm registration in `~/.claude/settings.json` under `"mcpServers"` → `"task-queue"`
3. Restart Claude / OpenCode to reload MCP servers
4. Verify by calling `task_list()` — an empty array `[]` is a healthy response
5. The SQLite DB is at `~/.agent_task_queue.db` by default — delete it to reset state
