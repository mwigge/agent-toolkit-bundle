# Service Discovery and API Gateway

Locating healthy service instances, and the edge concerns handled by an API gateway.

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
