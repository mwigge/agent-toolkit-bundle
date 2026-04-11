---
name: observability
description: >
  OpenTelemetry SDK patterns for Python and TypeScript: span creation, trace
  propagation, metric naming conventions, structured logging integration, and
  hook-based event streaming for chaos experiment observability.
  Activate when adding instrumentation, spans, metrics, or logging.
version: 1.0.0
argument-hint: "[component or instrumentation goal]"
---

# Observability Skill

## When to activate
- Adding OTel spans to a chaos action or probe
- Defining new metrics (counters, histograms, gauges)
- Wiring structured logging to OTel
- Reviewing instrumentation for completeness
- Interpreting hook event logs from `observe.sh`

---

## Metric Naming Convention

```
resilience_<component>_<metric>_<unit>
```

| Component | Examples |
|---|---|
| `experiment` | `resilience_experiment_duration_seconds` |
| `probe` | `resilience_probe_result_total` |
| `action` | `resilience_action_applied_total` |
| `score` | `resilience_score_value` |
| `recovery` | `resilience_recovery_time_seconds` |

Units: `_seconds`, `_milliseconds`, `_bytes`, `_total` (for counters), `_ratio`.

---

## Python — OTel SDK Setup

```python
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter

def configure_otel(service_name: str, endpoint: str = "http://localhost:4317") -> None:
    """Call once at application startup."""
    # Traces
    tracer_provider = TracerProvider()
    tracer_provider.add_span_processor(
        BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint))
    )
    trace.set_tracer_provider(tracer_provider)

    # Metrics
    reader = PeriodicExportingMetricReader(
        OTLPMetricExporter(endpoint=endpoint),
        export_interval_millis=10_000,
    )
    meter_provider = MeterProvider(metric_readers=[reader])
    metrics.set_meter_provider(meter_provider)
```

---

## Python — Span Patterns

```python
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode
import functools
from typing import Callable, TypeVar, Any

tracer = trace.get_tracer(__name__)

# ── Decorator pattern (preferred for actions/probes) ──────────────────────────
def with_span(span_name: str | None = None, **span_attrs: Any):
    """Decorator: wraps a function in an OTel span."""
    def decorator(fn: Callable) -> Callable:
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            name = span_name or fn.__qualname__
            with tracer.start_as_current_span(name) as span:
                for k, v in span_attrs.items():
                    span.set_attribute(k, v)
                try:
                    result = fn(*args, **kwargs)
                    span.set_status(Status(StatusCode.OK))
                    return result
                except Exception as exc:
                    span.set_status(Status(StatusCode.ERROR, str(exc)))
                    span.record_exception(exc)
                    raise
        return wrapper
    return decorator

# ── Context manager pattern (for complex flows) ───────────────────────────────
def run_probe(probe_name: str, target: str) -> dict:
    with tracer.start_as_current_span(f"probe.{probe_name}") as span:
        span.set_attribute("resilience.probe.name",   probe_name)
        span.set_attribute("resilience.probe.target", target)
        span.set_attribute("resilience.component",    "probe")
        try:
            result = _execute_probe(probe_name, target)
            span.set_attribute("resilience.probe.status", result["status"])
            span.set_status(Status(StatusCode.OK))
            return result
        except Exception as exc:
            span.set_status(Status(StatusCode.ERROR, str(exc)))
            span.record_exception(exc)
            raise
```

---

## Python — Standard `resilience_*` Attributes

Always set these on chaos spans:

```python
REQUIRED_SPAN_ATTRS = {
    "resilience.component":       str,   # "action" | "probe" | "experiment"
    "resilience.experiment_id":   str,   # UUID from experiment JSON
    "resilience.target_service":  str,   # affected service name
    "resilience.environment":     str,   # "production" | "staging" | "canary"
}

OPTIONAL_SPAN_ATTRS = {
    "resilience.blast_radius":    str,   # "single_service" | "multi_service"
    "resilience.action_type":     str,   # "latency" | "resource" | "network"
    "resilience.probe_result":    str,   # "ok" | "failed" | "timeout"
    "resilience.score_before":    float,
    "resilience.score_after":     float,
}
```

---

## Python — Metrics

