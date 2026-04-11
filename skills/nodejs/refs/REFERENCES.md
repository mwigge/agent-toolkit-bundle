# Node.js References

## Core Platform

### Official Documentation

- **Node.js Docs (all versions)**: https://nodejs.org/en/docs/
- **Node.js API v22**: https://nodejs.org/docs/latest-v22.x/api/
- **Built-in test runner (`node:test`)**: https://nodejs.org/api/test.html
- **Streams API**: https://nodejs.org/api/stream.html
- **AsyncLocalStorage / async_hooks**: https://nodejs.org/api/async_context.html
- **Worker Threads**: https://nodejs.org/api/worker_threads.html
- **diagnostics_channel**: https://nodejs.org/api/diagnostics_channel.html
- **ES Modules**: https://nodejs.org/api/esm.html
- **AbortController / AbortSignal**: https://nodejs.org/api/globals.html#class-abortcontroller
- **Timers**: https://nodejs.org/api/timers.html
- **Crypto**: https://nodejs.org/api/crypto.html
- **URL API**: https://nodejs.org/api/url.html

### Proposals & Standards

- **TC39 AsyncContext proposal**: https://github.com/nicolo-ribaudo/tc39-proposal-async-context
- **WHATWG Streams**: https://streams.spec.whatwg.org/
- **WHATWG Fetch**: https://fetch.spec.whatwg.org/

### Security

- **Node.js Security Best Practices**: https://nodejs.org/en/docs/guides/security/
- **OWASP Node.js Cheatsheet**: https://cheatsheetseries.owasp.org/cheatsheets/Nodejs_Security_Cheat_Sheet.html
- **npm audit docs**: https://docs.npmjs.com/cli/v10/commands/npm-audit

### Key RFCs / Reading

- **Backpressure in Node.js Streams**: https://nodejs.org/en/docs/guides/backpressuring-in-streams
- **Don't Block the Event Loop**: https://nodejs.org/en/docs/guides/dont-block-the-event-loop
- **Event Loop Timers and process.nextTick**: https://nodejs.org/en/docs/guides/event-loop-timers-and-nexttick

---

## Fastify

### Official Documentation

- **Fastify Docs (latest)**: https://fastify.dev/docs/latest/
- **Lifecycle / Hook order**: https://fastify.dev/docs/latest/Reference/Lifecycle/
- **Plugin system**: https://fastify.dev/docs/latest/Reference/Plugins/
- **TypeScript support**: https://fastify.dev/docs/latest/Reference/TypeScript/
- **Logging (Pino)**: https://fastify.dev/docs/latest/Reference/Logging/
- **Validation & Serialisation**: https://fastify.dev/docs/latest/Reference/Validation-and-Serialization/
- **Routes**: https://fastify.dev/docs/latest/Reference/Routes/
- **Decorators**: https://fastify.dev/docs/latest/Reference/Decorators/
- **Hooks**: https://fastify.dev/docs/latest/Reference/Hooks/
- **Error Handling**: https://fastify.dev/docs/latest/Reference/Errors/
- **Reply**: https://fastify.dev/docs/latest/Reference/Reply/

### GitHub Repositories

- **fastify/fastify**: https://github.com/fastify/fastify
- **fastify/fastify-plugin**: https://github.com/fastify/fastify-plugin
- **fastify/type-provider-typebox**: https://github.com/fastify/fastify-type-provider-typebox
- **fastify/fastify-jwt**: https://github.com/fastify/fastify-jwt
- **fastify/fastify-auth**: https://github.com/fastify/fastify-auth
- **fastify/fastify-helmet**: https://github.com/fastify/fastify-helmet
- **fastify/fastify-cors**: https://github.com/fastify/fastify-cors
- **fastify/fastify-rate-limit**: https://github.com/fastify/fastify-rate-limit
- **fastify/fastify-swagger**: https://github.com/fastify/fastify-swagger
- **fastify/fastify-error**: https://github.com/fastify/fastify-error

### TypeBox

- **@sinclair/typebox**: https://github.com/sinclairzx81/typebox
- **TypeBox docs**: https://github.com/sinclairzx81/typebox#readme

### Related Libraries

- **Ajv (JSON Schema validator)**: https://ajv.js.org/
- **fast-json-stringify**: https://github.com/fastify/fast-json-stringify

### Security

- **Helmet.js**: https://helmetjs.github.io/
- **OWASP REST Security**: https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html

---

## NestJS

### Official NestJS Documentation

- **NestJS Docs**: https://docs.nestjs.com/
- **Dependency Injection**: https://docs.nestjs.com/fundamentals/dependency-injection
- **Custom Providers**: https://docs.nestjs.com/fundamentals/custom-providers
- **Validation**: https://docs.nestjs.com/techniques/validation
- **Authentication**: https://docs.nestjs.com/security/authentication
- **Authorisation (Guards)**: https://docs.nestjs.com/security/authorization
- **CQRS**: https://docs.nestjs.com/techniques/cqrs
- **Configuration**: https://docs.nestjs.com/techniques/configuration
- **Testing**: https://docs.nestjs.com/fundamentals/testing
- **Exception Filters**: https://docs.nestjs.com/exception-filters
- **Interceptors**: https://docs.nestjs.com/interceptors
- **Pipes**: https://docs.nestjs.com/pipes
- **Guards**: https://docs.nestjs.com/guards
- **Middleware**: https://docs.nestjs.com/middleware

### Prisma

- **What is Prisma?**: https://www.prisma.io/docs/orm/overview/introduction/what-is-prisma
- **Prisma Client**: https://www.prisma.io/docs/orm/prisma-client
- **Transactions**: https://www.prisma.io/docs/orm/prisma-client/queries/transactions
- **Prisma Client Extensions**: https://www.prisma.io/docs/orm/prisma-client/client-extensions
- **NestJS + Prisma guide**: https://www.prisma.io/nestjs

### Logging

- **nestjs-pino**: https://github.com/iamolegga/nestjs-pino

### Validation Libraries

- **class-validator**: https://github.com/typestack/class-validator
- **class-transformer**: https://github.com/typestack/class-transformer

### Authentication

- **passport-jwt**: https://github.com/mikenicholson/passport-jwt
- **@nestjs/passport**: https://github.com/nestjs/passport
- **jsonwebtoken**: https://github.com/auth0/node-jsonwebtoken

### Testing

- **Jest**: https://jestjs.io/
- **Supertest**: https://github.com/ladjs/supertest
- **jest-mock-extended (Prisma mocks)**: https://github.com/marchaos/jest-mock-extended

---

## Shared Tooling

- **pnpm**: https://pnpm.io/
- **ESLint (flat config)**: https://eslint.org/docs/latest/use/configure/configuration-files-new
- **TypeScript**: https://www.typescriptlang.org/docs/
- **Vitest**: https://vitest.dev/
- **Pino logger**: https://getpino.io/
- **OpenTelemetry JS SDK**: https://opentelemetry.io/docs/languages/js/
- **@opentelemetry/api**: https://github.com/open-telemetry/opentelemetry-js/tree/main/api
