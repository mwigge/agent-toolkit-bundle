---
name: ai-developer
description: Use when building LLM-powered applications, RAG pipelines, MCP servers, evaluation frameworks, or integrating with the Anthropic or OpenAI APIs.
---

# Skill: AI Developer

**Version**: 1.0.0 | **Updated**: 2026-04-05

Apply this skill when building LLM-powered applications, RAG pipelines, MCP servers, evaluation frameworks, or integrating with the Anthropic or OpenAI APIs.

---

## When to Activate

- Integrating with the Anthropic or OpenAI APIs (messages, chat completions, streaming)
- Designing prompts (chain-of-thought, few-shot, XML structure, negative prompting)
- Building RAG pipelines (chunking, embeddings, vector stores, hybrid retrieval, reranking)
- Writing evaluation frameworks (deterministic checks, LLM-judge grading, regression tracking)
- Building or testing MCP servers (JSON-RPC, tool schemas, resources, prompts)
- Building agentic loops and tool-use integrations
- Serving or routing models (quantisation, batching, guardrails, cost control)
- Orchestrating delegated coding work via the task queue and tiered agents

---

## Reference Map

Load the companion file for full code and deep reference on demand:

| Topic | Reference |
|-------|-----------|
| LLM API calls, prompt engineering, local models | `refs/llm-patterns.md` |
| RAG architecture and evals | `refs/rag-evals.md` |
| MCP servers and agent tool use | `refs/mcp-and-agents.md` |
| Serving, safety, observability | `refs/serving-safety-observability.md` |
| Task queue MCP server | `refs/task-queue.md` |
| Tiered agent delegation (Pattern C) | `refs/tiered-agents.md` |
| External documentation links | `refs/REFERENCES.md` |

---

## LLM API Patterns

**Anthropic model selection**:
| Model | Use case |
|-------|----------|
| `claude-opus-4` | Complex reasoning, multi-step tasks, code generation |
| `claude-sonnet-4-5` | Balanced capability/cost for production workloads |
| `claude-haiku-3-5` | High-throughput classification, extraction, routing |

- Always set `max_tokens` explicitly — no implicit unlimited budgets
- Estimate input tokens: ~1 token ≈ 4 characters (English); ~1.5 tokens/word for code
- Use streaming for user-facing latency; non-streaming for backend pipelines
- Put the most important instructions at the start and end of the system prompt
- Never put user-controlled content in the system prompt without sanitisation

See `refs/llm-patterns.md` for the full Anthropic/OpenAI/streaming code, token budgeting, and system-prompt design.

---

## Prompt Engineering

Chain-of-thought, few-shot examples, and XML-structured prompts are the core techniques; few-shot is the single most effective lever for controlling output format (use 3+ examples for format-critical tasks).

**Temperature / top_p guidance**:
| Task | Temperature | top_p | Notes |
|------|-------------|-------|-------|
| Extraction, classification | 0.0 | 1.0 | Deterministic |
| Summarisation | 0.2 | 1.0 | Consistent |
| Code generation | 0.2 | 0.95 | Reliable |
| Creative writing | 0.8–1.0 | 0.9 | Varied |
| Brainstorming | 1.0 | 1.0 | Maximum diversity |

Never set both `temperature` and `top_p` to non-default values simultaneously — adjust one only.

See `refs/llm-patterns.md` for chain-of-thought, few-shot, XML-structure, and negative-prompting code.

---

## RAG Architecture

**Chunking strategies**:
| Strategy | Chunk size | Best for |
|----------|-----------|----------|
| Fixed-size | 512–1024 tokens with 10% overlap | Homogeneous text, quick iteration |
| Semantic (sentence boundary) | Variable ~200-800 tokens | Prose, articles |
| Hierarchical (parent/child) | Parent: 1024, Child: 128 | When both precision and context matter |
| Document structure | Section-based | Technical docs with headers |

**Embedding models**:
| Provider | Model | Dimensions | Notes |
|----------|-------|-----------|-------|
| OpenAI | `text-embedding-3-large` | 3072 | Best quality |
| OpenAI | `text-embedding-3-small` | 1536 | Cost-efficient |
| Cohere | `embed-english-v3.0` | 1024 | Strong for retrieval |
| Local | `nomic-embed-text` (Ollama) | 768 | No API cost |

