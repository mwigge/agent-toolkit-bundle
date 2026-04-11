---
name: typescript
description: Comprehensive TypeScript skill — language fundamentals, type system, generics, developer workflow (TDD, Vitest, DI), Red-Green-Refactor discipline, and clean architecture patterns. Use for any TypeScript development, testing, or design task.
---

# TypeScript — Unified Skill

TypeScript 5.x language fundamentals, developer workflow, TDD discipline, and architecture patterns for building safe, maintainable applications.

---

## Fundamentals

### Compiler Configuration

Enable `strict: true` plus additional safety flags (`noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noImplicitOverride`, `noPropertyAccessFromIndexSignature`). Use path aliases (`@src/*`, `@test/*`, `@lib/*`) — never use `../../` imports beyond one level deep.

### Type System

- **Prefer union types** over enums — simpler, tree-shakeable
- **Prefer interfaces** for public API shapes; **type aliases** for unions, intersections, mapped/conditional types
- **Generics**: constrain with `extends`, use defaults, keep type parameters minimal
- **Utility types**: `Partial`, `Required`, `Readonly`, `Pick`, `Omit`, `Record`, `Exclude`, `Extract`, `NonNullable`, `ReturnType`, `Awaited`
- **Discriminated unions**: tag with a literal discriminant, use `assertNever` for exhaustiveness
- **Branded types**: prevent mixing structurally identical types with smart constructors
- **Mapped types**: `Nullable<T>`, `DeepReadonly<T>`, key remapping with template literals
- **Conditional types**: `infer`, distributive conditionals

### Functional Patterns

- **ADTs**: sum types (discriminated unions) and product types (objects, tuples)
- **Boolean elimination**: replace boolean flags with explicit state variants
- **Option\<T\>**: explicit nullable values with `_tag: "None" | "Some"`
- **Result\<T, E\>**: explicit error handling with `_tag: "Ok" | "Err"`

### Anti-Patterns (never do)

- `any` without justification — use `unknown` and narrow
- `!` non-null assertion on uncertain values — use `??` or guard
- `@ts-ignore` — use `@ts-expect-error` with explanation if truly needed
- `{} as Type` — validate at boundaries with Zod or guards
- String enums — use union types
- Deep relative imports — use path aliases

For details, see [`refs/fundamentals.md`](./refs/fundamentals.md).

---

## Developer Workflow

### First Principles

1. Write the failing test first — no implementation without a red test
2. Strict types, zero `any` — every `any` is a bug waiting to happen
3. Behaviour, not implementation — tests prove what, not how
4. Self-verify before declaring done — run the full quality suite
5. Small commits, conventional messages — one logical change per commit

### TDD Cycle

```
RED      Write a failing test → confirm it fails with the right reason
GREEN    Write minimum code to pass → confirm green
REFACTOR Remove duplication, improve names → confirm still green
COMMIT   Conventional commit message
```

### Toolchain Run Order

```bash
npx tsc --noEmit          # Type check
npx eslint src/ tests/ --fix  # Lint
npx prettier --write src/ tests/  # Format
npx vitest run --coverage    # Tests + coverage
```

### Two Modes

| Input | Mode | Reference |
|-------|------|-----------|
| Spec (TRD, ADR, design doc) | Implementation | `refs/workflow-implementation.md` |
| Rejection feedback | Remediation | `refs/workflow-remediation.md` |

### Dependency Injection in Tests

Use in-memory fakes that implement the interface — no `vi.mock()` for DI. `vi.fn()` only for callbacks, timers, and spying without replacing behaviour.

For details, see [`refs/developer-workflow.md`](./refs/developer-workflow.md).

---

## TDD Discipline

### The Three Laws

1. Do not write production code unless it is to make a failing test pass
2. Do not write more of a test than is sufficient to fail
3. Do not write more production code than is sufficient to pass the current test

### Test Pyramid

~70% unit (pure logic, no I/O), ~20% integration (real DB/HTTP), ~10% E2E (critical journeys).

### Key Patterns

- **Fakes over mocks**: real simplified implementations, compile-checked against the interface
- **Parametrised tests**: `it.each(...)` for input/output matrices
- **Async tests**: `rejects.toThrow()`, fake timers with `vi.useFakeTimers()`
- **Test fixtures**: builder functions (`makeUser(overrides)`) with `@faker-js/faker`
- **Integration tests**: testcontainers for real DB
- **Test naming**: `GIVEN <precondition> WHEN <action> THEN <expected>`

### Coverage Gates

| Metric | Threshold |
|--------|-----------|
| Lines, Functions, Branches, Statements | >= 80% |

For details, see [`refs/tdd.md`](./refs/tdd.md).

---

## Architecture

### Layered Design

