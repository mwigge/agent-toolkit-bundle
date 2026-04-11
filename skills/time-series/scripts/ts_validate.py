#!/usr/bin/env python3
"""
ts_validate.py — Validate a time series CSV file for quality issues.

Usage:
    python ts_validate.py data.csv [--timestamp-col timestamp] [--interval-seconds 60]

Checks:
  - Timestamps are monotonically increasing
  - Detects gaps larger than the expected interval
  - Detects duplicate timestamps
  - Checks for null/missing values in numeric columns
  - Reports a quality summary

Exit codes:
  0 — data is clean
  1 — quality issues found
"""

from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

@dataclass
class QualityReport:
    path: str
    total_rows: int = 0
    duplicate_timestamps: list[str] = field(default_factory=list)
    non_monotonic_rows: list[tuple[int, str, str]] = field(default_factory=list)  # (row, prev_ts, curr_ts)
    gaps: list[tuple[str, str, float]] = field(default_factory=list)  # (start, end, gap_seconds)
    missing_values: dict[str, int] = field(default_factory=dict)  # column -> count
    min_timestamp: str | None = None
    max_timestamp: str | None = None
    expected_interval_seconds: float | None = None

    @property
    def is_clean(self) -> bool:
        return (
            not self.duplicate_timestamps
            and not self.non_monotonic_rows
            and not self.gaps
            and all(v == 0 for v in self.missing_values.values())
        )

    def print_report(self) -> None:
        print(f"\n=== Time Series Quality Report: {self.path} ===")
        print(f"Total rows:   {self.total_rows:,}")
        if self.min_timestamp and self.max_timestamp:
            print(f"Time range:   {self.min_timestamp}  →  {self.max_timestamp}")
        if self.expected_interval_seconds:
            print(f"Expected gap: {self.expected_interval_seconds}s")
        print()

        if not self.duplicate_timestamps and not self.non_monotonic_rows and not self.gaps:
            print("  ✓ Timestamp integrity: OK")
        else:
            if self.duplicate_timestamps:
                print(f"  ✗ Duplicate timestamps: {len(self.duplicate_timestamps)}")
                for ts in self.duplicate_timestamps[:5]:
                    print(f"      {ts}")
                if len(self.duplicate_timestamps) > 5:
                    print(f"      ... and {len(self.duplicate_timestamps) - 5} more")

            if self.non_monotonic_rows:
                print(f"  ✗ Non-monotonic timestamps: {len(self.non_monotonic_rows)} row(s)")
                for row_num, prev_ts, curr_ts in self.non_monotonic_rows[:5]:
                    print(f"      Row {row_num}: {prev_ts} → {curr_ts} (went backwards)")

            if self.gaps:
                print(f"  ✗ Gaps > expected interval: {len(self.gaps)}")
                for gap_start, gap_end, gap_sec in self.gaps[:5]:
                    print(f"      {gap_start} → {gap_end} ({gap_sec:.0f}s gap)")
                if len(self.gaps) > 5:
                    print(f"      ... and {len(self.gaps) - 5} more")

        if self.missing_values:
            any_missing = {k: v for k, v in self.missing_values.items() if v > 0}
            if any_missing:
                print(f"\n  ✗ Missing values detected:")
                for col, count in sorted(any_missing.items(), key=lambda x: -x[1]):
                    pct = count / self.total_rows * 100 if self.total_rows else 0
                    print(f"      {col}: {count:,} missing ({pct:.1f}%)")
            else:
                print("  ✓ No missing values")

        if self.is_clean:
            print("\n  RESULT: CLEAN — no quality issues found")
        else:
            print("\n  RESULT: ISSUES FOUND — see above")
        print()

TIMESTAMP_FORMATS = [
    "%Y-%m-%dT%H:%M:%S.%fZ",
    "%Y-%m-%dT%H:%M:%SZ",
    "%Y-%m-%dT%H:%M:%S",
    "%Y-%m-%d %H:%M:%S.%f",
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%d",
    "%s",  # Unix epoch (handled separately)
]

