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

Every experiment starts with a falsifiable steady-state hypothesis ("When [fault] is injected into [target], the system will continue to [expected behaviour] within [SLO thresholds]"), then encodes it as a validated `ExperimentSpec` and a Chaos Toolkit experiment definition with probes, method, and rollbacks.

See `refs/experiment-design.md` for the hypothesis templates, `ExperimentSpec` dataclass, Chaos Toolkit JSON structure, and the full steady-state validation method (measurable SLIs, phase comparison, statistical significance).

---

## Fault Injection Catalogue

Inject faults matched to real-world failures across the application, infrastructure, and data layers (HTTP errors, latency, process kills, resource stress, network partitions, DNS failures, connection-limit and replica-lag faults).

See `refs/fault-injection.md` for the full catalogue of faults, injection tools, and use cases by layer.

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

Run GameDays as structured team exercises: plan and rehearse in staging beforehand, execute on a timed schedule with safety briefings and steady-state verification, then debrief into a report with findings, action items, and a metrics summary.

See `refs/gameday.md` for the full pre/during/post checklists, execution timeline, and GameDay report template.

---

## Failure Mode Analysis

Enumerate failure modes with FMEA (scoring severity, likelihood, and detection into a Risk Priority Number) and trace cascading failures through service dependency chains to find mitigations.

See `refs/scenarios.md` for the FMEA table, cascading failure analysis, and the security and data-system chaos scenario catalogues.

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

## Domain Chaos Scenarios

Beyond generic faults, run targeted scenarios that verify security controls fail closed (auth outage, cert expiry, secret rotation, rate-limiter failure) and that data systems preserve integrity and capacity (replication lag, corruption detection, backup/restore, quota exhaustion, WAL growth).

See `refs/scenarios.md` for the full security and data-system scenario catalogues, the fail-closed principle, and the checksum validation pattern.

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

## References

- Reference: `refs/REFERENCES.md` — external documentation links for chaos engineering
