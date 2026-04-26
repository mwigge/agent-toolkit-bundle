# DORA — Digital Operational Resilience Act (EU 2022/2554)

**Applies to**: Worldline as a regulated payment institution within the EU.
**Effective**: 17 January 2025.

DORA requires financial entities to demonstrate ICT operational resilience through documented testing, incident classification, and measurable recovery capabilities. The ai_local setup — and the Resilience Platform it builds — directly supports several DORA obligations.

---

## Articles relevant to AI-assisted development tooling

### Art. 5-6 — ICT Risk Management Framework

Financial entities shall establish an ICT risk management framework that identifies, classifies, and mitigates ICT risks.

| Obligation | ai_local control | Status |
|---|---|---|
| Access control policies | `mode-guard` hook — enforces company/private path separation on every tool call | Implemented |
| Secure development practices | `security-guard` hook — blocks hardcoded secrets, destructive commands, protected file writes | Implemented |
| Change management | `quality-gate` hook — lint/type/security checks on every changed file at end-of-turn | Implemented |
| Configuration management | `ai_local/install.sh` — single source of truth, symlinked to all clients | Implemented |
| Data classification | `ai_local/docs/data-classification.md` — classifies all AI tooling artefacts | Implemented |
| PII protection | `pii-guard` hook — scans prompt content for PANs, IBANs, emails before API call | Implemented |

### Art. 11 — Incident Classification and Reporting

Financial entities shall classify ICT-related incidents and report major incidents to competent authorities.

| Obligation | ai_local control | Status |
|---|---|---|
| Incident detection | `observe.sh` risk scoring (0-3) — risk-3 events double-logged to `audit.log` | Implemented |
| Incident classification | Risk levels map to severity: 3=critical (destructive/exfiltration), 2=high (protected files), 1=medium (writes), 0=info | Implemented |
| Audit trail | `events.ndjson` — per-tool NDJSON log with session, timestamp, tool, outcome, risk | Implemented |
| Tamper-evident logs | Hash chain on `events.ndjson` | GAP — planned in `ai-tooling-security-and-observability` |

### Art. 23-25 — Digital Operational Resilience Testing

Financial entities shall conduct a range of tests including vulnerability assessments, scenario-based testing, and resilience testing.

| Obligation | ai_local control | Status |
|---|---|---|
| Resilience testing programme | The Resilience Platform (chaostooling-engine) — chaos + robustness experiments | Platform-level |
| Test coverage | Resilience score + fault-class coverage matrix | Platform-level |
| Test evidence | `chaostooling-reporting` — PDF/HTML per experiment run | Platform-level |
| Test tooling security | `security-guard` + `pii-guard` + `permission-policy` protect the tooling that builds the tests | Implemented |

### Art. 26 — Threat-Led Penetration Testing (TLPT)

Financial entities identified by competent authorities shall carry out advanced testing by means of TLPT.

| Obligation | ai_local control | Status |
|---|---|---|
| SSH-based fault injection | `chaostooling-extension-network` SSH chaos actions (CLS-327) — tunnel disruption, connection exhaustion, key rotation | Implemented |
| HTTP fault injection | `http-fault-injection` (HFI-1, planned W19-23) — tc/iptables, SDK monkey-patch, proxy, TLS | Planned |
| Database fault injection | `chaostooling-extension-db` — PostgreSQL, MySQL, MSSQL, MongoDB, Redis, Cassandra actions | Implemented |
| Application fault injection | `chaostooling-extension-app` — application-layer chaos actions | Implemented |

---

## Summary

DORA compliance for the AI development tooling is largely addressed by the existing hook framework (Art. 5-6, Art. 11) and the Resilience Platform itself (Art. 23-26). The primary gap is **tamper-evident audit logs** (Art. 11 / SOC 2 CC7.2), tracked in the `ai-tooling-security-and-observability` change.

---

## References

- [EU Regulation 2022/2554 (DORA)](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32022R2554)
- [EBA Guidelines on ICT risk management](https://www.eba.europa.eu/regulation-and-policy/internal-governance/guidelines-on-ict-and-security-risk-management)
- `ai_local/docs/data-classification.md` — data classification policy
- `ai_local/docs/ropa-ai-tooling.md` — ROPA entry for AI tooling
