# GameDay Plan — {DATE}

## Objectives
- {objective_1}
- {objective_2}

## Scope
- **Environment**: {staging / production-canary / production}
- **Target services**: {service_1, service_2}
- **Duration**: {estimated total time}
- **Kill switch**: {URL or procedure to abort all experiments}

## Team
| Role | Person | Contact |
|------|--------|---------|
| GameDay lead | {name} | {contact} |
| Incident commander | {name} | {contact} |
| Observer/scribe | {name} | {contact} |
| SRE on-call | {name} | {contact} |

## Pre-GameDay Checklist
- [ ] All experiments tested in staging
- [ ] Rollback procedures verified
- [ ] Dashboards bookmarked and shared
- [ ] Communication channel set up ({channel_name})
- [ ] Stakeholders notified
- [ ] Steady-state metrics baselined

## Experiment Schedule

| Time | Experiment | Target | Fault | Duration | Expected outcome |
|------|-----------|--------|-------|----------|-----------------|
| {HH:MM} | {name} | {service} | {fault_type} | {min} | {expected} |
| {HH:MM} | {name} | {service} | {fault_type} | {min} | {expected} |

## Safety Rules
1. Abort immediately if error rate exceeds {threshold}%
2. Maximum experiment duration: {max_duration} minutes
3. Minimum 10-minute gap between experiments
4. No experiments after {cutoff_time}
5. Kill switch must be tested before first experiment

## Abort Procedure
1. Trigger kill switch: {url_or_command}
2. Verify rollback completed
3. Check steady-state metrics restored
4. Notify team in {channel}

## Post-GameDay
- [ ] Debrief within 1 hour of completion
- [ ] GameDay report within 48 hours
- [ ] Action items created as tickets
- [ ] Findings shared with wider team
