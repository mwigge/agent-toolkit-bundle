# GameDay Planning

Structured team exercises for testing resilience, incident response, and observability.

## GameDay structure

A GameDay is a structured team exercise where chaos experiments are run in a controlled environment to test resilience, incident response, and observability.

### Pre-GameDay (1-2 weeks before)

- [ ] Define objectives: what are we testing?
- [ ] Select experiments from the experiment catalogue
- [ ] Verify all experiments have been run in staging
- [ ] Confirm rollback procedures are tested
- [ ] Brief the team: roles, timeline, communication channels
- [ ] Notify stakeholders (product, support, management)
- [ ] Set up war room (virtual or physical)
- [ ] Verify observability: dashboards, alerts, logging

### GameDay execution

| Time | Activity |
|------|----------|
| T-30m | Team assembles, review objectives and safety procedures |
| T-15m | Verify steady-state metrics, confirm all systems nominal |
| T-0 | Start first experiment |
| T+duration | Evaluate results, discuss observations |
| T+break | 10-minute break between experiments |
| Repeat | Run next experiment |
| End | Final debrief, collect observations |

### Post-GameDay (within 1 week)

- [ ] Write GameDay report with findings
- [ ] Create tickets for identified weaknesses
- [ ] Update runbooks based on observations
- [ ] Share findings with wider team
- [ ] Schedule follow-up experiments for unresolved issues

## GameDay report template

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
