# OpenTelemetry Instrumentation for Rust

Expert guidance for implementing high-quality, cost-efficient OpenTelemetry telemetry in Rust applications, specifically for chaos engineering workloads.

## When to Apply

Reference this skill when:
- Adding tracing spans to chaos actions or probes
- Implementing metrics for experiment outcomes
- Setting up structured logging with trace correlation
- Configuring the OpenTelemetry SDK in Rust
- Reviewing telemetry for correctness and efficiency

---

## Key Principles

### Signal density over volume

Every telemetry item should serve one of three purposes:
- **Detect** - Help identify that something is wrong
- **Localize** - Help pinpoint where the problem is
- **Explain** - Help understand why it happened

If it doesn't serve one of these purposes, don't emit it.

### Sample in the pipeline, not the SDK

Use the `AlwaysOn` sampler (the default) in every SDK.
Do not configure SDK-side samplers -- they make irreversible decisions before the outcome of a request is known.
Defer all sampling to the Collector, where policies can be changed centrally without redeploying applications.

```
SDK (AlwaysOn)  ->  Collector (sampling)  ->  Backend (retention)
```

---

## Rust SDK Setup

### Dependencies (Cargo.toml)

```toml
[dependencies]
opentelemetry = "0.27"
opentelemetry_sdk = { version = "0.27", features = ["rt-tokio"] }
opentelemetry-otlp = { version = "0.27", features = ["tonic"] }
opentelemetry-semantic-conventions = "0.27"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
tracing-opentelemetry = "0.28"
```

### Initialization pattern

```rust
use opentelemetry::global;
use opentelemetry_sdk::{trace::TracerProvider, Resource};
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_semantic_conventions::resource as res;

fn init_telemetry() -> Result<(), Box<dyn std::error::Error>> {
    let resource = Resource::builder()
        .with_attribute(res::SERVICE_NAME, "tumult-engine")
        .with_attribute(res::SERVICE_VERSION, env!("CARGO_PKG_VERSION"))
        .with_attribute(res::DEPLOYMENT_ENVIRONMENT_NAME,
            std::env::var("OTEL_ENVIRONMENT").unwrap_or_else(|_| "development".into()))
        .build();

    let exporter = opentelemetry_otlp::SpanExporter::builder()
        .with_tonic()
        .with_endpoint(
            std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT")
                .unwrap_or_else(|_| "http://localhost:4317".into())
        )
        .build()?;

    let provider = TracerProvider::builder()
        .with_resource(resource)
        .with_batch_exporter(exporter)
        .build();

    global::set_tracer_provider(provider);
    Ok(())
}
```

### Shutdown

Always flush and shut down the tracer provider on application exit:

```rust
fn shutdown_telemetry() {
    global::shutdown_tracer_provider();
}
```

---

## Spans

### Naming conventions

- Use **lowercase dot-separated** names: `chaos.action.execute`, `chaos.probe.check`
- Span names must be **low cardinality** -- never include variable data (IDs, URLs)
- Variable data goes in **attributes**, not the span name
- Format: `<component>.<operation>` or `<component>.<entity>.<operation>`

### Span kinds

| Kind | Use when |
|------|----------|
| `SERVER` | Processing an incoming request (API endpoint) |
| `CLIENT` | Making an outgoing call (DB query, HTTP request) |
| `INTERNAL` | Internal operation (chaos action execution) |
| `PRODUCER` | Sending a message to a queue |
| `CONSUMER` | Receiving a message from a queue |

### Span status

- Set `OK` only when the operation definitively succeeded
- Set `ERROR` on unrecoverable failures -- include the error message
- Leave `UNSET` (default) when the outcome is ambiguous or the caller decides

### Chaos engineering span attributes

```rust
use opentelemetry::KeyValue;

// Standard chaos experiment attributes
let attributes = vec![
    KeyValue::new("chaos.experiment.id", experiment_id.to_string()),
    KeyValue::new("chaos.experiment.name", experiment_name.clone()),
    KeyValue::new("chaos.action.type", "network-latency"),
    KeyValue::new("chaos.action.target", target_service.clone()),
    KeyValue::new("chaos.action.status", "succeeded"),
    KeyValue::new("chaos.probe.type", "http-health"),
    KeyValue::new("chaos.probe.tolerance_met", true),
    KeyValue::new("chaos.rollback.required", false),
];
```

---

## Metrics

