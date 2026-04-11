---
name: sre
description: >
  SRE discipline for chaos engineering: SLI/SLO management, error budgets,
  burn rate monitoring, deployment safety, rollback procedures, blast radius
  analysis, capacity planning, toil reduction, on-call practices, production
  readiness, reliability patterns, OTel instrumentation, and chaos probe design.
  Activate when implementing resilience controls or deployments.
version: 2.0.0
argument-hint: "[chaos action, probe, deployment scenario, or reliability concern]"
---

# SRE Skill

## When to activate
- Designing chaos actions (fault injection, resource exhaustion, network partition)
- Writing chaos probes (health checks, metric assertions)
- Deployment safety review (canary, rollback, blast radius)
- SLI/SLO definition, error budget policy, burn rate alerting
- Circuit breaker, bulkhead, retry, and timeout patterns
- Capacity planning and load forecasting
- Toil identification and reduction
- On-call rotation and escalation design
- Production readiness reviews
- Incident response runbooks

---

## SLI / SLO Management Framework

### The four golden signals

Every service must measure:

| Signal | SLI metric | SLO target |
|--------|-----------|------------|
| **Availability** | Ratio of successful responses to total | >= 99.9% over 28d |
| **Latency** | p50, p95, p99 response time | p99 < 500ms |
| **Error rate** | Ratio of 5xx to total requests | < 0.1% |
| **Saturation** | CPU, memory, connection pool usage | < 80% sustained |

### SLI specification pattern

```python
from dataclasses import dataclass
from enum import Enum

class SLICategory(str, Enum):
    AVAILABILITY = "availability"
    LATENCY = "latency"
    ERROR_RATE = "error_rate"
    SATURATION = "saturation"
    FRESHNESS = "freshness"
    CORRECTNESS = "correctness"
    THROUGHPUT = "throughput"

@dataclass(frozen=True)
class SLISpec:
    name: str
    category: SLICategory
    description: str
    good_event_query: str     # numerator — what counts as "good"
    total_event_query: str    # denominator — total events
    unit: str                 # "ratio", "milliseconds", "percent"

    def ratio_query(self, window: str = "5m") -> str:
        return (
            f"({self.good_event_query.replace('{{window}}', window)})"
            f" / "
            f"({self.total_event_query.replace('{{window}}', window)})"
        )
```

### SLO defaults

```python
SLO_DEFAULTS = {
    "availability":      0.999,   # 99.9% uptime
    "p99_latency_ms":    500,     # 500ms at p99
    "error_rate":        0.001,   # < 0.1% errors
    "recovery_time_s":   30,      # MTTR under 30s after chaos
    "saturation_ratio":  0.80,    # < 80% resource saturation
}

def evaluate_slo(metric_name: str, value: float) -> bool:
    threshold = SLO_DEFAULTS.get(metric_name)
    if threshold is None:
        raise ValueError(f"Unknown SLI: {metric_name}")
    if metric_name in ("p99_latency_ms", "error_rate", "recovery_time_s"):
        return value <= threshold   # lower is better
    return value >= threshold       # higher is better
```

### SLO document checklist

Every new service must have an SLO document covering:

- [ ] Service name, owner team, tier (critical / standard / best-effort)
- [ ] SLIs with exact Prometheus/OTel queries
- [ ] SLO targets with rolling window (28d recommended)
- [ ] Error budget policy (what happens at 25%, 50%, 75%, 90% burn)
- [ ] Alert conditions with burn rate thresholds
- [ ] Escalation path: who gets paged vs. ticketed
- [ ] Review cadence: monthly SLO review meeting

---

## Error Budget Policy and Burn Rate Monitoring

### Error budget calculation

```python
from dataclasses import dataclass

@dataclass
class ErrorBudget:
    slo_target: float         # e.g., 0.999
    window_days: int          # e.g., 28
    total_requests: int       # total requests in window

    @property
    def budget_ratio(self) -> float:
        """Fraction of requests allowed to fail."""
        return 1.0 - self.slo_target

    @property
    def budget_requests(self) -> int:
        """Absolute number of requests that can fail."""
        return int(self.total_requests * self.budget_ratio)

    def remaining(self, failures: int) -> float:
        """Fraction of error budget remaining (0.0 to 1.0)."""
        if self.budget_requests == 0:
            return 0.0
        return max(0.0, 1.0 - (failures / self.budget_requests))

    def burn_rate(self, failures_in_window: int, window_hours: float) -> float:
        """
        How fast the budget is burning relative to sustainable rate.
        burn_rate = 1.0 means budget will be exactly exhausted at window end.
        burn_rate > 1.0 means budget will be exhausted before window end.
        """
        window_fraction = window_hours / (self.window_days * 24)
        expected_failures = self.budget_requests * window_fraction
        if expected_failures == 0:
            return float("inf") if failures_in_window > 0 else 0.0
        return failures_in_window / expected_failures
```

