# Pattern C — Tiered Agent Architecture

The production delegation model for autonomous coding work. The SKILL.md body carries a one-line pointer to this file.

---

## Pattern C — Tiered Agent Architecture (opsx → OpenHands → MemPalace)

Pattern C is the production delegation model for autonomous coding work. The orchestrator
(opsx / Claude) posts a task to the queue; OpenHands executes it in a full sandboxed
environment; results flow back via the task queue and persist in MemPalace.

### Architecture

```
YOU
 │  natural language
 ▼
opsx (Claude / OpenCode)              tier 1 — orchestrator
 │
 │  1. task_post(title, description, wing)
 │  2. delegate_to_openhands.sh --task-id <uuid>
 ▼
task_queue.db  ←──────────────────────── shared bus (SQLite, persists forever)
 │
 │  openhands_bridge.py claims task, marks in_progress
 ▼
OpenHands (http://localhost:3000)     tier 2 — executor
 │  CodeActAgent + devstral:24b
 │  full sandbox: bash, git, browser, test runner
 │
 │  on finish:
 ├── task_complete(result)            → opsx can read via task_result()
 └── mempalace_add_drawer(...)        → session knowledge persists
      wing=openhands, room=sessions
```

### Key Files

| File | Purpose |
|------|---------|
| `~/dev/src/local/openhands/bridge/openhands_bridge.py` | Bridge: submit task → OpenHands, poll, complete |
| `~/.config/opencode/scripts/delegate_to_openhands.sh` | opsx calls this to hand off a task |
| `~/dev/src/local/openhands/docker-compose.yaml` | OpenHands container config |
| `~/.agent_task_queue.db` | Shared task bus (same DB as task_queue MCP) |

### How opsx Delegates (the standard pattern)

```python
# 1. Post the task
task = task_post(
    title="Add rate limiting to the auth API",
    description="...",   # full spec goes here
    wing="myproject",
    metadata={"repo": "/opt/workspace/myrepo", "branch": "feat/rate-limit"}
)

# 2. Hand off to OpenHands (blocking — waits for completion)
# Run via Bash tool:
# bash ~/.config/opencode/scripts/delegate_to_openhands.sh --task-id <task["id"]>

# 3. Read the result (after delegate returns)
result = task_result(task_id=task["id"])
# result["status"] == "done"
# result["result"]["conversation_url"] → OpenHands UI link

# 4. Query what was built in MemPalace
# mempalace_search("rate limiting auth API myproject")
```

### OpenHands Bridge CLI

```bash
# Submit a pending task and block until done
python ~/dev/src/local/openhands/bridge/openhands_bridge.py submit <task_id>

# List pending/claimed tasks
python ~/dev/src/local/openhands/bridge/openhands_bridge.py list

# Poll a running conversation (manual recovery)
python ~/dev/src/local/openhands/bridge/openhands_bridge.py poll <conversation_id> [task_id]
```

### Pointing OpenHands at a Repo

Edit `~/dev/src/local/openhands/.env`:
```
WORKSPACE_HOST=${HOME}/dev/src/pprojects/myrepo
```
Then restart: `docker-compose -f ~/dev/src/local/openhands/docker-compose.yaml restart`

The repo will be mounted at `/opt/workspace` inside the sandbox — OpenHands can read,
edit, test, and commit to it directly.

### MemPalace Query Patterns

```
# Find all sessions for a project
mempalace_search("openhands session myproject")

# Find what built a specific feature
mempalace_search("rate limiting openhands")

# Find failed sessions
mempalace_search("STATUS: ERROR openhands")
```

Sessions are stored in wing=`openhands`, room=`sessions`.
Architecture docs are in wing=`openhands`, room=`architecture`.

### Environment Variables (bridge)

| Variable | Default | Purpose |
|----------|---------|---------|
| `OPENHANDS_URL` | `http://localhost:3000` | OpenHands REST API |
| `TASK_QUEUE_DB` | `~/.agent_task_queue.db` | Shared task bus |
| `MEMPALACE_URL` | `http://localhost:8765` | MemPalace HTTP API |
| `OPENHANDS_LLM_MODEL` | `ollama/devstral:24b` | LLM passed to OpenHands |
| `OPENHANDS_LLM_URL` | `http://localhost:11434` | LLM base URL |
| `OPENHANDS_LLM_KEY` | `ollama` | LLM API key |
