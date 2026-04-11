# TypeScript Architect (Detailed)

Enterprise-grade TypeScript system design. Apply before implementation begins on any feature touching
more than two modules or introducing a new abstraction.

---

## 12-Factor Application (TypeScript Edition)

| Factor | Implementation |
|--------|---------------|
| **Config** | `process.env.*`; fail-fast if required vars absent; never commit `.env` |
| **Dependencies** | `package.json` + lock file; no peer-dep hacks |
| **Backing services** | Injected via interfaces; swappable without code changes |
| **Processes** | Stateless; share nothing between requests |
| **Port binding** | App exports its server; port is config |
| **Concurrency** | Scale by running more instances |
| **Disposability** | Graceful shutdown: drain in-flight, close DB connections |
| **Logs** | `stdout` only; structured JSON; never write log files |

---

## Layered Architecture

```
src/
├── domain/          # Pure business logic — no framework imports
│   ├── entities/    # Value objects, aggregates
│   ├── services/    # Domain services (pure functions preferred)
│   └── errors.ts    # Domain error hierarchy
│
├── application/     # Use-cases / commands / queries
│   ├── commands/    # Write operations (CreateUser, DeleteOrder …)
│   ├── queries/     # Read operations (GetUser, ListOrders …)
│   └── ports/       # Interfaces the application depends on
│
├── infrastructure/  # Adapters: DB, HTTP clients, message brokers
│   ├── db/
│   ├── http/
│   └── messaging/
│
├── interface/       # Delivery mechanism: REST, CLI, GraphQL, workers
│   ├── http/
│   └── cli/
│
└── shared/          # Cross-cutting: logger, config, result type
```

**Dependency rule**: inner layers never import from outer layers.

```
domain ← application ← infrastructure ← interface
```

Enforce with ESLint `import/no-restricted-paths` or architectural fitness functions.

---

## Dependency Injection

### Interface-First Design

```typescript
// domain/ports/UserRepository.ts
export interface UserRepository {
  findById(id: UserId): Promise<User | null>;
  findByEmail(email: string): Promise<User | null>;
  save(user: User): Promise<User>;
  delete(id: UserId): Promise<void>;
}

// application/commands/CreateUser.ts
export class CreateUserHandler {
  constructor(
    private readonly users: UserRepository,
    private readonly events: EventBus,
    private readonly clock: Clock,
  ) {}

  async execute(cmd: CreateUserCommand): Promise<User> {
    const existing = await this.users.findByEmail(cmd.email);
    if (existing) throw new EmailTakenError(cmd.email);

    const user = User.create(cmd, this.clock.now());
    await this.users.save(user);
    await this.events.publish(new UserCreatedEvent(user));
    return user;
  }
}
```

### Composition Root

```typescript
// src/bootstrap.ts — assemble the entire dependency graph here
import { PgUserRepository } from "@infra/db/PgUserRepository";
import { RabbitEventBus }   from "@infra/messaging/RabbitEventBus";
import { SystemClock }      from "@shared/SystemClock";
import { CreateUserHandler } from "@app/commands/CreateUser";

export function buildContainer(env: Env) {
  const db     = new PgPool({ connectionString: env.DATABASE_URL });
  const rabbit = new RabbitMQ(env.AMQP_URL);

  const users  = new PgUserRepository(db);
  const events = new RabbitEventBus(rabbit);
  const clock  = new SystemClock();

  return {
    createUser: new CreateUserHandler(users, events, clock),
    // ...
  };
}
```

**Never** use `new` inside domain or application layer — only in the composition root.

---

## Configuration Pattern

```typescript
// src/shared/config.ts
import { z } from "zod";

const EnvSchema = z.object({
  NODE_ENV:     z.enum(["development", "test", "production"]),
  DATABASE_URL: z.string().url(),
  PORT:         z.coerce.number().int().positive().default(3000),
  LOG_LEVEL:    z.enum(["debug", "info", "warn", "error"]).default("info"),
  API_KEY:      z.string().min(32),
});

export type Env = z.infer<typeof EnvSchema>;

export function loadEnv(): Env {
  const result = EnvSchema.safeParse(process.env);
  if (!result.success) {
    console.error("Invalid environment:", result.error.flatten());
    process.exit(1);  // fail-fast — never start with bad config
  }
  return result.data;
}
```

---

## Error Strategy

### Domain Error Hierarchy

```typescript
// src/domain/errors.ts
export class DomainError extends Error {
  constructor(
    message: string,
    public readonly code: string,
  ) {
    super(message);
    this.name = this.constructor.name;
    Error.captureStackTrace(this, this.constructor);
  }
}

export class NotFoundError extends DomainError {
  constructor(entity: string, id: string) {
    super(`${entity} not found: ${id}`, "NOT_FOUND");
  }
}

export class ConflictError extends DomainError {
  constructor(message: string) {
    super(message, "CONFLICT");
  }
}

export class ValidationError extends DomainError {
  constructor(
    message: string,
    public readonly fields: Record<string, string[]>,
  ) {
    super(message, "VALIDATION");
  }
}
```

### HTTP Error Mapping (interface layer only)

