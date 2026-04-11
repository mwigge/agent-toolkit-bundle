# TypeScript TDD (Detailed)

Strict Red-Green-Refactor discipline with Vitest. Tests prove behaviour; fakes replace mocks;
every story starts with a failing test.

---

## The Three Laws of TDD

1. **Do not write production code** unless it is to make a failing test pass.
2. **Do not write more of a test** than is sufficient to fail (compilation failure counts as failure).
3. **Do not write more production code** than is sufficient to make the currently failing test pass.

---

## Red → Green → Refactor

```
RED      Write the smallest test that describes ONE behaviour.
         Run it. It must FAIL with the right assertion message.
         If it fails to compile: that counts as red. Fix compile first, then assert.

GREEN    Write the MINIMUM code that makes the test pass.
         Do not generalise yet. Do not add error handling not covered by a test.
         Run the suite: all green.

REFACTOR Eliminate duplication. Improve names. Extract functions.
         Run the suite after every change: must stay all green.
         Commit only when tests are green.
```

---

## Test Pyramid

```
         /\
        /E2E\        — Few. Full stack. External services.
       /------\
      /INTEGR. \     — Some. Real DB / real HTTP / message bus.
     /----------\
    /    UNIT    \   — Many. Pure logic. No I/O. Milliseconds.
   /--------------\
```

**Target distribution**: ~70% unit, ~20% integration, ~10% E2E.
Unit tests run on every save; integration on pre-commit; E2E on CI pipeline.

---

## Test Levels and Infrastructure

| Level | Infrastructure required | When to use |
|-------|------------------------|-------------|
| **Unit** | None — Node.js + fakes | Pure logic, domain services, use-cases |
| **Integration** | Real DB (testcontainers) or real HTTP | Repository implementations, HTTP adapters |
| **E2E** | Full stack + external services | Critical user journeys only |

---

## Fakes Over Mocks

Fakes are real (simplified) implementations of an interface. They:
- Compile-check against the interface — safe to refactor
- Contain no framework magic — easy to reason about
- Are reusable across tests

```typescript
// ✅ Correct: in-memory fake
// tests/fakes/InMemoryEventBus.ts
import type { EventBus, DomainEvent } from "@domain/ports/EventBus";

export class InMemoryEventBus implements EventBus {
  readonly published: DomainEvent[] = [];

  async publish(event: DomainEvent): Promise<void> {
    this.published.push(event);
  }

  // Test helper
  lastEvent<T extends DomainEvent>(type: string): T | undefined {
    return [...this.published].reverse().find((e) => e.type === type) as T | undefined;
  }
}

// ❌ WRONG: vi.mock for dependency injection
vi.mock("@domain/ports/EventBus", () => ({
  EventBus: vi.fn().mockImplementation(() => ({ publish: vi.fn() })),
}));
```

`vi.fn()` is allowed only for:
- Callbacks / event listeners passed inline
- `vi.useFakeTimers()` / `vi.setSystemTime()`
- Spying on calls **without replacing behaviour** (`vi.spyOn`)

---

## Parametrised Tests

```typescript
import { describe, it, expect } from "vitest";
import { parseAmount } from "./parseAmount";

describe("parseAmount", () => {
  it.each([
    ["1.00",  100],
    ["0.01",    1],
    ["100.00", 10000],
    ["-1.00",  -100],
  ])("GIVEN %s WHEN parsing THEN returns %i cents", (input, expected) => {
    expect(parseAmount(input)).toBe(expected);
  });

  it.each([
    ["",        "empty string"],
    ["abc",     "non-numeric"],
    ["1.2.3",   "multiple decimals"],
  ])("GIVEN %s (%s) WHEN parsing THEN throws", (input) => {
    expect(() => parseAmount(input)).toThrow();
  });
});
```

---

## Async Test Patterns

```typescript
describe("UserService.createUser", () => {
  it("GIVEN network failure WHEN creating THEN propagates error", async () => {
    // Arrange — fake that throws
    const failingRepo: UserRepository = {
      findByEmail: vi.fn().mockRejectedValue(new Error("DB down")),
      save: vi.fn(),
      findById: vi.fn(),
      delete: vi.fn(),
    };
    const service = new UserService(failingRepo, new InMemoryEventBus());

    // Act + Assert
    await expect(
      service.createUser({ name: "Alice", email: "a@a.com", role: "user" }),
    ).rejects.toThrow("DB down");
  });

  it("GIVEN slow dependency WHEN timeout exceeded THEN rejects with TimeoutError", async () => {
    vi.useFakeTimers();

    const slowRepo = new SlowInMemoryRepo(5000);  // 5 s delay
    const service  = new UserService(slowRepo, new InMemoryEventBus(), { timeoutMs: 1000 });

    const promise = service.createUser({ name: "B", email: "b@b.com", role: "user" });
    vi.advanceTimersByTime(1500);

    await expect(promise).rejects.toThrow("timeout");
    vi.useRealTimers();
  });
});
```

