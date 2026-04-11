# Skill: Documentation

## Diátaxis Framework — Mandatory

Before writing any document, identify its type. Never mix types in a single document.

| Type | Orientation | Reader's state | Writer's obligation |
|------|-------------|---------------|-------------------|
| **Tutorial** | Learning | "I want to learn" | Guide through a complete, meaningful task. Every step must work. |
| **How-To Guide** | Task | "I want to achieve X" | List steps to accomplish a specific goal. Assumes competence. |
| **Explanation** | Understanding | "I want to understand" | Provide context, background, trade-offs. No step-by-step instructions. |
| **Reference** | Information | "I need to look up X" | Be complete, accurate, and consistent. No narrative. |

### Common mistakes

- Tutorial that turns into a reference (starts teaching, then dumps all options)
- How-to guide with teaching tangents ("before we do X, let's understand why...")
- Explanation that includes instructions ("and to enable this, run...")
- Reference that includes opinions or narrative prose

---

## ADR (Architecture Decision Record)

Use ADRs to record significant architectural decisions. Write one *when the decision is made*, not retrospectively.

### Naming

```
docs/adr/ADR-001-use-postgresql-for-primary-store.md
docs/adr/ADR-002-adopt-opentelemetry-for-observability.md
```

Auto-increment ADR number. Never reuse numbers, even for superseded ADRs.

### Status lifecycle

```
proposed → accepted → deprecated → superseded by ADR-NNN
```

Once accepted, never edit the decision. Add a new ADR instead.

### Mandatory sections

1. **Number and Title**: `ADR-NNN: Decision title`
2. **Date**: `YYYY-MM-DD`
3. **Status**: `Proposed | Accepted | Deprecated | Superseded by ADR-NNN`
4. **Context**: What situation forces this decision? What constraints exist?
5. **Decision**: What was decided? State it clearly and directly.
6. **Consequences**: What are the positive and negative consequences of this decision?
7. **Alternatives considered**: What else was evaluated? Why were alternatives rejected?

---

## RFC (Request for Comments)

Use RFCs for significant proposals that require team input before a decision is made.

### When to write an RFC

- The change affects multiple teams or systems
- The change is irreversible or costly to reverse
- The approach is novel or contentious
- The estimated effort is >1 week

### RFC lifecycle

```
Draft → Open for Comment → Accepted | Rejected | Withdrawn
```

Set a comment deadline (typically 2 weeks). After acceptance, write an ADR to record the decision.

### Required sections

1. Problem statement — what problem are you solving?
2. Proposed solution — with enough detail to evaluate it
3. Alternatives — at least two meaningful alternatives
4. Open questions — what is still unresolved?
5. Success criteria — how will you know if this worked?
6. Timeline — when will this be implemented?

---

## CHANGELOG.md

Keep a CHANGELOG.md in every repository using the keepachangelog.com format.

```markdown
# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added
- [<PROJ>-123] Circuit breaker for payment client with configurable thresholds

### Fixed
- [<PROJ>-123] Null pointer when user has no payment method on file

## [1.2.0] — 2026-03-15

### Added
- Resilience score v2 methodology

### Changed
- Error budget burn rate alerting uses 6h window instead of 1h

### Removed
- Legacy v1 API endpoints (deprecated in 1.0.0)
```

Rules:
- `[Unreleased]` section is always present; move entries to a versioned section on release
- Categories: `Added` / `Changed` / `Deprecated` / `Removed` / `Fixed` / `Security`
- Each entry references a Jira ticket and is readable without knowing the code
- Never say "misc fixes" — describe the fix

---

## API Documentation — OpenAPI 3.1

Every REST API must have an OpenAPI 3.1 specification.

### Minimum required fields per endpoint

