---
name: ci-cd
description: CI/CD pipeline patterns for GitLab CI, GitHub Actions, and container build/release flows. Use when designing pipelines, stages, artifacts, deployment gates, or debugging failed jobs.
---

# Skill: CI/CD — Pipelines, Containers, and Deployment

## GitLab CI Structure

### Core concepts

```yaml
stages:          # ordered list — jobs in the same stage run in parallel
  - lint
  - test
  - security
  - build
  - deploy

variables:       # pipeline-level; override per job with job-level variables
  PYTHON_VERSION: "3.10"

default:
  image: python:3.10-slim
  interruptible: true          # cancel superseded pipelines on new push
  retry:
    max: 1
    when: [runner_system_failure, stuck_or_timeout_failure]
```

### Job anatomy

```yaml
unit-test:
  stage: test
  needs: [lint]                # DAG: run as soon as lint passes, not after all lint-stage jobs
  script:
    - pdm run pytest --cov=src --cov-fail-under=95
  coverage: '/TOTAL.*\s+(\d+%)$/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml
    expire_in: 7 days
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

### Key directives

| Directive | Purpose |
|-----------|---------|
| `needs` | DAG dependency — job starts as soon as its dependencies finish, regardless of stage order |
| `rules` | Conditional job inclusion; replaces deprecated `only`/`except` |
| `extends` | YAML template inheritance; use `.hidden-jobs` (dot prefix) as base templates |
| `include` | Pull in external CI config files (project templates, security templates) |
| `trigger` | Kick off a child pipeline or a different project's pipeline |
| `artifacts` | Pass files between jobs; use `expire_in` to cap storage |
| `cache` | Speed up repeated installs; key on `$CI_COMMIT_REF_SLUG` + lockfile hash |
| `environment` | Track deployments; required for protected environments with manual gates |

### Rules examples

```yaml
# Only on MRs targeting main
rules:
  - if: $CI_PIPELINE_SOURCE == "merge_request_event" && $CI_MERGE_REQUEST_TARGET_BRANCH_NAME == "main"

# Skip if commit message contains [skip ci]
rules:
  - if: $CI_COMMIT_MESSAGE =~ /\[skip ci\]/
    when: never
  - when: on_success
```

---

## GitHub Actions Structure

### Workflow triggers

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened]
  workflow_dispatch:            # manual trigger with optional inputs
    inputs:
      environment:
        type: choice
        options: [staging, production]
```

### Matrix builds

```yaml
strategy:
  fail-fast: true               # cancel remaining matrix jobs on first failure
  matrix:
    python-version: ["3.10", "3.11", "3.12"]
    os: [ubuntu-22.04]
```

### Reusable workflows

```yaml
# Caller
jobs:
  call-lint:
    uses: ./.github/workflows/lint.yml
    with:
      python-version: "3.11"
    secrets: inherit

# Reusable workflow (lint.yml)
on:
  workflow_call:
    inputs:
      python-version:
        type: string
        required: true
```

### Environments and secrets

- Define environments in GitHub Settings → Environments
- Add required reviewers for `production` environment
- Reference: `environment: production`
- Secrets in reusable workflows must be explicitly passed with `secrets: inherit` or named secrets

---

## Pipeline Design Principles

1. **Fail fast**: lint and typecheck jobs run first; no point running 10-minute test suites against unformatted code
2. **Parallel test shards**: split pytest with `--splits N --group K` (pytest-split) or use matrix
3. **Security scan in every pipeline**: SAST, SCA, and secret scanning must not be optional jobs
4. **Never skip security on `main`**: remove `rules` from security jobs or lock them to always run
5. **Artifacts over re-computation**: pass build artefacts (wheels, Docker image digests) between stages
6. **Cache keys**: always include lockfile hash — stale caches cause non-deterministic failures

```yaml
cache:
  key:
    files:
      - pdm.lock
  paths:
    - .venv/
```

---

## Docker Best Practices

### Multi-stage build

```dockerfile
# Stage 1: dependency installation (layer-cacheable)
FROM python:3.10-slim AS builder
WORKDIR /app
COPY pdm.lock pyproject.toml ./
RUN pip install pdm && pdm install --prod --no-editable

# Stage 2: production image
FROM python:3.10-slim AS runtime
WORKDIR /app

# Non-root user
RUN groupadd --gid 1001 appuser && useradd --uid 1001 --gid appuser --no-create-home appuser

COPY --from=builder --chown=appuser:appuser /app/.venv /app/.venv
COPY --chown=appuser:appuser src/ ./src/

ENV PATH="/app/.venv/bin:$PATH"
USER appuser

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

EXPOSE 8000
ENTRYPOINT ["python", "-m", "src.main"]
```

