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

## Code Standards — Load Skill for Full Guidance

These standards apply to ALL development projects across all AI clients.

### Software Engineering Principles

- `/solid` — SOLID principles, clean code, value objects, early return, methods < 10 lines
- `/tdd-workflow` — Red-Green-Refactor, tests before code, coverage gates
- `/verification-loop` — Verification discipline, quality loops
- `/refactoring-specialist` — Code smell detection, safe transformations, tech debt
- `/code-simplifier` — Clarity, consistency, maintainability, readability
- `/property-based-testing` — Hypothesis, QuickCheck, invariant testing

### Architecture & Design

- `/architecture-blueprint-generator` — Codebase analysis, pattern detection, diagrams
- `/microservices-architect` — Service decomposition, API contracts, saga, CQRS
- `/cloud-design-patterns` — 42 patterns: reliability, performance, messaging, security
- `/api-and-interface-design` — REST/GraphQL endpoints, type contracts, module boundaries
- `/api-designer` — OpenAPI 3.1, REST design, pagination, versioning
- `/create-architectural-decision-record` — ADR documentation, AI-optimized decisions
- `/deprecation-and-migration` — API sunset, migration strategies, feature removal
- `/multi-tenancy` — Isolation models, RLS, tenant context propagation

### Languages & Frameworks

- `/python` — Type hints, pytest, 95% coverage, patterns, clean architecture
- `/pdm-expert` — PDM package manager, Artifactory PyPI, lock file strategy
- `/typescript` — Strict mode, Vitest, DI, Red-Green-Refactor, clean architecture
- `/ts-library` — npm packages, tsdown/unbuild, dual CJS/ESM, publishing
- `/vue-best-practices` — Composition API, `<script setup>`, TypeScript required
- `/vue-testing-best-practices` — Vitest, Vue Test Utils, component testing, Playwright
- `/vue-pinia-best-practices` — Pinia stores, state management, reactivity
- `/vue-router-best-practices` — Vue Router 4, navigation guards, route params
- `/vue-debug-guides` — Runtime errors, warnings, async failures, SSR/hydration
- `/vue-jsx-best-practices` — JSX syntax in Vue, class vs className, plugin config
- `/vueuse` — VueUse composables, reactive browser APIs
- `/create-adaptable-composable` — MaybeRef/MaybeRefOrGetter, toValue()/toRef()
- `/nuxt` — Server routes, middleware, Nuxt 4+ composables, h3 v1, nitropack v2
- `/rust` — 179 rules, borrow checker, thiserror/anyhow, OTel instrumentation
- `/golang-patterns` — Idiomatic Go, error handling, concurrency, interfaces
- `/go-style-guide` — Go package design, CLI patterns, logging, benchmarks
- `/nodejs` — Fastify, NestJS, Pino, TypeBox patterns
- `/frontend-ui-engineering` — Production-quality UI, components, layouts, state

### Database & Data

- `/database` — Schema design, migrations, indexing, query optimization, RLS
- `/sql-optimization` — Execution plans, pagination, batch operations, monitoring
- `/postgresql-optimization` — JSONB, arrays, full-text search, window functions, extensions
- `/mongodb-schema-design` — Embed vs reference, unbounded arrays, TTL, versioning
- `/mongodb-connection` — Connection pools, timeouts, serverless patterns
- `/mongodb-query-optimizer` — Index strategy, slow query diagnosis
- `/data-engineer` — Pipelines, dbt, Spark, data contracts, idempotency
- `/data-analyst` — EDA, pandas/NumPy, summary statistics, outlier detection
- `/data-visualisation` — Chart selection, matplotlib/seaborn/plotly, dashboards
- `/statistical-analysis` — Hypothesis testing, regression, confidence intervals
- `/time-series` — ARIMA/GARCH, rolling windows, seasonality, forecasting
- `/supabase-patterns` — Auth, RLS, Edge Functions, Realtime, Cron, Queues
- `/supabase-postgres-best-practices` — Postgres performance from Supabase lens

### Quality & Review

- `/addy-code-quality` — Multi-axis review: correctness, readability, architecture, security, performance
- `/health` — Code quality dashboard, codebase health check
- `/pr-review` — Pre-merge review workflow, approval standards
- `/differential-review` — Security-focused diff analysis, blast radius
- `/code-review` (coderabbit) — Automated review, PR feedback application
- `/find-bugs` — Bug detection, vulnerability scanning on local branch changes
- `/static-analysis` — CodeQL, Semgrep, SARIF processing
- `/audit-context-building` — Line-by-line analysis, deep architectural context
- `/mutation-testing` — mewt/muton campaign configuration, coverage quality

### Security & Compliance

- `/security-review` — Vulnerability detection, OWASP, injection, XSS, auth
- `/gha-security-review` — GitHub Actions exploitation, pwn requests, expression injection
- `/compliance` — Regulatory requirements, evidence, audit trails
- `/oauth` — PKCE, JWT, access/refresh tokens, authorization flows

### Testing

