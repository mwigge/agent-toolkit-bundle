# Plugins (OpenCode)

Plugins are TypeScript modules that OpenCode loads at startup from `~/.config/opencode/plugin/`. They implement the OpenCode plugin lifecycle (tool hooks, session events) and are the OpenCode-side analogue of Claude Code's shell hooks. OpenCode auto-loads every `.ts` file in the plugin directory — there is no `settings.json` entry to add.

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

All plugins live under `plugins/` at the repo root. The install target is `~/.config/opencode/plugin/`.

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

The selective installer copies the plugin files for you:

```bash
./install.sh --profile opencode
```

Or manually:

```bash
mkdir -p ~/.config/opencode/plugin
install -m 0644 plugins/*.ts ~/.config/opencode/plugin/
```

Restart OpenCode so the plugins load. There is nothing to edit in `opencode.json` — plugin discovery is directory-based.

---

## Authoring a new plugin

1. Copy the shape of an existing plugin that hooks the same lifecycle event.
2. Keep the plugin focused — one concern per file.
3. Throw `Error` from a `tool.execute.before` handler to reject the call; OpenCode surfaces the error back to the model.
4. Use structured logging via `console.error` (OpenCode routes stderr into its own log stream). Do not log to `console.log` in plugin code.
5. Add the new plugin to the table at the top of this file and to `README.md`.

---

## Plugin vs hook semantics

Plugins and Claude Code hooks are not 1:1 equivalents. A plugin is a long-lived TypeScript module with per-event callbacks; a hook is a short-lived shell script invoked once per event. Some patterns translate cleanly (format-on-save, security-guard); others do not (Claude Code skill activation has no OpenCode analogue because OpenCode does not ship a skill system).

See `docs/compatibility.md` for the full compatibility matrix.

---

## Security

The same rules that apply to shell hooks apply to plugins:

- Never log secrets. Never echo environment variables that contain tokens.
- Never exec arbitrary strings from tool input — pass through a shell-escape helper or refuse the call.
- Fail closed on any unexpected input shape.
- Treat the plugin runtime as trusted; treat tool input as hostile.
