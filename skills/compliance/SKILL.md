---
name: compliance
description: Use when handling regulatory requirements, audit evidence, or control mappings for GDPR, DORA, PCI-DSS 4.0, ISO 27001, or SOC 2.
---

# Skill: Compliance — GDPR, DORA, PCI-DSS, ISO 27001, SOC 2

**Coverage**: GDPR (data protection) · DORA (operational resilience, EU financial sector) · PCI-DSS 4.0 (payment card security) · ISO 27001 (information security) · SOC 2 (trust services)

**See also**: `refs/dora.md` (DORA article-to-control mapping) · `refs/pci-dss.md` (PCI-DSS requirement-to-hook mapping) · `refs/REFERENCES.md` (external links)

---

## GDPR Essentials for Engineers

### Lawful basis (Article 6)

Every processing activity must have a documented lawful basis. The six bases:

| Basis | When to use | Engineering implication |
|-------|-------------|------------------------|
| Consent | User has given clear, specific consent | Store consent with timestamp and version; implement withdrawal |
| Contract | Processing is necessary to perform a contract with the data subject | Only process what is necessary for the contract |
| Legal obligation | Processing is required by law | Document the specific law; do not over-collect |
| Vital interests | Protect someone's life | Narrow; rarely applicable in software |
| Public task | Official authority processing | Public sector only |
| Legitimate interests | Balancing test: your interests vs data subject rights | Requires documented Legitimate Interest Assessment (LIA) |

### Data minimisation and purpose limitation

- Collect only what is necessary for the stated purpose
- Do not repurpose data for secondary uses without a new lawful basis
- Every field in your data model must have a documented purpose
- Delete data when the purpose is fulfilled — implement TTL and deletion jobs

### Right to erasure (Article 17)

Requirements:
- Must complete erasure within 30 days of request
- Covers all systems: primary DB, backups, logs, analytics pipelines, third-party processors
- Pseudonymised data may be retained if re-identification is genuinely impossible
- Implement a deletion audit log: record who requested deletion, when it was processed, and which systems were purged

### Data breach notification (Article 33 / 34)

- Notify your Data Protection Authority (DPA) within **72 hours** of becoming aware of a breach
- If breach is likely to result in high risk to individuals, notify affected data subjects "without undue delay"
- Document all breaches, including ones that do not require notification
- Incident response process must include GDPR breach assessment as a step

### Data Processing Agreement (DPA)

Required when a controller uses a processor (a vendor who processes data on your behalf):
- Must specify: purpose, data categories, retention, sub-processors, security measures, deletion procedure
- Sub-processors must be listed and updated; controllers must be notified of changes
- Use the template at `templates/dpa-checklist.md`

---

## PII Classification

| Category | Examples | Handling |
|----------|---------|---------|
| **Direct identifiers** | Full name, email, national ID, passport number, phone | Encrypt at rest and in transit; access controls; audit log |
| **Quasi-identifiers** | Date of birth, postcode, employer, job title | Combination risk — assess re-identification risk before publishing |
| **Sensitive categories (Art. 9)** | Health data, racial/ethnic origin, political opinions, religious beliefs, biometric data, sexual orientation, criminal convictions | Explicit consent or specific exemption required; higher security bar |

### Pseudonymisation vs anonymisation

- **Pseudonymisation**: replace identifying data with a token that can be reversed with a key. Still personal data under GDPR; key must be protected separately.
- **Anonymisation**: irreversible removal of identifying information to the point that re-identification is not reasonably possible. No longer personal data under GDPR — but this bar is high.

### Retention periods

- Define retention periods for every data category
- Implement automated deletion / archival jobs
- Document retention periods in the data register
- Back up retention rules: if data is in a backup, the retention rule still applies

### Technical controls

- Encryption at rest: AES-256 minimum; key management via vault
- Encryption in transit: TLS 1.2 minimum; TLS 1.3 preferred
- Database-level: encrypt individual sensitive fields, not just the disk
- Never log PII: no email addresses, national IDs, or card numbers in application logs

---

## ISO 27001 Control Families (ISO/IEC 27001:2022 Annex A)

| Family | Key controls relevant to engineers |
|--------|-------------------------------------|
| **A.8 Asset Management** | Data classification, acceptable use, secure disposal of media |
| **A.9 Access Control** | Principle of least privilege, access reviews, privileged access management |
| **A.10 Cryptography** | Cryptographic policy, key management, approved algorithms |
| **A.12 Operations Security** | Change management, capacity management, malware protection, backup |
| **A.14 System Acquisition** | Security in SDLC, secure coding, security testing in CI/CD |

