"""
conftest.py — Shared pytest fixtures for the chaos platform test suite.

Covers:
  - tmp_path usage pattern
  - monkeypatch environment variable injection
  - HTTPX mock client (via respx or fallback)
  - Async fixture example (pytest-asyncio)
  - factory_boy factory example
  - parametrize with descriptive ids
"""

from __future__ import annotations

import asyncio
import os
from collections.abc import AsyncGenerator, Generator
from typing import Any
from unittest.mock import AsyncMock, MagicMock

import pytest

# ---------------------------------------------------------------------------
# Optional dependency guards — skip gracefully if not installed
# ---------------------------------------------------------------------------

try:
    import factory  # factory_boy
    FACTORY_BOY_AVAILABLE = True
except ImportError:
    FACTORY_BOY_AVAILABLE = False

try:
    import respx
    import httpx
    RESPX_AVAILABLE = True
except ImportError:
    RESPX_AVAILABLE = False


# ---------------------------------------------------------------------------
# 1. tmp_path-based fixture (built-in, shown for documentation)
# ---------------------------------------------------------------------------

@pytest.fixture()
def sample_config_file(tmp_path: Any) -> Any:
    """Write a temp config file and return its Path."""
    config = tmp_path / "experiment.json"
    config.write_text('{"id": "exp-001", "enabled": true}')
    return config


# ---------------------------------------------------------------------------
# 2. monkeypatch — environment variable injection
# ---------------------------------------------------------------------------

@pytest.fixture()
def clean_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """Ensure required env vars are set; remove noise vars."""
    monkeypatch.setenv("CHAOS_DB_URL", "postgresql://test:test@localhost:5432/testdb")
    monkeypatch.setenv("CHAOS_ENV", "test")
    monkeypatch.delenv("SENTRY_DSN", raising=False)


@pytest.fixture()
def no_external_calls(monkeypatch: pytest.MonkeyPatch) -> None:
    """Block all socket connections to prevent accidental external calls."""
    import socket

    def _block(*args: Any, **kwargs: Any) -> None:
        raise RuntimeError("External network calls are not allowed in unit tests")

    monkeypatch.setattr(socket, "socket", _block)


# ---------------------------------------------------------------------------
# 3. HTTPX mock via respx (falls back to MagicMock if respx not installed)
# ---------------------------------------------------------------------------

@pytest.fixture()
def mock_http() -> Generator[Any, None, None]:
    """Mock HTTP client — uses respx if available, otherwise a MagicMock."""
    if RESPX_AVAILABLE:
        with respx.mock(base_url="https://api.chaos.internal") as mock:
            mock.get("/experiments").respond(
                200,
                json={"experiments": [{"id": "exp-001", "status": "completed"}]},
            )
            mock.post("/experiments").respond(201, json={"id": "exp-002"})
            yield mock
    else:
        client = MagicMock()
        client.get.return_value = MagicMock(status_code=200, json=lambda: {"experiments": []})
        client.post.return_value = MagicMock(status_code=201, json=lambda: {"id": "exp-002"})
        yield client


# ---------------------------------------------------------------------------
# 4. Async fixtures (requires pytest-asyncio)
# ---------------------------------------------------------------------------

@pytest.fixture()
async def async_db_session() -> AsyncGenerator[Any, None]:
    """Simulate an async database session lifecycle."""
    session = AsyncMock()
    session.execute = AsyncMock(return_value=MagicMock(fetchall=lambda: []))
    session.commit = AsyncMock()
    session.rollback = AsyncMock()
    session.close = AsyncMock()
    try:
        yield session
    finally:
        await session.close()


@pytest.fixture()
def event_loop() -> Generator[asyncio.AbstractEventLoop, None, None]:
    """Provide a fresh event loop per test (pytest-asyncio mode=strict)."""
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


# ---------------------------------------------------------------------------
# 5. factory_boy factory (conditional on installation)
# ---------------------------------------------------------------------------

if FACTORY_BOY_AVAILABLE:
    import factory as f

    class ExperimentFactory(f.Factory):  # type: ignore[misc]
        """Creates ExperimentResult-like dicts for testing."""

        class Meta:
            model = dict

        id = f.Sequence(lambda n: f"exp-{n:04d}")
        status = f.Iterator(["pending", "running", "completed", "failed"])
        success = True
        duration_ms = f.LazyFunction(lambda: 1234.5)
        labels = f.LazyFunction(lambda: ["network"])

    @pytest.fixture()
    def experiment_factory() -> type[ExperimentFactory]:
        return ExperimentFactory

else:
    @pytest.fixture()
    def experiment_factory() -> Any:
        """Fallback when factory_boy is not installed."""
        def _factory(**kwargs: Any) -> dict[str, Any]:
            base: dict[str, Any] = {
                "id": "exp-0001",
                "status": "completed",
                "success": True,
                "duration_ms": 1234.5,
                "labels": ["network"],
            }
            base.update(kwargs)
            return base
        return _factory


# ---------------------------------------------------------------------------
# 6. Parametrize IDs helper — used via indirect parametrize
# ---------------------------------------------------------------------------

def pytest_make_parametrize_id(config: Any, val: Any, argname: str) -> str | None:  # noqa: ARG001
    """Generate readable IDs for parametrize: use str/repr for known types."""
    if isinstance(val, dict) and "id" in val:
        return str(val["id"])
    if isinstance(val, (int, float, str, bool)):
        return f"{argname}={val!r}"
    return None
