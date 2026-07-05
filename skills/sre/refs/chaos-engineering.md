# Chaos Engineering & Logging — Code

Full code for chaos probe design, chaos action design, rollback scoping, and structured logging. The SKILL.md body keeps the probe/action contracts, blast-radius checklist, and deployment safety rules; this file holds the implementations.

---

## Chaos Probe Design

### Probe result type

```python
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any


class ProbeStatus(str, Enum):
    OK      = "ok"
    FAILED  = "failed"
    TIMEOUT = "timeout"
    UNKNOWN = "unknown"


@dataclass
class ProbeResult:
    status:     ProbeStatus
    value:      Any
    message:    str
    probe_name: str
    timestamp:  datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    duration_ms: float = 0.0

    def passed(self) -> bool:
        return self.status == ProbeStatus.OK
```

### HTTP probe pattern

```python
import httpx
import time
from chaoslib.types import Configuration, Secrets


def probe_http_healthy(
    url: str,
    timeout: int = 5,
    expected_status: int = 200,
    configuration: Configuration | None = None,
    secrets: Secrets | None = None,
) -> ProbeResult:
    start = time.monotonic()
    try:
        resp = httpx.get(url, timeout=timeout, follow_redirects=True)
        duration = (time.monotonic() - start) * 1000
        ok = resp.status_code == expected_status
        return ProbeResult(
            status=ProbeStatus.OK if ok else ProbeStatus.FAILED,
            value=resp.status_code,
            message=f"HTTP {resp.status_code} from {url}",
            probe_name="http_healthy",
            duration_ms=duration,
        )
    except httpx.TimeoutException:
        return ProbeResult(ProbeStatus.TIMEOUT, None, f"Timeout after {timeout}s", "http_healthy")
    except Exception as exc:
        return ProbeResult(ProbeStatus.FAILED, None, str(exc), "http_healthy")
```

---

## Chaos Action Design

```python
def inject_latency(
    target_service: str,
    delay_ms: int,
    duration_s: int,
    configuration: Configuration | None = None,
    secrets: Secrets | None = None,
) -> dict:
    """
    Inject artificial latency into target_service for duration_s seconds.

    blast_radius: single service, upstream callers may timeout
    rollback: remove_latency(target_service)
    """
    # implementation ...
    return {"status": "ok", "output": f"Injected {delay_ms}ms on {target_service}", "duration_ms": 0.0}
```

---

## Rollback Patterns

```python
from contextlib import contextmanager
from typing import Callable


@contextmanager
def chaos_scope(rollback_fn: Callable[[], None], abort_threshold: float = 0.05):
    """
    Context manager for safe chaos execution.
    Automatically rolls back on exception or threshold breach.
    """
    try:
        yield
    except Exception as exc:
        rollback_fn()
        raise RuntimeError(f"Chaos aborted, rollback triggered: {exc}") from exc
    finally:
        # Always verify steady state after experiment
        pass
```

---

## Structured Logging (Python)

```python
import logging
import structlog


def configure_structlog() -> None:
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(),
    )

# Usage — never print(), always logger
logger = structlog.get_logger(__name__)

def run_experiment(experiment_id: str) -> None:
    logger.info("experiment.start", experiment_id=experiment_id)
    try:
        # ...
        logger.info("experiment.complete", experiment_id=experiment_id, status="ok")
    except Exception as exc:
        logger.error("experiment.failed", experiment_id=experiment_id, error=str(exc))
        raise
```
