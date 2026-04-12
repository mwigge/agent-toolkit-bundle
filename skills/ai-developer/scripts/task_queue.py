#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
task_queue.py — MCP server for agent task coordination (stdio transport).

Implements a persistent task queue and broadcast inbox for multi-agent
workflows. Eight tools exposed via the Model Context Protocol:

  Task lifecycle:
    task_post      — create a new task (status: pending)
    task_claim     — agent claims a pending task (pending → claimed)
    task_update    — advance task state (claimed → in_progress, any → failed)
    task_complete  — mark done and store result (in_progress → done)
    task_result    — fetch full task record including result
    task_list      — list tasks with optional status/agent/wing filters

  Agent messaging:
    agent_broadcast — post a message to a channel with TTL
    agent_inbox     — read non-expired messages from a channel

Storage backends:
  - SQLite (default): zero dependencies, file at ~/.agent_task_queue.db
    Override path with TASK_QUEUE_DB env var.
  - PostgreSQL: set DATABASE_URL=postgresql://user@host:port/dbname

MCP protocol coverage:
  - initialize / notifications/initialized
  - tools/list
  - tools/call
  - ping

Transport: stdio (stdout = protocol channel, stderr = logs only).

Usage:
    python task_queue.py

Reference: https://spec.modelcontextprotocol.io/
"""

from __future__ import annotations

import json
import logging
import os
import sqlite3
import sys
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

# ── Logging — stderr only, stdout is the MCP wire ────────────────────────────

logging.basicConfig(
    stream=sys.stderr,
    format="%(asctime)s %(levelname)s [task_queue] %(message)s",
    level=logging.INFO,
)
log = logging.getLogger("task_queue")

# ── Server metadata ───────────────────────────────────────────────────────────

SERVER_NAME = "task-queue"
SERVER_VERSION = "1.0.0"
PROTOCOL_VERSION = "2024-11-05"

# ── JSON-RPC error codes ──────────────────────────────────────────────────────

PARSE_ERROR = -32700
INVALID_REQUEST = -32600
METHOD_NOT_FOUND = -32601
INVALID_PARAMS = -32602
INTERNAL_ERROR = -32603

# ── Database abstraction ──────────────────────────────────────────────────────

def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _use_postgres() -> bool:
    return bool(os.environ.get("DATABASE_URL"))


def _get_conn() -> Any:
    """Return a new database connection (caller must close)."""
    if _use_postgres():
        try:
            import psycopg2  # type: ignore[import]
        except ImportError as exc:
            raise RuntimeError(
                "DATABASE_URL is set but psycopg2 is not installed. "
                "Run: pip install psycopg2-binary"
            ) from exc
        return psycopg2.connect(os.environ["DATABASE_URL"])
    else:
        db_path = os.path.expanduser(
            os.environ.get("TASK_QUEUE_DB", "~/.agent_task_queue.db")
        )
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        # WAL mode for safe concurrent readers
        conn.execute("PRAGMA journal_mode=WAL")
        return conn


def _ph(n: int) -> str:
    """Return n comma-separated placeholders for the active backend."""
    p = "%s" if _use_postgres() else "?"
    return ", ".join([p] * n)


def _execute(
    sql: str,
    params: tuple[Any, ...] = (),
    *,
    fetch: bool = False,
) -> list[dict[str, Any]]:
    """
    Execute one SQL statement. Returns rows as dicts when fetch=True.
    Opens and closes its own connection (auto-commits on success).
    """
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(sql, params)
        rows: list[dict[str, Any]] = []
        if fetch:
            raw = cur.fetchall()
            if _use_postgres():
                cols = [d[0] for d in cur.description]
                rows = [dict(zip(cols, row)) for row in raw]
            else:
                rows = [dict(row) for row in raw]
        conn.commit()
        return rows
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


# ── Schema bootstrap ──────────────────────────────────────────────────────────

_SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
    id          TEXT PRIMARY KEY,
    title       TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    status      TEXT NOT NULL DEFAULT 'pending',
    assigned_to TEXT,
    wing        TEXT,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL,
    result      TEXT,
    metadata    TEXT
);

CREATE TABLE IF NOT EXISTS broadcasts (
    id          TEXT PRIMARY KEY,
    from_agent  TEXT NOT NULL,
    message     TEXT NOT NULL,
    channel     TEXT NOT NULL DEFAULT '',
    created_at  TEXT NOT NULL,
    expires_at  TEXT
);
"""


