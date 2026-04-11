---
name: statistical-analysis
description: >
  Hypothesis testing, p-values, confidence intervals, regression, correlation,
  distribution fitting, and statistical comparison of chaos experiment results.
  Activate when performing significance testing or statistical inference.
version: 1.0.0
argument-hint: "[statistical test or comparison goal]"
---

# Statistical Analysis Skill

## When to activate
- Comparing baseline vs post-chaos metrics (significance testing)
- Determining if a resilience score change is statistically meaningful
- Regression analysis on probe data
- Distribution fitting (what distribution does this metric follow?)
- Correlation analysis between system components
- Sample size / power analysis for experiment design

---

## Core Libraries

```python
import numpy as np
import pandas as pd
from scipy import stats
import statsmodels.api as sm
import statsmodels.formula.api as smf
from dataclasses import dataclass
```

Pinned deps:
```toml
[project]
dependencies = [
    "scipy>=1.12",
    "statsmodels>=0.14",
    "numpy>=1.26",
    "pandas>=2.2",
]
```

---

## Hypothesis Testing Workflow

Always follow this order:
1. State H₀ and H₁
2. Check assumptions (normality, variance, sample size)
3. Choose test
4. Run test
5. Report: test statistic, p-value, effect size, CI

### Normality check (prerequisite)

```python
def check_normality(sample: np.ndarray, alpha: float = 0.05) -> bool:
    """Shapiro-Wilk for n≤5000, D'Agostino-Pearson otherwise."""
    if len(sample) <= 5000:
        _, p = stats.shapiro(sample)
    else:
        _, p = stats.normaltest(sample)
    return p > alpha  # True = cannot reject normality
```

### Test selection guide

| Scenario | Normal? | Equal var? | Test |
|---|---|---|---|
| 2 independent groups | Yes | Yes | t-test (Student) |
| 2 independent groups | Yes | No | t-test (Welch) |
| 2 independent groups | No | — | Mann-Whitney U |
| Paired samples (before/after) | Yes | — | Paired t-test |
| Paired samples | No | — | Wilcoxon signed-rank |
| 3+ groups | Yes | Yes | One-way ANOVA |
| 3+ groups | No | — | Kruskal-Wallis |
| Categorical association | — | — | Chi-square |

---

## Two-Sample Comparison

```python
@dataclass
class TestResult:
    test_name: str
    statistic: float
    p_value: float
    effect_size: float
    significant: bool
    interpretation: str

def compare_groups(
    a: np.ndarray,
    b: np.ndarray,
    alpha: float = 0.05,
) -> TestResult:
    """Auto-select appropriate two-sample test."""
    a = a[~np.isnan(a)]
    b = b[~np.isnan(b)]

    a_normal = check_normality(a, alpha)
    b_normal = check_normality(b, alpha)

    if a_normal and b_normal:
        _, p_levene = stats.levene(a, b)
        equal_var = p_levene > alpha
        stat, p = stats.ttest_ind(a, b, equal_var=equal_var)
        test_name = "Student t-test" if equal_var else "Welch t-test"
        # Cohen's d
        pooled_std = np.sqrt((np.std(a, ddof=1)**2 + np.std(b, ddof=1)**2) / 2)
        effect = (np.mean(a) - np.mean(b)) / pooled_std if pooled_std > 0 else 0.0
    else:
        stat, p = stats.mannwhitneyu(a, b, alternative="two-sided")
        test_name = "Mann-Whitney U"
        # Rank-biserial correlation as effect size
        n1, n2 = len(a), len(b)
        effect = 1 - (2 * stat) / (n1 * n2)

    significant = p < alpha
    direction = "higher" if np.median(a) > np.median(b) else "lower"
    interp = (
        f"{'Significant' if significant else 'Not significant'} difference "
        f"(p={p:.4f}, effect={effect:.3f}). Group A median is {direction} than B."
    )
    return TestResult(test_name, float(stat), float(p), float(effect), significant, interp)
```

---

## Confidence Intervals

```python
def confidence_interval(
    sample: np.ndarray,
    confidence: float = 0.95,
) -> tuple[float, float]:
    """Bootstrap CI — works for any statistic, no normality assumption."""
    n = len(sample)
    if n == 0:
        return (float("nan"), float("nan"))
    se = stats.sem(sample)
    h = se * stats.t.ppf((1 + confidence) / 2, df=n - 1)
    mean = float(np.mean(sample))
    return (mean - h, mean + h)

def bootstrap_ci(
    sample: np.ndarray,
    statistic=np.median,
    n_boot: int = 2000,
    confidence: float = 0.95,
    rng: np.random.Generator | None = None,
) -> tuple[float, float]:
    rng = rng or np.random.default_rng(42)
    boot_stats = np.array([
        statistic(rng.choice(sample, size=len(sample), replace=True))
        for _ in range(n_boot)
    ])
    lo = (1 - confidence) / 2
    return (float(np.quantile(boot_stats, lo)), float(np.quantile(boot_stats, 1 - lo)))
```

