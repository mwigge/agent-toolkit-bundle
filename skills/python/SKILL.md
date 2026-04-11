---
name: python
description: >
  Comprehensive Python skill covering language fundamentals, developer workflow (TDD, toolchain),
  idiomatic patterns and type hints, testing strategy (pytest, fixtures, coverage), and clean
  architecture (DI, hexagonal, 12-factor). Use when writing, reviewing, refactoring, designing,
  or testing Python code. Trigger phrases: python, pytest, TDD python, python patterns, python
  architecture, python testing, python developer, type hints, dataclass, protocol, fixtures,
  parametrize, clean architecture python, 12-factor python, ruff, mypy, bandit.
---

# Python Skill

One skill for all Python work: language fundamentals, daily developer workflow, idiomatic patterns,
testing strategy, and system architecture. Each domain has a lean summary here; detailed reference
material lives in `refs/`.

## When to Activate

- Writing, reviewing, or refactoring any Python code
- Starting a new Python project or module
- Running the TDD cycle (Red-Green-Refactor)
- Designing test suites, fixtures, or parametrised tests
- Choosing between language features (dataclass vs NamedTuple, threading vs asyncio)
- Designing package boundaries, layers, or framework choices
- Running pre-commit quality gates

---

## 1. Language Fundamentals

Target Python 3.10+ for all new projects. Use `requires-python = ">=3.11"` in `pyproject.toml`.

**Core types** fall into immutable (`int`, `float`, `str`, `bytes`, `bool`, `None`, `tuple`,
`frozenset`) and mutable (`list`, `dict`, `set`, `bytearray`). Choose the right collection:
`list` for ordered mutable sequences, `dict` for key-value lookup, `set` for uniqueness,
`tuple` for immutable records, `collections.deque` for double-ended queues.

**Modern syntax** to prefer: walrus operator (`:=`), structural pattern matching (`match`/`case`),
union types (`X | Y`), positional-only (`/`) and keyword-only (`*`) parameters.

**OOP**: prefer `@dataclass` for data containers, `Protocol` for structural subtyping over ABC
inheritance, `@cached_property` for expensive computed attributes. Know the dunder methods:
`__repr__`, `__eq__`/`__hash__`, `__iter__`/`__next__`, `__enter__`/`__exit__`, `__call__`.

**Async**: use `asyncio` for I/O-bound concurrency, `ProcessPoolExecutor` for CPU-bound work.
Never call blocking I/O inside an async function.

**Exception rules**: never catch `BaseException`, never use bare `except:`, always chain with
`raise NewError(...) from original`. Define a custom `AppError(Exception)` hierarchy.

For detailed coverage of data types, control flow, functions, closures, generators, itertools,
async patterns, stdlib quick reference, and exception hierarchy, see the full fundamentals
content retained in the sections below and `refs/patterns.md`.

---

## 2. Developer Workflow and TDD

Every new function, class, or behaviour follows **Red -> Green -> Refactor**:

1. **RED** -- write a failing test that describes the desired behaviour.
2. **GREEN** -- write the minimum code to make the test pass.
3. **REFACTOR** -- improve structure without changing behaviour; keep tests green.

Start with the test file, not the implementation. Test names are documentation:
`test_<unit>_<condition>_<expected_outcome>`. Every test follows **Arrange -> Act -> Assert**.

**Toolchain order** (run before every commit):

```bash
ruff check --fix .          # 1. Auto-fix imports and syntax
ruff format .               # 2. Format
black <package>/            # 3. Match CI formatter
ruff check .                # 4. Final lint (must be zero)
mypy <package>/ --strict    # 5. Type check
bandit -r <package>/ -ll    # 6. Security (zero HIGH)
pytest --co -q              # 7. Verify tests collect
pytest tests/ -v --cov=<package> --cov-fail-under=95  # 8. Tests + coverage
pip-audit                   # 9. CVE audit
```

**Type hints are mandatory** on all new functions. Use modern syntax: `list[str]`, `dict[str, int]`,
`X | None`. Never import deprecated `typing.List`, `typing.Dict`, `typing.Optional`.

**Import order**: stdlib, third-party, local (absolute imports only). `ruff` enforces this.

**Logging**: structured only via `logging.getLogger(__name__)`. Never `print()` in library code.
Never log credentials or PII.

**Commit format**: `{type}({scope}): {description}`. Never mention process, phases, or tooling
in commit messages.

For the complete workflow, conftest patterns, parametrize examples, mocking rules, and pitfall
catalogue, see `refs/developer-workflow.md`.

---

## 3. Patterns and Idioms

Write Python that is readable, explicit, and follows the principle of least surprise.

**Core principles**: readability counts, explicit over implicit, EAFP over LBYL. Use
comprehensions for simple transformations, generators for lazy evaluation and large datasets,
`pathlib.Path` for filesystem operations, f-strings for formatting.

**Type hints (Python 3.10+)**: always use built-in generics (`list[str]`, `dict[str, int]`)
and union shorthand (`X | Y`). Use `Protocol` for duck-typed interfaces. Use `TypeVar` for
generic functions.

**Error handling**: catch specific exceptions, chain with `from`, build a custom exception
hierarchy. Use context managers (`with`) for all resource management.

**Data modelling**: `@dataclass` for mutable entities, `@dataclass(frozen=True, slots=True)` for
value objects, `NamedTuple` for immutable records with unpacking. Add `__post_init__` validation.

**Decorators**: always use `@functools.wraps`. Prefer `@functools.cache` or `@lru_cache` for
memoisation.

