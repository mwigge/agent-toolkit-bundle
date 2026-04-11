"""
statistical_analysis.py — Full two-sample statistical comparison pipeline.

Pipeline:
  1. Load and describe data
  2. Normality test (Shapiro-Wilk or KS)
  3. Two-sample comparison (t-test or Mann-Whitney U based on normality)
  4. Effect size (Cohen's d)
  5. Bootstrap confidence interval for the mean difference
  6. Interpretation output

Dependencies: scipy, numpy, pandas
Install: pip install scipy numpy pandas
"""

from __future__ import annotations

import json
import logging
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# 1. Load Data
# ---------------------------------------------------------------------------

def load_groups(
    path: Path,
    value_col: str,
    group_col: str,
) -> tuple[np.ndarray, np.ndarray, list[str]]:
    """
    Load two-group comparison data from CSV.
    Returns (group_a, group_b, [label_a, label_b]).
    Expects exactly 2 unique values in group_col.
    """
    logger.info("loading_data", extra={"path": str(path), "value_col": value_col})

    df = pd.read_csv(path)

    for col in (value_col, group_col):
        if col not in df.columns:
            raise ValueError(f"Column '{col}' not found. Available: {list(df.columns)}")

    df = df.dropna(subset=[value_col, group_col])
    df[value_col] = pd.to_numeric(df[value_col], errors="coerce")
    df = df.dropna(subset=[value_col])

    group_labels = sorted(df[group_col].unique())
    if len(group_labels) != 2:
        raise ValueError(
            f"Expected exactly 2 groups in '{group_col}', found: {group_labels}"
        )

    a = df[df[group_col] == group_labels[0]][value_col].to_numpy()
    b = df[df[group_col] == group_labels[1]][value_col].to_numpy()

    logger.info("groups_loaded",
                extra={"group_a": str(group_labels[0]), "n_a": len(a),
                        "group_b": str(group_labels[1]), "n_b": len(b)})
    return a, b, [str(g) for g in group_labels]

# ---------------------------------------------------------------------------
# 2. Descriptive Statistics
# ---------------------------------------------------------------------------

def describe(data: np.ndarray, label: str) -> dict[str, float]:
    return {
        "label": label,
        "n": int(len(data)),
        "mean": round(float(np.mean(data)), 4),
        "std":  round(float(np.std(data, ddof=1)), 4),
        "median": round(float(np.median(data)), 4),
        "p25":  round(float(np.percentile(data, 25)), 4),
        "p75":  round(float(np.percentile(data, 75)), 4),
        "min":  round(float(np.min(data)), 4),
        "max":  round(float(np.max(data)), 4),
    }

# ---------------------------------------------------------------------------
# 3. Normality Test
# ---------------------------------------------------------------------------

def test_normality(data: np.ndarray, label: str) -> dict[str, object]:
    n = len(data)
    if n < 3:
        return {"label": label, "test": "none", "p_value": None, "is_normal": None}

    if n < 50:
        stat, p = stats.shapiro(data)
        test_name = "shapiro-wilk"
    else:
        # Standardise then KS test against normal
        z = (data - np.mean(data)) / np.std(data, ddof=1)
        stat, p = stats.kstest(z, "norm")
        test_name = "kolmogorov-smirnov"

    is_normal = bool(p >= 0.05)
    return {
        "label": label,
        "test": test_name,
        "statistic": round(float(stat), 4),
        "p_value": round(float(p), 4),
        "is_normal": is_normal,
        "interpretation": (
            "Normal distribution not rejected" if is_normal
            else "Non-normal distribution"
        ),
    }

# ---------------------------------------------------------------------------
# 4. Two-Sample Test
# ---------------------------------------------------------------------------

def two_sample_test(
    a: np.ndarray,
    b: np.ndarray,
    both_normal: bool,
    alpha: float = 0.05,
) -> dict[str, object]:
    if both_normal:
        stat, p = stats.ttest_ind(a, b, equal_var=False)  # Welch's t-test
        test_name = "welch-t-test"
    else:
        stat, p = stats.mannwhitneyu(a, b, alternative="two-sided")
        test_name = "mann-whitney-u"

    significant = bool(p < alpha)
    return {
        "test": test_name,
        "statistic": round(float(stat), 4),
        "p_value": round(float(p), 6),
        "alpha": alpha,
        "significant": significant,
        "interpretation": (
            f"Statistically significant difference (p={p:.4f} < {alpha})"
            if significant
            else f"No significant difference detected (p={p:.4f} ≥ {alpha})"
        ),
    }

# ---------------------------------------------------------------------------
# 5. Effect Size — Cohen's d
# ---------------------------------------------------------------------------

