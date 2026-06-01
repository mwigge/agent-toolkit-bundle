# RNG Guidance

Source basis: `https://quside.com/random-number-generator-types/`.

Use this as condensed working guidance, not as a copy of the source material.

## RNG Categories

- True/physical RNG sources derive randomness from physical processes.
- Hardware RNGs expose dedicated hardware entropy sources and may feed the kernel pool through services such as `rngd`.
- Jitter entropy derives randomness from timing variation and CPU behavior.
- Cryptographic DRBG/CSPRNG expands seed entropy into secure random streams.
- Pseudo-random generators are deterministic and only safe for cryptographic use when designed and seeded as CSPRNGs.

## Experiment Implications

- Separate source failure from consumer failure. A source can degrade while a CSPRNG still serves requests for a period.
- Measure both quality-facing indicators and operational impact: entropy availability, blocking reads, key-generation latency, TLS failures, service errors, and recovery time.
- Avoid shared weak-RNG configuration. Deterministic RNG belongs only in isolated test processes.
- Treat entropy service disruption as reversible service disruption with crypto-specific abort thresholds.

## Inventory Fields

- `/proc/sys/kernel/random/entropy_avail`.
- `/proc/sys/kernel/random/poolsize` when available.
- HWRNG devices and drivers.
- `rngd`, `haveged`, jitter entropy, and FIPS status.
- Crypto consumers: OpenSSL, JVM SecureRandom, Python secrets, application token/key generators.
