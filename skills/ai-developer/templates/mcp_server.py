#!/usr/bin/env python3
"""
mcp_server.py — Minimal MCP (Model Context Protocol) server using stdio transport.

Implements the JSON-RPC 2.0 message loop required by MCP with two example tools:
  1. search_knowledge_base — keyword search over an in-memory document store
  2. calculate_expression  — safe arithmetic expression evaluator

Transport: stdio (reads from stdin, writes to stdout, logs to stderr).

Protocol coverage:
  - initialize
  - initialized (notification)
  - tools/list
  - tools/call
  - ping
  - Proper JSON-RPC error responses for unknown methods and invalid params

Usage:
    python mcp_server.py

Reference: https://spec.modelcontextprotocol.io/
"""

from __future__ import annotations

import json
import logging
import math
import os
import re
import sys
from typing import Any

# Log to stderr ONLY — stdout is the MCP protocol channel.
logging.basicConfig(
    stream=sys.stderr,
    format="%(asctime)s %(levelname)s [mcp_server] %(message)s",
    level=logging.INFO,
)
log = logging.getLogger("mcp_server")

# ── Server metadata ───────────────────────────────────────────────────────────

SERVER_NAME = "example-mcp-server"
SERVER_VERSION = "1.0.0"
PROTOCOL_VERSION = "2024-11-05"

# ── JSON-RPC error codes ──────────────────────────────────────────────────────

PARSE_ERROR = -32700
INVALID_REQUEST = -32600
METHOD_NOT_FOUND = -32601
INVALID_PARAMS = -32602
INTERNAL_ERROR = -32603


# ── Tool definitions ──────────────────────────────────────────────────────────

TOOLS: list[dict[str, Any]] = [
    {
        "name": "search_knowledge_base",
        "description": (
            "Search an in-memory knowledge base for documents matching a keyword query. "
            "Returns up to `top_k` results with their titles and excerpt text. "
            "Use this tool when the user asks about topics that may be in the knowledge base."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "The search query. Case-insensitive keyword match.",
                },
                "top_k": {
                    "type": "integer",
                    "description": "Maximum number of results to return (1–10).",
                    "default": 3,
                    "minimum": 1,
                    "maximum": 10,
                },
            },
            "required": ["query"],
            "additionalProperties": False,
        },
    },
    {
        "name": "calculate_expression",
        "description": (
            "Safely evaluate a mathematical expression and return the numeric result. "
            "Supports: +, -, *, /, ** (power), // (floor division), % (modulo), "
            "and functions: abs, round, sqrt, floor, ceil, log, log10. "
            "Does NOT support variable assignment or arbitrary code. "
            "Use this tool for arithmetic, not for code execution."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "expression": {
                    "type": "string",
                    "description": "A mathematical expression, e.g. '2 ** 10' or 'sqrt(144)'.",
                },
                "precision": {
                    "type": "integer",
                    "description": "Decimal places to round the result to (0–15). Default: 6.",
                    "default": 6,
                    "minimum": 0,
                    "maximum": 15,
                },
            },
            "required": ["expression"],
            "additionalProperties": False,
        },
    },
]


# ── Knowledge base (replace with real retrieval in production) ────────────────

KNOWLEDGE_BASE: list[dict[str, str]] = [
    {
        "id": "kb-001",
        "title": "Idempotency in Distributed Systems",
        "text": (
            "An idempotent operation produces the same result regardless of how many times it is applied. "
            "In distributed systems, idempotency enables safe retries. Use idempotency keys to deduplicate "
            "requests. Examples: HTTP PUT, DELETE; Stripe payment intents."
        ),
    },
    {
        "id": "kb-002",
        "title": "Exactly-Once Semantics",
        "text": (
            "Exactly-once delivery guarantees that a message is processed exactly one time. "
            "Achieved with idempotent writes + transactional commits. "
            "Kafka supports exactly-once with transactions and idempotent producers."
        ),
    },
    {
        "id": "kb-003",
        "title": "Schema Evolution",
        "text": (
            "Schema evolution is changing a data schema over time while maintaining compatibility. "
            "Breaking changes: remove/rename fields, change types narrowly. "
            "Compatible changes: add optional fields with defaults, widen numeric types."
        ),
    },
    {
        "id": "kb-004",
        "title": "RAG Architecture",
        "text": (
            "Retrieval-Augmented Generation (RAG) combines document retrieval with LLM generation. "
            "Pipeline: chunk documents, embed chunks, store in vector DB, retrieve top-k for query, "
            "include context in LLM prompt. Improves factual grounding and reduces hallucination."
        ),
    },
]


def search_knowledge_base(query: str, top_k: int = 3) -> list[dict[str, str]]:
    """Simple keyword search over the in-memory knowledge base."""
    query_lower = query.lower()
    scored: list[tuple[int, dict[str, str]]] = []
    for doc in KNOWLEDGE_BASE:
        haystack = (doc["title"] + " " + doc["text"]).lower()
        # Count how many query words appear in the document
        words = re.split(r"\W+", query_lower)
        score = sum(1 for word in words if word and word in haystack)
        if score > 0:
            scored.append((score, doc))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [doc for _, doc in scored[:top_k]]


# ── Safe expression evaluator ─────────────────────────────────────────────────

_SAFE_NAMES: dict[str, Any] = {
    "abs": abs,
    "round": round,
    "sqrt": math.sqrt,
    "floor": math.floor,
    "ceil": math.ceil,
    "log": math.log,
    "log10": math.log10,
    "pi": math.pi,
    "e": math.e,
}

_ALLOWED_PATTERN = re.compile(
    r"^[\d\s\+\-\*\/\%\(\)\.\,_a-zA-Z]+$"
)


