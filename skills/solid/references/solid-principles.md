# SOLID Principles

## Overview

SOLID helps structure software to be flexible, maintainable, and testable. These principles reduce coupling and increase cohesion.

## S — Single Responsibility Principle (SRP)

> "A class should have one, and only one, reason to change."

Each class handles ONE responsibility. If you say "and" when describing what a class does, split it.

```typescript
// BAD: Multiple responsibilities
class Order {
  calculateTotal(): number { ... }
  saveToDatabase(): void { ... }    // Persistence
  generateInvoice(): string { ... } // Presentation
}

// GOOD: Single responsibility each
class Order {
  addItem(item: OrderItem): void { ... }
  calculateTotal(): number { ... }
}
class OrderRepository {
  save(order: Order): Promise<void> { ... }
}
class InvoiceGenerator {
  generate(order: Order): Invoice { ... }
}
```

**Detection:** Does this class have multiple reasons to change? Would different stakeholders request changes to different parts?

---

## O — Open/Closed Principle (OCP)

> "Software entities should be open for extension but closed for modification."

Design abstractions that allow new behaviour through new classes, not edits to existing ones.

```typescript
// BAD: Must modify to add new shipping type
class ShippingCalculator {
  calculate(type: string, value: number): number {
    if (type === 'standard') return value < 50 ? 5 : 0;
    if (type === 'express') return 15;
    // Must add more ifs for new types!
  }
}

// GOOD: Extend by adding new classes
interface ShippingMethod {
  calculateCost(orderValue: number): number;
}
class StandardShipping implements ShippingMethod { ... }
class ExpressShipping implements ShippingMethod { ... }
class SameDayShipping implements ShippingMethod { ... } // Add without touching existing
```

**Architecture insight:** New features should be added by adding code, not changing existing code.

---

## L — Liskov Substitution Principle (LSP)

> "Subtypes must be substitutable for their base types without altering program correctness."

Subclasses must honour the contract of the parent.

```typescript
// BAD: Violates parent's contract
class DiscountPolicy {
  getDiscount(value: number): number { return 0; } // Non-negative
}
class WeirdDiscount extends DiscountPolicy {
  getDiscount(value: number): number { return -5; } // Breaks expectation!
}

// GOOD: Enforces contract via constructor guard
class DiscountPolicy {
  constructor(private discount: number) {
    if (discount < 0) throw new Error("Discount must be non-negative");
  }
  getDiscount(): number { return this.discount; }
}
```

**Key insight:** This is why you can swap `InMemoryUserRepo` for `PostgresUserRepo` — both honour the `UserRepo` interface contract.

---

## I — Interface Segregation Principle (ISP)

> "Clients should not be forced to depend on methods they do not use."

Split fat interfaces into smaller, cohesive ones.

```typescript
// BAD: Fat interface forces empty stubs
interface WarehouseDevice {
  printLabel(orderId: string): void;
  scanBarcode(): string;
  packageItem(orderId: string): void;
}
class BasicPrinter implements WarehouseDevice {
  printLabel(orderId: string): void { /* works */ }
  scanBarcode(): string { throw new Error("Not supported"); }
  packageItem(orderId: string): void { throw new Error("Not supported"); }
}

// GOOD: Segregated interfaces
interface LabelPrinter  { printLabel(orderId: string): void; }
interface BarcodeScanner { scanBarcode(): string; }
class BasicPrinter implements LabelPrinter {
  printLabel(orderId: string): void { ... }
}
```

**Detection:** If you see `throw new Error("Not implemented")` or empty method bodies, the interface is too fat.

---

## D — Dependency Inversion Principle (DIP)

> "High-level modules should not depend on low-level modules. Both should depend on abstractions."

```typescript
// BAD: Business logic locked to a concrete implementation
class OrderService {
  private emailService = new SendGridEmailService();
  confirmOrder(email: string): void {
    this.emailService.send(email, "Order confirmed");
  }
}

// GOOD: Depend on abstraction, inject implementation
interface EmailService { send(to: string, message: string): void; }
class OrderService {
  constructor(private emailService: EmailService) {}
  confirmOrder(email: string): void {
    this.emailService.send(email, "Order confirmed");
  }
}
// Inject anything: SendGrid, SES, Mock
```

**Dependency Rule:**
```
Infrastructure → Application → Domain
     (outer)       (middle)    (inner)

Dependencies flow: outer → inner. Never inner → outer.
```

---

## Quick Reference

| Principle | One-Liner | Red Flag |
|-----------|-----------|----------|
| SRP | One reason to change | "This class handles X and Y and Z" |
| OCP | Add, don't modify | `if/else` chains for types |
| LSP | Subtypes are substitutable | Type-checking in calling code |
| ISP | Small, focused interfaces | Empty method implementations |
| DIP | Depend on abstractions | `new ConcreteClass()` in business logic |