```yaml
/experiments/{id}:
  get:
    summary: Retrieve an experiment by ID        # short, imperative verb phrase
    description: |                               # explain when to use this endpoint
      Returns the full experiment definition including hypothesis,
      actions, probes, and current status.
      Only accessible to users with the `experiments:read` scope.
    operationId: getExperiment                   # camelCase, unique across the spec
    tags: [experiments]
    parameters:
      - name: id
        in: path
        required: true
        schema:
          type: string
          format: uuid
        description: The experiment UUID
    responses:
      "200":
        description: Experiment found
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Experiment'
            example:                             # concrete example, not schema
              id: "550e8400-e29b-41d4-a716-446655440000"
              title: "Kill payment service primary pod"
              status: "completed"
      "404":
        $ref: '#/components/responses/NotFound'
      "401":
        $ref: '#/components/responses/Unauthorised'
```

Rules:
- No undocumented fields — every field in the schema must have a `description`
- Provide at least one request and one response example for every endpoint
- Document all error responses (401, 403, 404, 422, 500)
- Use `$ref` for reusable schemas, parameters, and responses
- Keep the spec in the repository; generate it from code annotations where possible

---

## Code Documentation

### Python — Google style docstrings

```python
def calculate_burn_rate(
    error_count: int,
    total_count: int,
    window_hours: float,
    slo_target: float,
) -> float:
    """Calculate the error budget burn rate for a given window.

    The burn rate is the ratio of actual error rate to the maximum allowable
    error rate implied by the SLO. A burn rate of 1.0 means the budget is
    being consumed at exactly the SLO-allowed pace. A burn rate >1 means
    faster-than-allowed consumption.

    Args:
        error_count: Number of failed requests in the window.
        total_count: Total number of requests in the window.
        window_hours: Duration of the measurement window in hours.
        slo_target: SLO success rate as a decimal (e.g. 0.999 for 99.9%).

    Returns:
        The burn rate as a float. Values >1 indicate over-budget consumption.

    Raises:
        ValueError: If total_count is zero or slo_target is not in (0, 1).

    Example:
        >>> calculate_burn_rate(10, 10_000, 1.0, 0.999)
        1.0
    """
```

Rules:
- Document *why*, not *what* — the code shows what; the docstring explains why
- All public functions, methods, and classes require docstrings
- Private functions (`_prefixed`) need docstrings only if non-obvious
- Include `Raises` section for any exception the caller must handle

### TypeScript — JSDoc

```typescript
/**
 * Verifies an access token and returns the decoded payload.
 *
 * Validates signature, expiry, issuer, and audience. Does NOT make a network
 * call — uses local JWKS cache. Call {@link refreshJwks} to update the cache.
 *
 * @param token - Raw JWT string from the Authorization header (without "Bearer " prefix)
 * @param options - Verification options; defaults use environment configuration
 * @returns Decoded, verified token payload
 * @throws {AuthError} If the token is expired, invalid, or signed by an unknown key
 *
 * @example
 * const payload = await verifyAccessToken(req.headers.authorization?.slice(7) ?? '');
 * console.log(payload.sub); // user ID
 */
async function verifyAccessToken(token: string, options?: VerifyOptions): Promise<TokenPayload>
```

---

## README Structure

Every repository README must contain these sections in order:

1. **Badges** — build status, coverage, latest version, licence
2. **One-line description** — what the service does and who uses it
3. **Quick start** — working in ≤5 commands from a clean checkout
4. **Configuration** — required environment variables with descriptions and examples
5. **Full documentation link** — link to the docs site or `docs/` directory
6. **Contributing** — how to set up locally, run tests, submit changes
7. **Licence** — SPDX identifier

Quick start must actually work. Test it from a clean environment before committing.

---

## Writing Rules

- **Active voice**: "The function validates the token" not "The token is validated by the function"
- **Present tense**: "Returns the user ID" not "Will return the user ID"
- **Second person**: "You can configure X by..." not "The user can configure X by..."
- **Concrete examples**: every concept should have a concrete example; abstract explanations without examples are incomplete
- **One idea per paragraph** in explanatory text
- **Define acronyms on first use** and use the acronym consistently thereafter
