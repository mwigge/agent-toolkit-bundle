---
description: Run a four-lens adversarial code review over all changes on the current branch relative to main.
---

# /review — Adversarial Code Review on Current Branch

Run a full adversarial code review against all changes on the current branch relative to main.

## Steps

### 1. Get all changes on the branch

```bash
git diff main...HEAD
git log main..HEAD --oneline
```

Read the full diff. Understand the intent of every changed file.

### 2. Run the security scan

```bash
bash ~/<your-dev-dir>/agent-toolkit-bundle/skills/security-review/scripts/security_scan.sh
```

Also run stack-specific scans if the diff contains Python or TypeScript:

**Python:**
```bash
bandit -r <changed_packages>/ -ll
pip-audit
```

**TypeScript:**
```bash
npm audit --audit-level=high
```

Capture the output — it feeds into Lens 2 (Security).

### 3. Apply all four review lenses

Apply every lens in full. Do not skip any.

---

#### Lens 1: Correctness

For every changed function and class:

- **Logic bugs:** off-by-one, wrong operator, incorrect boolean, inverted condition
- **Edge cases:** null/None/undefined, empty collections, zero, negative numbers, max values
- **Error paths:** every `except`/`catch` block is reachable and tested; no silent swallowing
- **Concurrency:** shared mutable state accessed across async tasks or threads without synchronisation
- **Idempotency:** any operation callable multiple times (rollback, upsert, publish, webhook delivery) is safe on repeat call
- **Type safety:** would mypy (Python) or tsc (TypeScript) flag anything?

---

#### Lens 2: Security

- **SQL injection:** all queries use `%s` / `$N` placeholders — no f-strings, no `.format()`
- **Shell injection:** `subprocess` uses list form with `shell=False`
- **Auth/authz:** every endpoint requires auth middleware; `org_id` scope enforced on every DB query
- **IDOR:** resource IDs always scoped by `org_id` in the WHERE clause
- **Secret exposure:** no hardcoded credentials, API keys, tokens; never logged
- **Dependency audit:** results from `bandit` / `pip-audit` / `npm audit` reviewed
- **Chaos-specific:** experiment error messages do not expose internal network topology, IPs, or credentials
- **Blast radius:** explicitly state which tenants or systems are affected if this fails silently

---

#### Lens 3: Observability

- **OTel spans:** every new chaos action emits `chaos.<action_type>.<target>`; every new probe emits `chaos.probe.<probe_type>`
- **Span attributes:** `resilience_experiment_id`, `resilience_target`, `resilience_action`, `resilience_outcome` present; no PII; no secrets
- **Error logging:** errors logged at ERROR level with `trace_id` and `span_id` from OTel context; no bare `print()`
- **Metrics:** new SLIs have a metric following `resilience_<component>_<metric>_<unit>` naming
- **Structured logging:** `structlog` / `pino` only — no `print()`, no `console.log()`

---

#### Lens 4: Maintainability

- **Naming:** variables, functions, classes named for what they are, not how they work
- **SRP:** each function does one thing; no God functions over ~40 lines with multiple concerns
- **Coverage:** ≥ 95% Python / ≥ 80% TypeScript on changed files
- **Magic values:** no unexplained integers or string literals — use named constants
- **Documentation:** non-obvious logic has a comment explaining *why*, not *what*
- **Deprecated patterns:** no `typing.Dict/List/Optional` (Python), no `any` without justification (TypeScript)
- **Layer violations:** domain layer imports nothing from routes/infra; service layer has no HTTP awareness

---

### 4. Check the MR description (if it exists)

Look for an existing MR/PR description via `gh pr view` or `glab mr view`:

```bash
gh pr view 2>/dev/null || glab mr view 2>/dev/null
```

If a description exists, verify:
- [ ] `<PROJ>-N` Jira reference present and not a placeholder
- [ ] Test plan section filled with real numbers
- [ ] Rollback plan present or explicitly "not applicable" with reason
- [ ] No AI attribution (`Co-authored-by: Claude`, mention of agent names)
- [ ] No references to `<your-docs-dir>/`, internal planning labels, or agent names
- [ ] Only `<PROJ>-N` Jira references — no `ELI-A`, `EA-x`, `T1`

### 5. Validate conventional commits on the branch

```bash
git log main..HEAD --format="%s"
```

Check every subject line:
- [ ] Follows `type(scope): description` or `type: description`
- [ ] Type is one of: feat / fix / refactor / test / docs / chore
- [ ] Subject ≤ 72 characters
- [ ] No TDD phase names, agent names, or AI attribution in any message

### 6. Output the structured review

Use exactly these comment formats:

```
BLOCKING: <what> — <why it matters> — <suggested fix>
nit: <observation>
```

Structure the output:

```markdown
## Code Review — <branch name>

### Lens 1: Correctness
<findings or "No issues found">

### Lens 2: Security
<findings or "No issues found">
Security scan: bandit <result> | pip-audit <result> | npm audit <result>

### Lens 3: Observability
<findings or "No issues found">

### Lens 4: Maintainability
<findings or "No issues found">

### MR Description
<findings or "Not created yet" or "PASS">

### Commits
<findings or "All commits follow convention">

### Blast Radius
If this change fails silently in production:
- Affected tenants: <all / specific / none>
- Affected features: <list>
- Data risk: <data loss / stale reads / none>
- Recovery: <automatic / manual rollback / unrecoverable>

---

## Verdict

### BLOCKING issues (must fix before merge)
1. [file:line] <issue>
...

### Nits (non-blocking)
- <nit>

### Overall: REQUEST CHANGES / APPROVED WITH COMMENTS
```

If there are no blocking issues:
```
## Overall: APPROVED WITH COMMENTS
No blocking issues found. Nits are non-blocking — address at your discretion.
```
