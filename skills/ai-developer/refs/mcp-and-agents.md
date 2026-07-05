# MCP Servers & Agent Tool Use

Full patterns for the Model Context Protocol (building servers, transports, tool schemas, error handling), agent tool-use loops, and comprehensive MCP server development (JSON-RPC compliance, resources/prompts, validation, rate limiting, testing). The SKILL.md body keeps the transport quick-reference table; this file holds the complete detail.

---

## MCP (Model Context Protocol)

### Building MCP Servers

MCP servers expose tools, resources, and prompts to LLM clients via a standard protocol.

```python
# Minimal structure — see templates/mcp_server.py for a complete example
{
    "jsonrpc": "2.0",
    "method": "tools/list",
    "id": 1
}
# Response:
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        "tools": [
            {
                "name": "search_documents",
                "description": "Search the knowledge base for relevant documents.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "query": {"type": "string", "description": "Search query"},
                        "top_k": {"type": "integer", "default": 5}
                    },
                    "required": ["query"]
                }
            }
        ]
    }
}
```

### Transport

| Transport | Use case |
|-----------|----------|
| `stdio` | Local tools, CLI integrations, Claude Desktop |
| `SSE` (Server-Sent Events) | Remote servers, web apps, multi-user |

For `stdio`: read JSON-RPC messages from stdin, write responses to stdout. Log only to stderr — stdout is the protocol channel.

### Tool Schema Rules

- All tool parameters must use JSON Schema with `description` for every property
- Mark required parameters in `"required": [...]`
- Use `"enum"` to constrain values where applicable
- Tool descriptions are read by the LLM — write them as you would a docstring: clear, specific, actionable

### Error Handling

```python
# MCP tool error response
{
    "jsonrpc": "2.0",
    "id": request_id,
    "result": {
        "content": [{"type": "text", "text": "Error: document not found for id=42"}],
        "isError": True
    }
}
# Never respond with jsonrpc "error" for tool failures — use isError in result
# Reserve jsonrpc "error" for protocol-level failures (invalid method, parse error)
```

---

## Agents and Tool Use

### Tool Definitions

```python
tools = [
    {
        "name": "get_weather",
        "description": "Get the current weather for a city. Returns temperature in Celsius and conditions.",
        "input_schema": {
            "type": "object",
            "properties": {
                "city": {"type": "string", "description": "City name, e.g. 'Paris'"},
                "units": {"type": "string", "enum": ["celsius", "fahrenheit"], "default": "celsius"}
            },
            "required": ["city"]
        }
    }
]

response = client.messages.create(
    model="claude-sonnet-4-5",
    max_tokens=1024,
    tools=tools,
    messages=[{"role": "user", "content": "What is the weather in Tokyo?"}],
)
```

### Parallel Tool Calls

Claude may request multiple tools simultaneously. Handle them all before returning:

```python
if response.stop_reason == "tool_use":
    tool_results = []
    for block in response.content:
        if block.type == "tool_use":
            result = execute_tool(block.name, block.input)
            tool_results.append({
                "type": "tool_result",
                "tool_use_id": block.id,
                "content": str(result),
            })
    # Continue the conversation with all results
    messages.append({"role": "assistant", "content": response.content})
    messages.append({"role": "user", "content": tool_results})
```

### Agentic Loop with Termination Conditions

```python
MAX_TURNS = 10  # Hard limit — never allow unbounded loops

for turn in range(MAX_TURNS):
    response = client.messages.create(...)

    if response.stop_reason == "end_turn":
        break  # Model is done

    if response.stop_reason == "tool_use":
        # Process tools and continue
        ...
    else:
        # Unexpected stop reason
        raise RuntimeError(f"Unexpected stop_reason: {response.stop_reason}")
else:
    raise RuntimeError(f"Agent exceeded {MAX_TURNS} turns without completing")
```

Always set a maximum turn limit. An agent without a termination condition is a runaway process.

---

## MCP Server Development

### JSON-RPC 2.0 Protocol Compliance

MCP servers must strictly follow the JSON-RPC 2.0 specification:

