# OpenTelemetry Rust Crate Reference

## Core crates (v0.27+)

```toml
[dependencies]
opentelemetry = "0.27"
opentelemetry_sdk = { version = "0.27", features = ["rt-tokio"] }
opentelemetry-otlp = { version = "0.27", features = ["tonic"] }
opentelemetry-semantic-conventions = "0.27"

# Tracing integration
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
tracing-opentelemetry = "0.28"
```

## Resource setup

```rust
use opentelemetry::KeyValue;
use opentelemetry_sdk::Resource;

let resource = Resource::builder()
    .with_service_name("my-service")
    .with_attributes([
        KeyValue::new("service.version", env!("CARGO_PKG_VERSION")),
        KeyValue::new("deployment.environment", "production"),
    ])
    .build();
```

## Tracer provider

```rust
use opentelemetry_otlp::SpanExporter;
use opentelemetry_sdk::trace::SdkTracerProvider;

let exporter = SpanExporter::builder()
    .with_tonic()
    .build()?;

let provider = SdkTracerProvider::builder()
    .with_resource(resource)
    .with_batch_exporter(exporter)
    .build();

// Set as global
opentelemetry::global::set_tracer_provider(provider.clone());
```

## Span conventions for chaos engineering

| Attribute | Example | Description |
|-----------|---------|-------------|
| `chaos.experiment.id` | `exp-42` | Experiment identifier |
| `chaos.experiment.name` | `pg-conn-exhaust` | Human-readable name |
| `chaos.action.type` | `fault_injection` | Action category |
| `chaos.action.provider` | `chaostooling-db` | Extension providing the action |
| `chaos.probe.type` | `ssh` | Probe transport |
| `chaos.probe.tolerance` | `true` | Whether probe passed |
| `chaos.rollback.status` | `completed` | Rollback outcome |

## Metric naming

Pattern: `chaos.<component>.<metric>.<unit>`

```
chaos.experiment.duration.seconds
chaos.action.execution.count
chaos.probe.latency.milliseconds
chaos.rollback.failure.count
```
