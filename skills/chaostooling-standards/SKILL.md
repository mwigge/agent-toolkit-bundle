---
name: chaostooling-standards
description: Apply shared Python, TypeScript, testing, security, and observability standards across chaostooling repositories.
---

# Chaostooling Engineering Standards

## When to Activate

Load this skill when working on any `chaostooling-*` repository
(chaostooling-generic, chaostooling-extension-*, chaostooling-otel,
chaostooling-reporting, chaostooling-experiments, chaostooling-platform-db).

---

## Python Standards

- **Runtime**: Python >= 3.12; PDM + `pdm.lock`
- **Lint/format**: ruff with rule sets `E,W,F,I,UP,B,S,T20,SIM,RUF`; black formatter
- **Types**: mypy strict; modern typing only -- `dict/list/X | None`, no deprecated `typing.Dict/List/Optional`
- **Logging/tracing**: use `chaosotel` re-exports -- never `print()`, never raw `logging.basicConfig`
- **Config**: `pydantic-settings`; secrets via `SecretStr`; env vars only -- never hardcode
- **API**: FastAPI async endpoints; parameterised SQL only (no f-string or `.format()` queries)
- **Tests**: pytest >= 95% coverage on changed files; >= 80% overall; AAA structure; mock at I/O boundaries only

## TypeScript Standards

- **Runtime**: Node 22 LTS; pnpm 9
- **Lint/format**: ESLint 9 flat config (`eslint.config.js` must exist); Prettier
- **Types**: `tsconfig` with `strict: true`; no untyped `any` without justification comment
- **Sanitisation**: DOMPurify for all user-supplied HTML before DOM insertion
- **Auth**: Keycloak JS adapter; never store tokens in `localStorage`
- **Tests**: Vitest >= 80% coverage

## Extension Module Standards

- `discover()` must return `list[dict]` (Chaos Toolkit contract)
- Actions live in `chaos{x}/actions/`; probes in `chaos{x}/probes/`
- Re-export OTel helpers from `chaosotel` -- do not import `opentelemetry` SDK directly
- Every action and probe must emit an OTel span; set `resilience_experiment_id`, `resilience_target`, `resilience_action`, `resilience_outcome` attributes

## Database Standards

- Migrations: Alembic; run `alembic check` in CI -- fails if unapplied migrations exist
- ORM: SQLAlchemy 2.0 `Mapped[]` style only; no legacy `Column()` declarations
- Queries: parameterised only -- `session.execute(text("... WHERE id = :id"), {"id": val})`
- No raw f-string SQL anywhere in the codebase

## Security Standards

- Secrets via env vars; `pydantic-settings` with `SecretStr` fields; fail-fast if absent; never log
- `bandit -r . -ll` -- zero HIGH findings block merge
- `pip-audit` -- zero HIGH/CRITICAL CVEs block merge
- `detect-private-key` pre-commit hook must be enabled in `.pre-commit-config.yaml`

---

## Full Standards Docs

- Reference: `chaostooling-engine/docs/standards/`
- ADRs: `chaostooling-engine/docs/standards/decisions.md`
