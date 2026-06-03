# Managing Complexity

## Two Types of Complexity

**Essential complexity** — inherent to the problem domain. Cannot be eliminated.

**Accidental complexity** — introduced by our solutions. Must be eliminated.

Our job: eliminate accidental complexity while accurately modelling essential complexity.

---

## Symptoms of Accidental Complexity

### Change Amplification
A small change requires edits to many files. Sign of tight coupling, violated SRP.

### Cognitive Load
Hard to understand. Too many things to know before making a change.

### Unknown Unknowns
Surprises in behaviour. Side effects, implicit dependencies, hidden state.

---

## Principles to Fight Complexity

### YAGNI — You Aren't Gonna Need It
Don't build for hypothetical future requirements. The simplest solution that works now is correct.

```typescript
// BAD: Speculative generality
class AbstractPluginBasedNotificationSystemFactory { ... }

// GOOD: Solve today's problem
class EmailNotifier { send(to: string, message: string): void { ... } }
```

### KISS — Keep It Simple
The simplest solution that correctly solves the problem is the best solution.

### DRY — Don't Repeat Yourself
But only apply **after the Rule of Three** — wait for three duplications before abstracting.

> "A little bit of duplication is 10× better than the wrong abstraction."

### The Rule of Three
- Duplication #1 — leave it
- Duplication #2 — note it, leave it
- Duplication #3 — now extract it

---

## Simple Design (XP — priority order)

1. **Runs all the tests** — must work correctly
2. **Expresses intent** — readable, reveals purpose
3. **No duplication** — DRY (after Rule of Three)
4. **Minimal** — fewest classes and methods possible

When two solutions both pass all tests, choose the simpler one.

---

## Architecture-Level Complexity Reduction

### Vertical Slicing
Organise by feature (user story), not by layer. Each feature is a self-contained end-to-end slice.

```
orders/
  CreateOrder.ts        (use case)
  OrderRepository.ts    (port)
  PostgresOrderRepo.ts  (adapter)
  Order.ts              (entity)
  OrderItem.ts          (value object)
```

### Horizontal Decoupling
Layers must not know each other's internals. Domain never imports infrastructure.

### Bounded Contexts (DDD)
Divide large systems into cohesive contexts with explicit interfaces between them. Each context owns its language and models.

---

## Complexity Red Flags

- A method that needs to be understood before you can change an unrelated method
- A class that you need to read entirely before changing anything
- A change that forces you to read/update N other files
- Code that surprises you — behaviour you didn't expect
- Functions with more than one level of abstraction mixed together
- A module that everyone is afraid to touch
