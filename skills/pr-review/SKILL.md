# Skill: PR / MR Review

## The Four Reviewer Lenses

Apply all four lenses to every review. A review that only checks correctness is incomplete.

---

### Lens 1: Correctness

Does the code do what it claims to do?

- Does the implementation match the requirements / acceptance criteria in the Jira ticket?
- Are all edge cases handled?
  - Empty inputs, zero values, null / None / undefined
  - Maximum values, overflow scenarios
  - Concurrent access to shared state
- Are error paths tested, not just the happy path?
- Are external calls (HTTP, database, queue) tested with failure scenarios?
- Is the logic provably correct, or does it rely on assumptions that could fail?
- Are there off-by-one errors, incorrect boundary conditions, or comparison operator mistakes?
- Do integration tests cover the behaviour end-to-end, not just unit-level?

**Correctness blockers**: code that will produce wrong results in production.

---

### Lens 2: Security

Could this change be exploited?

**Injection vectors**:
- SQL: all queries must use parameterised statements — no string concatenation with user input
- Command injection: no `subprocess.run(user_input, shell=True)`; no `eval()` on untrusted input
- Template injection: user input must not reach template rendering engines directly
- Path traversal: file paths constructed from user input must be validated and canonicalised

**Authentication and authorisation**:
- Are new endpoints protected? Is the auth check in the right layer (not just client-side)?
- Is authorisation checked per resource, not just per role?
- Are there any privilege escalation vectors?

**Secret exposure**:
- No hardcoded secrets, API keys, passwords, or tokens (not even test credentials)
- Secrets must not appear in log output, error messages, or HTTP responses
- Dependency versions: are any new dependencies known-vulnerable?

**Blast radius**:
- If this code is called with malicious input, how far can the damage spread?
- Does this change modify authentication, authorisation, or data access boundaries?
- Is rollback safe if this change is found to be malicious or broken?

**Security blockers**: hardcoded secrets, SQL injection, command injection, auth bypass, privilege escalation.

---

### Lens 3: Observability

Can we operate this change in production?

- Are new code paths instrumented with OpenTelemetry spans?
- Are errors logged with sufficient context to diagnose them?
  - Log the user ID / request ID / correlation ID, not just the error message
  - Log at the right level: DEBUG for verbose detail, INFO for normal flow, WARNING for expected failures, ERROR for unexpected failures
- Are new metrics emitted for new functionality?
  - Counters for discrete events (requests, errors, retries)
  - Histograms / summaries for durations and sizes
- Are new SLI candidates identified?
- Will this change produce new alert noise (false positives)?
- Can we diagnose failures from logs alone, or do we need live access to the system?

**Observability blockers**: new code paths with no instrumentation, errors swallowed silently, no way to distinguish this change's behaviour in production.

---

### Lens 4: Maintainability

Will the next engineer (including future you) understand and safely modify this code?

**Naming and structure**:
- Are names accurate and unambiguous? A function named `process()` that sends emails is a lie.
- Does each function / class have a single responsibility?
- Is complexity justified? If not, simplify.

**Documentation**:
- Public functions must have docstrings explaining *why*, not just *what*
- Complex algorithms must have a comment explaining the approach
- Non-obvious decisions (unusual algorithms, workarounds) must be explained in comments

**Test quality**:
- Tests must assert behaviour, not implementation details
- No tests that only check the happy path
- Coverage ≥95% (Python) / ≥80% (TypeScript) on changed files
- Test names must describe the scenario: `test_payment_fails_when_card_is_expired` not `test_payment_2`

**Technical debt**:
- TODOs must reference a Jira ticket: `# TODO: <PROJ>-123 — handle retry exhaustion`
- No magic numbers or strings — use named constants
- No code commented out and committed

**Maintainability blockers**: deleted tests, code that is impossible to test, public API changes without documentation.

---

## Blast Radius Analysis

Before approving, answer these questions:

1. **What breaks if this change has a latent bug?** List affected services and user flows.
2. **How many users are affected?** Is this on the critical path for all users, or a narrow feature?
3. **Is rollback safe?**
   - Are database migrations reversible without data loss?
   - Are API changes backwards-compatible (no breaking changes to existing clients)?
   - Can a feature flag be used to disable this change without a deployment?
4. **Does this change affect shared infrastructure?** (Shared DB schema, message topics, shared libraries)
5. **Are there timing / ordering dependencies?** Multi-step deployments that must be coordinated?

High blast radius changes require:
- Extra testing (load test, chaos experiment)
- Phased rollout (canary or feature flag)
- Production monitoring plan during rollout
- Explicit rollback procedure in the MR description

---

## Comment Tone and Protocol

**Use suggestion, not demand**:
- Bad: "This is wrong. Use X."
- Good: "Consider using X instead of Y here — Y will panic if `items` is nil and that's a real path."

**Label every comment**:
- `BLOCKING:` — must be resolved before merge
- `nit:` — style / preference; author's discretion; never blocks merge
- No label = non-blocking suggestion (default)

**Examples**:

```
BLOCKING: This SQL query concatenates user input directly into the query string.
Use a parameterised query: cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))

nit: Variable name `d` could be `duration_ms` for clarity.

Consider extracting this into a separate function — it's called from three places and 
if the logic needs to change, you'd have to update all three sites.
```

**Number of comments**: Be thorough on correctness and security. Be selective on style. A review with 40 nits and 1 blocking issue buries the signal in noise.

---

## Pre-Approval Checklist

Before clicking Approve:

- [ ] All BLOCKING comments are resolved
- [ ] Tests pass in CI (do not approve a red pipeline unless explicitly agreed)
- [ ] No hardcoded secrets in any file (including test fixtures)
- [ ] Database migrations are reversible
- [ ] API changes are backwards-compatible (or breaking change is intentional and documented)
- [ ] New code paths have observability (spans, logs, metrics)
- [ ] Coverage meets the minimum threshold
- [ ] MR description references a Jira ticket
- [ ] MR description has a test plan
- [ ] MR description describes the rollback procedure
- [ ] Conventional commit title format: `type(scope): description`
- [ ] No AI attribution (`Co-authored-by: Claude` etc.) in commit messages

---

## Request Changes vs Approve With Comments

| Situation | Action |
|-----------|--------|
| One or more BLOCKING issues | Request Changes |
| Only nits / non-blocking suggestions | Approve with comments |
| Uncertain about correctness in an area outside your expertise | Comment and tag an SME; do not approve until an expert reviews |
| Tests are missing or clearly insufficient | Request Changes |
| Pipeline is red | Do not approve; ask the author to fix it first |

---

## MR Description Quality

A high-quality MR description contains:

1. **Jira ticket reference**: `Closes <PROJ>-123`
2. **What changed**: a clear, factual description (not the commit message repeated)
3. **Why it changed**: link to the problem, user need, or technical motivation
4. **Test plan**: how was this verified? (unit tests, integration tests, manual testing steps)
5. **Rollback procedure**: exact steps to revert if the change causes issues in production
6. **Screenshots / recordings** (for UI changes)
7. **Migration notes** (for DB changes): is migration reversible? any downtime?

---

## Conventional Commits — Quick Reference

```
feat: add circuit breaker to payment client
fix(auth): handle expired refresh tokens on reissue
refactor(users): extract email validation to domain service
test(payments): add integration test for card decline scenario
docs: update resilience score methodology
chore: update ruff to 0.9.x
feat!: remove legacy v1 API endpoints
```

- No AI attribution
- No TDD phase labels ("RED:", "GREEN:")
- Title ≤72 characters
- Body separated from title by a blank line
- Breaking changes: `!` before `:` or `BREAKING CHANGE:` footer
