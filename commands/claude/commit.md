---
description: Analyse the staged (or tracked) diff, draft a conventional commit message, validate it, and commit.
---

# /commit — Conventional Commit Creator

Create a conventional commit for the current staged (or tracked) changes.

## Steps

### 1. Check what is staged

```bash
git status
git diff --staged
```

If nothing is staged, add all tracked modifications:
```bash
git add -u
git status
git diff --staged
```

Explain what was added and why (based on the diff).

### 2. Analyse the changes

Read the diff and identify:
- What changed (files, functions, behaviour)
- Why it changed (bug fix, new feature, refactor, tests, docs, config)
- The scope of the change (which module or package)

### 3. Draft the commit message

Follow Conventional Commits format:

```
<type>(<scope>): <description>

[optional body: explain what and why, not how — wrap at 72 chars]

[optional footer: BREAKING CHANGE: <description>]
```

**Types:**
| Type | When |
|------|------|
| `feat` | New user-facing behaviour or capability |
| `fix` | Bug fix |
| `refactor` | Code change with no behaviour change |
| `test` | Adding or fixing tests only |
| `docs` | Documentation only |
| `chore` | Build, deps, CI/CD, tooling — no prod code |

**Scope:** the module, package, or domain area (e.g. `experiments`, `auth`, `library`, `metrics`)

**Description rules:**
- Lowercase, imperative mood: "add", "fix", "remove", "update" — not "Added", "Fixes"
- No period at end
- ≤ 72 characters total for subject line
- Describe the capability or fix, not the implementation: "add dry_run support to experiment trigger" not "modify routes/experiments.py to accept dry_run param"

### 4. Validate the commit message

Before committing, check:

- [ ] Subject line ≤ 72 characters
- [ ] Type is one of: feat / fix / refactor / test / docs / chore
- [ ] No mention of TDD phases (Red/Green/Refactor) in the message
- [ ] No agent names in the message (no "@coder-python", no "Claude", no "AI")
- [ ] No `Co-authored-by: Claude` or any AI attribution in message or trailers
- [ ] If breaking change: `!` after type or `BREAKING CHANGE:` footer present

If any check fails, revise the message before committing.

### 5. Commit

```bash
git commit -m "<subject line>"
```

For messages with a body:
```bash
git commit -m "<subject line>" -m "<body paragraph>"
```

### 6. Output the result

After the commit succeeds, output:
```
Committed: <short hash> <subject line>
```

## Examples

```
feat(experiments): add dry_run parameter to experiment trigger endpoint
fix(auth): handle expired JWT gracefully with 401 response
refactor(library): extract tag validation to dedicated validator module
test(runs): add integration tests for org isolation on run queries
docs(changelog): add release notes for v1.4.0
chore: update ruff to 0.8.x and fix new lint warnings
feat!: remove v0 API endpoints — consumers must migrate to /v1/
```
