---
name: firewall-skill
description: Use when designing, reviewing, or implementing firewall, iptables, nftables, firewalld, security group, ingress block, egress block, port reject, packet-filter, segmentation, or firewall rollback chaos experiments.
---

# Firewall Skill

Design firewall experiments as scoped, reversible packet-filter changes. Inventory the firewall backend and rule ownership before adding any rule. Prefer explicit destination, protocol, port, interface, and comment labels over broad drops.

## Core Workflow

1. Inventory backend: firewalld status, nftables tables/chains, iptables-nft vs iptables-legacy, existing default policies, active zones, connection tracking, and control-path ports.
2. Define the target flow: source, destination, protocol, port, direction, interface, application owner, and expected business impact.
3. Choose the smallest rule: single egress port, single ingress port, scoped destination CIDR/host, or explicit REJECT where supported.
4. Add a named/commented rule with a TTL and rollback marker. Never create anonymous broad rules.
5. Verify rule counters, traffic impact, control-path preservation, and cleanup.

## Safety Rules

- Do not block SSH, Ops Agent, observability collectors, package mirrors, DNS, NTP, database primary, or identity endpoints unless the experiment is explicitly scoped to that dependency and has an out-of-band recovery path.
- Prefer `REJECT` for fast application feedback when supported; use `DROP` only when testing timeout behavior.
- Avoid flushing chains or changing default policy. Append or insert a single labeled rule and remove that exact rule.
- Capture rule snapshot before and after. Rollback must prove no chaos-labeled rules remain.
- Keep broad CIDR, `0.0.0.0/0`, all-ports, and all-protocol rules advanced/lab-only.

## Experiment Patterns

| Pattern | Scope | Evidence |
| --- | --- | --- |
| Egress block | destination host/CIDR + port + protocol | rule installed, counter increments, dependency failure, rollback |
| Ingress block | local port + source CIDR + protocol | listener preserved, inbound probe fails, rollback |
| Port reject | local or remote port with REJECT | fast failure semantics, app error handling |
| Dependency blackhole | one dependency endpoint | timeout budget, retry/circuit breaker evidence |
| Firewall backend inventory | read-only | backend, zones, rules, counters, control path |

## Required Metadata

- Use `resilience_metadata.component: "firewall"` and `execution_methods: ["remote_ops"]`.
- Include config for backend auto-detect, direction, interface, destination, port, protocol, duration, rule comment, preflight-only, and confirm flags.
- Include guardrails: `backend-detected`, `control-path-protected`, `single-rule-scope`, `labeled-rule`, `ttl`, `counter-evidence`, and `rollback-verified`.
- Include curated measurements for active backend, applied rule count, matched packet/byte counters, blocked probe result, control-path status, and remaining chaos rules after rollback.

## References

- Read `references/firewall-guidance.md` for condensed source-derived firewall security and rule-management guidance.
