---
description: Safely refactor a target — reduce complexity or pay down debt without changing behaviour, one verified transformation at a time.
argument-hint: <file / function / module> [smell or goal]
---

# /refactor — Safe, Behaviour-Preserving Refactor

Refactor the target without changing its behaviour. Target and goal: `$ARGUMENTS`.

## Skills in Effect

- **`/refactoring-specialist`** — smell detection, extract/inline/move/rename catalogue, strangler-fig, complexity metrics.
- **`/solid`** — single responsibility, depend on abstractions, no god objects; clean-code rules (early return, small methods, no primitive obsession, no abbreviations).

## Steps

### 1. Establish a safety net FIRST

Refactoring without tests is editing. Before changing anything:

```bash
# run the tests that cover the target and confirm they are green
pytest <path> -v          # or: npx vitest run <path>
```

If the target is **not** covered, write **characterisation tests** that pin its current behaviour (including quirks) before touching it. Do not refactor uncovered code.

### 2. Identify the smell / goal

Name the specific problem: long function, duplicated logic, primitive obsession, feature envy, god object, deep nesting, unclear names, mixed responsibilities. Tie the refactor to one concrete goal — do not "tidy everything".

### 3. Refactor in small, verified steps

Apply **one** transformation at a time from the catalogue (extract function/class, inline, move, rename, replace conditional with polymorphism, introduce parameter object, guard-clause early returns). After **each** step:

```bash
pytest <path> -v          # must stay green
```

- Never batch multiple transformations between test runs — you lose the ability to localise a break.
- Keep behaviour identical: same inputs -> same outputs, same side effects. If behaviour must change, that is a feature change, not a refactor — stop and flag it.
- Improve names to domain intent; remove dead code and duplication you touch; keep control flow shallow (validate and return early).

### 4. Final verification

```bash
# full suite + linters/type check for the stack
pytest -v && ruff check . && mypy <package>          # Python
npx vitest run && npx eslint . && npx tsc --noEmit    # TypeScript
```

Behaviour unchanged, complexity down, everything green.

### 5. Report

```
## Refactor — <target>
Smell/goal: <what and why>
Safety net: <existing tests | characterisation tests added>
Transformations: <ordered list, each verified green>
Behaviour: unchanged (same tests pass before and after)
Metrics: <complexity / length / duplication before -> after>
```

Commit as `refactor(<scope>): <description>` — no behaviour-change wording.
