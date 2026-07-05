# Failure Mode Analysis and Domain Chaos Scenarios

FMEA, cascading failure analysis, and targeted security and data-system chaos scenarios.

## Failure Mode Analysis

### FMEA (Failure Mode and Effects Analysis)

For each component, enumerate:

| Component | Failure mode | Cause | Effect | Severity (1-10) | Likelihood (1-10) | Detection (1-10) | RPN | Mitigation |
|-----------|-------------|-------|--------|-----------------|-------------------|------------------|-----|-----------|
| Database | Connection timeout | Network issue | API errors | 8 | 4 | 3 | 96 | Circuit breaker + retry |
| Cache | Complete eviction | Memory pressure | Slow responses | 5 | 3 | 2 | 30 | Warm cache on deploy |

RPN = Severity x Likelihood x Detection (lower detection score = easier to detect = better)

Priority: address highest RPN items first.

### Cascading failure analysis

```
[Service A] --depends-on--> [Service B] --depends-on--> [Database]
                                |
                                +--depends-on--> [Cache]

If Database fails:
  1. Service B: connection errors, circuit breaker opens after 5 failures
  2. Service A: gets errors from Service B, falls back to cached data
  3. Users: see stale data (acceptable) or degraded experience

If Cache fails:
  1. Service B: falls through to Database (increased load)
  2. Database: may hit connection limits under thundering herd
  3. Mitigation: rate-limit cache-miss path, warm cache on recovery
```

---

## Security Chaos Scenarios

Test security mechanisms under failure conditions — not penetration testing, but verifying that security controls degrade gracefully.

| Scenario | Injection method | What to validate |
|----------|-----------------|------------------|
| **Authentication service unavailable** | Network partition the auth service | Requests are rejected (fail-closed), not silently allowed |
| **Authorization policy failure** | Return malformed policy responses | Service denies access by default (fail-closed) |
| **Certificate expiry** | Deploy expired TLS certificates | Connections fail with clear errors, alerts fire, no silent fallback to plaintext |
| **Certificate rotation under load** | Rotate certificates while traffic is flowing | Zero-downtime rotation, no dropped connections during handshake |
| **Secret rotation during active connections** | Rotate database credentials mid-session | Active connections continue; new connections use new credentials |
| **Rate limiter failure** | Disable or crash the rate limiting component | Upstream service handles increased load gracefully or fails closed |
| **Quota exhaustion** | Consume all API quota/rate limit tokens | Clients receive clear 429 responses, not 500s; backpressure propagates |
| **Token validation latency** | Inject 5s latency on token validation endpoint | Requests time out cleanly, users see appropriate error, no cascading auth failures |

### Key principle

Security mechanisms must **fail closed** — if the auth service is down, deny access rather than granting it. Chaos experiments validate this assumption.

---

## Data System Chaos

Extend the data layer fault catalogue with data-integrity and capacity scenarios.

| Scenario | Injection method | What to validate |
|----------|-----------------|------------------|
| **Replication lag** | Inject artificial delay on replica | Read-after-write consistency handled (route reads to primary, or tolerate staleness) |
| **Data corruption detection** | Flip bits in stored data, inject bad checksums | Application detects corruption via checksum validation; does not serve corrupt data |
| **Backup/restore under load** | Trigger backup while system is under peak load | Backup completes without degrading request latency beyond SLO |
| **Restore from backup** | Restore a backup to a parallel environment | Data integrity verified, recovery time within RTO target |
| **Storage quota exhaustion** | Fill disk to 95%, then 100% | Application returns clear errors, does not corrupt existing data, alerts fire before 100% |
| **Connection pool exhaustion** | Consume all connections (hold open without releasing) | New requests get a clear timeout error, circuit breaker opens, pool recovers when connections are released |
| **Write-ahead log (WAL) growth** | Block WAL archiving | Database alerts on WAL growth, does not crash; application handles read-only mode |

### Checksum validation pattern

```python
import hashlib


def verify_data_integrity(data: bytes, expected_checksum: str) -> bool:
    """Verify data has not been corrupted in storage or transit."""
    actual = hashlib.sha256(data).hexdigest()
    return actual == expected_checksum
```
