# Firewall Guidance

Source basis: `https://mcpmarket.com/tools/skills/firewall-configuration-security`.

Use this as condensed working guidance, not as a copy of the upstream material.

## Principles

- Apply least privilege: one direction, one protocol, one port, one destination/source where possible.
- Preserve management/control traffic and observability.
- Prefer explicit rule labels/comments for traceability.
- Capture snapshots before and after changes.
- Use atomic and reversible changes; do not flush chains or change default policy for chaos experiments.

## Backend Inventory

- firewalld active zones and services.
- nftables tables, chains, hooks, priorities, and handles.
- iptables backend: nft or legacy.
- conntrack availability and current counts.
- Existing default policies and chaos-labeled rules.

## Evidence

- Rule installed with handle/comment.
- Packet and byte counters increment or remain zero as expected.
- Target probe changes during the fault.
- Control-path probe remains healthy.
- Rule removed and chaos-labeled rule count returns to zero.
