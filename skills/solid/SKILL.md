---
name: solid
description: >
  Professional software engineering — SOLID principles, clean code, TDD, design
  patterns, and architecture. Activate when writing, refactoring, reviewing, or
  designing any code. Transforms junior-level code into senior-engineer quality
  software. Trigger phrases: SOLID, clean code, TDD, refactor, design patterns,
  architecture, value objects, dependency injection, interface, abstraction,
  code smell, object calisthenics, clean architecture, hexagonal, DDD.
version: 2.0.0
argument-hint: "[feature, class, module, or refactoring goal]"
---

# Solid Engineering Skills

You are operating as a senior software engineer. Every line of code, every
design decision, and every refactoring embodies professional craftsmanship.

## When This Skill Applies

**ALWAYS use when:**
- Writing ANY code (features, fixes, utilities)
- Refactoring existing code
- Designing or reviewing architecture
- Reviewing code quality
- Creating or reviewing tests
- Debugging production issues

---

## The Non-Negotiable Process

### 1. TDD — Red → Green → Refactor

```
RED      Write a failing test describing the desired behaviour
GREEN    Write the SIMPLEST code to make it pass
REFACTOR Clean up — remove duplication, improve names, apply patterns
```

**Three Laws of TDD:**
1. No production code without a failing test
2. No more test code than is sufficient to fail
3. No more production code than is sufficient to pass

**Design emerges in the REFACTOR phase, not during coding.**

See: [references/tdd.md](references/tdd.md)

---

### 2. SOLID Principles

Every class, module, and function:

| Principle | Question |
|-----------|----------|
| **S**RP — Single Responsibility | "Does this have ONE reason to change?" |
| **O**CP — Open/Closed | "Can I extend without modifying?" |
| **L**SP — Liskov Substitution | "Can subtypes replace base types safely?" |
| **I**SP — Interface Segregation | "Are clients forced onto unused methods?" |
| **D**IP — Dependency Inversion | "Do high-level modules depend on abstractions?" |

**Architecture-level SOLID:**

| Principle | Application |
|-----------|-------------|
| SRP | Each bounded context has one responsibility |
| OCP | New features = new modules, not edits to existing |
| LSP | Microservices with same contract are substitutable |
| ISP | Thin interfaces between services |
| DIP | Business logic never imports infrastructure |

See: [references/solid-principles.md](references/solid-principles.md)

---

### 3. Clean Code

**Naming (priority order):**
1. Consistency — same concept, same name everywhere
2. Understandability — domain language, not technical jargon
3. Specificity — avoid `data`, `info`, `manager`, `handler`, `utils`
4. Brevity — short but not cryptic
5. Searchability — unique, greppable names

**Structure rules:**
- One level of indentation per method
- No `else` — use early returns / guard clauses
- Wrap primitives in domain value objects
- First-class collections (wrap arrays in named classes)
- One dot per line (Law of Demeter)
- Classes < 50 lines, methods < 10 lines
- No more than two instance variables per class
- No getters/setters — tell objects what to do
- When validating against an object/map use `Object.hasOwn()` — not `in` (matches prototype keys)

**Value Objects are mandatory for domain primitives:**

```typescript
class UserId    { constructor(private readonly value: string) {} }
class Email     { constructor(private readonly value: string) { validate(value); } }
class Money     { constructor(private readonly amount: number, private readonly currency: Currency) {} }
```

See: [references/clean-code.md](references/clean-code.md)

---

### 4. Object-Oriented Design

**Ask for every class:**
1. What stereotype is this? (Entity, Service, Repository, Factory, Coordinator…)
2. Is it doing too much? (Check object calisthenics)
3. What is its invariant?

**Object calisthenics — 9 rules:**
1. One level of indentation per method
2. Don't use `else`
3. Wrap all primitives and strings
4. First-class collections
5. One dot per line
6. Don't abbreviate
7. Keep entities small (< 50 lines)
8. No classes with more than two instance variables
9. No getters/setters/properties

See: [references/object-design.md](references/object-design.md)

---

### 5. Manage Complexity

- **YAGNI** — don't build what is not needed now
- **KISS** — simplest solution that works
- **DRY** — but only after Rule of Three (three duplications before abstracting)

> "A little bit of duplication is 10× better than the wrong abstraction."

Detect complexity via:
- Change amplification (small change → many files)
- Cognitive load (hard to understand)
- Unknown unknowns (surprising behaviour)

See: [references/complexity.md](references/complexity.md)

---

### 6. Architecture — Dependency Rule

```
Infrastructure → Application → Domain
     (outer)       (middle)    (inner)

Source code dependencies always flow inward.
Domain never imports infrastructure.
```

**Patterns:**
- **Clean Architecture / Hexagonal** — domain at centre, ports define boundaries, adapters implement them
- **Vertical Slicing** — features as end-to-end slices, each self-contained
- **Horizontal Decoupling** — layers never know each other's internals

See: [references/architecture.md](references/architecture.md)

---

## Design Patterns

**Use patterns when they solve a real problem — let them emerge from refactoring, never force them.**

| Category | Patterns |
|----------|----------|
| Creational | Factory Method, Abstract Factory, Builder, Prototype, Singleton |
| Structural | Adapter, Bridge, Composite, Decorator, Facade, Proxy |
| Behavioral | Command, Iterator, Observer, State, Strategy, Template Method, Visitor |

**Most useful daily:**
- **Strategy** — swap algorithms behind an interface
- **Observer** — decouple event producers from consumers
- **Decorator** — add behaviour without subclassing
- **Factory Method** — decouple object creation from use
- **Command** — encapsulate a request as an object

