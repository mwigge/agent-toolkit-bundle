# RFC-NNN: [Proposal Title]

**Author**: [Name, @handle]
**Date**: YYYY-MM-DD
**Status**: Draft
**Comment deadline**: YYYY-MM-DD

> Valid statuses: `Draft` | `Open for Comment` | `Accepted` | `Rejected` | `Withdrawn`
>
> Move to `Open for Comment` when ready for team review.
> Set a comment deadline (typically 2 weeks).
> After acceptance, write an ADR to record the final decision.

---

## Summary

<!--
One paragraph. What are you proposing and why?
Write this last — it should summarise the entire RFC.
-->

[One paragraph summary]

---

## Problem Statement

<!--
Describe the problem you are solving:
- What is broken, missing, or painful today?
- Who is affected and how severely?
- What happens if we do nothing?
- Include data / metrics where possible.
-->

### Current situation

[Describe what exists today]

### Why this is a problem

[Quantify the pain or risk]

### Out of scope

[Explicitly list what this RFC does NOT address — prevents scope creep during discussion]

---

## Proposed Solution

<!--
Describe your proposed approach in enough detail for the team to evaluate it.
Include:
- Architecture / design
- API contracts
- Data model changes
- Migration strategy
- Operational considerations (deployment, monitoring, rollback)

Use diagrams and code examples where they clarify.
-->

### Overview

[High-level description]

### Design

[Detailed design — diagrams, schemas, API shapes, pseudocode]

```mermaid
%%{init: {'theme': 'base'}}%%
graph LR
  title Proposed architecture
  A[Component A] -->|event| B[Component B]
  B -->|writes| C[(Store)]
```

### API changes

[List any new or modified API endpoints / events / schemas]

### Migration strategy

[How do we move from the current state to the proposed state? Is it backwards-compatible?]

### Rollback plan

[How do we revert if the proposal is adopted but causes problems?]

---

## Alternatives Considered

<!--
List at least two meaningful alternatives. For each, explain:
- What it is
- Why it was not chosen
This demonstrates due diligence and helps reviewers understand the decision space.
-->

### Alternative 1: [Name]

**Description**: [1–3 sentences]

**Why not chosen**: [Specific reasons]

### Alternative 2: [Name]

**Description**: [1–3 sentences]

**Why not chosen**: [Specific reasons]

### Alternative 3: Do nothing

**Why not chosen**: [The problem does not resolve itself; describe the cost of inaction]

---

## Open Questions

<!--
List questions that are still unresolved. For each, indicate:
- Who is best placed to answer it
- Whether it blocks acceptance or can be resolved in implementation

Remove questions as they are answered — update this section, do not add strikethrough text.
-->

| # | Question | Owner | Blocking? | Resolution |
|---|----------|-------|-----------|------------|
| 1 | [Question] | [@person] | Yes / No | _Open_ |
| 2 | [Question] | [@person] | Yes / No | _Open_ |

---

## Success Criteria

<!--
How will we know if this proposal achieved its goals?
Use measurable criteria. These will be used to evaluate the outcome after implementation.
-->

- [ ] [Metric: e.g. "P99 latency for /api/experiments < 200ms under 500 RPS"]
- [ ] [Metric: e.g. "Zero regressions in existing test suite"]
- [ ] [Qualitative: e.g. "Feature flag enables per-cohort rollout without redeployment"]

---

## Timeline

| Milestone | Target date | Owner |
|-----------|------------|-------|
| RFC open for comment | [YYYY-MM-DD] | [Name] |
| Comment deadline | [YYYY-MM-DD] | — |
| Decision (accept / reject) | [YYYY-MM-DD] | [Decision maker] |
| ADR written | [YYYY-MM-DD] | [Name] |
| Implementation starts | [YYYY-MM-DD] | [Team] |
| Implementation complete | [YYYY-MM-DD] | [Team] |

---

## References

- [<PROJ>-NNN: Jira ticket]
- [Link to related ADRs]
- [Link to benchmarks, spikes, or prior art]
- [External references]
