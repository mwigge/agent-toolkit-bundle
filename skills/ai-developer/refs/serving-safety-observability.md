# LLM Serving, Safety & Observability

Full patterns for serving models (quantisation, KV cache, batching, routing, guardrails, cost control), safety (prompt-injection defence, output sanitisation), and observability (OTel GenAI conventions, token usage, cost attribution). The SKILL.md body keeps the quantisation and batching quick-reference tables and the Security Rules; this file holds the complete detail.

---

## LLM Serving Patterns

### Model Quantisation

Reduce model memory footprint for inference without catastrophic quality loss:

| Precision | Memory reduction | Quality impact | Use case |
|-----------|-----------------|----------------|----------|
| FP16 (half) | 2x vs FP32 | Negligible | Default for GPU inference |
| INT8 | 4x vs FP32 | < 1% degradation | Production serving, mid-tier hardware |
| INT4 (GPTQ/AWQ) | 8x vs FP32 | 1-3% degradation | Edge deployment, cost-sensitive |

**Rules**:
- Always benchmark quantised models against full-precision on your eval set before deploying
- Use calibration datasets representative of production traffic for quantisation
- INT4 is acceptable for classification and extraction; prefer INT8+ for complex reasoning

### KV Cache Management

The key-value cache stores attention state for previously processed tokens:

- **Pre-allocation**: allocate KV cache memory at server startup based on max sequence length and max concurrent requests
- **Eviction**: when cache is full, evict the oldest or least-recently-used entries
- **Paged attention**: use paged memory management to reduce fragmentation and improve throughput
- **Budget**: KV cache memory = `num_layers * 2 * hidden_dim * sequence_length * precision_bytes * batch_size`

### Batching Strategies

| Strategy | Description | Trade-off |
|----------|-------------|-----------|
| Static batching | Fixed batch size, wait for batch to fill | Simple but high latency for early arrivals |
| Dynamic batching | Batch requests within a time window (e.g., 50ms) | Balanced latency/throughput |
| Continuous batching | Insert new requests into running batch as slots free up | Best throughput, complex implementation |

- Use continuous batching for production serving — it maximises GPU utilisation
- Set a maximum batch size to bound memory usage and prevent OOM
- Monitor queue depth and batch fill rate as key performance indicators

### Model Routing

Route requests to different model sizes based on task complexity:

```
Request → Classifier → Simple? → Small model (fast, cheap)
                     → Complex? → Large model (accurate, expensive)
```

**Routing signals**:
- Input token count (short queries → small model)
- Task type (classification → small, multi-step reasoning → large)
- Required output quality (draft → small, final → large)
- User tier (free → small, premium → large)

**Rules**:
- Build the classifier as a lightweight rule-based system first; use ML routing only if rules are insufficient
- Log routing decisions for analysis and threshold tuning
- Always provide a fallback to the large model when routing confidence is low

### Guardrails

**Prompt injection defence**:
- Sanitise user inputs before inclusion in prompts (see Safety section below)
- Use system-level instructions that are architecturally separated from user content
- Monitor for instruction-override patterns in inputs

**Hallucination detection**:
- Compare generated claims against source documents (for RAG applications)
- Use a secondary LLM call to verify factual claims when accuracy is critical
- Flag responses with low retrieval confidence scores for human review
- Track hallucination rate as a production metric

### Cost Monitoring and Token Budgets

- Set per-request token limits (`max_tokens`) — never allow unlimited generation
- Set per-user daily/monthly token budgets with hard caps
- Track cost per request: `(input_tokens * input_rate + output_tokens * output_rate) / 1_000_000`
- Alert when daily spend exceeds 120% of the rolling 7-day average
- Use cheaper models for internal/batch workloads; reserve expensive models for user-facing requests

---

## Safety

### Prompt Injection Defence

```python
def sanitise_user_input(user_text: str) -> str:
    """Remove common prompt injection patterns from user-supplied text."""
    import re
    # Remove instruction override attempts
    patterns = [
        r"ignore\s+(all\s+)?(previous|prior|above)\s+instructions?",
        r"system\s*prompt\s*:",
        r"<\s*/?system\s*>",
        r"you\s+are\s+now\s+",
        r"act\s+as\s+",
    ]
    for pattern in patterns:
        user_text = re.sub(pattern, "[REMOVED]", user_text, flags=re.IGNORECASE)
    return user_text
```

Never concatenate user input directly into the system prompt. Place user content in a clearly delimited `<user_message>` block.

### Output Sanitisation

```python
import json

def parse_llm_json(raw: str) -> dict:
    """Extract and validate JSON from LLM output. Never exec() or eval() LLM output."""
    # Strip markdown code fences if present
    raw = raw.strip()
    if raw.startswith("```"):
        raw = raw.split("\n", 1)[1].rsplit("```", 1)[0]
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"LLM returned invalid JSON: {exc}\nRaw: {raw[:200]}") from exc
```

**Rules**:
- Never use `eval()` or `exec()` on LLM output under any circumstances
- Always validate LLM-generated data against a schema before using it
- Never use LLM-generated file paths, shell commands, or SQL without explicit review and sanitisation
- Treat LLM output as untrusted user input at all times

---

## Observability

### OTel Semantic Conventions for GenAI

Key span attributes (`gen_ai.*` prefix):

```python
from opentelemetry import trace

tracer = trace.get_tracer("ai.service")

with tracer.start_as_current_span("llm.generate") as span:
    span.set_attribute("gen_ai.system", "anthropic")
    span.set_attribute("gen_ai.request.model", "claude-sonnet-4-5")
    span.set_attribute("gen_ai.request.max_tokens", 1024)
    span.set_attribute("gen_ai.request.temperature", 0.2)
    # ... make API call ...
    span.set_attribute("gen_ai.response.model", response.model)
    span.set_attribute("gen_ai.usage.input_tokens", response.usage.input_tokens)
    span.set_attribute("gen_ai.usage.output_tokens", response.usage.output_tokens)
    span.set_attribute("gen_ai.response.finish_reason", response.stop_reason)
```

Never set span attributes containing prompt content that may include PII. Log message hashes for correlation, not content.

### Token Usage Tracking

Emit per-request metrics:

```python
# Metric names follow: gen_ai.<provider>.<resource>_<unit>
meter.create_histogram("gen_ai.client.token.usage").record(
    response.usage.input_tokens + response.usage.output_tokens,
    attributes={
        "gen_ai.system": "anthropic",
        "gen_ai.token.type": "total",
        "gen_ai.request.model": model,
    }
)
```

### Cost Attribution

```python
COST_PER_MILLION_TOKENS = {
    "claude-opus-4":      {"input": 15.00, "output": 75.00},
    "claude-sonnet-4-5":  {"input":  3.00, "output": 15.00},
    "claude-haiku-3-5":   {"input":  0.80, "output":  4.00},
    "gpt-4o":             {"input":  5.00, "output": 15.00},
}

def calculate_cost(model: str, input_tokens: int, output_tokens: int) -> float:
    rates = COST_PER_MILLION_TOKENS.get(model, {"input": 0, "output": 0})
    return (input_tokens * rates["input"] + output_tokens * rates["output"]) / 1_000_000
```
