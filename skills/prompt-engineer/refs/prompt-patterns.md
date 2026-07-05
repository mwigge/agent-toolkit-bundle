# Common Prompt Patterns

Reusable prompt templates for classification, extraction, transformation, and comparison tasks.

## Classification

```
Classify the following log entry into one category: ERROR, WARNING, INFO, DEBUG.
Respond with only the category name.

Log: {log_entry}
Category:
```

## Extraction

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

## Transformation

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

## Comparison / Analysis

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

## CoT with structured output

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

## XML-delimited sections

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
