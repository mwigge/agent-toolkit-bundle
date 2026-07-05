---
name: prompt-engineer
description: >
  LLM prompt engineering: system prompt design, few-shot patterns,
  chain-of-thought reasoning, structured output, evaluation frameworks,
  prompt testing, and anti-patterns. Activate when designing prompts,
  building LLM-powered features, or evaluating prompt quality.
version: 1.0.0
argument-hint: "[prompt type, LLM task, or evaluation goal]"
---

# Prompt Engineer Skill

## When to activate
- Designing system prompts for LLM-powered features
- Writing few-shot examples for classification or extraction
- Implementing chain-of-thought reasoning
- Structuring LLM output (JSON, XML, structured data)
- Building evaluation frameworks for prompt quality
- Debugging prompt failures or inconsistencies
- Optimising prompt cost (token usage) and latency

---

## Prompt Design Principles

1. **Be specific and unambiguous** — tell the model exactly what you want
2. **Provide context** — include relevant background information
3. **Show, do not just tell** — use examples (few-shot) for complex tasks
4. **Constrain the output** — specify format, length, and structure
5. **Separate instructions from data** — use delimiters (XML tags, triple backticks)
6. **Iterate and test** — prompts are code; version and evaluate them

---

## System Prompt Patterns

### Role + context + constraints

```
You are a senior site reliability engineer specialising in chaos engineering.
You analyse experiment results and provide actionable recommendations.

Context:
- The platform runs on Kubernetes with PostgreSQL and Redis
- SLO targets: 99.9% availability, p99 latency < 500ms
- Experiments follow the Chaos Toolkit JSON format

Constraints:
- Always cite specific metrics when making recommendations
- Never recommend changes without explaining the expected impact
- Use structured output format (see below)
- If data is insufficient, say so rather than speculating
```

### Task decomposition prompt

```
Analyse the following chaos experiment result and provide:

1. **Summary**: one-paragraph description of what happened
2. **SLO Impact**: which SLOs were affected and by how much
3. **Root Cause**: what caused the observed behaviour
4. **Recommendations**: ordered list of improvements, each with:
   - Action to take
   - Expected impact
   - Effort estimate (low/medium/high)
5. **Follow-up Experiments**: what should be tested next

Experiment data:
<experiment>
{experiment_json}
</experiment>
```

---

## Few-Shot Prompting

### When to use few-shot

| Scenario | Zero-shot | Few-shot | Many-shot |
|----------|-----------|----------|-----------|
| Simple, well-known task | Yes | Unnecessary | Unnecessary |
| Custom format/style | Risky | 2-3 examples | Not needed |
| Domain-specific classification | Poor | 3-5 examples | 5-10 examples |
| Complex extraction | Poor | 3-5 examples | Use fine-tuning instead |

### Few-shot pattern

```python
SYSTEM_PROMPT = """You classify chaos experiment outcomes into categories.

Examples:

Input: "API returned 503 for 45 seconds, then recovered after circuit breaker reset"
Category: TRANSIENT_FAILURE
Severity: MEDIUM
Recovery: AUTOMATIC

Input: "Database connection pool exhausted, manual restart required"
Category: RESOURCE_EXHAUSTION
Severity: HIGH
Recovery: MANUAL

Input: "Latency increased from 50ms to 80ms during fault injection, within SLO"
Category: GRACEFUL_DEGRADATION
Severity: LOW
Recovery: NOT_NEEDED

Now classify the following:

Input: "{user_input}"
"""
```

### Example selection strategies

1. **Diverse examples** — cover different categories and edge cases
2. **Similar examples** — pick examples closest to the expected input (semantic similarity)
3. **Boundary examples** — include examples near decision boundaries
4. **Negative examples** — show what the output should NOT look like

---

## Chain-of-Thought (CoT)

### Explicit CoT

```
Analyse the following resilience score and explain your reasoning step by step
before providing the final assessment.

Score components:
- Availability: 99.85% (target: 99.9%)
- Recovery time: 45s (target: 30s)
- Error rate during fault: 2.3% (target: < 5%)
- Probe pass rate: 8/10

Think through each component:
1. Compare each metric to its target
2. Identify which are passing and which are failing
3. Determine the overall resilience posture
4. Provide specific recommendations for failing metrics

Then give your final assessment as:
- Overall: PASS / MARGINAL / FAIL
- Priority actions: [list]
```

For a CoT prompt that emits structured output alongside its reasoning, see the "CoT with structured output" example in `refs/prompt-patterns.md`.

---

## Structured Output

### JSON mode

```python
import anthropic
import json
import os

client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])

response = client.messages.create(
    model="claude-sonnet-4-5",
    max_tokens=1024,
    system="""You analyse chaos experiment data. Always respond with valid JSON.
Output schema:
{
  "summary": "string",
  "slo_impact": [{"sli": "string", "baseline": number, "during_fault": number, "within_slo": boolean}],
  "recommendations": [{"action": "string", "priority": "high|medium|low"}]
}""",
    messages=[{"role": "user", "content": f"Analyse: {experiment_data}"}],
)

result = json.loads(response.content[0].text)
```

