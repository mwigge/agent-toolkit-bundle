---
name: security-review
description: >
  Security review for chaos engineering platform: secrets management, parameterised
  SQL, input validation, authentication, OWASP Top 10, prompt injection (LLM/MCP),
  CVE triage, dependency auditing, and Claude Code hook security.
  Activate when adding auth, handling user input, secrets, APIs, or LLM integrations.
version: 2.0.0
argument-hint: "[component or security concern]"
---

# Security Review Skill

## When to activate
- Adding or modifying authentication / authorisation
- Handling user-supplied input or file uploads
- Creating or modifying API endpoints
- Working with secrets, credentials, or tokens
- Integrating LLMs, MCP servers, or external APIs
- Writing or modifying Claude Code hooks
- CVE triage or dependency audit

---

## 1. Secrets Management

**Rule: no hardcoded secrets — ever. Env vars only. Fail-fast if absent. Never log.**

```python
import os

def get_required_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Required env var {name!r} is not set")
    return value

DB_URL    = get_required_env("DATABASE_URL")
API_TOKEN = get_required_env("CHAOS_API_TOKEN")
```

```typescript
function getRequiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Required env var '${name}' is not set`);
  return value;
}
```

Checklist:
- [ ] No literals matching `/api_key|secret|password|token/i` in source
- [ ] `pip-audit` / `npm audit` passes with 0 HIGH/CRITICAL
- [ ] `.env*` files in `.gitignore` and blocked by `security-guard.sh`
- [ ] Secrets never appear in structured logs or OTel span attributes

---

## 2. Parameterised SQL (Python)

```python
# ❌ NEVER — SQL injection vector
cursor.execute(f"SELECT * FROM experiments WHERE id = '{exp_id}'")

# ✅ ALWAYS — parameterised
cursor.execute("SELECT * FROM experiments WHERE id = %s", (exp_id,))

