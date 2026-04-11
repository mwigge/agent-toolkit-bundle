---
name: time-series
description: >
  Time series analysis: ARIMA/GARCH modelling, rolling windows, trend/seasonality
  decomposition, stationarity testing, forecasting, and chaos experiment temporal
  analysis. Activate when working with time-indexed data or forecasting tasks.
version: 1.0.0
argument-hint: "[time series dataset or forecasting goal]"
---

# Time Series Skill

## When to activate
- Analysing metrics over time (latency, error rate, throughput)
- Detecting anomalies or change points in chaos experiment data
- Forecasting future metric values
- Decomposing trend + seasonality + residuals
- Stationarity testing before modelling
- Rolling statistics (SLI/SLO monitoring)

---

## Core Libraries

```python
import pandas as pd
import numpy as np
from statsmodels.tsa.statespace.sarimax import SARIMAX
from statsmodels.tsa.stattools import adfuller, kpss
from statsmodels.tsa.seasonal import STL
from scipy import signal
```

Pinned deps:
```toml
[project]
dependencies = [
    "pandas>=2.2",
    "numpy>=1.26",
    "statsmodels>=0.14",
    "scipy>=1.12",
]
```

---

## Time-Index Setup

Always convert to a proper DatetimeIndex before analysis:

```python
def prepare_time_index(
    df: pd.DataFrame,
    time_col: str,
    value_col: str,
    freq: str = "T",  # T=minute, H=hour, D=day, W=week
) -> pd.Series:
    """Return a regularly-spaced Series with DatetimeIndex."""
    ts = (
        df[[time_col, value_col]]
        .set_index(time_col)
        .squeeze()
        .rename(value_col)
    )
    ts.index = pd.to_datetime(ts.index, utc=True)
    ts = ts.sort_index()
    # Resample to regular frequency, forward-fill short gaps (≤ 3 periods)
    ts = ts.resample(freq).mean().ffill(limit=3)
    return ts
```

---

## Stationarity Testing

Run both ADF and KPSS — they have opposite null hypotheses:

```python
from dataclasses import dataclass

@dataclass
class StationarityResult:
    is_stationary: bool
    adf_p: float
    kpss_p: float
    recommendation: str

def test_stationarity(ts: pd.Series, alpha: float = 0.05) -> StationarityResult:
    adf_stat, adf_p, *_ = adfuller(ts.dropna(), autolag="AIC")
    kpss_stat, kpss_p, *_ = kpss(ts.dropna(), regression="c", nlags="auto")

    # ADF H0: unit root (non-stationary) → small p = stationary
    # KPSS H0: stationary → small p = non-stationary
    adf_stationary  = adf_p  < alpha
    kpss_stationary = kpss_p > alpha
    is_stationary   = adf_stationary and kpss_stationary

    if is_stationary:
        rec = "Series is stationary — proceed with ARIMA(p,0,q)"
    elif adf_stationary and not kpss_stationary:
        rec = "Conflicting results — possible trend stationarity; try first difference"
    else:
        rec = "Non-stationary — apply differencing (d=1) or log transform"

    return StationarityResult(is_stationary, adf_p, kpss_p, rec)
```

---

## Seasonal Decomposition (STL)

Preferred over classical additive/multiplicative decomposition — robust to outliers:

```python
def decompose_stl(
    ts: pd.Series,
    period: int,       # e.g. 24 for hourly data with daily seasonality
    robust: bool = True,
) -> dict[str, pd.Series]:
    stl = STL(ts.dropna(), period=period, robust=robust)
    result = stl.fit()
    return {
        "trend":    result.trend,
        "seasonal": result.seasonal,
        "residual": result.resid,
        "observed": result.observed,
    }
```

---

## Rolling Statistics