---

## Test Organisation for Debuggability

```typescript
describe("<ClassName>", () => {
  describe("<methodName>", () => {
    describe("happy path", () => {
      it("GIVEN ... WHEN ... THEN ...", () => { ... });
    });
    describe("error cases", () => {
      it("GIVEN ... WHEN ... THEN throws ...", () => { ... });
    });
  });
});
```

When a test fails, the output should read as a sentence:
`UserService > createUser > error cases > GIVEN duplicate email WHEN creating THEN throws ConflictError`

---

## Test Fixtures and Builders

```typescript
// tests/fixtures/users.ts
import { faker } from "@faker-js/faker";
import type { User } from "@domain";

export function makeUser(overrides: Partial<User> = {}): User {
  return {
    id:        faker.string.uuid(),
    name:      faker.person.fullName(),
    email:     faker.internet.email(),
    role:      "user",
    createdAt: new Date(),
    ...overrides,
  };
}

// Usage
const admin = makeUser({ role: "admin" });
const alice = makeUser({ email: "alice@example.com" });
```

---

## Integration Tests with Testcontainers

```typescript
import { PostgreSqlContainer } from "@testcontainers/postgresql";
import { PgUserRepository }    from "@infra/db/PgUserRepository";

describe("PgUserRepository (integration)", () => {
  let container: StartedPostgreSqlContainer;
  let repo: PgUserRepository;

  beforeAll(async () => {
    container = await new PostgreSqlContainer("postgres:16").start();
    const pool = createPool(container.getConnectionUri());
    await runMigrations(pool);
    repo = new PgUserRepository(pool);
  }, 30_000);

  afterAll(() => container.stop());

  it("GIVEN saved user WHEN finding by email THEN returns it", async () => {
    const user = await repo.save(makeUser());
    const found = await repo.findByEmail(user.email);
    expect(found).toEqual(user);
  });
});
```

---

## TDD for Bug Fixes

```
1. Write a failing test that reproduces the bug exactly.
   The test name should describe the observable defect.

2. Run it — confirm it reproduces the failure.

3. Fix the code.

4. Run all tests — confirm green with no regressions.

5. Commit: fix(<scope>): <what was broken and is now correct>
```

Never fix a bug without a test that would have caught it.

---

## Test Graduation Workflow

Start tests at the lowest level that gives confidence:

```
Unit test  →  passes?  →  stop here if no I/O involved
     ↓
Integration test  →  passes?  →  stop here for most cases
     ↓
E2E test  →  only for critical user journeys
```

Resist the urge to write E2E tests for logic that can be covered by unit tests.
E2E tests are 10–100× slower and 10× harder to maintain.

---

## Coverage Gates

| Metric | Threshold | Enforced by |
|--------|-----------|-------------|
| Lines | ≥ 80% | `vitest --coverage` thresholds |
| Functions | ≥ 80% | vitest.config.ts |
| Branches | ≥ 80% | vitest.config.ts |
| Statements | ≥ 80% | vitest.config.ts |

Coverage is a **floor**, not a target. 80% with meaningful assertions is worth more than
100% with trivial ones. Every branch in domain logic must be exercised.

---

## What to Test

```typescript
// ✅ Test behaviour (observable outputs and side effects)
expect(user.role).toBe("admin");
expect(eventBus.published).toHaveLength(1);
expect(eventBus.published[0].type).toBe("UserCreated");

// ❌ Do not test implementation details
expect(vi.mocked(someInternalHelper)).toHaveBeenCalledWith(...)  // fragile
expect(service["_cache"].size).toBe(1)  // accesses private field
```

If you can refactor a function's internals without changing tests, the tests are at the right level.

---

## Quick Reference

```bash
# Run tests in watch mode during development
npx vitest

# Run once with coverage
npx vitest run --coverage

# Run a specific file
npx vitest run src/users/UserService.test.ts

# Run tests matching a pattern
npx vitest run --grep "createUser"

# Type check only (no emit)
npx tsc --noEmit
```
