# Custom Tools (OpenCode)

**Purpose**: LLM-callable TypeScript functions that the agent can invoke as first-class tools, alongside `Bash`, `Edit`, `Read`, and friends. Tools are to OpenCode what MCP is to Claude Code — an extension point for capabilities the built-in toolset does not cover — except they live directly in your repo, run in-process, and need no separate server.

OpenCode discovers custom tools automatically from `~/.config/opencode/tools/` (and a per-project `./opencode/tools/`). Each `.ts` file that `export default`s a `tool(...)` value becomes a callable tool whose name is the file basename. There is no registration file, no manifest, no JSON glue — drop a file in the directory and restart OpenCode.

Reference: <https://opencode.ai/docs/custom-tools/>.

---

## Tools vs plugins vs hooks vs agents vs commands vs skills

The terms are easy to confuse. One-sentence definitions:

- **Custom tool** — a function the LLM can call during a turn. Inputs and outputs flow through the model. Synchronous, LLM-driven.
- **Plugin** (OpenCode) — a long-lived TypeScript module that hooks lifecycle events (`tool.execute.before`, `chat.message`, `session.start`). Not called by the LLM; runs around tool calls. See [`plugins.md`](plugins.md).
- **Hook** (Claude Code) — a shell script invoked once per lifecycle event. Same role as a plugin, different mechanism. See [`hooks.md`](hooks.md).
- **Agent** — a named personality / workflow the user switches into (`@reviewer`, `@coder-python`). Defined as markdown. See [`agents.md`](agents.md).
- **Command** — a slash command (`/commit`, `/pr`) the user types to run a scripted prompt. Defined as markdown. See [`commands.md`](commands.md).
- **Skill** — a domain-knowledge module loaded on demand (`/python`, `/oauth`). Defined as a directory with `SKILL.md`. See [`skills.md`](skills.md).

Custom tools are the only one of the six that the LLM calls directly. Everything else runs around the LLM, not inside its tool-call loop.

---

## Why the bundle ships custom tools

OpenCode's built-in `skill` tool (native skill support since v1.0.110+) loads a skill's `SKILL.md` but does **not** load files from the skill's `refs/`, `scripts/`, or `templates/` subdirectories. Many skills in this bundle use progressive disclosure — `SKILL.md` is a short orientation doc that points at deeper reference material in `refs/X.md`, runnable checks in `scripts/Y.sh`, and starter files in `templates/Z.yaml`. Without custom tools, OpenCode can read `SKILL.md` but not the subtree, and the progressive-disclosure model breaks on OpenCode.

The bundle fixes that gap with two custom tools:

| Tool | Purpose |
|------|---------|
| `skill_ref` | Read a specific file from an installed skill's subtree (e.g., `refs/postgresql-design.md`, `templates/pyproject.toml`). |
| `skill_list_refs` | Enumerate every non-`SKILL.md` file in an installed skill, so the model can discover what refs exist before deciding which one to load. |

Both tools use the same six-path skill discovery order as OpenCode's built-in `skill` tool, so a skill installed for one tool is visible to the other. A typical flow:

1. Native `skill` tool loads `database/SKILL.md`.
2. The model decides it needs the Postgres deep-dive.
3. The model calls `skill_list_refs(skill="database")` and sees `refs/postgresql-table-design.md`.
4. The model calls `skill_ref(skill="database", path="refs/postgresql-table-design.md")` and receives the file contents.

Neither tool has any side effects. They read files and return strings. No file writes, no shell execution, no network. That is an intentional line — the bundle's custom tools are pure readers. Anything that mutates state is a plugin or a slash command.

---

## Installed shipped tools

After `./install.sh --components tools --profile opencode`, the bundle's tools appear as symlinks under `~/.config/opencode/tools/`:

```
~/.config/opencode/tools/
├── skill_ref.ts          -> <repo>/tools/skill_ref.ts
└── skill_list_refs.ts    -> <repo>/tools/skill_list_refs.ts
```

`git pull` in the repo propagates any fix instantly — OpenCode re-reads the files on the next tool call.

### `skill_ref`

```
skill_ref(skill: string, path: string) -> string
```

