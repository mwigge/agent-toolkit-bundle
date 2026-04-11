"""
time_series_analysis.py — Complete time series pipeline for experiment metrics.

Pipeline:
  1. Load from CSV
  2. Resample to regular interval
  3. Interpolate gaps
  4. STL decomposition (statsmodels)
  5. Anomaly detection (IQR method)
  6. Forecast with Prophet
  7. Output JSON report

Dependencies: pandas, numpy, statsmodels, prophet
Install: pip install pandas numpy statsmodels prophet
"""

from __future__ import annotations

import json
import logging
import sys
from pathlib import Path

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# 1. Load and clean
# ---------------------------------------------------------------------------

def load_series(path: Path, value_col: str = "value") -> pd.Series:
    """Load CSV to a DatetimeIndex Series."""
    logger.info("loading_series", extra={"path": str(path), "value_col": value_col})

    df = pd.read_csv(path, parse_dates=["timestamp"])

    if "timestamp" not in df.columns:
        raise ValueError(f"CSV must have a 'timestamp' column. Found: {list(df.columns)}")
    if value_col not in df.columns:
        raise ValueError(f"Value column '{value_col}' not found. Found: {list(df.columns)}")

    series = df.set_index("timestamp")[value_col].sort_index()
    series = series[~series.index.duplicated(keep="first")]
    logger.info("series_loaded", extra={"rows": len(series)})
    return series

# ---------------------------------------------------------------------------
# 2. Resample to regular interval
# ---------------------------------------------------------------------------

def resample_regular(series: pd.Series, freq: str = "1min") -> pd.Series:
    """Resample series to a fixed frequency. Returns NaN for missing periods."""
    logger.info("resampling", extra={"freq": freq})
    resampled = series.resample(freq).mean()
    gap_count = int(resampled.isna().sum())
    logger.info("resampled", extra={"rows": len(resampled), "gaps": gap_count})
    return resampled

# ---------------------------------------------------------------------------
# 3. Interpolate gaps
# ---------------------------------------------------------------------------

def interpolate_gaps(
    series: pd.Series,
    method: str = "time",
    max_gap_periods: int = 10,
) -> pd.Series:
    """
    Fill gaps using time-based interpolation.
    Gaps larger than max_gap_periods are left as NaN.
    """
    logger.info("interpolating", extra={"method": method, "max_gap_periods": max_gap_periods})

    # Mark large gaps to leave unfilled
    na_mask = series.isna()
    gap_groups = (~na_mask).cumsum()
    gap_sizes = na_mask.groupby(gap_groups).transform("sum")
    large_gaps = na_mask & (gap_sizes > max_gap_periods)

    interpolated = series.interpolate(method=method, limit=max_gap_periods)
    interpolated[large_gaps] = np.nan  # Restore large gaps

    filled = int((~na_mask).sum())
    logger.info("interpolation_complete",
                extra={"filled": int(na_mask.sum()) - int(interpolated.isna().sum())})
    return interpolated

# ---------------------------------------------------------------------------
# 4. STL Decomposition
# ---------------------------------------------------------------------------

def stl_decompose(
    series: pd.Series,
    period: int = 1440,  # 1440 minutes = 1 day
) -> dict[str, pd.Series]:
    """
    STL (Seasonal-Trend decomposition using Loess).
    Returns dict with 'trend', 'seasonal', 'residual' components.
    """
    try:
        from statsmodels.tsa.seasonal import STL
    except ImportError as exc:
        raise ImportError("statsmodels is required: pip install statsmodels") from exc

    logger.info("stl_decomposition", extra={"period": period})

    # STL requires complete (no NaN) series
    clean = series.dropna()
    if len(clean) < period * 2:
        logger.warning("insufficient_data_for_stl",
                       extra={"rows": len(clean), "required": period * 2})
        return {"trend": clean, "seasonal": pd.Series(0, index=clean.index), "residual": clean}

    stl = STL(clean, period=period, robust=True)
    result = stl.fit()

    return {
        "trend": pd.Series(result.trend, index=clean.index),
        "seasonal": pd.Series(result.seasonal, index=clean.index),
        "residual": pd.Series(result.resid, index=clean.index),
    }

# ---------------------------------------------------------------------------
# 5. Anomaly Detection (IQR method)
# ---------------------------------------------------------------------------

def detect_anomalies(
    series: pd.Series,
    iqr_multiplier: float = 3.0,
) -> pd.DataFrame:
    """
    Flag anomalies using the IQR method on the series values.
    Returns DataFrame with columns: value, is_anomaly, lower_bound, upper_bound.
    """
    logger.info("detecting_anomalies", extra={"iqr_multiplier": iqr_multiplier})

    q1 = float(series.quantile(0.25))
    q3 = float(series.quantile(0.75))
    iqr = q3 - q1
    lower = q1 - iqr_multiplier * iqr
    upper = q3 + iqr_multiplier * iqr

    anomaly_df = pd.DataFrame({
        "value": series,
        "is_anomaly": (series < lower) | (series > upper),
        "lower_bound": lower,
        "upper_bound": upper,
    })

    anomaly_count = int(anomaly_df["is_anomaly"].sum())
    logger.info("anomalies_detected",
                extra={"count": anomaly_count, "lower": lower, "upper": upper})
    return anomaly_df

