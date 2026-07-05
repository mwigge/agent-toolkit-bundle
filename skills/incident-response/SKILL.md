---
name: incident-response
description: Use when triaging, managing, or writing up incidents — severity classification, incident lifecycle, paging and escalation, and postmortems.
---

# Skill: Incident Response

## Severity Classification

| Severity | Definition | Response SLA | Example |
|----------|-----------|-------------|---------|
| **SEV1** | Total service outage OR data loss / data corruption risk OR security breach | Acknowledge in 5 min, all-hands | Payment service down, DB corruption detected, credential leak |
| **SEV2** | Major feature broken, >20% of users affected, or SLO breach imminent | Acknowledge in 5 min, incident team assembled | Checkout flow failing for a segment, API error rate >5% |
| **SEV3** | Degraded performance, workaround exists, <20% of users affected | Acknowledge in 30 min | Slow search results, non-critical job queue backed up |
| **SEV4** | Minor issue, cosmetic bug, no user impact | Next business day | Dashboard UI misalignment, log noise |

### Escalation triggers

- SEV3 → SEV2: issue persists >30 min or blast radius expands
- SEV2 → SEV1: data loss confirmed, payment flows affected, or >50% of users impacted
- Any severity: escalate immediately if you suspect a security breach

---

## Incident Lifecycle

```
Detection → Triage → Containment → Eradication → Recovery → Post-Incident Review
```

### 1. Detection

Sources: automated alerting (Prometheus/Grafana), synthetic monitoring, customer report, error rate spike, SLO burn rate alert.

First responder actions (within 5 minutes for SEV1/2):
1. Acknowledge the alert in PagerDuty / OpsGenie
2. Open an incident channel: `#incident-YYYY-MM-DD-<service>` in Slack
3. Post initial message: "INCIDENT DECLARED: [service] [symptom]. IC: @you. Investigating."
4. Assign Incident Commander (IC) and Scribe

### 2. Triage

- Determine severity using the classification table above
- Establish the blast radius: which services, users, and data are affected?
- Confirm the incident is real (not a monitoring false positive) before paging additional people
- Open the relevant runbook and begin mitigation steps

### 3. Containment

Goal: stop the bleeding. Reduce impact, even if you don't understand the root cause yet.

Actions:
- Roll back the most recent deployment if it coincides with the incident start
- Increase circuit-breaker thresholds to shed load
- Enable maintenance mode / feature flag off
- Scale up if resource exhaustion is suspected
- Isolate affected nodes or database replicas

**Do not attempt root cause analysis during containment** — stabilise first, understand later.

### 4. Eradication

Once contained, identify and remove the root cause. Use structured investigation:

- Examine logs around the time of first symptom (not first alert)
- Compare current state against baseline metrics
- Use distributed tracing to find the failing component
- Confirm with the 5 Whys technique

### 5. Recovery

- Restore service to full capacity
- Verify restoration with synthetic tests and real traffic
- Confirm SLIs are back within SLO thresholds
- Declare incident resolved and post resolution message in Slack and status page

### 6. Post-Incident Review (PIR)

- SEV1: within 48 hours
- SEV2: within 1 week
- Use the PIR template in `templates/pir-template.md`
- Blameless: the system failed, not the person; focus on systemic causes

---

## On-Call Duties

- **Acknowledge** within 5 minutes for SEV1/2; 30 minutes for SEV3
- **Declare** the incident in `#incidents`: "[SEV] INCIDENT: [service] [symptom]"
- **Assign roles**:
  - **Incident Commander (IC)**: owns the incident, makes decisions, delegates tasks
  - **Scribe**: records timeline, decisions, and action items in real time
  - **Subject Matter Expert (SME)**: provides technical depth; rotates as needed
- **Communication cadence**: stakeholder update every 30 minutes during SEV1/2; every hour during SEV3
- **Never** work in silence: narrate investigations in the incident channel

---

## Runbook Format

Every service must have runbooks for its top-5 failure modes. Each runbook contains:

1. **Service name and version**
2. **Trigger condition** — the alert or symptom that brings you here
3. **Severity** — default severity if this condition is observed
4. **Immediate mitigation steps** (numbered, imperative, no ambiguity)
5. **Escalation path** — who to call if the runbook doesn't resolve it
6. **Rollback procedure** — exact commands or UI steps
7. **Verification steps** — how to confirm the issue is resolved
8. **Related links** — dashboards, logs, architecture diagram, previous incidents

Rules:
- Runbooks must be testable: a new team member with production access should be able to execute them
- Review runbooks after every incident that revealed a gap
- Store runbooks in the repository next to the service, not in a wiki that can go stale

---

## SLO Breach Response

### Error budget burn rate alerting

Alert at two thresholds using multi-window, multi-burn-rate approach:

| Burn rate | Window | Severity | Response |
|-----------|--------|---------|---------|
| 14.4× | 1 hour | SEV1 | Page immediately |
| 14.4× | 5 min | SEV1 | Confirm and escalate |
| 6× | 6 hours | SEV2 | Page on-call |
| 3× | 3 days | SEV3 | Ticket + investigation |

### When error budget is ≤2% remaining

1. Freeze all non-critical deployments (engineering manager approval required to override)
2. Cancel planned chaos experiments
3. Review open bugs and technical debt impacting reliability
4. Present burn rate trend to product and engineering leadership

---

## Communication Standards

- **Status page updates** (Statuspage.io / Atlassian): post immediately on SEV1/2 declaration; update at every milestone; resolve promptly when restored
- **Stakeholder updates**: plain language, no jargon, quantify impact, give an ETA or "we don't have an ETA yet" (never fabricate one)
- **Blame-free language**: "The deployment triggered a configuration issue" not "John's deployment broke the system"
- **Avoid speculation** in public channels: say "We are investigating a potential issue with X" not "X is probably broken because Y"
- **Post-mortem sharing**: share PIR findings in an engineering all-hands or newsletter — incidents are learning opportunities

---

## Chaos Engineering vs Real Incidents

| Aspect | Planned chaos experiment | Real incident |
|--------|--------------------------|---------------|
| Declaration | Post in #chaos-experiments before start | Declare in #incidents immediately |
| Kill switch | Mandatory — must be tested before experiment | N/A |
| Freeze windows | Never run during freeze | Investigate freeze impact |
| Communication | Notify affected teams 24h in advance | Notify stakeholders as soon as severity is assessed |
| Runbook | Experiment runbook with hypothesis and abort criteria | Service runbook |
| PIR | Experiment report (baseline → result → resilience score delta) | Full PIR if unexpected behaviour |

**Kill switch requirements**:
- Every chaos experiment must have a one-command abort that restores steady state
- Kill switch must be tested in a non-production environment before any production experiment
- The experiment runner must be reachable by the IC during the experiment window
- Never run experiments during deployment freeze windows, peak traffic periods, or public holidays

---

## Useful Queries During Incidents

```promql
# Error rate (5xx) over the last 5 minutes
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))

# Error budget burn rate (1 hour window, 30-day SLO)
1 - (
  sum(rate(http_requests_total{status!~"5.."}[1h]))
  / sum(rate(http_requests_total[1h]))
) / (1 - 0.999)  # replace 0.999 with your SLO target

# P99 latency
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
```
