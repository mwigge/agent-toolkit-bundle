# Local Models via Ollama

Run Gemma 4 and Qwen locally for cost-effective development. Models run on Apple Silicon via Metal acceleration — no GPU required.

## Setup

```bash
# Install Ollama
brew install ollama

# Start with performance optimisations
brew services start ollama

# Pull models
ollama pull devstral:24b          # ~9.6GB — primary model (thinking + tools + 128K context)
ollama pull devstral:24b   # ~9GB   — fast tasks (title, summary, compaction)
```

> **Zscaler note**: `ollama pull` may return a 403 on corporate networks. Use the manual manifest injection workaround — see `docs_local/ollama_zscaler.md`.

## Hardware Requirements

| RAM | Recommendation |
|-----|---------------|
| 16GB | Run one model at a time |
| 24GB | Run either model comfortably, swap as needed |
| 32GB+ | Both models loaded simultaneously |

Ollama automatically loads/unloads models based on available memory.

## Model Selection Guide

| Model | Size (Q4) | Strength | Tier |
|-------|-----------|----------|------|
| Devstral 24B | ~9.6GB | Thinking mode, tool use, 128K context, coding + reasoning | Local — primary |
| Devstral 24B | ~9GB | Fast, code-focused, tool use, low latency | Local — utility |
| Claude Sonnet (GitHub Copilot) | cloud | Multi-step reasoning, adversarial review, security audit | Cloud — sign-off |

### Why Devstral 24B as primary

`devstral:24b` is a Mixture-of-Experts edge model with 4.5B active parameters (8B total). Despite its small active footprint it has:
- **Thinking mode** — configurable reasoning before answering (enable with `<|think|>` in system prompt)
- **128K context window** — 4× larger than devstral:24b
- **Native tool use** — function calling without workarounds
- Comparable coding benchmarks to larger models at the same memory cost (~9.6GB)

---

## Model Routing

Each OpenCode agent is pinned to a model via the `model:` field in its frontmatter (`~/.config/opencode/agents/<agent>.md`). The orchestrator (`build` agent) defaults to Devstral 24B.

### Routing table

| Model | Agents | Rationale |
|-------|--------|-----------|
| `ollama/devstral:24b` | `build` (orchestrator), `coder-python`, `coder-sql`, `coder-tdd`, `coder-typescript`, `architect`, `data-analyst`, `data-engineer`, `jira-story`, `product-owner`, `refactor`, `observability`, `sre`, `tester`, `api`, `ai-developer` | Thinking + tools + 128K context covers all local workloads |
| `ollama/devstral:24b` | `title`, `summary`, `compaction` | Fast single-shot generation, low latency, no reasoning needed |
| `github-copilot/claude-sonnet-4.6` | `reviewer`, `security`, `explore` (built-in) | Adversarial review and threat modelling where stakes are high |

### Built-in OpenCode agents

| Built-in | Model | Rationale |
|----------|-------|-----------|
| `build` | `ollama/devstral:24b` | Default orchestrator — thinking-capable local model |
| `plan` | `ollama/devstral:24b` | Task decomposition — thinking mode beneficial |
| `general` | `ollama/devstral:24b` | General subagent — complex multi-step tasks |
| `explore` | `github-copilot/claude-sonnet-4.6` | Read-only exploration — cloud for depth |
| `title` | `ollama/devstral:24b` | Single-line generation — fast local |
| `summary` | `ollama/devstral:24b` | Compaction summary — fast local |
| `compaction` | `ollama/devstral:24b` | Context compaction — fast local |

---

## OpenCode Configuration

The relevant section of `~/.config/opencode/opencode.json`:

```json
{
  "model": "ollama/devstral:24b",
  "agent": {
    "build":      { "model": "ollama/devstral:24b" },
    "plan":       { "model": "ollama/devstral:24b" },
    "general":    { "model": "ollama/devstral:24b" },
    "explore":    { "model": "github-copilot/claude-sonnet-4.6" },
    "title":      { "model": "ollama/devstral:24b" },
    "summary":    { "model": "ollama/devstral:24b" },
    "compaction": { "model": "ollama/devstral:24b" }
  }
}
```

Custom agent frontmatter example:

```markdown
---
description: Adversarial code review using four lenses.
mode: subagent
model: github-copilot/claude-sonnet-4.6
---
```

---

## Switching Models at Runtime

```
/model ollama/devstral:24b                  # switch build agent to Devstral 24B
/model ollama/devstral:24b           # switch build agent to Qwen
/model github-copilot/claude-sonnet-4.6   # switch build agent to Claude
```

Subagent model overrides (frontmatter `model:`) are unaffected by `/model` — they always use their pinned model.

---

## Verify Setup

```bash
# Check Ollama is running
curl -s http://localhost:11434/api/tags | jq '.models[].name'

# Test the primary model
ollama run devstral:24b "Write a Python hello world"

# Start OpenCode with local models
opencode
```

---

## Cost Comparison

| Provider | Model | Cost per 1M tokens |
|----------|-------|-------------------|
| Anthropic | Claude Sonnet | ~$3–15 |
| OpenAI | GPT-4o | ~$5–15 |
| **Ollama** | **Devstral 24B / Qwen** | **$0 (electricity only)** |

For routine coding tasks (implementations, tests, refactoring), local models handle 90%+ of work at zero marginal cost. Reserve Claude for adversarial review, threat modelling, and security sign-off.

---

## Decision Flowchart

```
New task arrives
     │
     ├─ Implementation (Python)?         → @coder-python     (Devstral 24B)
     ├─ Implementation (TypeScript)?     → @coder-typescript (Devstral 24B)
     ├─ SQL / migration?                 → @coder-sql        (Devstral 24B)
     ├─ Refactoring / cleanup?           → @refactor         (Devstral 24B)
     ├─ Architecture design?             → @architect        (Devstral 24B)
     ├─ Test strategy / red phase?       → @tester           (Devstral 24B)
     ├─ Code review before MR?           → @reviewer         (Claude Sonnet)
     ├─ Security audit?                  → @security         (Claude Sonnet)
     ├─ Deployment / SLO / runbook?      → @sre              (Devstral 24B)
     ├─ OTel instrumentation?            → @observability    (Devstral 24B)
     ├─ API design?                      → @api              (Devstral 24B)
     ├─ Data analysis / stats?           → @data-analyst     (Devstral 24B)
     ├─ Pipeline / dbt / Airflow?        → @data-engineer    (Devstral 24B)
     ├─ LLM / RAG / MCP feature?        → @ai-developer     (Devstral 24B)
     ├─ User story / backlog?            → @product-owner    (Devstral 24B)
     └─ Jira ticket creation?            → @jira-story       (Devstral 24B)
```
