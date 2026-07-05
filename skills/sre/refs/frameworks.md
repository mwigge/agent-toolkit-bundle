# SRE Measurement Frameworks — Code

Code for the SLI/SLO, error budget, capacity planning, and toil reduction frameworks. The SKILL.md body keeps the golden-signal table, burn-rate thresholds, checklists, and process steps; this file holds the dataclasses and computation code.

---

## SLI Specification Pattern

```python
from dataclasses import dataclass
from enum import Enum


class SLICategory(str, Enum):
    AVAILABILITY = "availability"
    LATENCY = "latency"
    ERROR_RATE = "error_rate"
    SATURATION = "saturation"
    FRESHNESS = "freshness"
    CORRECTNESS = "correctness"
    THROUGHPUT = "throughput"


@dataclass(frozen=True)
class SLISpec:
    name: str
    category: SLICategory
    description: str
    good_event_query: str     # numerator — what counts as "good"
    total_event_query: str    # denominator — total events
    unit: str                 # "ratio", "milliseconds", "percent"

    def ratio_query(self, window: str = "5m") -> str:
        return (
            f"({self.good_event_query.replace('{{window}}', window)})"
            f" / "
            f"({self.total_event_query.replace('{{window}}', window)})"
        )
```

## SLO Defaults

```python
SLO_DEFAULTS = {
    "availability":      0.999,   # 99.9% uptime
    "p99_latency_ms":    500,     # 500ms at p99
    "error_rate":        0.001,   # < 0.1% errors
    "recovery_time_s":   30,      # MTTR under 30s after chaos
    "saturation_ratio":  0.80,    # < 80% resource saturation
}


def evaluate_slo(metric_name: str, value: float) -> bool:
    threshold = SLO_DEFAULTS.get(metric_name)
    if threshold is None:
        raise ValueError(f"Unknown SLI: {metric_name}")
    if metric_name in ("p99_latency_ms", "error_rate", "recovery_time_s"):
        return value <= threshold   # lower is better
    return value >= threshold       # higher is better
```

---

## Error Budget Calculation

```python
from dataclasses import dataclass


@dataclass
class ErrorBudget:
    slo_target: float         # e.g., 0.999
    window_days: int          # e.g., 28
    total_requests: int       # total requests in window

    @property
    def budget_ratio(self) -> float:
        """Fraction of requests allowed to fail."""
        return 1.0 - self.slo_target

    @property
    def budget_requests(self) -> int:
        """Absolute number of requests that can fail."""
        return int(self.total_requests * self.budget_ratio)

    def remaining(self, failures: int) -> float:
        """Fraction of error budget remaining (0.0 to 1.0)."""
        if self.budget_requests == 0:
            return 0.0
        return max(0.0, 1.0 - (failures / self.budget_requests))

    def burn_rate(self, failures_in_window: int, window_hours: float) -> float:
        """
        How fast the budget is burning relative to sustainable rate.
        burn_rate = 1.0 means budget will be exactly exhausted at window end.
        burn_rate > 1.0 means budget will be exhausted before window end.
        """
        window_fraction = window_hours / (self.window_days * 24)
        expected_failures = self.budget_requests * window_fraction
        if expected_failures == 0:
            return float("inf") if failures_in_window > 0 else 0.0
        return failures_in_window / expected_failures
```

---

## Resource Saturation Model

```python
from dataclasses import dataclass


@dataclass
class CapacityModel:
    resource_name: str        # e.g., "cpu", "memory", "connections"
    current_usage: float      # current utilisation ratio (0.0 to 1.0)
    growth_rate_monthly: float  # fractional monthly growth (e.g., 0.05 = 5%)
    headroom_target: float    # minimum free capacity (e.g., 0.30 = 30%)
    scaling_lead_days: int    # days needed to provision new capacity

    @property
    def ceiling(self) -> float:
        return 1.0 - self.headroom_target

    def months_until_ceiling(self) -> float:
        """Months until current_usage hits ceiling at steady growth."""
        if self.growth_rate_monthly <= 0:
            return float("inf")
        if self.current_usage >= self.ceiling:
            return 0.0
        import math
        return math.log(self.ceiling / self.current_usage) / math.log(1 + self.growth_rate_monthly)

    def needs_action(self) -> bool:
        months = self.months_until_ceiling()
        lead_months = self.scaling_lead_days / 30.0
        return months <= lead_months + 1  # 1 month safety margin
```

---

## Toil Scoring

```python
@dataclass
class ToilItem:
    name: str
    frequency_per_week: float
    minutes_per_occurrence: float
    automation_effort_hours: float

    @property
    def weekly_cost_hours(self) -> float:
        return (self.frequency_per_week * self.minutes_per_occurrence) / 60.0

    @property
    def payback_weeks(self) -> float:
        if self.weekly_cost_hours == 0:
            return float("inf")
        return self.automation_effort_hours / self.weekly_cost_hours
```
