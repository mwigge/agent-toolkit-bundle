# Monitoring Guidance

Source inputs:

- https://mcpmarket.com/tools/skills/error-rate-monitor-5
- https://explainx.ai/skills/aj-geddes/useful-ai-prompts/prometheus-monitoring
- https://explainx.ai/skills/sickn33/antigravity-awesome-skills/observability-monitoring-monitor-setup
- https://explainx.ai/skills/aj-geddes/useful-ai-prompts/infrastructure-monitoring
- https://explainx.ai/skills/mukul975/Anthropic-Cybersecurity-Skills/detecting-dns-exfiltration-with-dns-query-analysis
- https://mcpmarket.com/tools/skills/monitoring-observability
- https://mcpmarket.com/tools/skills/monitoring-observability-2
- https://mcpmarket.com/tools/skills/monitoring-logging

## Patterns To Carry Forward

- Error-rate monitoring should use request totals and error totals, not log text alone.
- Prometheus metrics should use stable names and bounded labels. Avoid user IDs, raw hosts, request IDs, and other high-cardinality labels.
- Infrastructure monitoring should include CPU, memory, disk, filesystem, network, process, and service health.
- Observability setup should connect metrics, logs, and traces through a shared correlation ID.
- Logging should be structured, redacted, and queryable by experiment ID, run ID, target ID, action kind, and outcome.
- DNS exfiltration detection should watch label length, query entropy, NXDOMAIN spikes, rare domains, unusual record types, query volume, and destination drift.
- Dashboards should show the operator journey: baseline, fault injection, impact, rollback, recovery, and residual risk.

## Prometheus Examples

Error ratio:

```promql
sum(rate(http_requests_total{status=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))
```

Latency p95:

```promql
histogram_quantile(
  0.95,
  sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service)
)
```

Host saturation:

```promql
1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))
```

Disk pressure:

```promql
1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)
```

## Chaos Experiment Acceptance

For a new experiment, reject instrumentation as incomplete when any of these are missing:

- Baseline query or measurement before the fault.
- Impact metric during the fault.
- Rollback verification after the fault.
- Report metric that can be read without inspecting raw logs.
- Target inventory field that explains why the experiment is safe for that target.
- RLS-safe ownership path for metrics, logs, reports, scenarios, and inventory.

## DNS Exfiltration Signals

Useful detectors include:

- Average and max query name length.
- Shannon entropy of labels or full query names.
- Percentage of unique subdomains per base domain.
- NXDOMAIN rate and response-code distribution.
- TXT, NULL, or uncommon record-type frequency.
- Queries to newly seen or low-reputation domains.
- Regular beacon interval or bursty high-volume behavior.

These are monitoring signals. Do not block production traffic without a staged policy, explicit owner, rollback path, and false-positive review.
