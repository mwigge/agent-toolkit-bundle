"""
charts.py — Production chart examples for chaos platform metrics.

Demonstrates:
  - Time series with confidence interval (matplotlib)
  - Heatmap (seaborn)
  - Interactive scatter (plotly)

All charts:
  - Have proper axis labels and titles
  - Use accessible colormaps (viridis, cividis, colorbrewer)
  - Save to file (not just plt.show())
  - Use structured logging instead of print()

Dependencies: matplotlib, seaborn, plotly, numpy, pandas
Install: pip install matplotlib seaborn plotly numpy pandas
"""

from __future__ import annotations

import logging
from pathlib import Path

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# 1. Time Series with Confidence Interval (matplotlib)
# ---------------------------------------------------------------------------

def plot_success_rate_over_time(
    df: pd.DataFrame,
    output_path: Path = Path("success_rate_over_time.png"),
) -> None:
    """
    Plot daily success rate with 95% confidence interval.

    Args:
        df: DataFrame with columns: date (datetime), success (bool)
        output_path: File path for saved PNG
    """
    import matplotlib.pyplot as plt
    import matplotlib.dates as mdates

    logger.info("plotting_success_rate_time_series")

    # Aggregate to daily
    daily = (
        df.set_index("date")
        .resample("D")["success"]
        .agg(["mean", "count", "sum"])
        .rename(columns={"mean": "rate", "count": "n", "sum": "passed"})
        .dropna()
    )

    # Wilson score confidence interval for proportions
    z = 1.96  # 95% CI
    n = daily["n"]
    p = daily["rate"]
    denominator = 1 + z**2 / n
    centre = (p + z**2 / (2 * n)) / denominator
    half_width = (z * np.sqrt(p * (1 - p) / n + z**2 / (4 * n**2))) / denominator
    lower = np.clip(centre - half_width, 0, 1)
    upper = np.clip(centre + half_width, 0, 1)

    fig, ax = plt.subplots(figsize=(12, 5))

    ax.fill_between(daily.index, lower * 100, upper * 100,
                    alpha=0.2, color="#1f77b4", label="95% CI")
    ax.plot(daily.index, daily["rate"] * 100,
            color="#1f77b4", linewidth=2, marker=".", markersize=4, label="Success rate")

    ax.axhline(95, color="#d62728", linestyle="--", linewidth=1, alpha=0.7, label="Target (95%)")

    ax.set_xlabel("Date", fontsize=12)
    ax.set_ylabel("Success Rate (%)", fontsize=12)
    ax.set_title("Daily Experiment Success Rate with 95% Confidence Interval", fontsize=14)
    ax.set_ylim(0, 105)
    ax.legend(loc="lower right")
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %d"))
    ax.xaxis.set_major_locator(mdates.WeekdayLocator(interval=1))
    fig.autofmt_xdate()
    ax.grid(axis="y", alpha=0.3)

    fig.tight_layout()
    fig.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    logger.info("chart_saved", extra={"path": str(output_path)})

# ---------------------------------------------------------------------------
# 2. Heatmap (seaborn)
# ---------------------------------------------------------------------------

def plot_failure_heatmap(
    df: pd.DataFrame,
    output_path: Path = Path("failure_heatmap.png"),
) -> None:
    """
    Heatmap of experiment failure rates by service and fault type.

    Args:
        df: DataFrame with columns: service (str), fault_type (str), success (bool)
        output_path: File path for saved PNG
    """
    import matplotlib.pyplot as plt
    import seaborn as sns

    logger.info("plotting_failure_heatmap")

    pivot = (
        df.groupby(["service", "fault_type"])["success"]
        .agg(["mean", "count"])
        .reset_index()
        .assign(failure_rate=lambda x: (1 - x["mean"]) * 100)
        .pivot(index="service", columns="fault_type", values="failure_rate")
        .fillna(0)
    )

    # Sort by mean failure rate descending (highest-risk services at top)
    pivot = pivot.loc[pivot.mean(axis=1).sort_values(ascending=False).index]

    fig, ax = plt.subplots(figsize=(max(8, len(pivot.columns) * 1.5), max(5, len(pivot) * 0.6)))

    sns.heatmap(
        pivot,
        ax=ax,
        annot=True,
        fmt=".1f",
        cmap="YlOrRd",          # Accessible sequential colormap (yellow → red)
        vmin=0,
        vmax=100,
        linewidths=0.5,
        cbar_kws={"label": "Failure Rate (%)"},
    )

    ax.set_xlabel("Fault Type", fontsize=12)
    ax.set_ylabel("Service", fontsize=12)
    ax.set_title("Experiment Failure Rate by Service and Fault Type", fontsize=14)
    ax.tick_params(axis="x", rotation=30)
    ax.tick_params(axis="y", rotation=0)

    fig.tight_layout()
    fig.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    logger.info("chart_saved", extra={"path": str(output_path)})

