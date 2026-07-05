# Fault Injection Catalogue

Faults by layer, the tools that inject them, and their use cases.

## Application layer

| Fault | Tool | Use case |
|-------|------|----------|
| HTTP error injection | Envoy fault filter, Istio | Test error handling in callers |
| Latency injection | tc, Envoy, Toxiproxy | Test timeout and retry behaviour |
| Exception injection | Code-level toggle | Test error paths |
| Thread pool exhaustion | Custom action | Test bulkhead isolation |

## Infrastructure layer

| Fault | Tool | Use case |
|-------|------|----------|
| Process kill | `kill -9`, Chaos Toolkit | Test restart/recovery |
| CPU stress | `stress-ng` | Test under resource contention |
| Memory pressure | `stress-ng --vm` | Test OOM handling |
| Disk fill | `fallocate` | Test disk-full error handling |
| Network partition | `iptables`, `tc` | Test split-brain, failover |
| DNS failure | `/etc/hosts`, CoreDNS | Test DNS resolution failures |

## Data layer

| Fault | Tool | Use case |
|-------|------|----------|
| DB connection limit | `pgbouncer` config | Test connection pool exhaustion |
| Slow queries | `pg_sleep()` | Test query timeout handling |
| Replica lag | Artificial delay | Test read-after-write consistency |
| Cache eviction | `redis-cli FLUSHALL` | Test cache-miss thundering herd |
