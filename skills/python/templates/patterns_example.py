"""
patterns_example.py — Demonstrates idiomatic Python 3.10+ patterns.

Covers:
  - dataclass with __slots__
  - Structural pattern matching (PEP 634)
  - Walrus operator (PEP 572)
  - contextlib.contextmanager
  - functools.cache
  - Generator pipeline
  - Protocol usage (PEP 544)
"""

from __future__ import annotations

import contextlib
import functools
import logging
from collections.abc import Generator, Iterable, Iterator
from dataclasses import dataclass, field
from typing import Protocol, runtime_checkable

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# 1. Dataclass with __slots__ for memory efficiency
# ---------------------------------------------------------------------------

@dataclass(frozen=True, slots=True)
class ExperimentResult:
    """Immutable, slot-optimised value object."""

    experiment_id: str
    success: bool
    duration_ms: float
    labels: tuple[str, ...] = field(default_factory=tuple)

    @property
    def passed(self) -> bool:
        return self.success and self.duration_ms < 5000.0


# ---------------------------------------------------------------------------
# 2. Protocol for structural subtyping (no inheritance required)
# ---------------------------------------------------------------------------

@runtime_checkable
class Measurable(Protocol):
    """Any object that can report its duration in milliseconds."""

    @property
    def duration_ms(self) -> float: ...


def summarise(item: Measurable) -> str:
    """Works with any object that has duration_ms — no base class needed."""
    return f"duration={item.duration_ms:.1f}ms"


# ---------------------------------------------------------------------------
# 3. Structural pattern matching
# ---------------------------------------------------------------------------

type StatusCode = int  # Python 3.12+ type alias; use TypeAlias on 3.10/3.11


def classify_http_status(status: int) -> str:
    match status:
        case 200 | 201 | 204:
            return "success"
        case 400:
            return "bad_request"
        case 401 | 403:
            return "auth_error"
        case 404:
            return "not_found"
        case code if 500 <= code < 600:
            return f"server_error_{code}"
        case _:
            return "unknown"


def handle_event(event: dict[str, object]) -> str:
    match event:
        case {"type": "experiment_started", "id": str(eid)}:
            return f"starting experiment {eid}"
        case {"type": "experiment_completed", "id": str(eid), "success": True}:
            return f"experiment {eid} passed"
        case {"type": "experiment_completed", "id": str(eid), "success": False}:
            return f"experiment {eid} FAILED"
        case {"type": str(t)}:
            return f"unhandled event type: {t}"
        case _:
            return "malformed event"


# ---------------------------------------------------------------------------
# 4. Walrus operator in comprehensions and while loops
# ---------------------------------------------------------------------------

def extract_passing_results(results: Iterable[ExperimentResult]) -> list[str]:
    """Use walrus to avoid computing passed twice."""
    return [
        f"{r.experiment_id}: {r.duration_ms:.0f}ms"
        for r in results
        if (passed := r.passed) and passed  # noqa: F841 — demonstrates walrus
    ]


def read_chunks(data: bytes, chunk_size: int = 64) -> list[bytes]:
    """Classic walrus pattern for chunked reading."""
    offset = 0
    chunks: list[bytes] = []
    while chunk := data[offset : offset + chunk_size]:
        chunks.append(chunk)
        offset += chunk_size
    return chunks


# ---------------------------------------------------------------------------
# 5. contextlib.contextmanager
# ---------------------------------------------------------------------------

@contextlib.contextmanager
def experiment_context(experiment_id: str) -> Generator[dict[str, object], None, None]:
    """Context manager that logs experiment lifecycle and handles cleanup."""
    ctx: dict[str, object] = {"id": experiment_id, "started": True}
    logger.info("experiment_started", extra={"experiment_id": experiment_id})
    try:
        yield ctx
    except Exception:
        ctx["failed"] = True
        logger.exception("experiment_failed", extra={"experiment_id": experiment_id})
        raise
    finally:
        logger.info("experiment_finished", extra={"experiment_id": experiment_id})


# ---------------------------------------------------------------------------
# 6. functools.cache (unbounded memoisation)
# ---------------------------------------------------------------------------

@functools.cache
def fibonacci(n: int) -> int:
    """Classic recursive Fibonacci — cache makes it O(n) rather than O(2^n)."""
    if n < 2:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)


@functools.lru_cache(maxsize=256)
def compute_resilience_score(
    success_rate: float,
    mttr_seconds: float,
    blast_radius: float,
) -> float:
    """Bounded cache for computed scores."""
    availability = success_rate * (1 - blast_radius * 0.1)
    recovery_factor = 1.0 / (1.0 + mttr_seconds / 3600)
    return round(availability * recovery_factor * 100, 2)


# ---------------------------------------------------------------------------
# 7. Generator pipeline (lazy, memory-efficient)
# ---------------------------------------------------------------------------

def _parse_raw(lines: Iterable[str]) -> Iterator[dict[str, str]]:
    """Stage 1: parse raw log lines into dicts."""
    for line in lines:
        if "=" in line:
            parts = dict(kv.split("=", 1) for kv in line.strip().split() if "=" in kv)
            yield parts


def _filter_errors(records: Iterable[dict[str, str]]) -> Iterator[dict[str, str]]:
    """Stage 2: keep only error records."""
    for record in records:
        if record.get("level") == "ERROR":
            yield record


def _enrich(records: Iterable[dict[str, str]]) -> Iterator[dict[str, str]]:
    """Stage 3: add derived fields."""
    for record in records:
        yield {**record, "source": "chaos-platform"}


def process_log_pipeline(raw_lines: Iterable[str]) -> Iterator[dict[str, str]]:
    """Compose generator stages — nothing runs until iterated."""
    return _enrich(_filter_errors(_parse_raw(raw_lines)))


# ---------------------------------------------------------------------------
# Example usage
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    result = ExperimentResult(
        experiment_id="exp-001",
        success=True,
        duration_ms=1234.5,
        labels=("network", "latency"),
    )
    print(summarise(result))
    print(classify_http_status(503))
    print(handle_event({"type": "experiment_completed", "id": "exp-001", "success": True}))

    with experiment_context("exp-002") as ctx:
        ctx["custom"] = "value"

    print(fibonacci(30))
    print(compute_resilience_score(0.995, 120.0, 0.2))

    sample_logs = [
        "level=ERROR msg=timeout service=auth",
        "level=INFO msg=started service=api",
        "level=ERROR msg=connection_refused service=db",
    ]
    for record in process_log_pipeline(sample_logs):
        print(record)
