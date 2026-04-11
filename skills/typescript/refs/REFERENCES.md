# TypeScript — Combined Reference Links

## Language Reference
- https://www.typescriptlang.org/docs/handbook/intro.html — TypeScript Handbook: the official comprehensive language guide
- https://www.typescriptlang.org/tsconfig — tsconfig reference: all compiler options with descriptions
- https://www.typescriptlang.org/docs/handbook/release-notes/overview.html — TypeScript release notes overview (all versions)

## TypeScript 5.x Features
- https://devblogs.microsoft.com/typescript/announcing-typescript-5-0/ — TS 5.0: decorators, const type parameters
- https://devblogs.microsoft.com/typescript/announcing-typescript-5-1/ — TS 5.1: unrelated return types for setters/getters
- https://devblogs.microsoft.com/typescript/announcing-typescript-5-2/ — TS 5.2: `using`/`await using` (Explicit Resource Management)
- https://devblogs.microsoft.com/typescript/announcing-typescript-5-3/ — TS 5.3: import attributes, narrowing improvements
- https://devblogs.microsoft.com/typescript/announcing-typescript-5-4/ — TS 5.4: `NoInfer<T>`, preserved narrowing in closures
- https://devblogs.microsoft.com/typescript/announcing-typescript-5-5/ — TS 5.5: inferred type predicates, control flow for computed properties

## Execution & Build
- https://typestrong.org/ts-node/ — ts-node: TypeScript execution for Node.js (development/scripts)
- https://tsx.is/ — tsx: fast TypeScript/ESM runner (esbuild-based, no type checking)
- https://tsup.egoist.dev/ — tsup: zero-config TypeScript bundler built on esbuild

## Compiler Options Deep Dive
- https://www.typescriptlang.org/docs/handbook/modules/reference.html — Module reference: `moduleResolution` NodeNext explained
- https://www.typescriptlang.org/docs/handbook/type-compatibility.html — Type compatibility and structural typing rules

## Package Management
- https://pnpm.io/motivation — pnpm: fast, disk-efficient package manager using hard links
- https://pnpm.io/pnpm-workspace_yaml — pnpm workspaces: monorepo configuration
- https://pnpm.io/filtering — pnpm filter: running commands in specific workspace packages

## Linting
- https://eslint.org/docs/latest/use/configure/configuration-files — ESLint v9 flat config (`eslint.config.js`) format
- https://typescript-eslint.io/getting-started/ — typescript-eslint: TypeScript rules for ESLint
- https://typescript-eslint.io/rules/ — typescript-eslint rules reference (no-explicit-any, no-unsafe-*, etc.)
- https://github.com/import-js/eslint-plugin-import — eslint-plugin-import: import ordering and resolution rules

## Formatting
- https://prettier.io/docs/en/configuration.html — Prettier configuration reference
- https://github.com/prettier/eslint-config-prettier — eslint-config-prettier: disable conflicting ESLint formatting rules

## Building
- https://tsup.egoist.dev/ — tsup: zero-config bundler for TypeScript libraries (ESM + CJS dual output)
- https://tsup.egoist.dev/#usage — tsup usage: `tsup src/index.ts --format esm,cjs --dts`

## Release Management
- https://github.com/changesets/changesets — changesets: manage versioning and CHANGELOG for monorepos
- https://github.com/changesets/changesets/blob/main/docs/command-line-options.md — changesets CLI reference

## Testing Framework
- https://vitest.dev/ — Vitest: Vite-native unit test framework, Jest-compatible API
- https://vitest.dev/config/ — Vitest configuration reference (all options)
- https://vitest.dev/guide/coverage.html — Vitest coverage: v8 and istanbul providers, threshold config

## UI & Component Testing
- https://testing-library.com/docs/ — Testing Library: DOM-centric testing utilities (React, Vue, Svelte)
- https://testing-library.com/docs/user-event/intro — user-event: realistic user interaction simulation

## HTTP Mocking
- https://mswjs.io/ — MSW v2: API mocking via Service Worker and Node.js interceptors
- https://mswjs.io/docs/integrations/node — MSW Node.js integration for Vitest/Jest

## Mock Utilities
- https://github.com/eratio08/vitest-mock-extended — vitest-mock-extended: deep mock creation with type safety
- https://vitest.dev/api/vi.html — vi API reference: `vi.mock`, `vi.spyOn`, `vi.fn`, `vi.useFakeTimers`

## Test Data Generation
- https://fakerjs.dev/ — @faker-js/faker: generate realistic fake data for tests (v9+)
- https://fakerjs.dev/api/ — Faker API reference: name, date, internet, commerce, finance modules

## Coverage & Quality
- https://istanbul.js.org/ — Istanbul: instrumentation-based JS coverage (used by Vitest)
- https://vitest.dev/guide/snapshot.html — Vitest snapshot testing reference

## Architecture Patterns
- https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html — Clean Architecture: dependency rule, layers, and boundaries
- https://khalilstemmler.com/articles/software-design-architecture/domain-driven-design-intro/ — DDD in TypeScript: aggregates, value objects, domain events
- https://martinfowler.com/bliki/CQRS.html — CQRS: separating read and write models in TypeScript applications

## Functional Patterns
- https://gcanti.github.io/fp-ts/ — fp-ts: functional programming primitives (Option, Either, Task, IO) for TypeScript
- https://effect.website/ — Effect-TS: typed errors, concurrency, dependency injection via the Effect ecosystem
- https://zod.dev/ — Zod: TypeScript-first schema validation and parsing (runtime type safety)
- https://github.com/sinclairzx81/typebox — TypeBox: JSON Schema + TypeScript types from the same declaration (fast validation)

## Dependency Injection
- https://inversify.io/ — InversifyJS: IoC container for TypeScript with decorators and typed symbols
- https://tsyringe.netlify.app/ — TSyringe (Microsoft): lightweight DI container using `reflect-metadata`

## Cross-Cutting Patterns
- https://www.npmjs.com/package/neverthrow — neverthrow: `Result<T, E>` type for explicit error handling without exceptions
- https://github.com/functional-promises/functional-promises — Functional Promises patterns in TypeScript

## Module Boundaries
- https://nx.dev/concepts/module-boundaries — Nx module boundaries: enforcing architecture layers via lint rules
- https://typescript-eslint.io/rules/no-restricted-imports/ — ESLint no-restricted-imports: block cross-layer imports
