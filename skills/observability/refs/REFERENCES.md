# Observability — Reference Links

## OpenTelemetry
- https://opentelemetry.io/docs/languages/python/ — OpenTelemetry Python SDK: TracerProvider, MeterProvider, LoggerProvider
- https://opentelemetry-python.readthedocs.io/en/latest/ — Python SDK API reference: spans, attributes, context, propagators
- https://opentelemetry.io/docs/specs/semconv/ — OTel Semantic Conventions: standard attribute names for HTTP, DB, messaging, etc.
- https://opentelemetry.io/docs/collector/ — OTel Collector: agent/gateway for receiving, processing, exporting telemetry

## Exporters
- https://opentelemetry-python-contrib.readthedocs.io/en/latest/exporter/otlp/otlp.html — OTLP exporter for Python (gRPC + HTTP)
- https://github.com/open-telemetry/opentelemetry-python/tree/main/exporter/opentelemetry-exporter-prometheus — Prometheus metrics exporter for OTel

## Metrics
- https://github.com/prometheus/client_python — prometheus_client Python library: Counter, Gauge, Histogram, Summary
- https://prometheus.io/docs/practices/naming/ — Prometheus metric naming conventions (unit suffix, base units)

## Grafana
- https://grafana.com/docs/grafana/latest/dashboards/ — Grafana dashboard documentation: panels, variables, alerting
- https://grafana.com/docs/grafana/latest/datasources/prometheus/ — Prometheus data source in Grafana

## Context Propagation
- https://opentelemetry.io/docs/specs/otel/context/api-propagators/ — Context propagators: W3C TraceContext, Baggage
- https://www.w3.org/TR/trace-context/ — W3C Trace Context specification: traceparent and tracestate headers
