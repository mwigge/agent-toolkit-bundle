# Fastify v5 -- Detailed Reference

**Runtime**: Node 22 LTS | **Framework**: Fastify v5 | **Language**: TypeScript 5+

---

## 1. Plugin Architecture

### fastify-plugin (`fp()`)

By default, Fastify's plugin system creates an encapsulated scope. Decorators, hooks, and routes registered inside a plugin are **not** visible to parent or sibling scopes. Use `fp()` to break encapsulation and share across the application:

```ts
import fp from 'fastify-plugin';
import type { FastifyPluginAsync } from 'fastify';

const dbPlugin: FastifyPluginAsync = async (fastify) => {
  const pool = createPool(fastify.config.databaseUrl);
  fastify.decorate('db', pool);
  fastify.addHook('onClose', async () => pool.end());
};

export default fp(dbPlugin, {
  name: 'db',
  dependencies: ['config'], // ensures 'config' plugin is registered first
});
```

Without `fp()`, `fastify.db` would only exist inside that plugin's scope.

### register()

Plugins are always async. Use `await fastify.register()` when order matters:

```ts
await fastify.register(import('./plugins/config.js'));
await fastify.register(import('./plugins/db.js'));
await fastify.register(import('./routes/users.js'), { prefix: '/api/v1/users' });
```

### decorate() / decorateRequest() / decorateReply()

```ts
// Application-wide decoration
fastify.decorate('config', configObject);

// Per-request decoration (must provide initial value for performance)
fastify.decorateRequest('user', null);

// Per-reply decoration
fastify.decorateReply('sendError', function (statusCode: number, message: string) {
  this.code(statusCode).send({ error: message });
});
```

**Rule**: Always provide an initial value to `decorateRequest` / `decorateReply`. Fastify uses it to pre-allocate the property on the prototype chain for V8 optimisation.

---

## 2. Hook Lifecycle

Full execution order per request:

```
onRequest          -> authentication, rate limiting (can abort with reply.send())
preParsing         -> modify raw request stream before body parsing
preValidation      -> modify parsed body/params/query before schema validation
preHandler         -> authorisation, modify request after validation
  -> handler       -> your route logic
preSerialization   -> transform reply payload before serialisation
onSend             -> modify serialised response before sending
onResponse         -> logging, metrics (response already sent -- cannot modify)

Error path:
onError            -> triggered when setErrorHandler sends a reply
onTimeout          -> triggered when connectionTimeout or keepAliveTimeout fires
onRequestAbort     -> triggered when client disconnects before response completes
```

```ts
fastify.addHook('onRequest', async (request, reply) => {
  const token = request.headers.authorization?.replace('Bearer ', '');
  if (!token) return reply.code(401).send({ error: 'Unauthorised' });
  request.user = await verifyToken(token);
});

fastify.addHook('onResponse', (request, reply, done) => {
  request.log.info({
    method: request.method,
    url: request.url,
    statusCode: reply.statusCode,
    durationMs: reply.elapsedTime,
  }, 'request completed');
  done();
});
```

---

## 3. Schema-First Design

### JSON Schema for Request/Response

Define schemas on every route. Fastify uses them for:
1. **Input validation** (via Ajv) -- rejects bad requests before your handler runs
2. **Output serialisation** (via fast-json-stringify) -- 2-10x faster than `JSON.stringify`
3. **Documentation** (OpenAPI generation with `@fastify/swagger`)

```ts
const createUserSchema = {
  body: {
    type: 'object',
    required: ['email', 'name'],
    additionalProperties: false,
    properties: {
      email: { type: 'string', format: 'email', maxLength: 254 },
      name: { type: 'string', minLength: 1, maxLength: 100 },
    },
  },
  response: {
    201: {
      type: 'object',
      properties: {
        id: { type: 'string', format: 'uuid' },
        email: { type: 'string' },
        name: { type: 'string' },
        createdAt: { type: 'string', format: 'date-time' },
      },
    },
  },
};

fastify.post('/users', { schema: createUserSchema }, createUserHandler);
```

### Ajv Strict Mode

Configure Ajv to reject unknown formats and enable all strict checks:

```ts
const fastify = Fastify({
  ajv: {
    customOptions: {
      strict: true,
      allErrors: false, // fail-fast on first error for performance
      coerceTypes: false, // never coerce types -- validate exactly what arrives
      useDefaults: true,
    },
  },
});
```

---

## 4. Pino Structured Logging

Fastify uses Pino natively. Every request gets a child logger with a unique `reqId`:

```ts
const fastify = Fastify({
  logger: {
    level: process.env.LOG_LEVEL ?? 'info',
    redact: {
      paths: ['req.headers.authorization', 'req.headers.cookie', 'body.password'],
      censor: '[REDACTED]',
    },
    serializers: {
      req(request) {
        return {
          method: request.method,
          url: request.url,
          remoteAddress: request.ip,
        };
      },
    },
  },
});

// In handlers -- use request.log for automatic reqId correlation
async function handler(request, reply) {
  request.log.info({ userId: request.user.id }, 'processing request');
  const result = await doWork();
  request.log.info({ resultCount: result.length }, 'work complete');
  return result;
}
```

**Never use `console.log`** -- always `request.log` inside handlers, `fastify.log` outside.

---

## 5. Error Handling

### setErrorHandler

Register a global error handler that normalises all errors to a consistent response shape:

```ts
import { createError, isHttpError } from '@fastify/error';

fastify.setErrorHandler((error, request, reply) => {
  request.log.error({ err: error }, 'request failed');

  if (isHttpError(error)) {
    return reply.code(error.statusCode).send({
      error: error.name,
      message: error.message,
      statusCode: error.statusCode,
    });
  }

  if (error.validation) {
    return reply.code(400).send({
      error: 'ValidationError',
      message: 'Request validation failed',
      statusCode: 400,
      details: error.validation,
    });
  }

  // Don't leak internal error details
  return reply.code(500).send({
    error: 'InternalServerError',
    message: 'An unexpected error occurred',
    statusCode: 500,
  });
});
```

