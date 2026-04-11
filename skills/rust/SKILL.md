---
name: rust
description: >
  Comprehensive Rust engineering skill covering coding patterns (179 rules),
  agentic methodology (RPI debugging, security, borrow checker), and
  OpenTelemetry instrumentation (traces, metrics, logs). Use when writing,
  reviewing, refactoring, debugging, or instrumenting Rust code.
  Invoke with /rust, /rust-patterns, /rust-agentic, or /rust-otel.
metadata:
  version: "1.0.0"
  sources:
    - Rust API Guidelines
    - Rust Performance Book
    - ripgrep, tokio, serde, polars codebases
    - https://github.com/udapy/rust-agentic-skills
    - David Barsky's Rust style gist
    - OpenTelemetry Rust SDK documentation
    - OpenTelemetry Semantic Conventions
    - https://github.com/dash0hq/agent-skills
  trigger_phrases:
    - rust
    - cargo
    - borrow checker
    - ownership
    - lifetimes
    - thiserror
    - anyhow
    - tokio
    - async rust
    - clippy
    - opentelemetry rust
    - otel rust
    - tracing crate
    - rust spans
    - rust metrics
---

# Rust Engineering Skill

Unified skill for writing, reviewing, debugging, and instrumenting production Rust code.
Combines 179 coding rules, agentic methodology (Research-Plan-Implement), and
OpenTelemetry instrumentation patterns for chaos engineering workloads.

## Quick Reference

| Area | Detail file |
|------|-------------|
| Coding rules (179 rules, 14 categories) | `refs/patterns.md` |
| Agentic methodology (RPI, debugging, security, style) | `refs/agentic.md` |
| OpenTelemetry instrumentation (traces, metrics, logs) | `refs/opentelemetry.md` |
| Async & Tokio cheatsheet | `refs/async-tokio-cheatsheet.md` |
| Error handling cheatsheet | `refs/error-handling-cheatsheet.md` |
| Borrow checker error resolution | `refs/borrow-checker-errors.md` |
| Debug techniques | `refs/debug-techniques.md` |
| OTel crate versions | `refs/otel-crate-versions.md` |
| Rust Book chapter index | `refs/rust-book-reference.md` |
| All references combined | `refs/REFERENCES.md` |

---

## Quality Gates

Run before every commit:

```bash
cargo fmt --check
cargo clippy -- -D warnings -W clippy::pedantic
cargo test --workspace
cargo audit
```

All four must pass. Use a **300000ms timeout** for `git commit` when pre-commit hooks
run the full test suite.

---

## Top Rules (must-know)

### Ownership & borrowing

1. **Borrow over clone** -- prefer `&T` over `.clone()`
2. **Slice parameters** -- accept `&[T]` not `&Vec<T>`, `&str` not `&String`
3. **Cow for conditional ownership** -- `Cow<'a, T>` when ownership is sometimes needed
4. **No locks across .await** -- never hold `Mutex`/`RwLock` guards across `.await`
5. **Move large data** -- move instead of cloning large structures

### Error handling

6. **thiserror for libraries, anyhow for binaries** -- never mix
7. **No `.unwrap()` in library code** -- use `?` or explicit error handling
8. **`#[must_use]` on all Result-returning public functions**
9. **Context chains** -- add `.context()` at every call site
10. **Custom error types** -- not `Box<dyn Error>`

### API design

11. **Builder pattern** for complex construction (see `templates/builder-pattern.rs`)
12. **Newtype safety** -- wrap IDs and validated data in newtypes
13. **`#[non_exhaustive]`** for future-proof public enums/structs
14. **Common trait derives** -- `Debug`, `Clone`, `PartialEq` on all public types
15. **Parse, don't validate** -- parse into validated types at boundaries

### Memory & performance

16. **`with_capacity()`** when collection size is known
17. **Iterators over indexing** -- avoids bounds checks, more idiomatic
18. **Profile before optimizing** -- `perf-profile-first`

---

## Methodology: Research-Plan-Implement (RPI)

Every task follows three phases:

1. **Research** -- understand the problem, read relevant code, identify constraints
2. **Plan** -- design the solution, identify affected modules, define acceptance criteria
3. **Implement** -- write the code, run quality gates, verify correctness

---

## Coding Style Summary