def cohens_d(a: np.ndarray, b: np.ndarray) -> dict[str, object]:
    """Cohen's d for two independent samples."""
    mean_diff = np.mean(a) - np.mean(b)
    pooled_std = np.sqrt(
        ((len(a) - 1) * np.std(a, ddof=1) ** 2 + (len(b) - 1) * np.std(b, ddof=1) ** 2)
        / (len(a) + len(b) - 2)
    )
    d = float(mean_diff / pooled_std) if pooled_std > 0 else 0.0

    if abs(d) < 0.2:
        magnitude = "negligible"
    elif abs(d) < 0.5:
        magnitude = "small"
    elif abs(d) < 0.8:
        magnitude = "medium"
    else:
        magnitude = "large"

    return {
        "cohens_d": round(d, 4),
        "magnitude": magnitude,
        "interpretation": f"Effect size is {magnitude} (d={d:.3f}; thresholds: 0.2/0.5/0.8)",
    }

# ---------------------------------------------------------------------------
# 6. Bootstrap Confidence Interval for Mean Difference
# ---------------------------------------------------------------------------

def bootstrap_ci(
    a: np.ndarray,
    b: np.ndarray,
    n_bootstrap: int = 2000,
    confidence: float = 0.95,
    rng: np.random.Generator | None = None,
) -> dict[str, object]:
    """Bootstrap CI for (mean_a - mean_b)."""
    if rng is None:
        rng = np.random.default_rng()

    diffs = np.array([
        np.mean(rng.choice(a, size=len(a), replace=True))
        - np.mean(rng.choice(b, size=len(b), replace=True))
        for _ in range(n_bootstrap)
    ])

    alpha = 1 - confidence
    lo = float(np.percentile(diffs, alpha / 2 * 100))
    hi = float(np.percentile(diffs, (1 - alpha / 2) * 100))
    observed = float(np.mean(a) - np.mean(b))

    return {
        "observed_mean_diff": round(observed, 4),
        "ci_lower": round(lo, 4),
        "ci_upper": round(hi, 4),
        "confidence": confidence,
        "n_bootstrap": n_bootstrap,
        "interpretation": (
            f"{confidence*100:.0f}% CI for mean difference: [{lo:.4f}, {hi:.4f}]. "
            + ("Excludes zero — consistent with significant difference."
               if lo > 0 or hi < 0
               else "Includes zero — difference may not be meaningful.")
        ),
    }

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Two-sample statistical analysis")
    parser.add_argument("csv_file", type=Path)
    parser.add_argument("value_col", help="Numeric column to compare")
    parser.add_argument("group_col", help="Column containing group labels (exactly 2 groups)")
    parser.add_argument("--alpha", type=float, default=0.05)
    parser.add_argument("--bootstrap", type=int, default=2000)
    parser.add_argument("--output", type=Path, default=Path("stats_report.json"))
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    if not args.csv_file.exists():
        logger.error("file_not_found", extra={"path": str(args.csv_file)})
        return 1

    a, b, labels = load_groups(args.csv_file, args.value_col, args.group_col)

    desc_a = describe(a, labels[0])
    desc_b = describe(b, labels[1])
    norm_a = test_normality(a, labels[0])
    norm_b = test_normality(b, labels[1])

    both_normal = bool(norm_a.get("is_normal")) and bool(norm_b.get("is_normal"))
    comparison = two_sample_test(a, b, both_normal=both_normal, alpha=args.alpha)
    effect = cohens_d(a, b)
    ci = bootstrap_ci(a, b, n_bootstrap=args.bootstrap)

    report: dict[str, object] = {
        "column": args.value_col,
        "groups": labels,
        "descriptive": [desc_a, desc_b],
        "normality": [norm_a, norm_b],
        "test_selection": (
            "parametric (Welch's t-test)" if both_normal else "non-parametric (Mann-Whitney U)"
        ),
        "comparison": comparison,
        "effect_size": effect,
        "bootstrap_ci": ci,
    }

    # Print summary
    print(f"\n=== Statistical Analysis: {args.value_col} by {args.group_col} ===\n")
    for d in [desc_a, desc_b]:
        print(f"  {d['label']}: n={d['n']}, mean={d['mean']}, std={d['std']}, median={d['median']}")
    print(f"\n  Normality: {labels[0]}={norm_a['interpretation']}, {labels[1]}={norm_b['interpretation']}")
    print(f"\n  Test: {comparison['test']} — {comparison['interpretation']}")
    print(f"  Effect size: {effect['interpretation']}")
    print(f"  Bootstrap CI: {ci['interpretation']}")

    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    logger.info("report_written", extra={"path": str(args.output)})
    return 0

if __name__ == "__main__":
    sys.exit(main())
