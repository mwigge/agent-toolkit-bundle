---
name: mempalace
description: Populate, query, and troubleshoot MemPalace cross-session memory, OpenSpec artifacts, and agent diary entries.
---

# Skill: MemPalace

**Version**: 1.0.0 | **Updated**: 2026-04-09

Apply this skill when working with the MemPalace memory system: populating the palace with
OpenSpec artifacts, querying cross-session context, writing agent diary entries, or diagnosing
why a session lacks historical context.

Reference: `ai_local/mempalace_addition.md` for full architecture, design decisions, and installation.

---

## When to Activate

- Starting a session and the context feels thin — "what did we decide about X?"
- After completing a design or review (agent diary write)
- Running `/mine` to populate or refresh the palace
- Asking about past decisions across OpenSpec changes
- Wiring MemPalace into a new project

---

## Palace Structure

```
WING  (domain area)
  +-- ROOM  (OpenSpec change name or topic)
        +-- HALL  (memory type)
              |  hall_facts        decisions made, locked-in choices
              |  hall_events       sessions, milestones
              |  hall_discoveries  breakthroughs, insights
              |  hall_preferences  approaches preferred
              +-- DRAWER  (verbatim text chunk, stored in ChromaDB)
```

**The 5 wings in this setup:**

| Wing | Contains |
|------|---------|
| `wing_cls_architecture` | MCP, SSO, auth, multi-tenancy, org-role, Apigee changes |
| `wing_cls_platform` | Early-adopter, feedback loop, admin, tester-first, Slack, SLO changes |
| `wing_cls_resilience` | Resilience maturity, score methodology, ontology, experiments, gamification |
| `wing_cls_infra` | Postgres refactor, pgbouncer, observability infra, pre-production hardening |
| `wing_ai_dev` | Session diary, hook evolution, skill/agent meta-work |
| `wing_architect_diary` | @architect diary entries (auto-created by agent) |
| `wing_reviewer_diary` | @reviewer diary entries (auto-created by agent) |

**Room naming**: always the exact OpenSpec change name (e.g. `mcp-agent-integration`).

---

## The 4-Layer Memory Stack

| Layer | Size | When loaded | Source |
|-------|------|------------|--------|
| L0 | ~80 tokens | Always, at wake-up | `~/.mempalace/identity.txt` |
| L1 | ~500-800 tokens | Always, at wake-up | Top-scored drawers for the detected wing |
| L2 | ~200-500 tokens | On demand | Wing/room-filtered query via `mempalace_list_rooms` + `mempalace_search` |
| L3 | Unlimited | On demand | Full semantic search via `mempalace_search` |

L0+L1 are injected automatically at SessionStart by `mempalace-wake-up.sh`.
L2 and L3 are queried by calling MCP tools during a session.

---

## MCP Tools Reference

The MemPalace MCP server exposes 19 tools. Key ones for daily use:

**Reading memory:**
```
mempalace_status()                          -- palace overview, wing list, identity
mempalace_list_wings()                      -- all wings
mempalace_list_rooms(wing="wing_cls_arch")  -- rooms in a wing
mempalace_search(
  query="auth token decision",
  wing="wing_cls_architecture",             -- optional filter
  room="sso-auth-foundation",              -- optional filter
  limit=5                                  -- default 5
)
mempalace_traverse(start_room="mcp-agent-integration", max_hops=2)
mempalace_find_tunnels()                    -- cross-wing room connections
```

**Writing memory (Pattern B -- AI-driven):**
```
mempalace_add_drawer(
  wing="wing_cls_architecture",
  room="mcp-agent-integration",
  content="<verbatim text>",
  source_file="/path/to/source",
  added_by="session"
)
mempalace_diary_write(
  agent_name="architect",                   -- or "reviewer"
  entry="<1-3 sentence structured entry>",
  topic="mcp-agent-integration"
)
```

**Knowledge graph:**
```
mempalace_kg_add(subject="CLS-257", predicate="status", object="complete",
                 valid_from="2026-03-26")
mempalace_kg_invalidate(subject="CLS-257", predicate="status", object="in-progress",
                        ended="2026-03-26")
mempalace_kg_query(entity="CLS-257")
mempalace_kg_timeline(entity="CLS-257")
```

---

## Wing Detection

When calling MCP tools manually, map the change name to the correct wing:

```
Change name contains...         -> Wing
-----------------------------------------------
mcp, agent, sso, auth,
multitenancy, org-role, idp,
apigee, compliance              -> wing_cls_architecture

early-adopter, onboarding,
feedback, admin-role,
tester-first, demo, learning,
gamification, slack, slo, dora  -> wing_cls_platform

resilience, maturity, score,
complexity, ontology, scenario,
experiment, library,
steadystate, recommend          -> wing_cls_resilience

postgres, pgbouncer,
observability, pre-production,
hardening, compute, metric,
typed, session-metric,
quality-lake, run-probe,
run-experiment, guardrail       -> wing_cls_infra

memory.md, CLAUDE.md, hooks,
skills, agents, setup           -> wing_ai_dev
```

