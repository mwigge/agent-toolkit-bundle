# Red-Green-Refactor: TDD Cycle Cheat Sheet

## The Three Laws

1. Write no production code unless a failing test requires it.
2. Write only enough test code to produce a failure (compilation failure counts).
3. Write only enough production code to make the failing test pass.

---

## The Cycle

```
RED  →  GREEN  →  REFACTOR  →  RED  →  ...
```

### RED — Write a failing test

- Name the test for the **behaviour**, not the implementation
  - `test_score_is_zero_when_no_experiments_completed` ✓
  - `test_calculate_resilience_score` ✗
- Write the **simplest** test that could possibly fail
- Run the test — confirm it fails for the **right reason** (assertion error, not syntax error)
- The test must compile/parse — write minimum scaffolding if needed
- Do not write more than one failing test at a time

**Checklist before writing production code:**
- [ ] Test fails? (red bar visible)
- [ ] Test fails for the expected reason?
- [ ] Test name describes the behaviour, not the method?

---

### GREEN — Make it pass (the simplest way)

- Write **only** enough code to make the failing test pass
- "Fake it till you make it" is valid — return a hardcoded value if it passes the test
  - Hardcoded value → triangulation with a second test forces generalisation
- Do **not** refactor during this phase
- Do **not** add features not required by the current test
- Run **all** tests — confirm the new one passes and nothing regresses

**Acceptable shortcuts in Green:**
- Returning a constant
- Duplicating code
- Using `if/else` instead of a general algorithm

These will be cleaned up in Refactor. The point is fast feedback.

---

### REFACTOR — Improve the design

Only refactor when all tests are green. Refactoring must not change behaviour.

**Refactor checklist:**
- [ ] All tests green before starting
- [ ] Run tests after **every** small change
- [ ] Eliminate duplication (DRY)
- [ ] Extract well-named functions/methods
- [ ] Clarify intent — rename variables, functions, classes
- [ ] Remove dead code
- [ ] Apply appropriate design patterns
- [ ] All tests still green after finishing

**Common refactoring moves:**
- Extract Method / Extract Variable
- Rename (method, parameter, class)
- Inline temporary variable
- Replace conditional with polymorphism
- Introduce Parameter Object

---

## Example Cycle Walkthrough

### Scenario: Compute resilience score

**Step 1 — RED**
```python
def test_score_is_zero_with_no_experiments():
    assert compute_resilience_score([]) == 0.0
```
Run → `NameError: name 'compute_resilience_score' is not defined` ✓ (right failure)

**Step 2 — GREEN**
```python
def compute_resilience_score(experiments):
    return 0.0  # Fake it — makes this test pass
```
Run → Green ✓

**Step 3 — RED (triangulate)**
```python
def test_score_is_100_when_all_pass():
    experiments = [{"success": True}, {"success": True}]
    assert compute_resilience_score(experiments) == 100.0
```
Run → Red (returns 0.0 instead of 100.0) ✓

**Step 4 — GREEN**
```python
def compute_resilience_score(experiments):
    if not experiments:
        return 0.0
    passed = sum(1 for e in experiments if e["success"])
    return (passed / len(experiments)) * 100.0
```
Run → Both tests Green ✓

**Step 5 — REFACTOR**
```python
def compute_resilience_score(experiments: list[dict]) -> float:
    """Return success rate as a percentage [0.0, 100.0]."""
    if not experiments:
        return 0.0
    pass_count = sum(1 for exp in experiments if exp["success"])
    return round((pass_count / len(experiments)) * 100.0, 2)
```
- Added type hints
- Renamed `passed` → `pass_count` (clearer)
- Added docstring
- Added `round()` for consistent precision

Run all tests → Green ✓. Commit.

---

## Anti-Patterns to Avoid

| Anti-pattern | Problem | Fix |
|---|---|---|
| Writing tests after production code | No design feedback; tests become approvals not specifications | Strict Red-first discipline |
| Testing implementation details | Tests break on refactor; locks in bad design | Test observable behaviour/outputs |
| Testing the framework/library | Testing code you don't own | Trust third-party libs; mock at your boundary |
| Giant tests (100+ lines) | Hard to name, hard to diagnose | One assertion per test concept |
| Skipping Refactor phase | Code rots; duplication accumulates | Commit to all three phases |
| Never running in Red | Tests may never actually catch failures | Confirm the red bar every time |
| Mocking too much | Tests pass but system fails | Use real collaborators where fast enough |
| `@pytest.mark.skip` as a permanent state | Dead tests give false coverage confidence | Delete or fix skipped tests |
| Committing red tests | Breaks CI; demoralises team | Use `tdd_guard.sh` pre-commit hook |

---

## Test Naming Conventions

```
test_{unit_under_test}_{scenario}_{expected_outcome}

test_compute_score_with_all_failed_returns_zero
test_experiment_start_when_already_running_raises_error
test_repository_save_persists_to_database
```

Or using `should` language (BDD style):
```
it should return 0 when no experiments have completed
it should raise ValueError when blast_radius exceeds 1.0
```

---

## Coverage is a Floor, Not a Target

- 95% coverage (Python) / 80% (TypeScript) is the **minimum floor**
- 100% line coverage does not mean correctness — you need meaningful assertions
- Branch coverage (condition combinations) is more valuable than line coverage
- If you follow TDD strictly, coverage follows naturally — do not write tests solely to hit a number
