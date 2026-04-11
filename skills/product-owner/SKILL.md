---
name: product-owner
description: Product owner discipline: user story INVEST criteria, Gherkin acceptance criteria, RICE prioritisation, and OKR alignment. Use when writing stories or grooming the backlog.
---

# Skill: Product Owner

**Version**: 1.0.0 | **Updated**: 2026-04-05

Apply this skill when writing user stories, prioritising backlogs, defining OKRs, running sprint ceremonies, creating Jira tickets (project=<PROJ>), or communicating with stakeholders.

---

## User Story Format

Every story follows this canonical structure:

```
As a <role>,
I want <goal>
so that <benefit>.
```

**Rules**:
- The role must be a real user persona, not "the system" or "the admin" (unless admin is genuinely the actor)
- The goal must be a concrete action, not a vague aspiration ("process a payment" not "handle money better")
- The benefit must express business value — this is why the story exists

### Acceptance Criteria (Given/When/Then)

Every story must include at least 2 scenarios. Each scenario covers one specific behaviour:

```
**Scenario 1: Happy path**
Given I am an authenticated user with an active account
When I submit a payment of €50 with a valid card
Then the payment is processed within 3 seconds
And I receive a confirmation email within 1 minute
And my account balance is decremented by €50

**Scenario 2: Invalid card**
Given I am an authenticated user
When I submit a payment with an expired card
Then the payment is rejected with error code CARD_EXPIRED
And my account balance is unchanged
And I am prompted to update my payment method
```

**Rules**:
- "Given" sets state — never put actions in Given clauses
- "When" describes a single user action
- "Then" describes observable outcomes — must be testable by a QA engineer
- Use "And" to chain; never use "But" (it signals a missing negative scenario)

---

## INVEST Criteria

Evaluate every story before adding it to a sprint. Reject stories failing more than 2 criteria.

| Criterion | Question | Failure signal |
|-----------|----------|----------------|
| **I**ndependent | Can this be built without another story being done first? | "Depends on X" in every conversation |
| **N**egotiable | Is the implementation open? | Story pre-specifies exact UI/code solution |
| **V**aluable | Does it deliver value to a user or the business? | "Refactor X" with no visible outcome |
| **E**stimable | Can the team size it confidently? | No agreement after two planning attempts |
| **S**mall | Will it fit in one sprint? | Estimate > 8 story points without splitting |
| **T**estable | Can AC be verified without subjective judgement? | "Works well" / "feels fast" in AC |

### Story Splitting Patterns

When a story is too large (>8 SP) or fails INVEST:

1. **By workflow step**: "User searches for a product" → "User types a search query" + "User applies filters" + "User views search results"
2. **By data variation**: "Process all payment types" → one story per payment method
3. **By user role**: "Admins and users can export reports" → separate stories per role
4. **By happy/unhappy path**: Keep happy path as primary; make each error path its own story
5. **By CRUD operation**: "Manage products" → Create product + Read product + Update product + Delete product
6. **By UI vs API**: "User can reset password" → API endpoint story + UI story

---

## RICE Scoring

Use RICE to compare and prioritise backlog items objectively:

```
RICE Score = (Reach × Impact × Confidence) / Effort
```

| Parameter | Definition | Scale |
|-----------|-----------|-------|
| **Reach** | How many users affected per quarter? | Absolute number |
| **Impact** | How much does it improve each user's experience? | 0.25 / 0.5 / 1 / 2 / 3 |
| **Confidence** | How sure are we about Reach and Impact estimates? | 20% / 50% / 80% / 100% |
| **Effort** | Total person-months required | Decimal (0.5 = 2 weeks) |

**Rules**:
- Never inflate Confidence above 80% without data (survey results, A/B test, usage metrics)
- Effort must include QA, docs, and deployment — not just coding time
- Recalculate RICE every quarter; context changes
- RICE is an input to decisions, not the final answer — use judgment for strategic bets

---

## OKR Structure

```
Objective: <Qualitative, inspiring, 1-2 sentence direction>
  Key Result 1: <Measurable, time-bound outcome> — Score: 0.0
  Key Result 2: <Measurable, time-bound outcome> — Score: 0.0
  Key Result 3: <Measurable, time-bound outcome> — Score: 0.0
```

**Objectives**:
- Qualitative, aspirational, memorable — not a metric
- Aligned to company strategy — one OKR per strategic theme per team per quarter
- Owned by one person; shared by the team

**Key Results**:
- Must be measurable (a number, percentage, binary yes/no with clear criteria)
- Time-bound (by end of quarter)
- 3-5 per objective; more than 5 dilutes focus
- Score 0.0–1.0 at end of quarter: 0.7 is a healthy stretch; 1.0 may mean the target was too easy

**Anti-patterns**:
- KRs that are tasks ("Launch feature X") — rewrite as outcomes ("50% of users activate feature X within 30 days of launch")
- OKRs as performance reviews — they should be aspirational, not minimum bars
- More than 3 objectives per team per quarter — forces false urgency on everything

---

