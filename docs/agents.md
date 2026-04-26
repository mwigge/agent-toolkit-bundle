# Agents

**Purpose**: Role-specific sub-sessions with constrained tool sets and pre-loaded domain expertise. Each agent is a leaf node — no agent spawns another agent.

Invoke with `@agent-name` in Claude Code.

---

## The No-Subagent Rule

```
Correct:
  "Implementation complete. Hand off to @reviewer for code review."

Forbidden:
  [internally calls @reviewer via spawn()]  <-- violates Claude Code constraint
```

This is a hard architectural constraint. Agents output human-readable handoff messages. All dispatching is human-triggered.

---

## Implementation Agents

### @architect

**Invoke when**: Before writing code that crosses module boundaries, adds dependencies, or spans more than 2 files.

**Skills loaded**: `/python-architect`, `/typescript-architect`, `/postgres-patterns`, `/api-designer`

**Produces**: ADR, interface spec, module diagram, design decision record. Outputs a handoff message telling you which agent to invoke next.

**Does NOT**: Write implementation code. Creates the plan, not the code.

---

### @coder-python

**Invoke when**: Implementing Python features or fixing Python bugs. Requires a spec or story.

**Skills loaded**: `/python-developer`, `/python-patterns`, `/python-testing`, `/python-architect`

**Produces**: Production Python code + tests. Always uses strict TDD (Red-Green-Refactor).

**Key rules**: >= 95% coverage, ruff + black formatting, mypy strict, no `print()` in library code.

---

### @coder-typescript

**Invoke when**: Implementing TypeScript/JavaScript features or fixing bugs. Requires a spec or story.

**Skills loaded**: `/typescript-developer`, `/typescript-tdd`, `/typescript-architect`, `/typescript`

**Produces**: Production TypeScript code + Vitest tests. Always uses strict TDD.

**Key rules**: >= 80% coverage, ESLint 9 flat config, Prettier, tsc strict, no `any` without justification.

---

### @coder-sql

**Invoke when**: Writing migrations, schema changes, query optimisation, RLS policies, stored procedures.

**Skills loaded**: `/postgres-patterns`, `/python-architect` (DB section)

**Produces**: Parameterised SQL, migration files, RLS policies.

**Key rules**: Always parameterised SQL. Never string interpolation. Forward-only migrations.

---

### @coder-tdd

**Invoke when**: Red phase when test strategy is unclear, or when a bug needs a failing test before a fix.

**Skills loaded**: `/python-testing`, `/typescript-tdd`, `/python-developer`, `/typescript-developer`

**Produces**: Failing tests only (Red phase). No implementation.

**Handoff**: Outputs "Hand off to @coder-python (or @coder-typescript) for the Green phase."

---

## Quality Agents

### @tester

**Invoke when**: Full test strategy needed, coverage gaps, contract testing design.

**Skills loaded**: `/tdd-workflow`, `/python-testing`, `/typescript-tdd`

**Produces**: Test plan + failing tests (Red phase). Coverage analysis. Test architecture decisions.

---

### @reviewer

**Invoke when**: After implementation is complete, before MR creation.

**Skills loaded**: `/pr-review`, `/security-review`

**Produces**: Adversarial 4-lens code review:

| Lens | Checks |
|------|--------|
| Correctness | Logic errors, edge cases, contract violations |
| Security | OWASP Top 10, secrets, injection, auth gaps |
| Observability | OTel spans, structured logging, metric naming |
| Maintainability | Complexity, naming, duplication, test quality |

**Output format**: BLOCKING issues (must fix), nits (optional), and a verdict (APPROVED / REQUEST CHANGES).

---

## Platform Agents

### @sre

**Invoke when**: Deployments, CI/CD changes, runbooks, incident response.

**Skills loaded**: `/sre`, `/observability`, `/ci-cd`, `/incident-response`

**Produces**: Deploy checklist, SLO review, runbook, rollback plan.

---

### @security

**Invoke when**: Auth changes, dependency updates, security-sensitive code.

**Skills loaded**: `/security-review`, `/compliance`, `/oauth`

**Produces**: Security report (PASS/FAIL per category: secrets, auth, input validation, dependencies).

---

### @observability

**Invoke when**: New chaos actions, probes, or services needing tracing/metrics/logging.

**Skills loaded**: `/observability`

**Produces**: OTel span definitions, Prometheus alert rules, structured logging setup.

---

### @api

**Invoke when**: Designing or reviewing HTTP APIs.

**Skills loaded**: `/api-designer`

**Produces**: OpenAPI 3.1 spec section, endpoint design, error handling, pagination.

---

## Domain Agents

### @data-analyst

**Invoke when**: Experiment result analysis, resilience score calculation, statistical testing.

**Skills loaded**: `/data-analyst`, `/statistical-analysis`, `/data-visualisation`, `/time-series`

**Produces**: Analysis report (markdown + charts + stats JSON).

---

### @data-engineer

**Invoke when**: Pipeline design, dbt models, data quality setup.

