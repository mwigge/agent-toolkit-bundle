# Production Readiness Review — {SERVICE_NAME}

**Date**: {DATE}
**Reviewer**: {REVIEWER}
**Service tier**: {critical | standard | best-effort}

---

## Service Overview

| Field | Value |
|-------|-------|
| Service name | {SERVICE_NAME} |
| Repository | {REPO_URL} |
| Owner team | {TEAM} |
| Language / Runtime | {e.g. Python 3.12, Node 22} |
| Dependencies | {list external services, databases, caches} |

---

## SLO Status

| SLI | Target | Current | Status |
|-----|--------|---------|--------|
| Availability | {e.g. 99.9%} | {measured} | PASS / FAIL |
| p99 latency | {e.g. < 500ms} | {measured} | PASS / FAIL |
| Error rate | {e.g. < 0.1%} | {measured} | PASS / FAIL |

Error budget policy documented: YES / NO

---

## Reliability Checklist

- [ ] Circuit breakers on all external dependencies
- [ ] Retry with exponential backoff + jitter on transient failures
- [ ] Timeouts on all outbound calls (connect: {X}s, read: {Y}s)
- [ ] Graceful degradation documented for each dependency failure
- [ ] Health endpoints: `/health` (liveness), `/ready` (readiness)
- [ ] Rate limiting on public-facing endpoints

---

## Observability Checklist

- [ ] OTel tracing with proper span attributes
- [ ] Structured JSON logging with correlation IDs
- [ ] Golden signal metrics emitting (rate, errors, latency, saturation)
- [ ] Dashboard exists: {DASHBOARD_URL}
- [ ] Alerts configured with burn rate thresholds
- [ ] Every alert has a linked runbook

---

## Deployment Checklist

- [ ] CI/CD pipeline: test, lint, security scan, deploy
- [ ] Canary deployment strategy
- [ ] Rollback procedure tested — ETA: {X} minutes
- [ ] Database migrations are backward-compatible
- [ ] Feature flags for risky features
- [ ] Deployment does not happen during active chaos experiments

---

## Security Checklist

- [ ] No hardcoded secrets — all from env vars / secret manager
- [ ] TLS on all communication
- [ ] Auth + authz on all endpoints
- [ ] Input validation on user-facing inputs
- [ ] Dependency scan: no critical CVEs
- [ ] Container image scanned

---

## Chaos Readiness

- [ ] At least one chaos experiment run in staging
- [ ] Blast radius documented
- [ ] Recovery time validated against MTTR SLO
- [ ] Kill switch available

---

## Decision

| Verdict | Notes |
|---------|-------|
| APPROVED / CONDITIONAL / BLOCKED | {explanation} |

Conditions (if any):
1. {condition}
2. {condition}