```python
from opentelemetry import metrics

meter = metrics.get_meter(__name__)

# ── Counter: total events ─────────────────────────────────────────────────────
probe_results = meter.create_counter(
    name="resilience_probe_result_total",
    description="Total probe executions by status",
    unit="1",
)

# ── Histogram: latency distribution ──────────────────────────────────────────
experiment_duration = meter.create_histogram(
    name="resilience_experiment_duration_seconds",
    description="End-to-end chaos experiment duration",
    unit="s",
)

# ── Gauge: current value ──────────────────────────────────────────────────────
resilience_score = meter.create_observable_gauge(
    name="resilience_score_value",
    description="Current resilience score (0.0–1.0)",
    unit="1",
    callbacks=[lambda _: [metrics.Observation(get_current_score())]],
)

# Recording
def record_probe(status: str, service: str, duration_s: float) -> None:
    probe_results.add(1, {"status": status, "service": service})
    experiment_duration.record(duration_s, {"component": "probe"})
```

---

## TypeScript — OTel SDK

```typescript
import { NodeSDK } from "@opentelemetry/sdk-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-grpc";
import { OTLPMetricExporter } from "@opentelemetry/exporter-metrics-otlp-grpc";
import { PeriodicExportingMetricReader } from "@opentelemetry/sdk-metrics";
import { trace, SpanStatusCode, context } from "@opentelemetry/api";

export function initOtel(serviceName: string, endpoint = "http://localhost:4317"): NodeSDK {
  const sdk = new NodeSDK({
    serviceName,
    traceExporter: new OTLPTraceExporter({ url: endpoint }),
    metricReader: new PeriodicExportingMetricReader({
      exporter: new OTLPMetricExporter({ url: endpoint }),
      exportIntervalMillis: 10_000,
    }),
  });
  sdk.start();
  return sdk;
}

const tracer = trace.getTracer("chaos-platform");

export async function withSpan<T>(
  name: string,
  attrs: Record<string, string | number | boolean>,
  fn: () => Promise<T>,
): Promise<T> {
  return tracer.startActiveSpan(name, async (span) => {
    Object.entries(attrs).forEach(([k, v]) => span.setAttribute(k, v));
    try {
      const result = await fn();
      span.setStatus({ code: SpanStatusCode.OK });
      return result;
    } catch (err) {
      span.setStatus({ code: SpanStatusCode.ERROR, message: String(err) });
      span.recordException(err as Error);
      throw err;
    } finally {
      span.end();
    }
  });
}
```

---

## Hook Event Log — Schema

`observe.sh` writes to `.claude/logs/events.ndjson`. Each line:

```json
{
  "ts":            "2026-04-05T12:00:00Z",
  "session_id":    "abc123",
  "event":         "PostToolUse",
  "tool":          "Edit",
  "input_summary": "src/actions/latency.py",
  "outcome":       "ok",
  "risk":          1
}
```

Reading the log:
```bash
# All high-risk events
jq 'select(.risk >= 3)' .claude/logs/events.ndjson

# Tools used in this session
jq -r '.tool' .claude/logs/events.ndjson | sort | uniq -c | sort -rn

# Blocked events
jq 'select(.outcome == "blocked")' .claude/logs/events.ndjson
```

---

## Completeness Checklist

Every new chaos action or probe must have:
- [ ] OTel span with `resilience_*` attributes (component, experiment_id, target_service)
- [ ] Span status set to `OK` or `ERROR` (never left unset)
- [ ] Exception recorded via `span.record_exception(exc)` on failure
- [ ] At least one counter increment (probe_result_total or action_applied_total)
- [ ] Duration recorded in histogram
- [ ] Structured log entry at start and end (structlog, not print)

---

## Distributed Tracing Patterns

### Trace Context Propagation (W3C Trace Context)

All services must propagate trace context using the W3C `traceparent` and `tracestate` headers:

```
traceparent: 00-<trace-id>-<span-id>-<trace-flags>
tracestate:  vendor1=value1,vendor2=value2
```

```python
# Python — automatic propagation with OTel SDK
from opentelemetry.propagate import inject, extract
from opentelemetry import context

# Outgoing request: inject trace context into headers
headers: dict[str, str] = {}
inject(headers)
# headers now contains {"traceparent": "00-...", "tracestate": "..."}

# Incoming request: extract trace context from headers
ctx = extract(carrier=request.headers)
with tracer.start_as_current_span("handle_request", context=ctx) as span:
    ...
```

```typescript
// TypeScript — automatic with OTel HTTP instrumentation
// If using manual propagation:
import { propagation, context } from "@opentelemetry/api";

const headers: Record<string, string> = {};
propagation.inject(context.active(), headers);
// Pass headers to downstream HTTP client
```

**Rules**:
- Use W3C Trace Context as the propagation format — it is the standard
- Never generate a new trace ID mid-request — always propagate the incoming one
- Ensure all HTTP clients and message queue producers inject trace context
- Ensure all HTTP servers and message queue consumers extract trace context

