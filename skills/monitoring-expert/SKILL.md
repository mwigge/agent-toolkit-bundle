---
name: monitoring-expert
description: Use when designing, auditing, or implementing monitoring instrumentation for experiments, infrastructure, services, security signals, Prometheus/OpenTelemetry metrics, logs, dashboards, alerts, SLOs, and runbooks.
---

# Monitoring Expert

Use this skill to make monitoring actionable, not decorative. It applies to chaos experiments, platform services, infrastructure checks, security detections, dashboards, alerts, logs, traces, and runbooks.

## Workflow

1. Identify the monitored user journey or experiment hypothesis.
2. Define the steady-state signal and failure signal before adding instrumentation.
3. Require RED metrics for services: request rate, error rate, and duration.
4. Require USE metrics for infrastructure: utilization, saturation, and errors.
5. Add experiment lifecycle metrics: preflight, injection, abort, rollback, validation, and recovery.
6. Add target inventory metrics that match the fault domain.
7. Add structured logs with correlation IDs and no secrets.
8. Add traces or spans around control-plane operations and target-side fault actions.
9. Add alert rules only when there is a runbook, owner, severity, and noise budget.
10. Validate that dashboards and reports show before, during, and after windows.

## Experiment Instrumentation Checklist

Every chaos experiment should expose:

- `steady_state`: objective, query or measurement, expected range, and failure threshold.
- `target_inventory`: host, network interfaces, open ports, firewall/iptables/nftables state, kernel/runtime version where relevant, disk, memory, CPU, and service-specific capacity.
- `metrics`: impact, saturation, errors, recovery time, rollback result, and experiment duration.
- `report_metrics`: concise metrics that prove the hypothesis or explain why it was inconclusive.
- `statistics`: min, max, average, percentile, baseline delta, and sample count for time-series values.
- `otel`: span names, attributes, metric names, log fields, and trace correlation IDs.
- `events`: timestamped preflight, apply, observe, abort, rollback, and validate events.
- `alerts`: expected alert behavior and silence/noise expectations for controlled tests.

## Domain Signals

- Database experiments: connection pool active/idle/waiting, query latency, lock waits, slow queries, memory, disk, WAL/commit pressure, error count, and restart/reconnect evidence.
- Event management systems: publish/consume rate, queue depth, consumer lag, redelivery count, dead-letter rate, broker memory, disk/store use, connection count, and processing latency.
- Network experiments: interface inventory, route, DNS resolver, open ports, packet loss, latency percentiles, bandwidth, TCP retransmits, connection failures, and rollback state.
- Firewall experiments: before/after iptables or nftables rules, affected direction, protocol, port, CIDR, connection failures, reject/drop behavior, and rule cleanup evidence.
- RNG/entropy experiments: entropy availability, RNG device health, random-read latency, crypto handshake error rate, service entropy dependency, and restoration evidence.
- Kernel experiments: kernel version, loaded modules, taint/oops/dmesg signals, panic guardrails, sysctl state, resource pressure, and console/access rollback requirements.
- DNS security monitoring: query volume, NXDOMAIN rate, subdomain length, label entropy, unusual record types, tunneling indicators, and destination rarity.

## Alert Quality

An alert is acceptable when it has:

- A PromQL, LogQL, SQL, or OTel query that can be tested.
- A severity and ownership route.
- A runbook link or inline remediation steps.
- A known false-positive condition.
- A validation method in smoke or canary tests.
- A recovery condition so operators can tell when the incident is over.

## Reference

Load `references/monitoring-guidance.md` when you need the source-derived checklist or examples for Prometheus, infrastructure monitoring, observability setup, logging, and DNS exfiltration signals.
