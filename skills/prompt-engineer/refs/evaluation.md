# Prompt Evaluation and A/B Testing

A comprehensive evaluation-metrics framework and an A/B testing workflow for treating prompt changes with code-level rigour.

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
