# MR Review Checklist

**MR**: [!NNN — MR title]
**Author**: [@author]
**Reviewer**: [@reviewer]
**Date**: [YYYY-MM-DD]
**Jira**: [<PROJ>-NNN]

---

## Pre-Review Checks

Before starting a detailed review, confirm:

- [ ] MR description references a Jira ticket (`Closes <PROJ>-NNN` or `Relates to <PROJ>-NNN`)
- [ ] CI pipeline is green (do not review a red MR without a good reason)
- [ ] Commit titles follow Conventional Commits format
- [ ] No AI attribution in commit messages (`Co-authored-by: Claude` etc.)
- [ ] MR description includes: what changed, why, test plan, rollback procedure

If any pre-review check fails, ask the author to fix it before proceeding.

---

## Lens 1: Correctness

- [ ] Implementation matches the requirements / acceptance criteria in the Jira ticket
- [ ] Happy path is tested
- [ ] Error paths are tested (network failures, database errors, validation failures)
- [ ] Edge cases are handled:
  - [ ] Null / None / undefined inputs
  - [ ] Empty collections / strings
  - [ ] Zero and negative numeric values
  - [ ] Maximum values / overflow scenarios
- [ ] Concurrent access to shared state is safe
- [ ] No off-by-one errors in loops, pagination, or slice operations
- [ ] External API / queue / DB calls include timeout and retry logic where appropriate

**BLOCKING issues from this lens**:
> _List any blocking correctness issues here_

---

## Lens 2: Security

- [ ] No hardcoded secrets, tokens, passwords, or API keys (including in test fixtures)
- [ ] All SQL queries use parameterised statements (no string concatenation with user input)
- [ ] No command injection vectors (`shell=True`, `eval()`, unsanitised shell arguments)
- [ ] User-supplied input is validated before use
- [ ] All new endpoints require authentication
- [ ] Authorisation is checked per resource, not just per role
- [ ] No sensitive data logged (passwords, tokens, PII)
- [ ] New dependencies are not known-vulnerable (`pip-audit` / `npm audit`)
- [ ] No path traversal vectors (user input used to construct file paths)
- [ ] Blast radius is acceptable: rollback is safe, API changes are backwards-compatible

**BLOCKING issues from this lens**:
> _List any blocking security issues here_

---

## Lens 3: Observability

- [ ] New code paths emit OpenTelemetry spans with meaningful attribute names
- [ ] Errors are logged with context (request ID, user ID, correlation ID)
- [ ] Log levels are appropriate: DEBUG/INFO/WARNING/ERROR (no `print()`)
- [ ] New counters / histograms are emitted for new features where applicable
- [ ] New alert-worthy conditions have corresponding alert rules (or a ticket to add them)
- [ ] The change does not introduce new alert noise (false positives)
- [ ] A production failure in this code path would be diagnosable from logs alone

**BLOCKING issues from this lens**:
> _List any blocking observability issues here_

---

## Lens 4: Maintainability

- [ ] Function and variable names are accurate and unambiguous
- [ ] Each function / class has a single, clear responsibility
- [ ] Public functions have docstrings explaining *why*, not just *what*
- [ ] Complex algorithms have a comment explaining the approach
- [ ] No magic numbers or magic strings — named constants used
- [ ] No commented-out code committed
- [ ] TODOs reference a Jira ticket: `# TODO: <PROJ>-NNN — description`
- [ ] Test coverage meets threshold: ≥95% Python / ≥80% TypeScript on changed files
- [ ] Test names describe the scenario (`test_payment_fails_when_card_expired`)
- [ ] Tests assert behaviour, not implementation details
- [ ] Documentation (README, API docs, CHANGELOG) updated if behaviour changed

**BLOCKING issues from this lens**:
> _List any blocking maintainability issues here_

---

## Blast Radius Assessment

Answer before approving:

| Question | Answer |
|----------|--------|
| What breaks if this has a latent bug? | |
| How many users are on this code path? | |
| Is rollback safe without data loss? | |
| Are DB migrations reversible? | |
| Are API changes backwards-compatible? | |
| Does this touch shared infrastructure? | |
| Is a phased rollout / feature flag needed? | |

---

## Approval Decision

| Outcome | Condition |
|---------|-----------|
| **Approve** | No BLOCKING issues; nits are at author's discretion |
| **Approve with comments** | No blocking issues; non-blocking suggestions provided |
| **Request Changes** | One or more BLOCKING issues; must be resolved before merge |
| **Tag SME** | Area outside reviewer's expertise; do not approve until expert reviews |

**Decision**: [ ] Approve  [ ] Approve with comments  [ ] Request Changes  [ ] Tag SME

---

## Comment Examples

```
BLOCKING: SQL query at line 47 concatenates `user_id` directly into the query string.
This is vulnerable to SQL injection. Use a parameterised query:
  cursor.execute("SELECT * FROM orders WHERE user_id = %s", (user_id,))

BLOCKING: The /admin/users endpoint has no authentication check.
All new endpoints must require a valid JWT. Add the `requireAuth` preHandler.

nit: Variable `d` on line 12 could be `duration_ms` for clarity.

Consider extracting lines 55–72 into a `_calculate_burn_rate()` function —
this logic is duplicated in `slo_reporter.py:88` and if the formula changes,
both sites will need updating.
```

---

## Notes

> _Free-form notes for the author or future reviewers_