def _bootstrap_schema() -> None:
    """Create tables if they don't exist. Runs once at startup."""
    # SQLite supports multiple statements in executescript; Postgres needs them split.
    if _use_postgres():
        for stmt in _SCHEMA.strip().split(";"):
            stmt = stmt.strip()
            if stmt:
                _execute(stmt)
    else:
        conn = _get_conn()
        try:
            conn.executescript(_SCHEMA)
            conn.commit()
        finally:
            conn.close()
    log.info("Schema ready (backend: %s)", "postgresql" if _use_postgres() else "sqlite")


# ── Tool implementations ──────────────────────────────────────────────────────

def _task_post(args: dict[str, Any]) -> dict[str, Any]:
    title = args.get("title")
    if not title or not isinstance(title, str):
        raise ValueError("'title' must be a non-empty string")

    task_id = str(uuid.uuid4())
    now = _now()
    _execute(
        f"INSERT INTO tasks (id, title, description, status, assigned_to, wing, "
        f"created_at, updated_at, result, metadata) VALUES ({_ph(10)})",
        (
            task_id,
            title,
            args.get("description") or "",
            "pending",
            None,
            args.get("wing") or None,
            now,
            now,
            None,
            json.dumps(args.get("metadata") or {}),
        ),
    )
    log.info("task_post id=%s title=%r", task_id, title)
    rows = _execute(
        f"SELECT * FROM tasks WHERE id = {_ph(1)}", (task_id,), fetch=True
    )
    return rows[0]


def _task_claim(args: dict[str, Any]) -> dict[str, Any]:
    task_id = args.get("task_id")
    agent_name = args.get("agent_name")
    if not task_id or not isinstance(task_id, str):
        raise ValueError("'task_id' must be a non-empty string")
    if not agent_name or not isinstance(agent_name, str):
        raise ValueError("'agent_name' must be a non-empty string")

    rows = _execute(
        f"SELECT status FROM tasks WHERE id = {_ph(1)}", (task_id,), fetch=True
    )
    if not rows:
        raise LookupError(f"Task not found: {task_id!r}")
    status = rows[0]["status"]
    if status != "pending":
        raise ValueError(f"Task {task_id!r} is {status!r}, can only claim 'pending' tasks")

    now = _now()
    _execute(
        f"UPDATE tasks SET status = 'claimed', assigned_to = {_ph(1)}, updated_at = {_ph(1)} "
        f"WHERE id = {_ph(1)}",
        (agent_name, now, task_id),
    )
    log.info("task_claim id=%s agent=%r", task_id, agent_name)
    rows = _execute(
        f"SELECT * FROM tasks WHERE id = {_ph(1)}", (task_id,), fetch=True
    )
    return rows[0]


def _task_update(args: dict[str, Any]) -> dict[str, Any]:
    task_id = args.get("task_id")
    new_status = args.get("status")
    note = args.get("note") or ""

    if not task_id or not isinstance(task_id, str):
        raise ValueError("'task_id' must be a non-empty string")
    if new_status not in ("in_progress", "failed"):
        raise ValueError("'status' must be 'in_progress' or 'failed'")

    rows = _execute(
        f"SELECT status, description FROM tasks WHERE id = {_ph(1)}", (task_id,), fetch=True
    )
    if not rows:
        raise LookupError(f"Task not found: {task_id!r}")

    current_status = rows[0]["status"]
    if new_status == "in_progress" and current_status != "claimed":
        raise ValueError(
            f"Task {task_id!r} is {current_status!r}, must be 'claimed' to advance to 'in_progress'"
        )

    description = rows[0]["description"] or ""
    if note:
        description = f"{description}\n[note] {note}".strip()

    now = _now()
    _execute(
        f"UPDATE tasks SET status = {_ph(1)}, description = {_ph(1)}, updated_at = {_ph(1)} "
        f"WHERE id = {_ph(1)}",
        (new_status, description, now, task_id),
    )
    log.info("task_update id=%s status=%r", task_id, new_status)
    rows = _execute(
        f"SELECT * FROM tasks WHERE id = {_ph(1)}", (task_id,), fetch=True
    )
    return rows[0]


