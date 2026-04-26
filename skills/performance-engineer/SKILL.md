---
name: performance-engineer
description: >
  Performance engineering: load testing, profiling, benchmarking, capacity
  analysis, latency optimisation, and resource efficiency. Activate when
  designing load tests, profiling bottlenecks, analysing chaos experiment
  performance impact, or setting performance budgets.
version: 1.0.0
argument-hint: "[service, endpoint, or performance concern]"
---

# Performance Engineer Skill

## When to activate
- Designing and running load tests (k6, Locust, wrk)
- Profiling Python or Node.js applications for CPU/memory bottlenecks
- Benchmarking API endpoints or database queries
- Analysing performance impact of chaos experiments
- Setting performance budgets and SLOs
- Capacity planning based on load test results
- Identifying and resolving latency regressions

---

## Load Testing Strategy

### Test types

| Type | Purpose | Duration | Load profile |
|------|---------|----------|-------------|
| **Smoke** | Verify system works under minimal load | 1-2 min | 1-5 VUs |
| **Load** | Validate performance under expected load | 10-30 min | Expected VUs |
| **Stress** | Find breaking point | 10-30 min | Ramp beyond expected |
| **Soak** | Detect memory leaks, resource exhaustion | 2-8 hours | Sustained expected load |
| **Spike** | Test autoscaling and recovery | 5-10 min | Sudden burst |
| **Breakpoint** | Find maximum capacity | 15-30 min | Incremental ramp |

### k6 load test pattern

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate = new Rate('errors');
const latency = new Trend('request_latency', true);

export const options = {
  stages: [
    { duration: '2m', target: 10 },    // ramp up
    { duration: '5m', target: 10 },    // steady state
    { duration: '2m', target: 50 },    // stress
    { duration: '5m', target: 50 },    // sustained stress
    { duration: '2m', target: 0 },     // ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    errors: ['rate<0.01'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const res = http.get(`${__ENV.BASE_URL}/api/experiments`);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'latency < 500ms': (r) => r.timings.duration < 500,
    'body is valid JSON': (r) => {
      try { JSON.parse(r.body); return true; } catch { return false; }
    },
  });

  errorRate.add(res.status >= 400);
  latency.add(res.timings.duration);

  sleep(1);
}
```

### Locust load test pattern (Python)

```python
from locust import HttpUser, task, between


class ChaosAPIUser(HttpUser):
    wait_time = between(1, 3)

    @task(3)
    def list_experiments(self) -> None:
        with self.client.get(
            "/api/experiments",
            name="/api/experiments",
            catch_response=True,
        ) as response:
            if response.status_code != 200:
                response.failure(f"Status {response.status_code}")
            elif response.elapsed.total_seconds() > 0.5:
                response.failure(f"Too slow: {response.elapsed.total_seconds():.2f}s")

    @task(1)
    def get_experiment_detail(self) -> None:
        self.client.get("/api/experiments/1", name="/api/experiments/[id]")

    def on_start(self) -> None:
        """Authenticate before starting tasks."""
        self.client.post("/api/auth/login", json={
            "username": self.environment.parsed_options.username,
            "password": self.environment.parsed_options.password,
        })
```

---

## Profiling

### Python profiling tools

| Tool | Use case | Overhead |
|------|----------|----------|
| `cProfile` | CPU profiling (function-level) | Low |
| `py-spy` | Sampling profiler (no code changes) | Minimal |
| `memray` | Memory profiling and leak detection | Medium |
| `scalene` | CPU + memory + GPU combined | Medium |
| `line_profiler` | Line-by-line CPU profiling | High |

### Python CPU profiling

```python
import cProfile
import pstats
from io import StringIO


def profile_function(fn, *args, **kwargs):
    """Profile a function and return sorted stats."""
    profiler = cProfile.Profile()
    profiler.enable()
    result = fn(*args, **kwargs)
    profiler.disable()

    stream = StringIO()
    stats = pstats.Stats(profiler, stream=stream)
    stats.sort_stats("cumulative")
    stats.print_stats(20)  # top 20 functions
    return result, stream.getvalue()
```

### py-spy (production-safe sampling)

```bash
# Attach to running process
py-spy top --pid <PID>

# Record flame graph
py-spy record -o profile.svg --pid <PID> --duration 30

# Profile a script
py-spy record -o profile.svg -- python my_service.py
```

### Memory profiling with memray

```bash
# Record memory allocations
memray run my_script.py

# Generate flame graph
memray flamegraph memray-my_script.bin -o memory.html

# Generate summary
memray summary memray-my_script.bin
```

### Node.js profiling

```bash
# Built-in V8 profiler
node --prof app.js
node --prof-process isolate-*.log > profile.txt

# Clinic.js (comprehensive)
npx clinic doctor -- node app.js
npx clinic flame -- node app.js
npx clinic bubbleprof -- node app.js

