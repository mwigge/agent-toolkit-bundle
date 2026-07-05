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

## Reference Map

Load the companion file for full code on demand:

| Topic | Reference |
|-------|-----------|
| SLI/SLO, error budget, capacity, toil scoring code | `refs/frameworks.md` |
| Reliability patterns (retry, circuit breaker, bulkhead, timeout, health checks, feature flags) | `refs/reliability-patterns.md` |
| Chaos probes, actions, rollback, structured logging code | `refs/chaos-engineering.md` |

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

### SLO document checklist

Every new service must have an SLO document covering:

- [ ] Service name, owner team, tier (critical / standard / best-effort)
- [ ] SLIs with exact Prometheus/OTel queries
- [ ] SLO targets with rolling window (28d recommended)
- [ ] Error budget policy (what happens at 25%, 50%, 75%, 90% burn)
- [ ] Alert conditions with burn rate thresholds
- [ ] Escalation path: who gets paged vs. ticketed
- [ ] Review cadence: monthly SLO review meeting

See `refs/frameworks.md` for the `SLISpec` dataclass and `SLO_DEFAULTS` / `evaluate_slo` code.

---

## Error Budget Policy and Burn Rate Monitoring

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

See `refs/frameworks.md` for the `ErrorBudget` calculation code (budget ratio, remaining, burn rate).

---

## Capacity Planning

### Capacity planning process

1. **Baseline**: measure current resource usage (CPU, memory, disk, network, connections)
2. **Model**: establish relationship between traffic and resource consumption
3. **Forecast**: project traffic growth (linear, seasonal, event-driven)
4. **Threshold**: define headroom requirement (typically 30-40% free)
5. **Plan**: schedule scaling actions with lead time

### Capacity planning checklist

- [ ] Baseline metrics collected for all critical resources
- [ ] Growth rate estimated from last 3-6 months of data
- [ ] Seasonal patterns identified (month-end, quarter-end)
- [ ] Scaling lead time documented per resource type
- [ ] Headroom target defined (default: 30% free)
- [ ] Alert on saturation > 70% sustained for > 15 minutes
- [ ] Quarterly capacity review meeting scheduled

See `refs/frameworks.md` for the `CapacityModel` saturation/forecast code.

---

## Toil Reduction Framework

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

See `refs/frameworks.md` for the `ToilItem` scoring code (weekly cost, payback weeks).

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

Implement retry with exponential backoff + jitter, circuit breakers, bulkheads, timeouts, health/readiness endpoints, graceful degradation, and feature-flagged progressive rollout.

See `refs/reliability-patterns.md` for the full implementation of each pattern plus the graceful-degradation matrix and progressive-rollout stages.

---

## Chaos Probe Design

### Probe contract

Every probe must:
1. Be **read-only** — probes observe, never mutate
2. Return a typed result with status, value, and timestamp
3. Be idempotent — safe to call repeatedly
4. Have a timeout <= 10s

See `refs/chaos-engineering.md` for the `ProbeResult` type and the HTTP probe pattern.

---

## Chaos Action Design

### Action contract

Every chaos action must:
1. Accept `configuration: Configuration` and `secrets: Secrets` (Chaos Toolkit convention)
2. Return a dict with `status`, `output`, and `duration_ms`
3. Have a corresponding rollback action (or be self-healing)
4. Define `blast_radius` in its docstring or experiment JSON

See `refs/chaos-engineering.md` for the `inject_latency` action example.

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

Wrap chaos execution in a scope that automatically rolls back on exception or threshold breach, and always verify steady state afterwards.

See `refs/chaos-engineering.md` for the `chaos_scope` context manager.

---

## Structured Logging (Python)

Use `structlog` with JSON rendering — never `print()`. See `refs/chaos-engineering.md` for the `configure_structlog` setup and usage.

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

## References

- Reference: `refs/REFERENCES.md` — external documentation links for SRE practices and tooling
