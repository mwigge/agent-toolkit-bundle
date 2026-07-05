# RBAC and Network Policy Design

Least-privilege access control and network segmentation for cluster workloads.

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
