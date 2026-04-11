---
name: docker-expert
description: >
  Docker and container best practices: Dockerfile optimisation, multi-stage
  builds, Compose patterns, security hardening, image scanning, layer
  caching, and production container configuration. Activate when writing
  Dockerfiles, configuring Compose, or reviewing container security.
version: 1.0.0
argument-hint: "[Dockerfile, Compose file, or container concern]"
---

# Docker Expert Skill

## When to activate
- Writing or reviewing Dockerfiles
- Optimising image size and build time
- Configuring Docker Compose for development or testing
- Hardening container security
- Debugging container networking or volumes
- Setting up multi-stage builds
- Container image scanning and vulnerability management

---

## Dockerfile Best Practices

### Python multi-stage build

```dockerfile
# Stage 1: Build dependencies
FROM python:3.12-slim AS builder

WORKDIR /app

# Install PDM
RUN pip install --no-cache-dir pdm==2.20.1

# Copy dependency files first (cache layer)
COPY pyproject.toml pdm.lock ./

# Install dependencies into .venv
RUN pdm install --prod --no-self --no-editable

# Stage 2: Runtime
FROM python:3.12-slim AS runtime

# Security: non-root user
RUN groupadd --gid 1000 app && \
    useradd --uid 1000 --gid 1000 --shell /bin/false --create-home app

WORKDIR /app

# Copy virtual environment from builder
COPY --from=builder /app/.venv /app/.venv

# Copy application code
COPY src/ ./src/

# Set environment
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8000/health').raise_for_status()"

# Run as non-root
USER app

EXPOSE 8000

ENTRYPOINT ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Node.js multi-stage build

```dockerfile
# Stage 1: Install dependencies
FROM node:22-slim AS deps

WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable pnpm && pnpm install --frozen-lockfile --prod

# Stage 2: Build
FROM node:22-slim AS builder

WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable pnpm && pnpm install --frozen-lockfile
COPY . .
RUN pnpm run build

# Stage 3: Runtime
FROM node:22-slim AS runtime

RUN groupadd --gid 1000 app && \
    useradd --uid 1000 --gid 1000 --shell /bin/false --create-home app

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY package.json ./

ENV NODE_ENV=production

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "fetch('http://localhost:3000/health').then(r => { if (!r.ok) process.exit(1) })"

USER app
EXPOSE 3000

