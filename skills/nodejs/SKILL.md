# Skill: Node.js

**Runtime**: Node 22 LTS | **Modules**: ES Modules only | **Frameworks**: Fastify v5, NestJS v10+

> Unified Node.js skill covering core platform fundamentals, Fastify (performance-oriented HTTP), and NestJS (enterprise DI framework). Detailed references live in `refs/`.

---

## Core Platform

**Full reference**: `refs/core-platform.md`

### Key Concepts

- **Event loop phases**: timers, pending I/O, poll, check, close. Microtask queue (nextTick, then Promises) runs between every phase.
- **ES Modules only**: `"type": "module"` in package.json. No `require()`, no `__dirname`. Use `import.meta.url`.
- **Built-in fetch**: global `fetch` + `AbortSignal.timeout()`. No `node-fetch` needed.
- **Built-in test runner**: `node:test` + `node:assert/strict`. Run with `--experimental-test-coverage`.
- **Streams**: always use `stream.pipeline()` from `node:stream/promises`. Respect backpressure.
- **Worker threads**: offload CPU-bound work. Use `cluster` only for HTTP load distribution.
- **AsyncLocalStorage**: propagate trace/request context through async call chains without parameter threading.
- **diagnostics_channel**: publish structured observability events without coupling to specific telemetry libraries.

### Error Handling

```js
export class AppError extends Error {
  constructor(message, context = {}) {
    super(message);
    this.name = this.constructor.name;
    this.context = context;
    Error.captureStackTrace(this, this.constructor);
  }
}
```

Register `unhandledRejection` and `uncaughtException` handlers in the entry point only. Never call `process.exit()` in library code.

### Security Essentials

- No `eval()` or `new Function(string)`
- No `child_process.exec(userInput)` -- use `execFile` with argument arrays
- Guard against path traversal with `path.resolve()` + prefix check
- Lock dependencies with `pnpm.lock`; run `npm audit` in CI

---

## Fastify v5

**Full reference**: `refs/fastify.md`

### Architecture

Fastify uses an **encapsulated plugin system**. Use `fastify-plugin` (`fp()`) to break scope boundaries and share decorators across the application.

```ts
import fp from 'fastify-plugin';
export default fp(myPlugin, { name: 'my-plugin', dependencies: ['config'] });
```

### Hook Lifecycle (per request)

```
onRequest -> preParsing -> preValidation -> preHandler -> handler
  -> preSerialization -> onSend -> onResponse
```

### Schema-First Design

Define JSON schemas on every route for:
1. Input validation (Ajv) -- rejects bad requests before handler runs
2. Output serialisation (fast-json-stringify) -- 2-10x faster than `JSON.stringify`
3. OpenAPI generation (`@fastify/swagger`)

Use **TypeBox** (`@sinclair/typebox`) for single-source-of-truth schemas that produce both JSON Schema and TypeScript types.

### Testing

Use `fastify.inject()` for in-process testing -- no real TCP sockets:

```ts
const response = await app.inject({ method: 'POST', url: '/users', payload: { ... } });
assert.equal(response.statusCode, 201);
```

### Key Rules

| Rule | Detail |
|------|--------|
| Export `fp()` from plugins | Ensures cross-scope decoration |
| `additionalProperties: false` | On all request body schemas |
| Use `request.log` / `fastify.log` | Never `console.log` |
| Typed errors via `@fastify/error` | Never throw plain `Error` |

---

## NestJS v10+

**Full reference**: `refs/nestjs.md`

### Architecture

Feature modules as vertical slices: module, controller, service, DTOs, guards, specs. Each module wires DI via `@Module()`.

```ts
@Module({
  imports: [PrismaModule],
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}
```

### Dependency Injection

Constructor injection with `@Injectable()`. Custom providers: `useValue`, `useFactory`, `useClass`. Never instantiate services directly.

### Validation

Global `ValidationPipe` with `whitelist: true` + `forbidNonWhitelisted: true`. DTOs use `class-validator` decorators. Response DTOs use `@Exclude()` / `@Expose()` to prevent leaking internal fields.

### ORM: Prisma

`PrismaService extends PrismaClient` with `OnModuleInit` / `OnModuleDestroy`. Use interactive `$transaction()` for complex atomic operations.

### Testing

```ts
const module = await Test.createTestingModule({
  providers: [UsersService, { provide: PrismaService, useValue: mockPrisma }],
}).compile();
```

E2E tests with Supertest against `app.getHttpServer()`.

### Key Rules

| Rule | Detail |
|------|--------|
| No `process.env` in services | Inject `ConfigService`; use `getOrThrow` |
| No `any` | TypeScript strict; use `unknown` + narrowing |
| Readonly DTO properties | All fields marked `readonly` |
| `whitelist: true` globally | ValidationPipe strips unknown fields |
| `HttpException` subclasses only | Never throw plain `Error` |

---

## Observability

Both frameworks integrate with **Pino** for structured logging and **OpenTelemetry** for distributed tracing.

- **Fastify**: Pino is built in. Use `request.log` for automatic `reqId` correlation.
- **NestJS**: Use `nestjs-pino` + `TracingInterceptor` with `@opentelemetry/api`.
- **Core**: Use `node:diagnostics_channel` for decoupled event publishing. Use `AsyncLocalStorage` for trace context propagation.

---

## Quality Gates

| Gate | Tool | Threshold |
|------|------|-----------|
| Node version | `scripts/check.sh` | >= 22 |
| Tests | `node:test` / Vitest / Jest | pass |
| Coverage | `--experimental-test-coverage` | >= 80% |
| Lint | ESLint 9 flat config | 0 warnings |
| Types | `tsc --noEmit` | 0 errors |
| Security | `npm audit` | no high/critical |

---

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/check.sh` | Node.js quality gate (version, tests, lint, types) |
| `scripts/scaffold-fastify.sh <name>` | Generate Fastify plugin with routes, schemas, tests |
| `scripts/scaffold-nestjs.sh <name>` | Generate NestJS module with controller, service, DTOs, specs |

## Templates

| Template | Purpose |
|----------|---------|
| `templates/main.js` | Node.js HTTP server with structured logging, routing, graceful shutdown |
| `templates/package.json` | Node 22 project scaffold with ESM, pnpm, test scripts |
| `templates/fastify-app.ts` | Fastify application with security plugins, JWT auth, error handling |
| `templates/fastify-plugin.ts` | Fastify TypeBox plugin with CRUD routes and service interface |
| `templates/nestjs-module.ts` | NestJS feature module with controller, service, DTOs, tests |
| `templates/nestjs-prisma.service.ts` | PrismaService with lifecycle hooks, transactions, health check |
