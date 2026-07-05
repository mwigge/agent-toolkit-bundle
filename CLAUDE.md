# Development Standards — Claude Code Setup

**Version**: 1.0 | **Updated**: 2026-06-03

> **Design principle**: CLAUDE.md is advisory context. Hooks are deterministic enforcement.
> Rules that must *always* run belong in `~/.claude/settings.json`, not here.

---

## Non-Negotiable Rules (Hook-Enforced)

These are enforced by hooks — listed here for awareness only.

- **No AI attribution anywhere** — never mention AI, Claude, OpenAI, agent names, or TDD phases in commits, PR/MR descriptions, code comments, documentation, or any project artifact. No `Co-Authored-By` AI trailers, no `Generated with` footers.
- **No hardcoded secrets** — env vars only; fail-fast if absent; never log
- **Parameterised SQL only** — `cursor.execute("... WHERE id = %s", (val,))`
- **No `print()` / `console.log` in library code** — structured logging only
- **No deprecated `typing.Dict/List`** — use `dict/list/X | None` (Python 3.10+)
- **No `any` without justification** — TypeScript strict mode enforced
- **No bare `except:`** — catch specific exceptions
- **≥95% coverage (Python), ≥80% (TypeScript)** on all changed files
- **ESLint 9 flat config MUST exist** in every TypeScript / Vue / Astro repo. Skipping ESLint because it is "not configured" is a defect. The Stop hook (`quality-gate.sh`) blocks completion when an `eslint.config.*` exists and changed files have ESLint errors.
- **SOLID at all times** — every class/module has one reason to change; depend on abstractions, not concretions; no god objects. See `/solid`.
- **Clean code** — no primitive obsession; no `else` when early return works; methods < 10 lines; no abbreviations. See `/solid`.
- **TDD** — write a failing test before production code; Red → Green → Refactor; no skipping the refactor phase. See `/tdd-workflow`.

---

## Code Standards — Load Skills On Demand

These standards apply to ALL development projects across all AI clients. Skills are **not** enumerated in full here — listing ~150 skills every session defeats progressive disclosure. Load the one you need with `/skill-name`, or let the `skill-activation` hook auto-load it from a keyword match.

- **Full catalogue** (every skill, by domain): [docs/skills.md](docs/skills.md)
- **Auto-activation keyword → skill map**: [skill-rules.json](skill-rules.json)

Skills are organised into these categories:

- **Software Engineering Principles** — `/solid`, `/tdd-workflow`, `/verification-loop`, `/refactoring-specialist`, `/code-simplifier`, `/systematic-debugging`, property-based testing
- **Architecture & Design** — blueprint generation, microservices, cloud design patterns, API/interface design, ADRs, deprecation & migration, multi-tenancy
- **Languages & Frameworks** — Python, TypeScript, Node.js, Rust, Go, React/Next.js, Vue/Nuxt, frontend UI, PDM, TS libraries
- **Document Generation** — `/pdf`, `/docx`, `/pptx`, `/xlsx` (read, extract, and create office formats)
- **Database & Data** — schema/SQL/Postgres optimisation, MongoDB, Supabase, data engineering, data analysis, statistics, time series, visualisation
- **Quality & Review** — code quality, PR review, differential & static analysis, bug finding, mutation testing, audit-context building
- **Security & Compliance** — security review, GitHub Actions security, compliance (GDPR/DORA/PCI-DSS), OAuth
- **Testing** — TDD, property-based, mutation, Playwright / webapp testing
- **DevOps & Infrastructure** — Docker, Kubernetes, Terraform/IaC, CI/CD, GitHub Actions efficiency, rollout plans
- **Git & Workflow** — conventional commits, branching, issues, releases, GitLab CLI
- **Observability & SRE** — OTel, monitoring, Grafana, alerting, SLO/SLI/SLA, incident response, runbooks, on-call, capacity
- **Cloud Platforms** — AWS, Azure, GCP (deploy, serverless, reliability, security, cost)
- **Product & UX** — product owner, epic breakdown, web design guidelines, UX research
- **AI/LLM Development** — AI developer, prompt engineering, workflow diagnostics
- **Datadog** — APM, audit, logs, monitors
- **Context & Memory** — `/codegraph`, `/mempalace`, `/context-map`
- **Token Compression** — `/caveman` family
- **Workflow** — OpenSpec `/openspec-*`

