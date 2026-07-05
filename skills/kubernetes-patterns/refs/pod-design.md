# Pod Design Patterns

Multi-container pod composition patterns: sidecar, init container, and ambassador.

## Sidecar

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

## Init Container

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

## Ambassador

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