Loads a specific file from an installed skill. The `path` is a relative subpath within the skill's directory (for example `refs/postgresql-table-design.md` or `templates/pyproject.toml`). The tool refuses absolute paths and any path containing `..`, and it caps file size at 2 MB to prevent the agent from pulling a huge binary into context.

Discovery order (first match wins):

1. `$CWD/.opencode/skills/<skill>/<path>`
2. `$HOME/.config/opencode/skills/<skill>/<path>`
3. `$CWD/.claude/skills/<skill>/<path>`
4. `$HOME/.claude/skills/<skill>/<path>`
5. `$CWD/.agents/skills/<skill>/<path>`
6. `$HOME/.agents/skills/<skill>/<path>`

This is the same order the native `skill` tool uses, so results are consistent between the two.

### `skill_list_refs`

```
skill_list_refs(skill: string) -> string
```

Enumerates every file inside an installed skill's directory that is **not** `SKILL.md`. Returns a newline-delimited list of relative paths, sorted. Walks the skill directory up to five levels deep and skips dotfiles and `node_modules`.

Use this when the model does not know the exact filename of a ref it needs — listing first, loading second.

---

## Adding your own custom tools

OpenCode's custom-tool contract is minimal: a TypeScript file that imports `@opencode-ai/plugin`, declares its arguments via `tool.schema`, and exports a default function. The bundle's two tools are short (70-90 lines each) and make reasonable starting points to copy from.

A stripped-down template:

```typescript
// ~/.config/opencode/tools/my_tool.ts
// SPDX-License-Identifier: Apache-2.0

import { tool } from "@opencode-ai/plugin";

export default tool({
  description:
    "One-paragraph description of what the tool does and when the model " +
    "should call it. This is the single most important field — it is the " +
    "only documentation the model sees before deciding whether to invoke.",
  args: {
    query: tool.schema
      .string()
      .describe("The user-supplied search string."),
    limit: tool.schema
      .number()
      .optional()
      .describe("Maximum number of results (default 10)."),
  },
  async execute(args, context) {
    // args is typed from the schema above.
    // context.directory is the session CWD.
    // Throw Error on any failure — the message surfaces back to the model.
    return `searched for ${args.query}`;
  },
});
```

Three rules of thumb:

1. **Write the description for the model, not the user.** The description is the model's only guide to when and how to call the tool. A vague description produces a tool the model ignores.
2. **Validate inputs at the top of `execute`.** OpenCode already type-checks against the schema, but anything the schema cannot express (path-traversal guards, length caps, regex-validated identifiers) is your responsibility. Throw `Error` on any violation.
3. **Fail closed, not open.** If the tool cannot answer the question, throw. Do not return a plausible-looking fallback string — the model will believe it.

---

## Security

Custom tools execute with the same privileges as OpenCode itself. That means a tool can read any file the agent process can read and can exec any command the agent process can exec. Treat tool authorship with the same rigour as plugin authorship:

- Never `execSync` a shell-interpolated string from tool input. Use `execFileSync` with argv arrays.
- Never concatenate tool input into a filesystem path without normalising and checking for `..`.
- Never return unfiltered environment variables to the model. Scrub tokens and credentials before the return.
- Cap any output that could be unbounded — large files, long lists, open-ended pagination. A 50 MB response dumped into the model's context is worse than a refusal.

The bundle's `skill_ref` and `skill_list_refs` follow all four rules. They are short for a reason.

---

## Why tools are OpenCode-only

Claude Code's extension surface for LLM-callable capabilities is MCP, not an in-process TypeScript tool loader. The bundle's `skill_ref` equivalent on the Claude Code side is… nothing, because Claude Code's native skill system already loads the subtree files via plain file reads from `~/.claude/skills/<skill>/`. The gap only exists for OpenCode. If Claude Code ever grows a custom-tool API, the bundle will grow Claude-side equivalents at that point — not before.

---

## See also

- [`skills.md`](skills.md) — how skills install, how OpenCode discovers them, why `skill_ref` exists.
- [`plugins.md`](plugins.md) — the other OpenCode extension point (lifecycle hooks, not LLM-callable).
- OpenCode custom tools reference: <https://opencode.ai/docs/custom-tools/>
- OpenCode plugin API: <https://opencode.ai/docs/plugins/>
