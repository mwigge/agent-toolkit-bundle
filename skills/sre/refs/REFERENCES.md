# SRE — Reference Links

## Foundational Books & Papers
- https://sre.google/sre-book/table-of-contents/ — Google SRE Book: the definitive SRE reference (free online)
- https://sre.google/workbook/table-of-contents/ — The Site Reliability Workbook: practical companion to the SRE Book
- https://sre.google/workbook/implementing-slos/ — Implementing SLOs chapter: error budgets, burn rates, alerting windows

## SLO Specification
- https://openslo.com/ — OpenSLO: vendor-neutral SLO specification format (YAML)
- https://github.com/OpenSLO/OpenSLO/blob/main/spec/openslo.md — OpenSLO spec: SLO, SLI, AlertPolicy, ErrorBudgetPolicy objects

## Alerting
- https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/ — Prometheus alerting rules: `expr`, `for`, `labels`, `annotations`
- https://prometheus.io/docs/practices/alerting/ — Prometheus alerting best practices: symptom-based alerting, avoid noise
- https://www.usenix.org/sites/default/files/conference/protected-files/srecon16europe_slides_reissner.pdf — Alerting on SLOs (Reissner, Google SRE): burn rate alerting model

## Runbooks
- https://github.com/pagerduty/incident-response-docs — PagerDuty Incident Response: runbook templates, postmortem guide
- https://response.pagerduty.com/ — PagerDuty response docs: on-call, escalation, incident command

## Metrics
- https://sre.google/sre-book/monitoring-distributed-systems/ — Monitoring distributed systems: the four golden signals (latency, traffic, errors, saturation)

## Reliability Patterns
- https://learn.microsoft.com/en-us/azure/architecture/patterns/circuit-breaker — Circuit Breaker pattern (Microsoft Azure Architecture)
- https://learn.microsoft.com/en-us/azure/architecture/patterns/bulkhead — Bulkhead pattern (Microsoft Azure Architecture)
- https://learn.microsoft.com/en-us/azure/architecture/patterns/retry — Retry pattern with exponential backoff
- https://learn.microsoft.com/en-us/azure/architecture/patterns/health-endpoint-monitoring — Health Endpoint Monitoring pattern
- https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/ — AWS Builders Library: timeouts, retries, and backoff with jitter

## Capacity Planning
- https://sre.google/sre-book/software-engineering-in-sre/ — Capacity planning at Google SRE
- https://sre.google/workbook/non-abstract-design/ — Non-abstract large system design (capacity modelling)

## Toil
- https://sre.google/sre-book/eliminating-toil/ — Eliminating Toil (Google SRE Book chapter)
- https://sre.google/workbook/eliminating-toil/ — Eliminating Toil (SRE Workbook chapter)

## On-Call
- https://sre.google/sre-book/being-on-call/ — Being On-Call (Google SRE Book)
- https://sre.google/workbook/on-call/ — On-Call (SRE Workbook): rotation sizing, compensation, escalation

## Production Readiness
- https://sre.google/sre-book/evolving-sre-engagement-model/ — Production Readiness Reviews (Google SRE)
- https://sre.google/workbook/production-readiness/ — Production Readiness Checklist patterns

## Feature Flags & Progressive Delivery
- https://martinfowler.com/articles/feature-toggles.html — Martin Fowler: Feature Toggles taxonomy
- https://launchdarkly.com/blog/what-are-feature-flags/ — Feature flag best practices
