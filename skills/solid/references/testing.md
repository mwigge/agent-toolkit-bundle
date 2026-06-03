# Testing Strategy

## The Testing Pyramid

```
       /\
      /  \       E2E / Acceptance (few — critical paths only)
     /----\
    /      \     Integration (some — component boundaries)
   /--------\
  /          \   Unit (many — fast, isolated)
 /____________\
```

---

## Test Types

### Unit Tests
Test ONE class or function in isolation. Fast (milliseconds), no external dependencies.

```typescript
describe('Order', () => {
  it('calculates total correctly', () => {
    const order = new Order();
    order.addItem({ price: 100 });
    order.addItem({ price: 50 });
    expect(order.calculateTotal()).toBe(150);
  });
});
```

### Integration Tests
Test multiple components together. May use real infrastructure (DB).

```typescript
describe('OrderService integration', () => {
  it('saves and retrieves an order', async () => {
    const repo = new PostgresOrderRepo(testDb);
    const service = new OrderService(repo, new MockEmailService());
    const order = Order.create({ customerId: '123' });

    await service.save(order);
    const retrieved = await service.findById(order.id);

    expect(retrieved).toEqual(order);
  });
});
```

### E2E / Acceptance Tests
Test the full system from the user's perspective. Slow, brittle — critical paths only.

---

## Test Doubles

| Double | Purpose | When to Use |
|--------|---------|-------------|
| **Dummy** | Passed but never used | Fill required parameters |
| **Stub** | Returns predefined values | Control indirect inputs |
| **Spy** | Records calls for later verification | Verify indirect outputs |
| **Mock** | Pre-programmed with expected calls | Verify interactions |
| **Fake** | Working simplified implementation | Replace heavy infrastructure |

```typescript
// Fake — best for repositories
class InMemoryUserRepo implements UserRepo {
  private users = new Map<string, User>();
  async save(user: User): Promise<void> { this.users.set(user.id.value, user); }
  async findById(id: UserId): Promise<User | null> { return this.users.get(id.value) ?? null; }
}
```

---

## Testing by Layer

### Domain Layer (Most Tests)
Unit tests, no mocks. Test business rules, value objects, entities.

```typescript
describe('Money', () => {
  it('adds amounts with same currency', () => {
    expect(Money.dollars(10).add(Money.dollars(20))).toEqual(Money.dollars(30));
  });
  it('throws when adding different currencies', () => {
    expect(() => Money.dollars(10).add(Money.euros(10))).toThrow(CurrencyMismatch);
  });
});
```

### Application Layer
Integration tests with fakes for infrastructure. Test use case orchestration.

```typescript
it('creates order and sends confirmation email', async () => {
  const repo = new InMemoryOrderRepo();
  const email = { send: jest.fn() };
  const useCase = new CreateOrderUseCase(repo, email);

  await useCase.execute({ customerId: '123', items: [...] });

  expect(repo.count()).toBe(1);
  expect(email.send).toHaveBeenCalled();
});
```

### Infrastructure Layer
Integration tests with real dependencies. Test DB round-trips and external calls.

---

## Contract Tests

Verify all implementations of the same interface behave identically.

```typescript
function testUserRepoContract(createRepo: () => UserRepo) {
  describe('UserRepo contract', () => {
    it('saves and retrieves user', async () => { ... });
    it('returns null for unknown id', async () => { ... });
  });
}

testUserRepoContract(() => new InMemoryUserRepo());
testUserRepoContract(() => new PostgresUserRepo(testDb));
```

---

## Test Builders

Fluent builders for complex test objects — avoid constructor sprawl.

```typescript
class OrderBuilder {
  private props = { id: 'order-1', customerId: 'cust-1', items: [], status: 'pending' };
  withItems(items: Item[]): this { this.props.items = items; return this; }
  paid(): this { this.props.status = 'paid'; return this; }
  build(): Order { return Order.create(this.props); }
}

const order = new OrderBuilder().withItems([{ sku: 'ABC', price: 100 }]).paid().build();
```

---

## Common Testing Mistakes

| Mistake | Problem | Solution |
|---------|---------|----------|
| Testing implementation | Brittle, rewrite with refactor | Test behaviour only |
| Too many mocks | Tests prove nothing | Use fakes / real objects |
| Shared mutable state | Flaky tests | Isolate each test |
| No assertions | False confidence | Assert something meaningful |
| Slow unit tests | Slow feedback | Keep units truly isolated |
