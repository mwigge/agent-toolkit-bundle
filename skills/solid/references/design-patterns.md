# Design Patterns

> "Let patterns emerge from refactoring, don't force them upfront."

Patterns should solve problems you **have**, not problems you **might** have.

## When to Use a Pattern

1. You recognise the problem — you've seen it before
2. The pattern fits — you're not forcing it
3. It simplifies — it doesn't add unnecessary complexity
4. Your team understands it

---

## Creational Patterns

### Factory Method
Decouple object creation from use. Create objects without specifying the exact class.

```typescript
interface Notification { send(message: string): void; }
class NotificationFactory {
  create(type: 'email' | 'sms' | 'push'): Notification {
    switch (type) {
      case 'email': return new EmailNotification();
      case 'sms':   return new SMSNotification();
      case 'push':  return new PushNotification();
    }
  }
}
```

### Builder
Construct complex objects step by step. Excellent for test data creation.

```typescript
class UserBuilder {
  private user: Partial<User> = {};
  withName(name: string): this { this.user.name = name; return this; }
  withEmail(email: string): this { this.user.email = email; return this; }
  build(): User { return new User(this.user.name!, new Email(this.user.email!)); }
}
const user = new UserBuilder().withName('Alice').withEmail('alice@example.com').build();
```

### Prototype
Create objects by cloning existing ones. Useful when creation is expensive.

---

## Structural Patterns

### Adapter
Make incompatible interfaces work together. Essential when integrating third-party libraries.

```typescript
interface PaymentGateway { charge(amount: Money): ChargeResult; }

// Adapt legacy API to our interface
class OldPaymentAdapter implements PaymentGateway {
  constructor(private oldAPI: OldPaymentAPI) {}
  charge(amount: Money): ChargeResult {
    const success = this.oldAPI.makePayment(amount.toCents());
    return success ? ChargeResult.success() : ChargeResult.failed();
  }
}
```

### Decorator
Add behaviour to objects dynamically without subclassing (OCP).

```typescript
interface Notifier { send(message: string): void; }
class SMSDecorator implements Notifier {
  constructor(private wrapped: Notifier) {}
  send(message: string): void {
    this.wrapped.send(message);
    smsClient.send(message); // Additional behaviour
  }
}
// Compose: Email + SMS + Slack without modifying any class
const notifier = new SlackDecorator(new SMSDecorator(new EmailNotifier()));
```

### Proxy
Control access to an object. Use for lazy loading, caching, or access control.

### Composite
Treat individual objects and compositions uniformly. Use for tree structures (files/folders, UI).

---

## Behavioral Patterns

### Strategy
Define a family of algorithms, make them interchangeable at runtime.

```typescript
interface PricingStrategy { calculate(base: number): number; }
class RegularPricing    implements PricingStrategy { calculate(b) { return b; } }
class PremiumDiscount   implements PricingStrategy { calculate(b) { return b * 0.8; } }
class BlackFriday       implements PricingStrategy { calculate(b) { return b * 0.5; } }

class ShoppingCart {
  constructor(private pricing: PricingStrategy) {}
  total(items: Item[]): number {
    return this.pricing.calculate(items.reduce((s, i) => s + i.price, 0));
  }
}
```

### Observer
Notify multiple objects about events. Decouples producers from consumers.

```typescript
interface Observer { update(event: DomainEvent): void; }
class OrderService {
  private observers: Observer[] = [];
  subscribe(o: Observer): void { this.observers.push(o); }
  placeOrder(order: Order): void {
    // process…
    this.observers.forEach(o => o.update({ type: 'ORDER_PLACED', order }));
  }
}
```

### Command
Encapsulate a request as an object. Supports undo/redo, queuing, logging.

### Template Method
Define algorithm skeleton in base class, let subclasses override steps.

---

## Pattern Selection Guide

| Problem | Pattern |
|---------|---------|
| Multiple interchangeable algorithms | Strategy |
| React to events without tight coupling | Observer |
| Build complex objects step by step | Builder |
| Add behaviour without subclassing | Decorator |
| Adapt incompatible interface | Adapter |
| Create objects without specifying class | Factory Method |
| Encapsulate request for undo/queue | Command |
| Control access / lazy load | Proxy |
| Uniform treatment of tree structures | Composite |
