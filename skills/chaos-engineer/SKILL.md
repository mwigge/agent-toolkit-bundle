---
name: chaos-engineer
description: >
  Chaos engineering discipline: experiment design, hypothesis formation,
  blast radius control, safety mechanisms, GameDay planning, failure mode
  analysis, and steady-state validation. Activate when designing experiments,
  planning GameDays, or building chaos infrastructure.
version: 1.0.0
argument-hint: "[experiment type, failure mode, or target system]"
---

# Chaos Engineer Skill

## When to activate
- Designing new chaos experiments
- Formulating hypotheses about system resilience
- Planning blast radius and safety mechanisms
- Organising GameDay exercises
- Analysing failure modes and cascading failures
- Building chaos experiment infrastructure
- Reviewing experiment results and proposing improvements

---

## Chaos Engineering Principles

1. **Build a hypothesis around steady-state behaviour** — define what "normal" looks like before injecting faults
2. **Vary real-world events** — inject faults that actually happen in production (not just theoretical failures)
3. **Run experiments in production** — start in staging, graduate to production with canary scope
4. **Automate experiments to run continuously** — chaos experiments should run in CI/CD, not just during GameDays
5. **Minimise blast radius** — scope experiments as tightly as possible; widen gradually

---

## Experiment Design Framework

### 1. Steady-state hypothesis

Every experiment starts with a falsifiable hypothesis:

> "When [fault] is injected into [target], the system will continue to [expected behaviour] within [SLO thresholds]."

Examples:
- "When the payment service is unavailable for 30s, the checkout flow will return a graceful error to users and recover within 10s of service restoration."
- "When 200ms of latency is added to the database connection, API p99 latency will remain below 1000ms."
- "When 1 of 3 API replicas is terminated, the load balancer will route traffic to healthy replicas with zero user-visible errors."

### 2. Experiment specification

```python
from dataclasses import dataclass, field
from enum import Enum


class FaultType(str, Enum):
    LATENCY = "latency"
    ERROR = "error"
    RESOURCE_EXHAUSTION = "resource_exhaustion"
    NETWORK_PARTITION = "network_partition"
    PROCESS_KILL = "process_kill"
    DISK_FULL = "disk_full"
    DNS_FAILURE = "dns_failure"
    CLOCK_SKEW = "clock_skew"
    DEPENDENCY_UNAVAILABLE = "dependency_unavailable"


class ExperimentScope(str, Enum):
    UNIT = "unit"           # single instance
    SERVICE = "service"     # all instances of one service
    ZONE = "zone"           # availability zone
    REGION = "region"       # entire region


@dataclass
class ExperimentSpec:
    name: str
    hypothesis: str
    fault_type: FaultType
    target_service: str
    scope: ExperimentScope
    duration_seconds: int
    blast_radius: str              # human-readable description
    abort_conditions: list[str]    # conditions that trigger immediate rollback
    rollback_procedure: str
    prerequisites: list[str] = field(default_factory=list)
    steady_state_probes: list[str] = field(default_factory=list)

    def validate(self) -> list[str]:
        """Return list of validation errors."""
        errors: list[str] = []
        if not self.hypothesis:
            errors.append("Hypothesis is required")
        if not self.abort_conditions:
            errors.append("At least one abort condition is required")
        if not self.rollback_procedure:
            errors.append("Rollback procedure is required")
        if self.duration_seconds > 3600:
            errors.append("Duration exceeds 1 hour maximum")
        if self.scope == ExperimentScope.REGION and not any(
            "approval" in p.lower() for p in self.prerequisites
        ):
            errors.append("Region-scope experiments require explicit approval")
        return errors
```

### 3. Chaos Toolkit experiment JSON structure

```json
{
  "title": "Verify API resilience when database has 200ms latency",
  "description": "Inject 200ms latency on DB connections and verify API p99 stays below 1s",
  "tags": ["database", "latency", "api"],
  "steady-state-hypothesis": {
    "title": "API responds within SLO",
    "probes": [
      {
        "name": "api-latency-within-slo",
        "type": "probe",
        "tolerance": true,
        "provider": {
          "type": "python",
          "module": "chaostooling.probes.http",
          "func": "probe_latency_within_threshold",
          "arguments": {
            "url": "${API_URL}/api/health",
            "threshold_ms": 1000
          }
        }
      },
      {
        "name": "error-rate-acceptable",
        "type": "probe",
        "tolerance": true,
        "provider": {
          "type": "python",
          "module": "chaostooling.probes.metrics",
          "func": "probe_error_rate_below",
          "arguments": {
            "threshold": 0.01
          }
        }
      }
    ]
  },
  "method": [
    {
      "name": "inject-db-latency",
      "type": "action",
      "provider": {
        "type": "python",
        "module": "chaostooling.actions.network",
        "func": "inject_latency",
        "arguments": {
          "target": "postgres",
          "delay_ms": 200,
          "duration_s": 120
        }
      }
    }
  ],
  "rollbacks": [
    {
      "name": "remove-db-latency",
      "type": "action",
      "provider": {
        "type": "python",
        "module": "chaostooling.actions.network",
        "func": "remove_latency",
        "arguments": {
          "target": "postgres"
        }
      }
    }
  ]
}
```