CMD ["node", "dist/main.js"]
```

### Layer caching rules

1. **Order instructions from least to most frequently changing**
2. **Copy dependency files before source code** — `COPY pyproject.toml pdm.lock ./` before `COPY src/ ./`
3. **Use `.dockerignore`** — exclude `.git`, `node_modules`, `__pycache__`, `.venv`, `*.pyc`
4. **Pin base image versions** — `python:3.12.7-slim`, not `python:latest`
5. **Combine RUN commands** — reduce layers: `RUN apt-get update && apt-get install -y ... && rm -rf /var/lib/apt/lists/*`
6. **Use `--no-cache-dir`** for pip/pdm installs

### .dockerignore template

```
.git
.gitignore
.venv
__pycache__
*.pyc
*.pyo
node_modules
dist
.env
.env.*
*.md
docs/
tests/
.coverage
htmlcov/
.mypy_cache
.pytest_cache
.ruff_cache
Dockerfile
docker-compose*.yml
```

---

## Security Hardening

### Container security checklist

- [ ] **Non-root user**: `USER app` (never run as root)
- [ ] **Read-only filesystem**: `--read-only` in Compose / `readOnlyRootFilesystem` in K8s
- [ ] **No new privileges**: `--security-opt=no-new-privileges:true`
- [ ] **Minimal base image**: `*-slim` or distroless
- [ ] **Pin base image digest**: `FROM python:3.12-slim@sha256:abc123...`
- [ ] **No secrets in image**: use env vars or mounted secrets
- [ ] **Drop capabilities**: `cap_drop: [ALL]` in Compose
- [ ] **Image scanning**: Trivy, Grype, or Snyk in CI
- [ ] **No `latest` tag in production**: always use specific version tags
- [ ] **Health check defined**: `HEALTHCHECK` instruction in Dockerfile

### Image scanning

```bash
# Trivy (recommended)
trivy image --severity HIGH,CRITICAL myapp:latest

# Grype
grype myapp:latest --fail-on high

# In CI pipeline
trivy image --exit-code 1 --severity CRITICAL myapp:$CI_COMMIT_SHA
```

### Secret management

```yaml
# NEVER do this:
# ENV DATABASE_PASSWORD=secret123

# Instead, use runtime environment variables:
services:
  api:
    environment:
      - DATABASE_URL  # passed from host env
    # Or use Docker secrets:
    secrets:
      - db_password

secrets:
  db_password:
    file: ./secrets/db_password.txt  # only in dev
    # In production, use external secret management (Vault, AWS Secrets Manager)
```

---

## Docker Compose Patterns

### Development environment

```yaml
services:
  api:
    build:
      context: .
      dockerfile: Dockerfile
      target: builder  # use build stage for dev (has dev deps)
    volumes:
      - ./src:/app/src:ro  # live reload, read-only
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://dev:dev@db:5432/chaosdb
      - LOG_LEVEL=debug
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 10s

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: chaosdb
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: dev
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dev -d chaosdb"]
      interval: 5s
      timeout: 3s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  pgdata:
```

### Testing environment

```yaml
services:
  api-test:
    build:
      context: .
      target: builder
    command: ["pytest", "--cov=src", "--cov-report=term-missing", "-v"]
    environment:
      - DATABASE_URL=postgresql://test:test@db-test:5432/testdb
      - TESTING=1
    depends_on:
      db-test:
        condition: service_healthy

  db-test:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: testdb
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
    tmpfs:
      - /var/lib/postgresql/data  # ephemeral, faster
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U test -d testdb"]
      interval: 2s
      timeout: 2s
      retries: 10
```

---

## Image Size Optimisation

### Size comparison by base image

| Base image | Size | Use case |
|-----------|------|----------|
| `python:3.12` | ~900MB | Never in production |
| `python:3.12-slim` | ~150MB | Default choice |
| `python:3.12-alpine` | ~50MB | Small but musl libc issues |
| `gcr.io/distroless/python3` | ~50MB | Maximum security, no shell |
| `node:22` | ~1GB | Never in production |
| `node:22-slim` | ~200MB | Default choice |
| `node:22-alpine` | ~130MB | Small, watch for native modules |

### Multi-stage size reduction

```dockerfile
# Build stage: has compilers, dev headers
FROM python:3.12-slim AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc libpq-dev && rm -rf /var/lib/apt/lists/*
# ... install deps ...

# Runtime stage: only runtime libraries
FROM python:3.12-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/.venv /app/.venv
```

---

## Networking

### Container DNS resolution

- Compose service names resolve to container IPs automatically
- Use service names, not `localhost` or hardcoded IPs
- For host access from container: `host.docker.internal` (Docker Desktop)

### Port mapping

```yaml
ports:
  - "8000:8000"       # host:container — accessible from host
  - "127.0.0.1:5432:5432"  # bind to localhost only
expose:
  - "8000"            # only accessible to other containers, not host
```

---

## Debugging

### Common debugging commands

```bash
# View container logs
docker compose logs -f api

# Execute shell in running container
docker compose exec api /bin/sh

# View container resource usage
docker stats

# Inspect container networking
docker inspect <container> | jq '.[0].NetworkSettings'

# Check why a container exited
docker inspect <container> --format='{{.State.ExitCode}} {{.State.Error}}'

# Build with no cache (when layers are stale)
docker compose build --no-cache api

# Prune dangling images and build cache
docker system prune -f
docker builder prune -f
```

---

## Anti-Patterns

| Anti-pattern | Fix |
|---|---|
| Running as root | Add `USER app` with non-root UID |
| Using `latest` tag | Pin specific version with digest |
| Secrets in ENV/ARG instructions | Use runtime env vars or mounted secrets |
| No `.dockerignore` | Always maintain `.dockerignore` |
| Installing dev dependencies in production image | Multi-stage build: dev deps in builder only |
| No health check | Add `HEALTHCHECK` instruction |
| `COPY . .` without `.dockerignore` | Copy only what is needed |
| Single-stage build with compiler tools | Multi-stage: compile in builder, copy artifacts to runtime |
| `apt-get update` without cleanup | Chain with `rm -rf /var/lib/apt/lists/*` |
| No resource limits in Compose | Set `mem_limit` and `cpus` |
