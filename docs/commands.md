# Slash Commands

**Purpose**: Workflow automations — structured step-by-step procedures that Claude executes when you type `/command-name`. They replace repetitive manual steps.

---

## Command Reference

### /commit

**What**: Analyse diff, draft conventional commit message, validate, commit.

**Flow**:
1. `git add -u` (stage tracked changes)
2. Analyse diff to determine change type and scope
3. Draft message: `{type}({scope}): {description}`
4. Validate: no AI attribution, <= 72 chars, conventional format
5. Commit

**Example**:
```
/commit

Claude:
  -> git add -u
  -> git diff --staged: src/probes/network_latency.py, tests/test_network_latency.py
  -> drafts: "feat(chaos): add network latency probe for PostgreSQL"
  -> validates: no "Co-authored-by: Claude", 51 chars
  -> commits (hash: abc1234)
```

---

### /pr

**What**: Validate branch, push, fill MR template, create PR/MR.

**Flow**:
1. Validate branch name: `{type}/CLS-{N}/{description}`
2. Push to remote if needed
3. Fill MR template from diff (Jira refs, test plan, rollback plan)
4. Create PR/MR via `gh` (GitHub) or `glab` (GitLab)

**Rules**:
- Never reference `docs_local/`, planning artifacts, or internal labels in MR descriptions
- Only `CLS-N` Jira references
- Checklist items must be reader-verifiable from code and repo only

---

### /story

**What**: Draft a user story with INVEST check and acceptance criteria.

**Flow**:
1. Gather feature description
2. INVEST check: Independent, Negotiable, Valuable, Estimable, Small, Testable
3. Draft: Title + "As a..." + Given/When/Then ACs + estimate
4. Get approval
5. Hand off to `@jira-story` to create the CLS ticket

**Example**:
```
/story Add a kill switch to the network latency probe

Claude:
  -> INVEST check: all pass
  -> Drafts:
      Title: Add kill switch to network latency probe
      As a chaos engineer, I want to stop an active experiment
      immediately so that I can contain unintended blast radius.
      Given an active experiment, When I call POST /experiments/{id}/stop,
      Then the probe terminates within 5 seconds.
      Estimate: 3 points
  -> "Approve? [yes/edit]"
  -> On approval: "Hand off to @jira-story"
```

---

### /review

**What**: Adversarial 4-lens code review on the current branch.

**Flow**:
1. `git diff main...HEAD` to get all changes
2. Run security scan (secrets, injection patterns)
3. Apply 4-lens review: Correctness, Security, Observability, Maintainability
4. Check MR description (if present) for compliance
5. Output: BLOCKING issues, nits, verdict

---

### /spec

**What**: Generate an OpenAPI 3.1 path entry for a new endpoint.

**Flow**:
1. Gather endpoint details: path, method, request/response shape, auth, scopes
2. Generate OpenAPI 3.1 path entry with:
   - Error responses (400, 401, 403, 404, 409, 500)
   - Request/response examples
   - `dry_run` parameter if chaos endpoint
3. Output YAML ready to paste into an OpenAPI spec

---

### /index

**What**: Update docs index and memory after a work session.

**Flow**:
1. Scan `ai_local/` for all skills, agents, commands, hooks
2. Write/update `docs_local/INDEX.md`
3. Update `memory.md` with date and session state

---

### /mine

**What**: Mine OpenSpec artifacts and memory into MemPalace.

**Flow**:
1. Resolve target (specific change name, path, or all recent changes)
2. Check MemPalace is importable
3. Mine each artifact: `proposal.md`, `design.md`, `delivery.md`, `tasks.md` (< 150 lines)
4. Report results (processed, skipped, errors)

**Usage**:
```
/mine                           # all recently modified changes
/mine early-adopter-onboarding  # specific change
```

---

### /opsx:propose

**What**: Create a new OpenSpec change with all artifacts in one step.

**Produces**: `openspec/changes/<name>/proposal.md`, `design.md`, `specs/`, `tasks.md`

---

### /opsx:explore

**What**: Thinking mode — explore ideas, investigate problems, no implementation.

**Rules**: May read files and search code, but must NOT write code. May create OpenSpec artifacts (that's capturing thinking, not implementing).

---

### /opsx:apply

**What**: Implement tasks from an OpenSpec change.

**Flow**: Reads `tasks.md`, picks the next unchecked task, implements it, marks complete.

---

### /opsx:archive

**What**: Archive a completed change.

**Flow**: Promotes specs to `openspec/specs/`, moves the change directory to `openspec/changes/archive/`.

---

## Command File Location

Command definitions live in `.claude/commands/`. Each is a markdown file containing the full prompt that Claude executes. OpenSpec commands are in `.claude/commands/opsx/`.

---

## OpenCode Commands

OpenCode supports the same `/command` syntax as Claude Code. Command files live in
`ai_local/opencode/commands/` — symlinked to `~/.config/opencode/commands/` (global).
Edit files in `ai_local/opencode/commands/`; the change is live immediately via symlink.

### All commands are ported

| Command | File (canonical) | Status |
|---|---|---|
| `/commit` | `ai_local/opencode/commands/commit.md` | ✅ |
| `/pr` | `ai_local/opencode/commands/pr.md` | ✅ |
| `/story` | `ai_local/opencode/commands/story.md` | ✅ |
| `/review` | `ai_local/opencode/commands/review.md` | ✅ |
| `/spec` | `ai_local/opencode/commands/spec.md` | ✅ |
| `/index` | `ai_local/opencode/commands/index.md` | ✅ |
| `/mine` | `ai_local/opencode/commands/mine.md` | ✅ |
| `/opsx:propose` | `ai_local/opencode/commands/opsx/propose.md` | ✅ |
| `/opsx:apply` | `ai_local/opencode/commands/opsx/apply.md` | ✅ |
| `/opsx:explore` | `ai_local/opencode/commands/opsx/explore.md` | ✅ |
| `/opsx:archive` | `ai_local/opencode/commands/opsx/archive.md` | ✅ |

### How to add a new command (OpenCode)

1. Create `ai_local/opencode/commands/my-command.md` (canonical — symlinked to `~/.config/opencode/commands/`)
2. Write the command as a markdown prompt — the full text is injected into the model when the user types `/my-command`
3. No registration needed — OpenCode scans the commands directory automatically

For subcommand namespacing (e.g. `/opsx:propose`), create a subdirectory:
`ai_local/opencode/commands/opsx/propose.md` → `/opsx:propose`

### Difference from Claude Code

In Claude Code, command files live in `ai_local/.claude/commands/`. In OpenCode, the canonical
location is `ai_local/opencode/commands/`, symlinked to `~/.config/opencode/commands/`.
Project-scoped commands go in `<project>/.opencode/commands/`.
The markdown format and `/command-name` invocation syntax are identical.

---

## Codex Reference

Codex does not use these files as a native slash-command registry in this setup.

Instead, the Codex reference installation reuses the same command markdown files as
**workflow playbooks**:

- read the matching command file from `ai_local/opencode/commands/`
- follow its steps as the operating procedure
- treat `/commit`, `/review`, `/opsx:*`, and similar names as user intent labels

See `ai_local/codex/AGENTS.md` and [codex.md](codex.md) for the Codex-specific model.
