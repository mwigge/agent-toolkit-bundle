# PCI-DSS 4.0 — Requirements Relevant to AI-Assisted Development

**Applies to**: Worldline as a payment processor handling cardholder data.
**Version**: PCI-DSS 4.0 (March 2022, mandatory March 2025).

AI-assisted development tools touch codebases that process, store, or transmit cardholder data. PCI-DSS Requirements 6 (secure development), 7 (access control), and 10 (logging and monitoring) apply directly to the tooling used to build and maintain those systems.

---

## Requirements mapped to ai_local controls

### Req. 6.2 — Secure Software Development

Bespoke and custom software is developed securely.

| Sub-requirement | ai_local control | Status |
|---|---|---|
| 6.2.1 — No hardcoded authentication credentials | `security-guard` hook — regex scan blocks `api_key\|secret_key\|password\|token = "..."` in file content | Implemented |
| 6.2.2 — Software reviewed for vulnerabilities | `@reviewer` agent — adversarial 4-lens code review (correctness, security, maintainability, test rigour) | Implemented |
| 6.2.3 — Custom software reviewed prior to release | `quality-gate` hook — lint/type/security checks on every changed file at end-of-turn | Implemented |
| 6.2.4 — Injection prevention | CLAUDE.md / AGENTS.md — "parameterised SQL only" non-negotiable rule; `quality-gate` blocks bare `cursor.execute(f"...")` | Implemented |

### Req. 6.3 — Security Vulnerabilities Identified and Addressed

| Sub-requirement | ai_local control | Status |
|---|---|---|
| 6.3.1 — Vulnerability identification | `@security` agent loads `/security-review` skill — runs `security_scan.sh` at start of every review | Implemented |
| 6.3.2 — Inventory of bespoke software | OpenSpec change tracking — every change has a proposal, design, and task list | Implemented |
| 6.3.3 — Software updated to address known vulnerabilities | Renovate Bot — automated dependency updates across all repos | Implemented |

### Req. 7.1 — Access to System Components and Cardholder Data is Restricted

| Sub-requirement | ai_local control | Status |
|---|---|---|
| 7.1.1 — Access control policies | `mode-guard` hook — company/private path separation enforced on every tool call | Implemented |
| 7.1.2 — Access based on job function | `permission-policy.md` — 3-tier classification (GREEN/YELLOW/RED); `permission-autoapprove.sh` enforces | Implemented |

### Req. 10.1 — Logging and Monitoring

Audit logs that record user activities, exceptions, and security events are implemented.

| Sub-requirement | ai_local control | Status |
|---|---|---|
| 10.1.1 — Audit log of all access | `observe.sh` / `observe.ts` — per-tool NDJSON log with timestamp, session, tool, outcome, risk | Implemented |
| 10.1.2 — Audit log protected from modification | — | **GAP** |
| 10.1.3 — Audit logs promptly available for analysis | `events.ndjson` — local file, immediately readable | Implemented |

### Req. 10.5 — Audit Log History is Retained and Accessible

| Sub-requirement | ai_local control | Status |
|---|---|---|
| 10.5.1 — Retain audit log history for at least 12 months | `audit.log` — retained per SOC 2 (3 years); `events.ndjson` — 90-day rotation (planned) | Partial |
| 10.5.1.1 — Audit log review mechanisms | Risk scoring (0-3) in `observe.sh`; risk-3 events double-written to `audit.log` | Implemented |

---

## Primary gap: tamper-evident audit logs (Req. 10.1.2 / 10.5)

PCI-DSS Req. 10.1.2 requires audit logs to be protected from unauthorised modification. The current `events.ndjson` is an append-only file by convention — anyone with file access can edit or delete entries.

**Planned mitigation** (tracked in `ai-tooling-security-and-observability`):
- Option A: cryptographic hash chain on each NDJSON entry (local tamper-evidence)
- Option B: ship audit events to a centralised SIEM (Loki) where immutability is managed
- Option C: both

Until implemented, this is a documented gap with compensating controls:
- macOS FileVault / Linux LUKS for whole-disk encryption
- Risk-3 events are double-written to `audit.log` (separate file, same limitation)

---

## References

- [PCI-DSS 4.0 Requirements](https://www.pcisecuritystandards.org/document_library/)
- `ai_local/docs/data-classification.md` — data classification policy
- `ai_local/.claude/permission-policy.md` — 3-tier access control
- `ai-tooling-security-and-observability` OpenSpec change — tamper-evident audit planned
