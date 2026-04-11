# Python Architect Skill

Architecture principles, structural patterns, and technology choices for Python services. Grounded in 12-factor, clean architecture, and the Python ecosystem as of 2026.

## When to Activate

- Designing a new Python service or package from scratch
- Choosing between frameworks (FastAPI vs Flask vs Django vs bare ASGI)
- Planning async vs sync strategy for a service
- Designing package boundaries and module dependencies
- Reviewing a pull request for architectural drift
- Making technology choices (ORM, messaging, caching, task queues)
- Designing for observability and testability

---

## 1. The Twelve-Factor App (Python Edition)

| Factor | Python practice |
|--------|----------------|
| Codebase | One repo, one deployable; no shared-code submodules |
| Dependencies | `pyproject.toml` + lock file (`pdm.lock`); never system-site-packages |
| Config | `os.environ` / `pydantic-settings`; fail-fast if absent; never in code |
| Backing services | Attached resources via URL env vars; swappable without code change |
| Build/release/run | `pdm build` -> Docker image -> `CMD python -m mypackage` |
| Processes | Stateless; no in-memory session state; use Redis/DB for shared state |
| Port binding | `uvicorn mypackage.main:app --host 0.0.0.0 --port 8000` |
| Concurrency | Scale via processes (Gunicorn workers) not threads |
| Disposability | Fast startup (< 3 s); graceful shutdown on SIGTERM |
| Dev/prod parity | Same Docker image in all environments; no "works on my machine" |
| Logs | Structured JSON to stdout; never write to files in code |
| Admin processes | One-off commands as `python -m mypackage.cli <command>` |

---

## 2. Application Layers

### Canonical Layer Order

```
HTTP / CLI / Worker (entrypoint)
        |
        v
   Routes / Handlers       <- thin; validate input, call service, return response
        |
        v
   Service Layer           <- business logic; orchestrates domain objects
        |
        v
   Domain / Core           <- pure functions + value objects; zero I/O
        |
        v
   Repositories / Adapters <- all I/O lives here (DB, HTTP, queues)
        |
        v
   Infrastructure          <- DB pool, HTTP client, OTel, config
```

**Rules:**
- Domain layer has zero imports from outer layers
- Service layer knows nothing about HTTP status codes
- Repositories receive connection objects via DI; they never create them
- Routes are 5-15 lines; if longer, extract to a service

### File Layout

```
src/
└── myservice/
    ├── __init__.py
    ├── main.py               # ASGI app factory
    ├── config.py             # pydantic-settings Settings
    ├── domain/               # pure business logic
    │   ├── __init__.py
    │   ├── models.py         # dataclasses / Pydantic models
    │   └── rules.py          # pure functions
    ├── service/              # use-case orchestration
    │   ├── __init__.py
    │   └── experiment.py
    ├── routes/               # HTTP handlers (thin)
    │   ├── __init__.py
    │   └── experiments.py
    ├── store/                # repository pattern
    │   ├── __init__.py
    │   └── postgres.py
    ├── infra/                # clients, pools, OTel
    │   ├── __init__.py
    │   ├── db.py
    │   └── telemetry.py
    └── cli.py                # admin commands
tests/
├── conftest.py
├── unit/
├── integration/
└── e2e/
```

---

## 3. Configuration Pattern

```python
# config.py
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import PostgresDsn, AnyHttpUrl

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    # Database
    database_url: PostgresDsn
    db_pool_size: int = 5
    db_pool_max_overflow: int = 10

    # Service
    service_name: str = "myservice"
    debug: bool = False
    log_level: str = "INFO"

    # External
    otel_exporter_otlp_endpoint: AnyHttpUrl | None = None

# Singleton -- import from here everywhere
settings = Settings()  # raises ValidationError if required vars are absent
```

**Rules:**
- Required config (DB URL, secrets) has **no default** -- fails-fast at startup
- Optional config has a sensible default
- Never pass `settings` down through function arguments -- import it
- One `Settings` class per package, not one per module

---

## 4. Framework Selection Guide

| Need | Recommended | Avoid |
|------|-------------|-------|
| High-throughput async API | FastAPI + uvicorn | Flask for async |
| Traditional web app with ORM | Django | FastAPI (over-engineering) |
| Microservice / internal API | FastAPI or Flask | Django (too heavy) |
| Background workers | Celery + Redis / RQ | cron + scripts |
| CLI tool | Click or Typer | argparse (verbose) |
| Data pipeline | Prefect / Airflow | custom scheduler |
| gRPC service | grpcio + protobuf | REST for binary protocols |

---

## 5. Async Architecture Decisions

### When to use async

| Scenario | Async? | Reason |
|----------|--------|--------|
| Database I/O (psycopg3, asyncpg) | Yes | Frees thread during I/O wait |
| HTTP calls to external services | Yes | Concurrent fan-out |
| CPU-bound computation | No | Use ProcessPoolExecutor |
| Simple CRUD API with < 100 RPS | Optional | Sync is easier to reason about |
| Chaos action runner (I/O heavy) | Yes | Many concurrent probes |

### Async rules

```python
# GOOD: executor for CPU-bound work inside async context
import asyncio
from concurrent.futures import ProcessPoolExecutor

async def run_cpu_task(data: bytes) -> dict:
    loop = asyncio.get_running_loop()
    with ProcessPoolExecutor() as pool:
        return await loop.run_in_executor(pool, heavy_computation, data)

# BAD: blocking call inside async function
async def bad_handler() -> dict:
    result = requests.get("http://api.example.com")  # blocks event loop!
    return result.json()

# GOOD: use aiohttp or httpx[async]
async def good_handler() -> dict:
    async with httpx.AsyncClient() as client:
        resp = await client.get("http://api.example.com")
        return resp.json()
```

