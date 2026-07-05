# Health Checks, Autoscaling, and Config Management

Runtime concerns: probes, horizontal pod autoscaling, and configuration/secret delivery.

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