### Rules
- **Never use `latest` tag** for base images — pin to a specific digest or version tag
- **Use `COPY` not `ADD`** — `ADD` has implicit behaviours (URL fetching, tar extraction) that are rarely wanted
- **`.dockerignore`** must exclude: `.git`, `__pycache__`, `*.pyc`, `.env`, `node_modules`, test directories
- **No secrets in layers**: do not `COPY .env` or `RUN export SECRET=...`; use build secrets (`--secret`) or runtime env vars
- **`COPY --chown`** sets ownership in a single layer, avoiding a separate `RUN chown` layer
- **`HEALTHCHECK`** is required in production images; CI security scanners flag its absence

---

## Kubernetes Manifests

### Deployment: key fields

```yaml
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0       # zero-downtime rolling update
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        fsGroup: 1001
      containers:
        - name: app
          image: registry.example.com/app:1.2.3   # never :latest in prod
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 8000
            initialDelaySeconds: 5
            periodSeconds: 10
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health/live
              port: 8000
            initialDelaySeconds: 15
            periodSeconds: 20
            failureThreshold: 3
```

### HPA

```yaml
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

## Helm Charts

### Required files

```
chart/
  Chart.yaml          # name, version, appVersion, description
  values.yaml         # all configurable defaults; document every field
  templates/
    _helpers.tpl      # named templates: fullname, labels, selectorLabels
    deployment.yaml
    service.yaml
    hpa.yaml
    _NOTES.txt        # post-install instructions
```

### values.yaml discipline

- Every value must have a comment explaining its purpose
- Use `{}` or `[]` for optional maps/lists; never omit keys that templates reference
- Image tags: `image.tag` should default to `""` and be overridden at deploy time (`--set image.tag=$CI_COMMIT_SHA`)
- Secrets: never store actual secrets in `values.yaml`; reference existing Kubernetes secrets by name

---

## Security in CI

| Tool | Language | Purpose | Block on |
|------|----------|---------|---------|
| semgrep | Any | SAST — code pattern analysis | HIGH findings |
| bandit | Python | SAST — Python-specific security issues | HIGH/MEDIUM |
| pip-audit | Python | SCA — known CVEs in dependencies | any CVE (configurable) |
| npm audit | Node | SCA — known CVEs in npm deps | `--audit-level=high` |
| detect-secrets | Any | Secret scanning — pre-commit and CI | any new secret baseline violation |
| truffleHog | Any | Secret scanning — git history | any verified secret |
| trivy | Container | Container scanning — OS + app CVEs | CRITICAL, HIGH |

### Pipeline placement

- Secret scanning: run on every push, before tests (fast)
- SAST: run on every MR
- SCA: run on every MR and nightly on `main` (new CVEs appear daily)
- Container scan: run after `docker build`, before `docker push`

---

## Deployment Strategies

### Blue-Green

Two identical environments; route 100% of traffic to blue, deploy to green, then cut over. Instant rollback by re-routing. Requires double the infrastructure.

### Canary (Argo Rollouts)

```yaml
strategy:
  canary:
    steps:
      - setWeight: 5
      - pause: {duration: 2m}
      - analysis:
          templates: [{templateName: success-rate}]
      - setWeight: 50
      - pause: {duration: 5m}
      - setWeight: 100
```

Increment traffic gradually. Use analysis templates to auto-promote or auto-abort based on error rate / latency.

### Feature Flags

Decouple deployment from release. Flag off by default; enable per user / cohort. Allows dark launches and A/B testing.

---

## Release Process

1. All commits must follow Conventional Commits format
2. Run `conventional-changelog` or `release-please` to generate `CHANGELOG.md`
3. Tag: `git tag -a v1.2.3 -m "chore: release v1.2.3"`
4. Push tag: `git push origin v1.2.3`
5. CI pipeline triggers on tag, builds release artifacts, creates GitHub/GitLab release
6. Docker image tagged with semver AND `latest` (on `main` only)

### Semver rules
- `MAJOR` — breaking change (incompatible API change)
- `MINOR` — new backwards-compatible feature
- `PATCH` — backwards-compatible bug fix
- Pre-release: `1.0.0-alpha.1`, `1.0.0-rc.1`

---

## Secrets Management

- **Never** store secrets in CI variables without masking
- **Prefer** OIDC / Workload Identity over static secrets — no credential rotation needed
- Vault integration: use the Vault CI template; issue short-lived tokens per pipeline
- Rotate all static secrets every ≤90 days; automate rotation where possible
- Audit access: all secret reads should produce an audit log entry
