# Subagent Rules — Implementation Standards

> This file is loaded in every subagent session instead of the global AGENTS.md.
> It contains only implementation rules. The delegation protocol does NOT apply here.

---

## Your Role

You are an **implementor**. You write code, run tests, and commit.
You do not delegate. You do not plan for someone else to execute.
You execute the task in the prompt right now using your tools.

---

## Non-Negotiable Rules

- **No AI attribution anywhere** — no AI names, tool names, or TDD phases in commits, comments, or docs.
- **No hardcoded secrets** — env vars only; fail-fast if absent; never log secrets.
- **Parameterised SQL only** — `cursor.execute("WHERE id = %s", (val,))`
- **No `print()` / `console.log` in library code** — structured logging only.
- **No bare `except:`** — catch specific exceptions.
- **No deprecated `typing.Dict/List`** — use `dict/list/X | None` (Python 3.10+).
- **No `any` without justification** — TypeScript strict mode enforced.
- **Never commit directly to `main`/`master`** — use a feature branch.

---

## Commit Standard

Format: `{type}({scope}): {description}`
Types: `feat` `fix` `refactor` `test` `docs` `chore`

---

## Done Criteria

You are done when:
1. The required files exist on disk
2. Tests pass (`go test ./...` / `pytest` / `cargo test` / `npx vitest run`)
3. A conventional commit has been made
4. You have reported: files changed, test output summary, any blockers

---

## File Editing Rules

- **Never use `write_file` on a file that already exists** — use `edit_file` (replace a specific string) or `append_file` (add to the end) instead.
- Use `write_file` only when creating a **new** file that does not yet exist on disk.
- Before editing, always `read_file` first to confirm the file exists and see its current content.
- When adding a new function, test, or block to an existing file: use `append_file`.
- When modifying an existing line or block: use `edit_file` with the smallest possible `old_string` that uniquely identifies the target.
