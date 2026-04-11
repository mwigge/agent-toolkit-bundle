# GitHub Copilot CLI

**Status**: Planned — not yet supported by the installer.

GitHub Copilot CLI is GitHub's official terminal-based coding agent. It ships as a public preview and, per the official GitHub docs, supports "agent skills" as a first-class extension point. The bundle is designed to grow a `--profile copilot` once the exact on-disk discovery paths are pinned down — the same skills, agents, and commands the Claude Code / OpenCode profiles install would become available under the Copilot profile, via symlinks into whatever location Copilot CLI reads.

If you are reading this because you want Copilot CLI support today, skip to [Manual workaround](#manual-workaround) at the bottom.

---

## What is confirmed

- **Copilot CLI exists and is in public preview.** Install via Homebrew on macOS and Linux:
  ```bash
  brew install copilot-cli@prerelease
  ```
  Other platforms: see the Copilot CLI install docs.
- **Copilot CLI officially supports agent skills.** The feature is listed in GitHub's official Copilot CLI documentation under the "About Copilot CLI" page: <https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli>.
- **The SDK repo is public.** The Copilot Agent SDK lives at <https://github.com/github/copilot-sdk>. It is the authoritative reference for how agents, skills, and tools are discovered and loaded at runtime.

---

## What is not yet confirmed

The bundle needs three things to ship a working `--profile copilot`:

1. **The user-level skill discovery directory.** Claude Code reads `~/.claude/skills/`. OpenCode reads six paths including `~/.agents/skills/`. Copilot CLI's equivalent is not documented in a form the author of this file was able to confirm from a public, non-paywalled source. The SDK repo is in public preview and does not specify user-level skill paths as of the time of writing; the most widely circulated third-party writeup is behind a Medium paywall and was not consulted.
2. **The skill file-format contract.** Every skill host enforces its own frontmatter schema. OpenCode requires `name` (kebab-case regex `^[a-z0-9]+(-[a-z0-9]+)*$`, 1-64 chars), `description` (1-1024 chars), and an uppercase `SKILL.md` filename. Claude Code's schema is similar but not identical. Copilot CLI's constraints need to be verified before the installer can safely drop files into its discovery path.
3. **Agent and command discovery paths.** Copilot CLI has agent-style concepts of its own. Whether it reads slash commands from a dedicated directory, whether its agent definitions look anything like OpenCode's frontmatter contract, and whether there is a user-level or per-project convention — all of that needs the SDK source plus at least one official GitHub blog post to confirm.

Rather than guess at any of these, the bundle declines to ship Copilot support until they are confirmed from a public, canonical source. A `--profile copilot` that drops files into the wrong directory, or that writes frontmatter the host cannot parse, is worse than no profile at all.

---

## Planned bundle support

Once the paths above are confirmed, the bundle will grow:

- A `--profile copilot` flag in `install.sh`, following the same symlink model as the Claude Code and OpenCode profiles. The cloned repo stays the golden source of truth; Copilot's install path gets symlinks.
- A `copilot` column in [`compatibility.md`](compatibility.md)'s component matrix, listing which components install under which Copilot directory.
- Targeted adjustments to skill frontmatter if (and only if) Copilot's schema diverges from the OpenCode/Claude intersection the bundle already satisfies.
- A fresh lookup of the `TARGET_COPILOT` default in the installer, probably `$HOME/.config/copilot` or `$HOME/.copilot` depending on what the SDK repo settles on.

No file copies, no placeholder rewriting, no interactive prompts beyond the single confirm that every profile shares.

---

## Manual workaround

If you want to use the bundle's skills from Copilot CLI today, you need to find Copilot CLI's skill discovery directory yourself and manually drop symlinks into it. A starting point:

```bash
# 1. Install the bundle without Copilot support.
./install.sh --profile both    # or --profile claude / --profile opencode

# 2. Locate Copilot CLI's skill directory.
#    Check the SDK docs, check `copilot --help`, check any
#    configuration file Copilot CLI creates on first run.
copilot --help | grep -i skill || true
ls -la ~/.copilot 2>/dev/null
ls -la ~/.config/copilot 2>/dev/null

# 3. Once found, symlink the bundle's skills into it.
#    Replace <copilot-skills-dir> with the real path you found.
mkdir -p <copilot-skills-dir>
for skill in /path/to/agent-toolkit-bundle/skills/*/; do
  name=$(basename "$skill")
  ln -sfn "$skill" "<copilot-skills-dir>/$name"
done
```

Verify that Copilot CLI picks them up by starting a session and invoking a skill manually. If nothing resolves, the frontmatter contract is probably different — compare one of the bundle's `SKILL.md` files against whatever schema Copilot CLI's documentation or error messages imply.

This workaround is best-effort. Report findings — especially the confirmed discovery path — so the installer can grow a proper `--profile copilot` that future users do not need to hand-roll.

---

## See also

- Copilot CLI official docs: <https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli>
- Copilot Agent SDK repo: <https://github.com/github/copilot-sdk>
- [`compatibility.md`](compatibility.md) — the current tool compatibility matrix.
- [`skills.md`](skills.md) — the on-disk skill format the bundle uses.