- Every public function has a doc comment (`///`) and type annotations
- Summary sentences: third-person singular present tense with periods
- Standard doc sections: Examples, Panics, Errors, Safety
- Prefer `for` loops with accumulators over complex iterator chains when readability suffers
- Use `let ... else` for early returns to keep the happy path unindented
- Shadow variables through transformations rather than renaming
- Strongly-typed enums over boolean parameters
- Always match all variants explicitly -- no wildcard `_` on enums you own
- Group imports: std, external crates, crate-internal
- Run `cargo fmt` before every commit

---

## Async Patterns

- Use Tokio for production async runtime
- `spawn_blocking` for CPU-intensive work
- `tokio::fs` not `std::fs` in async code
- `CancellationToken` for graceful shutdown
- Bounded channels for backpressure
- `JoinSet` for dynamic task groups

See `refs/async-tokio-cheatsheet.md` for full reference.

---

## OpenTelemetry Instrumentation

### Key principles

- **Signal density over volume** -- every telemetry item must detect, localize, or explain
- **Sample in the pipeline, not the SDK** -- use `AlwaysOn` sampler, defer to Collector
- **Never log credentials** in span attributes or structured logs

### Span naming

- Lowercase dot-separated: `chaos.action.execute`, `chaos.probe.check`
- Low cardinality -- variable data goes in attributes, not span names
- Format: `<component>.<operation>` or `<component>.<entity>.<operation>`

### Metric naming

- Format: `chaos.<component>.<metric>.<unit>`
- Examples: `chaos.experiment.duration.seconds`, `chaos.probe.latency.milliseconds`
- Keep attribute cardinality under 100 per metric

### Structured logging

- Use `tracing` crate with `#[instrument]` for automatic span creation
- Map log levels: ERROR (failures), WARN (degraded), INFO (lifecycle), DEBUG (state), TRACE (wire)
- Correlate logs with traces via `tracing-opentelemetry`

See `refs/opentelemetry.md` for SDK setup, span conventions, metrics, and sensitive data rules.
See `refs/otel-crate-versions.md` for dependency versions.

---

## Debugging

1. **Reproduce** -- write a failing test or minimal reproducible example
2. **Isolate** -- Wolf Fence method with `dbg!()` (binary search the code path)
3. **Resolve** -- fix the logic, remove all `dbg!()` before commit

Tools: `RUST_BACKTRACE=1`, `RUST_LOG=debug`, `cargo expand`, `rustc --explain E0xxx`

See `refs/debug-techniques.md` and `refs/borrow-checker-errors.md`.

---

## Security

1. `cargo audit` for dependency vulnerabilities
2. Every `unsafe` block needs a `// SAFETY:` comment explaining the invariant
3. No hardcoded secrets -- use `std::env::var` or config files
4. All external input validated at boundaries
5. Chaos actions must never escalate privileges beyond what is declared

See `scripts/security-audit.sh`.

---

## Cargo.toml Defaults

```toml
[profile.release]
opt-level = 3
lto = "fat"
codegen-units = 1
panic = "abort"
strip = true

[profile.bench]
inherits = "release"
debug = true
strip = false

[profile.dev]
opt-level = 0
debug = true

[profile.dev.package."*"]
opt-level = 3  # Optimize dependencies in dev

[lints.clippy]
pedantic = { level = "warn", priority = -1 }
correctness = "deny"
```

---

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/quality-gate.sh` | Full quality gate (fmt, clippy, test, audit) |
| `scripts/new-crate.sh` | Scaffold a new crate with standard config |
| `scripts/security-audit.sh` | Security-focused audit (deps, unsafe, unwrap) |

## Templates

| Template | Purpose |
|----------|---------|
| `templates/lib-crate.rs` | Library crate entry point |
| `templates/error-type.rs` | thiserror-based error type |
| `templates/builder-pattern.rs` | Builder with typestate |
| `templates/test-module.rs` | Test module structure |
| `templates/main-bin.rs` | Binary entry point with anyhow + tracing |
| `templates/otel-setup.rs` | OpenTelemetry initialization |
| `templates/instrumented-function.rs` | Function with OTel tracing |

---

## Sources

- [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/)
- [Rust Performance Book](https://nnethercote.github.io/perf-book/)
- [Rust Design Patterns](https://rust-unofficial.github.io/patterns/)
- [OpenTelemetry Rust SDK](https://docs.rs/opentelemetry/latest/opentelemetry/)
- [tracing-opentelemetry](https://docs.rs/tracing-opentelemetry/latest/tracing_opentelemetry/)
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- Production codebases: ripgrep, tokio, serde, polars, axum, deno
