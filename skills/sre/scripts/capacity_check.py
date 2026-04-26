#!/usr/bin/env python3
"""
capacity_check.py --- Capacity planning analysis from Prometheus metrics.

Usage:
    python capacity_check.py --prometheus-url http://localhost:9090 --service chaos-platform-api
    python capacity_check.py --csv metrics.csv

Analyses resource saturation trends and estimates time-to-ceiling.
Outputs a summary with recommended actions.

Exit codes:
  0 --- all resources have sufficient headroom
  1 --- one or more resources need attention within lead time
  2 --- usage error
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from dataclasses import dataclass, asdict
from pathlib import Path


@dataclass
class ResourceMetric:
    name: str
    current_usage: float       # 0.0 to 1.0
    growth_rate_monthly: float  # fractional (0.05 = 5% per month)
    headroom_target: float     # minimum free capacity (0.30 = 30%)
    scaling_lead_days: int     # days to provision new capacity

    @property
    def ceiling(self) -> float:
        return 1.0 - self.headroom_target

    def months_until_ceiling(self) -> float:
        if self.growth_rate_monthly <= 0:
            return float("inf")
        if self.current_usage >= self.ceiling:
            return 0.0
        return math.log(self.ceiling / self.current_usage) / math.log(
            1 + self.growth_rate_monthly
        )

    def needs_action(self) -> bool:
        months = self.months_until_ceiling()
        lead_months = self.scaling_lead_days / 30.0
        return months <= lead_months + 1  # 1 month safety margin

    def status(self) -> str:
        if self.current_usage >= self.ceiling:
            return "CRITICAL"
        if self.needs_action():
            return "ACTION_NEEDED"
        return "OK"


def load_from_csv(path: Path) -> list[ResourceMetric]:
    """
    CSV format:
    name,current_usage,growth_rate_monthly,headroom_target,scaling_lead_days
    cpu,0.65,0.05,0.30,14
    memory,0.72,0.03,0.30,14
    """
    metrics: list[ResourceMetric] = []
    with path.open(encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            metrics.append(
                ResourceMetric(
                    name=row["name"],
                    current_usage=float(row["current_usage"]),
                    growth_rate_monthly=float(row["growth_rate_monthly"]),
                    headroom_target=float(row.get("headroom_target", "0.30")),
                    scaling_lead_days=int(row.get("scaling_lead_days", "14")),
                )
            )
    return metrics


def default_metrics() -> list[ResourceMetric]:
    """Example metrics for demonstration."""
    return [
        ResourceMetric("cpu", 0.55, 0.05, 0.30, 14),
        ResourceMetric("memory", 0.62, 0.04, 0.30, 14),
        ResourceMetric("disk", 0.45, 0.08, 0.20, 30),
        ResourceMetric("connections", 0.30, 0.06, 0.25, 7),
    ]


def report(metrics: list[ResourceMetric], output_json: bool = False) -> int:
    if output_json:
        results = []
        for m in metrics:
            d = asdict(m)
            d["months_until_ceiling"] = round(m.months_until_ceiling(), 1)
            d["status"] = m.status()
            results.append(d)
        json.dump(results, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        print("\n=== Capacity Planning Report ===\n")
        print(
            f"{'Resource':<15} {'Usage':>7} {'Ceiling':>8} "
            f"{'Growth/mo':>10} {'Months left':>12} {'Lead (d)':>9} {'Status':>15}"
        )
        print("-" * 80)
        for m in metrics:
            months = m.months_until_ceiling()
            months_str = f"{months:.1f}" if months < 999 else "inf"
            print(
                f"{m.name:<15} {m.current_usage:>6.1%} {m.ceiling:>7.1%} "
                f"{m.growth_rate_monthly:>9.1%} {months_str:>12} "
                f"{m.scaling_lead_days:>9} {m.status():>15}"
            )
        print()

    needs_action = [m for m in metrics if m.needs_action()]
    if needs_action:
        if not output_json:
            print(f"{len(needs_action)} resource(s) need scaling action:")
            for m in needs_action:
                months = m.months_until_ceiling()
                print(
                    f"  - {m.name}: {months:.1f} months until ceiling "
                    f"(lead time: {m.scaling_lead_days}d)"
                )
        return 1
    else:
        if not output_json:
            print("All resources have sufficient headroom.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Capacity planning check")
    parser.add_argument("--csv", type=Path, help="CSV file with resource metrics")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--demo", action="store_true", help="Run with demo metrics")
    args = parser.parse_args()

    if args.csv:
        if not args.csv.exists():
            print(f"ERROR: File not found: {args.csv}", file=sys.stderr)
            return 2
        metrics = load_from_csv(args.csv)
    elif args.demo:
        metrics = default_metrics()
    else:
        print("Usage: capacity_check.py --csv <file> | --demo", file=sys.stderr)
        return 2

    return report(metrics, output_json=args.json)


if __name__ == "__main__":
    sys.exit(main())