**Vector stores**:
| Store | Best for | Notes |
|-------|----------|-------|
| pgvector | Existing Postgres infra | `CREATE EXTENSION vector;` |
| Pinecone | Managed, high scale | Serverless tier for dev |
| Chroma | Local development | In-memory or persistent |
| Weaviate | Multi-modal, graph-linked | Self-hosted |

Retrieve with a dense + sparse hybrid, merge via Reciprocal Rank Fusion, then rerank the top-20 down to the top-5 context chunks (reranking improves quality 10–20% for one extra call).

See `refs/rag-evals.md` for hybrid retrieval, RRF, and reranking code.

---

## Evals

Combine deterministic checks (exact/contains/regex match) for structured outputs with model-graded LLM-judge scoring for open-ended responses; average 3+ judges to reduce bias. Version eval datasets with your code, keep 100+ examples (500+ for production), turn every production bug into a regression case, and alert if pass rate drops > 2% from the previous release.

See `refs/rag-evals.md` for deterministic evals, the LLM-judge prompt, dataset format, and regression-tracking schema.

---

## MCP & Agents

MCP servers expose tools, resources, and prompts to LLM clients over a standard protocol.

**Transport**:
| Transport | Use case |
|-----------|----------|
| `stdio` | Local tools, CLI integrations, Claude Desktop |
| `SSE` (Server-Sent Events) | Remote servers, web apps, multi-user |

- For `stdio`, stdout is the protocol channel — log only to stderr
- Every tool parameter uses JSON Schema with a `description`; mark required params; use `enum` to constrain values
- Return tool failures via `isError` in `result`; reserve JSON-RPC `error` for protocol-level failures
- Always bound agentic loops with a hard `MAX_TURNS` limit — an agent without a termination condition is a runaway process

See `refs/mcp-and-agents.md` for full MCP server code, tool/resource/prompt primitives, JSON-RPC compliance, agent tool-use loops, and MCP server testing.

---

## LLM Serving Patterns

**Quantisation**:
| Precision | Memory reduction | Quality impact | Use case |
|-----------|-----------------|----------------|----------|
| FP16 (half) | 2x vs FP32 | Negligible | Default for GPU inference |
| INT8 | 4x vs FP32 | < 1% degradation | Production serving, mid-tier hardware |
| INT4 (GPTQ/AWQ) | 8x vs FP32 | 1-3% degradation | Edge deployment, cost-sensitive |

**Batching strategies**:
| Strategy | Description | Trade-off |
|----------|-------------|-----------|
| Static batching | Fixed batch size, wait for batch to fill | Simple but high latency for early arrivals |
| Dynamic batching | Batch requests within a time window (e.g., 50ms) | Balanced latency/throughput |
| Continuous batching | Insert new requests into running batch as slots free up | Best throughput, complex implementation |

Route requests to the smallest sufficient model, guard against prompt injection and hallucination, and cap per-request and per-user token budgets.

See `refs/serving-safety-observability.md` for KV-cache management, model routing, guardrails, cost monitoring, prompt-injection defence, output sanitisation, and OTel GenAI observability.

---

## Security Rules

- **Never hardcode API keys** — always read from environment variables
- **Never log prompt content** — log only prompt hashes (`hashlib.sha256(prompt.encode()).hexdigest()`) for correlation
- **Never log LLM responses** containing personal data — sanitise before logging
- **API key storage**: use `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` env vars; store in Vault or cloud secrets manager for production
- **Rate limiting**: implement client-side exponential backoff on 429 responses; use jitter to avoid thundering herd
- **Input length limits**: reject inputs exceeding your configured `max_input_tokens` before sending to the API — fail fast and cheaply

---

## Delegation & Task Orchestration

- **Task queue MCP server** (`task_queue.py`) — persistent task queue and agent broadcast bus over stdio. See `refs/task-queue.md` for registration, the task state machine, tools reference, schema, and reinstall checklist.
- **Tiered agent architecture (Pattern C)** — orchestrator posts a task, an executor runs it in a full sandbox, results persist. See `refs/tiered-agents.md` for the architecture, delegation pattern, bridge CLI, and environment variables.