def _task_complete(args: dict[str, Any]) -> dict[str, Any]:
    task_id = args.get("task_id")
    if not task_id or not isinstance(task_id, str):
        raise ValueError("'task_id' must be a non-empty string")

    rows = _execute(
        f"SELECT status FROM tasks WHERE id = {_ph(1)}", (task_id,), fetch=True
    )
    if not rows:
        raise LookupError(f"Task not found: {task_id!r}")
    if rows[0]["status"] != "in_progress":
        raise ValueError(
            f"Task {task_id!r} is {rows[0]['status']!r}, must be 'in_progress' to complete"
        )

    result_json = json.dumps(args.get("result") or {})
    now = _now()
    _execute(
        f"UPDATE tasks SET status = 'done', result = {_ph(1)}, updated_at = {_ph(1)} "
        f"WHERE id = {_ph(1)}",
        (result_json, now, task_id),
    )
    log.info("task_complete id=%s", task_id)
    rows = _execute(
        f"SELECT * FROM tasks WHERE id = {_ph(1)}", (task_id,), fetch=True
    )
    return rows[0]


def _task_result(args: dict[str, Any]) -> dict[str, Any]:
    task_id = args.get("task_id")
    if not task_id or not isinstance(task_id, str):
        raise ValueError("'task_id' must be a non-empty string")

    rows = _execute(
        f"SELECT * FROM tasks WHERE id = {_ph(1)}", (task_id,), fetch=True
    )
    if not rows:
        raise LookupError(f"Task not found: {task_id!r}")
    return rows[0]


def _task_list(args: dict[str, Any]) -> list[dict[str, Any]]:
    limit = int(args.get("limit") or 50)
    limit = max(1, min(200, limit))

    conditions: list[str] = []
    params: list[Any] = []
    p = "%s" if _use_postgres() else "?"

    if status := args.get("status"):
        conditions.append(f"status = {p}")
        params.append(status)
    if assigned_to := args.get("assigned_to"):
        conditions.append(f"assigned_to = {p}")
        params.append(assigned_to)
    if wing := args.get("wing"):
        conditions.append(f"wing = {p}")
        params.append(wing)

    where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
    params.append(limit)

    return _execute(
        f"SELECT * FROM tasks {where} ORDER BY updated_at DESC LIMIT {p}",
        tuple(params),
        fetch=True,
    )


def _agent_broadcast(args: dict[str, Any]) -> dict[str, Any]:
    from_agent = args.get("from_agent")
    message = args.get("message")
    if not from_agent or not isinstance(from_agent, str):
        raise ValueError("'from_agent' must be a non-empty string")
    if not message or not isinstance(message, str):
        raise ValueError("'message' must be a non-empty string")

    ttl = int(args.get("ttl_seconds") or 3600)
    expires_at = (
        datetime.now(timezone.utc) + timedelta(seconds=ttl)
    ).isoformat()

    broadcast_id = str(uuid.uuid4())
    now = _now()
    _execute(
        f"INSERT INTO broadcasts (id, from_agent, message, channel, created_at, expires_at) "
        f"VALUES ({_ph(6)})",
        (
            broadcast_id,
            from_agent,
            message,
            args.get("channel") or "",
            now,
            expires_at,
        ),
    )
    log.info("agent_broadcast id=%s from=%r channel=%r", broadcast_id, from_agent, args.get("channel"))
    rows = _execute(
        f"SELECT * FROM broadcasts WHERE id = {_ph(1)}", (broadcast_id,), fetch=True
    )
    return rows[0]


def _agent_inbox(args: dict[str, Any]) -> list[dict[str, Any]]:
    if not args.get("agent_name"):
        raise ValueError("'agent_name' must be a non-empty string")

    limit = int(args.get("limit") or 20)
    limit = max(1, min(100, limit))
    now = _now()

    conditions = [f"(expires_at IS NULL OR expires_at > {_ph(1)})"]
    params: list[Any] = [now]
    p = "%s" if _use_postgres() else "?"

    if channel := args.get("channel"):
        conditions.append(f"channel = {p}")
        params.append(channel)

    where = f"WHERE {' AND '.join(conditions)}"
    params.append(limit)

    return _execute(
        f"SELECT * FROM broadcasts {where} ORDER BY created_at DESC LIMIT {p}",
        tuple(params),
        fetch=True,
    )


