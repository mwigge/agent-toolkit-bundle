---
name: rng-skill
description: Use when designing, reviewing, or implementing entropy, random-number-generator, cryptographic randomness, jitter entropy, hardware RNG, pseudo-random generator, blocking RNG, or RNG starvation fault-injection experiments.
---

# RNG Skill

Design RNG experiments around entropy source classification, consumer impact, and safety floors. Treat entropy disruption as a system dependency fault: it can affect TLS handshakes, key generation, token generation, UUID quality, cryptographic libraries, and boot-time services.

## Core Workflow

1. Inventory RNG sources: `/proc/sys/kernel/random/*`, `/proc/sys/crypto/fips_enabled`, `/dev/random`, `/dev/urandom`, `getrandom(2)` behavior, `rngd`, `haveged`, jitter entropy, TPM/HWRNG devices, VM entropy devices, and container/cgroup context.
2. Classify the target path: hardware RNG, true/random physical source, cryptographic DRBG/CSPRNG, pseudo-random deterministic generator, jitter-based generator, or application-specific library RNG.
3. Define the consumer: TLS/key generation, session tokens, database identifiers, queue IDs, JVM SecureRandom, OpenSSL, Python `secrets`, Java crypto, or kernel randomness.
4. Choose the least-invasive fault: observation first, entropy-source service stop, HWRNG device withdrawal, entropy load/consumer pressure, blocking RNG pressure, or library misconfiguration in a scoped test process.
5. Capture recovery: entropy availability, blocking duration, consumer latency, error count, service health, and rollback status.

## Guardrails

- Start with preflight-only and observation unless the target is disposable or dedicated-validation.
- Keep control-plane tokens, SSH, Ops Agent auth, package managers, and CI signing paths out of the blast radius.
- Never weaken cryptography in shared or production environments. For degraded RNG quality, use a scoped process/container with explicit test-only configuration.
- Apply duration and floor limits: abort if available entropy, key-generation latency, TLS errors, or service error rate crosses the configured critical threshold.
- Require rollback of stopped entropy services and proof that entropy sources returned to baseline.

## Experiment Patterns

| Pattern | Use | Evidence |
| --- | --- | --- |
| Entropy baseline | Confirm source inventory and consumer latency before faults. | entropy avail, rng services, HWRNG devices, keygen latency |
| Entropy consumer pressure | Run bounded reads/key generation to expose blocking/latency. | read latency, keygen p95/p99, errors, entropy delta |
| RNG daemon disruption | Stop/restart `rngd` or `haveged` with rollback. | service state, entropy recovery, rollback verified |
| Jitter entropy validation | Verify jitter entropy availability and behavior under CPU pressure. | jitter module presence, CPU load, entropy deltas |
| Scoped weak RNG | Test application handling with deterministic RNG in an isolated process. | config scope, no shared crypto weakening, consumer assertions |

## Required Metadata

- Use `resilience_metadata.component: "entropy"` or `"rng"`.
- Include `fault_pattern` such as `entropy-rng-disruption`, `entropy-source-loss`, or `rng-consumer-pressure`.
- Include `guardrails`: `preflight-default`, `bounded-duration`, `consumer-scope-required`, `crypto-weakening-forbidden`, `control-path-protected`, and `rollback-verified`.
- Include curated measurements for entropy available before/during/after, RNG service status, consumer latency, blocking reads, error count, and rollback status.

## References

- Read `references/rng-guidance.md` for condensed source-derived guidance on RNG source types and experiment design.
