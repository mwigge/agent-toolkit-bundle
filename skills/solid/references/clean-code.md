# Clean Code Practices

## What is Clean Code?

Code that is easy to understand, easy to change, easy to test, and simple.

Code has three consumers:
1. **Users** — get their needs met
2. **Customers** — make or save money
3. **Developers** — must maintain it

Developers read code 10× more than they write it. Design for readability.

---

## Naming Principles (priority order)

1. **Consistency** — same concept = same name everywhere
2. **Understandability** — domain language, not technical jargon
3. **Specificity** — avoid `data`, `info`, `manager`, `handler`, `utils`
4. **Brevity** — short but not cryptic
5. **Searchability** — unique, greppable names
6. **Pronounceability** — say it in conversation
7. **Austerity** — no redundant filler words (`userData` → `user`)

```typescript
// BAD
const usrLst = getUsrs();
class DataManager {}
function processInfo(data) {}

// GOOD
const activeUsers = getActiveUsers();
class OrderRepository {}
function validatePayment(payment) {}
```

---

## Object Calisthenics — 9 Rules

### 1. One Level of Indentation per Method
```typescript
// BAD: multiple levels
function process(orders: Order[]) {
  for (const order of orders) {
    if (order.isValid()) {
      for (const item of order.items) {
        if (item.inStock) { /* ... */ }
      }
    }
  }
}

// GOOD: extract methods
function process(orders: Order[]) {
  orders.filter(o => o.isValid()).forEach(processOrder);
}
```

### 2. Don't Use `else` — Use Early Returns
```typescript
// BAD
function getDiscount(user: User): number {
  if (user.isPremium) { return 20; } else { return 0; }
}

// GOOD
function getDiscount(user: User): number {
  if (user.isPremium) return 20;
  return 0;
}
```

### 3. Wrap All Primitives in Domain Objects
```typescript
// BAD: primitive obsession
function createUser(email: string, age: number) {}

// GOOD: value objects
class Email { constructor(private value: string) { validate(value); } }
class Age  { constructor(private value: number) { if (value < 0) throw new InvalidAge(); } }
function createUser(email: Email, age: Age) {}
```

### 4. First-Class Collections
```typescript
// BAD: collection mixed with other state
class Order { items: OrderItem[]; customerId: string; total: number; }

// GOOD: collection is its own class
class OrderItems {
  constructor(private items: OrderItem[] = []) {}
  add(item: OrderItem): void { ... }
  total(): Money { ... }
}
```

### 5. One Dot per Line (Law of Demeter)
```typescript
// BAD: train wreck
const city = order.customer.address.city;

// GOOD: tell, don't ask
const city = order.getShippingCity();
```

### 6. Don't Abbreviate
```typescript
// BAD
const custRepo = new CustRepo();

// GOOD
const customerRepository = new CustomerRepository();
```

### 7. Keep All Entities Small
- Classes: < 50 lines
- Methods: < 10 lines

### 8. No Classes with More Than Two Instance Variables
Forces small, focused classes composed of smaller objects.

### 9. No Getters/Setters — Behaviour-Rich Objects
```typescript
// BAD: data bag
if (account.getBalance() >= amount) {
  account.setBalance(account.getBalance() - amount);
}

// GOOD: tell, object decides
const result = account.withdraw(amount);
```

---

## Comments

Write comments only to explain **WHY**, never WHAT or HOW.

```typescript
// BAD: explains what (redundant)
// Add 1 to counter
counter++;

// GOOD: explains why
// Compensate for 0-based indexing in legacy API
counter++;
```

Prefer self-documenting code over comments:
```typescript
// BAD: comment needed
if (user.subscriptionLevel >= 2 && !user.isBanned) { }

// GOOD: self-documenting
if (user.canAccessPremiumFeatures()) { }
```

---

## Formatting

- Related code together, blank lines between concepts
- High-level / public API at top, details below
- Max line length ~80–120 characters
- Code reads top-to-bottom like a story

```typescript
class OrderProcessor {
  process(order: Order): ProcessResult {
    this.validate(order);
    this.calculateTotals(order);
    return this.save(order);
  }

  private validate(order: Order): void { ... }
  private calculateTotals(order: Order): void { ... }
  private save(order: Order): ProcessResult { ... }
}
```

---

## Security Note

When validating against an object/map, always use `Object.hasOwn(obj, key)` — never the `in` operator, which matches prototype-inherited keys and can be exploited.