### Span Relationship Types

| Relationship | When to use | Example |
|-------------|-------------|---------|
| **Parent-child** | Work is done on behalf of the parent span | HTTP handler → database query |
| **Follows-from** | Work is triggered by but not blocking the prior span | Event published → async consumer processes it |
| **Link** | Related but independent traces (batch processing, fan-out) | Batch job links to each individual item's trace |

```python
from opentelemetry import trace

# Parent-child (default — use context manager nesting)
with tracer.start_as_current_span("parent"):
    with tracer.start_as_current_span("child"):
        ...  # child is automatically a child of parent

# Link to a related trace (e.g., batch processing)
link = trace.Link(triggering_span_context)
with tracer.start_as_current_span("batch_process", links=[link]):
    ...
```

### Sampling Strategies

| Strategy | How it works | Trade-off |
|----------|-------------|-----------|
| **Head-based** | Decision made at trace start, propagated to all spans | Simple, consistent, but may miss interesting traces |
| **Tail-based** | Decision made after trace completes, based on full trace data | Captures errors/slow traces, but requires buffering all spans |
| **Rate-based** | Sample N traces per second regardless of volume | Predictable cost, but may miss rare events |

**Recommended approach**:
- Use head-based sampling as the default (e.g., sample 10% of traces)
- Add tail-based sampling rules for high-value signals:
  - Always sample traces with errors (`span.status == ERROR`)
  - Always sample traces exceeding latency thresholds (e.g., p99)
  - Always sample traces from canary deployments
- Never sample 0% — even 1% provides debugging capability

```python
from opentelemetry.sdk.trace.sampling import TraceIdRatioBased, ParentBasedTraceIdRatio

# Sample 10% of root spans; child spans follow parent decision
sampler = ParentBasedTraceIdRatio(rate=0.1)
```

### Trace-to-Log Correlation

Embed trace and span IDs in every structured log entry for cross-referencing:

```python
import structlog
from opentelemetry import trace

def add_trace_context(logger, method_name, event_dict):
    """Structlog processor: adds trace/span IDs to every log entry."""
    span = trace.get_current_span()
    ctx = span.get_span_context()
    if ctx.is_valid:
        event_dict["trace_id"] = format(ctx.trace_id, "032x")
        event_dict["span_id"] = format(ctx.span_id, "016x")
    return event_dict

structlog.configure(
    processors=[
        add_trace_context,
        structlog.processors.JSONRenderer(),
    ]
)
```

**Result**: every log line includes `trace_id` and `span_id`, enabling direct lookup from a log entry to the full distributed trace.

### Service Dependency Graph from Traces

Trace data can generate a real-time service dependency map:

- **Edges**: every parent-child span relationship crossing a service boundary creates an edge
- **Attributes per edge**: call count, error rate, p50/p99 latency
- **Drift detection**: compare the observed graph against the expected architecture diagram — new edges may indicate unplanned dependencies

Use the dependency graph to:
- Identify critical path services (most downstream dependencies)
- Find single points of failure (services with no redundancy on the critical path)
- Scope blast radius for chaos experiments (which services are affected if service X fails?)

### Latency Breakdown Analysis

Use span waterfalls to identify where time is spent in a request:

```
[──── HTTP handler (120ms) ───────────────────────────]
  [── auth check (5ms) ──]
  [────── DB query (45ms) ──────]
                                [── serialize (3ms) ──]
                                   [── downstream API call (60ms) ────]
                                                                      [─ log (1ms) ─]
```

**Analysis rules**:
- Identify the **critical path**: the longest chain of sequential spans
- Look for **sequential spans that could be parallel** (e.g., independent DB queries)
- Flag spans with high **self-time** (time not accounted for by child spans) — this indicates CPU-bound work or untraced I/O
- Compare latency breakdown across percentiles (p50 vs p99) to find variance sources

---

## Anti-Patterns

| Anti-pattern | Fix |
|---|---|
| `print()` for observability output | `structlog.get_logger().info(...)` |
| Span without status set | Always call `span.set_status(OK\|ERROR)` |
| Metric names without `resilience_` prefix | Follow `resilience_<component>_<metric>_<unit>` |
| `console.log` in TS instrumentation code | Use OTel structured logger or `pino` |
| Span started but never ended (no try/finally) | Use `start_as_current_span` context manager or `withSpan` wrapper |
| Counter without labels | Always add `{"status": ..., "service": ...}` attributes |