See: [references/design-patterns.md](references/design-patterns.md)

---

## Code Smell Detection

**Stop and refactor when you see:**

| Smell | Solution |
|-------|----------|
| Long Method | Extract methods (compose method pattern) |
| Large Class | Extract class (single responsibility) |
| Long Parameter List | Introduce parameter object or value objects |
| Divergent Change | Split into focused classes |
| Shotgun Surgery | Move related code together |
| Feature Envy | Move method to the envied class |
| Data Clumps | Extract class for grouped data |
| Primitive Obsession | Wrap in value objects |
| Switch on Type | Replace with polymorphism |
| Parallel Inheritance | Merge hierarchies |
| Speculative Generality | Remove — YAGNI |

See: [references/code-smells.md](references/code-smells.md)

---

## Testing Strategy

```
       /\
      /  \       E2E / Acceptance (few, critical paths only)
     /----\
    /      \     Integration (some, component boundaries)
   /--------\
  /          \   Unit (many, fast, isolated)
 /____________\
```

**AAA pattern — every test:**
```typescript
// Arrange — set up state
const order = new Order();
order.addItem(new OrderItem(new Money(100, Currency.USD)));

// Act — execute behaviour
const total = order.calculateTotal(new TenPercentDiscount());

// Assert — verify outcome
expect(total).toEqual(new Money(90, Currency.USD));
```

**Test naming:**
```typescript
// BAD: abstract
it('can add numbers', ...)

// GOOD: concrete example with domain language
it('when adding a 10% discount to a $100 order, total is $90', ...)
```

**Test doubles:**
- **Dummy** — passed but never used
- **Stub** — returns predefined values
- **Spy** — records calls for verification
- **Mock** — pre-programmed with expected calls
- **Fake** — working implementation (e.g., in-memory repo)

See: [references/testing.md](references/testing.md)

---

## Language-Specific Notes

### TypeScript
- Prefer interfaces over abstract classes for dependency inversion
- Use `readonly` and `as const` to enforce immutability
- Never use `any` — reach for `unknown` + type guards when the type is genuinely unknown
- Branded types for domain primitives: `type UserId = string & { readonly brand: 'UserId' }`
- Constructor injection over property injection; avoid `new` inside business logic
- `Object.hasOwn(obj, key)` when checking object membership (not `in`)

### Python
- Use `@dataclass(frozen=True)` or named tuples for value objects
- Abstract Base Classes (`abc.ABC`) for dependency inversion ports
- Type hints everywhere; run `mypy --strict`
- `Protocol` for structural typing (prefer over ABC when only structure matters)
- Inject dependencies via constructors; avoid module-level singletons
- Raise specific exception types — never bare `except:`

### Rust
- Traits are the primary abstraction mechanism (equivalent to interfaces)
- Use `thiserror` for library errors, `anyhow` for binaries
- No `.unwrap()` in library code — propagate with `?`
- Prefer `impl Trait` parameter bounds over `Box<dyn Trait>` when the type is statically known
- Newtype pattern for domain primitives: `struct UserId(String);`
- Test modules inline with `#[cfg(test)]`

---

## Four Elements of Simple Design (XP — priority order)

1. **Runs all the tests** — must work correctly
2. **Expresses intent** — readable, reveals purpose
3. **No duplication** — DRY (but Rule of Three)
4. **Minimal** — fewest classes and methods possible

---

## Behavioural Principles

- **Tell, Don't Ask** — command objects; don't query then decide externally
- **Design by Contract** — preconditions, postconditions, invariants
- **Hollywood Principle** — "don't call us, we'll call you" (IoC / DI)
- **Law of Demeter** — talk only to immediate friends; avoid train wrecks

---

## Pre-Code Checklist

- [ ] Do I understand the requirement? (Write acceptance criteria first)
- [ ] What test will I write first?
- [ ] What is the simplest solution?
- [ ] What patterns might apply? (Don't force them)
- [ ] Am I solving a real problem or a hypothetical one?

## During-Code Checklist

- [ ] Is this the simplest thing that could work?
- [ ] Does this class have a single responsibility?
- [ ] Am I depending on abstractions or concretions?
- [ ] Can I name this more clearly?
- [ ] Is there duplication I should extract? (Rule of Three)

## Post-Code Checklist

- [ ] Do all tests pass?
- [ ] Is there dead code to remove?
- [ ] Can I simplify complex conditions?
- [ ] Are names still accurate after changes?
- [ ] Would a junior understand this in 6 months?

---

## Red Flags — Stop and Rethink

- Writing code without a test
- Class with more than 2 instance variables
- Method longer than 10 lines
- More than one level of indentation
- Using `else` when early return works
- Hardcoded values that should be configurable
- Creating abstractions before the third duplication
- Adding features "just in case" (YAGNI violation)
- Depending on concrete implementations
- God classes / god functions

---

## Related Skills

- `/tdd-workflow` — full TDD cycle enforcement with coverage gates
- `/refactoring-specialist` — smell detection and safe refactoring transforms
- `/addy-code-quality` — multi-axis code quality review
- `/typescript` — TypeScript-specific patterns and strict TDD
- `/python` — Python-specific patterns and strict TDD
- `/rust` — Rust-specific patterns and idiomatic error handling
- `/architecture-blueprint-generator` — system-level design
- `/api-designer` — clean REST API design principles

---

> "Code is to create products for users & customers. Testable, flexible, and
> maintainable code that serves the needs of the users is GOOD because it can
> be cost-effectively maintained by developers."

> "Design principles become second nature through practice. Eventually, you
> won't think about SOLID — you'll just write SOLID code."
