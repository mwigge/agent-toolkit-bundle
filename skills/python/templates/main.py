"""
Template: main.py — application composition root.
The ONLY place where concrete implementations are wired together.
Domain, services, and repositories must never call `new` on their own.
"""
from __future__ import annotations

import logging
import os
import sys

import structlog
from my_service.config import Config
from my_service.infra.db import create_pool
from my_service.infra.otel import configure_otel
from my_service.store.postgres import PostgresExperimentStore
from my_service.service.experiments import ExperimentService


def configure_logging() -> None:
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
    )


def get_required_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        print(f"FATAL: required env var {name!r} is not set", file=sys.stderr)  # noqa: T201
        sys.exit(1)
    return value


async def main() -> None:
    configure_logging()
    log = structlog.get_logger(__name__)

    config = Config(
        database_url=get_required_env("DATABASE_URL"),
        service_name=os.environ.get("SERVICE_NAME", "my-service"),
    )

    configure_otel(config.service_name)
    pool = await create_pool(config.database_url)

    # Composition root — wire dependencies here
    store = PostgresExperimentStore(pool)
    service = ExperimentService(store=store)  # noqa: F841

    log.info("service.started", service=config.service_name)
    # ... start server / worker


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