## Sprint Planning

### Capacity Calculation

```
Team capacity (SP) = (working days in sprint) × (team_size) × (focus_factor)
Focus factor: 0.6–0.7 (accounts for meetings, reviews, incidents, context switching)

Example: 10-day sprint, 4 devs, 0.65 focus = 10 × 4 × 0.65 = 26 SP available
Commit to: 80% of capacity = ~21 SP (buffer for unplanned work)
```

### Tech Debt Ratio

Maintain at least **20% of sprint capacity** on tech debt, non-functional requirements, and platform health. Never allow this to drop below 10% for more than 2 consecutive sprints — this is a leading indicator of delivery risk.

### Rules

- Never pull stories in that are not DoR-complete
- Never commit to > 80% of capacity — unplanned work is guaranteed
- If mid-sprint scope changes occur, remove an equivalent story (scope swap, not scope add)
- Velocity is the average of last 3-5 sprints — use this, not estimates from individuals

---

## Definition of Ready (DoR)

A story is ready for sprint planning when ALL of the following are true:

- [ ] Acceptance criteria written in Given/When/Then format
- [ ] INVEST criteria evaluated — no more than 2 failures
- [ ] Story estimated by the team (planning poker or equivalent)
- [ ] Dependencies identified and resolved or explicitly accepted as risk
- [ ] UI mockup linked (if the story involves a user interface change)
- [ ] API contract defined (if the story involves a new or changed API)
- [ ] PII and security implications reviewed
- [ ] Linked to the correct Jira epic

---

## Definition of Done (DoD)

A story is done when ALL of the following are true:

- [ ] All acceptance criteria scenarios pass
- [ ] Code reviewed and approved by at least one peer
- [ ] Automated tests written and passing (≥95% coverage for Python, ≥80% for TypeScript)
- [ ] No new HIGH/CRITICAL security findings (bandit, npm audit)
- [ ] Documentation updated (README, API docs, architecture decision records)
- [ ] Deployed to staging environment
- [ ] PO sign-off received (demo or async review)
- [ ] Jira ticket transitioned to Done

---

## Jira Workflow (Project: <PROJ>)

### Key Configuration

| Item | Value |
|------|-------|
| Project | <PROJ> |
| Primary epic | <PROJ>-123 (`<your-project>`) |
| Architecture epic | <PROJ>-123 (`cap-backbone`) |
| Default label | `<your-project>` |
| Jira server | https://<your-jira-host>/ |
| CLI | `~/go/bin/jira` |
| Auth env var | `JIRA_API_TOKEN` |

### Two-Step Story Creation

Jira checklist fields cannot be set during CREATE. Always use two steps:

```bash
# Step 1: Create the story
~/go/bin/jira issue create \
  --project <PROJ> \
  --type Story \
  --summary "feat: add user email verification" \
  --description "$(cat story.md)" \
  --custom epic-link=<PROJ>-123

# Step 2: Update checklist fields (acceptance criteria, DoR/DoD checkboxes)
~/go/bin/jira issue edit <PROJ>-123 \
  --custom "Acceptance Criteria=Given ... When ... Then ..."
```

### Transitions

| Transition ID | Target status |
|---------------|---------------|
| 51 | Abandonné (reject/close without delivery) |

```bash
# Reject a story
~/go/bin/jira issue transition <PROJ>-123 --transition 51
```

### Assignment Rules

- Assign `reporter` and `assignee` only when work begins — not at story creation
- Never assign a story to a role; always a named individual
- Epic link: use <PROJ>-123 for delivery work; <PROJ>-123 for architecture docs only

---

## Stakeholder Communication

### Executive Summary Format

```
Status: [GREEN / AMBER / RED]
Period: [Sprint N / Q1 2026]
Progress: [1-2 sentences on what was delivered]
Risks: [1-2 bullet points — each with mitigation]
Next period: [1-2 sentences on what is planned]
Decision needed: [explicit ask, or "None"]
```

**Rules**:
- One page maximum
- No jargon (Jira IDs, sprint velocity, story points) in executive summaries
- Always include "Decision needed" — even if the answer is "None"
- Amber means "at risk, mitigation in place"; Red means "blocked, need intervention"

### Risk Radar

Classify risks on two axes: Likelihood (1–5) and Impact (1–5).

| Zone | Score | Action |
|------|-------|--------|
| Red | ≥16 | Immediate escalation, executive visibility |
| Amber | 9–15 | Active mitigation plan, weekly review |
| Green | 1–8 | Monitor, monthly review |

### Decision Log

Maintain a `decisions.md` in the project wiki. Each entry:

```
## DECISION-042 — 2026-03-15
**Decision**: Use Snowflake Dynamic Tables instead of dbt materialised views for the revenue mart.
**Context**: dbt materialised views do not support JOINs in Snowflake.
**Alternatives considered**: Scheduled tasks, custom stored procedures.
**Owner**: [Name]
**Review date**: 2026-06-15
```

Never delete entries — mark superseded ones with a `Superseded by DECISION-N` note.