- `/tdd-workflow` — Test-driven development, Red-Green-Refactor
- `/property-based-testing` — Invariant testing, fuzzing
- `/mutation-testing` — Mutation campaign configuration
- `/webapp-testing` — Playwright interaction, screenshots, browser logs
- `/playwright-generate-test` — Test generation from user scenarios
- `/playwright-explore-website` — Website exploration for testing

### DevOps & Infrastructure

- `/docker-expert` — Dockerfile optimization, multi-stage, security hardening
- `/kubernetes-patterns` — Pod design, RBAC, GitOps, autoscaling, secret management
- `/terraform-skill` — Modules, state, drift detection, policy-as-code, CI
- `/iac-patterns` — Module design, environment promotion, secret management
- `/ci-cd` — Pipeline design, deployment strategies, quality gates
- `/github-actions-efficiency` — CI minutes optimization, caching, parallelism
- `/devops-rollout-plan` — Preflight checks, step-by-step deployment, rollback

### Git & Workflow

- `/git-commit` — Conventional commits, intelligent staging, message generation
- `/git-flow-branch-creator` — Branch naming, Git Flow model
- `/github-issues` — Issue management, labels, milestones, dependencies
- `/github-release` — SemVer versioning, Keep a Changelog formatting
- `/gitlab-glab` — GitLab CLI operations, MRs, pipelines

### Observability & SRE

- `/observability` — OTel spans, trace propagation, metrics, structured logging
- `/monitoring-expert` — Prometheus, dashboards, alerts, SLOs, runbooks
- `/build-grafana-dashboards` — Panels, template variables, annotations, provisioning
- `/configure-alerting-rules` — Alertmanager, routing trees, PagerDuty, Slack receivers
- `/sre` — SLI/SLO, error budgets, burn rate, capacity planning, on-call
- `/incident-response` — Severity classification, lifecycle, PagerDuty, escalation
- `/write-incident-runbook` — Diagnostic steps, resolution procedures, escalation paths
- `/define-slo-sli-sla` — Reliability targets, error budgets, burn rate alerts
- `/design-on-call-rotation` — Balanced schedules, escalation policies, fatigue management
- `/plan-capacity` — Historical metrics, growth models, headroom calculation
- `/forecast-operational-metrics` — Prophet/statsmodels forecasting, proactive scaling
- `/performance-engineer` — Load testing, profiling, benchmarking, latency optimization

### Cloud Platforms

- `/aws-deploy` — Optimal service selection, cost estimation, infrastructure generation
- `/aws-lambda` — Serverless functions, event sources, cold starts
- `/aws-cdk-development` — CDK stacks, constructs, TypeScript/Python, deployment
- `/aws-serverless-eda` — Event-driven, Step Functions, EventBridge, SQS, SNS
- `/aws-api-gateway` — REST/HTTP/WebSocket APIs, authorizers, throttling, CORS
- `/aws-cost-operations` — Billing analysis, CloudWatch alarms, CloudTrail audit
- `/azure-enterprise-infra-planner` — Landing zones, hub-spoke, Bicep, WAF alignment
- `/azure-kubernetes` — AKS clusters, networking, security, autoscaling
- `/azure-reliability` — Zone redundancy, multi-region failover, health probes
- `/gcp-gke` — GKE Autopilot, Workload Identity, Gateway API, cost optimization
- `/gcp-bigquery` — Datasets, BigQuery ML, Gemini integration, data analytics
- `/gcp-cloud-run` — Services, jobs, worker pools, event-triggered tasks
- `/gcp-reliability` — Well-Architected reliability guidance for GCP
- `/gcp-security` — IAM, network security, data protection, operational security

### Product & UX

- `/product-owner` — Stories, INVEST, RICE, OKR, backlog management
- `/breakdown-epic-arch` — Epic technical architecture from PRD
- `/web-design-guidelines` — Interface Guidelines compliance, accessibility
- `/replay-ux-research` — Session replay analysis, user journeys, pain points

### AI/LLM Development

- `/ai-developer` — LLM, RAG, MCP servers, vector stores, evaluations
- `/prompt-engineer` — System prompts, few-shot, chain-of-thought, structured output
- `/diagnose` — AI workflow diagnostic scan, 5-dimension quality assessment

### Datadog

- `/dd-apm` — APM setup, SSI instrumentation, traces, service dependencies
- `/dd-audit` — Audit Trail investigations, compliance evidence, cost spikes
- `/dd-logs` — Log management, archives, metrics, cost control
- `/dd-monitors` — Monitor management, alerting best practices

### Context & Memory

- `/codegraph` — Symbol search, call graphs, impact analysis, blast radius
- `/mempalace` — Cross-session persistent memory, wing/room/drawer API
- `/context-map` — Pre-change file mapping, relevant file discovery

### Token Compression

- `/caveman` — ~75% token reduction, full technical accuracy preserved
- `/caveman-commit` — Ultra-compressed conventional commit messages
- `/caveman-review` — Compressed code review comments

### Workflow

- `/openspec-propose` — Spec-driven change proposals with design + tasks
- `/openspec-apply-change` — Task implementation from OpenSpec change
- `/openspec-explore` — Thinking mode, idea exploration, no implementation
- `/openspec-archive-change` — Change archival after implementation

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
