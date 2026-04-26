# Post-Incident Review: [Incident Title]

> **Status**: Draft
> **Author**: [Name, @handle]
> **Reviewers**: [Names]
> **Date of incident**: [YYYY-MM-DD]
> **Date published**: [YYYY-MM-DD]

---

## Incident Summary

| Field | Value |
|-------|-------|
| **Title** | [Descriptive title] |
| **Severity** | [SEV1 / SEV2 / SEV3] |
| **Date/time detected** | [YYYY-MM-DD HH:MM UTC] |
| **Date/time resolved** | [YYYY-MM-DD HH:MM UTC] |
| **Total duration** | [H hours M minutes] |
| **Incident Commander** | [Name] |
| **Scribe** | [Name] |
| **Services affected** | [service-a, service-b] |

---

## Impact Assessment

| Metric | Value |
|--------|-------|
| Users affected | [N users / X%] |
| Transactions failed | [N] |
| Data at risk | [None / Describe] |
| Error budget consumed | [X% of monthly budget] |
| Estimated business impact | [£X / describe] |
| SLA breached | [Yes / No / Pending] |

---

## Timeline

All times UTC.

| Time (UTC) | Event | Actor |
|-----------|-------|-------|
| HH:MM | First symptom observable in metrics | Monitoring |
| HH:MM | Alert fired: [alert name] | Alerting system |
| HH:MM | On-call acknowledged | [Name] |
| HH:MM | Incident declared at [SEV] | [Name] |
| HH:MM | [Investigation action taken] | [Name] |
| HH:MM | [Hypothesis formed / tested] | [Name] |
| HH:MM | [Mitigation applied] | [Name] |
| HH:MM | [Mitigation outcome] | System |
| HH:MM | Root cause identified | [Name] |
| HH:MM | Fix deployed / rollback completed | [Name] |
| HH:MM | Service restored — metrics nominal | System |
| HH:MM | Incident declared resolved | [Name] |

---

## Root Cause — 5 Whys

**Presenting symptom**: [What users / monitoring observed]

| # | Why? | Because… |
|---|------|----------|
| 1 | Why did [symptom] occur? | [Answer] |
| 2 | Why did [answer 1] happen? | [Answer] |
| 3 | Why did [answer 2] happen? | [Answer] |
| 4 | Why did [answer 3] happen? | [Answer] |
| 5 | Why did [answer 4] happen? | **[Root cause]** |

**Root cause**: [One clear sentence]

---

## Contributing Factors

These factors amplified the incident or delayed resolution. They are not root causes but should be addressed.

1. **[Factor]** — [Why it contributed and its effect]
2. **[Factor]** — [Why it contributed and its effect]
3. **[Factor]** — [Why it contributed and its effect]

---

## What Went Well

> This section is mandatory. Reinforce good practices.

- [e.g. Alert fired within 2 minutes of the first anomalous signal]
- [e.g. Rollback was clean and completed in under 3 minutes]
- [e.g. Clear, regular communication kept all stakeholders informed without requiring them to interrupt the responders]

---

## What Went Poorly

> State facts, not blame. "The runbook was missing step X" not "Alice forgot to update the runbook."

- [e.g. The runbook did not cover this failure mode]
- [e.g. P99 latency alert was set at 2s — problem was visible at 800ms but did not fire]
- [e.g. No staging equivalent of the production configuration — issue could not have been caught in pre-prod]

---

## Action Items

All action items must have an owner and a due date. Ownerless items will not be acted upon.

| # | Action | Type | Owner | Due | Status |
|---|--------|------|-------|-----|--------|
| 1 | [Specific, verifiable action] | Prevention | [@owner] | [YYYY-MM-DD] | Open |
| 2 | [e.g. Lower alert threshold: P99 > 800ms for 3 min] | Detection | [@owner] | [YYYY-MM-DD] | Open |
| 3 | [e.g. Add runbook section for DB failover] | Mitigation | [@owner] | [YYYY-MM-DD] | Open |
| 4 | [e.g. Add chaos experiment: kill primary DB replica] | Resilience | [@owner] | [YYYY-MM-DD] | Open |

*Types: Prevention / Detection / Mitigation / Process / Resilience*

---

## Lessons Learned

> Written for engineers who were not involved. Plain language. 2–4 paragraphs.

[Paragraph 1: What happened and what users experienced]

[Paragraph 2: What caused it and why it wasn't caught earlier]

[Paragraph 3: What the team is doing to prevent recurrence and improve detection]

[Paragraph 4 (optional): Any broader architectural or process change this incident motivates]

---

## Appendix

### A — Alerts that fired

```
[Alert name and PromQL / query]
[Threshold and window]
[Time from symptom to alert: N minutes]
```

### B — Key log excerpts

```
[Timestamp] [level] [service] message with context
[...]
```

### C — Metrics at time of incident

[Embed or link to Grafana snapshots]

### D — Links

| Resource | URL |
|----------|-----|
| Incident Slack channel | [link] |
| Grafana dashboard (incident time range) | [link] |
| Deployment that preceded incident | [link] |
| Related Jira tickets | [CLS-XXX] |
| Previous related incidents | [link] |
