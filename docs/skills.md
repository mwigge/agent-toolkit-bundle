# Skills

**Purpose**: Domain knowledge modules loaded on demand. Each skill contains expert guidance, reference docs, scripts, and templates for a specific area.

Skills are loaded manually (`/skill-name`) or automatically via the `skill-activation.sh` hook when Claude detects matching keywords in your prompt.

---

## How Skills Work

### Structure

```
skills/
  <skill-name>/
    SKILL.md          # Main instructions — loaded into Claude's context
    refs/             # Official documentation links, deep-dive references
      REFERENCES.md
    scripts/          # Runnable shell/Python scripts
      check.sh
    templates/        # Starter files (pyproject.toml, openapi.yaml, etc.)
      *.py / *.ts / *.yaml
```

**Key point**: `SKILL.md` is read into Claude's context. The `refs/`, `scripts/`, and `templates/` directories are available but not automatically loaded — Claude reads them when relevant.

### Auto-Activation

The `skill-activation.sh` hook scans every prompt against `.claude/skill-rules.json`:

```json
[
  {"pattern": "postgres|SQL|query|index|migration|schema", "skill": "postgres-patterns"},
  {"pattern": "pytest|test.*fixture|parametrize|mock|coverage", "skill": "python-testing"},
  {"pattern": "fastify|@fastify|Pino.*log|TypeBox", "skill": "nodejs-fastify"}
]
```

When a pattern matches, Claude receives an additionalContext hint to load the skill before responding. Multiple skills can activate simultaneously.

### Manual Invocation

Type `/skill-name` in Claude Code to load a skill explicitly:

```
/python-testing         # load pytest patterns and TDD guidance
/postgres-patterns      # load SQL best practices
/api-designer           # load REST/OpenAPI design guidance
```

---

## Skill Catalogue

The bundle ships **159 skill directories**: **152** are directly loadable (a top-level `SKILL.md`), and the remaining 7 are sub-skill families whose `SKILL.md` files live one level down. Counting nested sub-skills there are **187** `SKILL.md` files in total.