def parse_timestamp(value: str) -> datetime | None:
    value = value.strip()
    if not value:
        return None

    # Unix epoch
    try:
        epoch = float(value)
        return datetime.fromtimestamp(epoch)
    except ValueError:
        pass

    for fmt in TIMESTAMP_FORMATS:
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            continue
    return None

def validate_csv(
    path: Path,
    timestamp_col: str = "timestamp",
    interval_seconds: float | None = None,
) -> QualityReport:
    report = QualityReport(path=str(path), expected_interval_seconds=interval_seconds)

    try:
        with path.open(encoding="utf-8", newline="") as fh:
            reader = csv.DictReader(fh)

            if reader.fieldnames is None:
                print(f"ERROR: Empty CSV file: {path}", file=sys.stderr)
                return report

            fieldnames = list(reader.fieldnames)

            if timestamp_col not in fieldnames:
                print(
                    f"ERROR: Timestamp column '{timestamp_col}' not found. "
                    f"Available columns: {fieldnames}",
                    file=sys.stderr,
                )
                return report

            # Initialise missing value counters for numeric-looking columns
            numeric_cols = [c for c in fieldnames if c != timestamp_col]
            report.missing_values = {c: 0 for c in numeric_cols}

            prev_ts: datetime | None = None
            seen_timestamps: dict[str, int] = {}
            rows: list[dict[str, Any]] = list(reader)

    except OSError as exc:
        print(f"ERROR: Cannot read {path}: {exc}", file=sys.stderr)
        return report

    report.total_rows = len(rows)

    # Auto-detect interval if not specified
    if interval_seconds is None and len(rows) >= 2:
        ts0 = parse_timestamp(rows[0].get(timestamp_col, ""))
        ts1 = parse_timestamp(rows[1].get(timestamp_col, ""))
        if ts0 and ts1:
            inferred = abs((ts1 - ts0).total_seconds())
            if inferred > 0:
                interval_seconds = inferred
                report.expected_interval_seconds = interval_seconds

    for row_idx, row in enumerate(rows, start=2):  # row 1 = header
        ts_raw = row.get(timestamp_col, "")
        ts = parse_timestamp(ts_raw)

        # Track timestamps for duplicate/monotonic checks
        ts_str = ts_raw.strip()
        if ts_str in seen_timestamps:
            report.duplicate_timestamps.append(ts_str)
        else:
            seen_timestamps[ts_str] = row_idx

        if ts is None:
            continue

        if report.min_timestamp is None:
            report.min_timestamp = ts_str
        report.max_timestamp = ts_str

        # Monotonic check
        if prev_ts is not None:
            if ts < prev_ts:
                report.non_monotonic_rows.append((row_idx, str(prev_ts), str(ts)))
            elif interval_seconds is not None:
                gap = (ts - prev_ts).total_seconds()
                if gap > interval_seconds * 1.5:  # 50% tolerance
                    report.gaps.append((str(prev_ts), str(ts), gap))

        prev_ts = ts

        # Missing value check for non-timestamp columns
        for col in numeric_cols:
            val = row.get(col, "")
            if val is None or str(val).strip() in ("", "null", "NULL", "NA", "NaN", "nan"):
                report.missing_values[col] = report.missing_values.get(col, 0) + 1

    return report

def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a time series CSV file")
    parser.add_argument("csv_file", type=Path, help="Path to CSV file")
    parser.add_argument("--timestamp-col", default="timestamp",
                        help="Name of timestamp column (default: timestamp)")
    parser.add_argument("--interval-seconds", type=float, default=None,
                        help="Expected interval between measurements in seconds")
    args = parser.parse_args()

    if not args.csv_file.exists():
        print(f"ERROR: File not found: {args.csv_file}", file=sys.stderr)
        return 2

    report = validate_csv(
        args.csv_file,
        timestamp_col=args.timestamp_col,
        interval_seconds=args.interval_seconds,
    )
    report.print_report()
    return 0 if report.is_clean else 1

if __name__ == "__main__":
    sys.exit(main())
