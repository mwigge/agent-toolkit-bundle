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

## Service Mesh

### When to use a service mesh

| Concern | Without mesh | With mesh (Istio/Linkerd) |
|---------|-------------|--------------------------|
| mTLS | Manual cert management | Automatic |
| Retry/timeout | In application code | Sidecar config |
| Circuit breaker | Library (tenacity) | Sidecar config |
| Traffic splitting | Load balancer rules | VirtualService |
| Observability | SDK instrumentation | Automatic proxy metrics |
| Rate limiting | Application middleware | Sidecar policy |

### Traffic management example (Istio)

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: chaos-api
spec:
  hosts:
    - chaos-api
  http:
    - match:
        - headers:
            x-canary:
              exact: "true"
      route:
        - destination:
            host: chaos-api
            subset: canary
    - route:
        - destination:
            host: chaos-api
            subset: stable
          weight: 95
        - destination:
            host: chaos-api
            subset: canary
          weight: 5
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

---

## Service Discovery Patterns

### Discovery approaches

| Approach | How it works | Trade-offs |
|----------|-------------|------------|
| **Client-side discovery** | Client queries a service registry, then calls the chosen instance directly | Client must implement load balancing; flexible routing; no single proxy bottleneck |
| **Server-side discovery** | Client calls a load balancer/proxy, which queries the registry and routes | Simpler clients; proxy can become a bottleneck; additional infrastructure |
| **DNS-based discovery** | Services register DNS records; clients resolve hostname to instance IPs | Simple, universal; limited load balancing options; DNS TTL caching can cause staleness |
| **Platform-native (Kubernetes Services)** | Platform provides built-in service discovery via internal DNS and endpoints | No extra infrastructure; tightly coupled to platform; handles health checks natively |

### Health check integration

Service discovery is only useful if unhealthy instances are removed promptly:

- **Liveness check** — is the process running? (restart if not)
- **Readiness check** — can the service handle requests? (remove from load balancer if not)
- **Startup check** — has the service finished initialising? (do not send traffic until ready)

```python
@dataclass
class HealthCheck:
    endpoint: str                  # e.g., "/health/ready"
    interval_s: float = 10.0      # check every N seconds
    timeout_s: float = 3.0        # response must arrive within N seconds
    healthy_threshold: int = 2    # consecutive successes to mark healthy
    unhealthy_threshold: int = 3  # consecutive failures to mark unhealthy
```

### Key principle

Deregister unhealthy instances within seconds, not minutes. A stale registry is worse than no registry.

---

## API Gateway Patterns

An API gateway sits at the edge and provides cross-cutting concerns for all backend services.

### Core responsibilities

| Concern | What the gateway does | Why at the gateway |
|---------|----------------------|-------------------|
| **Request routing** | Route requests to the correct backend service based on path, headers, or method | Single entry point; clients do not need to know about internal service topology |
| **Request composition** | Aggregate responses from multiple services into a single response | Reduces client round-trips; simplifies frontend code |
| **Rate limiting and throttling** | Enforce request quotas per client, API key, or endpoint | Protects backend services from overload; applied consistently |
| **Authentication offloading** | Validate tokens, API keys, or certificates before forwarding | Backend services trust the gateway; reduces duplicated auth logic |
| **Response caching** | Cache responses for idempotent endpoints (GET) with appropriate TTLs | Reduces backend load; improves response times for repeat requests |
| **Protocol translation** | Accept REST from external clients, forward as gRPC (or vice versa) internally | Allows internal services to use efficient protocols without exposing them externally |

### Gateway anti-patterns

| Anti-pattern | Fix |
|---|---|
| Business logic in the gateway | Gateway routes and enforces policies; business logic belongs in services |
| Single monolithic gateway | Use one gateway per domain or per team (Backend-for-Frontend pattern) |
| No rate limiting | Always rate-limit; start conservative and relax based on data |
| Gateway as the only auth layer | Defence in depth — services should validate their own authorization |

---

## Zero-Trust Networking Principles

In a microservices architecture, assume the network is hostile — even between internal services.

### Core tenets

1. **Mutual TLS (mTLS) between all services** — every service-to-service call is encrypted and both sides present certificates. No "trusted network" exceptions.

2. **Service identity verification** — each service has a cryptographic identity (certificate, SPIFFE ID). Verify identity on every request, not just at the network boundary.

3. **Least-privilege access policies** — each service is authorized to call only the specific endpoints it needs. Default-deny; explicitly allow.

4. **Network segmentation** — group services by trust level or domain. A compromised service in one segment cannot reach services in another segment without explicit policy.

### Implementation checklist

- [ ] All service-to-service communication uses mTLS
- [ ] Certificates are short-lived and automatically rotated
- [ ] Each service has a unique identity (not shared credentials)
- [ ] Access policies are defined per-service, per-endpoint (not per-network)
- [ ] Network policies restrict traffic to declared dependencies only
- [ ] Egress traffic is controlled — services cannot reach arbitrary external endpoints
- [ ] All policy changes are auditable (version-controlled or logged)

### Access policy pattern

```python
from dataclasses import dataclass


@dataclass
class ServiceAccessPolicy:
    """Define which services can call which endpoints."""
    source_service: str
    target_service: str
    allowed_endpoints: list[str]       # e.g., ["GET /api/experiments", "POST /api/results"]
    allowed_methods: list[str] | None = None  # if None, inferred from endpoints

    def is_allowed(self, method: str, path: str) -> bool:
        return f"{method} {path}" in self.allowed_endpoints


# Example: experiment-runner can read experiments and write results, nothing else
POLICIES = [
    ServiceAccessPolicy(
        source_service="experiment-runner",
        target_service="chaos-api",
        allowed_endpoints=["GET /api/experiments", "POST /api/results"],
    ),
]
```

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