The always-on engineering skills cited in the Non-Negotiable Rules above (`/solid`, `/tdd-workflow`) apply to every task regardless of keyword match.

---

## Stack Defaults

| Concern | Python | TypeScript | Rust |
|---------|--------|------------|------|
| Runtime | Python 3.10+ | Node 22 LTS | stable toolchain |
| Packages | PDM + `pdm.lock` | pnpm 9 | Cargo |
| Lint/format | ruff + black | ESLint 9 flat + Prettier | `cargo fmt` + `cargo clippy -D warnings -W clippy::pedantic` |
| Types | mypy strict | tsc strict | native |
| Security | bandit (HIGH=block) | npm audit | `cargo audit` |
| CVE audit | pip-audit | npm audit | `cargo audit` |
| Tests | pytest + pytest-cov (≥95%) | Vitest (≥80%) | `cargo test --workspace` |
| Observability | OpenTelemetry SDK | OpenTelemetry SDK | OpenTelemetry SDK |

### Rust-Specific Notes

- No `.unwrap()` in library code — use `?` or explicit error handling
- `#[must_use]` on all `Result`-returning public functions
- No `#[allow(...)]` without an explanatory comment on the same line
- Use `thiserror` for library errors, `anyhow` for binary/CLI errors only
- No blocking `std::fs` / `std::io` inside `async` functions — use `tokio::fs`
- Use a **300000ms timeout** for `git commit` when pre-commit hooks run the full test suite
- See `/rust` skill for complete 179-rule reference

---

## Commit Standard (Conventional Commits)

Format: `{type}({scope}): {description}` — types: `feat` `fix` `refactor` `test` `docs` `chore`.
Breaking change: add `!` before `:`.

- **Never** mention TDD phases, agent names, or AI in commit messages
- **Never** add AI attribution (`Co-Authored-By: Claude` etc.)
- **Never** reference internal planning artifacts or labels in PR/MR descriptions

---

## Branch Rules

**NEVER commit directly to `main`/`master`. Always use a feature branch.**

- One branch per logical unit of work
- PR/MR must pass all CI status checks before merge
- Delete branch locally and remotely after merge

---

## Observability Standards

Every new action, probe, or service endpoint must:

- Emit an OTel span with appropriate attributes
- Use structured logging only — no `print()`, no credentials in output
- Follow metric naming conventions appropriate to the domain

See `/observability` skill for full OTel SDK patterns.

---

## Reduce Entropy While Coding

- Prefer the smallest coherent change that closes the requirement
- Delete obsolete branches, unused helpers, and dead configuration while touching the same surface
- Avoid parallel abstractions — extend existing patterns unless clearly broken
- Name things by domain intent, not implementation trivia
- Keep control flow shallow: validate early, return early, isolate exceptional paths
- Make state transitions explicit and testable
- Add tests around behavior boundaries, not incidental implementation
- Keep generated artifacts, package churn, formatting churn, and broad refactors out of feature commits
- When a file accumulates special cases, extract the common policy or data shape before adding another branch

---

## Session Memory

Save session state to memory every ~15 minutes and after every commit.
Include: active branch, what was done, what is pending, key decisions.

See `/mempalace` skill for cross-session persistent memory.

---

## CodeGraph Convention

When inside a large repo, prefer CodeGraph MCP tools over Grep/Glob for code exploration.

| Task | Tool |
|------|------|
| Find a symbol or function | `codegraph_search` |
| Understand a function's context | `codegraph_context` |
| Find callers | `codegraph_callers` |
| Find callees | `codegraph_callees` |
| Assess blast radius | `codegraph_impact` |
| Look up a node | `codegraph_node` |
| Find files | `codegraph_files` |

Fall back to Grep/Glob only when CodeGraph returns no results or is unavailable.
See `/codegraph` skill for full MCP tool reference.
