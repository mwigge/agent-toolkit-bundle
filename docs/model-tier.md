# Model Tier Guide

**Updated**: 2026-04-12

Three-tier model routing for OpenCode on Apple Silicon. Local-first, cloud for stakes.

---

## Tiers at a Glance

| Tier | Model | Jobs | Cost | Why |
|------|-------|------|------|-----|
| **Utility** | Qwen 2.5 Coder 14B | `title`, `summary`, `compaction` | $0 | Fast single-shot generation — no reasoning needed |
| **Primary** | Gemma 4 E4B | All 17 local agents | $0 | Thinking mode + 128K context + native tool use |
| **Sign-off** | Claude Sonnet 4.6 | `@reviewer`, `@security`, `explore` | ~$3–15/1M tokens | Frontier quality for adversarial review |

**Rule of thumb**: If sign-off tokens exceed 10% of your weekly total, routing is misconfigured.

---

## Why Gemma 4 E4B for thinking?

A common question. Gemma 4 E4B is a **Mixture-of-Experts** model: 8B total parameters, 4.5B active per forward pass. Despite its small active footprint it has genuine thinking capability:

- `ollama show gemma4:e4b` reports `Capabilities: thinking` — this is a real CoT reasoning mode, not a label
- 128K context window = full codebase fits in a single pass
- Apache-2.0 licensed, runs at ~9.6GB on Metal — same RAM budget as Qwen
- Benchmarks at or above dense 14B models on coding tasks despite fewer active parameters

You would consider upgrading to a larger model (e.g. `gemma4:27b`, `llama3.3:70b`) only if you observe consistent quality failures on complex multi-file refactors — which the `model-report` command will surface as high `tokens_reasoning` with poor output quality correlation.

---

## When does each tier fire?

Controlled by `~/.config/opencode/opencode.json` `agent` routing table:

```
User prompt / @agent-name
        │
        ├─ title / summary / compaction   → Qwen 2.5 Coder 14B  (utility)
        │
        ├─ All 17 local agents            → Gemma 4 E4B          (primary)
        │   (build, plan, general,
        │    @coder-*, @architect, @tester,
        │    @sre, @observability, @api,
        │    @data-*, @product-owner,
        │    @ai-developer, @jira-story,
        │    @refactor)
        │
        └─ @reviewer / @security / explore → Claude Sonnet 4.6   (sign-off)
```

### What the "Compaction · Qwen 2.5 Coder 14B" UI label means

When you see this in the OpenCode status bar:
```
▣  Compaction · Qwen 2.5 Coder 14B · 3m 17s
```
OpenCode is trimming the context window using the local Qwen model. Claude (cloud) was **not** charged. This is the utility tier doing its job — compaction is fast, cost-free, and stays on-device.

---

## Instrumentation

The `model-usage.ts` plugin records every assistant message with tier, token counts, and cost:

```
.claude/logs/model-usage.ndjson        — per-message record
.claude/logs/model-summary.ndjson      — per-session summary (on idle/close)
.claude/logs/model-usage-errors.ndjson — MemPalace write failures
```

Session summaries are also written to MemPalace (`wing_ai_dev / model-usage`) for cross-session sprint and block analysis.

### Reading the data

```bash
# Table view — current project, all sessions
python3 ~/.config/opencode/scripts/model-report.py --cwd "$PWD" --format table

# JSON — this sprint (14 days)
python3 ~/.config/opencode/scripts/model-report.py --cwd "$PWD" sprint

# Last 30 days (block)
python3 ~/.config/opencode/scripts/model-report.py --cwd "$PWD" block
```

Or use the slash command from inside OpenCode:
```
/model-report week
/model-report sprint
/model-report block
```

### Sample output

```
------------------------------------------------------------------------
Tier         Calls    Tok In   Tok Out  Reasoning   Cost USD  % Total
------------------------------------------------------------------------
utility          3     8,400       600          0     0.0000     3.4%
primary         14   187,000     9,800      4,200     0.0000    86.2%
sign-off         2    44,000     6,400          0     0.0820    20.0%  ← ⚠️ if >10%
------------------------------------------------------------------------
TOTAL           19   239,400    16,800      4,200     0.0820   100.0%
------------------------------------------------------------------------

Sessions: 4  |  Compaction events: 3

Routing:  ✅ Routing healthy — sign-off tier < 10% of tokens
Savings:  Utility tier handled 9,000 tokens → estimated $0.0001 cloud cost avoided
```

---

## Routing health thresholds

| Sign-off % of total tokens | Status | Action |
|---------------------------|--------|--------|
| < 10% | ✅ Healthy | No action needed |
| 10–25% | ⚠️ Warning | Review recent `@reviewer` / `@security` invocations — are they warranted? |
| > 25% | 🔴 Alert | Routing misconfigured — check `opencode.json` agent model assignments |

---

## RAM guidance

| RAM | Behaviour |
|-----|-----------|
| 16 GB | One model loaded at a time — Ollama hot-swaps automatically |
| 24 GB | Both Gemma and Qwen comfortably in memory simultaneously |
| 32 GB+ | All three tiers loaded — zero swap latency |

---

## Switching models at runtime

```
/model ollama/gemma4:e4b                 # switch build agent to primary tier
/model ollama/qwen2.5-coder:14b          # switch to utility tier
/model github-copilot/claude-sonnet-4.6  # switch to sign-off tier
```

Subagent `model:` frontmatter overrides are unaffected — they always use their pinned tier.

---

## Adding a new model to the tier map

Edit `~/.config/opencode/plugins/model-usage.ts` and add an entry to `TIER_MAP`:

```typescript
"my-new-model:7b": { tier: "primary", costPer1MOut: 0 },
```

Then update `opencode.json` to route the relevant agents to it. No other changes needed — the plugin picks up the new entry automatically.

---

## MemPalace cross-session analysis

After each session, the plugin writes a compressed summary to MemPalace:
```
SESSION_USAGE:2026-04-12|utility:calls=3,tok_in=8400,...|primary:calls=14,...|total_tok=256200|total_cost_usd=0.0820
```

To query across sessions / sprints / blocks from inside OpenCode:
```
Use mempalace_search with query "SESSION_USAGE" and wing "wing_ai_dev"
```

This gives you a longitudinal view: are you using more cloud over time? Is the primary tier growing as expected? Are compaction events increasing (context getting larger)?

---

## See also

- `local-models.md` — hardware requirements, setup, Ollama commands
- `plugins/model-usage.ts` — instrumentation plugin source (bundle)
- `tools/model-report.py` — aggregation script source (bundle)
- `commands/opencode/model-report.md` — slash command definition (bundle)
