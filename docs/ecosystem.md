# Ecosystem — Companion Tools

A short, opinionated list of other projects that pair well with `agent-toolkit-bundle`. These are **not** dependencies — the bundle works fine on its own. Each entry is here because, in practice, users who installed the bundle ended up wanting what it offers.

Pick the ones you need. Skip the ones you don't.

---

## Siblings

### [`agent-circuit-breaker`](https://github.com/mwigge/agent-circuit-breaker)

Sibling repo by the same author. Ships a dual-context mode guard (a `PreToolUse` hook for Claude Code and a `tool.execute.before` plugin for OpenCode) that enforces hard separation between two work contexts — typically employer vs personal. When the breaker is "closed" on one context, every file edit, shell command, and git operation against the other context is rejected before it runs.

Pair with this bundle if you work in two contexts on the same machine and want blast-radius protection against cross-contamination (wrong SSH key, wrong access token, wrong remote). The bundle deliberately does **not** re-ship the mode guard — install the circuit breaker separately.

---

## Memory backends

### [`milla-jovovich/mempalace`](https://github.com/milla-jovovich/mempalace)

**The upstream `mempalace` project this bundle integrates with.** MIT-licensed, installable via `pip install mempalace`, ships its own Claude Code plugin via the marketplace system (`claude plugin install --scope user mempalace`) or a generic MCP wrapper (`claude mcp add mempalace -- python -m mempalace.mcp_server`). Every concept the bundle's `mempalace/` sub-package uses — wings, rooms, halls, drawers, the 19 MCP tools, the palace path at `~/.mempalace/palace/`, the `MEMPAL_DIR` auto-ingest environment variable — comes from this upstream project.

The bundle's `mempalace/` sub-package is an **integration layer**, not a server. It supplies OpenCode custom tools (`mempalace_ingest`, `mempalace_query`), an OpenCode plugin, the `/mempalace-mine` slash command, and a per-project `docs_local/openspec` scanning convention that sits on top of the upstream server. The actual memory system — ChromaDB-backed palace, knowledge graph, agent diary, AAAK compression — lives in upstream.

Recommended backend for the bundle's mempalace sub-package. Any MCP-compatible backend that implements the contract in [`../mempalace/docs/mcp-contract.md`](../mempalace/docs/mcp-contract.md) also works, but upstream is the path of least resistance. See [`install-mempalace.md`](install-mempalace.md) for the full wiring guide.

---

## Extra capability on top of OpenCode

### [`joshuadavidthomas/opencode-agent-skills`](https://github.com/joshuadavidthomas/opencode-agent-skills)

MIT-licensed OpenCode plugin that adds session-compaction resilience and a handful of extra skill-related tools: `use_skill`, `read_skill_file`, `run_skill_script`, `get_available_skills`. The headline feature is that it re-loads the skill system after OpenCode compacts the session context — without it, a long session that triggers a compact will lose access to any skill that was loaded via the built-in `skill` tool earlier in the turn.

Pairs well with this bundle if you run long sessions and routinely trigger compaction. It does not conflict with the bundle's own `skill_ref` / `skill_list_refs` tools — both can coexist, and each covers a slightly different gap. Install via its own repo's instructions; both projects drop symlinks into `~/.config/opencode/tools/` or `~/.config/opencode/plugin/` and neither overwrites the other.

---

## Claude Code plugins

### [`obra/superpowers`](https://github.com/obra/superpowers)

A Claude Code plugin for subagent spawning and structured context gathering. Adds a planning-mode workflow where the top-level agent spins up focused subagents, collects their findings, and synthesises an answer. Useful for research-heavy tasks where a single linear conversation starts to lose track of context.

Pairs with this bundle when you want the bundle's stack discipline (TDD, conventional commits, strict types) to apply inside each subagent too. Install `superpowers` as a Claude Code plugin; the bundle's `CLAUDE.md` rules apply globally regardless of which subagent is running.

---

## Research and search

### [`tavily-ai/skills`](https://github.com/tavily-ai/skills)

A web research skill for Claude Code, built on the Tavily search API. Adds a `/tavily` skill the model can invoke to fetch live web content, summarise articles, and produce cited answers. Works well alongside this bundle's `/ai-developer` and `/prompt-engineer` skills when the task is "find recent information on X, then use our house patterns to integrate it".

Requires a Tavily API key. Free tier is enough for occasional research; paid tier is needed for heavy use. Drop the skill into `~/.claude/skills/` and it coexists with every skill in this bundle — no conflicts.

---

## Selection criteria

The list is deliberately short. Projects land here only if all four conditions are true:

1. **Public**. No paywalled docs, no private registries, no closed betas.
2. **Licensed permissively**. MIT, Apache-2.0, BSD, or equivalent. Copyleft is fine for runtime dependencies but not for something you drop into `~/.claude/`.
3. **Actually used by the bundle's author**. Not a wishlist. Every entry here earned its spot by solving a real gap the bundle itself does not fill.
4. **Pairs cleanly**. No overlapping install paths, no conflicting frontmatter, no requirement that this bundle be removed first.

If a project you think should be on this list is not, open an issue. If a project on this list stops meeting the criteria, it will be removed without ceremony.

---

## See also

- [`README.md`](../README.md) — the bundle's own "Companion tools" section, which is a shorter pointer at the same content.
- [`compatibility.md`](compatibility.md) — which components work on which tools, and what the bundle deliberately does not ship.
- [`install-mempalace.md`](install-mempalace.md) — the detailed wiring guide for the upstream mempalace integration.
