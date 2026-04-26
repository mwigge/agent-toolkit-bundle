# Prompt Retention Policy — AI Development Tooling

**Version**: 1.0 | **Updated**: 2026-04-17

---

## Policy statement

The ai_local setup does **not** log prompt content or model responses to any persistent local store. This is by design — prompt content may contain source code, internal architecture, and (despite the PII guard) potentially personal data. Retaining it locally creates a data-classification burden disproportionate to its diagnostic value.

---

## What IS logged locally

| Log file | What it contains | What it does NOT contain |
|---|---|---|
| `events.ndjson` | Tool metadata: timestamp, session ID, tool name, outcome (ok/blocked/error), risk level (0-3) | No prompt text, no model response text, no file content |
| `model-usage.ndjson` | Per-call: model name, provider, tier, token counts (input/output/cache), cost in USD | No prompt text, no response text |
| `model-summary.ndjson` | Per-session aggregates: call count, token totals, cost totals | No content of any kind |
| `audit.log` | Security events: blocked tool calls, PII pattern detections (pattern name + redacted indicator only) | No actual PII, no prompt text |

---

## What IS retained (with content)

| Artefact | Content | Retention | Classification |
|---|---|---|---|
| **Transcript backups** (`transcript-*.jsonl`) | Full conversation: prompts + responses + tool calls | 10-deep ring buffer (oldest auto-deleted on compaction) | Confidential |

Transcript backups exist because Claude Code's `PreCompact` hook saves the conversation before context compaction. They serve a diagnostic purpose (debugging a bad session) and are classified Confidential per the [data classification policy](data-classification.md).

**Recommendation**: encrypt transcript backups at rest. On macOS, FileVault covers whole-disk; for additional defence-in-depth, consider directory-level encryption for `.claude/backups/`.

---

## Provider-side retention

Prompt content and model responses are sent to cloud model providers. Their retention is governed by each provider's Data Processing Agreement (DPA):

| Provider | Used for | DPA reference |
|---|---|---|
| **Anthropic** (Claude) | Claude Code sessions | Anthropic Commercial Terms of Service; zero-retention API by default for business customers |
| **GitHub** (Copilot) | OpenCode sessions via `github-copilot/claude-sonnet-4.6` | GitHub Copilot for Business DPA; prompt/response not retained for training |
| **OpenAI** (Codex) | Codex sessions | OpenAI Business API DPA; zero-retention on API tier |

**Action**: verify each DPA is signed and on file with the procurement/legal team. If a new provider is added, obtain a DPA before routing production prompts.

---

## PII safeguard

The `pii-guard` hook scans prompt content for PII patterns (PAN, IBAN, email, national IDs) on every `Bash` and `Agent` tool call. If a match is found, the tool call is blocked before the content reaches the provider API. See `pii-patterns.json` for the active pattern set.

This is a technical safeguard, not a guarantee. Engineers should still avoid pasting production log output containing personal data into AI tool sessions.

---

## References

- [Data classification policy](data-classification.md)
- `~/.claude/pii-patterns.json` — active PII detection patterns
- GDPR Art. 5(1)(e) — storage limitation principle
- SOC 2 CC6.1 — logical and physical access controls