### Instrument selection

| Instrument | Use case |
|------------|----------|
| `Counter` | Monotonically increasing count (experiments run, actions executed) |
| `UpDownCounter` | Value that goes up and down (active experiments) |
| `Histogram` | Distribution of values (action duration, probe latency) |
| `Gauge` | Point-in-time value (system health score) |

### Naming conventions

- Format: `<namespace>.<entity>.<metric>` with unit suffix
- Use dots as separators, not underscores
- Examples:
  - `chaos.experiment.duration.seconds`
  - `chaos.action.count`
  - `chaos.probe.latency.milliseconds`
  - `chaos.rollback.count`

### Cardinality management

- **NEVER** use unbounded values as metric attributes (user IDs, request IDs, timestamps)
- Keep attribute cardinality under 100 per metric
- Safe attributes: `experiment_type`, `action_type`, `target_system`, `status`
- Unsafe attributes: `experiment_id`, `trace_id`, `timestamp`

---

## Logs

### Structured logging with trace correlation

Use `tracing` crate with OpenTelemetry integration:

```rust
use tracing::{info, error, instrument};

#[instrument(skip(config), fields(experiment.id = %experiment_id))]
async fn execute_experiment(experiment_id: &str, config: &ExperimentConfig) -> Result<()> {
    info!(action = %config.action_type, "starting chaos action");

    match run_action(config).await {
        Ok(result) => {
            info!(status = "success", "chaos action completed");
            Ok(result)
        }
        Err(e) => {
            error!(error = %e, "chaos action failed");
            Err(e)
        }
    }
}
```

### Log severity mapping

| Level | Use for |
|-------|---------|
| `ERROR` | Action failure, rollback failure, unrecoverable error |
| `WARN` | Probe tolerance not met, retry needed, degraded mode |
| `INFO` | Experiment started/completed, action executed, probe checked |
| `DEBUG` | Internal state transitions, configuration details |
| `TRACE` | Wire-level details, raw responses |

---

## Sensitive Data

### Prevention rules

- **Never** log connection strings, API keys, or tokens
- **Never** include credentials in span attributes
- **Redact** request/response bodies that may contain PII
- Use the `OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT` env var to truncate long values
- For chaos experiments: never log target system credentials in telemetry

### Safe patterns

```rust
// Good: log the presence, not the value
info!(has_auth_token = config.auth_token.is_some(), "connecting to target");

// Bad: logging the actual credential
// info!(token = %config.auth_token, "connecting to target");
```

---

## Semantic Conventions

### Registry-first approach

Before creating any custom attribute:
1. Search the [OpenTelemetry Attribute Registry](https://opentelemetry.io/docs/specs/semconv/registry/attributes/)
2. Use existing attributes where they fit
3. Only create custom attributes when no standard attribute applies
4. Custom attributes use the `chaos.` namespace prefix

### Standard attributes to use

| Domain | Attributes |
|--------|-----------|
| HTTP | `http.request.method`, `http.response.status_code`, `url.full` |
| Database | `db.system`, `db.operation.name`, `db.namespace` |
| Network | `network.transport`, `network.peer.address`, `network.peer.port` |
| Service | `service.name`, `service.version`, `deployment.environment.name` |

### Attribute placement

| Level | What goes here |
|-------|---------------|
| **Resource** | Service identity, deployment environment, host info |
| **Scope** | Instrumentation library name and version |
| **Span** | Request-specific data, operation details |
| **Log** | Event-specific data, error details |
| **Metric** | Low-cardinality dimensions for aggregation |

---

## Quick Reference

| Task | Approach |
|------|----------|
| New chaos action | Create span with `chaos.action.*` attributes, record duration histogram |
| New probe | Create span with `chaos.probe.*` attributes, record latency |
| API endpoint | Use `SERVER` span kind, set HTTP semantic convention attributes |
| Database call | Use `CLIENT` span kind, set DB semantic convention attributes |
| Background task | Use `INTERNAL` span kind, propagate context from parent |
| Error handling | Set span status to `ERROR`, record error message as event |

## References

- [OpenTelemetry Rust SDK](https://docs.rs/opentelemetry/latest/opentelemetry/)
- [tracing-opentelemetry](https://docs.rs/tracing-opentelemetry/latest/tracing_opentelemetry/)
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- [Dash0 OTel Skills](https://github.com/dash0hq/agent-skills)
