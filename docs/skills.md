# Skills

**Purpose**: Domain-knowledge modules loaded on demand. Each skill is a directory containing a `SKILL.md` orientation doc plus (optionally) `refs/`, `scripts/`, and `templates/` subdirectories with deeper reference material, runnable checks, and starter files.

Skills are a **supported first-class concept in both Claude Code and OpenCode**. This used to not be the case — early OpenCode releases had no skill system and the bundle shipped workarounds. As of OpenCode v1.0.110+, skills are native on both tools, the discovery paths overlap, and the same skill directory installs once and is visible to both.

The bundle ships ~40 skills covering languages (Python, TypeScript, Rust, Go, Node), platforms (Docker, Kubernetes, Terraform, Postgres), disciplines (SRE, security, chaos engineering, data analysis), and workflows (TDD, OpenSpec, PR review, documentation).

---

## How the two tools discover skills

Both tools walk a small set of directories at session start and treat each subdirectory containing a `SKILL.md` as one loadable skill. The bundle's installer (`install.sh`) drops symlinks into the tool-neutral path `~/.agents/skills/<name>` and, for the Claude Code profile, additionally into `~/.claude/skills/<name>`. Because OpenCode reads `~/.agents/skills/` natively (see below), no separate OpenCode symlink is needed.

**OpenCode discovery paths** (first match wins, 6 locations):

1. `./.opencode/skills/` — project-local, OpenCode native
2. `~/.config/opencode/skills/` — user-level, OpenCode native
3. `./.claude/skills/` — project-local, Claude Code compat mode
4. `~/.claude/skills/` — user-level, Claude Code compat mode
5. `./.agents/skills/` — project-local, tool-neutral convention
6. `~/.agents/skills/` — user-level, tool-neutral convention

The tool-neutral paths (5-6) are what the bundle targets by default. They let you install a skill once and have every cooperating tool pick it up, without duplicating the filesystem tree.

**Claude Code discovery paths** (smaller set):

1. `~/.claude/skills/` — user-level, native
2. `./.claude/skills/` — project-local, native

Claude Code does not (yet) read `~/.agents/skills/`. The bundle's installer handles that by dropping a second symlink at `~/.claude/skills/<name>` that points into the repo — the same real files as the `~/.agents/skills/<name>` symlink, so both tools see the same content. Two symlinks, one source of truth.

---

## The subagent caveat

By default, OpenCode's built-in `skill` tool is **disabled for subagents**. A subagent (one spawned by a top-level agent via the `task` tool, for example) cannot invoke `skill` at all — the tool simply is not in its toolset.

This is a deliberate OpenCode safety default, and it is the wrong default for this bundle's agents. The bundle ships agents that actively rely on skills for role-specific discipline — `@coder-typescript` needs the `/typescript` skill, `@coder-python` needs `/python`, `@reviewer` needs `/pr-review`, and so on. Without `skill` in their toolset, those agents silently lose half their context.

The bundle's fix: every OpenCode agent under `agents/opencode/` has this in its frontmatter:

```yaml
tools:
  skill: true
```

That single line re-enables the `skill` tool for the agent regardless of whether it is running as a top-level agent or a subagent. The Claude Code agents under `agents/claude/` do not need the equivalent, because Claude Code's skill system has no subagent gating.

If you write your own OpenCode agent and it has access to the skills, make sure your frontmatter carries the same line. Otherwise the agent will pretend the skill system does not exist.

---

## Frontmatter requirements

OpenCode enforces a fairly strict schema on each skill's `SKILL.md`:

- **`name`** — lowercase kebab-case, regex `^[a-z0-9]+(-[a-z0-9]+)*$`, 1-64 characters, MUST match the directory name exactly. A skill in `skills/postgres-patterns/SKILL.md` must have `name: postgres-patterns` in its frontmatter, and the filename must be uppercase `SKILL.md` not `skill.md`.
- **`description`** — 1-1024 characters of plain text. This is the only documentation the model sees before deciding whether to load the skill; make it a clear trigger-phrase summary like "Python testing patterns: pytest fixtures, parameterise, mocks, coverage", not a marketing blurb.
- **`SKILL.md`** — filename must be uppercase.

Claude Code's schema is a superset and accepts everything OpenCode accepts, so a skill that satisfies OpenCode's rules automatically works on Claude Code. Write every new skill to the OpenCode schema and you are safe on both.

A minimal valid frontmatter:

```yaml
---
name: postgres-patterns
description: >
  PostgreSQL query optimisation, schema design, indexing, migrations, and
  slow-query debugging. Activate when writing SQL, designing tables, or
  debugging query performance.
---
```

Validation is strict enough that a mismatched name or a missing field will cause OpenCode to skip the skill silently at startup. If a skill you installed is not showing up, check the frontmatter first.

---

## Permission configuration

OpenCode's permission system uses a `skill` key inside `opencode.json` to control skill invocation:

