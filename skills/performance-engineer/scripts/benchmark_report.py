#!/usr/bin/env python3
"""
benchmark_report.py --- Compare benchmark results and detect regressions.

Usage:
    python benchmark_report.py --baseline baseline.json --current current.json
    python benchmark_report.py --demo

Input JSON format (per endpoint):
{
  "endpoint": "/api/experiments",
  "p50_ms": 45.2,
  "p95_ms": 120.5,
  "p99_ms": 250.3,
  "rps": 1500,
  "error_rate": 0.001
}

Exit codes:
  0 --- no regressions detected
  1 --- regressions detected
  2 --- usage error
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass
class EndpointMetrics:
    endpoint: str
    p50_ms: float
    p95_ms: float
    p99_ms: float
    rps: float
    error_rate: float


@dataclass
class Comparison:
    endpoint: str
    metric: str
    baseline: float
    current: float
    change_pct: float
    is_regression: bool

    def __str__(self) -> str:
        direction = "REGRESSION" if self.is_regression else "ok"
        sign = "+" if self.change_pct > 0 else ""
        return (
            f"  [{direction:>10}] {self.endpoint:<30} "
            f"{self.metric:<10} {self.baseline:>8.1f} -> {self.current:>8.1f} "
            f"({sign}{self.change_pct:.1f}%)"
        )


REGRESSION_THRESHOLDS = {
    "p50_ms": 0.15,      # 15% increase is a regression
    "p95_ms": 0.10,      # 10% increase
    "p99_ms": 0.10,      # 10% increase
    "rps": -0.10,         # 10% decrease (negative = regression)
    "error_rate": 0.005,  # absolute threshold: 0.5% increase
}


def compare(
    baseline: list[EndpointMetrics],
    current: list[EndpointMetrics],
) -> list[Comparison]:
    baseline_map = {m.endpoint: m for m in baseline}
    comparisons: list[Comparison] = []

    for cur in current:
        base = baseline_map.get(cur.endpoint)
        if base is None:
            continue

        for metric in ("p50_ms", "p95_ms", "p99_ms"):
            base_val = getattr(base, metric)
            cur_val = getattr(cur, metric)
            if base_val == 0:
                continue
            change = (cur_val - base_val) / base_val
            threshold = REGRESSION_THRESHOLDS[metric]
            comparisons.append(Comparison(
                endpoint=cur.endpoint,
                metric=metric,
                baseline=base_val,
                current=cur_val,
                change_pct=change * 100,
                is_regression=change > threshold,
            ))

        # RPS: decrease is bad
        if base.rps > 0:
            rps_change = (cur.rps - base.rps) / base.rps
            comparisons.append(Comparison(
                endpoint=cur.endpoint,
                metric="rps",
                baseline=base.rps,
                current=cur.rps,
                change_pct=rps_change * 100,
                is_regression=rps_change < REGRESSION_THRESHOLDS["rps"],
            ))

        # Error rate: absolute change
        err_change = cur.error_rate - base.error_rate
        comparisons.append(Comparison(
            endpoint=cur.endpoint,
            metric="error_rate",
            baseline=base.error_rate,
            current=cur.error_rate,
            change_pct=err_change * 100,
            is_regression=err_change > REGRESSION_THRESHOLDS["error_rate"],
        ))

    return comparisons


def demo() -> int:
    baseline = [
        EndpointMetrics("/api/experiments", 45.2, 120.5, 250.3, 1500, 0.001),
        EndpointMetrics("/api/experiments/[id]", 22.1, 55.0, 110.0, 2000, 0.0005),
        EndpointMetrics("/api/health", 5.0, 8.0, 12.0, 5000, 0.0),
    ]
    current = [
        EndpointMetrics("/api/experiments", 48.0, 135.0, 290.0, 1450, 0.002),
        EndpointMetrics("/api/experiments/[id]", 23.5, 58.0, 115.0, 1950, 0.001),
        EndpointMetrics("/api/health", 5.1, 8.2, 12.5, 4900, 0.0),
    ]

    results = compare(baseline, current)

    print("\n=== Performance Benchmark Comparison ===\n")
    regressions = [r for r in results if r.is_regression]
    for r in results:
        print(r)

    print(f"\n{len(regressions)} regression(s) detected out of {len(results)} comparisons.")
    return 1 if regressions else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark regression detector")
    parser.add_argument("--baseline", type=Path, help="Baseline metrics JSON")
    parser.add_argument("--current", type=Path, help="Current metrics JSON")
    parser.add_argument("--demo", action="store_true", help="Run with demo data")
    args = parser.parse_args()

    if args.demo:
        return demo()

    if not args.baseline or not args.current:
        print("Usage: benchmark_report.py --baseline <file> --current <file>", file=sys.stderr)
        return 2

    baseline = [EndpointMetrics(**m) for m in json.loads(args.baseline.read_text())]
    current = [EndpointMetrics(**m) for m in json.loads(args.current.read_text())]

    results = compare(baseline, current)

    print("\n=== Performance Benchmark Comparison ===\n")
    for r in results:
        print(r)

    regressions = [r for r in results if r.is_regression]
    print(f"\n{len(regressions)} regression(s) detected.")
    return 1 if regressions else 0


if __name__ == "__main__":
    sys.exit(main())
