# /test — Generate and Run Tests

Generate meaningful tests for the target and run them to green. The target is the command argument (a file, function, or module); if none is given, use the current diff / most recently changed files.

## Skills in Effect

- **`/tdd-workflow`** — Red-Green-Refactor discipline, test naming, AAA structure, coverage gates.
- **`/property-based-testing`** — when the target has invariants worth checking across many inputs (round-trips, idempotency, ordering, bounds).

## Steps

### 1. Understand the target

Read the target code. Identify its public behaviour, inputs, outputs, side effects, and error paths. List the branches and edge cases that need coverage:

- Happy path(s)
- Boundaries: empty, zero, negative, max, null/None/undefined
- Error paths: every `except`/`catch` and validation failure
- Idempotency / concurrency where relevant
- Invariants that hold for all inputs -> candidates for property-based tests

### 2. Detect the stack and test runner

```bash
# Python
ls pyproject.toml pytest.ini 2>/dev/null && echo "pytest"
# TypeScript / JS
cat package.json 2>/dev/null | grep -E "vitest|jest"
```

Match the project's existing test conventions (framework, directory layout, fixture style, naming). Do not introduce a second framework.

### 3. Write behaviour-focused tests

- One behaviour per test; name it for the behaviour, not the implementation (`test_<unit>_<condition>_<expected>`).
- Arrange–Act–Assert. Mock only at I/O boundaries (DB, HTTP, filesystem) — never internal domain logic.
- Parametrise boundary conditions rather than copy-pasting cases.
- Add property-based tests for any invariant surfaced in step 1.
- Assert on observable behaviour and return values, not private internals.

### 4. Run and close gaps

**Python:**
```bash
pytest -v --cov=<package> --cov-report=term-missing --cov-fail-under=95
```

**TypeScript:**
```bash
npx vitest run --coverage
```

Read the coverage report. Add tests for every uncovered branch until the gate passes (≥95% Python / ≥80% TypeScript on changed files). A line covered but not asserted on is not tested — verify each test would fail if the behaviour regressed.

### 5. Report

```
## Tests — <target>
Added: <n> tests (<m> parametrised cases, <k> property-based)
Result: <pass/fail counts>
Coverage: <before>% -> <after>% on <target>
Gaps closed: <list>
Remaining risk: <any behaviour still untested and why>
```