```json
{
  "permission": {
    "skill": {
      "*": "allow"
    }
  }
}
```

Wildcards are supported. Common patterns:

```json
{
  "permission": {
    "skill": {
      "*": "allow",
      "security-review": "ask",
      "compliance": "ask"
    }
  }
}
```

Per-skill overrides beat the wildcard. The bundle's recommended starter in [`templates/opencode.json.example`](../templates/opencode.json.example) uses `"*": "allow"`, which lets every skill in the bundle load without a prompt. Tighten it if you ship sensitive skills.

Claude Code has its own skill-rules file (`~/.claude/skill-rules.json`) that controls automatic activation rather than permission. Completely different mechanism, no overlap with OpenCode's permission block.

---

## Progressive disclosure: `refs/`, `scripts/`, `templates/`

Most skills in the bundle follow a progressive-disclosure pattern:

```
skills/
  <skill-name>/
    SKILL.md          # orientation — loaded into context on activation
    refs/             # deeper reference material, loaded on demand
      patterns.md
      testing.md
      architecture.md
    scripts/          # runnable shell or Python checks
      check.sh
    templates/        # starter files (pyproject.toml, openapi.yaml, etc.)
      pyproject.toml.example
```

`SKILL.md` is short (a few hundred lines at most) and carries the activation rules and a table of contents. The `refs/` files are longer deep-dives — a few thousand lines — that the model loads only when the task needs them.

**Claude Code** loads everything under the skill's directory as part of its native skill system. The model reads `SKILL.md`, sees a reference to `refs/patterns.md`, and can pull it directly using its file-read tools. No friction.

**OpenCode** is a little different. OpenCode's built-in `skill` tool loads `SKILL.md` but does **not** automatically surface the subtree. If the skill says "see `refs/patterns.md` for details", the model needs some way to read that file from inside its session.

That is exactly the gap the bundle's [`tools/skill_ref.ts`](../tools/skill_ref.ts) and [`tools/skill_list_refs.ts`](../tools/skill_list_refs.ts) custom tools fix. See [`tools.md`](tools.md) for the full documentation. Short version: once installed, the model can call:

```
skill_list_refs(skill="database")
  -> refs/postgresql-table-design.md
  -> refs/query-optimisation.md
  -> scripts/slow-query-check.sh
  -> templates/migration.sql

skill_ref(skill="database", path="refs/postgresql-table-design.md")
  -> <file contents>
```

and the progressive-disclosure model works on OpenCode just as well as on Claude Code. The custom tools use the same 6-path skill discovery order as OpenCode's built-in `skill` tool, so a skill installed for either tool is visible to both.

---

## Manual vs automatic activation

Both tools support manual and automatic activation, but the mechanics differ.

### Claude Code — automatic via `skill-activation.sh`

The bundle ships `hooks/skill-activation.sh`, a `UserPromptSubmit` hook that scans every user prompt against a keyword-to-skill map in `~/.claude/skill-rules.json`:

```json
[
  {"pattern": "postgres|SQL|query|index|migration|schema", "skill": "database"},
  {"pattern": "pytest|test.*fixture|parametrize|mock|coverage", "skill": "python"},
  {"pattern": "fastify|@fastify|Pino.*log|TypeBox", "skill": "nodejs"}
]
```

When a pattern matches, Claude receives an `additionalContext` hint telling it to load the matching skill before responding. Multiple skills can activate simultaneously.

### Claude Code — manual via `/skill-name`

```
/python                 # load Python patterns and TDD guidance
/database               # load Postgres and general SQL guidance
/api-designer           # load REST/OpenAPI design guidance
```

### OpenCode — manual via the `skill` tool

OpenCode's native `skill` tool is LLM-callable. The model invokes it explicitly when a task looks like a match:

```
skill(name="python")
  -> <SKILL.md contents>
```

The user can also type `/python` at the prompt, which OpenCode resolves to a skill invocation under the hood.

### OpenCode — automatic

OpenCode does not (yet) ship a built-in equivalent of Claude Code's `skill-activation.sh`. The closest equivalent is the [`opencode-agent-skills`](https://github.com/joshuadavidthomas/opencode-agent-skills) third-party plugin, which adds automatic loading based on prompt content. See [`ecosystem.md`](ecosystem.md) for the details.

If you want keyword-driven auto-activation on OpenCode today and you do not want an external plugin, the pragmatic workaround is to maintain a keyword-to-skill table directly in `AGENTS.md` and instruct the model to behave as if the listed skill were activated when a match is seen. Less deterministic than the Claude Code hook, but model-side-only and zero extra dependencies.

---

## Skill catalogue (abridged)

The bundle ships roughly 40 skills. A partial index:

### Languages

| Skill | Activate for |
|-------|--------------|
| `/python` | Any Python work — fundamentals, TDD (pytest), patterns, architecture |
| `/typescript` | Any TypeScript work — type system, TDD (Vitest), clean architecture |
| `/rust` | Any Rust work — 179 coding rules, RPI debugging, OTel instrumentation |
| `/golang-patterns` | Go code — idiomatic errors, interfaces, concurrency |
| `/nodejs` | Node.js services — Fastify, NestJS, platform essentials |

