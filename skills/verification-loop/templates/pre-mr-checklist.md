# Pre-MR Checklist

Use this checklist before raising a merge request. Every item must be reader-verifiable
from the code and repository alone — no subjective judgements.

---

## Code Quality

- [ ] `ruff check` or `eslint` passes with zero warnings
- [ ] `mypy --strict` or `tsc --noEmit` passes with zero errors
- [ ] No `# type: ignore` or `@ts-ignore` added without a comment explaining why
- [ ] All new public functions have type annotations (parameters and return type)
- [ ] No `print()` calls in library/service code (use structured logging)
- [ ] No bare `except:` clauses — specific exception types only
- [ ] No deprecated typing imports (`Dict`, `List`, `Optional`, `Union`) — use builtins
- [ ] No `any` in TypeScript without a comment justification
- [ ] No mutable default arguments (`def f(x=[])`) — use `None` sentinel

---

## Tests

- [ ] All tests pass (`pytest` / `vitest run`)
- [ ] Coverage is ≥ 95% (Python) or ≥ 80% (TypeScript) on changed files
- [ ] New behaviour has at least one test per logical branch (happy path + error path)
- [ ] Tests use parameterise / `@pytest.mark.parametrize` where multiple inputs are tested
- [ ] No `@pytest.mark.skip` or `xit()`/`xdescribe()` left in the test suite
- [ ] Test names describe the **behaviour**, not the implementation method
- [ ] No test depends on external network/database without an integration test marker

---

## Security

- [ ] No secrets, API keys, passwords, or tokens committed — use environment variables
- [ ] `bandit` or `npm audit` passes at HIGH+MEDIUM severity level
- [ ] All SQL uses parameterised queries — no f-string or `%` formatting
- [ ] User input is validated before use (Pydantic / Zod / `@Valid`)
- [ ] No sensitive data logged (PII, credentials, auth tokens)
- [ ] Dependencies are pinned and audited (`pdm.lock` or `pnpm-lock.yaml` updated)
- [ ] No `eval()`, `exec()`, `shell=True` without documented justification

---

## Observability

- [ ] New chaos actions and probes emit an OTel span with `resilience_*` attributes
- [ ] All new HTTP routes have trace context propagation headers
- [ ] New metrics follow naming convention: `resilience_<component>_<metric>_<unit>`
- [ ] Logs use structured format (`structlog` / `logging.info(..., extra={})`)
- [ ] No credentials or PII in log messages or span attributes
- [ ] Error paths log the exception with `logger.exception(...)` or `logger.error(..., exc_info=True)`

---

## Documentation

- [ ] Public functions and classes have docstrings (or JSDoc for TypeScript)
- [ ] `CHANGELOG.md` updated with the change under `[Unreleased]`
- [ ] If a scoring formula or threshold changed: methodology doc updated/created
- [ ] OpenAPI spec updated if API endpoints were added or modified
- [ ] README updated if setup instructions changed

---

## MR Description

- [ ] MR title follows Conventional Commits format: `type(scope): description`
- [ ] MR description explains **why** the change was made, not just what
- [ ] Jira ticket linked (`CLS-N`)
- [ ] No references to internal planning artefacts (`docs_local/`, agent names)
- [ ] Screenshots or test output attached for UI or behaviour changes
- [ ] Breaking changes clearly documented (API changes, config schema changes)

---

## Review Readiness

- [ ] Diff is ≤ 400 lines (excluding generated files, lock files, migrations)
- [ ] Commits are atomic — each commit passes tests independently
- [ ] All commit messages follow Conventional Commits specification
- [ ] Branch is rebased on latest `master` (no merge commits in branch)
- [ ] Self-review completed: read your own diff as if you were the reviewer
- [ ] No TODO/FIXME comments that were not present before this branch
