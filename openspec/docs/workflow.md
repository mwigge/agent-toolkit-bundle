# Workflow — OpenSpec

The OpenSpec workflow is three commands. Human and AI align on what to build,
implement it task by task, then promote the specs when done.

```
/opsx:propose   →   /opsx:apply   →   /opsx:archive
```

---

## Overview

Each change lives in `openspec/changes/<name>/` and contains:

```
openspec/changes/add-dark-mode/
├── .openspec.yaml   ← change metadata (managed by CLI)
├── proposal.md      ← what & why
├── design.md        ← technical approach and decisions
├── specs/           ← requirement deltas against main specs
│   └── ui-theme/
│       └── spec.md
└── tasks.md         ← implementation checklist
```

When the change is archived, the spec deltas are merged into `openspec/specs/`
and the change folder moves to `openspec/changes/archive/`.

---

## Step 1: Propose

**Slash command**: `/opsx:propose <name>`

Creates the change directory and generates all planning artifacts in one pass.

```
You:  /opsx:propose add-dark-mode

AI:   Created openspec/changes/add-dark-mode/
      ✓ proposal.md  — why we're doing this, what's changing
      ✓ design.md    — technical approach
      ✓ specs/       — requirement deltas
      ✓ tasks.md     — 8 tasks across 2 phases
      Ready for implementation. Run /opsx:apply to start.
```

**What to review before moving on:**

- `proposal.md` — is the scope right? Are the goals clear?
- `design.md` — does the technical approach match your intent?
- `tasks.md` — are the tasks the right granularity?

Edit any artifact before implementing. The plan is yours to change.

---

## Step 2: Apply

**Slash command**: `/opsx:apply [name]`

Implements tasks from the change one by one. If only one active change exists,
the name is inferred automatically.

```
You:  /opsx:apply

AI:   Using change: add-dark-mode (schema: spec-driven)
      Progress: 0/8 tasks complete

      Working on task 1/8: Add theme context provider
      [implementation...]
      ✓ Task complete

      Working on task 2/8: Create toggle component
      [implementation...]
      ✓ Task complete
      ...
```

The agent marks each task `- [x]` in `tasks.md` as it completes it. You can
interrupt at any point and resume later — the checkbox state is persistent.

**If the agent pauses:**

```
## Implementation Paused

Progress: 4/8 tasks complete

Issue: The OAuth integration is more complex than expected.
The current design assumes a single provider but the codebase
supports three. Options:
1. Scope this change to the primary provider only
2. Update design.md to cover all three providers

What would you like to do?
```

Update the relevant artifact and re-run `/opsx:apply` to continue.

---

## Step 3: Explore (optional)

**Slash command**: `/opsx:explore [name]`

A thinking-partner mode for before or during a change. Does not implement
anything — reads files, draws diagrams, compares options. Useful when
requirements are unclear or mid-implementation surprises arise.

```
You:  /opsx:explore
      The OAuth integration is more complex than expected

AI:   [reads change artifacts, maps the existing auth code]

      CURRENT AUTH FLOW
      ─────────────────────────────────────────
      ┌──────────┐  ┌──────────┐  ┌──────────┐
      │  Google  │  │  GitHub  │  │  Email   │
      └────┬─────┘  └────┬─────┘  └────┬─────┘
           └─────────────┼─────────────┘
                         ▼
                   ┌───────────┐
                   │  Session  │
                   └───────────┘

      Three providers all converge on the same session layer.
      The design currently only mentions Google.

      Want to update design.md to reflect this, or scope
      the change to Google only?
```

---

## Step 4: Archive

**Slash command**: `/opsx:archive [name]`

Merges spec deltas into `openspec/specs/`, moves the change to
`openspec/changes/archive/YYYY-MM-DD-<name>/`.

```
You:  /opsx:archive

AI:   Change: add-dark-mode
      Schema: spec-driven
      Artifacts: all complete ✓
      Tasks: 8/8 complete ✓

      Spec delta found in specs/ui-theme/spec.md
      → Syncing 3 requirement changes to openspec/specs/ui-theme/spec.md

      Archived to openspec/changes/archive/2026-06-03-add-dark-mode/
```

---

## Status commands

```bash
# List all active changes
openspec list

# Show artifact completion for a change
openspec status --change add-dark-mode

# Open the interactive dashboard
openspec view
```

Example `openspec list` output:

```
CHANGES
  add-dark-mode      spec-driven   ready        3/3 artifacts, 0/8 tasks done
  fix-auth-bug       spec-driven   in-progress  2/3 artifacts
```

Example `openspec status --change add-dark-mode` output:

```
Change: add-dark-mode
Schema: spec-driven
─────────────────────────────────────────
  ✓ proposal.md        done
  ✓ design.md          done
  ✓ tasks.md           done  (8 tasks, 5 complete)
─────────────────────────────────────────
Status: in-progress (apply-ready)
```

---

## Working with specs

Specs live in `openspec/specs/<capability>/spec.md` and describe the
*functional requirements* of a capability. They persist across changes and
accumulate the intent behind the code.

```
openspec/specs/
├── auth-login/
│   └── spec.md       ← login requirements and scenarios
├── auth-session/
│   └── spec.md       ← session lifecycle requirements
└── ui-theme/
    └── spec.md       ← theme and dark mode requirements
```

A change's `specs/` subfolder contains *deltas* — additions and modifications
to main specs that take effect when the change is archived. You review them in
the proposal phase and `/opsx:archive` applies them.

---

## Tips

- **Clear context before `/opsx:apply`** — OpenSpec benefits from a clean
  context window at the start of implementation.
- **Commit after archiving** — `git add openspec/specs/ && git commit` to
  preserve the updated specs alongside the code.
- **One change at a time** — the workflow is designed for focused, sequential
  changes rather than concurrent branches.
- **Edit artifacts freely** — proposal, design, and tasks can be updated at
  any point. The workflow is fluid, not phase-locked.
