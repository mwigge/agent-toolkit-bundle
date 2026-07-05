# Token Optimisation

Reduce cost and latency without sacrificing output quality.

## Compression techniques

| Technique | How | Savings |
|-----------|-----|---------|
| **Remove redundant instructions** | If the model handles a task well without an instruction, remove it | 10-30% input tokens |
| **Use structured delimiters** | XML tags (`<context>...</context>`) over verbose prose ("The following is the context:") | 5-15% input tokens |
| **Abbreviate few-shot examples** | Shorter examples that still demonstrate the pattern | 20-40% input tokens |
| **Move stable instructions to system prompt** | System prompt is cacheable across requests; saves re-processing | 50-90% cost on repeated calls |
| **Batch similar requests** | Send multiple items in one request instead of one-per-call | Reduces per-request overhead |

## Model routing for cost efficiency

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

## Cost monitoring checklist

- [ ] Track input and output tokens per request
- [ ] Set budget alerts (daily, weekly, per-endpoint)
- [ ] Log prompt version alongside token usage — correlate cost with prompt changes
- [ ] Review high-token-count requests monthly — are they necessary?
- [ ] Cache identical requests — do not re-run the same prompt + input combination
