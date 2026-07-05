# Service Mesh and Zero-Trust Networking

When to offload cross-cutting concerns to a service mesh, and the zero-trust principles for securing inter-service traffic.

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
