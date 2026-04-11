# /story — Draft a Jira Story

Draft an INVEST-compliant user story from a feature description. Once approved, hand off to @jira-story for Jira creation.

## Steps

### 1. Get the feature description

If the user has provided a description as the command argument, use it.

If no description was provided, ask:
```
What feature do you want to turn into a story?
Describe it in plain language — as much or as little detail as you have.
```

Wait for the user to respond before proceeding.

### 2. INVEST criteria check

Evaluate the feature description against all six INVEST criteria:

| Criterion | Question |
|-----------|---------|
| **I**ndependent | Can this be built without waiting for another in-progress story? |
| **N**egotiable | Is the scope flexible, not a rigid fixed spec? |
| **V**aluable | Does it deliver measurable value to a user or the platform? |
| **E**stimable | Can it be sized in Fibonacci points by an engineer? |
| **S**mall | Can one developer complete it in ≤ 1 sprint (2 weeks)? |
| **T**estable | Are acceptance criteria specific enough to write tests from? |

Report any failures:
```
INVEST issue: <criterion> — <why it fails> — <suggested fix>
```

If the feature fails more than 2 criteria, ask the user to clarify or adjust scope before drafting.

### 3. Draft the story

Write the story in this format:

```markdown
## Title
<Imperative verb, ≤10 words, describes the user-facing capability>

## User Story
As a <role>,
I want <goal>
so that <benefit>.

## Acceptance Criteria

**Given** <precondition>
**When** <action>
**Then** <expected outcome>

**Given** <precondition>
**When** <action>
**Then** <expected outcome>

[3–5 criteria — more than 5 means the story is too large]

## Out of Scope
<Anything explicitly excluded — prevents scope creep>

## Estimate
<Fibonacci: 1 / 2 / 3 / 5 / 8>
(anything > 8 should be split before creation)
```

**Roles to use (pick the most accurate):**
- Platform engineer — deploys and configures the platform
- Chaos practitioner — designs and runs experiments
- Service owner — monitors resilience scores for their service
- Platform administrator — manages orgs, users, and API keys
- On-call engineer — responds to incidents using runbooks

**Acceptance criteria rules:**
- 3–5 criteria, each in Given/When/Then format
- Every criterion must be independently testable
- No implementation details (no class names, no module paths, no SQL)
- Cover: one happy path, one error/failure path, one edge case

### 4. Show the draft and ask for approval

Present the full draft to the user and ask:
```
Does this story look right? Reply with:
- "approve" to hand off for Jira creation
- Your changes/feedback to revise the draft
```

Wait for the user's response.

### 5. Revise if needed

If the user provides feedback, revise the story and show the updated draft again. Repeat until the user approves.

### 6. Handoff on approval

Once the user approves, output:
```
## Story approved — ready for Jira creation

<final story text>

Suggested branch: feat/<PROJ>-{N}/{short-slug}
(Replace {N} with the actual Jira issue number after creation)

Hand off to @jira-story to create this story in Jira.
```

Do NOT create the Jira ticket yourself. @jira-story handles all Jira API calls.

## Example Output

```
## Title
Add kill switch to active experiment runs

## User Story
As a chaos practitioner,
I want to abort an in-progress experiment run immediately
so that I can stop blast radius from expanding during an incident.

## Acceptance Criteria

**Given** an experiment run is in the `running` state
**When** I POST to `/v1/experiments/{id}/runs/{run_id}/abort`
**Then** the run transitions to `aborted` within 5 seconds and the chaos action is reversed

**Given** an experiment run is already in the `aborted` state
**When** I POST to the abort endpoint again
**Then** I receive a 200 with the current run state — no error, no duplicate action

**Given** I POST to the abort endpoint with an experiment_id that does not belong to my org
**Then** I receive 404 — the experiment's existence is not confirmed

## Out of Scope
Bulk abort of all running experiments (separate story).
Abort notification webhooks (separate story).

## Estimate
3 story points
```
