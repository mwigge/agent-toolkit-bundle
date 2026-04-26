# User Story

## Title
<!-- One sentence: verb + actor + outcome, e.g. "Allow users to export reports as CSV" -->

---

## Story

As a **[role]**,
I want **[goal — specific action]**
so that **[benefit — business value delivered]**.

---

## INVEST Checklist
<!-- Review before moving to Ready. Reject if more than 2 criteria fail. -->

- [ ] **Independent** — can be built without another in-progress story
- [ ] **Negotiable** — implementation approach is open, not pre-specified
- [ ] **Valuable** — delivers direct value to a user or business metric
- [ ] **Estimable** — team can size it with available information
- [ ] **Small** — fits within one sprint (≤ 8 story points)
- [ ] **Testable** — acceptance criteria can be verified by a QA engineer

---

## Acceptance Criteria

### Scenario 1: [Happy path — brief label]
**Given** [precondition — system state before the action]
**When** [single user action]
**Then** [observable outcome 1]
**And** [observable outcome 2, if needed]

### Scenario 2: [Unhappy path / edge case — brief label]
**Given** [precondition]
**When** [action that triggers the failure case]
**Then** [expected error behaviour — specific, measurable]
**And** [system state is unchanged / appropriate fallback occurs]

<!-- Add more scenarios for each distinct path: role variation, data boundary, timeout, etc. -->

---

## Definition of Ready (DoR)
<!-- All must be checked before sprint planning -->

- [ ] Acceptance criteria written in Given/When/Then format
- [ ] Story estimated by the team
- [ ] Dependencies identified: [list or "None"]
- [ ] UI mockup linked: [URL or "N/A"]
- [ ] API contract defined: [link or "N/A"]
- [ ] PII / security implications reviewed
- [ ] Linked to epic: [CLS-23 / CLS-20]

---

## Definition of Done (DoD)
<!-- All must be checked before transitioning to Done -->

- [ ] All acceptance criteria scenarios pass
- [ ] Code reviewed and approved (≥1 peer reviewer)
- [ ] Automated tests written and passing (≥95% Python / ≥80% TypeScript)
- [ ] No new HIGH/CRITICAL security findings
- [ ] Documentation updated
- [ ] Deployed to staging
- [ ] PO sign-off received

---

## RICE Prioritisation

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Reach** (users/quarter) | | |
| **Impact** (0.25 / 0.5 / 1 / 2 / 3) | | |
| **Confidence** (20% / 50% / 80% / 100%) | | Data source: |
| **Effort** (person-months) | | Includes QA + docs + deploy |
| **RICE Score** | _(R × I × C) / E_ | |

---

## Technical Notes
<!-- Architecture decisions, constraints, non-functional requirements -->

- **Performance**: [e.g., response time ≤ 200 ms at p99]
- **Security**: [PII handling, auth requirements, data classification]
- **Dependencies**: [services, teams, third-party APIs]
- **Observability**: [spans, metrics, log events required]

---

## Open Questions

| # | Question | Owner | Due | Resolution |
|---|----------|-------|-----|------------|
| 1 | | | | |

---

## Jira

- **Project**: CLS
- **Epic**: [CLS-23 (cap-resilience) / CLS-20 (cap-backbone)]
- **Story ID**: [assigned after creation]
- **Sprint**: [assigned at planning]
- **Assignee**: [assigned when work begins]
- **Reporter**: [assigned when work begins]
- **Labels**: [cap-resilience / cap-backbone]