### Engineer-facing controls

- **Access control**: every system access must be role-based; no shared accounts; MFA required for all privileged access
- **Change management**: all production changes via version-controlled code review; no manual production changes without incident record
- **Cryptography**: maintain an approved algorithm list; review annually; HS256 for JWT is prohibited — use RS256 or ES256
- **Vulnerability management**: CVE scanning in CI; critical CVEs patched within 30 days; high CVEs within 90 days
- **Logging and monitoring**: all administrative actions logged; all authentication events logged; logs retained ≥1 year

---

## SOC 2 Trust Service Criteria

| Principle | Description |
|-----------|-------------|
| **Security (CC)** | Protection against unauthorised access — required for all SOC 2 reports |
| **Availability** | System is available as committed |
| **Confidentiality** | Information designated as confidential is protected |
| **Processing Integrity** | System processing is complete, accurate, timely, and authorised |
| **Privacy** | PII is collected, used, and disclosed in accordance with the privacy notice |

### Common Criteria relevant to engineers

| CC | Description | Engineering control |
|----|-------------|-------------------|
| CC6.1 | Logical and physical access controls | RBAC, MFA, VPN for production |
| CC6.3 | Remove or modify access | Offboarding process; quarterly access review |
| CC6.6 | Logical access restrictions | Network segmentation; WAF; API authentication |
| CC7.2 | Monitor for anomalies | SIEM integration; alert on failed login patterns |
| CC7.4 | Respond to identified security incidents | Incident response process; runbooks |
| CC8.1 | Authorise and approve infrastructure changes | Change management process; code review gates |

---

## Audit Logging Requirements

Every audit log event must answer: **who** did **what** to **which resource**, **when**, and **from where**.

### Mandatory fields

| Field | Type | Description |
|-------|------|-------------|
| `actor` | object | Identity of the user or service performing the action |
| `actor.id` | string | User ID or service account ID |
| `actor.type` | enum | `user` or `service` |
| `action` | string | Verb describing the action: `create`, `read`, `update`, `delete`, `login`, `logout`, `export` |
| `resource` | object | The object acted upon |
| `resource.type` | string | Resource type: `experiment`, `user`, `config` |
| `resource.id` | string | Resource identifier |
| `timestamp` | string | ISO 8601 with timezone: `2026-04-05T14:32:00Z` |
| `ip_address` | string | Source IP of the request |
| `outcome` | enum | `success` or `failure` |
| `correlation_id` | string | Request / trace ID for cross-system correlation |

### Additional requirements

- **Tamper-evident**: use append-only storage or cryptographic chaining; audit log rows must not be updatable or deletable via the application
- **Retention**: minimum 1 year; 3 years for SOC 2 environments
- **Immutability**: SOC 2 requires that logs cannot be modified; use write-once storage or WORM-compliant log sinks
- **Separate store**: audit logs must not share a database with application data — compromise of the application must not compromise the audit log
- **What to log**: all authentication events; all privilege escalations; all access to sensitive data; all administrative actions; all data exports

---

## Secrets Management

| Rule | Detail |
|------|--------|
| No secrets in code | No hardcoded passwords, tokens, or API keys — ever, including in tests |
| No secrets in config files | `.env` files must never be committed; use vault or environment injection |
| Rotate ≤90 days | All static secrets must be rotated at least every 90 days; automate where possible |
| Key custodians | Document who is responsible for each key or secret class |
| OIDC / Workload Identity | Prefer short-lived, automatically rotated credentials over static secrets in CI/CD |
| Vault | All long-lived secrets stored in HashiCorp Vault or equivalent; access is audited |

---

## Vendor / Third-Party Assessment

Before integrating a new vendor that will process personal data:

1. **Data Processing Agreement**: obtain a signed DPA before processing begins
2. **Sub-processor list**: confirm and document which sub-processors the vendor uses
3. **Data residency**: confirm which countries data is stored in; verify adequacy for GDPR transfers
4. **Security questionnaire**: ISO 27001 / SOC 2 / equivalent certification or completed questionnaire
5. **Breach notification**: confirm vendor's process for notifying you within a timeframe that allows your 72-hour DPA notification

Document all vendor assessments in the vendor register.