### httpErrors

Create typed HTTP errors with `@fastify/error`:

```ts
import createError from '@fastify/error';

export const NotFoundError = createError('NOT_FOUND', '%s not found', 404);
export const ConflictError = createError('CONFLICT', '%s already exists', 409);

// In handlers:
throw new NotFoundError('User');   // -> 404 { error: 'NOT_FOUND', message: 'User not found' }
throw new ConflictError('Email');  // -> 409
```

---

## 6. Testing with @fastify/inject

Never start a real HTTP server in tests. Use `fastify.inject()` for in-process testing:

```ts
import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';

describe('POST /api/v1/users', () => {
  let app;

  before(async () => {
    app = await buildApp({ logger: false });
    await app.ready();
  });

  after(() => app.close());

  it('creates a user with valid payload', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/users',
      payload: { email: 'alice@example.com', name: 'Alice' },
    });

    assert.equal(response.statusCode, 201);
    const body = response.json();
    assert.match(body.id, /^[0-9a-f-]{36}$/);
    assert.equal(body.email, 'alice@example.com');
  });

  it('rejects missing email with 400', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/users',
      payload: { name: 'Alice' },
    });

    assert.equal(response.statusCode, 400);
  });
});
```

---

## 7. Performance

- Keep handlers async -- never use sync filesystem/crypto ops in hot paths
- Use `reply.raw` only as a last resort (bypasses serialisation, hooks, logging)
- Prefer streaming responses for large payloads (`reply.send(readable)`)
- Define response schemas -- `fast-json-stringify` is substantially faster than `JSON.stringify`
- Use `reply.type('application/json')` explicitly when not using schemas to skip content-type inference

```ts
// Streaming a large result set
fastify.get('/export', async (request, reply) => {
  const stream = db.queryStream('SELECT * FROM events ORDER BY created_at');
  reply.type('application/x-ndjson');
  return reply.send(stream.pipe(new NDJSONTransform()));
});
```

---

## 8. Security

Register security plugins early in plugin load order so they apply to all routes:

```ts
await fastify.register(import('@fastify/helmet'));
await fastify.register(import('@fastify/cors'), {
  origin: process.env.ALLOWED_ORIGINS?.split(',') ?? false,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  credentials: true,
});
await fastify.register(import('@fastify/rate-limit'), {
  max: 100,
  timeWindow: '1 minute',
  keyGenerator: (request) => request.user?.id ?? request.ip,
});
```

Additional rules:
- Always set `additionalProperties: false` on request body schemas
- Validate and sanitise path/query parameters -- never pass raw values to SQL
- Never log request bodies that may contain secrets -- use Pino `redact`

---

## 9. Authentication with @fastify/jwt + @fastify/auth

```ts
import fp from 'fastify-plugin';
import type { FastifyPluginAsync } from 'fastify';

const authPlugin: FastifyPluginAsync = async (fastify) => {
  await fastify.register(import('@fastify/jwt'), {
    secret: fastify.config.jwtSecret,
    sign: { expiresIn: '15m' },
  });

  fastify.decorate('authenticate', async function (request, reply) {
    await request.jwtVerify();
    // request.user is now populated by @fastify/jwt
  });

  fastify.decorate('requireRole', (role: string) =>
    async function (request, reply) {
      if (request.user.role !== role) {
        return reply.code(403).send({ error: 'Forbidden' });
      }
    }
  );
};

export default fp(authPlugin, { name: 'auth', dependencies: ['config'] });

// In route files:
fastify.get('/admin/stats', {
  onRequest: [fastify.authenticate, fastify.requireRole('admin')],
  handler: adminStatsHandler,
});
```

---

## 10. TypeScript: TypeBox + FastifyPluginAsyncTypebox

Use TypeBox to define schemas that are both JSON Schema (for Fastify) and TypeScript types (for your handlers) -- no duplication:

```ts
import { Type, type Static } from '@sinclair/typebox';
import { FastifyPluginAsyncTypebox } from '@fastify/type-provider-typebox';
import fp from 'fastify-plugin';

const CreateUserBody = Type.Object({
  email: Type.String({ format: 'email', maxLength: 254 }),
  name: Type.String({ minLength: 1, maxLength: 100 }),
}, { additionalProperties: false });

const UserResponse = Type.Object({
  id: Type.String({ format: 'uuid' }),
  email: Type.String(),
  name: Type.String(),
  createdAt: Type.String({ format: 'date-time' }),
});

type CreateUserBodyType = Static<typeof CreateUserBody>;
type UserResponseType = Static<typeof UserResponse>;

const usersPlugin: FastifyPluginAsyncTypebox = async (fastify) => {
  fastify.post('/users', {
    schema: {
      body: CreateUserBody,
      response: { 201: UserResponse },
    },
  }, async (request, reply) => {
    // request.body is fully typed as CreateUserBodyType
    const user = await fastify.userService.create(request.body);
    return reply.code(201).send(user);
  });
};

export default fp(usersPlugin);
```

---

## Code Standards

| Rule | Detail |
|------|--------|
| Plugin files export default `fp()` | Ensures cross-scope decoration works |
| Always define response schemas | Required for fast-json-stringify benefits |
| `additionalProperties: false` | On all request body schemas |
| Use Pino child loggers | `request.log` in handlers, never `console` |
| Never throw plain `Error` | Always use typed HTTP errors from `@fastify/error` |
| Test with `fastify.inject()` | No real TCP sockets in unit/integration tests |
