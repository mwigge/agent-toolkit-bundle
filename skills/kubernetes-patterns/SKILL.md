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

### Sidecar

A helper container that extends the main container's functionality without modifying it:

```yaml
spec:
  containers:
    - name: app
      image: myapp:1.2.0
      ports:
        - containerPort: 8080
    - name: log-forwarder
      image: fluentbit:2.1
      volumeMounts:
        - name: app-logs
          mountPath: /var/log/app
  volumes:
    - name: app-logs
      emptyDir: {}
```

**Use cases**: log forwarding, metrics collection, TLS termination, service mesh proxies.

**Rules**:
- Sidecar must not depend on the main container's startup order (use init containers for sequencing)
- Sidecar should have independent resource requests/limits
- Sidecar failures should not crash the main container unless the sidecar is critical

### Init Container

Runs to completion before app containers start. Use for setup tasks:

```yaml
spec:
  initContainers:
    - name: db-migration
      image: migrate:latest
      command: ["migrate", "-path", "/migrations", "-database", "$(DB_URL)", "up"]
      env:
        - name: DB_URL
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: url
  containers:
    - name: app
      image: myapp:1.2.0
```

**Use cases**: database migrations, config file generation, dependency health checks, permission setup.

### Ambassador

A proxy container that simplifies access to external services:

```yaml
spec:
  containers:
    - name: app
      image: myapp:1.2.0
      # App connects to localhost:6379 — ambassador handles routing
    - name: redis-proxy
      image: redis-proxy:1.0
      ports:
        - containerPort: 6379
      env:
        - name: REDIS_CLUSTER
          value: "redis-cluster.prod.svc.cluster.local:6379"
```

**Use cases**: connection pooling, protocol translation, service discovery abstraction.

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

## RBAC Design

### Least Privilege Principle

```yaml
# ✅ Namespace-scoped Role — preferred
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: payment-api
  name: deployment-manager
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]

---
# Bind to a service account
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: payment-api
  name: ci-deployment-manager
subjects:
  - kind: ServiceAccount
    name: ci-deployer
    namespace: payment-api
roleRef:
  kind: Role
  name: deployment-manager
  apiGroup: rbac.authorization.k8s.io
```

**Rules**:
- Prefer namespace-scoped `Role` over cluster-wide `ClusterRole`
- Use `ClusterRole` only for resources that are cluster-scoped (nodes, namespaces, PVs)
- Never grant `*` (wildcard) verbs or resources in production
- Use separate service accounts per workload — never use the `default` service account
- Audit RBAC bindings quarterly — remove stale bindings
- CI/CD service accounts should only have deploy permissions, not cluster-admin

---

## Network Policies

### Default Deny + Explicit Allow

```yaml
# Step 1: Default deny all ingress and egress in the namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: payment-api
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress

---
# Step 2: Allow specific traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-ingress
  namespace: payment-api
spec:
  podSelector:
    matchLabels:
      app: payment-api
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: api-gateway
        - podSelector:
            matchLabels:
              app: api-gateway
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: payment-api
        - podSelector:
            matchLabels:
              app: postgres
      ports:
        - protocol: TCP
          port: 5432
    - to:  # Allow DNS resolution
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
```

**Rules**:
- Start with default-deny in every namespace — then allowlist
- Always allow DNS egress (port 53 UDP) or pods cannot resolve service names
- Test network policies in staging before applying to production
- Network policies are additive — multiple policies are OR'd together
- Verify your CNI plugin supports NetworkPolicy (not all do)

---

## GitOps Deployment

Manage cluster state declaratively through version control:

**Principles**:
- The Git repository is the single source of truth for desired cluster state
- All changes go through pull/merge requests with review
- An operator continuously reconciles cluster state with the repository
- Manual `kubectl apply` is prohibited in production

**Repository structure**:
```
gitops-repo/
  base/                    # Shared manifests
    payment-api/
      deployment.yaml
      service.yaml
      kustomization.yaml
  overlays/
    dev/
      kustomization.yaml   # Dev-specific patches (replicas, resources)
    staging/
      kustomization.yaml
    prod/
      kustomization.yaml
```