# Heap snapshot for memory leaks
node --inspect app.js
# Then in Chrome DevTools: Memory tab > Take heap snapshot
```

---

## Benchmarking

### HTTP benchmarking tools

| Tool | Strength |
|------|----------|
| `wrk` | High-throughput HTTP benchmarking |
| `hey` | Simple HTTP load generator |
| `k6` | Scriptable, CI-integrated |
| `ab` | Apache Bench — quick and simple |

### wrk usage

```bash
# Basic benchmark: 12 threads, 400 connections, 30 seconds
wrk -t12 -c400 -d30s http://localhost:8000/api/health

# With Lua script for POST requests
wrk -t4 -c100 -d30s -s post.lua http://localhost:8000/api/experiments
```

### Python micro-benchmarking

```python
import timeit
import statistics


def benchmark(fn, iterations=1000, warmup=100):
    """Benchmark a function with warmup and statistical summary."""
    # Warmup
    for _ in range(warmup):
        fn()

    # Measure
    times = []
    for _ in range(iterations):
        start = timeit.default_timer()
        fn()
        elapsed = (timeit.default_timer() - start) * 1000  # ms
        times.append(elapsed)

    return {
        "p50_ms": statistics.median(times),
        "p95_ms": sorted(times)[int(len(times) * 0.95)],
        "p99_ms": sorted(times)[int(len(times) * 0.99)],
        "mean_ms": statistics.mean(times),
        "stdev_ms": statistics.stdev(times),
        "iterations": iterations,
    }
```

---

## Performance Budgets

### Setting budgets

| Metric | Budget | Measurement |
|--------|--------|-------------|
| API response (p95) | < 200ms | k6 / Locust |
| API response (p99) | < 500ms | k6 / Locust |
| Page load (LCP) | < 2.5s | Lighthouse |
| Time to Interactive | < 3.5s | Lighthouse |
| Bundle size (JS) | < 250KB gzipped | webpack-bundle-analyzer |
| Database query | < 50ms (p95) | query logging |
| Memory per request | < 10MB | profiler |

### Performance regression detection

```python
from dataclasses import dataclass


@dataclass
class PerformanceBaseline:
    metric_name: str
    p50_ms: float
    p95_ms: float
    p99_ms: float
    regression_threshold: float = 0.10  # 10% regression triggers alert

    def is_regression(self, new_p95: float) -> bool:
        return new_p95 > self.p95_ms * (1 + self.regression_threshold)

    def is_improvement(self, new_p95: float) -> bool:
        return new_p95 < self.p95_ms * (1 - self.regression_threshold)
```

---

## Database Query Optimisation

### Query analysis checklist

- [ ] Run `EXPLAIN ANALYZE` on slow queries
- [ ] Check for missing indexes on WHERE/JOIN columns
- [ ] Look for N+1 query patterns (use eager loading)
- [ ] Check for sequential scans on large tables
- [ ] Verify connection pool sizing (too small = queuing, too large = memory)
- [ ] Check for lock contention under concurrent load

### Connection pool sizing

```python
# Rule of thumb: connections = (2 * CPU_cores) + disk_spindles
# For SSDs: connections = (2 * CPU_cores) + 1
# For most services: 10-20 connections per instance

POOL_CONFIG = {
    "min_size": 5,
    "max_size": 20,
    "max_idle_time": 300,       # seconds
    "connection_timeout": 5.0,  # seconds
    "command_timeout": 30.0,    # seconds
}
```

---

## Chaos Experiment Performance Analysis

### Pre/post experiment comparison

```python
@dataclass
class ExperimentPerformanceReport:
    experiment_id: str
    baseline_p50: float
    baseline_p99: float
    during_fault_p50: float
    during_fault_p99: float
    recovery_p50: float
    recovery_p99: float
    recovery_time_s: float

    @property
    def degradation_factor(self) -> float:
        """How much worse p99 got during fault injection."""
        if self.baseline_p99 == 0:
            return float("inf")
        return self.during_fault_p99 / self.baseline_p99

    @property
    def recovered(self) -> bool:
        """Did performance return to within 10% of baseline?"""
        return self.recovery_p99 <= self.baseline_p99 * 1.10
