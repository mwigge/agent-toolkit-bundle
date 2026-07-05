# Data Consistency Patterns

Saga orchestration and choreography, CQRS, database-per-service ownership, and the outbox pattern for reliable event publishing.

## Saga Pattern

### Orchestration-based saga

```python
from dataclasses import dataclass, field
from enum import Enum
from typing import Callable, Awaitable


class StepStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    COMPENSATED = "compensated"


@dataclass
class SagaStep:
    name: str
    action: Callable[..., Awaitable[dict]]
    compensation: Callable[..., Awaitable[None]]
    status: StepStatus = StepStatus.PENDING
    result: dict | None = None


@dataclass
class Saga:
    name: str
    steps: list[SagaStep] = field(default_factory=list)

    async def execute(self, context: dict) -> dict:
        completed: list[SagaStep] = []
        for step in self.steps:
            step.status = StepStatus.RUNNING
            try:
                step.result = await step.action(context)
                step.status = StepStatus.COMPLETED
                completed.append(step)
                context.update(step.result)
            except Exception as exc:
                step.status = StepStatus.FAILED
                # Compensate in reverse order
                for comp_step in reversed(completed):
                    try:
                        await comp_step.compensation(context)
                        comp_step.status = StepStatus.COMPENSATED
                    except Exception:
                        pass  # log compensation failure
                raise RuntimeError(
                    f"Saga '{self.name}' failed at step '{step.name}': {exc}"
                ) from exc
        return context
```

### Choreography-based saga (event-driven)

```
[Order Service]
    --publishes--> OrderCreated
        --> [Payment Service] processes payment
            --publishes--> PaymentCompleted
                --> [Inventory Service] reserves stock
                    --publishes--> StockReserved
                        --> [Order Service] confirms order

On failure at any step:
    Compensating events are published in reverse
```

---

## CQRS Pattern

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass


# Command side — writes
class Command(ABC):
    pass


@dataclass
class CreateExperiment(Command):
    name: str
    target_service: str
    fault_type: str


class CommandHandler(ABC):
    @abstractmethod
    async def handle(self, command: Command) -> str:
        """Execute command, return aggregate ID."""


# Query side — reads (can use a denormalised read model)
class Query(ABC):
    pass


@dataclass
class GetExperimentSummary(Query):
    experiment_id: str


class QueryHandler(ABC):
    @abstractmethod
    async def handle(self, query: Query) -> dict:
        """Execute query, return read model."""
```

---

## Data Management

### Database-per-service

Each service owns its data store. No direct database access across service boundaries.

| Pattern | Use case |
|---------|----------|
| Private database per service | Default — strongest isolation |
| Shared database, separate schemas | Acceptable for small teams, migration path |
| Event-carried state transfer | Share data via events, each service keeps a local copy |
| API composition | Query multiple services, aggregate in API gateway |

### Distributed transaction alternatives

| Approach | Consistency | Complexity |
|----------|------------|------------|
| Two-phase commit (2PC) | Strong | High, poor availability |
| Saga (orchestration) | Eventual | Medium |
| Saga (choreography) | Eventual | Medium-High (tracing) |
| Outbox pattern | Eventual, reliable | Low-Medium |

### Outbox pattern

```python
async def create_experiment_with_outbox(
    db,
    experiment: dict,
    event: DomainEvent,
) -> str:
    """
    Write to the experiments table and the outbox table in a single
    database transaction. A separate process polls the outbox and
    publishes events to the message broker.
    """
    async with db.transaction():
        experiment_id = await db.execute(
            "INSERT INTO experiments (name, config) VALUES ($1, $2) RETURNING id",
            experiment["name"],
            experiment["config"],
        )
        await db.execute(
            "INSERT INTO outbox (event_type, aggregate_id, payload) VALUES ($1, $2, $3)",
            event.event_type,
            str(experiment_id),
            event.payload,
        )
    return str(experiment_id)
```