---

## Fault Injection Catalogue

### Application layer

| Fault | Tool | Use case |
|-------|------|----------|
| HTTP error injection | Envoy fault filter, Istio | Test error handling in callers |
| Latency injection | tc, Envoy, Toxiproxy | Test timeout and retry behaviour |
| Exception injection | Code-level toggle | Test error paths |
| Thread pool exhaustion | Custom action | Test bulkhead isolation |

### Infrastructure layer

| Fault | Tool | Use case |
|-------|------|----------|
| Process kill | `kill -9`, Chaos Toolkit | Test restart/recovery |
| CPU stress | `stress-ng` | Test under resource contention |
| Memory pressure | `stress-ng --vm` | Test OOM handling |
| Disk fill | `fallocate` | Test disk-full error handling |
| Network partition | `iptables`, `tc` | Test split-brain, failover |
| DNS failure | `/etc/hosts`, CoreDNS | Test DNS resolution failures |

### Data layer

| Fault | Tool | Use case |
|-------|------|----------|
| DB connection limit | `pgbouncer` config | Test connection pool exhaustion |
| Slow queries | `pg_sleep()` | Test query timeout handling |
| Replica lag | Artificial delay | Test read-after-write consistency |
| Cache eviction | `redis-cli FLUSHALL` | Test cache-miss thundering herd |

---

## Blast Radius Control

### Scoping mechanisms

| Level | Mechanism | Example |
|-------|-----------|---------|
| **Request** | Header-based routing | `X-Chaos: latency-200ms` |
| **User** | Percentage-based | 1% of users see degraded path |
| **Instance** | Target single pod/instance | Kill 1 of N replicas |
| **Service** | All instances of one service | Network partition a service |
| **Zone** | Availability zone failure | Simulate AZ outage |

### Safety mechanisms

```python
from dataclasses import dataclass
from typing import Callable


@dataclass
class SafetyMechanism:
    """Safety controls for chaos experiments."""

    # Kill switch: immediately halt and rollback
    kill_switch_url: str          # e.g., POST /api/chaos/kill

    # Abort conditions (checked every probe interval)
    max_error_rate: float = 0.05  # abort if error rate > 5%
    max_latency_p99_ms: float = 2000  # abort if p99 > 2s
    max_duration_s: int = 3600    # absolute maximum experiment duration

    # Notification
    notification_channels: list[str] | None = None  # Slack channels, PagerDuty

    # Approval
    requires_approval: bool = False  # for production experiments
    approved_by: str | None = None


def abort_check(
    current_error_rate: float,
    current_p99_ms: float,
    elapsed_s: float,
    safety: SafetyMechanism,
) -> tuple[bool, str]:
    """Check if experiment should be aborted. Returns (should_abort, reason)."""
    if current_error_rate > safety.max_error_rate:
        return True, f"Error rate {current_error_rate:.2%} exceeds {safety.max_error_rate:.2%}"
    if current_p99_ms > safety.max_latency_p99_ms:
        return True, f"p99 latency {current_p99_ms:.0f}ms exceeds {safety.max_latency_p99_ms:.0f}ms"
    if elapsed_s > safety.max_duration_s:
        return True, f"Duration {elapsed_s:.0f}s exceeds maximum {safety.max_duration_s}s"
    return False, ""
```

---

## GameDay Planning

### GameDay structure

A GameDay is a structured team exercise where chaos experiments are run in a controlled environment to test resilience, incident response, and observability.

#### Pre-GameDay (1-2 weeks before)

- [ ] Define objectives: what are we testing?
- [ ] Select experiments from the experiment catalogue
- [ ] Verify all experiments have been run in staging
- [ ] Confirm rollback procedures are tested
- [ ] Brief the team: roles, timeline, communication channels
- [ ] Notify stakeholders (product, support, management)
- [ ] Set up war room (virtual or physical)
- [ ] Verify observability: dashboards, alerts, logging

#### GameDay execution

