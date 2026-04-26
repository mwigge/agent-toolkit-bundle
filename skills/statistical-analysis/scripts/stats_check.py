#!/usr/bin/env python3
"""
stats_check.py — Quick statistical quality check for a CSV column.

Usage:
    python stats_check.py data.csv target_column

Outputs:
  - Sample size
  - Mean, std, median
  - Normality test result (Shapiro-Wilk if n < 50, else Kolmogorov-Smirnov)
  - Outlier count (IQR method)
  - Recommendation: parametric vs non-parametric test

Exit codes:
  0 — analysis complete
  1 — error (file not found, column missing)
"""

from __future__ import annotations

import csv
import math
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Statistics (stdlib only — no numpy/scipy)
# ---------------------------------------------------------------------------

def mean(data: list[float]) -> float:
    return sum(data) / len(data)


def variance(data: list[float]) -> float:
    m = mean(data)
    return sum((x - m) ** 2 for x in data) / (len(data) - 1)


def std(data: list[float]) -> float:
    return math.sqrt(variance(data))


def median(data: list[float]) -> float:
    s = sorted(data)
    n = len(s)
    if n % 2 == 1:
        return s[n // 2]
    return (s[n // 2 - 1] + s[n // 2]) / 2.0


def percentile(data: list[float], p: float) -> float:
    """Linear interpolation percentile."""
    s = sorted(data)
    n = len(s)
    idx = (n - 1) * p / 100
    lo = int(idx)
    hi = lo + 1
    if hi >= n:
        return s[-1]
    frac = idx - lo
    return s[lo] + frac * (s[hi] - s[lo])


def iqr_outliers(data: list[float], multiplier: float = 1.5) -> tuple[list[float], float, float]:
    q1 = percentile(data, 25)
    q3 = percentile(data, 75)
    iqr = q3 - q1
    lower = q1 - multiplier * iqr
    upper = q3 + multiplier * iqr
    outliers = [x for x in data if x < lower or x > upper]
    return outliers, lower, upper


def shapiro_wilk_w(data: list[float]) -> float:
    """
    Approximate Shapiro-Wilk W statistic.
    This is a simplified implementation — use scipy.stats.shapiro for production.
    Returns W in (0, 1]; values close to 1 indicate normality.
    """
    n = len(data)
    if n < 3:
        return 1.0

    s = sorted(data)
    m = mean(s)
    ss = sum((x - m) ** 2 for x in s)

    # Shapiro-Wilk a coefficients (first 10 terms approximation)
    # For a proper implementation use the published tables or scipy
    # This approximation is for indicative use only when scipy unavailable
    half = n // 2
    a_approx = [
        (s[n - 1 - i] - s[i]) / (2.0 * math.sqrt(ss / (n - 1)) + 1e-12)
        for i in range(half)
    ]
    w_num = sum(a_approx) ** 2
    w = min(1.0, w_num / ss * (n - 1)) if ss > 0 else 1.0
    return round(w, 4)


def normality_test(data: list[float]) -> tuple[str, float, float, str]:
    """
    Run normality test. Uses scipy if available, falls back to approximation.
    Returns (test_name, statistic, p_value, interpretation).
    """
    n = len(data)
    try:
        from scipy import stats as sp_stats
        if n < 50:
            stat, p = sp_stats.shapiro(data)
            test_name = "Shapiro-Wilk"
        else:
            # Kolmogorov-Smirnov against normal with estimated parameters
            m = mean(data)
            s = std(data)
            standardised = [(x - m) / s for x in data]
            stat, p = sp_stats.kstest(standardised, "norm")
            test_name = "Kolmogorov-Smirnov"
    except ImportError:
        # Fallback: simplified W statistic, no p-value
        w = shapiro_wilk_w(data)
        stat = w
        # Rough heuristic: W < 0.95 suggests non-normality (not a real p-value)
        p = 1.0 if w >= 0.95 else 0.04
        test_name = "Shapiro-Wilk (approx)"

    if p < 0.05:
        interpretation = f"Non-normal (p={p:.4f} < 0.05)"
    else:
        interpretation = f"Normal distribution not rejected (p={p:.4f} ≥ 0.05)"

    return test_name, round(stat, 4), round(p, 4), interpretation


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def load_column(path: Path, column: str) -> list[float]:
    """Read a numeric column from a CSV file."""
    values: list[float] = []
    skipped = 0

    with path.open(encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames is None:
            raise ValueError("Empty CSV file")

        if column not in reader.fieldnames:
            raise ValueError(
                f"Column '{column}' not found. Available: {list(reader.fieldnames)}"
            )

        for row in reader:
            raw = row.get(column, "")
            if raw is None or str(raw).strip() in ("", "null", "NULL", "NA", "NaN", "nan"):
                skipped += 1
                continue
            try:
                values.append(float(raw))
            except ValueError:
                skipped += 1

    if skipped:
        print(f"  (Skipped {skipped} non-numeric or missing values)", file=sys.stderr)

    return values


def main() -> int:
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <data.csv> <column_name>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    column = sys.argv[2]

    if not path.exists():
        print(f"ERROR: File not found: {path}", file=sys.stderr)
        return 1

    try:
        data = load_column(path, column)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    n = len(data)
    if n < 3:
        print(f"ERROR: Insufficient data — need at least 3 values, got {n}", file=sys.stderr)
        return 1

    m = mean(data)
    s = std(data)
    med = median(data)
    p25 = percentile(data, 25)
    p75 = percentile(data, 75)
    mn = min(data)
    mx = max(data)

    outliers, lower, upper = iqr_outliers(data)
    test_name, stat, p_val, interpretation = normality_test(data)

    print(f"\n=== Statistical Summary: {path.name} [{column}] ===\n")
    print(f"  Sample size:   {n:,}")
    print(f"  Mean:          {m:.4f}")
    print(f"  Std dev:       {s:.4f}")
    print(f"  Median:        {med:.4f}")
    print(f"  25th pct:      {p25:.4f}")
    print(f"  75th pct:      {p75:.4f}")
    print(f"  Min:           {mn:.4f}")
    print(f"  Max:           {mx:.4f}")

    print(f"\n  Normality Test ({test_name}):")
    print(f"    Statistic:   {stat}")
    print(f"    p-value:     {p_val}")
    print(f"    Result:      {interpretation}")

    print(f"\n  Outliers (IQR × 1.5):")
    print(f"    Bounds:      [{lower:.4f}, {upper:.4f}]")
    print(f"    Count:       {len(outliers)} ({len(outliers)/n*100:.1f}%)")
    if outliers:
        sample = sorted(outliers)[:5]
        print(f"    Sample:      {sample}" + (" ..." if len(outliers) > 5 else ""))

    is_normal = p_val >= 0.05
    print(f"\n  Recommendation:")
    if is_normal:
        print("    Distribution appears normal.")
        print("    → Use parametric tests: t-test, ANOVA, Pearson correlation")
    else:
        print("    Distribution is non-normal.")
        print("    → Use non-parametric tests: Mann-Whitney U, Wilcoxon, Spearman")
        print("    → Or apply log/sqrt transformation and re-test")

    if len(outliers) / n > 0.1:
        print("    → High outlier rate (>10%): investigate data quality before testing")

    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