```python
def rolling_stats(
    ts: pd.Series,
    window: int,
    percentiles: list[float] | None = None,
) -> pd.DataFrame:
    if percentiles is None:
        percentiles = [0.5, 0.95, 0.99]
    result = pd.DataFrame(index=ts.index)
    result["mean"]  = ts.rolling(window).mean()
    result["std"]   = ts.rolling(window).std()
    result["min"]   = ts.rolling(window).min()
    result["max"]   = ts.rolling(window).max()
    for p in percentiles:
        result[f"p{int(p*100)}"] = ts.rolling(window).quantile(p)
    return result

def rolling_anomaly_score(ts: pd.Series, window: int = 60) -> pd.Series:
    """Z-score of each value relative to the rolling window."""
    mu  = ts.rolling(window).mean()
    std = ts.rolling(window).std().replace(0, np.nan)
    return (ts - mu) / std
```

---

## ARIMA Modelling

```python
from dataclasses import dataclass
from typing import Any

@dataclass
class ForecastResult:
    forecast: pd.Series
    lower_ci: pd.Series
    upper_ci: pd.Series
    aic: float
    order: tuple[int, int, int]

def fit_arima(
    ts: pd.Series,
    order: tuple[int, int, int] = (1, 1, 1),
    seasonal_order: tuple[int, int, int, int] = (0, 0, 0, 0),
) -> Any:  # returns fitted SARIMAXResults
    model = SARIMAX(
        ts.dropna(),
        order=order,
        seasonal_order=seasonal_order,
        enforce_stationarity=False,
        enforce_invertibility=False,
    )
    return model.fit(disp=False)

def forecast_arima(
    fitted_model: Any,
    steps: int,
    alpha: float = 0.05,
) -> ForecastResult:
    pred = fitted_model.get_forecast(steps=steps)
    summary = pred.summary_frame(alpha=alpha)
    return ForecastResult(
        forecast=summary["mean"],
        lower_ci=summary["mean_ci_lower"],
        upper_ci=summary["mean_ci_upper"],
        aic=fitted_model.aic,
        order=fitted_model.model.order,
    )
```

---

## Change Point Detection

Lightweight approach using rolling mean shift (no extra deps):

```python
def detect_change_points(
    ts: pd.Series,
    window: int = 20,
    threshold_std: float = 3.0,
) -> pd.DatetimeIndex:
    """Return timestamps where rolling mean shifts by > threshold_std * std."""
    roll_mean = ts.rolling(window).mean()
    diff = roll_mean.diff().abs()
    std  = diff.std()
    return ts.index[diff > threshold_std * std]
```

---

## Chaos Experiment Temporal Analysis

```python
def annotate_chaos_window(
    ts: pd.Series,
    chaos_start: pd.Timestamp,
    chaos_end: pd.Timestamp,
) -> dict[str, pd.Series]:
    """Split series into pre/during/post chaos windows."""
    return {
        "pre":    ts[ts.index < chaos_start],
        "during": ts[(ts.index >= chaos_start) & (ts.index <= chaos_end)],
        "post":   ts[ts.index > chaos_end],
    }

def recovery_time(ts: pd.Series, baseline_mean: float, threshold: float = 0.05) -> pd.Timedelta | None:
    """Time from chaos_end until metric is within threshold*100% of baseline."""
    within = ts[np.abs(ts - baseline_mean) / baseline_mean <= threshold]
    return (within.index[0] - ts.index[0]) if len(within) > 0 else None
```

---

## Rules

- Always test stationarity before fitting ARIMA
- Use STL decomposition (not classical) — it handles outliers better
- For chaos data: always annotate `pre/during/post` windows before analysis
- Rolling window size: minimum 4× the seasonality period for stable estimates
- Store forecast results as typed dataclasses — not raw tuples
- Never use `model.fit(disp=True)` in pipeline code — suppresses noisy optimiser output

---

## Anti-Patterns

| Anti-pattern | Fix |
|---|---|
| Raw `pd.datetime` strings as index | `pd.to_datetime(..., utc=True)` |
| Fitting ARIMA on non-stationary data | Always run `test_stationarity` first |
| `resample().mean()` without `ffill` limit | Set `ffill(limit=3)` to avoid ghost data |
| Ignoring confidence intervals | Always return and report CI bands |
| Rolling window < seasonality period | Use ≥ 4× period for stable estimates |