```

---

## Load Test Types — Detailed Taxonomy

Beyond the summary table above, understand the purpose and design of each test type:

| Type | Goal | Load profile | Key question answered | Duration |
|------|------|-------------|----------------------|----------|
| **Load test** | Validate expected traffic | Sustain expected VU count | "Can we handle normal traffic for a sustained period?" | 10-30 min |
| **Stress test** | Find breaking point | Ramp beyond expected capacity | "Where does the system break and how does it fail?" | 10-30 min |
| **Spike test** | Test sudden traffic surge | Instant jump to high VUs, then drop | "Does auto-scaling react fast enough? Do we shed load gracefully?" | 5-10 min |
| **Soak test** | Find slow-burn issues | Sustained expected load over hours/days | "Are there memory leaks, connection leaks, or resource exhaustion over time?" | 2-24 hours |
| **Volume test** | Test data handling | Normal VUs but with large payloads or data sets | "Can the system handle large data volumes (uploads, batch processing, big DB tables)?" | 30-60 min |
| **Breakpoint test** | Find maximum capacity | Incremental ramp until failure | "What is the absolute maximum throughput before errors appear?" | 15-30 min |

### Choosing the right test

```
New feature or endpoint?       --> Smoke test first, then Load test
Preparing for a known event?   --> Load test at expected peak, then Stress test
Deploying to production?       --> Load test + Soak test (minimum 2 hours)
Investigating slow degradation? --> Soak test (8+ hours)
Capacity planning?             --> Breakpoint test
Auto-scaling validation?       --> Spike test
Data migration or bulk import? --> Volume test
```

---

## Common Performance Anti-Patterns

| Anti-pattern | Symptom | Detection | Fix |
|---|---|---|---|
| **N+1 query problem** | Linear growth in query count with result set size | Query logging shows repeated similar queries; ORM lazy-loading | Use eager loading / joins; batch queries; add a data loader |
| **Synchronous blocking in async code** | Event loop stalls, high tail latency, low throughput despite low CPU | Profiler shows `await` on blocking I/O (file, network, CPU-bound) | Offload blocking calls to a thread pool; use async-native libraries |
| **Connection pool exhaustion** | Requests queue, then timeout; "too many connections" errors | Pool wait-time metrics spike; active connections = max pool size | Return connections promptly (use context managers); size pool correctly; add circuit breaker |
| **Cache stampede (thundering herd)** | Sudden latency/load spike when a popular cache key expires | Cache miss rate spikes; backend load multiplies on expiry | Use stale-while-revalidate; probabilistic early expiry; single-flight / lock-based refresh |
| **Unbounded queue growth** | Memory grows until OOM; processing delay increases indefinitely | Queue depth metric grows without bound; memory usage climbs | Set max queue size; apply backpressure; reject or shed load |
| **Missing pagination** | Response time grows with data volume; eventual timeouts | Slow responses on list endpoints; large response bodies | Add cursor or offset pagination; set a max page size; enforce it server-side |
| **Over-fetching (SELECT *)** | Unnecessary I/O and serialisation overhead; larger payloads | Query plans show full row scans; response bodies contain unused fields | Select only needed columns; use projections; consider GraphQL for client-driven field selection |
| **No warmup before measurement** | Misleading benchmark results (JIT, pool init, cache cold) | First N requests are slow, then stabilise | Add warmup phase to all load tests; exclude warmup from metrics |

---

## Performance Budget — CI Enforcement

### Define budgets per endpoint

```python
PERFORMANCE_BUDGETS = {
    "GET /api/experiments": {"p99_ms": 200, "max_body_kb": 50},
    "POST /api/experiments": {"p99_ms": 500, "max_body_kb": 10},
    "GET /api/health": {"p99_ms": 50, "max_body_kb": 1},
    "page:/dashboard": {"lcp_ms": 2500, "bundle_kb": 200, "tti_ms": 3500},
}
```

### Budget enforcement in CI

- Run a lightweight load test (smoke level) on every pull request
- Compare results against the budget table
- **Fail the build** if any budget is exceeded
- Track budget trends over time — catch slow regressions before they breach the threshold

```python
def check_budget(endpoint: str, measured_p99: float, budgets: dict) -> tuple[bool, str]:
    """Check if an endpoint's measured p99 is within budget."""
    budget = budgets.get(endpoint)
    if budget is None:
        return False, f"No budget defined for {endpoint}"
    limit = budget["p99_ms"]
    if measured_p99 > limit:
        return False, f"{endpoint}: p99={measured_p99:.0f}ms exceeds budget {limit}ms"
    return True, f"{endpoint}: p99={measured_p99:.0f}ms within budget {limit}ms"
```

### Budget allocation across components

When a request traverses multiple components, allocate the total budget:

```
Total budget: 200ms (p99)
  |-- API gateway:     10ms  (5%)
  |-- Auth middleware:  20ms  (10%)
  |-- Business logic:  50ms  (25%)
  |-- Database query:  80ms  (40%)
  |-- Serialisation:   20ms  (10%)
  |-- Network/other:   20ms  (10%)
```

If any component exceeds its allocation, investigate that component first. This prevents "it is slow but we do not know where" situations.

---

## Anti-Patterns

| Anti-pattern | Fix |
|---|---|
| Load testing only happy path | Include error paths, auth flows, edge cases |
| No warmup period | JIT, connection pools, caches need warmup |
| Testing from same machine as service | Separate load generator from system under test |
| Ignoring tail latency (p99/p999) | Always measure and alert on p99 |
| Profiling in production with high overhead tools | Use sampling profilers (py-spy) in production |
| Fixed connection pool too large | Size pool to `(2 * cores) + 1`, monitor wait times |
| No baseline before chaos experiment | Always capture steady-state metrics first |
| Benchmarking with debug/dev mode on | Profile with production-equivalent configuration |
