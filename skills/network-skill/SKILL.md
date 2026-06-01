---
name: network-skill
description: Use when designing, reviewing, or implementing network engineering and chaos experiments, including latency, jitter, packet loss, bandwidth throttling, dependency blackhole, DNS disruption, routing changes, interface inventory, port/listener evidence, and rollback-safe connectivity tests.
---

# Network Skill

Design network experiments from topology and flow evidence. Scope faults to a single interface, dependency, route, port, or traffic class before widening. Always preserve the control path.

## Core Workflow

1. Inventory interfaces, addresses, routes, DNS resolvers, listening ports, firewall backend, qdisc state, connection tracking, and dependency endpoints.
2. Map the experiment flow: client, server, protocol, port, direction, dependency owner, SLO, timeout, retry policy, and expected failure mode.
3. Select the smallest injector: `tc netem` for latency/loss/jitter, qdisc class for bandwidth, firewall rule for dependency block, DNS override for resolver faults, or route change for lab-only tests.
4. Record before/during/after probes: TCP connect, HTTP health, ICMP where allowed, DNS resolution, route lookup, qdisc stats, rule counters, and service-level metrics.
5. Roll back exactly the changed qdisc, route, DNS rule, or firewall rule. Verify baseline is restored.

## Safety Rules

- Protect SSH, Ops Agent, identity, DB admin, telemetry, package mirror, DNS/NTP unless explicitly targeted with an out-of-band recovery path.
- Avoid broad interface-wide netem on shared hosts. Prefer destination match, cgroup, class, or single dependency where the tooling supports it.
- Cap latency, loss, and duration. Abort if control-path probe fails or application error rate crosses the critical threshold.
- Use deterministic rule names/handles and capture cleanup evidence.
- Treat route deletion, default gateway change, DNS hijack, and full blackhole as advanced/lab-only unless narrowly scoped.

## Experiment Patterns

| Pattern | Use | Evidence |
| --- | --- | --- |
| Latency/jitter | Timeout and retry behavior | qdisc stats, p95/p99 latency, SLO status |
| Packet loss | Retry, idempotency, stream recovery | loss percentage, retransmits, app errors |
| Bandwidth throttle | Backpressure and queueing | throughput, queue depth, latency, recovery |
| Dependency blackhole | Circuit breaker/failover | connection failure, fallback behavior, rollback |
| DNS block/override | Resolver and cache behavior | resolution failure, cache TTL, recovery |
| Route preflight | Lab-only path validation | route lookup, control path preserved |

## Required Metadata

- Use `resilience_metadata.target: "network"` or target system with `component: "network"`.
- Include `fault_pattern` like `network-latency`, `packet-loss`, `bandwidth-throttle`, `dependency-blackhole`, or `dns-block`.
- Include inventory relation to interfaces, routes, listening ports, firewall backend, and dependency endpoints.
- Include curated measurements for qdisc/rule state, latency, loss, throughput, connection result, DNS result, route result, control-path status, and rollback status.

## References

- Read `references/network-guidance.md` for condensed source-derived network engineering and chaos guidance.
