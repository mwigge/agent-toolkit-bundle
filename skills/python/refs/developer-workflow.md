# Python Developer Workflow

The daily workflow for writing production-quality Python code: TDD, toolchain, quality gates, and commit hygiene.

## When to Activate

- Starting implementation on any story or bug fix
- Setting up a new Python module or test file
- Running pre-commit checks before committing
- Debugging a failing test
- Reviewing someone else's Python PR

---

## 1. The TDD Cycle -- Non-Negotiable

Every new function, class, or behaviour follows **Red -> Green -> Refactor**.

```
RED    Write a failing test that describes the desired behaviour
GREEN  Write the minimum code to make the test pass
REFACTOR  Improve structure without changing behaviour; keep tests green
```

### Step-by-Step

**1. Start with the test file, not the implementation**

```python
# tests/unit/test_experiment_runner.py

def test_run_returns_success_result_for_valid_experiment():
    runner = ExperimentRunner(store=FakeStore(), tracer=FakeTracer())
    result = runner.run("exp-001")
    assert result.status == "success"
```

Run it -- it must fail (RED). If it passes without implementation, the test is wrong.

```bash
pytest tests/unit/test_experiment_runner.py -v
# FAILED tests/unit/test_experiment_runner.py::test_run_... - ImportError
```

**2. Write the minimal implementation (GREEN)**

```python
# src/myservice/runner.py

class ExperimentRunner:
    def __init__(self, store, tracer) -> None:
        self._store = store
        self._tracer = tracer

    def run(self, experiment_id: str) -> RunResult:
        return RunResult(status="success")
```

Run again -- it must pass.

**3. Add the next failing test, expand incrementally**

```python
def test_run_raises_not_found_for_unknown_experiment():
    runner = ExperimentRunner(store=FakeStore(), tracer=FakeTracer())
    with pytest.raises(NotFoundError):
        runner.run("does-not-exist")
```

**4. Refactor once green**

- Extract helper functions
- Replace magic strings with constants
- Improve naming
- Never refactor while RED

---

## 2. Test Naming Convention

```python
# Pattern: test_<unit>_<condition>_<expected_outcome>

def test_validate_experiment_with_empty_name_raises_validation_error(): ...
def test_run_experiment_when_probe_fails_returns_deviated_status(): ...
def test_create_user_with_duplicate_email_raises_conflict_error(): ...
def test_get_experiment_returns_none_when_not_found(): ...
```

Long names are correct. They are the documentation.

---

## 3. Test Structure -- AAA

Every test follows **Arrange -> Act -> Assert**:

```python
def test_score_is_zero_when_all_probes_fail(db_session):
    # Arrange
    experiment = ExperimentFactory.build(probe_count=3)
    db_session.add(experiment)
    db_session.flush()

    # Act
    score = calculate_resilience_score(experiment)

    # Assert
    assert score.value == 0.0
    assert score.label == "critical"
```

---

## 4. Pytest Essentials

### File layout

```
tests/
├── conftest.py          # shared fixtures
├── unit/                # fast, no I/O, pure logic
│   └── test_domain.py
├── integration/         # DB, HTTP -- use mocks or test containers
│   └── test_store.py
└── e2e/                 # full pipeline, real containers
    └── test_experiment_flow.py
```

### conftest.py patterns

```python
# tests/conftest.py
import pytest
from myservice.config import Settings

@pytest.fixture(scope="session")
def settings() -> Settings:
    return Settings(database_url="postgresql://localhost/test")

@pytest.fixture
def fake_store() -> FakeExperimentStore:
    return FakeExperimentStore()

@pytest.fixture
def runner(fake_store) -> ExperimentRunner:
    return ExperimentRunner(store=fake_store, tracer=NoopTracer())
```

### Parametrize -- use it for boundary conditions

```python
@pytest.mark.parametrize("score,expected_label", [
    (0.0,   "critical"),
    (0.25,  "critical"),
    (0.5,   "degraded"),
    (0.75,  "degraded"),
    (0.9,   "healthy"),
    (1.0,   "healthy"),
])
def test_score_label(score: float, expected_label: str) -> None:
    assert ResilienceScore(score).label == expected_label
```

### Mocking -- mock at the boundary

```python
from unittest.mock import AsyncMock, patch

@pytest.mark.asyncio
async def test_runner_calls_store_with_experiment_id(runner):
    runner._store.get = AsyncMock(return_value=None)

    with pytest.raises(NotFoundError):
        await runner.run("exp-999")

    runner._store.get.assert_awaited_once_with("exp-999")
```

**NEVER mock internal implementation -- mock I/O boundaries only.**

---

## 5. Coverage Requirements

```bash
# Run with coverage -- ALWAYS
pytest tests/ -v --cov=myservice --cov-report=term-missing --cov-fail-under=95

# Generate HTML report
pytest tests/ --cov=myservice --cov-report=html
open htmlcov/index.html
```

**Gate: >= 95% on all changed files. No exceptions.**