- Every request must have `jsonrpc: "2.0"`, `method`, and `id` (for requests, not notifications)
- Responses must include either `result` or `error`, never both
- Batch requests (JSON arrays) must be supported
- Notifications (requests without `id`) must not produce a response

```python
# Valid JSON-RPC 2.0 request/response cycle
request  = {"jsonrpc": "2.0", "method": "tools/call", "id": 1, "params": {...}}
response = {"jsonrpc": "2.0", "id": 1, "result": {...}}

# Protocol-level errors (invalid JSON, method not found)
error_response = {
    "jsonrpc": "2.0",
    "id": 1,
    "error": {"code": -32601, "message": "Method not found"}
}

# Tool-level errors (tool executed but failed) — use isError in result
tool_error = {
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        "content": [{"type": "text", "text": "File not found: config.yaml"}],
        "isError": True
    }
}
```

### Tool Definition Patterns

Every tool must have a clear name, descriptive text, and a JSON Schema for inputs:

```python
{
    "name": "query_metrics",
    "description": (
        "Query time-series metrics for a service. Returns datapoints "
        "for the specified metric name within the given time range. "
        "Use this when you need to check service health or performance."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "service": {
                "type": "string",
                "description": "Service name, e.g. 'payment-api'"
            },
            "metric": {
                "type": "string",
                "enum": ["latency_p99", "error_rate", "throughput"],
                "description": "Metric to query"
            },
            "window_minutes": {
                "type": "integer",
                "minimum": 1,
                "maximum": 1440,
                "default": 60,
                "description": "Lookback window in minutes"
            }
        },
        "required": ["service", "metric"]
    }
}
```

**Rules**:
- Tool names must be `snake_case`, descriptive, and action-oriented (verb_noun)
- Descriptions are read by the LLM to decide when to use the tool — write them as clear, specific docstrings
- Use `enum` to constrain values wherever the set of valid inputs is known
- Mark all mandatory parameters in `required`

### Resource and Prompt Primitives

Beyond tools, MCP servers can expose **resources** (read-only data) and **prompts** (reusable prompt templates):

```python
# Resource: exposes data the LLM can read
{
    "uri": "metrics://payment-api/health",
    "name": "Payment API Health",
    "description": "Current health status and key metrics for the payment API",
    "mimeType": "application/json"
}

# Prompt: reusable prompt template
{
    "name": "analyze_incident",
    "description": "Structured incident analysis prompt",
    "arguments": [
        {"name": "service", "description": "Affected service", "required": True},
        {"name": "symptoms", "description": "Observed symptoms", "required": True}
    ]
}
```

- Use resources for data that changes over time (dashboards, configs, status)
- Use prompts for standardised workflows the user triggers repeatedly

### Input Validation and Output Sanitisation

- Validate all tool inputs against the declared JSON Schema before execution
- Reject inputs that exceed expected size limits (file paths, query strings)
- Sanitise output before returning — strip credentials, internal paths, and PII
- Never return raw stack traces in tool results — log internally, return a user-safe message

### Rate Limiting and Audit Logging

- Implement per-client rate limits on tool calls (e.g., 60 calls/minute per tool)
- Log every tool invocation with: timestamp, tool name, truncated input, outcome, latency
- Never log full input/output if it may contain secrets or PII
- Use structured logging (JSON) for audit trails — never `print()`

### Testing MCP Servers

```python
import subprocess
import json

def test_mcp_tool_call():
    """Test MCP server via stdio transport."""
    request = json.dumps({
        "jsonrpc": "2.0",
        "method": "tools/call",
        "id": 1,
        "params": {
            "name": "query_metrics",
            "arguments": {"service": "payment-api", "metric": "latency_p99"}
        }
    }) + "\n"

    proc = subprocess.run(
        ["python", "-m", "my_mcp_server"],
        input=request,
        capture_output=True,
        text=True,
        timeout=10,
    )

    response = json.loads(proc.stdout.strip())
    assert response["jsonrpc"] == "2.0"
    assert response["id"] == 1
    assert "result" in response
    assert response["result"].get("isError") is not True
```

- Test via stdio transport for isolation — no network dependencies
- Test both success and error paths for every tool
- Test with invalid inputs to verify schema validation
- Use mock data sources to avoid external dependencies in tests
