# Quality Metrics

Deep-dive reference for test quality measurement: defect density, defect leakage, test effectiveness, MTTD, risk-based prioritisation, shift-left testing, and mutation testing.

## Quality Metrics

### Defect Density

Defects per thousand lines of code (KLOC):

```
defect_density = total_defects / (lines_of_code / 1000)
```

| Rating | Defects per KLOC | Interpretation |
|--------|-----------------|----------------|
| Excellent | < 1.0 | Production-grade quality |
| Good | 1.0 – 5.0 | Acceptable for most systems |
| Concerning | 5.0 – 10.0 | Needs targeted refactoring |
| Poor | > 10.0 | Systemic quality issues |

Track defect density per module to identify hotspots that need attention.

### Defect Leakage

Percentage of defects that escape to production despite testing:

```
defect_leakage = (defects_found_in_production / total_defects_found) * 100
```

- Target: < 5% leakage rate
- Measure per release cycle
- Every leaked defect must become a regression test case
- High leakage in a module indicates insufficient test coverage or missing test scenarios

### Test Effectiveness

Ratio of defects found by tests vs. total defects (including those found in production):

```
test_effectiveness = defects_found_by_tests / (defects_found_by_tests + defects_found_in_production)
```

- Target: > 95% effectiveness
- Break down by test type (unit, integration, E2E) to identify which layer catches the most defects
- Low unit test effectiveness often indicates tests are testing implementation details rather than behaviour

### Mean Time to Detect (MTTD)

Average time between a defect being introduced and being detected:

- **Unit tests**: MTTD should be < 5 minutes (caught during TDD cycle)
- **Integration tests**: MTTD should be < 1 hour (caught in CI pipeline)
- **E2E tests**: MTTD should be < 4 hours (caught in staging)
- **Production monitoring**: MTTD should be < 15 minutes (caught by alerts)

Shorter MTTD means cheaper fixes. A defect found in production costs 10-100x more to fix than one found during development.

### Risk-Based Test Prioritisation

Not all code paths are equally important. Prioritise testing by risk:

| Priority | Criteria | Test depth |
|----------|----------|------------|
| P0 — Critical | Revenue-impacting, data integrity, security | 100% coverage, E2E, chaos tests |
| P1 — High | Core user workflows, API contracts | 95%+ coverage, integration tests |
| P2 — Medium | Secondary features, admin flows | 80%+ coverage, unit tests |
| P3 — Low | Cosmetic, logging, internal tooling | Smoke tests sufficient |

**Rules**:
- Test critical paths first — if time is limited, skip P3 before skipping P0
- Code that handles money, authentication, or personal data is always P0
- Code with high cyclomatic complexity (> 10) gets extra test attention regardless of priority

### Shift-Left Testing

Test at the earliest possible stage in the development lifecycle:

```
Cheapest ◄──────────────────────────────────────────► Most expensive

  IDE          Unit        Integration      Staging      Production
  (lint,       (TDD        (CI pipeline)    (E2E,        (monitoring,
   types)       cycle)                       load)        incident)
```

**Practices**:
- Use type checking and linting as the first quality gate (catches ~30% of issues)
- Write unit tests during development, not after (TDD)
- Run integration tests in CI on every push, not just before release
- Automate E2E tests in staging — never rely on manual QA as the primary gate
- Shift security testing left: run `pip-audit`/`npm audit` in pre-commit hooks

### Mutation Testing

Validate that your tests actually catch bugs by introducing small mutations into the code and checking that tests fail:

```
Mutation types:
- Replace `>` with `>=`           (boundary mutations)
- Replace `True` with `False`     (boolean mutations)
- Replace `+` with `-`            (arithmetic mutations)
- Remove a function call          (statement deletion)
- Replace return value with None  (return value mutation)
```

```bash
# Python — mutmut
mutmut run --paths-to-mutate=src/

# TypeScript — Stryker
npx stryker run
```

**Mutation score**:
```
mutation_score = killed_mutants / total_mutants * 100
```

| Score | Interpretation |
|-------|----------------|
| > 80% | Strong test suite — tests catch most real bugs |
| 60-80% | Adequate — review surviving mutants for gaps |
| < 60% | Weak — tests pass but do not validate behaviour |

- Run mutation testing on P0/P1 modules at minimum
- Surviving mutants reveal missing assertions and untested branches
- A high line coverage with low mutation score means tests execute code but do not verify results