---

## Correlation Analysis

```python
def correlation_test(
    x: np.ndarray,
    y: np.ndarray,
    alpha: float = 0.05,
) -> dict[str, float | str]:
    """Pearson + Spearman; pick Spearman if non-normal."""
    x_normal = check_normality(x, alpha)
    y_normal = check_normality(y, alpha)
    if x_normal and y_normal:
        r, p = stats.pearsonr(x, y)
        method = "Pearson"
    else:
        r, p = stats.spearmanr(x, y)
        method = "Spearman"
    strength = "strong" if abs(r) > 0.7 else "moderate" if abs(r) > 0.3 else "weak"
    direction = "positive" if r > 0 else "negative"
    return {
        "method": method, "r": float(r), "p": float(p),
        "significant": p < alpha,
        "interpretation": f"{strength} {direction} {method} correlation (r={r:.3f}, p={p:.4f})",
    }
```

---

## Linear Regression

```python
@dataclass
class RegressionResult:
    coefficients: dict[str, float]
    r_squared: float
    adj_r_squared: float
    f_p_value: float
    aic: float
    significant_predictors: list[str]

def linear_regression(
    df: pd.DataFrame,
    formula: str,  # statsmodels formula syntax: "y ~ x1 + x2"
    alpha: float = 0.05,
) -> RegressionResult:
    model = smf.ols(formula=formula, data=df).fit()
    sig = model.pvalues[model.pvalues < alpha].index.tolist()
    return RegressionResult(
        coefficients=model.params.to_dict(),
        r_squared=float(model.rsquared),
        adj_r_squared=float(model.rsquared_adj),
        f_p_value=float(model.f_pvalue),
        aic=float(model.aic),
        significant_predictors=[p for p in sig if p != "Intercept"],
    )
```

---

## Distribution Fitting

```python
CANDIDATE_DISTRIBUTIONS = ["norm", "lognorm", "expon", "gamma", "weibull_min"]

def fit_distribution(
    sample: np.ndarray,
    candidates: list[str] | None = None,
) -> list[dict[str, float | str]]:
    """Fit candidate distributions and rank by AIC (lower = better)."""
    candidates = candidates or CANDIDATE_DISTRIBUTIONS
    results = []
    for name in candidates:
        dist = getattr(stats, name)
        try:
            params = dist.fit(sample)
            log_lik = dist.logpdf(sample, *params).sum()
            k = len(params)
            aic = 2 * k - 2 * log_lik
            _, ks_p = stats.kstest(sample, name, args=params)
            results.append({"distribution": name, "aic": aic, "ks_p": ks_p, "params": params})
        except Exception:
            continue
    return sorted(results, key=lambda r: r["aic"])
```

---

## Effect Size Guide

| d (Cohen's d) | Interpretation |
|---|---|
| < 0.2 | Negligible |
| 0.2 – 0.5 | Small |
| 0.5 – 0.8 | Medium |
| > 0.8 | Large |

**For chaos engineering**: a statistically significant result with d < 0.2 is often practically irrelevant — always report both p-value and effect size.

---

## Rules

- Never report p-value alone — always pair with effect size and CI
- Use Welch's t-test as default (not Student's) — it handles unequal variances
- Use bootstrap CI when sample size < 30 or distribution is unknown
- For multiple comparisons (> 2 groups), apply Bonferroni correction: `alpha_corrected = alpha / n_tests`
- Prefer Spearman over Pearson unless normality is confirmed
- State the null hypothesis explicitly in code comments or docstrings

---

## Anti-Patterns

| Anti-pattern | Fix |
|---|---|
| `p < 0.05` as sole criterion | Report effect size + CI + practical significance |
| Student t-test without variance check | Use Welch's by default (`equal_var=False`) |
| Pearson on skewed data | Check normality first; use Spearman if non-normal |
| Multiple t-tests without correction | Use ANOVA or apply Bonferroni |
| Discarding outliers without justification | Document outlier removal criteria |
| Reporting exact p=0.000 | Use `p < 0.001` threshold |