# ---------------------------------------------------------------------------
# 6. Prophet Forecast
# ---------------------------------------------------------------------------

def prophet_forecast(
    series: pd.Series,
    periods: int = 60,
    freq: str = "1min",
) -> pd.DataFrame:
    """
    Forecast using Prophet. Returns DataFrame with ds, yhat, yhat_lower, yhat_upper.
    """
    try:
        from prophet import Prophet
    except ImportError as exc:
        raise ImportError("prophet is required: pip install prophet") from exc

    logger.info("prophet_forecast", extra={"periods": periods, "freq": freq})

    df_prophet = pd.DataFrame({
        "ds": series.dropna().index,
        "y": series.dropna().values,
    })

    m = Prophet(
        interval_width=0.95,
        yearly_seasonality=False,
        weekly_seasonality=True,
        daily_seasonality=True,
    )
    m.fit(df_prophet)

    future = m.make_future_dataframe(periods=periods, freq=freq)
    forecast = m.predict(future)

    logger.info("forecast_complete", extra={"forecast_rows": len(forecast)})
    return forecast[["ds", "yhat", "yhat_lower", "yhat_upper"]]

# ---------------------------------------------------------------------------
# 7. Report
# ---------------------------------------------------------------------------

def build_report(
    series: pd.Series,
    anomalies: pd.DataFrame,
    decomposition: dict[str, pd.Series],
    forecast: pd.DataFrame | None = None,
) -> dict[str, object]:
    clean = series.dropna()

    return {
        "summary": {
            "total_points": int(len(series)),
            "non_null_points": int(len(clean)),
            "missing_pct": round((series.isna().sum() / len(series)) * 100, 2),
            "start": str(series.index.min()),
            "end":   str(series.index.max()),
            "mean":   round(float(clean.mean()),   4),
            "std":    round(float(clean.std()),    4),
            "median": round(float(clean.median()), 4),
            "p95":    round(float(clean.quantile(0.95)), 4),
            "min":    round(float(clean.min()), 4),
            "max":    round(float(clean.max()), 4),
        },
        "anomalies": {
            "count": int(anomalies["is_anomaly"].sum()),
            "pct":   round(float(anomalies["is_anomaly"].mean()) * 100, 2),
            "timestamps": [
                str(ts) for ts in anomalies.index[anomalies["is_anomaly"]].tolist()[:20]
            ],
        },
        "decomposition": {
            "trend_range": {
                "min": round(float(decomposition["trend"].min()), 4),
                "max": round(float(decomposition["trend"].max()), 4),
            },
            "seasonal_amplitude": round(
                float(decomposition["seasonal"].max() - decomposition["seasonal"].min()), 4
            ),
        },
        "forecast": (
            {
                "periods": len(forecast[forecast["ds"] > series.index.max()]),
                "last_yhat": round(float(forecast["yhat"].iloc[-1]), 4),
            }
            if forecast is not None
            else None
        ),
    }

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Time series analysis pipeline")
    parser.add_argument("csv_file", type=Path, help="Input CSV with 'timestamp' and 'value' columns")
    parser.add_argument("--value-col", default="value", help="Name of value column")
    parser.add_argument("--freq", default="1min", help="Resample frequency (default: 1min)")
    parser.add_argument("--forecast-periods", type=int, default=60,
                        help="Number of periods to forecast (default: 60)")
    parser.add_argument("--output", type=Path, default=Path("ts_report.json"))
    parser.add_argument("--no-forecast", action="store_true",
                        help="Skip Prophet forecasting (faster)")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    if not args.csv_file.exists():
        logger.error("file_not_found", extra={"path": str(args.csv_file)})
        return 1

    series = load_series(args.csv_file, value_col=args.value_col)
    resampled = resample_regular(series, freq=args.freq)
    interpolated = interpolate_gaps(resampled)

    decomp = stl_decompose(interpolated)
    anomalies = detect_anomalies(interpolated)

    forecast = None
    if not args.no_forecast:
        try:
            forecast = prophet_forecast(interpolated, periods=args.forecast_periods, freq=args.freq)
        except ImportError as exc:
            logger.warning("prophet_unavailable", extra={"reason": str(exc)})

    report = build_report(interpolated, anomalies, decomp, forecast)
    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    logger.info("report_written", extra={"path": str(args.output)})
    return 0

if __name__ == "__main__":
    sys.exit(main())
