// Template: OpenTelemetry setup for a Rust service

use anyhow::Result;
use opentelemetry::KeyValue;
use opentelemetry_otlp::SpanExporter;
use opentelemetry_sdk::{
    trace::SdkTracerProvider,
    Resource,
};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

/// Initialize OpenTelemetry tracing with OTLP export.
///
/// # Errors
///
/// Returns an error if the OTLP exporter or tracer provider fails to initialize.
pub fn init_telemetry(service_name: &str) -> Result<SdkTracerProvider> {
    let resource = Resource::builder()
        .with_service_name(service_name)
        .with_attributes([
            KeyValue::new("service.version", env!("CARGO_PKG_VERSION")),
        ])
        .build();

    let exporter = SpanExporter::builder()
        .with_tonic()
        .build()?;

    let provider = SdkTracerProvider::builder()
        .with_resource(resource)
        .with_batch_exporter(exporter)
        .build();

    // Bridge tracing crate → OpenTelemetry
    let otel_layer = tracing_opentelemetry::layer()
        .with_tracer(provider.tracer(service_name));

    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .with(tracing_subscriber::fmt::layer())
        .with(otel_layer)
        .init();

    Ok(provider)
}

/// Shut down the tracer provider, flushing pending spans.
pub fn shutdown_telemetry(provider: SdkTracerProvider) {
    if let Err(e) = provider.shutdown() {
        eprintln!("failed to shut down tracer provider: {e}");
    }
}
