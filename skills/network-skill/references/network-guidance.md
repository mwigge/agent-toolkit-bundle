# Network Guidance

Source basis: `https://explainx.ai/skills/404kidwiz/claude-supercode-skills/network-engineer`.

Use this as condensed working guidance, not as a copy of the source material.

## Network Experiment Design

- Start from topology and flow mapping.
- Identify source, destination, interface, route, protocol, port, DNS name, timeout, retry policy, and owner.
- Prefer scoped qdisc/rule changes over broad host-level changes.
- Verify before/during/after with independent probes and system counters.

## Evidence Sources

- `ip addr`, `ip route`, `ss -lntup`, `resolvectl` or `/etc/resolv.conf`.
- `tc qdisc show`, `tc -s qdisc show`, class/filter state.
- firewall rule counters where firewall-based injection is used.
- TCP connect latency, HTTP health, DNS resolution result, retransmits where available.

## Rollback Checks

- qdisc, route, DNS, and firewall state match the pre-fault baseline.
- Control path remains reachable.
- Application metrics recover within the declared objective.