def safe_evaluate(expression: str, precision: int = 6) -> float:
    """
    Evaluate a mathematical expression in a restricted environment.
    Raises ValueError for disallowed expressions.
    """
    if not _ALLOWED_PATTERN.match(expression):
        raise ValueError(f"Expression contains disallowed characters: {expression!r}")

    # Block Python builtins and dunder access
    if re.search(r"__|\bimport\b|\bexec\b|\beval\b|\bopen\b|\bos\b", expression):
        raise ValueError("Expression contains disallowed keywords")

    try:
        result = eval(expression, {"__builtins__": {}}, _SAFE_NAMES)  # noqa: S307
    except Exception as exc:
        raise ValueError(f"Expression evaluation failed: {exc}") from exc

    if not isinstance(result, (int, float)):
        raise ValueError(f"Expression did not produce a number: {type(result)}")

    return round(float(result), precision)


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
        "capabilities": {
            "tools": {"listChanged": False},
        },
        "serverInfo": {
            "name": SERVER_NAME,
            "version": SERVER_VERSION,
        },
    })


def handle_tools_list(request_id: Any) -> dict[str, Any]:
    return make_response(request_id, {"tools": TOOLS})


def handle_tools_call(request_id: Any, params: dict[str, Any]) -> dict[str, Any]:
    tool_name = params.get("name")
    arguments: dict[str, Any] = params.get("arguments", {})

    log.info("Tool call: %s", tool_name)

    if tool_name == "search_knowledge_base":
        query = arguments.get("query")
        if not query or not isinstance(query, str):
            return make_error(request_id, INVALID_PARAMS, "'query' must be a non-empty string")

        top_k = int(arguments.get("top_k", 3))
        top_k = max(1, min(10, top_k))

        results = search_knowledge_base(query, top_k=top_k)

        if not results:
            text = f"No documents found matching query: {query!r}"
        else:
            lines = [f"Found {len(results)} result(s) for query: {query!r}\n"]
            for doc in results:
                lines.append(f"**{doc['title']}** (id: {doc['id']})")
                lines.append(doc["text"])
                lines.append("")
            text = "\n".join(lines)

        return make_response(request_id, {
            "content": [{"type": "text", "text": text}],
            "isError": False,
        })

    elif tool_name == "calculate_expression":
        expression = arguments.get("expression")
        if not expression or not isinstance(expression, str):
            return make_error(request_id, INVALID_PARAMS, "'expression' must be a non-empty string")

        precision = int(arguments.get("precision", 6))
        precision = max(0, min(15, precision))

        try:
            result = safe_evaluate(expression, precision=precision)
            text = f"{expression} = {result}"
        except ValueError as exc:
            return make_response(request_id, {
                "content": [{"type": "text", "text": f"Calculation error: {exc}"}],
                "isError": True,
            })

        return make_response(request_id, {
            "content": [{"type": "text", "text": text}],
            "isError": False,
        })

    else:
        return make_response(request_id, {
            "content": [{"type": "text", "text": f"Unknown tool: {tool_name!r}"}],
            "isError": True,
        })


def dispatch(message: dict[str, Any]) -> dict[str, Any] | None:
    """
    Dispatch a JSON-RPC message and return a response (or None for notifications).
    """
    request_id = message.get("id")
    method = message.get("method")
    params: dict[str, Any] = message.get("params") or {}

    if not method:
        return make_error(request_id, INVALID_REQUEST, "Missing 'method' field")

    # Notifications (no id) — handle but do not respond
    if request_id is None:
        if method == "notifications/initialized":
            log.info("Client initialised — ready")
        else:
            log.debug("Unhandled notification: %s", method)
        return None

    if method == "initialize":
        return handle_initialize(request_id, params)

    elif method == "ping":
        return make_response(request_id, {})

    elif method == "tools/list":
        return handle_tools_list(request_id)

    elif method == "tools/call":
        return handle_tools_call(request_id, params)

    else:
        log.warning("Unknown method: %s", method)
        return make_error(request_id, METHOD_NOT_FOUND, f"Method not found: {method!r}")


# ── Main loop ─────────────────────────────────────────────────────────────────

def main() -> None:
    log.info("MCP server starting (stdio transport)")

    # Use binary mode + manual line buffering for robust cross-platform behaviour
    stdin = sys.stdin.buffer
    stdout = sys.stdout.buffer

    while True:
        try:
            line = stdin.readline()
        except KeyboardInterrupt:
            log.info("Interrupted — shutting down")
            break

        if not line:
            # EOF — client disconnected
            log.info("stdin closed — shutting down")
            break

        line_str = line.decode("utf-8", errors="replace").strip()
        if not line_str:
            continue

        # Parse JSON-RPC message
        try:
            message = json.loads(line_str)
        except json.JSONDecodeError as exc:
            error_response = make_error(None, PARSE_ERROR, f"Parse error: {exc}")
            _write_response(stdout, error_response)
            continue

        if not isinstance(message, dict):
            error_response = make_error(None, INVALID_REQUEST, "Request must be a JSON object")
            _write_response(stdout, error_response)
            continue

        # Dispatch and respond
        try:
            response = dispatch(message)
        except Exception as exc:  # noqa: BLE001
            log.exception("Internal error dispatching %s", message.get("method"))
            response = make_error(
                message.get("id"),
                INTERNAL_ERROR,
                "Internal server error",
                str(exc),
            )

        if response is not None:
            _write_response(stdout, response)


def _write_response(stdout: Any, response: dict[str, Any]) -> None:
    """Serialise and write a JSON-RPC response to stdout, followed by a newline."""
    try:
        data = json.dumps(response, ensure_ascii=False) + "\n"
        stdout.write(data.encode("utf-8"))
        stdout.flush()
    except Exception as exc:
        log.error("Failed to write response: %s", exc)


if __name__ == "__main__":
    main()
