# Data Classification — AI Development Tooling

**Version**: 1.0 | **Updated**: 2026-04-17

This document classifies every artefact type produced or consumed by the ai_local setup and states the handling requirements per classification level.

---

## Classification levels

| Level | Definition | Examples |
|---|---|---|
| **Public** | No restrictions. Safe to share externally. | Open-source skill documentation, public tool versions |
| **Internal** | Worldline-internal only. No external sharing without approval. | Token counts, cost summaries, tool metadata, symbol indexes |
| **Confidential** | Contains proprietary architecture, code, or planning detail. Access restricted to the project team. | Source code in prompts, design documents, full conversation transcripts |
| **Restricted** | Contains security-critical or regulatory-sensitive data. Logged, encrypted, access-audited. | Security audit events, PII detection events, credentials (should never exist in this tier — but if they do, this is the handling) |

---

## Artefact classification

| Artefact | Classification | Content | Handling |
|---|---|---|---|
| **Prompt content** (sent to model API) | Confidential | May contain source code, internal architecture, planning detail. PII guard prevents personal data. | Not logged locally. Sent to provider under DPA. PII-guard hook scans before transmission. |
| **Model responses** (received from API) | Confidential | Generated code, explanations, plans. May reflect proprietary architecture. | Not logged locally. Consumed in session only. |
| **events.ndjson** | Internal | Tool metadata: timestamp, tool name, outcome, risk level. No prompt content, no response content. | Retained locally. Rotate at 50 MB. No external sharing. |
| **model-usage.ndjson** | Internal | Per-call: model, provider, tier, token counts, cost. No content. | Retained locally. Rotate at 50 MB. Aggregate to MemPalace for cross-session analysis. |
| **model-summary.ndjson** | Internal | Per-session: call count, token totals, cost totals. No content. | Retained locally. |
| **audit.log** | Restricted | Security events: blocked tool calls, PII detections, risk-3 events. Contains pattern names but never actual PII. | Retained per SOC 2 (3 years). Tamper-evident (planned). Access restricted to security reviewers. |
| **MemPalace content** | Confidential | Planning artefacts, decisions, designs, gate feedback. May reference internal architecture and team decisions. | Stored locally in SQLite. Not shared externally. Encrypted at rest recommended (macOS FileVault / Linux LUKS). |
| **CodeGraph index** | Internal | Symbol names, file paths, call relationships. No source code content — only structural metadata. | Stored locally in SQLite. Rebuilt on demand from source. |
| **Transcript backups** (`.claude/backups/transcript-*.jsonl`) | Confidential | Full conversation including prompt content and model responses. | 10-deep ring buffer. Encrypted at rest recommended. Oldest automatically deleted. Not shared externally. |
| **pii-patterns.json** | Internal | PII detection regex patterns. No sensitive data itself. | Version-controlled in ai_local. Shared across all team members via install.sh. |
| **pii-guard-allowlist.txt** | Internal | Known-safe strings that bypass PII detection. May contain test card numbers. | Version-controlled. Reviewed on change. |

---

## Handling requirements by level

| Requirement | Public | Internal | Confidential | Restricted |
|---|---|---|---|---|
| External sharing | Allowed | Approval required | Prohibited | Prohibited |
| Encryption at rest | Not required | Recommended (FileVault/LUKS) | Recommended | Required |
| Access logging | Not required | Not required | Recommended | Required (audit.log) |
| Retention policy | None | 90 days (log rotation) | Session-scoped or 10-deep ring | 3 years (SOC 2) |
| Backup | Not required | Not required | Ring buffer (transcript-backup) | Immutable backup (planned) |
