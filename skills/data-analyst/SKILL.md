---
name: data-analyst
description: >
  EDA workflow, pandas/NumPy data manipulation, summary statistics, outlier
  detection, correlation analysis, and structured data investigation patterns.
  Activate when asked to explore, clean, aggregate, or summarise datasets.
version: 1.0.0
argument-hint: "[dataset or analysis goal]"
---

# Data Analyst Skill

## When to activate
- Exploratory data analysis (EDA) on any dataset
- Data cleaning, deduplication, type coercion
- Aggregation, groupby, pivot, reshape
- Correlation and outlier analysis
- Feature engineering for ML pipelines
- Reporting summary statistics from experiment or probe data

---

## Core Libraries

```python
import pandas as pd
import numpy as np
from pathlib import Path
```

Always pin versions in `pyproject.toml`:
```toml
[project]
dependencies = [
    "pandas>=2.2",
    "numpy>=1.26",
    "pyarrow>=15",   # fast parquet I/O
]
```

---

## EDA Workflow — Standard Order

### 1. Load

```python
def load_data(path: Path) -> pd.DataFrame:
    """Load CSV, Parquet, or JSON with explicit types."""
    suffix = path.suffix.lower()
    match suffix:
        case ".csv":
            return pd.read_csv(path, dtype_backend="numpy_nullable")
        case ".parquet":
            return pd.read_parquet(path)
        case ".json":
            return pd.read_json(path, orient="records", lines=True)
        case _:
            raise ValueError(f"Unsupported format: {suffix}")
```

### 2. Inspect

```python
def inspect(df: pd.DataFrame) -> None:
    print(f"Shape: {df.shape}")
    print(f"\nDtypes:\n{df.dtypes}")
    print(f"\nMissing:\n{df.isnull().sum()[df.isnull().sum() > 0]}")
    print(f"\nHead:\n{df.head(3)}")
```

### 3. Summary statistics

```python
def describe_numeric(df: pd.DataFrame) -> pd.DataFrame:
    return df.select_dtypes(include="number").describe(percentiles=[0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99]).T
```

### 4. Missing value analysis

```python
def missing_report(df: pd.DataFrame) -> pd.DataFrame:
    total = df.isnull().sum()
    pct = total / len(df) * 100
    return pd.DataFrame({"missing_count": total, "missing_pct": pct}).query("missing_count > 0").sort_values("missing_pct", ascending=False)
```

### 5. Outlier detection (IQR method)

```python
def flag_outliers_iqr(df: pd.DataFrame, col: str, k: float = 1.5) -> pd.Series:
    q1, q3 = df[col].quantile([0.25, 0.75])
    iqr = q3 - q1
    return (df[col] < q1 - k * iqr) | (df[col] > q3 + k * iqr)
```

### 6. Correlation matrix

```python
def top_correlations(df: pd.DataFrame, threshold: float = 0.5) -> pd.DataFrame:
    corr = df.select_dtypes(include="number").corr().abs()
    upper = corr.where(np.triu(np.ones(corr.shape), k=1).astype(bool))
    return (
        upper.stack()
        .reset_index()
        .rename(columns={"level_0": "feature_a", "level_1": "feature_b", 0: "correlation"})
        .query("correlation >= @threshold")
        .sort_values("correlation", ascending=False)
    )
```

---

## Data Cleaning Patterns

### Type coercion

```python
def coerce_types(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    for col in df.select_dtypes(include="object"):
        # Try datetime
        try:
            df[col] = pd.to_datetime(df[col], errors="raise")
        except Exception:
            # Try numeric
            coerced = pd.to_numeric(df[col], errors="coerce")
            if coerced.notna().mean() > 0.8:
                df[col] = coerced
    return df
```

### Deduplication

```python
df = df.drop_duplicates(subset=["id"], keep="last")
```

### Fill strategy

```python
# Numeric: median fill (robust to outliers)
df[numeric_cols] = df[numeric_cols].fillna(df[numeric_cols].median())
# Categorical: mode fill
df[cat_cols] = df[cat_cols].fillna(df[cat_cols].mode().iloc[0])
```

---

## Aggregation Patterns

```python
# Multi-level groupby with named aggregation
result = (
    df.groupby(["region", "component"])
    .agg(
        p50_latency=("latency_ms", "median"),
        p99_latency=("latency_ms", lambda s: s.quantile(0.99)),
        error_rate=("is_error", "mean"),
        sample_count=("latency_ms", "count"),
    )
    .reset_index()
)
```

---

## Performance Rules

- Use `pd.read_parquet()` over CSV for files > 10 MB
- Set `dtype_backend="numpy_nullable"` to avoid silent float coercion of ints
- Prefer `.query()` over boolean indexing for readability on large DataFrames
- Use `pd.CategoricalDtype` for low-cardinality string columns (10x memory saving)
- Avoid row-by-row iteration — use `.apply()` only when vectorisation is impossible
- Use `chunksize=` in `read_csv` for files > 500 MB

---

## Anti-Patterns

| Anti-pattern | Fix |
|---|---|
| `df['col'] = df['col'].apply(lambda x: ...)` over numeric | Use vectorised `np.where` / `.str.` methods |
| Chained indexing `df['a']['b']` | Use `.loc[:, ('a', 'b')]` |
| `for i, row in df.iterrows()` | Vectorise or use `.apply(axis=1)` as last resort |
| `df.dropna()` without inspection | Always check missing % first |
| Implicit string→float coercion | Explicit `pd.to_numeric(errors='coerce')` |
| Ignoring `.copy()` after `.loc` slice | Always `.copy()` to avoid `SettingWithCopyWarning` |

---

## Testing Data Analysis Code

```python
import pytest
import pandas as pd
import numpy as np
from your_module import flag_outliers_iqr, describe_numeric

@pytest.fixture
def sample_df() -> pd.DataFrame:
    rng = np.random.default_rng(42)
    return pd.DataFrame({
        "latency_ms": rng.normal(100, 20, 200).tolist() + [999, 1000],  # 2 outliers
        "region": ["eu"] * 100 + ["us"] * 102,
    })

def test_flag_outliers_detects_injected_outliers(sample_df: pd.DataFrame) -> None:
    mask = flag_outliers_iqr(sample_df, "latency_ms")
    assert mask.sum() == 2, f"Expected 2 outliers, got {mask.sum()}"

def test_describe_numeric_covers_all_percentiles(sample_df: pd.DataFrame) -> None:
    desc = describe_numeric(sample_df)
    assert "99%" in desc.columns
```
