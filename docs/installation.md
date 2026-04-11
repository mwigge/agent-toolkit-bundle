# Installation Guide

Long-form install guide for `agent-toolkit-bundle`. Complements the terse quick-start in `README.md`.

---

## Prerequisites

The installer is `bash(1)` with no external dependencies beyond what your agent runtime already needs:

- **Claude Code** — installed and initialised once (`~/.claude/` exists).
- **OpenCode** — installed and initialised once (`~/.config/opencode/` exists).
- **bash 4+** — macOS users may need `brew install bash` if the system bash is 3.2.
- **jq** — used by several hooks to parse tool input JSON. If `jq` is missing, hooks that need it log a warning and fail open.

The bundle does not depend on any specific language runtime for the agent definitions themselves — agents are plain markdown. Hooks are shell; plugins are TypeScript compiled by OpenCode at load time.

---

## Clone and inspect

```bash
git clone https://github.com/mwigge/agent-toolkit-bundle.git
cd agent-toolkit-bundle
```

Before running the installer, look at what you're about to install:

```bash
./install.sh --help        # see the full option list
find agents commands skills hooks plugins -type f | head -40
```

Every file in the bundle is plain text — read the ones you care about before installing them. `README.md` has a short description of every component category.

---

## Run the installer

The simplest invocation is:

```bash
./install.sh
```

This auto-detects which tools you have and installs the corresponding profile. With both Claude Code and OpenCode present it picks `both`; with only one present it picks that one. With neither present it prints an error and exits.

To force a specific profile:

```bash
./install.sh --profile claude       # Claude Code only
./install.sh --profile opencode     # OpenCode only
./install.sh --profile both         # both tools
```

To install only a subset of components:

```bash
./install.sh --profile claude --components agents,skills
./install.sh --profile opencode --components agents,commands
```

Valid components are: `agents`, `skills`, `hooks`, `plugins`, `commands`. Any token not in that list causes the installer to exit with `unknown component: <token>`.

### Non-interactive / CI

```bash
./install.sh --yes --profile both --force
```

`--yes` skips the confirmation prompt. `--force` overwrites existing files. Together they are safe for CI runners with empty `$HOME`.

### Custom install targets

If you need to install to a non-default location (testing, sandbox, chroot):

```bash
./install.sh --target-claude /tmp/fake-claude --target-opencode /tmp/fake-opencode
```

This does not change the source layout — only where files land.

### Templates

The system-prompt starter files (`templates/CLAUDE.md.example`, `templates/AGENTS.md.example`) are **user-owned**. They never land automatically. To drop them into the current directory as `CLAUDE.md` and/or `AGENTS.md`:

```bash
cd ~/my-project
/path/to/agent-toolkit-bundle/install.sh --templates
```

The installer refuses to overwrite an existing `CLAUDE.md` or `AGENTS.md` unless you pass `--force`.

---

## What the installer does NOT do

Understanding these non-behaviours avoids nasty surprises:

- **No settings file mutation.** The installer never touches `~/.claude/settings.json` or `~/.config/opencode/opencode.json`. You merge the hook registration block yourself. The README has the copy-pasteable JSON.
- **No placeholder substitution.** Files ship with literal `<your-org>`, `<your-project>`, `<your-git-host>` strings. Grep-and-replace them in your own copies after install. The installer is a file copier, not a templater.
- **No dependency install.** The installer does not run `brew install jq`, `npm install`, or anything else. Missing dependencies are your problem.
- **No registration of `agent-circuit-breaker`.** That is a separate repo with a separate installer. If you want the dual-context mode guard, clone that repo and run its installer.
- **No optional-integration code.** Optional integrations documented under `docs/` (for example, any BYO cross-session memory layer) ship as docs only — the installer does not copy code for them.

---

## Post-install configuration

### 1. Register hooks (Claude Code)

Merge the JSON from the `README.md` `Install — Claude Code only` section into `~/.claude/settings.json`. You do not need to register every hook — only the ones you actually want to run.

### 2. Restart OpenCode (OpenCode)

OpenCode loads plugins at startup. Quit and relaunch so the newly installed plugins take effect.

### 3. Substitute placeholders

Grep for `<your-` across your install directory and replace the strings with your real values:

```bash
grep -rn '<your-' ~/.claude/agents ~/.claude/commands ~/.claude/skills 2>/dev/null
grep -rn '<your-' ~/.config/opencode/agent ~/.config/opencode/command 2>/dev/null
```

See `README.md` for the placeholder table.

### 4. (Optional) Drop the templates into your project

```bash
cd ~/my-project
/path/to/agent-toolkit-bundle/install.sh --templates
# then edit CLAUDE.md / AGENTS.md to fill in project-specific rules
```

---

## Upgrading

Re-running `./install.sh` is safe and idempotent when no source files have changed. To pull in upstream updates:

```bash
cd /path/to/agent-toolkit-bundle
git pull
./install.sh --force
```

`--force` is required on re-runs because the installer treats existing files as user-modified by default. Back up any local edits first.

---

## Uninstall

```bash
# Claude Code
rm -rf ~/.claude/agents ~/.claude/commands ~/.claude/skills ~/.claude/hooks
# Then remove the hook registration block from ~/.claude/settings.json.

# OpenCode
rm -rf ~/.config/opencode/agent ~/.config/opencode/command ~/.config/opencode/plugin
# Then restart OpenCode.
```

If you installed templates into a project, delete `CLAUDE.md` / `AGENTS.md` in that project.

---

## Troubleshooting

- **Hook does not run.** Check `~/.claude/settings.json` for the registration block. Claude Code reloads settings on restart.
- **Plugin does not load.** Restart OpenCode. Check for TypeScript syntax errors in the plugin — OpenCode logs them at startup.
- **Formatter fails with "command not found".** The formatters are not bundled. Install them via your package manager (`brew install ruff`, `npm i -g prettier`, etc.).
- **`jq: command not found`.** Install `jq` (`brew install jq` or `sudo apt install jq`). Hooks that parse tool input need it.
- **Agent file opens blank.** Check the install target — Claude Code looks in `~/.claude/agents/`, OpenCode looks in `~/.config/opencode/agent/`. The installer copies to both when the profile is `both`.
