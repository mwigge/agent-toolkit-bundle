# GitOps and Progressive Delivery

Declarative deployment via version control, and safe rollout strategies.

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
