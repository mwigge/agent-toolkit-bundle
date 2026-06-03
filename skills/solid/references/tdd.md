# Test-Driven Development

## The Core Loop

```
RED → GREEN → REFACTOR → RED → ...
```

### RED Phase
Write a failing test describing the desired behaviour.
- Use domain language, not technical jargon
- Describe WHAT, not HOW
- Use a concrete example, not an abstract statement

```typescript
// BAD: abstract
it('can add numbers', () => { ... });

// GOOD: concrete example
it('when adding 2 + 3, returns 5', () => { ... });
```

### GREEN Phase
Write the **simplest possible code** to make the test pass.

1. **Fake It** — return a hardcoded value first
2. **Obvious Implementation** — if the real solution is clear

Prefer Fake It when learning. Let more tests drive the real implementation.

### REFACTOR Phase
**This is where design happens.** Look for:
- Duplication (but wait for Rule of Three)
- Long methods to extract
- Poor names to improve
- SOLID violations to fix

---

## The Three Laws of TDD

1. No production code without a failing test
2. No more test code than is sufficient to fail (compilation failures count)
3. No more production code than is sufficient to pass the one failing test

---

## The Rule of Three

Only extract duplication when you see it **three times**. Wrong abstractions are worse than duplication.

---

## Arrange-Act-Assert (AAA)

Structure every test:

```typescript
it('calculates total with 10% discount', () => {
  // ARRANGE — set up the world
  const order = new Order();
  order.addItem({ price: 100 });
  const discount = new PercentDiscount(10);

  // ACT — execute the behaviour
  const total = order.calculateTotal(discount);

  // ASSERT — verify the outcome
  expect(total).toBe(90);
});
```

### Writing AAA Backwards
1. Write the ASSERT first — what do you want to verify?
2. Write the ACT — what action produces that result?
3. Write the ARRANGE — what setup is needed?

---

## Transformation Priority Premise

When going RED → GREEN, prefer simpler transformations:

| Priority | Transformation |
|----------|----------------|
| 1 | `{}` → nil |
| 2 | nil → constant |
| 3 | constant → variable |
| 4 | unconditional → conditional |
| 5 | scalar → collection |
| 6 | statement → recursion |
| 7 | value → mutated value |

Higher priority = simpler. Don't jump to complex transformations too early.

---

## Test Naming

```typescript
// BAD: technical, implementation-focused
it('should set the data property to 1', () => { ... });

// GOOD: behaviour-focused, domain language
it('recognises "mom" as a palindrome', () => { ... });
it('calculates 20% discount for premium users', () => { ... });
it('when adding a 10% discount to a $100 order, total is $90', () => { ... });
```

---

## Classic vs Mockist TDD

**Classic (Detroit) TDD:** test with real objects; higher confidence; best for pure functions and domain logic.

**Mockist (London) TDD:** mock infrastructure; faster; best for classes that depend on databases, APIs, etc.

Start with Classic. Add mocks at infrastructure boundaries.

---

## Common Mistakes

1. Writing code before tests
2. Writing too much test (just enough to fail)
3. Writing too much production code (just enough to pass)
4. Skipping refactor (design lives here)
5. Testing implementation rather than behaviour
6. Abstract test names — use concrete examples
7. Extracting too early — wait for Rule of Three
