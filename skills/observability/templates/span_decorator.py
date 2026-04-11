"""
span_decorator.py — Reusable decorators for OpenTelemetry tracing and metrics.

Provides:
  - @traced(name, attributes) — adds a span around any function (sync or async)
  - @timed_histogram(name) — records function duration as an OTel histogram
  - current_trace_id() — get the current trace ID for log correlation
  - AsyncLocalStorage-style context via contextvars

Usage:
    from span_decorator import traced, timed_histogram

    @traced("experiment.run", attributes={"component": "executor"})
    async def run_experiment(experiment_id: str) -> dict:
        ...

    @timed_histogram("resilience_score_computation_duration_seconds")
    def compute_score(results: list) -> float:
        ...
"""

from __future__ import annotations

import asyncio
import functools
import logging
import time
from collections.abc import Callable
from contextvars import ContextVar
from typing import Any, TypeVar, overload

from opentelemetry import metrics, trace
from opentelemetry.trace import SpanKind, Status, StatusCode

logger = logging.getLogger(__name__)

F = TypeVar("F", bound=Callable[..., Any])

# ---------------------------------------------------------------------------
# Context variable for request-scoped metadata (analogous to AsyncLocalStorage)
# ---------------------------------------------------------------------------

_request_context: ContextVar[dict[str, str]] = ContextVar("request_context", default={})

def set_request_context(**kwargs: str) -> None:
    """Store request-scoped metadata (user_id, experiment_id, etc.) in context."""
    ctx = {**_request_context.get(), **kwargs}
    _request_context.set(ctx)

def get_request_context() -> dict[str, str]:
    return _request_context.get()

def current_trace_id() -> str:
    """Return the current span's trace ID as a hex string, or zeros if no active span."""
    span = trace.get_current_span()
    ctx = span.get_span_context()
    if ctx.is_valid:
        return format(ctx.trace_id, "032x")
    return "0" * 32

# ---------------------------------------------------------------------------
# @traced decorator
# ---------------------------------------------------------------------------

def traced(
    span_name: str | None = None,
    *,
    attributes: dict[str, str | int | float | bool] | None = None,
    kind: SpanKind = SpanKind.INTERNAL,
    record_exception: bool = True,
) -> Callable[[F], F]:
    """
    Decorator that wraps a function in an OpenTelemetry span.

    Works with both sync and async functions.

    Args:
        span_name: Name for the span. Defaults to `module.function_name`.
        attributes: Static span attributes applied at span creation.
        kind: SpanKind (INTERNAL, SERVER, CLIENT, PRODUCER, CONSUMER).
        record_exception: Whether to record exceptions as span events.

    Example:
        @traced("experiment.execute", attributes={"component": "chaos-runner"})
        async def execute(experiment_id: str) -> Result:
            ...
    """
    def decorator(func: F) -> F:
        name = span_name or f"{func.__module__}.{func.__qualname__}"
        tracer = trace.get_tracer(func.__module__)
        base_attrs = attributes or {}

        if asyncio.iscoroutinefunction(func):
            @functools.wraps(func)
            async def async_wrapper(*args: Any, **kwargs: Any) -> Any:
                with tracer.start_as_current_span(name, kind=kind) as span:
                    _apply_attributes(span, base_attrs)
                    _apply_context_attrs(span)
                    try:
                        result = await func(*args, **kwargs)
                        span.set_status(Status(StatusCode.OK))
                        return result
                    except Exception as exc:
                        span.set_status(Status(StatusCode.ERROR, str(exc)))
                        if record_exception:
                            span.record_exception(exc)
                        raise
            return async_wrapper  # type: ignore[return-value]
        else:
            @functools.wraps(func)
            def sync_wrapper(*args: Any, **kwargs: Any) -> Any:
                with tracer.start_as_current_span(name, kind=kind) as span:
                    _apply_attributes(span, base_attrs)
                    _apply_context_attrs(span)
                    try:
                        result = func(*args, **kwargs)
                        span.set_status(Status(StatusCode.OK))
                        return result
                    except Exception as exc:
                        span.set_status(Status(StatusCode.ERROR, str(exc)))
                        if record_exception:
                            span.record_exception(exc)
                        raise
            return sync_wrapper  # type: ignore[return-value]

    return decorator

def _apply_attributes(
    span: trace.Span,
    attributes: dict[str, str | int | float | bool],
) -> None:
    for key, value in attributes.items():
        span.set_attribute(key, value)

def _apply_context_attrs(span: trace.Span) -> None:
    """Propagate request context variables as span attributes."""
    ctx = get_request_context()
    for key, value in ctx.items():
        span.set_attribute(f"app.{key}", value)

# ---------------------------------------------------------------------------
# @timed_histogram decorator
# ---------------------------------------------------------------------------

def timed_histogram(
    metric_name: str,
    *,
    unit: str = "s",
    description: str = "",
    attributes: dict[str, str] | None = None,
) -> Callable[[F], F]:
    """
    Decorator that records function execution time as an OTel histogram.

    Works with both sync and async functions.

    Args:
        metric_name: Name of the histogram metric (e.g. "resilience_score_duration_seconds").
        unit: Unit string (default: "s").
        description: Metric description.
        attributes: Static metric attributes.

    Example:
        @timed_histogram("resilience_db_query_duration_seconds",
                         attributes={"query": "list_experiments"})
        def fetch_experiments(limit: int) -> list:
            ...
    """
    def decorator(func: F) -> F:
        meter = metrics.get_meter(func.__module__)
        histogram = meter.create_histogram(
            metric_name,
            unit=unit,
            description=description or f"Duration of {func.__qualname__}",
        )
        static_attrs = {**(attributes or {})}

        if asyncio.iscoroutinefunction(func):
            @functools.wraps(func)
            async def async_wrapper(*args: Any, **kwargs: Any) -> Any:
                start = time.perf_counter()
                outcome = "success"
                try:
                    return await func(*args, **kwargs)
                except Exception:
                    outcome = "error"
                    raise
                finally:
                    duration = time.perf_counter() - start
                    histogram.record(duration, attributes={**static_attrs, "outcome": outcome})
            return async_wrapper  # type: ignore[return-value]
        else:
            @functools.wraps(func)
            def sync_wrapper(*args: Any, **kwargs: Any) -> Any:
                start = time.perf_counter()
                outcome = "success"
                try:
                    return func(*args, **kwargs)
                except Exception:
                    outcome = "error"
                    raise
                finally:
                    duration = time.perf_counter() - start
                    histogram.record(duration, attributes={**static_attrs, "outcome": outcome})
            return sync_wrapper  # type: ignore[return-value]

    return decorator

# ---------------------------------------------------------------------------
# Usage example
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    # Minimal setup for demonstration
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
    from opentelemetry.sdk.trace.export import SimpleSpanProcessor

    exporter = InMemorySpanExporter()
    provider = TracerProvider()
    provider.add_span_processor(SimpleSpanProcessor(exporter))
    trace.set_tracer_provider(provider)

    set_request_context(experiment_id="exp-001", user_id="usr-42")

    @traced("demo.compute", attributes={"component": "scorer"})
    def compute_demo(n: int) -> int:
        return n * n

    @traced("demo.async_fetch")
    async def fetch_demo(url: str) -> str:
        await asyncio.sleep(0.01)
        return f"result from {url}"

    result = compute_demo(7)
    asyncio.run(fetch_demo("https://api.example.com"))

    spans = exporter.get_finished_spans()
    for s in spans:
        print(f"span: {s.name} trace_id={s.context.trace_id:032x}")
    print(f"current_trace_id: {current_trace_id()}")