If you can't reach 95%, you are missing tests -- not overcounting. Find the missing cases.

---

## 6. Toolchain -- Run in This Order Before Every Commit

```bash
# 1. Auto-fix imports and syntax
ruff check --fix .
ruff format .

# 2. Black (CI uses black -- must match exactly)
black <package>/

# 3. Final lint check -- must be zero errors
ruff check .

# 4. Type check
mypy <package>/ --ignore-missing-imports

# 5. Security -- zero HIGH issues
bandit -r <package>/ -ll

# 6. Verify tests collect (catches import errors)
pytest --co -q

# 7. Run tests with coverage
pytest tests/ -v --cov=<package> --cov-report=term-missing --cov-fail-under=95

# 8. CVE audit
pip-audit
```

Or run the project pre-commit script:

```bash
./docs_local/projects/chaostooling-generic/03-team-coordination/scripts/pre-commit-checks.sh
```

---

## 7. Type Hints -- Always

```python
# ALL new functions must have type hints
# BAD
def process(data, timeout=30):
    pass

# GOOD
def process(data: dict[str, object], timeout: int = 30) -> ProcessResult:
    pass

# Modern union syntax (Python 3.10+)
def find(id: str) -> Experiment | None: ...

# No deprecated typing aliases (Python 3.9+)
# BAD
from typing import List, Dict, Optional
def f(x: List[str]) -> Optional[Dict[str, int]]: ...

# GOOD
def f(x: list[str]) -> dict[str, int] | None: ...
```

---

## 8. Import Order

`ruff` and `isort` enforce this automatically. Know the rule:

```python
# 1. stdlib
import os
import sys
from datetime import datetime, UTC
from pathlib import Path

# 2. third-party
import httpx
from fastapi import FastAPI, Depends
from pydantic import BaseModel

# 3. local -- absolute imports only
from myservice.domain.models import Experiment
from myservice.config import settings
```

---

## 9. Docstrings

```python
def calculate_resilience_score(
    experiment: Experiment,
    weights: ScoreWeights | None = None,
) -> ResilienceScore:
    """Calculate the resilience score for a completed experiment.

    Args:
        experiment: The completed experiment to score.
        weights: Optional custom weights; defaults to ScoreWeights.default().

    Returns:
        A ResilienceScore with value in [0, 1] and a descriptive label.

    Raises:
        ValueError: If the experiment has no completed runs.
    """
```

Use Google-style docstrings. Do not document the obvious.

---

## 10. Logging -- Structured, Never print()

```python
import logging

logger = logging.getLogger(__name__)

# BAD
print(f"Running experiment {experiment_id}")

# GOOD
logger.info("running experiment", extra={"experiment_id": experiment_id})

# NEVER log credentials, PII, or connection strings
logger.debug("connected", extra={"host": host, "port": port})  # OK
logger.debug("connected", extra={"dsn": dsn})                  # BAD -- may contain password
```

---

## 11. Common Pitfalls and Fixes

### Pitfall: module-level decorator test assertion

```python
# WRONG -- @_instrument_action fires at import time, not call time
assert mock_tracer.start_span.call_count == 1  # always 0 or misleading

# CORRECT -- test observable behaviour
result = action_under_test(target, configuration, secrets)
assert result["status"] == "success"
assert some_span_attribute_was_set(mock_tracer)
```

### Pitfall: sleeping in tests

```python
# WRONG
import time
time.sleep(0.1)  # flaky

# CORRECT -- use freezegun or mock time
from freezegun import freeze_time

@freeze_time("2026-01-01 12:00:00")
def test_expiry(): ...
```

### Pitfall: not cleaning up state between tests

```python
# WRONG -- shared mutable state leaks between tests
_cache: dict = {}

# CORRECT -- use fixtures with setup/teardown
@pytest.fixture(autouse=True)
def clear_cache():
    yield
    _cache.clear()
```

---

## 12. Commit Message Format

```
feat(runner): add dry-run mode to experiment execution

Allows operators to validate experiment configuration without
affecting the target system. Probe results are collected but
chaos actions are skipped.

Closes CLS-42
```

**Never** mention TDD, failing tests, red phase, or "add tests for" in a commit message. The commit describes the feature, not the process.

---

## 13. Quick Reference Card

| Task | Command |
|------|---------|
| Run all tests | `pytest tests/ -v` |
| Run specific test | `pytest tests/unit/test_runner.py::test_run_success -v` |
| Run with coverage | `pytest --cov=myservice --cov-fail-under=95` |
| Watch mode | `pytest-watch` or `ptw` |
| Fix lint | `ruff check --fix . && ruff format .` |
| Format | `black <package>/` |
| Type check | `mypy <package>/` |
| Security | `bandit -r <package>/ -ll` |
| CVE check | `pip-audit` |
| Last failed | `pytest --lf -v` |
| Collect only | `pytest --co -q` |
| Verbose on fail | `pytest --tb=long -v` |