---

## Mining Sources

Two patterns are used (see `mempalace_addition.md` for full detail):

**Pattern A — File mining (CLI, deterministic):**
Used for OpenSpec artifacts, memory.md, ADRs. Runs automatically at PreCompact via
`mempalace-ingest.sh`, or manually via `/mine`.

**Pattern B — AI-driven mining (MCP tools):**
Used for conversation content and agent diary entries. The AI calls MCP tools directly.

**What gets mined automatically (PreCompact):**
- `openspec/changes/*/proposal.md` — always
- `openspec/changes/*/design.md` — always
- `openspec/changes/*/delivery.md` — always (umbrella support)
- `openspec/changes/*/tasks.md` — only if < 150 lines
- `docs_local/memory.md` — always, into wing_ai_dev/sessions
- `docs_local/adr/*.md` — always, into wing_cls_architecture/decisions

**What is skipped automatically:**
- `openspec/changes/archive/*` — archived changes
- `openspec/specs/*` — mine via `/mine specs` when needed

---

## Agent Diary Instructions

### @architect

After completing a design, ADR, or interface spec:

```python
mempalace_diary_write(
    agent_name="architect",
    entry="Designed <what>. Key trade-off: <option A vs B>. Chose <A> because <reason>.",
    topic="<change-name or domain>"
)
```

Keep entries to 1-3 sentences. Focus on the trade-off and the reason, not the mechanics.

### @reviewer

After completing any review (regardless of verdict):

```python
mempalace_diary_write(
    agent_name="reviewer",
    entry="Reviewed <what>. Verdict: <APPROVED / REQUEST CHANGES>. "
          "<BLOCKING issue if any>. Pattern: <recurring observation>.",
    topic="<file area or change-name>"
)
```

---

## Common Queries

**"What did we decide about X?"**
```
mempalace_search(query="decision about X", wing="wing_cls_architecture")
```

**"What is the current state of change Y?"**
```
mempalace_search(query="Y status tasks done", room="Y")
mempalace_kg_query(entity="CLS-NNN")  -- if CLS ticket number known
```

**"What other changes connect to this one?"**
```
mempalace_traverse(start_room="mcp-agent-integration", max_hops=2)
mempalace_find_tunnels()
```

**"What has the architect decided recently?"**
```
mempalace_diary_read(agent_name="architect", last_n=10)
```

---

## Populating the Palace: /mine Command

```
/mine openspec    -- mine all openspec/changes/ proposal+design+delivery
/mine memory      -- mine docs_local/memory.md into wing_ai_dev/sessions
/mine adr         -- mine docs_local/adr/ into wing_cls_architecture/decisions
/mine convo       -- mine recent transcript backups as conversations
/mine all         -- run all of the above
```

Run `/mine all` after the first installation to bootstrap the palace from existing artifacts.
Run `/mine openspec` after completing or updating an OpenSpec change.

---

## Installation Checklist

- [ ] MemPalace installed: `pip install git+https://github.com/milla-jovovich/mempalace.git`
- [ ] Palace initialized: `mempalace init ~/.mempalace`
- [ ] `~/.mempalace/identity.txt` edited with your context
- [ ] `~/.mempalace/wing_config.json` replaced with template from `skills/mempalace/templates/`
- [ ] MCP server registered in project `.claude/settings.local.json`
- [ ] `~/.claude/settings.json` updated with mempalace-wake-up.sh + mempalace-ingest.sh hooks
- [ ] Palace bootstrapped: `/mine all`
- [ ] Verify: `mempalace status`

See `ai_local/mempalace_addition.md` for full installation steps.

---

## Anti-Patterns

| Anti-pattern | Why wrong | Fix |
|--------------|-----------|-----|
| Summarizing content before storing | Loses the "why" — semantic search needs original reasoning | Store verbatim with `mempalace_add_drawer` |
| Using AAAK compression for storage | Regresses recall from 96.6% to 84.2% | Keep AAAK disabled; verbatim only |
| Mining archive/ changes | Creates noise from superseded decisions | ingest.sh skips archive/ by design |
| Calling `mempalace_add_drawer` without a room | Falls into "general" room, unsearchable by area | Always specify wing + room |
| Relying only on wake-up L1 | L1 is top-scored drawers, not exhaustive | Use mempalace_search for specific queries |
| Large conversation dumps as single drawer | ChromaDB embeds the whole chunk, degrades similarity | Let the CLI mine with exchange-pair chunking |
