# Architecture Patterns

## The Dependency Rule

The most important architectural rule:

```
Source code dependencies must always point inward.

Infrastructure → Application → Domain
     (outer)       (middle)    (inner)

Domain never imports Application or Infrastructure.
Application never imports Infrastructure.
```

The domain is the most stable layer. Infrastructure (databases, APIs, frameworks) is the most volatile.

---

## Clean Architecture / Hexagonal Architecture

```
┌─────────────────────────────────────────┐
│  Infrastructure (outer ring)            │
│  ┌───────────────────────────────────┐  │
│  │  Application (use cases)          │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │  Domain (entities, rules)   │  │  │
│  │  └─────────────────────────────┘  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### Domain Layer
- Entities, value objects, domain events
- Pure business logic — no framework imports
- The most-tested layer (unit tests, no mocks needed)

### Application Layer (Use Cases)
- Orchestrates domain objects to perform a use case
- Defines **ports** (interfaces) for infrastructure
- Tested with fakes for infrastructure

### Infrastructure Layer (Adapters)
- Implements ports: database repositories, HTTP clients, message brokers
- Framework glue code
- Integration-tested against real dependencies

### Ports & Adapters
```typescript
// Port — defined in Application layer
interface OrderRepository {
  save(order: Order): Promise<void>;
  findById(id: OrderId): Promise<Order | null>;
}

// Adapter — lives in Infrastructure layer
class PostgresOrderRepository implements OrderRepository { ... }
class InMemoryOrderRepository implements OrderRepository { ... } // For tests
```

---

## Vertical Slicing

Organise by feature, not by layer. Each feature is a self-contained vertical slice.

```
src/
  orders/
    create-order/
      CreateOrderUseCase.ts
      CreateOrderRequest.ts
      CreateOrderResponse.ts
    get-order/
      GetOrderUseCase.ts
    shared/
      Order.ts
      OrderRepository.ts
  payments/
    process-payment/
      ProcessPaymentUseCase.ts
```

Benefits:
- Features can be delivered and reasoned about independently
- Team members can own vertical slices without stepping on each other
- Easier to understand the full flow of a feature

---

## Domain-Driven Design (DDD) Building Blocks

| Concept | Description |
|---------|-------------|
| **Entity** | Object with identity that persists over time |
| **Value Object** | Immutable, identity by value |
| **Aggregate** | Cluster of objects with a single root |
| **Repository** | Port for persisting/retrieving aggregates |
| **Domain Service** | Stateless operation that doesn't belong on an entity |
| **Domain Event** | Something that happened in the domain |
| **Factory** | Complex object creation logic |
| **Bounded Context** | Explicit boundary within which a model is defined |

---

## Layered Architecture (Traditional)

When Clean Architecture is overkill, a simple three-layer architecture is valid:

```
┌─────────────────┐
│  Presentation   │  Controllers, views, CLI
├─────────────────┤
│  Business Logic │  Services, domain objects
├─────────────────┤
│  Data Access    │  Repositories, DAOs
└─────────────────┘
```

Rule: dependencies flow **downward only**. Presentation never imports Data Access directly.

---

## Architecture Decision Questions

Before designing:
1. What is the core domain? What is the business problem?
2. What are the most volatile parts? (frameworks, external APIs)
3. What are the most stable parts? (business rules)
4. Where are the bounded contexts?
5. What are the contracts between contexts?
6. How will this be tested? (Drive design from testability)