# ── MCP tool registry ─────────────────────────────────────────────────────────

TOOLS: list[dict[str, Any]] = [
    {
        "name": "task_post",
        "description": (
            "Create a new task in the queue with status 'pending'. "
            "Returns the full task record including the generated id."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "Short task title (required)."},
                "description": {"type": "string", "description": "Detailed description."},
                "wing": {"type": "string", "description": "Namespace or domain label."},
                "metadata": {"type": "object", "description": "Arbitrary JSON metadata."},
            },
            "required": ["title"],
            "additionalProperties": False,
        },
    },
    {
        "name": "task_claim",
        "description": (
            "Claim a pending task for an agent. Transitions status pending → claimed. "
            "Fails if the task is not found or not in 'pending' state."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "task_id": {"type": "string", "description": "Task UUID."},
                "agent_name": {"type": "string", "description": "Name of the claiming agent."},
            },
            "required": ["task_id", "agent_name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "task_update",
        "description": (
            "Update a claimed task's status. "
            "claimed → in_progress, or any → failed. "
            "An optional note is appended to the task description."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "task_id": {"type": "string", "description": "Task UUID."},
                "status": {
                    "type": "string",
                    "enum": ["in_progress", "failed"],
                    "description": "New status.",
                },
                "note": {"type": "string", "description": "Optional progress note."},
            },
            "required": ["task_id", "status"],
            "additionalProperties": False,
        },
    },
    {
        "name": "task_complete",
        "description": (
            "Mark an in-progress task as done and store the result. "
            "Transitions in_progress → done."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "task_id": {"type": "string", "description": "Task UUID."},
                "result": {"type": "object", "description": "Arbitrary result payload (JSON)."},
            },
            "required": ["task_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "task_result",
        "description": "Fetch the full task record including result and metadata.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "task_id": {"type": "string", "description": "Task UUID."},
            },
            "required": ["task_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "task_list",
        "description": (
            "List tasks, newest-updated first. "
            "All filters are optional and combinable."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "status": {
                    "type": "string",
                    "enum": ["pending", "claimed", "in_progress", "done", "failed"],
                    "description": "Filter by status.",
                },
                "assigned_to": {"type": "string", "description": "Filter by agent name."},
                "wing": {"type": "string", "description": "Filter by wing/namespace."},
                "limit": {
                    "type": "integer",
                    "description": "Max results (1–200, default 50).",
                    "default": 50,
                    "minimum": 1,
                    "maximum": 200,
                },
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "agent_broadcast",
        "description": (
            "Post a message to a channel. Messages expire after ttl_seconds (default 3600). "
            "Use channel to scope messages to a topic or team."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "from_agent": {"type": "string", "description": "Sending agent name."},
                "message": {"type": "string", "description": "Message content."},
                "channel": {"type": "string", "description": "Topic or channel name."},
                "ttl_seconds": {
                    "type": "integer",
                    "description": "Seconds until expiry (default 3600).",
                    "default": 3600,
                    "minimum": 1,
                },
            },
            "required": ["from_agent", "message"],
            "additionalProperties": False,
        },
    },
    {
        "name": "agent_inbox",
        "description": (
            "Read non-expired broadcast messages, newest first. "
            "Expired messages are silently excluded. "
            "Filter by channel to read topic-scoped messages."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "agent_name": {"type": "string", "description": "Requesting agent name."},
                "channel": {"type": "string", "description": "Filter by channel."},
                "limit": {
                    "type": "integer",
                    "description": "Max results (1–100, default 20).",
                    "default": 20,
                    "minimum": 1,
                    "maximum": 100,
                },
            },
            "required": ["agent_name"],
            "additionalProperties": False,
        },
    },
]

_TOOL_HANDLERS: dict[str, Any] = {
    "task_post": _task_post,
    "task_claim": _task_claim,
    "task_update": _task_update,
    "task_complete": _task_complete,
    "task_result": _task_result,
    "task_list": _task_list,
    "agent_broadcast": _agent_broadcast,
    "agent_inbox": _agent_inbox,
}

# ── MCP message handling ──────────────────────────────────────────────────────

def make_response(request_id: Any, result: Any) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def make_error(request_id: Any, code: int, message: str, data: Any = None) -> dict[str, Any]:
    error: dict[str, Any] = {"code": code, "message": message}
    if data is not None:
        error["data"] = data
    return {"jsonrpc": "2.0", "id": request_id, "error": error}


