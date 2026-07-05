---
name: microservices-architect
description: >
  Microservices architecture: service decomposition, API contracts, event-driven
  patterns, saga orchestration, CQRS, service mesh, inter-service communication,
  and distributed system design. Activate when designing service boundaries,
  choosing communication patterns, or reviewing system architecture.
version: 1.0.0
argument-hint: "[service, pattern, or architecture concern]"
---

# Microservices Architect Skill

## When to activate
- Decomposing a monolith into services
- Designing service boundaries and API contracts
- Choosing between sync and async communication
- Implementing saga, CQRS, or event sourcing patterns
- Evaluating service mesh options
- Reviewing distributed system architecture
- Designing for resilience in multi-service systems

---

## Service Decomposition

### Bounded context identification

Services should align with business domains (Domain-Driven Design):

1. **Identify business capabilities** — what does the organisation do?
2. **Map bounded contexts** — where do domain models differ?
3. **Define context maps** — how do contexts interact?
4. **Extract services** — one service per bounded context

### Decomposition checklist

- [ ] Each service owns its data (no shared databases)
- [ ] Each service has a single responsibility / bounded context
- [ ] Service can be deployed independently
- [ ] Service can be scaled independently
- [ ] Team can own and operate the service end-to-end
- [ ] API contract is well-defined and versioned
- [ ] Service has its own CI/CD pipeline

### Service sizing heuristic

| Too small | Right-sized | Too large |
|-----------|-------------|-----------|
| < 1 developer to maintain | 2-8 developers | > 12 developers |
| Trivial business logic | Cohesive bounded context | Multiple bounded contexts |
| Frequent cross-service transactions | Rare cross-service transactions | Internal domain confusion |
| High network overhead | Balanced local/remote calls | Monolith-in-disguise |

---

## API Contracts

### Synchronous communication (REST/gRPC)

Use for:
- Queries that need immediate response
- Simple CRUD operations
- External-facing APIs

```python
# Service-to-service HTTP client with resilience
import httpx
from tenacity import retry, stop_after_attempt, wait_exponential


@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=0.5, max=10),
)
async def get_experiment(experiment_id: str, base_url: str) -> dict:
    async with httpx.AsyncClient(timeout=5.0) as client:
        response = await client.get(f"{base_url}/api/experiments/{experiment_id}")
        response.raise_for_status()
        return response.json()
```

### Asynchronous communication (events/messages)

Use for:
- Commands that do not need immediate response
- Event notification across services
- Decoupling producers from consumers
- Long-running workflows

```python
from dataclasses import dataclass, field
from datetime import datetime, timezone
import uuid


@dataclass(frozen=True)
class DomainEvent:
    event_type: str
    aggregate_id: str
    payload: dict
    event_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    version: int = 1


# Example events
ExperimentCreated = lambda exp_id, name: DomainEvent(
    event_type="experiment.created",
    aggregate_id=exp_id,
    payload={"name": name},
)

ExperimentCompleted = lambda exp_id, result: DomainEvent(
    event_type="experiment.completed",
    aggregate_id=exp_id,
    payload={"result": result},
)
```

### Contract-first design

1. Define the API contract (OpenAPI / AsyncAPI / protobuf) **before** implementation
2. Generate client SDKs from the contract
3. Use contract tests to verify compatibility
4. Version contracts with semantic versioning

---

## Communication Patterns

### Pattern selection guide

| Pattern | Use when | Trade-off |
|---------|----------|-----------|
| **Request/Response** (REST, gRPC) | Need immediate answer | Tight coupling, cascading failures |
| **Async messaging** (events) | Fire-and-forget, eventual consistency OK | Complexity, ordering challenges |
| **Choreography** | Simple flows, few services | Hard to trace, no central control |
| **Orchestration** (saga) | Complex flows, need visibility | Single point of failure risk |
| **CQRS** | Read/write asymmetry | Data consistency lag |
| **Event sourcing** | Audit trail, temporal queries | Storage growth, replay complexity |

### Service discovery

```python
# Health-based service registry pattern
from dataclasses import dataclass
from datetime import datetime, timezone


@dataclass
class ServiceInstance:
    service_name: str
    host: str
    port: int
    health_url: str
    last_healthy: datetime
    metadata: dict

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.port}"

    def is_healthy(self, max_age_s: float = 30.0) -> bool:
        age = (datetime.now(timezone.utc) - self.last_healthy).total_seconds()
        return age <= max_age_s
```

---

## Data Consistency Patterns

Coordinate cross-service transactions with sagas (orchestration with compensations, or event-driven choreography), separate read and write models with CQRS, and publish events reliably from a database-per-service using the outbox pattern.

See `refs/data-patterns.md` for the saga orchestrator implementation and choreography flow, the CQRS command/query handlers, the database-per-service and distributed-transaction trade-off tables, and the outbox pattern.

---

## Service Mesh and Zero-Trust

Offload mTLS, retries, circuit breaking, traffic splitting, and observability to a service mesh, and secure inter-service traffic with zero-trust principles: mTLS everywhere, cryptographic service identity, least-privilege access policies, and network segmentation.

See `refs/mesh-security.md` for the mesh capability comparison, the Istio VirtualService traffic-management example, the zero-trust tenets and implementation checklist, and the access-policy pattern.

---

## Service Discovery and API Gateway

Locate healthy instances via client-side, server-side, DNS-based, or platform-native discovery (deregistering unhealthy instances within seconds), and centralise edge concerns — routing, composition, rate limiting, auth offloading, caching, protocol translation — in an API gateway.

See `refs/edge-discovery.md` for the discovery-approach trade-offs, health-check integration, the gateway responsibility matrix, and gateway anti-patterns.

---

## Anti-Patterns

| Anti-pattern | Fix |
|---|---|
| Shared database across services | Each service owns its data; share via APIs/events |
| Distributed monolith | If services must deploy together, merge them |
| Synchronous chains > 3 deep | Use async events for long chains |
| No API versioning | Version from day one (URL or header) |
| "Nano services" (too granular) | Merge related nano services into a cohesive service |
| No circuit breakers on inter-service calls | Add circuit breakers on every remote call |
| Ignoring eventual consistency | Design UIs and APIs to handle stale reads gracefully |
| No contract testing | Consumer-driven contract tests between services |

## References

- Reference: `refs/REFERENCES.md` — external documentation links for microservices architecture