The tables below are **curated highlights** by domain — not an exhaustive list. The authoritative, complete inventory is the [Full Skill Index](#full-skill-index) at the bottom of this page. Auto-activation keyword mappings live in [`skill-rules.json`](../skill-rules.json).

### Python

| Skill | When to load | Key guidance |
|-------|-------------|-------------|
| `/python` | Any Python work | Fundamentals, TDD workflow, patterns, testing (pytest), architecture. Detailed content in refs/: `patterns.md`, `testing.md`, `architecture.md`, `developer-workflow.md` |

### TypeScript

| Skill | When to load | Key guidance |
|-------|-------------|-------------|
| `/typescript` | Any TypeScript work | Type system, generics, TDD (Vitest), developer workflow, clean architecture. Detailed content in refs/: `fundamentals.md`, `tdd.md`, `architecture.md`, `developer-workflow.md` |

### Node.js

| Skill | When to load | Key guidance |
|-------|-------------|-------------|
| `/nodejs` | Node.js services | Core platform, Fastify, NestJS. Detailed content in refs/: `core-platform.md`, `fastify.md`, `nestjs.md` |

### Data (5 skills)

| Skill | When to load | Key guidance |
|-------|-------------|-------------|
| `/data-analyst` | Analysing experiment results | EDA workflow, statistical hygiene, Mann-Whitney, effect size, BLUF reports |
| `/data-engineer` | Building pipelines | dbt (staging->intermediate->mart), Airflow TaskFlow, Spark, Snowflake, medallion |
| `/statistical-analysis` | Hypothesis testing | Normality tests, parametric vs non-parametric, bootstrap CI, multiple comparison |
| `/time-series` | Metrics over time | STL decomposition, anomaly detection, Prophet, InfluxDB/Prometheus patterns |
| `/data-visualisation` | Charts and dashboards | Accessible colormaps, Plotly/Seaborn/Matplotlib, Tufte principles |

### Rust

| Skill | When to load | Key guidance |
|-------|-------------|-------------|
| `/rust` | Any Rust work | 179 coding rules, RPI debugging, security audit, OTel instrumentation. Detailed content in refs/: `patterns.md`, `agentic.md`, `opentelemetry.md`, cheatsheets |

### Platform / SRE (8 skills)

| Skill | When to load | Key guidance |
|-------|-------------|-------------|
| `/sre` | Deployments, incidents, reliability | SLI/SLO framework, error budgets, burn rate, capacity planning, toil reduction, on-call, production readiness |
| `/observability` | Instrumentation | OTel span naming, metric naming, distributed tracing, sampling strategies, trace-log correlation |
| `/ci-cd` | Pipeline work | GitLab CI DAG, GitHub Actions, Docker multi-stage, K8s, Helm, SAST/SCA |
| `/incident-response` | Incidents, PIR | SEV1-4 classification, lifecycle, blameless PIR, SLO burn rate response |
| `/chaos-engineer` | Chaos experiment design | Hypothesis formation, blast radius control, safety mechanisms, GameDay planning, FMEA, maturity model |
| `/docker-expert` | Containers | Multi-stage builds, layer caching, Compose patterns, security hardening, image scanning |
| `/kubernetes-patterns` | Container orchestration | Pod design, RBAC, network policies, GitOps, progressive delivery, HPA, secret management |
| `/iac-patterns` | Infrastructure-as-Code | Module design, state management, drift detection, policy-as-code, environment promotion |

### Database

| Skill | When to load | Key guidance |
|-------|-------------|-------------|
| `/database` | Any SQL/DB work | Multi-engine (PG, MySQL, SQLite): schema design, query optimisation, migrations, data quality audit, slow query debugging. PG table design in refs/: `postgresql-table-design.md` |

### Architecture (2 skills)

| Skill | When to load | Key guidance |
|-------|-------------|-------------|
| `/api-designer` | Designing or reviewing HTTP/GraphQL APIs | OpenAPI 3.1-first, RFC 7807 errors, cursor pagination, GraphQL federation, DataLoader, schema evolution |
| `/microservices-architect` | Service boundaries, distributed systems | Bounded contexts, saga, CQRS, service mesh, API gateway, zero-trust, database-per-service |

### Security (3 skills)

| Skill | When to load | Key guidance |
|-------|-------------|-------------|
| `/security-review` | Security-sensitive changes | OWASP Top 10, MCP Top 10, prompt injection, supply chain security, SBOM, typosquatting |
| `/compliance` | GDPR, audit, PII handling | Art. 6/17/33, PII classification, ISO 27001, SOC 2 CC criteria |
| `/oauth` | Auth implementation | OAuth 2.1 / PKCE, JWT verification (RS256/ES256), token storage, Fastify |

### AI Development (2 skills)

| Skill | When to load | Key guidance |
|-------|-------------|-------------|
| `/ai-developer` | LLM features, RAG, MCP | APIs, RAG pipeline, MCP server development, LLM serving patterns, eval suites |
| `/prompt-engineer` | Prompt design, evaluation | System prompts, few-shot, CoT, structured output, A/B testing, token optimisation, eval frameworks |

### Process / Quality (7 skills)

| Skill | When to load | Key guidance |
|-------|-------------|-------------|
| `/tdd-workflow` | TDD coaching | Red-Green-Refactor, quality metrics (defect density, shift-left, mutation testing) |
| `/verification-loop` | Pre-MR quality check | Full lint/typecheck/test/security sweep, pre-MR checklist |
| `/pr-review` | Code review | 4-lens framework, blast radius, BLOCKING vs nit, approval criteria |
| `/documentation` | Writing docs, ADRs | Diataxis framework, ADR format, RFC template, CHANGELOG |
| `/presentation` | Stakeholder comms | C4 model, BLUF structure, Mermaid diagrams, assertion-evidence slides |
| `/refactoring-specialist` | Code cleanup, tech debt | Smell detection, extract/inline/move patterns, strangler fig, complexity metrics |
| `/performance-engineer` | Load testing, profiling | Test taxonomy, anti-patterns, performance budgets, capacity analysis |

### Product (1 skill)

| Skill | When to load | Key guidance |
|-------|-------------|-------------|
| `/product-owner` | Story writing, prioritisation | INVEST, GWT acceptance criteria, RICE scoring, OKR structure |

### Specialist

| Skill | When to load | Key guidance |
|-------|-------------|-------------|
| `/golang-patterns` | Go code | Idiomatic Go — errors, interfaces, concurrency |
| `/pdm-expert` | PDM package manager | Artifactory, lock file strategy, include_packages/exclude_packages |
| `/multi-tenancy` | SaaS tenant isolation | Shared schema, RLS, query scoping, tenant context propagation |
| `/web-design-guidelines` | UI review | WCAG 2.1 accessibility, Web Interface Guidelines, keyboard nav, screen readers |
| `/mempalace` | Cross-session memory | Palace structure, MCP tools, wing/room/drawer API, mining |
| `/skill-development` | Creating or improving skills | Skill anatomy, progressive disclosure, creation process, validation |

### OpenSpec (4 skills)

| Skill | When to load | Key guidance |
|-------|-------------|-------------|
| `/openspec-propose` | Creating a new change | Generates proposal, design, specs, tasks in one step |
| `/openspec-apply-change` | Implementing a change | Picks next unchecked task, implements it |
| `/openspec-explore` | Thinking mode | Explore ideas, investigate problems, no implementation |
| `/openspec-archive-change` | Archiving a change | Promotes specs, moves to archive |

---

## Full Skill Index

Every directly loadable skill (152 — each has a top-level `SKILL.md`, invoke with `/<name>`):

`addy-code-quality` · `addy-performance` · `ai-developer` · `api-and-interface-design` · `api-designer` · `architecture-blueprint-generator` · `autofix` · `aws-api-gateway` · `aws-architecture-diagram` · `aws-cdk-development` · `aws-cost-operations` · `aws-deploy` · `aws-dsql` · `aws-lambda` · `aws-serverless-deployment` · `aws-serverless-eda` · `azure-enterprise-infra-planner` · `azure-kubernetes` · `azure-reliability` · `breakdown-epic-arch` · `build-grafana-dashboards` · `canary` · `caveman` · `caveman-commit` · `caveman-compress` · `caveman-help` · `caveman-review` · `chaos-engineer` · `chaostooling-standards` · `ci-cd` · `cloud-design-patterns` · `codegraph` · `coderabbit-code-review` · `code-simplifier` · `compliance` · `configure-alerting-rules` · `confluence` · `context-map` · `conventional-commit` · `create-adaptable-composable` · `create-architectural-decision-record` · `data-analyst` · `database` · `data-engineer` · `data-visualisation` · `dd-apm` · `dd-audit` · `dd-logs` · `dd-monitors` · `dd-pup` · `define-slo-sli-sla` · `deprecation-and-migration` · `design-on-call-rotation` · `devops-rollout-plan` · `diagnose` · `docker-expert` · `documentation` · `documentation-and-adrs` · `document-release` · `find-bugs` · `firewall-skill` · `forecast-operational-metrics` · `frontend-ui-engineering` · `gcp-bigquery` · `gcp-cloud-run` · `gcp-gke` · `gcp-operational-excellence` · `gcp-reliability` · `gcp-security` · `gha-security-review` · `git-commit` · `git-flow-branch-creator` · `github-actions-efficiency` · `github-issues` · `github-release` · `gitlab-glab` · `golang-patterns` · `go-style-guide` · `gstack-review` · `health` · `iac-patterns` · `incident-response` · `investigate` · `kubernetes-patterns` · `land-and-deploy` · `linux-kernel-skill` · `mempalace` · `microservices-architect` · `mongodb-connection` · `mongodb-query-optimizer` · `mongodb-schema-design` · `monitoring-expert` · `multi-tenancy` · `network-skill` · `nodejs` · `nuxt` · `nuxt-vitest` · `nuxt-vue` · `oauth` · `observability` · `openspec-apply-change` · `openspec-archive-change` · `openspec-explore` · `openspec-propose` · `pdm-expert` · `performance-engineer` · `plan-capacity` · `playwright-explore-website` · `playwright-generate-test` · `postgresql-optimization` · `presentation` · `product-owner` · `prompt-engineer` · `pr-review` · `python` · `python-patterns` · `refactoring-specialist` · `replay-ux-research` · `rng-skill` · `rust` · `security-review` · `sentry-code-review` · `sentry-security-review` · `ship` · `skill-development` · `solid` · `sql-optimization` · `sre` · `sred-project-organizer` · `sred-work-summary` · `statistical-analysis` · `supabase-patterns` · `supabase-postgres-best-practices` · `tdd-workflow` · `terraform-skill` · `time-series` · `triage-frontend-issues` · `ts-library` · `typescript` · `verification-loop` · `vue-best-practices` · `vue-debug-guides` · `vue-development` · `vue-jsx-best-practices` · `vue-options-api-best-practices` · `vue-pinia-best-practices` · `vue-router-best-practices` · `vue-testing-best-practices` · `vueuse` · `webapp-testing` · `web-design-guidelines` · `write-incident-runbook`

**Sub-skill families** (7 directories whose `SKILL.md` files sit one level down — load a specific sub-skill):

- `audit-context-building` — line-by-line analysis, deep architectural context
- `dd-software-delivery` — `triage-flaky-test`, `unblock-pr`
- `differential-review` — security-focused diff analysis, blast radius
- `golang` — 9 sub-skills: `golang-code-style`, `golang-concurrency`, `golang-error-handling`, `golang-linter`, `golang-naming`, `golang-project-layout`, `golang-safety`, `golang-structs-interfaces`, `golang-testing` (the broad `golang` keyword in `skill-rules.json` maps to the loadable `/golang-patterns`)
- `mutation-testing` — mutation campaign configuration, coverage quality
- `property-based-testing` — invariant testing, generators, shrinking
- `static-analysis` — `codeql`, `semgrep`, `sarif-parsing`

---

## Adding a New Skill

1. Create `ai_local/skills/<skill-name>/SKILL.md`
2. Add keyword mapping to `.claude/skill-rules.json`:
   ```json
   {"pattern": "keyword1|keyword2|keyword3", "skill": "skill-name"}
   ```
3. Optionally add `refs/`, `scripts/`, `templates/` subdirectories
4. The skill is immediately available via `/skill-name` and auto-activation

---

## OpenCode Skills

Skills work in OpenCode with one key difference: **there is no hook-based auto-activation**.
The `skill-activation.sh` hook (which scans every prompt for keywords) does not have a plugin
equivalent because OpenCode has no `UserPromptSubmit` event.

### What works the same

- Skills live in `~/.claude/skills/` — symlinked from `ai_local/skills/`
- Manual load via `/skill-name` — identical syntax
- OpenCode's built-in `skill` tool loads `SKILL.md` into context on demand

### Auto-activation workaround

The keyword-to-skill mapping from `.claude/skill-rules.json` is embedded as a lookup table in
`~/.config/opencode/AGENTS.md`. The model reads this at session start and applies it when
the user's request contains matching keywords.

**You (the model) must activate skills yourself.** When a user prompt contains any of the
keywords below, load the corresponding skill before responding:

| Keywords | Skill |
|---|---|
| `pandas`, `dataframe`, `csv`, `EDA`, `groupby` | `/data-analyst` |
| `visuali`, `plot`, `chart`, `matplotlib`, `seaborn`, `plotly` | `/data-visualisation` |
| `time series`, `ARIMA`, `rolling window`, `forecast` | `/time-series` |
| `hypothesis test`, `p-value`, `t-test`, `regression`, `scipy` | `/statistical-analysis` |
| `dbt`, `airflow`, `spark`, `snowflake`, `pipeline`, `ETL` | `/data-engineer` |
| `pytest`, `fixture`, `parametrize`, `mock`, `TDD` | `/python` |
| `dataclass`, `pydantic`, `type hint`, `mypy`, `protocol` | `/python` |
| `typescript`, `interface`, `generic`, `union type` | `/typescript` |
| `vitest`, `jest`, `describe`, `spy`, `stub` | `/typescript` |
| `postgres`, `SQL`, `query`, `index`, `migration`, `schema` | `/database` |
| `REST`, `GraphQL`, `OpenAPI`, `endpoint`, `HTTP` | `/api-designer` |
| `OTel`, `span`, `trace`, `metric`, `observability` | `/observability` |
| `SRE`, `deployment`, `rollback`, `incident`, `canary` | `/sre` |
| `security`, `secret`, `injection`, `OWASP`, `auth`, `CVE` | `/security-review` |
| `RAG`, `LLM`, `prompt`, `embeddings`, `vector store`, `MCP` | `/ai-developer` |
| `mempalace`, `palace`, `cross-session`, `wing` | `/mempalace` |

The full keyword table is in `~/.config/opencode/AGENTS.md` under "Automatic skill activation".

### How to add a new skill (OpenCode)

1. Create `ai_local/skills/<skill-name>/SKILL.md`
2. Add the keyword row to the auto-activation table in `~/.config/opencode/AGENTS.md`
3. The skill is immediately available via `/skill-name`
4. No `skill-rules.json` update needed for OpenCode (that file is Claude Code only)