**Skills loaded**: `/data-engineer`

**Produces**: Pipeline code, dbt models, Airflow DAGs.

---

### @product-owner

**Invoke when**: Story drafting, backlog prioritisation, OKR review.

**Skills loaded**: `/product-owner`

**Produces**: INVEST-compliant user stories, RICE scores, acceptance criteria (Given/When/Then).

---

### @ai-developer

**Invoke when**: LLM feature implementation, RAG pipelines, MCP server development, eval suites.

**Skills loaded**: `/ai-developer`

**Produces**: LLM integration code, prompt design, eval framework.

---

### @jira-story

**Invoke when**: Creating a Jira ticket for project CLS.

**Skills loaded**: `/product-owner`, Jira CLI integration

**Produces**: Two-step Jira creation (CLS project, epic CLS-23). Creates the story, then sets DoR/DoD/AC fields in a second step (checklist fields can't be set on CREATE).

---

## Typical Collaboration Flow

```
Feature development:

  @product-owner  -->  draft story
       | (user handoff)
  @jira-story     -->  create CLS ticket
       | (user handoff)
  @architect      -->  design + ADR
       | (user handoff)
  @coder-tdd      -->  failing tests (Red)
       | (user handoff)
  @coder-python   -->  implementation (Green + Refactor)
       | (user handoff)
  @observability  -->  OTel spans + alerts
       | (user handoff)
  @reviewer       -->  adversarial review
       | (user handoff)
  @security       -->  security sign-off
       | (user handoff)
  @sre            -->  deploy safety check
       | (user handoff)
  /commit + /pr   -->  merge request created
```

Not every feature needs every agent. Small bug fixes might go directly to `@coder-python` -> `@reviewer` -> `/commit`.

---

## Agent File Location

Claude Code agent files live in `ai_local/.claude/agents/`.
OpenCode agent files live in `ai_local/opencode/agents/`.

---

## Codex Reference

Codex does not have a native `@agent-name` registry in this setup.

Instead, the Codex reference installation reuses the existing OpenCode agent files as
**role contracts** and source prompts:

- read the matching file from `ai_local/opencode/agents/`
- follow its scope, responsibilities, and output contract
- optionally delegate using Codex sub-agents when that helps, but do not assume file-based
  agent registration exists

See `ai_local/codex/AGENTS.md` and [codex.md](codex.md) for the Codex-specific behavior.

Agent definitions live in `.claude/agents/`. Each is a markdown file that defines the agent's role, skills, constraints, and output format. Claude Code reads these when you invoke `@agent-name`.

---

## OpenCode Agents

OpenCode fully supports custom agent definitions. Agent files live in
`~/.config/opencode/agents/` (global) or `<project>/.opencode/agents/` (project-scoped).

### All 17 agents are ported

Agent files live in `ai_local/opencode/agents/` — symlinked to `~/.config/opencode/agents/`.
Edit files in `ai_local/opencode/agents/`; the symlink means the change is live immediately.

Agent files: `ai_local/opencode/agents/<agent-name>.md` (canonical)
             `~/.config/opencode/agents/<agent-name>.md` (symlink)

Format uses frontmatter to declare `description`, `mode`, and `permission`:

```markdown
---
description: One-line description shown in agent picker.
mode: subagent
permission:
  bash: deny
---

# @my-agent — Role Description

System prompt content...
```

### Key difference from Claude Code: subagent spawning

**Claude Code**: Agents are leaf nodes. All dispatch is human-triggered. The model outputs
a handoff message and waits for the user to invoke the next agent.

**OpenCode**: The model CAN spawn subagents autonomously using the `task` tool. `mode: subagent`
agents are spawned directly by the orchestrator without human intervention.

The no-subagent rule in `agents.md` is **Claude Code-specific**. In OpenCode, the correct
architectural decision (autonomous vs human-gated dispatch) depends on the task:

- **Simple, well-scoped tasks**: autonomous spawn is appropriate (e.g. `@coder-python` after `@architect` completes a design)
- **Ambiguous tasks requiring human review**: output a handoff message as in Claude Code
- **High-risk tasks** (deploys, database changes): always human-gated regardless of platform

### How to add a new agent (OpenCode)

1. Create `ai_local/opencode/agents/my-agent.md` (canonical location)
2. Add frontmatter: `description`, `mode: subagent`, `model: <provider/model>`, and any `permission` overrides
3. Write the system prompt below the frontmatter
4. The agent is immediately available via `@my-agent` (symlink makes it live instantly)
5. Update the Agents Reference table in `ai_local/opencode/AGENTS.md`

### permission field

```yaml
permission:
  bash: deny        # agent cannot run shell commands (read-only agents: @architect)
  bash: allow       # agent can run shell commands (default for most agents)
  write: deny       # agent cannot write files
```

The `permission` block in OpenCode agent files replaces the `allowedTools` and `disallowedTools`
arrays in Claude Code `.claude/agents/*.md` files.