# ---------------------------------------------------------------------------
# 3. Interactive Scatter (plotly)
# ---------------------------------------------------------------------------

def plot_resilience_scatter(
    df: pd.DataFrame,
    output_path: Path = Path("resilience_scatter.html"),
) -> None:
    """
    Interactive scatter: blast_radius vs duration_ms, coloured by success.

    Args:
        df: DataFrame with columns: blast_radius, duration_ms, success, name
        output_path: File path for saved HTML
    """
    import plotly.graph_objects as go

    logger.info("plotting_resilience_scatter")

    passed = df[df["success"] == True]
    failed = df[df["success"] == False]

    fig = go.Figure()

    fig.add_trace(go.Scatter(
        x=passed["blast_radius"],
        y=passed["duration_ms"],
        mode="markers",
        name="Passed",
        marker={
            "color": "#2ca02c",
            "size": 8,
            "opacity": 0.7,
            "symbol": "circle",
        },
        text=passed.get("name", pd.Series([""] * len(passed))),
        hovertemplate=(
            "<b>%{text}</b><br>"
            "Blast Radius: %{x:.2f}<br>"
            "Duration: %{y:.0f} ms<br>"
            "<extra></extra>"
        ),
    ))

    fig.add_trace(go.Scatter(
        x=failed["blast_radius"],
        y=failed["duration_ms"],
        mode="markers",
        name="Failed",
        marker={
            "color": "#d62728",
            "size": 8,
            "opacity": 0.7,
            "symbol": "x",
        },
        text=failed.get("name", pd.Series([""] * len(failed))),
        hovertemplate=(
            "<b>%{text}</b><br>"
            "Blast Radius: %{x:.2f}<br>"
            "Duration: %{y:.0f} ms<br>"
            "<extra></extra>"
        ),
    ))

    fig.update_layout(
        title={
            "text": "Experiment Outcome: Blast Radius vs Duration",
            "x": 0.5,
            "xanchor": "center",
        },
        xaxis_title="Blast Radius (fraction of system affected)",
        yaxis_title="Duration (ms)",
        legend_title="Outcome",
        hovermode="closest",
        width=900,
        height=600,
        font={"family": "Arial, sans-serif", "size": 13},
        plot_bgcolor="white",
        paper_bgcolor="white",
    )
    fig.update_xaxes(gridcolor="#e5e5e5", zeroline=True, zerolinecolor="#cccccc")
    fig.update_yaxes(gridcolor="#e5e5e5")

    fig.write_html(str(output_path), include_plotlyjs="cdn")
    logger.info("chart_saved", extra={"path": str(output_path)})

# ---------------------------------------------------------------------------
# Demo entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    rng = np.random.default_rng(42)
    n = 90

    # Generate synthetic data
    dates = pd.date_range("2026-01-01", periods=n, freq="D")
    df_ts = pd.DataFrame({
        "date": dates,
        "success": rng.choice([True, False], size=n, p=[0.93, 0.07]),
    })

    df_heat = pd.DataFrame({
        "service": rng.choice(["payments", "auth", "inventory", "notifications"], size=200),
        "fault_type": rng.choice(["latency", "connection_refused", "cpu_stress", "memory_leak"], size=200),
        "success": rng.choice([True, False], size=200, p=[0.85, 0.15]),
    })

    df_scatter = pd.DataFrame({
        "blast_radius": rng.uniform(0, 1, size=150),
        "duration_ms": rng.exponential(2000, size=150),
        "success": rng.choice([True, False], size=150, p=[0.82, 0.18]),
        "name": [f"exp-{i:04d}" for i in range(150)],
    })

    output_dir = Path("charts_output")
    output_dir.mkdir(exist_ok=True)

    plot_success_rate_over_time(df_ts, output_dir / "success_rate.png")
    plot_failure_heatmap(df_heat, output_dir / "failure_heatmap.png")
    plot_resilience_scatter(df_scatter, output_dir / "resilience_scatter.html")

    logger.info("all_charts_generated", extra={"output_dir": str(output_dir)})
