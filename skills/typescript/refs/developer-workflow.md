# TypeScript Developer Workflow (Detailed)

Day-to-day implementation guide for TypeScript. Enforces TDD, strict types, and zero-compromise quality gates.

---

## First Principles

1. **Write the failing test first** — no implementation without a red test
2. **Strict types, zero `any`** — every `any` is a bug waiting to happen
3. **Behaviour, not implementation** — tests prove what, not how
4. **Self-verify before declaring done** — run the full quality suite yourself
5. **Small commits, conventional messages** — one logical change per commit

---

## TDD Cycle — Red → Green → Refactor

```
RED    Write a failing test that describes the behaviour you need
         └─ Run: npx vitest run — confirm it fails with the right reason
GREEN  Write the minimum code to make the test pass
         └─ Run: npx vitest run — confirm green
REFACTOR Remove duplication, improve names, extract abstractions
         └─ Run: npx vitest run — confirm still green
COMMIT commit with a conventional message
```

**Rule**: never write implementation code without a failing test.
**Rule**: never commit a test that is not yet failing (you haven't started the cycle).

---

## Vitest Patterns

### Test File Naming and Location

```
src/
├── users/
│   ├── UserService.ts
│   └── UserService.test.ts     ← co-located unit tests
tests/
├── integration/
│   └── users.integration.test.ts
└── e2e/
    └── auth.e2e.test.ts
```

### AAA Structure — Given / When / Then

```typescript
import { describe, it, expect, beforeEach } from "vitest";
import { UserService } from "./UserService";
import { InMemoryUserRepo } from "@test/fakes/InMemoryUserRepo";

describe("UserService", () => {
  let repo: InMemoryUserRepo;
  let service: UserService;

  beforeEach(() => {
    repo    = new InMemoryUserRepo();
    service = new UserService(repo);
  });

  describe("createUser", () => {
    it("GIVEN valid data WHEN creating THEN saves and returns user", async () => {
      // Arrange
      const cmd = { name: "Alice", email: "alice@example.com", role: "user" as const };

      // Act
      const user = await service.createUser(cmd);

      // Assert
      expect(user.id).toBeDefined();
      expect(user.email).toBe("alice@example.com");
      expect(await repo.findById(user.id)).toEqual(user);
    });

    it("GIVEN duplicate email WHEN creating THEN throws ConflictError", async () => {
      await repo.save(makeUser({ email: "alice@example.com" }));

      await expect(
        service.createUser({ name: "Alice2", email: "alice@example.com", role: "user" }),
      ).rejects.toThrow("alice@example.com");
    });
  });
});
```

### Test Naming Convention

```
GIVEN <precondition> WHEN <action> THEN <expected outcome>
```

Use `describe` blocks to group by class/function, nested `describe` for method/scenario.

---

## Dependency Injection in Tests (No Mocking Frameworks)

```typescript
// ✅ Correct: inject a real in-memory fake
// tests/fakes/InMemoryUserRepo.ts
import type { UserRepository } from "@domain/ports/UserRepository";
import type { User, UserId } from "@domain";

export class InMemoryUserRepo implements UserRepository {
  private store = new Map<string, User>();

  async findById(id: UserId): Promise<User | null> {
    return this.store.get(id) ?? null;
  }

  async findByEmail(email: string): Promise<User | null> {
    return [...this.store.values()].find((u) => u.email === email) ?? null;
  }

  async save(user: User): Promise<User> {
    this.store.set(user.id, user);
    return user;
  }

  async delete(id: UserId): Promise<void> {
    this.store.delete(id);
  }

  // Test helper — not on the interface
  seedMany(users: User[]): void {
    for (const u of users) this.store.set(u.id, u);
  }
}
```

```typescript
// ❌ FORBIDDEN: vi.mock() for dependency injection
vi.mock("../UserRepository", () => ({
  UserRepository: vi.fn().mockImplementation(() => ({ findById: vi.fn() })),
}));

// ✅ REQUIRED: inject the fake
const repo    = new InMemoryUserRepo();
const service = new UserService(repo);
```

`vi.mock()` is permitted **only** for:
- Mocking time (`vi.useFakeTimers()`)
- Mocking environment variables
- Mocking native modules with no injectable alternative

---

## Type Safety Rules

```typescript
// NEVER: any
const data: any = response.json();   // ❌
const data: unknown = response.json();  // ✅ — narrow before use

// NEVER: non-null assertion on uncertain values
const user = maybeUser!;    // ❌
const user = maybeUser ?? throwError("User required");  // ✅

// NEVER: @ts-ignore (treat as compile error)
// @ts-ignore
const x = brokenCode();     // ❌
// If genuinely needed: @ts-expect-error with explanation — and fix it ASAP

// NEVER: type assertion to bypass checking
const user = {} as User;    // ❌
// ✅ validate at boundaries with Zod or a guard function

// ALWAYS: annotate function return types explicitly
function getUser(id: string) { ... }          // ❌ return type inferred
function getUser(id: string): Promise<User>   // ✅ explicit contract
```

---

## Vitest Configuration

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";
import tsconfigPaths    from "vite-tsconfig-paths";

export default defineConfig({
  plugins: [tsconfigPaths()],
  test: {
    globals:     false,           // explicit imports — no implicit globals
    environment: "node",
    coverage: {
      provider:          "v8",
      reporter:          ["text", "lcov"],
      thresholds: {
        lines:     80,
        functions: 80,
        branches:  80,
        statements: 80,
      },
      exclude: ["tests/**", "**/*.test.ts", "src/**/index.ts"],
    },
    include: ["src/**/*.test.ts", "tests/**/*.test.ts"],
  },
});
```

---

## Toolchain — Run Order

Run in this exact sequence before every commit:

```bash
# 1. Type check (fails fast on type errors)
npx tsc --noEmit

# 2. Lint (catches style and pattern violations)
npx eslint src/ tests/ --fix

# 3. Format
npx prettier --write src/ tests/

# 4. Tests with coverage
npx vitest run --coverage

# 5. Verify coverage thresholds met
#    (vitest exits non-zero if below threshold)
```

One-liner for pre-commit:
```bash
npx tsc --noEmit && npx eslint src/ tests/ --fix && npx prettier --write src/ tests/ && npx vitest run --coverage
```

---

## ESLint Configuration (flat config, ESLint 9)

```typescript
// eslint.config.ts
import tsPlugin from "@typescript-eslint/eslint-plugin";
import tsParser from "@typescript-eslint/parser";

export default [
  {
    files: ["**/*.ts"],
    languageOptions: { parser: tsParser, parserOptions: { project: true } },
    plugins: { "@typescript-eslint": tsPlugin },
    rules: {
      ...tsPlugin.configs["strict-type-checked"].rules,
      "@typescript-eslint/no-explicit-any":        "error",
      "@typescript-eslint/explicit-function-return-type": "error",
      "@typescript-eslint/no-non-null-assertion":  "error",
      "@typescript-eslint/consistent-type-imports": ["error", { prefer: "type-imports" }],
      "no-console": "error",
    },
  },
];
```

---

## Structured Logging (never `console.log`)

```typescript
import { logger } from "@shared/logger";

// ✅ Structured — machine-parseable
logger.info({ userId, action: "user.created" }, "User created");
logger.error({ err, requestId }, "Failed to create user");

// ❌ Unstructured — never in library/service code
console.log("User created:", userId);
```

---

## Conventional Commits

```
feat: add user email verification
fix(auth): handle expired tokens on refresh
refactor(users): extract email validation to domain service
test: add coverage for ConflictError path in UserService
chore: update vitest to 3.x
```

- `feat`: new behaviour visible to users or callers
- `fix`: bug fix
- `refactor`: code change that doesn't add feature or fix bug
- `test`: adding or fixing tests
- `chore`: tooling, deps, CI

**Never** mention TDD phases in commit messages — commit messages describe what was built.

---

## Code Style Conventions

```typescript
// ✅ Type-only imports
import type { User } from "@domain";
import { createUser } from "@domain";

// ✅ Path aliases (configured in tsconfig.json)
import { logger } from "@shared/logger";
// ❌ Deep relative imports
import { logger } from "../../../shared/logger";

// ✅ Readonly parameters where not mutated
function format(user: Readonly<User>): string {
  return `${user.name} <${user.email}>`;
}

// ✅ Explicit void for fire-and-forget
void sendWelcomeEmail(user.email);

// ✅ const assertion for literal arrays/objects
const ALLOWED_ROLES = ["admin", "user"] as const;
type Role = typeof ALLOWED_ROLES[number];

// ✅ Assertion function (never silent nulls)
function assertDefined<T>(value: T | null | undefined, label: string): asserts value is T {
  if (value == null) throw new Error(`Expected ${label} to be defined`);
}
```

---

## Before Opening a PR — Checklist

```
tsc --noEmit           ← zero errors
eslint src/ tests/     ← zero errors (--fix applied)
prettier --check       ← zero formatting issues
vitest run --coverage  ← 100% pass, ≥80% coverage
git diff               ← no debug code, no console.log, no TODO
```

Success criteria:

- [ ] All functions have explicit return type annotations
- [ ] All public functions have JSDoc
- [ ] Tests prove behaviour, not implementation
- [ ] No `any`, no `!`, no `@ts-ignore`
- [ ] No hardcoded secrets
- [ ] No deep relative imports
- [ ] Coverage ≥ 80% on new code
- [ ] Conventional commit message

---

## Two Modes

Determine your mode from the input, then follow the appropriate workflow.

| Input                            | Mode               | Workflow                            |
| -------------------------------- | ------------------ | ----------------------------------- |
| Spec (TRD, ADR, design doc)      | **Implementation** | `workflow-implementation.md`        |
| Rejection feedback from reviewer | **Remediation**    | `workflow-remediation.md`           |

### Implementation Mode

**Spec Is Law.** Implement exactly what the specification says. Before writing any code:

1. Read the specification completely
2. Identify deliverables, interfaces, edge cases, and test scenarios
3. Write failing tests first (red phase), then implement (green), then refactor
4. Self-verify with the full toolchain before declaring done

### Remediation Mode

When input is rejection feedback from a reviewer:

1. Parse the rejection — categorise issues as Blocking / Conditional / Warning
2. Understand root cause before fixing (5 type errors from one bad return type = fix the return type)
3. Plan non-trivial fixes in writing before applying them
4. Add missing tests for every bug the reviewer caught
5. Run the full toolchain (`tsc`, `eslint`, `vitest --coverage`) — all must pass
6. Submit a structured re-review summary

---

## Path Alias Depth Rules

Before writing any import, ask: *"Is this module-internal (same module, moves together) or shared infrastructure?"*

```typescript
// ✅ OK — sibling in the same module
import { validateEmail } from "./validators";

// ⚠️ Review — is this truly module-internal?
import { helper } from "../utils";

// ❌ REJECT — use a path alias instead
import { helper } from "../../../../../../tests/helpers/tree-builder";
import { Logger } from "../../../../lib/logging";
import { Config } from "../../../shared/config";

// ✅ Correct — configure path aliases in tsconfig.json
import { Logger } from "@lib/logging";
import { Config } from "@shared/config";
import { helper } from "@test/helpers/tree-builder";
```

**Depth rules:**

| Depth          | Rule                                          |
| -------------- | --------------------------------------------- |
| `./sibling`    | ✅ OK — same directory, module-internal        |
| `../parent`    | ⚠️ Review — is it truly module-internal?      |
| `../../` deeper | ❌ REJECT — configure and use a path alias   |

**Configure `tsconfig.json`:**

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/*":     ["src/*"],
      "@test/*": ["tests/*"],
      "@lib/*":  ["lib/*"]
    }
  }
}
```

---

## Additional Dependency Injection Patterns

DI via a typed deps object — use this pattern for any function that needs external collaborators:

```typescript
// ✅ Dependencies as a typed interface
export interface SyncDependencies {
  execa: typeof execa;
  logger: Logger;
}

export async function syncFiles(
  source: string,
  dest: string,
  deps: SyncDependencies,
): Promise<SyncResult> {
  deps.logger.info(`Syncing ${source} to ${dest}`);
  // ...
}

// ❌ Hidden dependency — never do this
async function syncFiles(source: string, dest: string): Promise<SyncResult> {
  const logger = getLogger(); // invisible coupling
}
```

In tests, inject a fake or a `vi.fn()` stub **only on the function slot**, not via `vi.mock()`:

```typescript
it("GIVEN valid args WHEN syncing THEN calls execa once", async () => {
  const deps: SyncDependencies = {
    execa: vi.fn().mockResolvedValue({ exitCode: 0 }),
    logger: createTestLogger(),
  };

  await syncFiles("/src", "/dst", deps);

  expect(deps.execa).toHaveBeenCalledOnce();
});
```

---

## Reference Files

| File                              | Purpose                                          |
| --------------------------------- | ------------------------------------------------ |
| `code-patterns.md`               | Subprocess execution, resource cleanup, Zod config, typed errors |
| `test-patterns.md`               | Debuggability-first 4-part test progression      |
| `verification-checklist.md`      | Full pre-submission checklist with tool commands |
| `workflow-implementation.md`     | Phase-by-phase implementation protocol (TDD)     |
| `workflow-remediation.md`        | Phase-by-phase remediation protocol (fixes)      |