# ✅ SQLAlchemy ORM (preferred for complex queries)
result = session.execute(
    select(Experiment).where(Experiment.id == exp_id)
)
```

The `inline-quality.sh` hook blocks `cursor.execute(f"...)` patterns.

---

## 3. Input Validation

```python
from pydantic import BaseModel, field_validator
import re

class ExperimentRequest(BaseModel):
    experiment_id: str
    target_service: str
    duration_s: int

    @field_validator("experiment_id")
    @classmethod
    def valid_uuid(cls, v: str) -> str:
        if not re.fullmatch(r"[0-9a-f-]{36}", v):
            raise ValueError("experiment_id must be a UUID")
        return v

    @field_validator("duration_s")
    @classmethod
    def reasonable_duration(cls, v: int) -> int:
        if not (1 <= v <= 3600):
            raise ValueError("duration_s must be between 1 and 3600")
        return v
```

---

## 4. Authentication & Authorisation

```python
from functools import wraps
from typing import Callable

def require_role(role: str) -> Callable:
    """Decorator — raises 403 if caller lacks the required role."""
    def decorator(fn: Callable) -> Callable:
        @wraps(fn)
        def wrapper(*args, requester_roles: list[str], **kwargs):
            if role not in requester_roles:
                raise PermissionError(f"Role '{role}' required")
            return fn(*args, requester_roles=requester_roles, **kwargs)
        return wrapper
    return decorator

@require_role("chaos-operator")
def trigger_experiment(experiment_id: str, *, requester_roles: list[str]) -> dict:
    ...
```

---

## 5. OWASP Top 10 — Platform-Relevant Items

| # | Risk | Platform relevance | Mitigation |
|---|---|---|---|
| A01 | Broken Access Control | Experiment trigger API | RBAC + `require_role` decorator |
| A02 | Cryptographic Failures | Secrets in transit | TLS everywhere, no plain HTTP |
| A03 | Injection | Probe commands, SQL queries | Parameterised SQL, no shell injection |
| A04 | Insecure Design | Blast radius unconstrained | Abort criteria + scope checks |
| A05 | Security Misconfiguration | Default credentials, open ports | Env-var secrets, port allowlist |
| A06 | Vulnerable Components | Outdated deps | `pip-audit` + `npm audit` in CI |
| A07 | Auth Failures | API token brute force | Rate limiting + token rotation |
| A09 | Logging Failures | Secrets in logs | Structlog + redact sensitive fields |
| A10 | SSRF | Probe HTTP targets | Allowlist probe target domains |

---

## 6. Prompt Injection (LLM / MCP)

**Critical for any code path that feeds user-controlled text into an LLM.**

Attack vectors:
- User-supplied experiment names/descriptions containing `\n---\nIgnore previous instructions`
- MCP tool descriptions manipulated via supply chain (ToxicSkills pattern)
- Hidden unicode/bidi override characters in skill files (`U+202E`, `U+200B`)

Mitigations:

```python
import unicodedata
import re

BIDI_OVERRIDES = {"\u202a", "\u202b", "\u202c", "\u202d", "\u202e", "\u2066", "\u2067", "\u2068", "\u2069"}
ZERO_WIDTH     = {"\u200b", "\u200c", "\u200d", "\ufeff"}

def sanitise_for_llm(text: str) -> str:
    """Remove hidden control characters before passing to an LLM prompt."""
    # Remove bidi overrides and zero-width chars
    for ch in BIDI_OVERRIDES | ZERO_WIDTH:
        text = text.replace(ch, "")
    # Normalise to NFC
    text = unicodedata.normalize("NFC", text)
    # Remove null bytes
    text = text.replace("\x00", "")
    return text

def validate_prompt_input(text: str, max_len: int = 2000) -> str:
    cleaned = sanitise_for_llm(text)
    if len(cleaned) > max_len:
        raise ValueError(f"Input exceeds {max_len} characters")
    return cleaned
```

Checklist (OWASP MCP Top 10 — relevant items):
- [ ] MCP tool descriptions reviewed before installation
- [ ] Third-party skills audited for embedded prompt injections
- [ ] User input to LLM prompts sanitised (bidi, zero-width, null bytes)
- [ ] LLM output never used as shell command without parsing
- [ ] No tool_call results fed back unsanitised into next prompt

---

## 7. Claude Code Hook Security

Hooks run with the same privilege as the Claude Code process.

Rules:
- Hooks must **never** read or log `CLAUDE_API_KEY`, `JIRA_API_TOKEN`, or other env vars to disk
- Hooks must exit 0 on unexpected input — never crash silently with unhandled errors
- `observe.sh` writes to `.claude/logs/` — ensure this path is in `.gitignore`
- `permission-autoapprove.sh` must not approve `curl | bash` or `eval` patterns
- Audit log (`.claude/audit.log`) must not contain secret values

```bash
# ✅ Safe: log only tool name and truncated command
echo "[$TS] TOOL=$TOOL CMD=${COMMAND:0:100}" >> "$AUDIT"

# ❌ Unsafe: could log env var expansion
echo "[$TS] ENV=$(env)" >> "$AUDIT"
```

---

## 8. Dependency Auditing

Run in CI on every merge to master:

```bash
# Python
pip-audit --strict --desc on   # exit 1 on any HIGH/CRITICAL

# Node/TypeScript
npm audit --audit-level=high   # exit 1 on HIGH/CRITICAL
pnpm audit --audit-level=high
```

In `pyproject.toml` / CI config — pin major versions, use lock files, enable Dependabot.

---

## 9. Error Handling — Never Leak Internals

```python
# ❌ Leaks stack trace and path info
except Exception as exc:
    return {"error": str(exc), "traceback": traceback.format_exc()}

# ✅ Log internally, return generic message
except Exception as exc:
    logger.error("experiment.failed", experiment_id=experiment_id, error=str(exc))
    return {"error": "Experiment failed — see server logs for details"}
```

---

## 10. Supply Chain Security

### Dependency Pinning and Lock Files

- **Always commit lock files** (`pdm.lock`, `pnpm-lock.yaml`, `Cargo.lock`) to the repository
- Pin exact versions in production dependencies — avoid floating ranges (`^`, `~`, `*`)
- Use hash verification where supported (`pip install --require-hashes`, `pnpm` integrity checks)

```bash
# Python — generate hashes for reproducibility
pdm export --format requirements --without-hashes > requirements.txt  # ❌
pdm export --format requirements > requirements.txt                   # ✅ includes hashes

# Node — verify integrity on install
pnpm install --frozen-lockfile   # CI: fail if lockfile is out of date
```

### Typosquatting Detection

Before adding any new dependency, verify the package name:

- Check the official registry for the canonical package name
- Look for suspicious similarity: `reqeusts` vs `requests`, `lodasch` vs `lodash`
- Verify the publisher/maintainer is the expected organisation
- Check download counts — legitimate packages have established download history
- Use namespace/scoped packages where available (`@org/package` in npm)

### License Compliance Scanning

```bash
# Python
pip-licenses --format=csv --with-urls > licenses.csv
# Flag: GPL, AGPL, SSPL in non-GPL projects

# Node
npx license-checker --summary --failOn "GPL-3.0;AGPL-3.0"
```

**Rules**:
- Maintain an approved license allowlist (MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC)
- Flag copyleft licenses (GPL, AGPL, SSPL) for legal review before adoption
- Run license checks in CI — block merges that introduce disallowed licenses

### SBOM Generation

Generate a Software Bill of Materials for every release:

```bash
# Python — CycloneDX format
pdm export --format requirements | cyclonedx-py requirements -i - -o sbom.json

# Node — CycloneDX format
npx @cyclonedx/cyclonedx-npm --output-file sbom.json
```

- Use CycloneDX or SPDX format for interoperability
- Store SBOMs as release artifacts alongside binaries
- Include both direct and transitive dependencies

### Dependency Update Cadence

- Review and update dependencies at least every 30 days
- Prioritise security patches — apply within 48 hours of disclosure for HIGH/CRITICAL
- Use automated dependency update tooling (Dependabot, Renovate) with auto-merge for patch versions
- Track dependency age: any dependency more than 2 major versions behind is a risk

### Transitive Dependency Auditing

Direct dependencies are only part of the attack surface — audit the full dependency tree:

```bash
# Python — full tree
pdm list --tree

# Node — full tree
pnpm list --depth Infinity

# Check for known vulnerabilities in transitive deps
pip-audit --strict       # scans installed packages including transitive
pnpm audit               # scans full dependency tree
```

- Review transitive dependencies when they are > 50% of total dependency count
- Pin transitive dependencies via lock files (never rely on floating resolution)
- Investigate any transitive dependency with fewer than 100 weekly downloads

### Reproducible Builds

Ensure that the same source input always produces the same build output:

- Use lock files with integrity hashes for all dependencies
- Pin build tool versions (language runtime, package manager, compiler)
- Use `--frozen-lockfile` or equivalent in CI to prevent resolution drift
- Container builds: pin base image by digest (`@sha256:...`), not tag
- Document the full build environment in CI configuration

---

## Pre-Deployment Checklist

- [ ] `pip-audit` / `npm audit` — 0 HIGH/CRITICAL
- [ ] No hardcoded secrets (`grep -r 'api_key\s*=' src/` returns 0 matches)
- [ ] All SQL queries parameterised
- [ ] Input validated at API boundary (Pydantic / Zod)
- [ ] RBAC enforced on all mutating endpoints
- [ ] Structured logging — no secrets in log output
- [ ] Prompt inputs sanitised (bidi/zero-width removed)
- [ ] MCP/skill files reviewed for prompt injection
- [ ] `.env*`, `.claude/logs/`, `.claude/audit.log` in `.gitignore`
- [ ] OTel span attributes do not include secret values