```typescript
// src/interface/http/errorHandler.ts
function toHttpStatus(err: unknown): number {
  if (err instanceof NotFoundError)   return 404;
  if (err instanceof ConflictError)   return 409;
  if (err instanceof ValidationError) return 422;
  if (err instanceof DomainError)     return 400;
  return 500;
}

// RFC 9457 Problem Details
function toProblemDetail(err: unknown, requestId: string): ProblemDetail {
  const status = toHttpStatus(err);
  if (err instanceof DomainError) {
    return { type: `/errors/${err.code}`, title: err.message, status, requestId };
  }
  return { type: "/errors/INTERNAL", title: "Internal server error", status, requestId };
}
```

---

## Module Boundary Rules

```typescript
// Each module exposes a public API via its index.ts
// src/domain/index.ts
export type { User, UserId, UserRole } from "./entities/User";
export type { UserRepository }         from "./ports/UserRepository";
export { DomainError, NotFoundError }  from "./errors";

// ✅ External modules import from the index
import type { User } from "@domain";

// ❌ Reaching inside another module's internals
import { PgUserRepository } from "@infra/db/PgUserRepository";  // from app layer — NO
```

Enforce with ESLint `import/no-internal-modules` rule.

---

## Observability (OpenTelemetry)

```typescript
import { trace, metrics, SpanStatusCode } from "@opentelemetry/api";

const tracer  = trace.getTracer("my-service", "1.0.0");
const meter   = metrics.getMeter("my-service", "1.0.0");
const counter = meter.createCounter("users.created");

export class CreateUserHandler {
  async execute(cmd: CreateUserCommand): Promise<User> {
    return tracer.startActiveSpan("CreateUser", async (span) => {
      span.setAttributes({
        "user.email": cmd.email,
        "user.role":  cmd.role,
      });
      try {
        const user = await this.doExecute(cmd);
        counter.add(1, { role: user.role });
        return user;
      } catch (err) {
        span.recordException(err as Error);
        span.setStatus({ code: SpanStatusCode.ERROR });
        throw err;
      } finally {
        span.end();
      }
    });
  }
}
```

**Rules**:
- Every public use-case/command/query gets a span
- Never log PII in span attributes
- Use semantic conventions: `http.method`, `db.statement`, `messaging.destination`
- Metrics naming: `<service>.<entity>.<operation>` (counters, histograms)

---

## Structured Logging

```typescript
import pino from "pino";

export const logger = pino({
  level: process.env.LOG_LEVEL ?? "info",
  base: { service: "my-service" },
  timestamp: pino.stdTimeFunctions.isoTime,
});

// Usage — always structured, never concatenation
logger.info({ userId, action: "user.created" }, "User created");
logger.error({ err, requestId }, "Request failed");

// ❌ NEVER
console.log("User created: " + userId);
logger.info("User " + userId + " created");
```

---

## Async Strategy

| Scenario | Pattern |
|----------|---------|
| Sequential steps | `async/await` chain |
| Independent parallel ops | `Promise.all([...])` |
| Fan-out with partial failure tolerance | `Promise.allSettled([...])` |
| Stream processing | `AsyncGenerator` + `for await` |
| Rate-limited I/O | `p-limit` or `async-pool` |
| Event-driven | Node `EventEmitter` or message broker |

```typescript
// Parallel with failure isolation
const results = await Promise.allSettled([
  fetchUsers(),
  fetchOrders(),
  fetchProducts(),
]);

for (const result of results) {
  if (result.status === "rejected") {
    logger.warn({ err: result.reason }, "Partial failure");
  }
}
```

---

## Security Baseline

- **Secrets**: environment variables only; fail-fast if absent; never log
- **Input validation**: validate at the boundary (Zod schema) before entering domain
- **SQL**: parameterised queries only — never template strings
- **HTTP headers**: `helmet` defaults + explicit CSP
- **Dependencies**: `npm audit` before every MR; zero HIGH/CRITICAL CVEs
- **Secrets scanning**: `gitleaks` in pre-commit and CI
- **Auth**: JWT verification in middleware, not in use-cases

---

## Technology Stack Defaults

| Concern | Default | Alternative |
|---------|---------|-------------|
| Runtime | Node.js 22 LTS | Deno, Bun |
| Package manager | pnpm 9 | npm |
| Bundler | Vite 7 / tsup | esbuild |
| HTTP framework | Fastify | Express, Hono |
| Validation | Zod | io-ts, Yup |
| ORM | Drizzle | Prisma |
| Testing | Vitest | Jest |
| Lint + format | ESLint 9 flat config + Prettier | Biome |
| Type check | tsc (strict) | — |
| Observability | OpenTelemetry SDK | — |
| Containerisation | Docker + multi-stage | — |

---

## Design Checklist (before coding)

- [ ] Module boundaries defined — what is public, what is internal
- [ ] Dependencies flow inward — domain has zero framework imports
- [ ] All external deps injected via interfaces
- [ ] Config validated at startup with fail-fast
- [ ] Error hierarchy documented
- [ ] OTel spans on every use-case
- [ ] No secrets in source code or logs
- [ ] Parameterised queries for every DB call
- [ ] Input validated at boundary (Zod)
- [ ] Graceful shutdown handler registered