### Burn rate alerting thresholds

| Alert | Burn rate | Lookback | Severity | Action |
|-------|----------|----------|----------|--------|
| Fast burn | >= 14.4x | 1h + 5m | critical/page | Immediate response |
| Medium burn | >= 6.0x | 6h + 30m | warning/ticket | Investigate within 4h |
| Slow burn | >= 3.0x | 3d + 6h | info/ticket | Review in next SLO meeting |

### Error budget policy actions

| Budget consumed | Action |
|----------------|--------|
| 0-25% | Normal operations. Run chaos experiments freely. |
| 25-50% | Reduce experiment blast radius. Monitor dashboards. |
| 50-75% | Freeze new chaos experiments. Focus on reliability. |
| 75-90% | Freeze all non-critical changes. Reliability-only sprints. |
| 90-100% | Emergency stop. Incident review before any changes. |

---

## Capacity Planning

### Capacity planning process

1. **Baseline**: measure current resource usage (CPU, memory, disk, network, connections)
2. **Model**: establish relationship between traffic and resource consumption
3. **Forecast**: project traffic growth (linear, seasonal, event-driven)
4. **Threshold**: define headroom requirement (typically 30-40% free)
5. **Plan**: schedule scaling actions with lead time

### Resource saturation model

```python
from dataclasses import dataclass

@dataclass
class CapacityModel:
    resource_name: str        # e.g., "cpu", "memory", "connections"
    current_usage: float      # current utilisation ratio (0.0 to 1.0)
    growth_rate_monthly: float  # fractional monthly growth (e.g., 0.05 = 5%)
    headroom_target: float    # minimum free capacity (e.g., 0.30 = 30%)
    scaling_lead_days: int    # days needed to provision new capacity

    @property
    def ceiling(self) -> float:
        return 1.0 - self.headroom_target

    def months_until_ceiling(self) -> float:
        """Months until current_usage hits ceiling at steady growth."""
        if self.growth_rate_monthly <= 0:
            return float("inf")
        if self.current_usage >= self.ceiling:
            return 0.0
        import math
        return math.log(self.ceiling / self.current_usage) / math.log(1 + self.growth_rate_monthly)

    def needs_action(self) -> bool:
        months = self.months_until_ceiling()
        lead_months = self.scaling_lead_days / 30.0
        return months <= lead_months + 1  # 1 month safety margin
```

### Capacity planning checklist

- [ ] Baseline metrics collected for all critical resources
- [ ] Growth rate estimated from last 3-6 months of data
- [ ] Seasonal patterns identified (month-end, quarter-end)
- [ ] Scaling lead time documented per resource type
- [ ] Headroom target defined (default: 30% free)
- [ ] Alert on saturation > 70% sustained for > 15 minutes
- [ ] Quarterly capacity review meeting scheduled

---

## Toil Reduction Framework

### Toil identification

Toil is work that is manual, repetitive, automatable, tactical, devoid of lasting value, and scales linearly with service size.

| Category | Example | Automation |
|----------|---------|-----------|
| Deployment | Manual deploy steps | CI/CD pipeline |
| Certificate rotation | Renewing TLS certs | cert-manager / auto-renewal |
| User provisioning | Manual account creation | SSO + SCIM |
| Capacity scaling | Manual VM/pod resizing | HPA / auto-scaling |
| Log rotation | Manual archive/cleanup | logrotate + retention policy |
| Experiment cleanup | Removing stale chaos runs | TTL-based garbage collection |
| Alert triage | Noisy/false alerts | Tune thresholds, add context |

### Toil budget

- Target: <= 50% of SRE time spent on toil (Google SRE standard)
- Track toil hours weekly per team member
- Prioritise automation that saves the most cumulative hours
- Every sprint should include at least one toil reduction story

### Toil scoring

```python
@dataclass
class ToilItem:
    name: str
    frequency_per_week: float
    minutes_per_occurrence: float
    automation_effort_hours: float

    @property
    def weekly_cost_hours(self) -> float:
        return (self.frequency_per_week * self.minutes_per_occurrence) / 60.0

    @property
    def payback_weeks(self) -> float:
        if self.weekly_cost_hours == 0:
            return float("inf")
        return self.automation_effort_hours / self.weekly_cost_hours
```

---

## On-Call Practices

### On-call rotation design

- **Rotation length**: 1 week (hand-off on Monday morning)
- **Minimum roster size**: 5 engineers (prevents burnout)
- **Shadow on-call**: new team members shadow for 2 rotations before going primary
- **Escalation chain**: primary (5 min) -> secondary (15 min) -> team lead (30 min) -> management
- **Handoff**: written summary of active incidents, known issues, upcoming changes

### On-call expectations

