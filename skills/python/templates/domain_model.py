"""
domain_model.py — Example Clean Architecture domain layer for a chaos platform.

Demonstrates:
  - Domain entity (dataclass, no infrastructure imports)
  - Value object (frozen dataclass)
  - Domain event
  - Repository protocol (Abstract Base Class + Protocol)
  - Application service function

NO infrastructure imports. NO framework imports (SQLAlchemy, FastAPI, etc.).
"""

from __future__ import annotations

import uuid
from abc import abstractmethod
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum, auto
from typing import Protocol


# ---------------------------------------------------------------------------
# Value Objects — immutable, equality by value, no identity
# ---------------------------------------------------------------------------

@dataclass(frozen=True, slots=True)
class ExperimentId:
    """Typed wrapper around experiment UUID — prevents stringly-typed IDs."""

    value: str

    def __post_init__(self) -> None:
        if not self.value:
            raise ValueError("ExperimentId cannot be empty")
        # Validate UUID format
        uuid.UUID(self.value)

    @classmethod
    def generate(cls) -> ExperimentId:
        return cls(value=str(uuid.uuid4()))

    def __str__(self) -> str:
        return self.value


@dataclass(frozen=True, slots=True)
class BlastRadius:
    """Fraction of the system affected by an experiment (0.0 – 1.0)."""

    value: float

    def __post_init__(self) -> None:
        if not (0.0 <= self.value <= 1.0):
            raise ValueError(f"BlastRadius must be between 0 and 1, got {self.value}")

    @classmethod
    def none(cls) -> BlastRadius:
        return cls(value=0.0)

    @classmethod
    def full(cls) -> BlastRadius:
        return cls(value=1.0)


# ---------------------------------------------------------------------------
# Domain Enumerations
# ---------------------------------------------------------------------------

class ExperimentStatus(Enum):
    PENDING = auto()
    RUNNING = auto()
    COMPLETED = auto()
    FAILED = auto()
    ABORTED = auto()


# ---------------------------------------------------------------------------
# Domain Entity — has identity, mutable lifecycle
# ---------------------------------------------------------------------------

@dataclass
class Experiment:
    """Core domain entity representing a chaos experiment."""

    id: ExperimentId
    name: str
    blast_radius: BlastRadius
    status: ExperimentStatus = field(default=ExperimentStatus.PENDING)
    created_at: datetime = field(default_factory=lambda: datetime.now(tz=timezone.utc))
    started_at: datetime | None = None
    completed_at: datetime | None = None
    success: bool | None = None
    _domain_events: list[DomainEvent] = field(default_factory=list, repr=False)

    def start(self) -> None:
        if self.status != ExperimentStatus.PENDING:
            raise ValueError(f"Cannot start experiment in status {self.status.name}")
        self.status = ExperimentStatus.RUNNING
        self.started_at = datetime.now(tz=timezone.utc)
        self._domain_events.append(
            ExperimentStarted(experiment_id=self.id, occurred_at=self.started_at)
        )

    def complete(self, *, success: bool) -> None:
        if self.status != ExperimentStatus.RUNNING:
            raise ValueError(f"Cannot complete experiment in status {self.status.name}")
        self.status = ExperimentStatus.COMPLETED if success else ExperimentStatus.FAILED
        self.success = success
        self.completed_at = datetime.now(tz=timezone.utc)
        self._domain_events.append(
            ExperimentCompleted(
                experiment_id=self.id,
                success=success,
                occurred_at=self.completed_at,
            )
        )

    def abort(self) -> None:
        if self.status not in (ExperimentStatus.PENDING, ExperimentStatus.RUNNING):
            raise ValueError(f"Cannot abort experiment in status {self.status.name}")
        self.status = ExperimentStatus.ABORTED
        self._domain_events.append(
            ExperimentAborted(experiment_id=self.id, occurred_at=datetime.now(tz=timezone.utc))
        )

    def pull_events(self) -> list[DomainEvent]:
        """Drain and return accumulated domain events."""
        events = list(self._domain_events)
        self._domain_events.clear()
        return events

    @classmethod
    def create(cls, name: str, blast_radius: float = 0.1) -> Experiment:
        return cls(
            id=ExperimentId.generate(),
            name=name,
            blast_radius=BlastRadius(value=blast_radius),
        )


# ---------------------------------------------------------------------------
# Domain Events — plain dataclasses, serialisable, no side effects
# ---------------------------------------------------------------------------

@dataclass(frozen=True, slots=True)
class DomainEvent:
    experiment_id: ExperimentId
    occurred_at: datetime


@dataclass(frozen=True, slots=True)
class ExperimentStarted(DomainEvent):
    pass


@dataclass(frozen=True, slots=True)
class ExperimentCompleted(DomainEvent):
    success: bool


@dataclass(frozen=True, slots=True)
class ExperimentAborted(DomainEvent):
    pass


# ---------------------------------------------------------------------------
# Repository Protocol — the port; infrastructure provides the adapter
# ---------------------------------------------------------------------------

class ExperimentRepository(Protocol):
    """Abstract persistence contract — implemented in infrastructure layer."""

    @abstractmethod
    def save(self, experiment: Experiment) -> None: ...

    @abstractmethod
    def get_by_id(self, experiment_id: ExperimentId) -> Experiment | None: ...

    @abstractmethod
    def list_by_status(self, status: ExperimentStatus) -> Sequence[Experiment]: ...


# ---------------------------------------------------------------------------
# Domain Service — orchestrates multi-entity logic, no persistence concerns
# ---------------------------------------------------------------------------

def calculate_resilience_score(experiments: Sequence[Experiment]) -> float:
    """
    Domain service: compute resilience score from a set of completed experiments.

    Returns a score in [0, 100].
    Pure function — no I/O, no side effects.
    """
    completed = [e for e in experiments if e.status == ExperimentStatus.COMPLETED]
    if not completed:
        return 0.0

    successful = [e for e in completed if e.success is True]
    success_rate = len(successful) / len(completed)

    # Weight by blast radius: high blast radius successes score higher
    weighted_sum = sum(
        (1.0 if e.success else 0.0) * (1.0 + e.blast_radius.value)
        for e in completed
    )
    max_weighted = sum(1.0 + e.blast_radius.value for e in completed)
    weighted_score = weighted_sum / max_weighted if max_weighted > 0 else 0.0

    # Combine raw success rate and weighted score
    final = (success_rate * 0.4 + weighted_score * 0.6) * 100
    return round(final, 2)


# ---------------------------------------------------------------------------
# Application Service — coordinates use case, depends only on domain + ports
# ---------------------------------------------------------------------------

class RunExperimentService:
    """
    Application service for the 'run experiment' use case.

    Depends on the ExperimentRepository protocol — the infrastructure
    implementation is injected at runtime (Dependency Inversion Principle).
    """

    def __init__(self, repository: ExperimentRepository) -> None:
        self._repo = repository

    def execute(self, experiment_id: ExperimentId, *, success: bool) -> list[DomainEvent]:
        """Run an experiment to completion and return domain events."""
        experiment = self._repo.get_by_id(experiment_id)
        if experiment is None:
            raise ValueError(f"Experiment {experiment_id} not found")

        experiment.start()
        experiment.complete(success=success)
        self._repo.save(experiment)

        return experiment.pull_events()