For the XML-delimited extraction pattern (separating instructions, schema, and data with tags), see `refs/prompt-patterns.md`.

---

## Prompt Testing and Evaluation

### Evaluation framework

```python
from dataclasses import dataclass


@dataclass
class PromptTestCase:
    input_text: str
    expected_output: str | None = None      # exact match
    expected_contains: list[str] | None = None  # must contain these strings
    expected_format: str | None = None       # "json", "markdown", etc.
    max_tokens: int | None = None            # output should not exceed this


@dataclass
class EvalResult:
    test_case: PromptTestCase
    actual_output: str
    passed: bool
    failure_reason: str | None = None
    latency_ms: float = 0.0
    token_count: int = 0


def evaluate_prompt(
    test_cases: list[PromptTestCase],
    prompt_fn,
    model: str = "claude-sonnet-4-5",
) -> list[EvalResult]:
    results: list[EvalResult] = []
    for tc in test_cases:
        output = prompt_fn(tc.input_text, model=model)
        passed = True
        reason = None

        if tc.expected_output and output.strip() != tc.expected_output.strip():
            passed = False
            reason = f"Expected '{tc.expected_output}', got '{output}'"

        if tc.expected_contains:
            missing = [s for s in tc.expected_contains if s not in output]
            if missing:
                passed = False
                reason = f"Missing expected strings: {missing}"

        if tc.expected_format == "json":
            try:
                import json
                json.loads(output)
            except json.JSONDecodeError as e:
                passed = False
                reason = f"Invalid JSON: {e}"

        results.append(EvalResult(test_case=tc, actual_output=output, passed=passed, failure_reason=reason))
    return results
```

### Evaluation metrics

| Metric | When to use | How to measure |
|--------|-------------|----------------|
| **Accuracy** | Classification tasks | % correct predictions |
| **Format compliance** | Structured output | % valid JSON/schema |
| **Completeness** | Extraction tasks | % of required fields present |
| **Relevance** | Open-ended generation | Human rating 1-5 or LLM-as-judge |
| **Consistency** | Any task | Run N times, measure variance |
| **Cost** | Production prompts | Input + output tokens per request |
| **Latency** | User-facing | Time to first token, total time |

---

## Prompt Optimisation

### Token reduction techniques

1. **Remove redundant instructions** — if the model handles it well without, remove it
2. **Use abbreviations in few-shot examples** — shorter examples that still demonstrate the pattern
3. **Prefer structured delimiters** — XML tags over verbose prose separators
4. **Cache system prompts** — use prompt caching for repeated system prompts
5. **Move static context to system prompt** — system prompt tokens are cheaper with caching

### Prompt caching (Anthropic)

```python
response = client.messages.create(
    model="claude-sonnet-4-5",
    max_tokens=1024,
    system=[
        {
            "type": "text",
            "text": large_static_context,  # cached across requests
            "cache_control": {"type": "ephemeral"},
        }
    ],
    messages=[{"role": "user", "content": user_query}],
)
```

### Model selection for cost optimisation

| Task complexity | Model | Cost tier |
|----------------|-------|-----------|
| Classification, extraction | claude-haiku-3-5 | Low |
| Analysis, summarisation | claude-sonnet-4-5 | Medium |
| Complex reasoning, code generation | claude-opus-4 | High |

---

## Deep-Dive References

- **Common prompt patterns** — copy-ready templates for classification, extraction, transformation, and comparison. See `refs/prompt-patterns.md`.
- **Comprehensive evaluation and A/B testing** — the full multi-dimensional metrics framework, an evaluation pipeline, and a version-controlled A/B rollout workflow. See `refs/evaluation.md`.
- **Token optimisation** — compression techniques, model routing for cost, and a cost-monitoring checklist. See `refs/token-optimisation.md`.

---

## Anti-Patterns

| Anti-pattern | Fix |
|---|---|
| Vague instructions ("do your best") | Be specific about format, length, and criteria |
| No examples for complex tasks | Add 2-3 few-shot examples |
| Mixing instructions with data | Use XML tags or delimiters to separate |
| No output format specification | Define exact schema or template |
| Not testing prompt changes | Build an eval suite; run before and after changes |
| Using the most expensive model for everything | Route by task complexity; use Haiku for simple tasks |
| Prompt injection vulnerability | Validate and sanitise user input; use system prompts for instructions |
| No error handling for malformed output | Parse with fallback; retry with clarifying prompt |
| Hardcoded prompts without versioning | Store prompts in version control; treat as code |
| Ignoring token costs in production | Monitor token usage; set budget alerts |

## References

- Reference: `refs/REFERENCES.md` — external documentation links for prompt engineering