| Metric | Target |
|--------|--------|
| Acknowledge time | < 5 minutes (page) |
| Time to engage | < 15 minutes |
| Post-incident review | Within 48 hours |
| Interrupt budget | <= 2 pages per shift |
| Compensation | Time-off in lieu or on-call stipend |

### On-call anti-patterns

| Anti-pattern | Fix |
|---|---|
| Paging on non-actionable alerts | Only page on customer-impacting symptoms |
| No runbook for an alert | Every alert needs a linked runbook |
| Hero culture (one person always on) | Enforce rotation, minimum roster size |
| No post-incident review | Blameless postmortem within 48h |
| Paging for toil | Automate it; toil is not an incident |

---

## Production Readiness Checklist

Before any service goes to production:

### Reliability
- [ ] SLOs defined and documented
- [ ] Error budget policy agreed with stakeholders
- [ ] Circuit breakers on all external dependencies
- [ ] Retry with exponential backoff + jitter on transient failures
- [ ] Timeouts configured on all outbound calls (connect + read)
- [ ] Graceful degradation path when dependencies are unavailable
- [ ] Health check endpoints: `/health` (liveness), `/ready` (readiness)

### Observability
- [ ] OTel tracing enabled with proper span attributes
- [ ] Structured logging (JSON) with correlation IDs
- [ ] Key metrics emitting: request rate, error rate, latency, saturation
- [ ] Dashboards created with golden signals
- [ ] Alerts configured with burn rate thresholds
- [ ] Runbooks linked to every alert

### Deployment
- [ ] CI/CD pipeline with automated tests, lint, security scan
- [ ] Canary deployment strategy configured
- [ ] Rollback procedure documented and tested (< 5 min target)
- [ ] Database migration strategy (forward-only, backward-compatible)
- [ ] Feature flags for gradual rollout

### Security
- [ ] No hardcoded secrets — env vars or secret manager only
- [ ] TLS on all network communication
- [ ] Authentication and authorization on all endpoints
- [ ] Input validation on all user-facing inputs
- [ ] Dependency scan passing (no critical CVEs)

### Chaos readiness
- [ ] At least one chaos experiment defined and run in staging
- [ ] Blast radius documented for primary failure modes
- [ ] Recovery time validated (within MTTR SLO)
- [ ] Kill switch available for all chaos experiments

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

---

## Chaos Probe Design

### Probe contract

Every probe must:
1. Be **read-only** — probes observe, never mutate
2. Return a typed result with status, value, and timestamp
3. Be idempotent — safe to call repeatedly
4. Have a timeout <= 10s

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

### Action contract

Every chaos action must:
1. Accept `configuration: Configuration` and `secrets: Secrets` (Chaos Toolkit convention)
2. Return a dict with `status`, `output`, and `duration_ms`
3. Have a corresponding rollback action (or be self-healing)
4. Define `blast_radius` in its docstring or experiment JSON

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

## Blast Radius Analysis Checklist

Before any chaos experiment:

- [ ] **Scope**: which services/components are directly affected?
- [ ] **Blast radius**: which downstream dependencies will be impacted?
- [ ] **Steady state**: what are the baseline SLI values (p50, p99 latency, error rate)?
- [ ] **Hypothesis**: what behaviour do we expect under fault?
- [ ] **Abort criteria**: at what threshold do we halt (e.g. error rate > 5%)?
- [ ] **Rollback**: is rollback automatic or manual? ETA?
- [ ] **Observability**: are spans/metrics emitting before experiment starts?
- [ ] **Isolation**: is this scoped to a non-prod environment or a canary?

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

---

## Deployment Safety Rules

1. **Never deploy to production during a running chaos experiment**
2. **Canary before full rollout** — validate steady state holds at 5% traffic
3. **Abort threshold in CI**: if error rate > 1% during canary, block deploy
4. **Rollback ETA must be < 5 minutes** — if rollback takes longer, the experiment design is wrong
5. **Observability must be emitting before experiment starts** — dark deployments are not chaos engineering

---

## Anti-Patterns

| Anti-pattern | Fix |
|---|---|
| Mutating state in a probe | Probes are read-only — move mutation to an action |
| Chaos experiment without abort criteria | Always define `abort_on_slo_breach` threshold |
| `print()` in chaos actions | Use `structlog.get_logger(__name__)` |
| Hardcoded credentials in experiment JSON | Use `secrets` dict with env var references |
| No rollback function | Every action needs a paired rollback |
| Running chaos in production without canary | Canary-scope all experiments first |
| Alerting on causes instead of symptoms | Alert on SLI breaches, not CPU spikes |
| Same SLO for all tiers | Critical services need tighter SLOs |
| No error budget policy | Define actions at 25/50/75/90% burn |
| Toil exceeding 50% of team time | Automate; track toil hours weekly |
