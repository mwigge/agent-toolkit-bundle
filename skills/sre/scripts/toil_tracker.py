#!/usr/bin/env python3
"""
toil_tracker.py --- Track and prioritise toil reduction opportunities.

Usage:
    python toil_tracker.py --csv toil_items.csv
    python toil_tracker.py --demo

CSV format:
    name,frequency_per_week,minutes_per_occurrence,automation_effort_hours
    manual-deploy,5,30,16
    cert-rotation,0.5,60,8

Outputs a prioritised list sorted by payback period (shortest first).

Exit codes:
  0 --- report generated
  2 --- usage error
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from dataclasses import dataclass, asdict
from pathlib import Path


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
    def monthly_cost_hours(self) -> float:
        return self.weekly_cost_hours * 4.33

    @property
    def payback_weeks(self) -> float:
        if self.weekly_cost_hours == 0:
            return float("inf")
        return self.automation_effort_hours / self.weekly_cost_hours

    @property
    def annual_savings_hours(self) -> float:
        return self.weekly_cost_hours * 52


def load_from_csv(path: Path) -> list[ToilItem]:
    items: list[ToilItem] = []
    with path.open(encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            items.append(
                ToilItem(
                    name=row["name"],
                    frequency_per_week=float(row["frequency_per_week"]),
                    minutes_per_occurrence=float(row["minutes_per_occurrence"]),
                    automation_effort_hours=float(row["automation_effort_hours"]),
                )
            )
    return items


def demo_items() -> list[ToilItem]:
    return [
        ToilItem("manual-deploy", 5, 30, 16),
        ToilItem("cert-rotation", 0.25, 60, 8),
        ToilItem("user-provisioning", 3, 15, 12),
        ToilItem("log-rotation", 1, 20, 4),
        ToilItem("experiment-cleanup", 7, 10, 6),
        ToilItem("alert-triage", 10, 5, 20),
    ]


def report(items: list[ToilItem], output_json: bool = False) -> None:
    sorted_items = sorted(items, key=lambda t: t.payback_weeks)

    if output_json:
        results = []
        for item in sorted_items:
            d = asdict(item)
            d["weekly_cost_hours"] = round(item.weekly_cost_hours, 1)
            d["payback_weeks"] = round(item.payback_weeks, 1)
            d["annual_savings_hours"] = round(item.annual_savings_hours, 1)
            results.append(d)
        json.dump(results, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return

    total_weekly = sum(t.weekly_cost_hours for t in items)
    total_annual = sum(t.annual_savings_hours for t in items)

    print("\n=== Toil Reduction Priority Report ===\n")
    print(f"Total weekly toil: {total_weekly:.1f} hours")
    print(f"Total annual toil: {total_annual:.0f} hours")
    print()
    print(
        f"{'Item':<25} {'Freq/wk':>8} {'Min/occ':>8} "
        f"{'Wk cost (h)':>12} {'Effort (h)':>11} {'Payback (wk)':>13} {'Annual (h)':>11}"
    )
    print("-" * 92)
    for item in sorted_items:
        payback = (
            f"{item.payback_weeks:.1f}"
            if item.payback_weeks < 999
            else "inf"
        )
        print(
            f"{item.name:<25} {item.frequency_per_week:>8.1f} "
            f"{item.minutes_per_occurrence:>8.0f} "
            f"{item.weekly_cost_hours:>12.1f} "
            f"{item.automation_effort_hours:>11.0f} "
            f"{payback:>13} "
            f"{item.annual_savings_hours:>11.0f}"
        )
    print()
    print("Recommendation: automate items with payback < 4 weeks first.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Toil reduction tracker")
    parser.add_argument("--csv", type=Path, help="CSV file with toil items")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--demo", action="store_true", help="Run with demo data")
    args = parser.parse_args()

    if args.csv:
        if not args.csv.exists():
            print(f"ERROR: File not found: {args.csv}", file=sys.stderr)
            return 2
        items = load_from_csv(args.csv)
    elif args.demo:
        items = demo_items()
    else:
        print("Usage: toil_tracker.py --csv <file> | --demo", file=sys.stderr)
        return 2

    report(items, output_json=args.json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