| Time | Activity |
|------|----------|
| T-30m | Team assembles, review objectives and safety procedures |
| T-15m | Verify steady-state metrics, confirm all systems nominal |
| T-0 | Start first experiment |
| T+duration | Evaluate results, discuss observations |
| T+break | 10-minute break between experiments |
| Repeat | Run next experiment |
| End | Final debrief, collect observations |

#### Post-GameDay (within 1 week)

- [ ] Write GameDay report with findings
- [ ] Create tickets for identified weaknesses
- [ ] Update runbooks based on observations
- [ ] Share findings with wider team
- [ ] Schedule follow-up experiments for unresolved issues

### GameDay report template

```markdown
## GameDay Report — {DATE}

### Objectives
- {objective 1}
- {objective 2}

### Experiments Run
| # | Experiment | Result | Finding |
|---|-----------|--------|---------|
| 1 | {name} | PASS/FAIL | {observation} |

### Key Findings
1. {finding}
2. {finding}

### Action Items
- [ ] {action} — owner: {name}, due: {date}
- [ ] {action} — owner: {name}, due: {date}

### Metrics Summary
| Metric | Baseline | During fault | Recovery |
|--------|----------|-------------|----------|
| p99 latency | {value} | {value} | {value} |
| Error rate | {value} | {value} | {value} |
| Recovery time | N/A | N/A | {value} |
```

---

## Failure Mode Analysis

### FMEA (Failure Mode and Effects Analysis)

For each component, enumerate:

| Component | Failure mode | Cause | Effect | Severity (1-10) | Likelihood (1-10) | Detection (1-10) | RPN | Mitigation |
|-----------|-------------|-------|--------|-----------------|-------------------|------------------|-----|-----------|
| Database | Connection timeout | Network issue | API errors | 8 | 4 | 3 | 96 | Circuit breaker + retry |
| Cache | Complete eviction | Memory pressure | Slow responses | 5 | 3 | 2 | 30 | Warm cache on deploy |

RPN = Severity x Likelihood x Detection (lower detection score = easier to detect = better)

Priority: address highest RPN items first.

### Cascading failure analysis

```
[Service A] --depends-on--> [Service B] --depends-on--> [Database]
                                |
                                +--depends-on--> [Cache]

If Database fails:
  1. Service B: connection errors, circuit breaker opens after 5 failures
  2. Service A: gets errors from Service B, falls back to cached data
  3. Users: see stale data (acceptable) or degraded experience

If Cache fails:
  1. Service B: falls through to Database (increased load)
  2. Database: may hit connection limits under thundering herd
  3. Mitigation: rate-limit cache-miss path, warm cache on recovery
```

---

## Experiment Maturity Model

| Level | Description | Practices |
|-------|-------------|-----------|
| **0 — Ad hoc** | No chaos engineering | Incidents are the only "experiments" |
| **1 — Reactive** | Manual experiments after incidents | Post-incident chaos experiments |
| **2 — Proactive** | Regular GameDays | Quarterly GameDays, experiment catalogue |
| **3 — Systematic** | Automated experiments in CI/CD | Experiments run on every deploy |
| **4 — Advanced** | Continuous chaos in production | Automated fault injection with auto-remediation |

---

## Security Chaos Scenarios

Test security mechanisms under failure conditions — not penetration testing, but verifying that security controls degrade gracefully.

| Scenario | Injection method | What to validate |
|----------|-----------------|------------------|
| **Authentication service unavailable** | Network partition the auth service | Requests are rejected (fail-closed), not silently allowed |
| **Authorization policy failure** | Return malformed policy responses | Service denies access by default (fail-closed) |
| **Certificate expiry** | Deploy expired TLS certificates | Connections fail with clear errors, alerts fire, no silent fallback to plaintext |
| **Certificate rotation under load** | Rotate certificates while traffic is flowing | Zero-downtime rotation, no dropped connections during handshake |
| **Secret rotation during active connections** | Rotate database credentials mid-session | Active connections continue; new connections use new credentials |
| **Rate limiter failure** | Disable or crash the rate limiting component | Upstream service handles increased load gracefully or fails closed |
| **Quota exhaustion** | Consume all API quota/rate limit tokens | Clients receive clear 429 responses, not 500s; backpressure propagates |
| **Token validation latency** | Inject 5s latency on token validation endpoint | Requests time out cleanly, users see appropriate error, no cascading auth failures |

### Key principle

Security mechanisms must **fail closed** — if the auth service is down, deny access rather than granting it. Chaos experiments validate this assumption.

---

## Data System Chaos

Extend the data layer fault catalogue with data-integrity and capacity scenarios.

