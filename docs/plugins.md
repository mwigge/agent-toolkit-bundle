# Plugins (OpenCode)

Plugins are TypeScript modules that OpenCode loads at startup from `~/.config/opencode/plugin/`. They implement the OpenCode plugin lifecycle (tool hooks, session events) and are the OpenCode-side analogue of Claude Code's shell hooks. OpenCode auto-loads every `.ts` file in the plugin directory — there is no `settings.json` entry to add.

Reference: <https://opencode.ai/docs/plugins/>.

---

## Plugins vs custom tools vs hooks — don't confuse them

These three words get used interchangeably in agent documentation across different projects, and they mean different things. For this bundle:

- **Plugin** (OpenCode) — a long-lived TypeScript module that registers per-event callbacks (`tool.execute.before`, `tool.execute.after`, `session.start`, `session.end`, `chat.message`). Not called by the LLM. Runs **around** tool calls, intercepting inputs and decorating outputs. Discovered from `~/.config/opencode/plugin/`.
- **Custom tool** (OpenCode) — an LLM-callable TypeScript function that the agent invokes as a first-class tool, the same way it invokes `Bash` or `Edit`. Called **by** the LLM. Discovered from `~/.config/opencode/tools/`. See [`tools.md`](tools.md).
- **Hook** (Claude Code) — a short-lived shell script invoked once per lifecycle event. Same role as a plugin (runs around tool calls, not by the LLM), different mechanism. Discovered via `~/.claude/settings.json` entries. See [`hooks.md`](hooks.md).

**When to use which:**

| If you want to... | Use |
|-------------------|-----|
| ...block or decorate a tool call before / after it runs (OpenCode) | plugin |
| ...block or decorate a tool call before / after it runs (Claude Code) | hook |
| ...expose a new capability the model can call by name (OpenCode) | custom tool |
| ...run a fast shell check during commit / write / save (Claude Code) | hook |
| ...react to session start or session end (OpenCode) | plugin |
| ...react to session start (Claude Code) | hook (`SessionStart` event) |
| ...let the model load a skill ref file by name (OpenCode) | custom tool |

If the model should **call** your code — it is a custom tool. If your code should **observe or intercept** the model's calls — it is a plugin (OpenCode) or a hook (Claude Code).

Plugins and custom tools are independent: you can have both in the same OpenCode install, and they do not compete for the same directory or lifecycle slot. A plugin can even dispatch to a custom tool internally, though the simpler pattern is usually to keep the two separate.

---

## Shipped plugins

| Plugin | Lifecycle | Purpose |
|--------|-----------|---------|
| `format-on-save.ts` | `tool.execute.after` (Edit / Write) | Runs language-appropriate formatters after a write |
| `inline-quality.ts` | `tool.execute.after` (Edit / Write) | Immediate lint / type-check feedback on changed files |
| `no-ai-attribution.ts` | `tool.execute.before` (Bash) | Blocks commits that contain AI attribution strings |
| `observe.ts` | session events | Emits structured OTel-style events for tool calls and session lifecycle |
| `quality-gate.ts` | `session.end` | Runs the full test / lint / type gate at session end |
| `security-guard.ts` | `tool.execute.before` (all) | Rejects tool calls that would exfiltrate secrets or touch forbidden paths |
| `session-init.ts` | `session.start` | Prints a short context summary and sets up per-session state |

All plugins live under `plugins/` at the repo root. The installer symlinks them into `~/.config/opencode/plugin/`.

---

## Lifecycle

OpenCode plugins export a default function that receives a runtime handle with registration methods. A typical plugin looks like this:

```typescript
import type { Plugin } from "@opencode-ai/plugin";

const plugin: Plugin = async ({ tool, session }) => {
  tool.execute.before("Bash", async (input) => {
    // inspect input, throw Error to block
  });

  tool.execute.after("Edit", async (input, output) => {
    // post-process output, run formatters, etc.
  });

  session.start(async (ctx) => {
    // set up per-session state
  });

  session.end(async (ctx) => {
    // tear down, run final gates
  });
};

export default plugin;
```

The plugin must be valid TypeScript against the `@opencode-ai/plugin` type definitions shipped with OpenCode. The `plugins/tsconfig.json` in this repo is configured to type-check every plugin against those types during development.

---

## Install

The bundled installer creates symlinks for you:

```bash
./install.sh --profile opencode
```

Restart OpenCode so the plugins load. There is nothing to edit in `opencode.json` — plugin discovery is directory-based.

---

## Authoring a new plugin

1. Copy the shape of an existing plugin that hooks the same lifecycle event.
2. Keep the plugin focused — one concern per file.
3. Throw `Error` from a `tool.execute.before` handler to reject the call; OpenCode surfaces the error back to the model.
4. Use structured logging via `console.error` (OpenCode routes stderr into its own log stream). Do not log to `console.log` in plugin code.
5. Add the new plugin to the table at the top of this file and to `README.md`.

If the capability you want to add is something the model should **call by name** — a search tool, a classifier, a database query — write a custom tool instead. See [`tools.md`](tools.md) for the custom-tool contract and the two shipped examples.

---

## Plugin vs hook semantics — one more time, clearly

Plugins and Claude Code hooks share a role but not a shape. A plugin is a long-lived TypeScript module with per-event callbacks; a hook is a short-lived shell script invoked once per event. Some patterns translate cleanly (format-on-save, security-guard, no-AI-attribution); others do not (Claude Code skill activation has no direct OpenCode analogue because OpenCode's skill system is a native tool rather than a hook-driven side effect).

Neither mechanism is a strict superset of the other. When a feature translates, the bundle ships it on both sides as independent implementations. When a feature does not translate, the bundle leaves the other side alone rather than forcing an awkward port. See [`compatibility.md`](compatibility.md) for the component matrix and the one-sided-content list.

---

## Security

The same rules that apply to shell hooks apply to plugins:

- Never log secrets. Never echo environment variables that contain tokens.
- Never exec arbitrary strings from tool input — pass through a shell-escape helper or refuse the call.
- Fail closed on any unexpected input shape.
- Treat the plugin runtime as trusted; treat tool input as hostile.

The same rules also apply to custom tools, doubly so, because custom tool inputs come directly from the model and are the single highest-trust point in the OpenCode execution model.

---

## See also

- [`tools.md`](tools.md) — OpenCode custom tools (LLM-callable, not lifecycle hooks).
- [`hooks.md`](hooks.md) — Claude Code shell hooks (the other side of the plugin/hook pair).
- [`compatibility.md`](compatibility.md) — component matrix, one-sided-content list.
- OpenCode plugin docs: <https://opencode.ai/docs/plugins/>
- OpenCode custom tools docs: <https://opencode.ai/docs/custom-tools/>