### Data

| Skill | Activate for |
|-------|--------------|
| `/data-analyst` | EDA workflow, statistical hygiene, effect size, BLUF reports |
| `/data-engineer` | dbt, Airflow, Spark, Snowflake, medallion architecture |
| `/statistical-analysis` | Hypothesis testing, bootstrap CI, multiple comparison |
| `/time-series` | STL decomposition, anomaly detection, forecasting |
| `/data-visualisation` | Accessible colormaps, Plotly/Seaborn/Matplotlib, Tufte |

### Platform / SRE

| Skill | Activate for |
|-------|--------------|
| `/sre` | SLI/SLO, error budgets, burn rate, capacity planning, on-call |
| `/observability` | OTel span naming, distributed tracing, sampling |
| `/ci-cd` | CI DAG, Docker multi-stage, Kubernetes, Helm, SAST/SCA |
| `/incident-response` | SEV1-4, blameless PIR, SLO burn rate response |
| `/chaos-engineer` | Hypothesis formation, blast radius, GameDay, FMEA |
| `/docker-expert` | Multi-stage builds, layer caching, security hardening |
| `/kubernetes-patterns` | Pod design, RBAC, network policies, GitOps, HPA |
| `/iac-patterns` | Module design, state management, drift detection |

### Databases and APIs

| Skill | Activate for |
|-------|--------------|
| `/database` | Multi-engine (PG, MySQL, SQLite) query and schema work |
| `/api-designer` | REST and GraphQL — OpenAPI, RFC 7807, pagination |
| `/microservices-architect` | Service boundaries, saga, CQRS, mesh, zero-trust |

### Security

| Skill | Activate for |
|-------|--------------|
| `/security-review` | OWASP Top 10, MCP Top 10, prompt injection, supply chain |
| `/compliance` | GDPR, ISO 27001, SOC 2, PII classification |
| `/oauth` | OAuth 2.1 / PKCE, JWT verification, token storage |

### AI and prompting

| Skill | Activate for |
|-------|--------------|
| `/ai-developer` | LLM features, RAG, MCP server development |
| `/prompt-engineer` | System prompts, few-shot, CoT, eval frameworks |

### Workflow and quality

| Skill | Activate for |
|-------|--------------|
| `/tdd-workflow` | Red-Green-Refactor, quality metrics |
| `/verification-loop` | Pre-MR full lint/type/test/security sweep |
| `/pr-review` | 4-lens review framework, blocking vs nit, approval |
| `/documentation` | Diataxis, ADR format, CHANGELOG |
| `/refactoring-specialist` | Smell detection, strangler fig, complexity metrics |
| `/performance-engineer` | Load testing, profiling, capacity, budgets |

### OpenSpec workflow (4 skills)

| Skill | Activate for |
|-------|--------------|
| `/openspec-propose` | Draft a new change with proposal, design, specs, tasks |
| `/openspec-apply-change` | Implement the next unchecked task in a change |
| `/openspec-explore` | Explore ideas and clarify requirements without coding |
| `/openspec-archive-change` | Archive a completed change |

### Specialist

| Skill | Activate for |
|-------|--------------|
| `/pdm-expert` | PDM package manager, Artifactory integration |
| `/multi-tenancy` | SaaS tenant isolation, RLS, query scoping |
| `/web-design-guidelines` | WCAG 2.1 accessibility, Web Interface Guidelines |
| `/skill-development` | Creating or improving skills |

---

## Authoring a new skill

1. Create `skills/<name>/SKILL.md` with frontmatter matching the OpenCode regex (`^[a-z0-9]+(-[a-z0-9]+)*$`) and a kebab-case directory name that matches.
2. Write the orientation section — activation triggers, when to use, when NOT to use.
3. Break deep reference material into files under `refs/`. Keep `SKILL.md` short.
4. (Optional) add runnable checks under `scripts/`.
5. (Optional) add starter files under `templates/`.
6. (Claude Code) add a keyword mapping to `.claude/skill-rules.json` if you want auto-activation.
7. The skill is immediately available via `/<name>` on Claude Code and via the native `skill` tool on OpenCode.

See `/skill-development` for the long version — skill anatomy, progressive disclosure, creation process, validation.

---

## See also

- [`tools.md`](tools.md) — the custom tools that bridge OpenCode's subtree gap (`skill_ref`, `skill_list_refs`).
- [`rules.md`](rules.md) — how `CLAUDE.md` and `AGENTS.md` interact with skills.
- [`compatibility.md`](compatibility.md) — full component matrix across Claude Code, OpenCode, and planned Copilot CLI.
- [`ecosystem.md`](ecosystem.md) — companion tools including `opencode-agent-skills` for auto-activation on OpenCode.