def handle_initialize(request_id: Any, params: dict[str, Any]) -> dict[str, Any]:
    client_name = params.get("clientInfo", {}).get("name", "unknown")
    log.info("Client connected: %s", client_name)
    return make_response(request_id, {
        "protocolVersion": PROTOCOL_VERSION,
        "capabilities": {"tools": {"listChanged": False}},
        "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
    })


def handle_tools_list(request_id: Any) -> dict[str, Any]:
    return make_response(request_id, {"tools": TOOLS})


def handle_tools_call(request_id: Any, params: dict[str, Any]) -> dict[str, Any]:
    tool_name = params.get("name")
    arguments: dict[str, Any] = params.get("arguments") or {}

    log.info("tools/call name=%s", tool_name)

    handler = _TOOL_HANDLERS.get(tool_name)  # type: ignore[arg-type]
    if handler is None:
        return make_response(request_id, {
            "content": [{"type": "text", "text": f"Unknown tool: {tool_name!r}"}],
            "isError": True,
        })

    try:
        result = handler(arguments)
    except (ValueError, LookupError) as exc:
        return make_response(request_id, {
            "content": [{"type": "text", "text": str(exc)}],
            "isError": True,
        })
    except (sqlite3.Error, Exception) as exc:
        log.exception("Tool %r raised an error", tool_name)
        return make_response(request_id, {
            "content": [{"type": "text", "text": f"Internal error: {exc}"}],
            "isError": True,
        })

    return make_response(request_id, {
        "content": [{"type": "text", "text": json.dumps(result, default=str)}],
        "isError": False,
    })


def dispatch(message: dict[str, Any]) -> dict[str, Any] | None:
    """Dispatch a JSON-RPC 2.0 message. Returns None for notifications."""
    request_id = message.get("id")
    method = message.get("method")
    params: dict[str, Any] = message.get("params") or {}

    if not method:
        return make_error(request_id, INVALID_REQUEST, "Missing 'method' field")

    # Notifications (no id) — acknowledge but do not respond
    if request_id is None:
        if method == "notifications/initialized":
            log.info("Client initialised — ready")
        else:
            log.debug("Unhandled notification: %s", method)
        return None

    if method == "initialize":
        return handle_initialize(request_id, params)
    if method == "ping":
        return make_response(request_id, {})
    if method == "tools/list":
        return handle_tools_list(request_id)
    if method == "tools/call":
        return handle_tools_call(request_id, params)

    log.warning("Unknown method: %s", method)
    return make_error(request_id, METHOD_NOT_FOUND, f"Method not found: {method!r}")


# ── Main loop ─────────────────────────────────────────────────────────────────

def _write_response(stdout: Any, response: dict[str, Any]) -> None:
    try:
        data = json.dumps(response, ensure_ascii=False, default=str) + "\n"
        stdout.write(data.encode("utf-8"))
        stdout.flush()
    except Exception as exc:
        log.error("Failed to write response: %s", exc)


def main() -> None:
    log.info("task_queue MCP server starting (stdio transport)")
    try:
        _bootstrap_schema()
    except Exception as exc:
        log.error("Schema bootstrap failed: %s — exiting", exc)
        sys.exit(1)

    stdin = sys.stdin.buffer
    stdout = sys.stdout.buffer

    while True:
        try:
            line = stdin.readline()
        except KeyboardInterrupt:
            log.info("Interrupted — shutting down")
            break

        if not line:
            log.info("stdin closed — shutting down")
            break

        line_str = line.decode("utf-8", errors="replace").strip()
        if not line_str:
            continue

        try:
            message = json.loads(line_str)
        except json.JSONDecodeError as exc:
            _write_response(stdout, make_error(None, PARSE_ERROR, f"Parse error: {exc}"))
            continue

        if not isinstance(message, dict):
            _write_response(stdout, make_error(None, INVALID_REQUEST, "Request must be a JSON object"))
            continue

        try:
            response = dispatch(message)
        except Exception as exc:  # noqa: BLE001
            log.exception("Internal error dispatching %s", message.get("method"))
            response = make_error(message.get("id"), INTERNAL_ERROR, "Internal server error", str(exc))

        if response is not None:
            _write_response(stdout, response)


if __name__ == "__main__":
    main()