```
domain/          Pure business logic — no framework imports
application/     Use-cases, commands, queries, ports (interfaces)
infrastructure/  Adapters: DB, HTTP clients, messaging
interface/       Delivery: REST, CLI, GraphQL, workers
shared/          Cross-cutting: logger, config, result type
```

**Dependency rule**: inner layers never import from outer layers.

### Key Patterns

- **Interface-first design**: define ports in `application/ports/`, implement in `infrastructure/`
- **Composition root**: assemble the full dependency graph in `bootstrap.ts` — never `new` in domain/application
- **Configuration**: Zod schema validation at startup, fail-fast on missing env vars
- **Error hierarchy**: `DomainError` base with `NotFoundError`, `ConflictError`, `ValidationError`
- **HTTP error mapping**: interface layer only, RFC 9457 Problem Details
- **Module boundaries**: each module exposes via `index.ts`; no reaching into internals

### 12-Factor (TypeScript Edition)

Config via env vars, stateless processes, backing services injected via interfaces, structured JSON logs to stdout, graceful shutdown.

### Observability

Every use-case gets an OTel span. Structured logging only (pino). Metrics naming: `<service>.<entity>.<operation>`.

### Technology Stack Defaults

| Concern | Default |
|---------|---------|
| Runtime | Node.js 22 LTS |
| Packages | pnpm 9 |
| HTTP | Fastify |
| Validation | Zod |
| ORM | Drizzle |
| Testing | Vitest |
| Lint + Format | ESLint 9 flat + Prettier |
| Observability | OpenTelemetry SDK |

For details, see [`refs/architecture.md`](./refs/architecture.md).

---

## Quality Gates

### Before Every Commit

```bash
npx tsc --noEmit && npx eslint src/ tests/ --fix && npx prettier --write src/ tests/ && npx vitest run --coverage
```

### PR Checklist

- [ ] All functions have explicit return type annotations
- [ ] All public functions have JSDoc
- [ ] Tests prove behaviour, not implementation
- [ ] No `any`, no `!`, no `@ts-ignore`
- [ ] No hardcoded secrets
- [ ] No deep relative imports
- [ ] Coverage >= 80% on new code
- [ ] Conventional commit message

### Design Checklist (architecture changes)

- [ ] Module boundaries defined — public vs internal
- [ ] Dependencies flow inward
- [ ] All external deps injected via interfaces
- [ ] Config validated at startup with fail-fast
- [ ] Error hierarchy documented
- [ ] OTel spans on every use-case
- [ ] Parameterised queries for every DB call
- [ ] Input validated at boundary (Zod)
- [ ] Graceful shutdown handler registered

---

## Reference Files

| File | Purpose |
|------|---------|
| `refs/fundamentals.md` | Full type system, generics, utility types, modules, functional patterns |
| `refs/developer-workflow.md` | TDD workflow, Vitest config, ESLint config, DI patterns, code style |
| `refs/tdd.md` | Red-Green-Refactor, fakes over mocks, parametrised tests, async, fixtures |
| `refs/architecture.md` | Clean architecture, DI, module boundaries, error strategy, observability |
| `refs/adts.md` | Algebraic data types — nested ADTs, generic sum types, testing |
| `refs/branded-types.md` | Brand composition, NonEmptyArray, JSON serialisation, smart constructors |
| `refs/functional-migration.md` | Incremental adoption playbook, strict mode, CI enforcement |
| `refs/option-result.md` | Chaining, error accumulation, HTTP handling, conversion helpers |
| `refs/code-patterns.md` | Subprocess execution, resource cleanup, Zod config, typed errors |
| `refs/test-patterns.md` | Debuggability-first 4-part test progression |
| `refs/verification-checklist.md` | Full pre-submission checklist with tool commands |
| `refs/workflow-implementation.md` | Phase-by-phase implementation protocol (TDD) |
| `refs/workflow-remediation.md` | Phase-by-phase remediation protocol (fixes) |
| `refs/REFERENCES.md` | External links — language, toolchain, testing, architecture |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/check.sh` | Core TypeScript quality checks |
| `scripts/dev_check.sh` | Developer workflow quality checks |
| `scripts/tdd_check.sh` | TDD quality checks |
| `scripts/arch_check.sh` | Architecture quality checks |

## Templates

| Template | Purpose |
|----------|---------|
| `templates/tsconfig.json` | Strict baseline tsconfig |
| `templates/types_example.ts` | Type system examples |
| `templates/eslint.config.js` | ESLint 9 flat config |
| `templates/test_example.ts` | Vitest test examples |
| `templates/vitest.config.ts` | Vitest configuration |
| `templates/di_container.ts` | DI composition root example |
| `templates/result_type.ts` | Result type implementation |
