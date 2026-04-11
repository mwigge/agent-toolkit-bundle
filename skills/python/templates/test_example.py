"""
test_example.py — Example test module demonstrating pytest best practices.

Shows:
  - @pytest.mark.parametrize with ids
  - Fixture injection
  - Hypothesis @given property-based test
  - Async test with pytest-asyncio
  - HTTP mocking with respx
  - Exception assertion
  - Structured test organisation (Arrange-Act-Assert)
"""

from __future__ import annotations

import pytest

# Optional imports — tests skip gracefully if not installed
try:
    from hypothesis import given, settings
    from hypothesis import strategies as st
    HYPOTHESIS_AVAILABLE = True
except ImportError:
    HYPOTHESIS_AVAILABLE = False

try:
    import respx
    import httpx
    RESPX_AVAILABLE = True
except ImportError:
    RESPX_AVAILABLE = False

# ---------------------------------------------------------------------------
# Module under test (inline for self-contained example)
# ---------------------------------------------------------------------------

def compute_resilience_score(
    success_rate: float,
    mttr_seconds: float,
    blast_radius: float,
) -> float:
    """Compute a resilience score in the range [0, 100]."""
    if not (0.0 <= success_rate <= 1.0):
        raise ValueError(f"success_rate must be in [0, 1], got {success_rate}")
    if mttr_seconds < 0:
        raise ValueError(f"mttr_seconds must be >= 0, got {mttr_seconds}")
    if not (0.0 <= blast_radius <= 1.0):
        raise ValueError(f"blast_radius must be in [0, 1], got {blast_radius}")

    availability = success_rate * (1 - blast_radius * 0.1)
    recovery_factor = 1.0 / (1.0 + mttr_seconds / 3600)
    return round(availability * recovery_factor * 100, 2)

async def fetch_experiment(client: httpx.AsyncClient, experiment_id: str) -> dict:  # type: ignore[type-arg]
    """Fetch experiment data from the chaos API."""
    response = await client.get(f"/experiments/{experiment_id}")
    response.raise_for_status()
    return response.json()  # type: ignore[no-any-return]

# ---------------------------------------------------------------------------
# 1. Parametrize with descriptive ids
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    ("success_rate", "mttr_seconds", "blast_radius", "expected_min", "expected_max"),
    [
        pytest.param(1.0, 0.0, 0.0, 99.9, 100.1, id="perfect-conditions"),
        pytest.param(0.99, 120.0, 0.1, 90.0, 99.0, id="high-availability"),
        pytest.param(0.95, 600.0, 0.5, 70.0, 90.0, id="degraded"),
        pytest.param(0.0, 0.0, 0.0, -0.1, 0.1, id="complete-failure"),
    ],
)
def test_resilience_score_range(
    success_rate: float,
    mttr_seconds: float,
    blast_radius: float,
    expected_min: float,
    expected_max: float,
) -> None:
    score = compute_resilience_score(success_rate, mttr_seconds, blast_radius)
    assert expected_min <= score <= expected_max, (
        f"Score {score} out of expected range [{expected_min}, {expected_max}]"
    )

# ---------------------------------------------------------------------------
# 2. Fixture injection
# ---------------------------------------------------------------------------

def test_config_file_content(sample_config_file: object) -> None:  # type: ignore[type-arg]
    """sample_config_file fixture from conftest.py."""
    from pathlib import Path
    path = sample_config_file  # type: ignore[assignment]
    assert isinstance(path, Path)
    assert path.exists()
    content = path.read_text()
    assert "exp-001" in content

def test_env_injection(clean_env: None) -> None:
    """clean_env fixture sets required env vars."""
    import os
    assert os.environ["CHAOS_ENV"] == "test"
    assert "SENTRY_DSN" not in os.environ

# ---------------------------------------------------------------------------
# 3. Hypothesis property-based test
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not HYPOTHESIS_AVAILABLE, reason="hypothesis not installed")
@given(
    success_rate=st.floats(min_value=0.0, max_value=1.0, allow_nan=False),
    mttr_seconds=st.floats(min_value=0.0, max_value=86400.0, allow_nan=False),
    blast_radius=st.floats(min_value=0.0, max_value=1.0, allow_nan=False),
)
@settings(max_examples=200)
def test_resilience_score_always_in_bounds(
    success_rate: float,
    mttr_seconds: float,
    blast_radius: float,
) -> None:
    """Property: score is always in [0, 100] for valid inputs."""
    score = compute_resilience_score(success_rate, mttr_seconds, blast_radius)
    assert 0.0 <= score <= 100.0

# ---------------------------------------------------------------------------
# 4. Exception assertions
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    ("kwargs", "error_fragment"),
    [
        pytest.param(
            {"success_rate": 1.5, "mttr_seconds": 0.0, "blast_radius": 0.0},
            "success_rate must be in",
            id="invalid-success-rate-high",
        ),
        pytest.param(
            {"success_rate": 0.9, "mttr_seconds": -1.0, "blast_radius": 0.0},
            "mttr_seconds must be",
            id="negative-mttr",
        ),
        pytest.param(
            {"success_rate": 0.9, "mttr_seconds": 0.0, "blast_radius": 2.0},
            "blast_radius must be in",
            id="invalid-blast-radius",
        ),
    ],
)
def test_resilience_score_invalid_inputs(kwargs: dict, error_fragment: str) -> None:
    with pytest.raises(ValueError, match=error_fragment):
        compute_resilience_score(**kwargs)

# ---------------------------------------------------------------------------
# 5. Async test with mocked HTTP (respx)
# ---------------------------------------------------------------------------

@pytest.mark.skipif(not RESPX_AVAILABLE, reason="respx/httpx not installed")
@pytest.mark.asyncio
async def test_fetch_experiment_success() -> None:
    with respx.mock(base_url="https://api.chaos.internal") as mock:
        mock.get("/experiments/exp-001").respond(
            200,
            json={"id": "exp-001", "status": "completed", "success": True},
        )
        async with httpx.AsyncClient(base_url="https://api.chaos.internal") as client:
            result = await fetch_experiment(client, "exp-001")

    assert result["id"] == "exp-001"
    assert result["success"] is True

@pytest.mark.skipif(not RESPX_AVAILABLE, reason="respx/httpx not installed")
@pytest.mark.asyncio
async def test_fetch_experiment_not_found() -> None:
    with respx.mock(base_url="https://api.chaos.internal") as mock:
        mock.get("/experiments/missing").respond(404)
        async with httpx.AsyncClient(base_url="https://api.chaos.internal") as client:
            with pytest.raises(httpx.HTTPStatusError):
                await fetch_experiment(client, "missing")

# ---------------------------------------------------------------------------
# 6. factory_boy usage
# ---------------------------------------------------------------------------

def test_experiment_factory_defaults(experiment_factory: object) -> None:
    exp = experiment_factory()  # type: ignore[operator]
    assert "id" in exp
    assert exp["success"] is True

def test_experiment_factory_override(experiment_factory: object) -> None:
    exp = experiment_factory(success=False, status="failed")  # type: ignore[operator]
    assert exp["success"] is False
    assert exp["status"] == "failed"