---

## 6. Dependency Injection

Python has no DI container in its stdlib; use constructor injection:

```python
# store/base.py
from typing import Protocol

class ExperimentStore(Protocol):
    async def get(self, experiment_id: str) -> Experiment | None: ...
    async def save(self, experiment: Experiment) -> None: ...

# service/experiment.py
class ExperimentService:
    def __init__(self, store: ExperimentStore, tracer: Tracer) -> None:
        self._store = store
        self._tracer = tracer

    async def run(self, experiment_id: str) -> RunResult:
        with self._tracer.start_as_current_span("experiment.run"):
            experiment = await self._store.get(experiment_id)
            if experiment is None:
                raise NotFoundError(experiment_id)
            return await self._execute(experiment)

# main.py -- wiring at startup only
def create_app() -> FastAPI:
    app = FastAPI()
    store = PostgresExperimentStore(settings.database_url)
    tracer = trace.get_tracer(__name__)
    service = ExperimentService(store, tracer)
    app.state.service = service
    return app
```

**Why no DI container:** Python's duck typing + Protocols gives you all the power of DI without the magic. Keep it explicit.

---

## 7. Error Handling Architecture

```python
# domain/errors.py -- hierarchy rooted here
class AppError(Exception):
    """All domain errors inherit from this."""
    http_status: int = 500
    error_code: str = "INTERNAL_ERROR"

class NotFoundError(AppError):
    http_status = 404
    error_code = "NOT_FOUND"

class ValidationError(AppError):
    http_status = 422
    error_code = "VALIDATION_ERROR"

class ConflictError(AppError):
    http_status = 409
    error_code = "CONFLICT"

# routes -- single error handler at the top
from fastapi import Request
from fastapi.responses import JSONResponse

@app.exception_handler(AppError)
async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.http_status,
        content={"error": exc.error_code, "message": str(exc)},
    )
```

---

## 8. Observability Architecture

Every service must emit:

### Traces

```python
# infra/telemetry.py
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

def configure_tracing(service_name: str, otlp_endpoint: str | None) -> None:
    provider = TracerProvider(
        resource=Resource.create({"service.name": service_name})
    )
    if otlp_endpoint:
        provider.add_span_processor(
            BatchSpanProcessor(OTLPSpanExporter(endpoint=otlp_endpoint))
        )
    trace.set_tracer_provider(provider)
```

### Logs

```python
# Structured JSON logging -- never print()
import logging
import json

class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        return json.dumps({
            "timestamp": self.formatTime(record),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "trace_id": get_current_span_trace_id(),
        })
```

### Metrics

```python
from opentelemetry import metrics

meter = metrics.get_meter(__name__)

experiment_counter = meter.create_counter(
    "resilience_experiments_total",
    description="Total experiments executed",
)
```

**Naming convention:** `resilience_<component>_<metric>_<unit>`

---

## 9. Database Architecture

```python
# store/postgres.py
import asyncpg

class PostgresExperimentStore:
    def __init__(self, dsn: str) -> None:
        self._dsn = dsn
        self._pool: asyncpg.Pool | None = None

    async def connect(self) -> None:
        self._pool = await asyncpg.create_pool(self._dsn, min_size=2, max_size=10)

    async def close(self) -> None:
        if self._pool:
            await self._pool.close()

    # ALWAYS parameterised -- never f-string SQL
    async def get(self, experiment_id: str) -> Experiment | None:
        assert self._pool is not None
        row = await self._pool.fetchrow(
            "SELECT * FROM experiments WHERE id = $1", experiment_id
        )
        return Experiment(**dict(row)) if row else None
```

**Hard rules:**
- All SQL uses `$1` / `%s` parameter placeholders -- no f-strings or `.format()`
- Connection pool created once at startup; passed to store via DI
- Migrations in dedicated `migrations/` directory; run by `alembic` or `yoyo-migrations`
- Never run raw DDL in application code

---

## 10. Package Dependency Rules

```
domain/      <- imports nothing from this project
service/     <- imports domain/ only
store/       <- imports domain/ only (implements Protocol)
routes/      <- imports service/ and domain/
infra/       <- imports nothing from this project (stdlib + third-party only)
config.py    <- imports nothing from this project
main.py      <- wires everything; may import all layers
```

Use `import-linter` or `ruff` rules to enforce this statically.

---

## 11. Technology Stack (Defaults for This Project)

| Concern | Default | Alternatives |
|---------|---------|--------------|
| ASGI framework | FastAPI | Litestar, Starlette |
| ASGI server | Uvicorn + Gunicorn | Hypercorn |
| DB driver (async) | asyncpg / psycopg3 | aiosqlite |
| DB driver (sync) | psycopg2 / psycopg3 | -- |
| ORM | SQLAlchemy 2 (optional) | None for simple SQL |
| Validation | Pydantic v2 | attrs |
| Config | pydantic-settings | dynaconf |
| Task queue | Celery + Redis | RQ, Huey |
| HTTP client | httpx | aiohttp, requests |
| OTel | opentelemetry-sdk | -- |
| Testing | pytest + pytest-cov | -- |
| Linting | ruff | -- |
| Type checking | mypy | pyright |
| Security scan | bandit | semgrep |
| CVE audit | pip-audit | safety |
| Packaging | PDM | Poetry, pip |
