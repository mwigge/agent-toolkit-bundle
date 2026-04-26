# OTel Agent Tracing — Configuration Guide

**Version**: 1.0 | **Updated**: 2026-04-17

Agent sessions in Claude Code and OpenCode emit OpenTelemetry spans and metrics via the `observe` hook/plugin. This document explains how to configure the endpoint and verify connectivity.

---

## How it works

### Claude Code (observe.sh)

Uses `otel-cli` (Go binary, installed via Homebrew):
- **SessionStart** → `ai.session` span with `ai.session.id`
- **PreToolUse** → `ai.tool.call` span with `ai.tool.name`, `ai.tool.risk_level`
- **Stop** → `ai.session.end` span with `ai.outcome=completed`

All spans are emitted in a backgrounded subshell (`&`) — fire-and-forget, never blocks the hook.

### OpenCode (observe.ts)

Uses `@opentelemetry/api` + `@opentelemetry/sdk-trace-node`:
- **Session span** created on first tool call (module-level flag)
- **Tool-call spans** created per `tool.execute.before`
- **Metrics**: `ai_session_tool_calls_total` counter, `ai_session_cost_usd` gauge

TracerProvider + MeterProvider initialize at module load. If the SDK packages are not installed, tracing degrades silently — the audit trail (events.ndjson) continues regardless.

---

## Configuration

### Endpoint

Set via environment variable:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://chaostarget0101e3:4318
```

Default: `http://localhost:4318`

The same endpoint is used for both traces (`/v1/traces`) and metrics (`/v1/metrics`).

### Service name

- Claude Code: `ai-agent` (set in observe.sh)
- OpenCode: `ai-agent-opencode` (set in observe.ts TracerProvider resource)

---

## Verifying connectivity

### Without a collector (local test)

```bash
# otel-cli fires and forgets — exits clean even without a collector
otel-cli span --service ai-agent --name test-span --endpoint http://localhost:4318
echo $?  # 0
```

### With a local collector (Docker)

```bash
docker run --rm -p 4318:4318 \
  otel/opentelemetry-collector-contrib:latest \
  --config - <<EOF
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
exporters:
  debug:
    verbosity: detailed
service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [debug]
    metrics:
      receivers: [otlp]
      exporters: [debug]
EOF
```

Then run a Claude Code or OpenCode session — spans appear in the collector's debug output.

### With the sandbox collector

The OTel Collector on `chaostarget0101e3` already routes to Prometheus (metrics) and Tempo (traces). Set the endpoint:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://chaostarget0101e3:4318
```

Verify in Grafana → Tempo → search for `service.name = ai-agent`.

---

## Span attributes

| Attribute | Type | Where |
|---|---|---|
| `ai.session.id` | string | session span + all child spans |
| `ai.tool.name` | string | tool-call spans |
| `ai.tool.risk_level` | int | tool-call spans (0-3) |
| `ai.outcome` | string | session-end span |

## Metrics

| Metric | Type | Labels |
|---|---|---|
| `ai_session_tool_calls_total` | counter | tool, outcome, risk_level |
| `ai_session_cost_usd` | gauge | tier, model |

---

## Prerequisites

- `otel-cli` installed (`brew install otel-cli`) — for Claude Code hooks
- `@opentelemetry/*` packages installed in `~/.config/opencode/` — for OpenCode plugins
- OTel Collector endpoint reachable from the development workstation
