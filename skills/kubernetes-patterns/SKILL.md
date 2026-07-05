---
name: kubernetes-patterns
description: >
  Container orchestration patterns: pod design, resource management, RBAC, network
  policies, GitOps deployment, progressive delivery, health checks, autoscaling,
  secret management, and namespace strategy.
  Activate when designing workloads, configuring deployments, or reviewing
  container orchestration configurations.
version: 1.0.0
argument-hint: "[workload or orchestration concern]"
---

# Container Orchestration Patterns

## When to activate
- Designing pod configurations and sidecar patterns
- Setting resource requests, limits, and QoS classes
- Configuring RBAC roles and bindings
- Writing or reviewing network policies
- Setting up GitOps deployment pipelines
- Implementing progressive delivery (canary, blue-green)
- Configuring health checks and probes
- Designing autoscaling strategies
- Managing secrets and configuration
- Planning namespace and multi-tenancy strategy

---

## Pod Design Patterns

Compose multi-container pods with sidecar (log forwarding, mesh proxies), init container (migrations, setup), and ambassador (proxy to external services) patterns.

See `refs/pod-design.md` for the full sidecar, init container, and ambassador manifests and rules.

---

## Resource Management

### Requests and Limits

```yaml
resources:
  requests:
    cpu: 100m        # Guaranteed minimum — used for scheduling
    memory: 128Mi    # Guaranteed minimum — OOM killed if node is overcommitted
  limits:
    cpu: 500m        # Throttled above this — never OOM killed for CPU
    memory: 256Mi    # OOM killed if exceeded
```

### QoS Classes

| Class | Condition | Behaviour |
|-------|-----------|-----------|
| **Guaranteed** | requests == limits for all containers | Last to be evicted; most predictable |
| **Burstable** | At least one container has requests < limits | Evicted after BestEffort |
| **BestEffort** | No requests or limits set | First to be evicted; never use in production |

**Rules**:
- Always set both requests and limits for production workloads — never deploy BestEffort
- Set memory limits close to requests (1.5-2x) — large gaps waste node capacity
- CPU limits are optional for non-latency-sensitive workloads — CPU is compressible
- Use vertical pod autoscaler (VPA) recommendations to right-size after initial deployment
- Monitor actual usage vs. requests to identify over-provisioning

---

## Security: RBAC and Network Policies

Enforce least privilege with namespace-scoped Roles bound to per-workload service accounts, and segment traffic with default-deny NetworkPolicies plus explicit allowlists (always permitting DNS egress).

See `refs/security.md` for full RBAC Role/RoleBinding and default-deny NetworkPolicy manifests and rules.

---

## Deployment: GitOps and Progressive Delivery

Manage cluster state declaratively from Git (single source of truth, no manual `kubectl apply` in production), and roll out safely with canary, blue-green, or rolling-update strategies gated on error rate and latency.

See `refs/deployment.md` for GitOps repository structure, canary/blue-green/rolling-update manifests, and promotion criteria.

---

## Runtime: Health Checks, Autoscaling, and Config

Configure startup/liveness/readiness probes, horizontal pod autoscaling on CPU/memory/custom metrics, and external-secret sync for configuration and credentials.

See `refs/runtime.md` for probe manifests, the HorizontalPodAutoscaler spec, and the ExternalSecret pattern with rules.

---

## Namespace Strategy

| Strategy | When to use | Trade-off |
|----------|-------------|-----------|
| Per-team | Teams manage their own resources | Simple RBAC, potential resource contention |
| Per-environment | dev/staging/prod in same cluster | Clear separation, but cluster-wide failures affect all |
| Per-service | One namespace per microservice | Fine-grained isolation, many namespaces to manage |
| Hybrid | Per-team + per-environment | Most common in production; team-dev, team-staging, team-prod |

**Rules**:
- Apply resource quotas to every namespace to prevent one team from starving others
- Apply limit ranges to set default resource requests/limits for pods without explicit settings
- Use namespace labels for network policy selectors
- Production and non-production workloads should run on separate clusters, not just separate namespaces

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: payment-team-prod
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
    pods: "50"
```

---

## Anti-Patterns

| Anti-pattern | Problem | Fix |
|-------------|---------|-----|
| Privileged containers | Full host access; container escape = root on node | Set `securityContext.privileged: false`, use `securityContext.capabilities.drop: ["ALL"]` |
| `latest` image tag | Non-deterministic deployments; rollbacks impossible | Use immutable tags (semver or digest) |
| No resource limits | Pods can consume unbounded resources; OOM kills neighbours | Set requests and limits on every container |
| Running as root | Compromise of container = root access | Set `runAsNonRoot: true`, `runAsUser: 1000` |
| No network policies | All pods can communicate with all other pods | Default-deny per namespace, explicit allow rules |
| Secrets in ConfigMaps | Plaintext credentials visible to anyone with namespace access | Use Kubernetes Secrets (encrypted at rest) or external secret stores |
| Single replica in production | No high availability; any failure causes downtime | `minReplicas: 2` minimum, with pod anti-affinity |
| No pod disruption budget | Cluster upgrades or node drains take down all replicas | Set PDB with `minAvailable` or `maxUnavailable` |
| Hardcoded image registry | Cannot migrate to different registry; vendor lock-in | Use variables or Kustomize for registry prefix |
| No liveness/readiness probes | Orchestrator cannot detect unhealthy pods | Configure appropriate probes for every container |

## References

- Reference: `refs/REFERENCES.md` — external documentation links for Kubernetes patterns
