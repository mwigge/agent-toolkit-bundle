# /pr — Create GitLab MR or GitHub PR

Create a merge request or pull request from the current branch.

## Steps

### 1. Validate branch name

```bash
git branch --show-current
```

Check the branch name follows the pattern: `{type}/<PROJ>-{N}/{short-description}`

Examples of valid names:
- `feat/<PROJ>-123/network-latency-probe`
- `fix/<PROJ>-123/expired-token-handling`
- `refactor/<PROJ>-123/extract-tag-validator`

If the branch name does not match, warn:
```
WARNING: Branch name does not follow {type}/<PROJ>-{N}/{description} convention.
Current: <name>
Expected pattern: feat/<PROJ>-123/short-description
Proceed anyway? (continuing — rename the branch before merge if possible)
```

### 2. Review all commits on the branch

```bash
git log main..HEAD --oneline
git diff main...HEAD --stat
```

Read the full diff to understand what changed. This is the scope of the MR.

### 3. Ensure branch is pushed

```bash
git status
```

If the branch has no upstream or is ahead of remote:
```bash
git push -u origin HEAD
```

### 4. Load the MR description template

Read `~/<your-dev-dir>/agent-toolkit-bundle/mr-description-template.md` and fill every section based on the diff and commit history.

**Template sections to fill:**

#### What
One paragraph describing what was built. Key files/functions added or changed.
Include a behaviour table if there are multiple modes or conditions.

#### Why
One sentence stating the business reason. Always include the Jira reference:
```
Jira: <PROJ>-<N>
```
The Jira reference is extracted from the branch name `{type}/<PROJ>-{N}/`.

#### Tests
Fill with actual numbers from the test run:
- Tests: __ / __ pass
- Coverage (`<module>`): __%
- Suite total: __ tests
- Ruff / Mypy / Bandit HIGH: 0 / 0 / 0

If you don't have these numbers, note: "Run the test suite to fill these before merge."

#### Docs
Link any doc that was added or updated (CHANGELOG.md, architecture notes, runbooks).
Delete this section if no docs changed.

#### Checklist
Mark each item that applies:
```
- [x] Pre-commit checks pass locally before push
- [x] Coverage ≥ 95% on all changed files
- [x] CHANGELOG.md updated
- [x] No hardcoded credentials
- [x] OTel span added for any new action or probe (engine only)
```

### 5. Validate the MR description

Before creating, check:
- [ ] Jira reference present: `<PROJ>-N` — not placeholder `<PROJ>-`
- [ ] No AI attribution: no "Co-authored-by: Claude", no mention of agent names
- [ ] No references to `<your-docs-dir>/`, planning artefacts, or internal labels (ELI-A, EA-x, T1)
- [ ] No Jira references other than `<PROJ>-N` format
- [ ] Rollback plan present or explicitly stated as "not applicable" with reason

### 6. Create the MR / PR

**For GitHub (gh CLI):**
```bash
gh pr create \
    --title "<type>(<scope>): <description from most significant commit>" \
    --body "$(cat <<'EOF'
<filled MR description>
EOF
)"
```

**For GitLab (glab CLI):**
```bash
glab mr create \
    --title "<title>" \
    --description "<filled description>" \
    --target-branch main \
    --remove-source-branch
```

Use whichever CLI is available. Check with `which gh` and `which glab`.

### 7. Output the URL

```
MR created: <URL>
```

## MR Title Format

Same as the primary commit on the branch, or a summary if there are multiple commits:
```
feat(library): add experiment copy endpoint
fix(auth): handle expired JWT with 401 and clear error message
```

No AI attribution. No branch name. No ticket number in the title (it belongs in the body).
