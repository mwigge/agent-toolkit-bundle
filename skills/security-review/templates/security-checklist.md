# Security Review Checklist

Use this checklist before every merge request. Each item must be verifiable from code and repo alone.

---

## 1. Input Validation

- [ ] All external inputs (HTTP params, headers, body, env vars, file paths) are validated before use
- [ ] String lengths are bounded; no unbounded allocation from user input
- [ ] File paths are normalised and checked against an allowed prefix (`os.path.abspath` / `path.resolve`)
- [ ] Enum-like fields are validated against an allowlist, not a denylist
- [ ] JSON / XML / YAML deserialisers are invoked on untrusted data with size and depth limits

## 2. Authentication & Authorisation

- [ ] All endpoints that mutate state require authentication
- [ ] JWTs are verified with a library (`python-jose`, `jsonwebtoken`) — not decoded manually
- [ ] Token expiry (`exp`) and issuer (`iss`) claims are validated
- [ ] Authorisation checks are performed at the service layer, not only the route layer
- [ ] Role/permission checks use deny-by-default logic
- [ ] No `is_admin` flag readable or settable by the user themselves

## 3. Secrets Management

- [ ] No secrets, API keys, tokens, or passwords in source code or committed config files
- [ ] All secrets are read from environment variables at startup; service fails fast if absent
- [ ] No secrets appear in log output, error messages, or HTTP responses
- [ ] `.env` files are listed in `.gitignore`; `detect-secrets` baseline is up to date
- [ ] Secrets are rotated via CI/CD vault, not hardcoded in pipeline YAML

## 4. SQL Injection

- [ ] All DB queries use parameterised statements (`%s` / `$1` placeholders), never string formatting
- [ ] No f-string or `.format()` SQL construction anywhere in the codebase
- [ ] ORM raw-query escape hatches (`text()`, `RawSQL`) are reviewed and justified
- [ ] Dynamic `ORDER BY` / column names are validated against an allowlist

## 5. Cross-Site Scripting (XSS) — Web / API responses

- [ ] HTML responses use auto-escaping templates (Jinja2 autoescape=True, React JSX)
- [ ] `Content-Type` headers are explicit; JSON responses are `application/json`
- [ ] `Content-Security-Policy` header is set; `unsafe-inline` is absent or justified
- [ ] User-supplied URLs are validated to `https://` scheme before rendering as links

## 6. CSRF

- [ ] State-mutating endpoints (POST/PUT/PATCH/DELETE) require a CSRF token or use `SameSite=Strict` cookies
- [ ] CORS `Access-Control-Allow-Origin` is not `*` for credentialed requests
- [ ] Preflight OPTIONS handling does not bypass auth middleware

## 7. Dependency Auditing

- [ ] `pip-audit` (Python) or `npm audit --audit-level=high` (Node) passes with zero HIGH/CRITICAL findings
- [ ] No dependencies with known CVEs are pinned at a vulnerable version without a documented exception
- [ ] Lock files (`pdm.lock` / `pnpm-lock.yaml`) are committed and match `pyproject.toml` / `package.json`
- [ ] Transitive dependency versions are pinned in the lock file

## 8. Logging & PII

- [ ] No personally identifiable information (email, name, address, IP, session ID) is written to logs
- [ ] Passwords and tokens are never logged, even at DEBUG level
- [ ] Structured logging is used (`structlog`, `python-json-logger`, `pino`); no raw `print()` calls
- [ ] Log levels are appropriate: DEBUG for internals, INFO for business events, ERROR for failures
- [ ] Log output does not include stack traces in production HTTP responses

## 9. API Security

- [ ] Rate limiting is applied to authentication and resource-intensive endpoints
- [ ] Pagination is enforced on list endpoints; no unbounded queries
- [ ] `4xx` responses do not leak internal paths, stack traces, or DB schema details
- [ ] HTTP methods are restricted to those actually needed per route
- [ ] Sensitive fields (passwords, tokens) are excluded from response serialisers

## 10. Cryptography

- [ ] Password hashing uses `bcrypt`, `argon2`, or `scrypt` — not MD5, SHA-1, or SHA-256 alone
- [ ] Random tokens use `secrets.token_urlsafe()` (Python) or `crypto.randomBytes()` (Node)
- [ ] TLS 1.2+ is enforced; no SSLv3/TLS 1.0/1.1 in service config
- [ ] Symmetric encryption uses AES-256-GCM or ChaCha20-Poly1305; no ECB mode

## 11. Chaos Engineering — Domain-Specific

- [ ] Chaos actions require explicit scope parameters; no implicit "affect all" defaults
- [ ] Experiment definitions require a `rollback` stanza before execution is permitted
- [ ] Blast radius is bounded by config (max affected instances, max duration)
- [ ] Chaos actions do not log target credentials or connection strings
- [ ] Dry-run / hypothesis-only mode is available and does not mutate production state
- [ ] OTel spans emitted by chaos actions do not include secret values in attributes

## 12. Infrastructure & Container

- [ ] Container images run as a non-root user
- [ ] No `--privileged` flag or dangerous capabilities (`SYS_ADMIN`, `NET_ADMIN`) without justification
- [ ] Health-check endpoints do not require authentication but return no sensitive data
- [ ] Environment variables injected into containers come from a secrets manager, not plain CI variables

---

## Sign-off

| Area | Reviewer | Status |
|------|----------|--------|
| Input validation | | |
| Auth / Authz | | |
| Secrets | | |
| SQL injection | | |
| Dependencies | | |
| Logging / PII | | |
| API security | | |
| Chaos-specific | | |

**Reviewed by**: _______________  
**Date**: _______________  
**MR**: _______________
