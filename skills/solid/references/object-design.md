# Object Design

## Object Stereotypes

Every class plays a role. Identify it before writing the class.

| Stereotype | Responsibility | Example |
|------------|---------------|---------|
| **Information Holder** | Holds data, minimal behaviour | `Address`, `Money`, `UserId` |
| **Structurer** | Manages relationships between objects | `OrderItems`, `BoundedContext` |
| **Service Provider** | Performs work, stateless operations | `TaxCalculator`, `EmailSender` |
| **Coordinator** | Orchestrates multiple services | `CheckoutUseCase`, `OrderProcessor` |
| **Controller** | Makes decisions, delegates work | `OrderPolicy`, `DiscountRule` |
| **Interfacer** | Transforms data between systems | `OrderMapper`, `PaymentAdapter` |

Naming tip: the stereotype often suggests the suffix — `Repository`, `Service`, `Factory`, `Policy`, `Mapper`.

---

## Value Objects

Domain primitives with identity defined by their value, not a database ID.

**Rules:**
- Immutable
- Validated on construction — illegal states are unrepresentable
- Compare by value, not reference
- Self-documenting (replace primitive types)

```typescript
class Money {
  constructor(
    private readonly amount: number,
    private readonly currency: Currency
  ) {
    if (amount < 0) throw new NegativeAmountError(amount);
  }

  add(other: Money): Money {
    if (!this.currency.equals(other.currency)) throw new CurrencyMismatch();
    return new Money(this.amount + other.amount, this.currency);
  }

  equals(other: Money): boolean {
    return this.amount === other.amount && this.currency.equals(other.currency);
  }
}
```

**Always wrap these as value objects:**
- IDs (`UserId`, `OrderId`)
- Emails, phone numbers, URLs
- Money / currency
- Quantities, percentages
- Coordinates, measurements
- Dates that carry business rules

---

## Entities

Domain objects with identity that persists over time.

- Identity defined by an ID, not by attribute values
- Mutable (state changes over time)
- Enforce their own invariants
- Never expose raw collections — use value objects or first-class collections

```typescript
class Order {
  private constructor(
    private readonly id: OrderId,
    private items: OrderItems,
    private status: OrderStatus
  ) {}

  static create(customerId: CustomerId): Order {
    return new Order(OrderId.generate(), OrderItems.empty(), OrderStatus.PENDING);
  }

  addItem(item: OrderItem): void {
    if (this.status !== OrderStatus.PENDING) throw new OrderAlreadyConfirmed();
    this.items = this.items.add(item);
  }

  confirm(): void {
    if (this.items.isEmpty()) throw new EmptyOrderError();
    this.status = OrderStatus.CONFIRMED;
  }
}
```

---

## Aggregates (DDD)

A cluster of entities and value objects treated as a single unit.

- **Aggregate Root** — the entry point; the only object external code should hold references to
- External code interacts with the aggregate only through the root
- The root is responsible for enforcing all invariants of the aggregate

---

## Behavioural Principles

### Tell, Don't Ask
Don't ask objects for data, make decisions, then set state back. Tell them what to do.

```typescript
// BAD: ask, decide, set
if (account.getBalance() >= amount) {
  account.setBalance(account.getBalance() - amount);
}

// GOOD: tell
account.withdraw(amount);
```

### Design by Contract
- **Preconditions** — what must be true when a method is called
- **Postconditions** — what is guaranteed after a method returns
- **Invariants** — what is always true about the object

Enforce preconditions in constructors and method guards.

### Hollywood Principle (IoC)
"Don't call us, we'll call you." High-level code defines the framework; low-level code plugs in. Achieved through dependency injection.

### Law of Demeter
A method should only call methods on:
1. `this`
2. Its own fields
3. Parameters passed to it
4. Objects it creates directly

Avoid: `order.customer.address.city` — chain three calls deep through object graphs.