| Scenario | Injection method | What to validate |
|----------|-----------------|------------------|
| **Replication lag** | Inject artificial delay on replica | Read-after-write consistency handled (route reads to primary, or tolerate staleness) |
| **Data corruption detection** | Flip bits in stored data, inject bad checksums | Application detects corruption via checksum validation; does not serve corrupt data |
| **Backup/restore under load** | Trigger backup while system is under peak load | Backup completes without degrading request latency beyond SLO |
| **Restore from backup** | Restore a backup to a parallel environment | Data integrity verified, recovery time within RTO target |
| **Storage quota exhaustion** | Fill disk to 95%, then 100% | Application returns clear errors, does not corrupt existing data, alerts fire before 100% |
| **Connection pool exhaustion** | Consume all connections (hold open without releasing) | New requests get a clear timeout error, circuit breaker opens, pool recovers when connections are released |
| **Write-ahead log (WAL) growth** | Block WAL archiving | Database alerts on WAL growth, does not crash; application handles read-only mode |

### Checksum validation pattern

```python
import hashlib


def verify_data_integrity(data: bytes, expected_checksum: str) -> bool:
    """Verify data has not been corrupted in storage or transit."""
    actual = hashlib.sha256(data).hexdigest()
    return actual == expected_checksum
```

---

## Steady-State Validation

Robust steady-state validation goes beyond a simple hypothesis — it is continuous, quantitative, and statistically aware.

### 1. Define steady state as measurable SLIs

Before any experiment, capture concrete baselines:

| SLI | Measurement | Example baseline |
|-----|-------------|-----------------|
| Request success rate | `successful_requests / total_requests` | 99.95% |
| Latency p50 / p99 | Histogram from metrics pipeline | 45ms / 180ms |
| Error rate | `5xx_responses / total_responses` | 0.02% |
| Throughput | Requests per second | 1200 rps |
| Saturation | CPU / memory / connection pool utilisation | CPU 40%, pool 60% |

### 2. Continuous monitoring during experiment

- Probe steady-state SLIs at a fixed interval (e.g., every 10 seconds) throughout the experiment
- Stream probe results to a time-series store for post-experiment analysis
- Abort immediately if any SLI crosses the abort threshold (see Safety Mechanisms)

### 3. Automated comparison: pre vs during vs post

```python
from dataclasses import dataclass


@dataclass
class PhaseMetrics:
    phase: str          # "baseline", "during_fault", "recovery"
    p50_ms: float
    p99_ms: float
    error_rate: float
    throughput_rps: float
    duration_s: float


def compare_phases(
    baseline: PhaseMetrics,
    during: PhaseMetrics,
    post: PhaseMetrics,
    degradation_tolerance: float = 0.20,  # 20% degradation allowed
) -> dict:
    """Compare metrics across experiment phases."""
    return {
        "p99_degradation": (during.p99_ms - baseline.p99_ms) / baseline.p99_ms,
        "error_rate_increase": during.error_rate - baseline.error_rate,
        "throughput_drop": (baseline.throughput_rps - during.throughput_rps) / baseline.throughput_rps,
        "recovery_within_baseline": post.p99_ms <= baseline.p99_ms * (1 + degradation_tolerance),
        "hypothesis_held": during.error_rate <= baseline.error_rate + degradation_tolerance,
    }
```

### 4. Statistical significance of deviation

Not every metric change is meaningful. Use statistical tests to distinguish real degradation from normal variance:

- Collect baseline samples over a sufficient window (at least 5 minutes, ideally 30+)
- During the experiment, compare rolling windows against baseline distribution
- Use a two-sample test (e.g., Welch's t-test or Mann-Whitney U) to determine if the difference is statistically significant (p < 0.05)
- Report effect size alongside p-values — a statistically significant but tiny degradation may not be actionable

| Signal | Interpretation | Action |
|--------|---------------|--------|
| Large effect + significant | Real degradation | Investigate and remediate |
| Small effect + significant | Detectable but minor | Log, do not alarm |
| Large effect + not significant | Noisy data or short window | Extend observation window |
| Small effect + not significant | No meaningful change | Hypothesis holds |

---

## Anti-Patterns

| Anti-pattern | Fix |
|---|---|
| No hypothesis before running experiment | Always start with "we believe X will happen when Y" |
| Running experiments without observability | Verify dashboards and alerts are working first |
| Skipping staging and going straight to production | Graduate experiments: dev -> staging -> canary -> production |
| No rollback plan | Every experiment needs a tested rollback |
| "Break everything" mentality | Chaos engineering is controlled, scientific experimentation |
| Only running experiments during GameDays | Automate experiments to run continuously |
| Not sharing results | Publish findings, update runbooks, create tickets |
| Experiments without abort conditions | Define abort thresholds before starting |