**Rules**:
- Use Kustomize overlays or Helm values files for environment-specific differences
- Never use `kubectl apply` directly in production — all changes go through Git
- Image tags must be immutable (use digests or semver tags, never `latest`)
- Separate application repositories from GitOps configuration repositories

---

## Progressive Delivery

### Canary Deployment

Route a small percentage of traffic to the new version before full rollout:

```
v1 (95% traffic) ◄──── Load Balancer ────► v2 (5% traffic)
        │                                         │
        └── Monitor error rate, latency ──────────┘
            If healthy → increase to 25%, 50%, 100%
            If unhealthy → rollback to 100% v1
```

**Promotion criteria**:
- Error rate < baseline + 0.5%
- p99 latency < baseline + 20%
- No increase in 5xx responses

### Blue-Green Deployment

Run two identical environments; switch traffic atomically:

```
Blue (v1) ◄──── Active traffic
Green (v2) ◄── Idle (pre-validated)

Switch: Blue becomes idle, Green becomes active
Rollback: Reverse the switch (instant)
```

### Rolling Update (Default)

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0       # Never reduce below desired count
      maxSurge: 1             # Add one new pod at a time
  minReadySeconds: 30         # Wait 30s after ready before continuing
```

**Rules**:
- Use `maxUnavailable: 0` for zero-downtime deployments
- Set `minReadySeconds` to allow the new pod to warm up before continuing
- Always have readiness probes configured — rolling updates depend on them

---

## Health Checks

### Probe Types

```yaml
spec:
  containers:
    - name: app
      livenessProbe:
        httpGet:
          path: /healthz
          port: 8080
        initialDelaySeconds: 15
        periodSeconds: 10
        failureThreshold: 3      # 3 failures → restart container
      readinessProbe:
        httpGet:
          path: /ready
          port: 8080
        initialDelaySeconds: 5
        periodSeconds: 5
        failureThreshold: 2      # 2 failures → remove from service
      startupProbe:
        httpGet:
          path: /healthz
          port: 8080
        initialDelaySeconds: 0
        periodSeconds: 5
        failureThreshold: 30     # 30 * 5s = 150s max startup time
```

| Probe | Purpose | On failure |
|-------|---------|------------|
| **Startup** | Slow-starting apps; protects liveness probe during startup | Restart after `failureThreshold * periodSeconds` |
| **Liveness** | Detect deadlocks and unrecoverable states | Restart the container |
| **Readiness** | Determine if pod can accept traffic | Remove from Service endpoints |

**Rules**:
- Liveness checks should test only if the process is alive — not downstream dependencies
- Readiness checks should test if the pod can serve traffic — including critical dependencies
- Use startup probes for applications with variable startup times (JVM, ML model loading)
- Never make liveness probes depend on external services — a database outage should not restart all pods
- Set `initialDelaySeconds` based on actual startup time; use startup probes instead of long delays

---

## Horizontal Pod Autoscaler (HPA)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: payment-api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: payment-api
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300    # Wait 5 min before scaling down
      policies:
        - type: Percent
          value: 25                      # Remove max 25% of pods per period
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 30
      policies:
        - type: Pods
          value: 2                       # Add max 2 pods per period
          periodSeconds: 60
```

**Rules**:
- Always set `minReplicas >= 2` for production workloads (high availability)
- Scale down slowly (5 min stabilisation) to avoid flapping
- Scale up quickly (30s stabilisation) to handle traffic spikes
- Use custom metrics (requests per second, queue depth) when CPU/memory is not the bottleneck
- HPA and VPA should not target the same resource — use one or the other

---

## ConfigMap and Secret Management

### External Secrets Pattern

Sync secrets from an external store into Kubernetes Secrets:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: payment-api
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: db-credentials
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: secret/data/payment-api/db
        property: username
    - secretKey: password
      remoteRef:
        key: secret/data/payment-api/db
        property: password
```

**Rules**:
- Never store secrets in Git — use external secret stores synced via operators
- Use `refreshInterval` to rotate secrets automatically
- Mount secrets as files, not environment variables, when the secret may contain special characters
- Use separate secrets per application — never share a secret across namespaces
- ConfigMaps are for non-sensitive configuration — never put credentials in ConfigMaps

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
