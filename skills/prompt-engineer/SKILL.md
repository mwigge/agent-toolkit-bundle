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

### CoT with structured output

```python
ANALYSIS_PROMPT = """Analyse the chaos experiment results.

<thinking>
Step 1: Identify the steady-state baseline metrics
Step 2: Compare during-fault metrics to baseline
Step 3: Evaluate recovery metrics
Step 4: Determine if the hypothesis was validated
</thinking>

<result>
{
  "hypothesis_validated": true/false,
  "baseline": {"p99_ms": N, "error_rate": N},
  "during_fault": {"p99_ms": N, "error_rate": N},
  "recovery": {"time_s": N, "metrics_restored": true/false},
  "recommendations": ["..."]
}
</result>
"""
```

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

### XML-delimited sections

```
<instructions>
Extract the following fields from the incident report.
</instructions>

<schema>
- service_name: string
- incident_type: one of [outage, degradation, data_loss, security]
- duration_minutes: integer
- root_cause: string (one sentence)
- action_items: list of strings
</schema>

<incident_report>
{report_text}
</incident_report>

Respond with the extracted fields in JSON format.
```

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

## Common Prompt Patterns

### Classification

```
Classify the following log entry into one category: ERROR, WARNING, INFO, DEBUG.
Respond with only the category name.

Log: {log_entry}
Category:
```

### Extraction

```
Extract structured data from the incident report below.

<report>
{incident_report}
</report>

Return JSON with these fields:
- service: string
- severity: "critical" | "high" | "medium" | "low"
- duration_minutes: number
- affected_users: number | null
- root_cause: string
```

### Transformation

```
Convert the following Chaos Toolkit experiment JSON into a human-readable
summary suitable for a non-technical stakeholder.

Rules:
- No technical jargon
- Focus on business impact
- Include duration and outcome
- Maximum 3 paragraphs

<experiment>
{experiment_json}
</experiment>
```

### Comparison / Analysis

```
Compare the two chaos experiment runs below and identify:
1. What improved between runs
2. What degraded between runs
3. What remained unchanged
4. Recommended next steps

<run_1>
{run_1_data}
</run_1>

<run_2>
{run_2_data}
</run_2>
```

---

## Evaluation Metrics — Comprehensive Framework

Beyond format compliance and accuracy, measure prompts across multiple dimensions:

| Metric | What it measures | How to measure | When it matters |
|--------|-----------------|----------------|-----------------|
| **Accuracy (exact match)** | Output matches expected answer exactly | `output.strip() == expected.strip()` | Classification, extraction with known answers |
| **Accuracy (fuzzy match)** | Output is close enough to expected | Levenshtein distance, token overlap ratio | Extraction where phrasing may vary |
| **Accuracy (semantic similarity)** | Output means the same thing as expected | Embedding cosine similarity > threshold | Open-ended generation, summarisation |
| **Consistency** | Same input produces the same output class across runs | Run N times (N >= 10), measure agreement rate | Any task where determinism matters |
| **Latency (time to first token)** | How fast the user sees the first response token | Measure TTFT from API response stream | Interactive / user-facing applications |
| **Latency (total generation)** | Total time from request to complete response | End-to-end wall clock time | Batch processing, API pipelines |
| **Token efficiency** | Quality of output per token spent | `quality_score / (input_tokens + output_tokens)` | Cost-sensitive production systems |
| **Safety (refusal rate)** | Model refuses adversarial or harmful inputs | `refusals / adversarial_inputs` (target: > 95%) | Any user-facing system |
| **Groundedness** | Output is supported by provided context | Claim-level verification against source | RAG, document Q&A |

### Evaluation pipeline

```python
@dataclass
class EvalSuite:
    name: str
    test_cases: list[PromptTestCase]
    metrics: list[str]  # which metrics to compute

    def run(self, prompt_fn, runs_per_case: int = 5) -> dict:
        """Run all test cases multiple times and aggregate metrics."""
        results: dict[str, list] = {m: [] for m in self.metrics}
        for tc in self.test_cases:
            for _ in range(runs_per_case):
                output = prompt_fn(tc.input_text)
                if "accuracy" in self.metrics:
                    results["accuracy"].append(output.strip() == tc.expected_output)
                if "consistency" in self.metrics:
                    results["consistency"].append(output)
        return results
```

---

## A/B Testing Prompts

Prompts are code. Treat prompt changes with the same rigour as code changes.

### Version control prompts

- Store all prompts in version control (same repo as the application)
- Each prompt has a version identifier (semantic version or commit hash)
- Never edit prompts ad-hoc in production — always go through the change pipeline
- Maintain a changelog for prompt changes alongside code changes

### A/B test framework

```python
@dataclass
class PromptVariant:
    name: str           # e.g., "v2.1-concise-instructions"
    prompt_text: str
    version: str

@dataclass
class ABTestResult:
    variant_a: str
    variant_b: str
    metric: str
    a_score: float
    b_score: float
    p_value: float
    significant: bool   # p < 0.05

    @property
    def winner(self) -> str | None:
        if not self.significant:
            return None
        return self.variant_a if self.a_score > self.b_score else self.variant_b

def ab_test_prompts(
    variant_a: PromptVariant,
    variant_b: PromptVariant,
    test_inputs: list[str],
    eval_fn,
) -> list[ABTestResult]:
    """Run the same inputs through both variants and compare."""
    a_outputs = [eval_fn(variant_a.prompt_text, inp) for inp in test_inputs]
    b_outputs = [eval_fn(variant_b.prompt_text, inp) for inp in test_inputs]
    # Compare outputs using configured metrics
    # Return statistical comparison
    ...
```

### Rollout strategy

1. **Test offline** — run eval suite on both variants with a fixed test set
2. **Shadow mode** — run new variant in parallel, compare outputs, do not serve to users
3. **Canary rollout** — serve new variant to 5% of traffic, monitor metrics
4. **Gradual ramp** — increase to 25%, 50%, 100% if metrics hold
5. **Rollback plan** — if any metric degrades beyond threshold, revert immediately

---

## Token Optimisation

Reduce cost and latency without sacrificing output quality.

### Compression techniques

| Technique | How | Savings |
|-----------|-----|---------|
| **Remove redundant instructions** | If the model handles a task well without an instruction, remove it | 10-30% input tokens |
| **Use structured delimiters** | XML tags (`<context>...</context>`) over verbose prose ("The following is the context:") | 5-15% input tokens |
| **Abbreviate few-shot examples** | Shorter examples that still demonstrate the pattern | 20-40% input tokens |
| **Move stable instructions to system prompt** | System prompt is cacheable across requests; saves re-processing | 50-90% cost on repeated calls |
| **Batch similar requests** | Send multiple items in one request instead of one-per-call | Reduces per-request overhead |

### Model routing for cost efficiency

Not every task needs the most capable model. Route by complexity:

```python
def select_model(task_complexity: str) -> str:
    """Route to the appropriate model based on task complexity."""
    routing = {
        "simple": "smallest-capable-model",     # classification, extraction, formatting
        "moderate": "mid-tier-model",            # summarisation, analysis, code review
        "complex": "most-capable-model",         # multi-step reasoning, novel code generation
    }
    return routing.get(task_complexity, "mid-tier-model")
```

### Cost monitoring checklist

- [ ] Track input and output tokens per request
- [ ] Set budget alerts (daily, weekly, per-endpoint)
- [ ] Log prompt version alongside token usage — correlate cost with prompt changes
- [ ] Review high-token-count requests monthly — are they necessary?
- [ ] Cache identical requests — do not re-run the same prompt + input combination

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