**Concurrency**: `ThreadPoolExecutor` for I/O-bound, `ProcessPoolExecutor` for CPU-bound,
`asyncio` for async I/O. Never mix blocking calls into async code.

**Memory**: use `__slots__` on hot-path classes, generators over lists for large data, `str.join`
over concatenation in loops.

**Anti-patterns to avoid**: mutable default arguments, bare `except:`, `type()` instead of
`isinstance()`, `== None` instead of `is None`, `from module import *`, deprecated typing imports.

For the complete patterns catalogue including decorators, concurrency examples, package layout,
`pyproject.toml` configuration, and the full anti-patterns list, see `refs/patterns.md`.

---

## 4. Testing Strategy

Use pytest for all testing. Follow TDD: write the test first, watch it fail, implement, refactor.

**Test pyramid**: unit tests (fast, no I/O) at the base, integration tests (DB, HTTP) in the
middle, end-to-end tests (full pipeline) at the top. Organise in `tests/unit/`, `tests/integration/`,
`tests/e2e/`.

**Fixtures**: use `@pytest.fixture` for setup/teardown, scope appropriately (`function`, `module`,
`session`). Share via `conftest.py`. Use `autouse=True` sparingly.

**Parametrize**: use `@pytest.mark.parametrize` for boundary conditions and multiple input
combinations. Add descriptive `ids` for readable output.

**Mocking**: mock at the I/O boundary only, never mock internal implementation. Use `@patch` for
external dependencies, `AsyncMock` for async, `autospec=True` to catch API misuse.

**Async testing**: use `pytest-asyncio` with `@pytest.mark.asyncio`. Async fixtures yield via
`AsyncGenerator`.

**Coverage gate**: >= 95% on all changed files. Run with `--cov-fail-under=95`. If coverage is
low, find missing test cases rather than lowering the threshold.

**Property-based testing**: use Hypothesis `@given` for invariant properties. Test factories
via `factory_boy`.

For the complete testing reference including fixture scopes, marker configuration, mocking patterns,
database testing, API testing, and pytest configuration, see `refs/testing.md`.

---

## 5. Architecture and Design

Follow clean architecture with dependency inversion. The domain layer has zero imports from
outer layers.

**Layer order** (top to bottom):
1. **Routes / Handlers** -- thin; validate input, call service, return response (5-15 lines)
2. **Service Layer** -- business logic; orchestrates domain objects
3. **Domain / Core** -- pure functions + value objects; zero I/O
4. **Repositories / Adapters** -- all I/O (DB, HTTP, queues); implement Protocol interfaces
5. **Infrastructure** -- DB pool, HTTP client, OTel, config

**12-factor compliance**: config via `os.environ` / `pydantic-settings` (fail-fast if absent),
stateless processes, structured JSON logs to stdout, fast startup (< 3s), graceful SIGTERM shutdown.

**Configuration pattern**: single `Settings(BaseSettings)` class per package, required config has
no default, optional config has sensible defaults. Import the singleton; do not pass it down.

**Dependency injection**: use constructor injection with Protocol interfaces. No DI container
needed -- Python duck typing + Protocols provide the power without the magic.

**Error handling architecture**: custom `AppError(Exception)` hierarchy with `http_status` and
`error_code` attributes. Single exception handler at the route layer.

**Framework selection**: FastAPI for high-throughput async APIs, Django for traditional web apps,
Click/Typer for CLIs, Celery for background workers.

**Database rules**: all SQL uses parameterised placeholders (`$1` / `%s`), connection pool
created once at startup via DI, migrations in dedicated directory via alembic/yoyo.

**Observability**: every service emits OTel traces, structured JSON logs, and metrics following
the naming convention `resilience_<component>_<metric>_<unit>`.

For the complete architecture reference including file layout, async decision matrix, technology
stack defaults, and package dependency rules, see `refs/architecture.md`.

---

## 6. Quality Gates

Before declaring any Python work done, verify:

- [ ] All tests pass: `pytest tests/ -v --cov=<package> --cov-fail-under=95`
- [ ] Zero lint errors: `ruff check .`
- [ ] Formatting matches: `black --check <package>/`
- [ ] Type check passes: `mypy <package>/ --strict`
- [ ] Zero HIGH security issues: `bandit -r <package>/ -ll`
- [ ] No known CVEs: `pip-audit --strict`
- [ ] No deprecated typing imports (`List`, `Dict`, `Optional`)
- [ ] No bare `except:` clauses
- [ ] No `print()` in library code
- [ ] All public functions have type annotations and docstrings
- [ ] Domain layer imports nothing from outer layers

---

## Quick Reference

| Task | Command |
|------|---------|
| Run all tests | `pytest tests/ -v` |
| Run specific test | `pytest tests/unit/test_runner.py::test_run_success -v` |
| Run with coverage | `pytest --cov=<pkg> --cov-fail-under=95` |
| Fix lint | `ruff check --fix . && ruff format .` |
| Format | `black <package>/` |
| Type check | `mypy <package>/ --strict` |
| Security | `bandit -r <package>/ -ll` |
| CVE check | `pip-audit` |
| Last failed | `pytest --lf -v` |
| Collect only | `pytest --co -q` |
| Full pipeline | `bash scripts/check.sh <package>` |
| Dev quality gate | `bash scripts/dev_check.sh <src_dir>` |
| Pattern check | `python scripts/patterns_check.py <path>` |
| Arch check | `python scripts/arch_check.py <src_dir>` |
| Test conventions | `bash scripts/test_check.sh <tests_dir>` |
