# TypeScript — Core Language Reference (Detailed)

TypeScript 5.x language fundamentals for building safe, maintainable applications.
Source: typescriptlang.org/docs, TypeScript 5.x release notes.

---

## Compiler Configuration (`tsconfig.json`)

### Strict Baseline (mandatory)

```json
{
  "compilerOptions": {
    "strict": true,
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "lib": ["ES2022"],
    "outDir": "dist",
    "rootDir": "src",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true,
    "noPropertyAccessFromIndexSignature": true
  }
}
```

`strict: true` enables: `strictNullChecks`, `strictFunctionTypes`, `strictBindCallApply`,
`strictPropertyInitialization`, `noImplicitAny`, `noImplicitThis`, `alwaysStrict`.

Additional flags above close common loopholes — enable them in new projects by default.

### Path Aliases

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@src/*":   ["src/*"],
      "@test/*":  ["tests/*"],
      "@lib/*":   ["lib/*"]
    }
  }
}
```

Never use `../../` imports beyond one level deep — use path aliases instead.

---

## Type System Fundamentals

### Primitive and Literal Types

```typescript
// Primitives
const name: string = "Alice";
const age: number = 30;
const active: boolean = true;
const id: bigint = 9007199254740993n;
const sym: symbol = Symbol("key");

// Literal types — exact values
type Direction = "north" | "south" | "east" | "west";
type StatusCode = 200 | 400 | 404 | 500;
type Flag = true;

// Template literal types (TS 4.1+)
type EventName = `on${Capitalize<string>}`;
type CSSProperty = `${string}-${string}`;
```

### Arrays and Tuples

```typescript
// Arrays
const names: string[] = ["Alice", "Bob"];
const matrix: number[][] = [[1, 2], [3, 4]];
const readonly: ReadonlyArray<string> = ["x"];

// Tuples — fixed-length, typed positions
type Pair = [string, number];
type RGB = [red: number, green: number, blue: number];  // labeled

// Rest elements in tuples
type StringsAndNumber = [...string[], number];
```

### Objects and Interfaces

```typescript
// Interface — prefer for public API shapes
interface User {
  readonly id: string;
  name: string;
  email: string;
  role?: "admin" | "user";  // optional
}

// Type alias — prefer for unions, intersections, mapped/conditional
type Result<T> =
  | { ok: true; value: T }
  | { ok: false; error: Error };

// Intersection
type AdminUser = User & { permissions: string[] };

// Index signature
interface StringMap {
  [key: string]: string;
}
```

### Enums — Prefer Union Types

```typescript
// Prefer string unions — simpler, tree-shakeable
type Status = "pending" | "active" | "inactive";

// const enum — inlined by compiler, no runtime object
const enum Direction {
  Up = "UP",
  Down = "DOWN",
}

// Avoid: regular enum (creates runtime object, harder to tree-shake)
// enum Status { Pending, Active }  // ❌
```

---

## Functions

### Signatures and Overloads

```typescript
// Arrow with explicit return type
const add = (a: number, b: number): number => a + b;

// Named function with default and rest params
function buildUrl(
  base: string,
  path: string = "/",
  ...params: string[]
): string {
  return `${base}${path}?${params.join("&")}`;
}

// Overloads — when signature varies by input type
function parse(input: string): number;
function parse(input: number): string;
function parse(input: string | number): string | number {
  return typeof input === "string" ? parseInt(input) : String(input);
}
```

### Higher-Order Functions

```typescript
type Predicate<T> = (value: T) => boolean;
type Transform<A, B> = (value: A) => B;

function filter<T>(items: T[], pred: Predicate<T>): T[] {
  return items.filter(pred);
}

function pipe<A, B, C>(f: Transform<A, B>, g: Transform<B, C>): Transform<A, C> {
  return (x) => g(f(x));
}
```

---

## Generics

### Generic Functions and Constraints

```typescript
// Basic generic
function identity<T>(value: T): T {
  return value;
}

// Constraint — T must have a .length
function longest<T extends { length: number }>(a: T, b: T): T {
  return a.length >= b.length ? a : b;
}

// Multiple type parameters
function zip<A, B>(as: A[], bs: B[]): [A, B][] {
  return as.map((a, i) => [a, bs[i]] as [A, B]);
}

// Default type parameter (TS 5.5+)
function createBox<T = string>(value: T): { value: T } {
  return { value };
}
```

### Generic Interfaces and Classes

```typescript
interface Repository<T, ID = string> {
  findById(id: ID): Promise<T | null>;
  findAll(): Promise<T[]>;
  save(entity: T): Promise<T>;
  delete(id: ID): Promise<void>;
}

class InMemoryRepo<T extends { id: string }>
  implements Repository<T>
{
  private store = new Map<string, T>();

  async findById(id: string): Promise<T | null> {
    return this.store.get(id) ?? null;
  }

  async findAll(): Promise<T[]> {
    return [...this.store.values()];
  }

  async save(entity: T): Promise<T> {
    this.store.set(entity.id, entity);
    return entity;
  }

  async delete(id: string): Promise<void> {
    this.store.delete(id);
  }
}
```

---

## Utility Types

### Built-In Utility Types

```typescript
interface User {
  id: string;
  name: string;
  email: string;
  password: string;
  role: "admin" | "user";
}

// Partial — all properties optional
type UpdateUserDto = Partial<User>;

// Required — all properties required
type RequiredUser = Required<User>;

// Readonly — all properties read-only
type FrozenUser = Readonly<User>;

// Pick — select subset
type PublicUser = Pick<User, "id" | "name" | "role">;

// Omit — exclude properties
type SafeUser = Omit<User, "password">;

// Record — map keys to value type
type UserMap = Record<string, User>;

// Exclude/Extract — filter union members
type NonAdmin = Exclude<User["role"], "admin">;   // "user"
type AdminOnly = Extract<User["role"], "admin">;  // "admin"

// NonNullable — remove null/undefined
type DefiniteId = NonNullable<string | null | undefined>;  // string

// ReturnType / Parameters / ConstructorParameters
type FetchReturn = ReturnType<typeof fetch>;
type FetchParams = Parameters<typeof fetch>;

// Awaited — unwrap Promise type
type UserPromise = Promise<User>;
type UnwrappedUser = Awaited<UserPromise>;  // User
```

### Template Literal Utility Types

```typescript
type EventName = "click" | "focus" | "blur";
type Handler = `on${Capitalize<EventName>}`;
// "onClick" | "onFocus" | "onBlur"

type Getters<T> = {
  [K in keyof T as `get${Capitalize<string & K>}`]: () => T[K];
};
```

---

## Advanced Type Patterns

### Discriminated Unions

```typescript
// Tag each variant with a literal type
type Shape =
  | { kind: "circle";    radius: number }
  | { kind: "rectangle"; width: number; height: number }
  | { kind: "triangle";  base: number;  height: number };

function area(shape: Shape): number {
  switch (shape.kind) {
    case "circle":    return Math.PI * shape.radius ** 2;
    case "rectangle": return shape.width * shape.height;
    case "triangle":  return 0.5 * shape.base * shape.height;
  }
  // TypeScript enforces exhaustiveness — no default needed when all cases covered
}
```

### Mapped Types

```typescript
// Make all properties nullable
type Nullable<T> = { [K in keyof T]: T[K] | null };

// Deep readonly
type DeepReadonly<T> = {
  readonly [K in keyof T]: T[K] extends object ? DeepReadonly<T[K]> : T[K];
};

// Prefix all keys
type Prefixed<T, P extends string> = {
  [K in keyof T as `${P}${Capitalize<string & K>}`]: T[K];
};
```

### Conditional Types

```typescript
// Basic conditional
type IsArray<T> = T extends unknown[] ? true : false;

// Infer — extract type from within another type
type UnwrapPromise<T> = T extends Promise<infer U> ? U : T;
type ArrayItem<T> = T extends (infer U)[] ? U : never;

// Distributive conditional (distributes over unions)
type ToArray<T> = T extends unknown ? T[] : never;
// ToArray<string | number> → string[] | number[]
```

### Branded / Nominal Types

```typescript
// Prevent mixing structurally identical types
declare const __brand: unique symbol;
type Brand<T, B> = T & { readonly [__brand]: B };

type UserId  = Brand<string, "UserId">;
type OrderId = Brand<string, "OrderId">;

function createUserId(raw: string): UserId {
  return raw as UserId;
}

const uid: UserId  = createUserId("u-123");
const oid: OrderId = "o-456" as OrderId;

// TypeScript now prevents: const x: UserId = oid;  ← compile error
```

---

## Classes

### Access Modifiers and Decorators

```typescript
class Service {
  // Parameter properties (shorthand)
  constructor(
    private readonly db: Database,
    protected readonly logger: Logger,
    public readonly name: string,
  ) {}

  // Accessor
  get connectionString(): string {
    return this.db.url;
  }

  // Override enforcement
  override toString(): string {
    return `Service(${this.name})`;
  }
}

// Abstract class
abstract class BaseHandler<TInput, TOutput> {
  abstract handle(input: TInput): Promise<TOutput>;

  async execute(input: TInput): Promise<TOutput> {
    this.logger.debug("Handling", { input });
    return this.handle(input);
  }

  protected readonly logger = new Logger(this.constructor.name);
}
```

### `satisfies` Operator (TS 4.9+)

```typescript
// Validates type without widening — keeps literal types
const palette = {
  red:   [255, 0, 0],
  green: "#00ff00",
  blue:  [0, 0, 255],
} satisfies Record<string, string | number[]>;

// palette.red is number[] (not string | number[])
// palette.green is string (not string | number[])
```

---

## Modules

### ES Module Syntax

```typescript
// Named exports
export type { User };        // type-only export
export { createUser };

// Default export (avoid in libraries — prefer named)
export default class UserService {}

// Re-export
export { createUser as create } from "./users.js";
export * from "./types.js";

// Dynamic import
const { createUser } = await import("./users.js");
```

### Module Augmentation

```typescript
// Extend an existing module's types
declare module "express" {
  interface Request {
    user?: AuthenticatedUser;
  }
}

// Ambient declarations for non-TS modules
declare module "*.svg" {
  const content: string;
  export default content;
}
```

---

## Type Narrowing

```typescript
function processInput(input: string | number | null): string {
  // typeof guard
  if (typeof input === "string") return input.toUpperCase();

  // null check
  if (input === null) return "(empty)";

  // Now narrowed to number
  return input.toFixed(2);
}

// instanceof guard
function formatError(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (typeof err === "string") return err;
  return String(err);
}

// Discriminated union narrowing
function handleResult<T>(result: Result<T>): T {
  if (!result.ok) throw result.error;
  return result.value;
}

// Type predicate (user-defined guard)
function isUser(value: unknown): value is User {
  return (
    typeof value === "object" &&
    value !== null &&
    "id" in value &&
    typeof (value as User).id === "string"
  );
}
```

---

## Async Patterns

```typescript
// Async/await with proper error handling
async function fetchUser(id: string): Promise<User> {
  const response = await fetch(`/api/users/${id}`);
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
  }
  return response.json() as Promise<User>;
}

// Promise combinators
const [users, orders] = await Promise.all([
  fetchUsers(),
  fetchOrders(),
]);

// Race with timeout
async function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  const timeout = new Promise<never>((_, reject) =>
    setTimeout(() => reject(new Error(`Timeout after ${ms}ms`)), ms),
  );
  return Promise.race([promise, timeout]);
}

// AsyncIterable
async function* paginate<T>(
  fetchPage: (cursor: string | null) => Promise<{ items: T[]; next: string | null }>,
): AsyncGenerator<T> {
  let cursor: string | null = null;
  do {
    const { items, next } = await fetchPage(cursor);
    yield* items;
    cursor = next;
  } while (cursor !== null);
}
```

---

## Error Handling

```typescript
// Typed error hierarchy
class AppError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly statusCode: number = 500,
  ) {
    super(message);
    this.name = this.constructor.name;
  }
}

class NotFoundError extends AppError {
  constructor(resource: string, id: string) {
    super(`${resource} not found: ${id}`, "NOT_FOUND", 404);
  }
}

// Result type — explicit error without throwing
type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E };

function tryParse(raw: string): Result<number> {
  const n = Number(raw);
  if (Number.isNaN(n)) {
    return { ok: false, error: new Error(`Not a number: ${raw}`) };
  }
  return { ok: true, value: n };
}

// Handle unknown errors safely
function toError(err: unknown): Error {
  if (err instanceof Error) return err;
  return new Error(String(err));
}
```

---

## Anti-Patterns

```typescript
// NEVER: any without justification
const data: any = fetch("/api");  // ❌
const data: unknown = fetch("/api");  // ✅ — narrows safely

// NEVER: type assertion to bypass type system
const user = {} as User;  // ❌ — silent runtime errors
// ✅ — validate at the boundary (zod, io-ts, etc.)

// NEVER: non-null assertion on uncertain values
const name = user!.name;  // ❌
const name = user?.name ?? "anonymous";  // ✅

// NEVER: import from deprecated typing packages
import { Dict } from "utility-types";  // ❌
type Dict<V> = Record<string, V>;  // ✅ — built-in

// NEVER: string enums (prefer union types)
enum Color { Red = "RED" }  // ❌ runtime object
type Color = "RED" | "GREEN" | "BLUE";  // ✅

// NEVER: deep relative imports
import { x } from "../../../../../../lib/x";  // ❌
import { x } from "@lib/x";  // ✅
```

---

## Functional Patterns

Use the type system to make illegal states unrepresentable. The compiler becomes a safety net that catches missing cases, invalid states, and unit confusion at build time.

### Algebraic Data Types (ADTs)

ADTs come in two forms:

- **Sum types (OR)** — a value is *one of* several variants (discriminated unions)
- **Product types (AND)** — a value contains *all* fields simultaneously (objects, tuples)

#### Discriminated Unions in Depth

Tag each variant with a literal discriminant (`kind`, `type`, or `_tag`) and always use `assertNever` for exhaustiveness:

```typescript
const assertNever = (x: never): never => {
  throw new Error(`Unhandled variant: ${JSON.stringify(x)}`)
}

type TxnState =
  | { kind: "pending";   createdAt: number }
  | { kind: "settled";   ledgerId: string; settledAt: number }
  | { kind: "failed";    reason: FailureReason; failedAt: number }
  | { kind: "reversed";  originalLedgerId: string; reversedAt: number }

function isTerminal(state: TxnState): boolean {
  switch (state.kind) {
    case "pending":  return false
    case "settled":  return true
    case "failed":   return true
    case "reversed": return true
    default:         return assertNever(state)  // compile error if variant missing
  }
}
```

Adding a new variant forces every switch to be updated — the compiler shows exactly where.

#### Boolean Elimination

Replace boolean flags with explicit states so impossible combinations cannot be constructed:

```typescript
// ❌ boolean soup — what does { isPaid: true, isCancelled: true } mean?
type Order = { id: string; isPaid: boolean; isShipped: boolean; isCancelled: boolean }

// ✅ explicit states — only valid combinations exist
type OrderStatus =
  | { kind: "pending" }
  | { kind: "paid";      paidAt: Date }
  | { kind: "shipped";   trackingNumber: string; shippedAt: Date }
  | { kind: "delivered"; deliveredAt: Date }
  | { kind: "cancelled"; reason: string; cancelledAt: Date }

type Order = { id: string; status: OrderStatus }
```

#### State Machine Modeling

Encode domain transitions so invalid states are unrepresentable:

```typescript
type FailureReason =
  | { kind: "insufficient_funds" }
  | { kind: "invalid_account" }
  | { kind: "network_error"; retryable: boolean }

function settle(state: TxnState, ledgerId: string): TxnState {
  if (state.kind !== "pending") throw new Error("Can only settle pending transactions")
  return { kind: "settled", ledgerId, settledAt: Date.now() as number }
}
```

See [`adts.md`](./adts.md) for full examples including nested ADTs, generic sum types (`RemoteData<T, E>`), type guard patterns, and testing strategies.

---

### Option\<T\> — Explicit Nullable Values

`Option<T>` replaces `T | null | undefined` with a tagged union that forces callers to handle absence:

```typescript
type None   = { _tag: "None" }
type Some<T> = { _tag: "Some"; value: T }
type Option<T> = None | Some<T>

const None: None = { _tag: "None" }
const Some = <T>(value: T): Option<T> => ({ _tag: "Some", value })

// Utilities
const getOrElse = <T>(opt: Option<T>, def: T): T =>
  opt._tag === "Some" ? opt.value : def

const map = <T, U>(opt: Option<T>, fn: (v: T) => U): Option<U> =>
  opt._tag === "Some" ? Some(fn(opt.value)) : None

const flatMap = <T, U>(opt: Option<T>, fn: (v: T) => Option<U>): Option<U> =>
  opt._tag === "Some" ? fn(opt.value) : None
```

Use **`Option`** when absence is a normal, expected outcome (e.g. lookup by ID, optional config field). Use **`Result`** when failure carries error context.

---

### Result\<T, E\> — Explicit Error Handling

`Result<T, E>` encodes fallibility directly in the return type, eliminating invisible throws:

```typescript
type Ok<T>  = { _tag: "Ok";  value: T }
type Err<E> = { _tag: "Err"; error: E }
type Result<T, E> = Ok<T> | Err<E>

const Ok  = <T>(value: T): Result<T, never> => ({ _tag: "Ok",  value })
const Err = <E>(error: E): Result<never, E> => ({ _tag: "Err", error })

// Utilities
const mapResult = <T, U, E>(r: Result<T, E>, fn: (v: T) => U): Result<U, E> =>
  r._tag === "Ok" ? Ok(fn(r.value)) : r

const flatMapResult = <T, U, E>(r: Result<T, E>, fn: (v: T) => Result<U, E>): Result<U, E> =>
  r._tag === "Ok" ? fn(r.value) : r
```

#### Decision Guide

| Scenario | Use |
|----------|-----|
| Value may be absent (expected) | `Option<T>` |
| Operation may fail (recoverable) | `Result<T, E>` |
| Programmer error / assertion failure | Exception (`throw`) |

#### Typed Error Example

```typescript
type ConfigError = { field: string; message: string }

function parsePort(raw: unknown): Result<number, ConfigError> {
  if (typeof raw !== "number")      return Err({ field: "port", message: "must be number" })
  if (raw < 1 || raw > 65535)       return Err({ field: "port", message: "must be 1-65535" })
  return Ok(raw)
}

const result = parsePort(process.env.PORT)
switch (result._tag) {
  case "Ok":  startServer(result.value); break
  case "Err": logger.error(result.error.message); process.exit(1)
}
```

See [`option-result.md`](./option-result.md) for chaining, accumulating multiple errors, HTTP handling, and conversion helpers (`optionToResult`, `fromNullable`).

---

### Branded Types — Deeper Dive

Beyond the basic brand pattern (see [Branded / Nominal Types](#branded--nominal-types) above), smart constructors enforce invariants at creation time so every value in your domain is already valid:

```typescript
type Brand<K, T> = K & { __brand: T }

type Cents   = Brand<number, "Cents">
type Dollars = Brand<number, "Dollars">
type Email   = Brand<string, "Email">

const Cents = (n: number): Cents => {
  if (!Number.isInteger(n) || n < 0) throw new Error("Cents must be non-negative integer")
  return n as Cents
}

const Email = (s: string): Email => {
  const t = s.trim().toLowerCase()
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(t)) throw new Error("Invalid email")
  return t as Email
}

// For external / user input — return Result instead of throwing
const parseEmail = (s: string): Result<Email, string> => {
  try   { return Ok(Email(s)) }
  catch { return Err("Invalid email format") }
}
```

Common branded types by domain:

| Domain | Types |
|--------|-------|
| Financial | `Cents`, `Dollars`, `BasisPoints` |
| Time | `Millis`, `Seconds`, `IsoDateString` |
| Identifiers | `UserId`, `OrderId`, `SessionToken` |
| Validated strings | `Email`, `Url`, `NonEmptyString` |
| Numeric constraints | `PositiveInt`, `Percentage`, `Port` |

See [`branded-types.md`](./branded-types.md) for multiple-brand composition, `NonEmptyArray<T>`, JSON serialisation helpers, and testing smart constructors.

---

### Paste-Ready Helpers

Drop this into `src/lib/functional.ts`:

```typescript
// Option
export type None    = { _tag: "None" }
export type Some<T> = { _tag: "Some"; value: T }
export type Option<T> = None | Some<T>
export const None: None = { _tag: "None" }
export const Some = <T>(v: T): Option<T> => ({ _tag: "Some", value: v })
export const getOrElse  = <T>(o: Option<T>, d: T): T => o._tag === "Some" ? o.value : d
export const mapOpt     = <T, U>(o: Option<T>, f: (v: T) => U): Option<U> => o._tag === "Some" ? Some(f(o.value)) : None
export const flatMapOpt = <T, U>(o: Option<T>, f: (v: T) => Option<U>): Option<U> => o._tag === "Some" ? f(o.value) : None

// Result
export type Ok<T>   = { _tag: "Ok";  value: T }
export type Err<E>  = { _tag: "Err"; error: E }
export type Result<T, E> = Ok<T> | Err<E>
export const Ok  = <T>(v: T): Result<T, never> => ({ _tag: "Ok",  value: v })
export const Err = <E>(e: E): Result<never, E> => ({ _tag: "Err", error: e })
export const mapResult     = <T, U, E>(r: Result<T, E>, f: (v: T) => U): Result<U, E> => r._tag === "Ok" ? Ok(f(r.value)) : r
export const flatMapResult = <T, U, E>(r: Result<T, E>, f: (v: T) => Result<U, E>): Result<U, E> => r._tag === "Ok" ? f(r.value) : r

// Exhaustiveness
export const assertNever = (x: never): never => { throw new Error(`Unhandled variant: ${JSON.stringify(x)}`) }

// Brand
export type Brand<K, T> = K & { __brand: T }
```

See [`functional-migration.md`](./functional-migration.md) for the incremental adoption playbook — strict mode setup, code smell identification, team onboarding, and CI enforcement.

---

## Quick Reference

| Concept | Syntax |
|---------|--------|
| Strict null guard | `value ?? "default"` |
| Optional chaining | `obj?.prop?.method?.()` |
| Type assertion (safe) | `value as Type` (only when certain) |
| Satisfies | `expr satisfies Type` |
| Const assertion | `["a", "b"] as const` |
| Key access | `User["email"]` |
| Conditional type | `T extends U ? A : B` |
| Infer | `T extends Promise<infer U> ? U : T` |
| Mapped type | `{ [K in keyof T]: ... }` |
| Template literal | `` `${Capitalize<K>}` `` |

---

**Remember**: TypeScript's value is in the compile-time contract it enforces.
Every `any`, `!`, or `@ts-ignore` is a hole in that contract — treat them as bugs.
