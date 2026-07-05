# Reliability Patterns — Code

Full implementations of the reliability patterns referenced from the SKILL.md body: retry with backoff, circuit breaker, bulkhead, timeout, health checks, graceful degradation, and progressive rollout via feature flags.

---

## Reliability Patterns

### Retry with exponential backoff and jitter

```python
import random
import time
from typing import TypeVar, Callable

T = TypeVar("T")


def retry_with_backoff(
    fn: Callable[[], T],
    max_retries: int = 3,
    base_delay: float = 1.0,
    max_delay: float = 30.0,
    retryable_exceptions: tuple[type[Exception], ...] = (ConnectionError, TimeoutError),
) -> T:
    for attempt in range(max_retries + 1):
        try:
            return fn()
        except retryable_exceptions:
            if attempt == max_retries:
                raise
            delay = min(base_delay * (2 ** attempt), max_delay)
            jitter = random.uniform(0, delay * 0.5)
            time.sleep(delay + jitter)
    raise RuntimeError("Unreachable")
```

### Circuit breaker pattern

```python
from enum import Enum
import time
from threading import Lock


class CircuitState(Enum):
    CLOSED   = "closed"    # normal operation
    OPEN     = "open"      # blocking calls
    HALF_OPEN = "half_open" # testing recovery


class CircuitBreaker:
    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: float = 30.0,
        half_open_max_calls: int = 1,
    ):
        self.failure_threshold  = failure_threshold
        self.recovery_timeout   = recovery_timeout
        self.half_open_max_calls = half_open_max_calls
        self._state             = CircuitState.CLOSED
        self._failure_count     = 0
        self._last_failure_time: float = 0.0
        self._lock              = Lock()

    @property
    def state(self) -> CircuitState:
        with self._lock:
            if self._state == CircuitState.OPEN:
                if time.monotonic() - self._last_failure_time >= self.recovery_timeout:
                    self._state = CircuitState.HALF_OPEN
            return self._state

    def record_success(self) -> None:
        with self._lock:
            self._failure_count = 0
            self._state = CircuitState.CLOSED

    def record_failure(self) -> None:
        with self._lock:
            self._failure_count += 1
            self._last_failure_time = time.monotonic()
            if self._failure_count >= self.failure_threshold:
                self._state = CircuitState.OPEN
```

### Bulkhead pattern

```python
import asyncio
from contextlib import asynccontextmanager
from collections.abc import AsyncGenerator


class Bulkhead:
    """
    Limits concurrent access to a resource to prevent cascading failure.
    Each dependency gets its own bulkhead with an independent concurrency limit.
    """

    def __init__(self, name: str, max_concurrent: int = 10, max_wait: float = 5.0):
        self.name = name
        self.max_concurrent = max_concurrent
        self.max_wait = max_wait
        self._semaphore = asyncio.Semaphore(max_concurrent)

    @asynccontextmanager
    async def acquire(self) -> AsyncGenerator[None, None]:
        try:
            await asyncio.wait_for(self._semaphore.acquire(), timeout=self.max_wait)
        except asyncio.TimeoutError:
            raise RuntimeError(
                f"Bulkhead '{self.name}' rejected: {self.max_concurrent} "
                f"concurrent calls in flight, waited {self.max_wait}s"
            )
        try:
            yield
        finally:
            self._semaphore.release()
```

### Timeout pattern

```python
import asyncio
from typing import TypeVar, Callable, Awaitable

T = TypeVar("T")


async def with_timeout(
    coro: Awaitable[T],
    timeout_seconds: float,
    fallback: Callable[[], T] | None = None,
) -> T:
    """
    Execute a coroutine with a timeout.
    Returns fallback value if timeout and fallback is provided.
    Raises asyncio.TimeoutError if no fallback.
    """
    try:
        return await asyncio.wait_for(coro, timeout=timeout_seconds)
    except asyncio.TimeoutError:
        if fallback is not None:
            return fallback()
        raise
```

### Health check endpoints

```python
from dataclasses import dataclass


@dataclass
class HealthStatus:
    status: str               # "healthy", "degraded", "unhealthy"
    checks: dict[str, bool]   # per-dependency check results
    version: str              # application version

    def is_healthy(self) -> bool:
        return self.status == "healthy"

    def is_ready(self) -> bool:
        """Ready to serve traffic (all critical deps available)."""
        return all(self.checks.values())


def liveness_check() -> dict:
    """GET /health — is the process alive?"""
    return {"status": "ok"}


def readiness_check(deps: dict[str, Callable[[], bool]]) -> dict:
    """GET /ready — can we serve traffic?"""
    results = {}
    for name, check_fn in deps.items():
        try:
            results[name] = check_fn()
        except Exception:
            results[name] = False
    all_ok = all(results.values())
    return {"ready": all_ok, "checks": results}
```

### Graceful degradation

Prioritise core functionality when dependencies fail:

| Dependency state | Behaviour |
|-----------------|-----------|
| All healthy | Full functionality |
| Cache unavailable | Serve from database (slower, acceptable) |
| Recommendations service down | Show default/popular items |
| Analytics pipeline down | Queue events, do not block user flow |
| Auth service degraded | Use cached tokens with short grace period |

### Feature flags for progressive rollout

```python
from dataclasses import dataclass


@dataclass(frozen=True)
class FeatureFlag:
    name: str
    rollout_percentage: float  # 0.0 to 100.0
    enabled_for_internal: bool = True

    def is_enabled(self, user_id: str, is_internal: bool = False) -> bool:
        if is_internal and self.enabled_for_internal:
            return True
        # Deterministic hash-based rollout
        bucket = hash(f"{self.name}:{user_id}") % 100
        return bucket < self.rollout_percentage
```

Progressive rollout stages:
1. **Internal** (0%): enabled for team only via feature flag
2. **Canary** (1-5%): small percentage of production traffic
3. **Early access** (10-25%): broader validation
4. **General availability** (100%): full rollout, remove flag
