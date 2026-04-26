"""
otel_setup.py — Complete OpenTelemetry setup for the chaos platform.

Provides:
  - TracerProvider with BatchSpanProcessor + OTLPSpanExporter
  - MeterProvider with Prometheus exporter
  - Structured logging with trace_id injection
  - W3C TraceContext context propagation helpers
  - resilience_* metric instruments

Usage:
    from otel_setup import setup_telemetry, get_tracer, get_meter

    setup_telemetry(service_name="chaos-platform-api")
    tracer = get_tracer(__name__)
    meter = get_meter(__name__)

Dependencies:
    opentelemetry-api opentelemetry-sdk
    opentelemetry-exporter-otlp-proto-grpc
    opentelemetry-exporter-prometheus
    opentelemetry-propagator-b3
"""

from __future__ import annotations

import logging
import os
from typing import Any

from opentelemetry import metrics, trace
from opentelemetry.context import attach, detach, get_current
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.propagators.textmap import TextMapPropagator
from opentelemetry.propagate import extract, inject, set_global_textmap
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Resource — service identity for all telemetry
# ---------------------------------------------------------------------------

def _build_resource(
    service_name: str,
    service_version: str = "unknown",
    environment: str | None = None,
) -> Resource:
    return Resource.create({
        "service.name": service_name,
        "service.version": service_version,
        "deployment.environment": environment or os.environ.get("CHAOS_ENV", "production"),
        "service.namespace": "chaos-platform",
    })


# ---------------------------------------------------------------------------
# Tracing Setup
# ---------------------------------------------------------------------------

def _setup_tracer_provider(resource: Resource) -> TracerProvider:
    otlp_endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")

    exporter = OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True)
    processor = BatchSpanProcessor(
        exporter,
        max_export_batch_size=512,
        max_queue_size=2048,
        export_timeout_millis=30_000,
    )

    provider = TracerProvider(resource=resource)
    provider.add_span_processor(processor)

    trace.set_tracer_provider(provider)
    logger.info("tracer_provider_configured", extra={"endpoint": otlp_endpoint})
    return provider


# ---------------------------------------------------------------------------
# Metrics Setup (Prometheus exporter)
# ---------------------------------------------------------------------------

def _setup_meter_provider(resource: Resource) -> MeterProvider:
    try:
        from opentelemetry.exporter.prometheus import PrometheusMetricReader
        reader = PrometheusMetricReader(prefix="chaos")
        logger.info("prometheus_exporter_configured")
    except ImportError:
        from opentelemetry.sdk.metrics.export import ConsoleMetricExporter
        reader = PeriodicExportingMetricReader(ConsoleMetricExporter(), export_interval_millis=30_000)
        logger.warning("prometheus_exporter_unavailable_using_console")

    provider = MeterProvider(resource=resource, metric_readers=[reader])
    metrics.set_meter_provider(provider)
    return provider


# ---------------------------------------------------------------------------
# Structured Logging with trace_id injection
# ---------------------------------------------------------------------------

class TraceContextFilter(logging.Filter):
    """Injects trace_id and span_id into every log record."""

    def filter(self, record: logging.LogRecord) -> bool:
        span = trace.get_current_span()
        ctx = span.get_span_context()
        if ctx.is_valid:
            record.trace_id = format(ctx.trace_id, "032x")
            record.span_id = format(ctx.span_id, "016x")
        else:
            record.trace_id = "0" * 32
            record.span_id = "0" * 16
        return True


def _setup_logging(service_name: str) -> None:
    """Configure root logger with JSON-friendly format and trace context injection."""
    root = logging.getLogger()
    for handler in root.handlers:
        handler.addFilter(TraceContextFilter())

    if not root.handlers:
        handler = logging.StreamHandler()
        handler.addFilter(TraceContextFilter())
        handler.setFormatter(logging.Formatter(
            fmt='%(asctime)s %(levelname)s %(name)s trace_id=%(trace_id)s span_id=%(span_id)s %(message)s',
            datefmt="%Y-%m-%dT%H:%M:%S",
        ))
        root.addHandler(handler)


# ---------------------------------------------------------------------------
# Context Propagation Helpers
# ---------------------------------------------------------------------------

def extract_context(headers: dict[str, str]) -> Any:
    """Extract OTel context from incoming HTTP headers (W3C TraceContext)."""
    return extract(headers)


def inject_context(headers: dict[str, str]) -> None:
    """Inject current OTel context into outgoing HTTP headers."""
    inject(headers)


# ---------------------------------------------------------------------------
# Resilience Metric Instruments
# ---------------------------------------------------------------------------

def _create_instruments(meter: metrics.Meter) -> dict[str, Any]:
    """Create standard resilience_* metric instruments."""
    return {
        "experiment_started": meter.create_counter(
            "resilience_experiments_started_total",
            description="Total number of chaos experiments started",
            unit="1",
        ),
        "experiment_completed": meter.create_counter(
            "resilience_experiments_completed_total",
            description="Total number of chaos experiments completed",
            unit="1",
        ),
        "experiment_failed": meter.create_counter(
            "resilience_experiments_failed_total",
            description="Total number of chaos experiments that failed",
            unit="1",
        ),
        "experiment_duration": meter.create_histogram(
            "resilience_experiment_duration_seconds",
            description="Duration of chaos experiment execution",
            unit="s",
        ),
        "score_gauge": meter.create_gauge(
            "resilience_score",
            description="Current resilience score (0–100)",
            unit="1",
        ),
        "blast_radius_histogram": meter.create_histogram(
            "resilience_blast_radius",
            description="Distribution of experiment blast radius values",
            unit="1",
        ),
    }


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

_instruments: dict[str, Any] = {}


def setup_telemetry(
    service_name: str = "chaos-platform",
    service_version: str = "unknown",
    environment: str | None = None,
) -> None:
    """Initialise all telemetry providers. Call once at application startup."""
    global _instruments

    resource = _build_resource(service_name, service_version, environment)

    _setup_tracer_provider(resource)
    meter_provider = _setup_meter_provider(resource)
    _setup_logging(service_name)

    set_global_textmap(TraceContextTextMapPropagator())

    meter = metrics.get_meter(service_name, schema_url="https://opentelemetry.io/schemas/1.24.0")
    _instruments = _create_instruments(meter)

    logger.info("telemetry_initialised", extra={"service": service_name})


def get_tracer(name: str) -> trace.Tracer:
    return trace.get_tracer(name)


def get_meter(name: str) -> metrics.Meter:
    return metrics.get_meter(name)


def get_instruments() -> dict[str, Any]:
    return _instruments
