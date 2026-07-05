# Experiment Design and Steady-State Validation

Falsifiable hypotheses, experiment specifications, Chaos Toolkit encoding, and quantitative steady-state validation.

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
