# Runbook: [Service Name] — [Failure Mode Title]

> **Service**: [service-name]
> **Version**: [1.0.0]
> **Last reviewed**: [YYYY-MM-DD]
> **Reviewed by**: [@engineer]
> **Runbook for**: [One sentence describing what failure this addresses]

---

## Trigger Condition

**Alert name**: `[alert_name_in_prometheus_or_grafana]`

**Condition**: `[metric expression, e.g. error rate > 5% for 5 consecutive minutes]`

**What you will observe**:
- [Observable symptom 1, e.g. "HTTP 5xx responses from /api/v1/payments"]
- [Observable symptom 2, e.g. "P99 latency > 2s on payment-service Grafana dashboard"]
- [Observable symptom 3, e.g. "Errors in Slack #alerts channel"]

---

## Severity

**Default severity**: [SEV1 / SEV2 / SEV3]

**Escalate to SEV1 immediately if**:
- [Condition, e.g. "Error rate exceeds 50% for more than 2 minutes"]
- [Condition, e.g. "Data loss or corruption is suspected"]
- [Condition, e.g. "More than 3 services are affected"]

---

## Immediate Actions

Execute these steps in order. Do not skip steps unless explicitly noted.

1. **Acknowledge the alert** in PagerDuty / OpsGenie within 5 minutes.

2. **Declare the incident** in Slack `#incidents`:
   ```
   INCIDENT DECLARED [SEV]: [service-name] — [symptom].
   IC: @you. Runbook: [this URL]. Investigating.
   ```

3. **Open the dashboard**: [Grafana dashboard URL]

4. **Check recent deployments**:
   ```bash
   kubectl rollout history deployment/[service-name] --namespace=production
   ```
   If a deployment occurred in the last 30 minutes, proceed to step 5. Otherwise, skip to step 6.

5. **Roll back the deployment** (if applicable):
   ```bash
   kubectl rollout undo deployment/[service-name] --namespace=production
   kubectl rollout status deployment/[service-name] --namespace=production --timeout=5m
   ```
   Wait 2 minutes, then check the error rate. If resolved, proceed to verification steps. If not, continue.

6. **Check service health**:
   ```bash
   kubectl get pods --namespace=production -l app=[service-name]
   kubectl logs --namespace=production deployment/[service-name] --tail=100 --since=10m
   ```

7. **Check upstream dependencies**:
   - [Dependency 1, e.g. database]: `[command or dashboard link]`
   - [Dependency 2, e.g. external API]: `[command or dashboard link]`

8. **If upstream dependency is failing**:
   - Enable circuit breaker / fallback mode:
     ```bash
     [command to toggle feature flag or circuit breaker]
     ```
   - Notify the owning team: ping `@[team-name]` in `#[channel]`

9. **If service is OOMKilled or crashing**:
   ```bash
   kubectl describe pod --namespace=production -l app=[service-name] | grep -A 10 "Last State"
   # Scale up if resource pressure:
   kubectl scale deployment/[service-name] --replicas=5 --namespace=production
   ```

10. **Post first stakeholder update** (if SEV1/2):
    ```
    UPDATE [HH:MM UTC]: We have identified [what]. We are [action]. Next update in 30 minutes.
    ```

---

## Escalation Path

If the runbook steps do not resolve the incident within 20 minutes, escalate immediately.

| Condition | Escalation target | Contact method |
|-----------|------------------|----------------|
| Database issue suspected | [DBA team name] | PagerDuty: [schedule name] |
| Security breach suspected | [Security team] | PagerDuty: [schedule name] — do not post details in public Slack |
| External dependency failing | [Vendor support] | [Support URL / phone] |
| Service not recoverable after rollback | [Engineering Manager] | PagerDuty / direct message |

---

## Rollback Procedure

### Application rollback (Kubernetes)

```bash
# Roll back to the previous deployment
kubectl rollout undo deployment/[service-name] --namespace=production

# Roll back to a specific revision
kubectl rollout undo deployment/[service-name] --to-revision=N --namespace=production

# Verify the rollback
kubectl rollout status deployment/[service-name] --namespace=production --timeout=5m
```

### Database migration rollback

```bash
# List migration history
pdm run alembic history --verbose

# Roll back one migration
pdm run alembic downgrade -1

# Roll back to a specific revision
pdm run alembic downgrade <revision_id>
```

> **WARNING**: Migration rollbacks may cause data loss if the migration included destructive changes. Confirm with the Database Administrator before executing.

### Feature flag rollback

```bash
# Disable the feature flag for all users
[feature flag CLI command, e.g.: unleash toggle --off [feature-name]]
```

---

## Verification Steps

Confirm the incident is resolved before declaring it closed.

1. **Error rate** is below SLO threshold for at least 5 consecutive minutes:
   ```promql
   sum(rate(http_requests_total{service="[service-name]",status=~"5.."}[5m]))
   / sum(rate(http_requests_total{service="[service-name]"}[5m]))
   ```
   Expected: < [threshold, e.g. 0.1%]

2. **P99 latency** is within SLO:
   ```promql
   histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{service="[service-name]"}[5m])))
   ```
   Expected: < [threshold, e.g. 500ms]

3. **All pods are running**:
   ```bash
   kubectl get pods --namespace=production -l app=[service-name]
   ```
   Expected: All pods in `Running` state, 0 restarts in the last 5 minutes.

4. **Synthetic test passes**:
   ```bash
   [curl / script that exercises the affected endpoint]
   ```

5. **Post resolution message** in `#incidents` and update the status page:
   ```
   RESOLVED [HH:MM UTC]: [service-name] is operating normally.
   Root cause: [brief summary]. PIR scheduled: [date].
   ```

---

## Related Links

| Resource | URL |
|----------|-----|
| Grafana dashboard | [URL] |
| Kibana / Loki logs | [URL] |
| Architecture diagram | [URL] |
| Previous incidents | [URL to incident history] |
| Deployment pipeline | [URL] |
| Service README | [URL] |
| PIR template | [URL to pir-template.md] |
