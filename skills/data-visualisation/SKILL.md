---
name: data-visualisation
description: >
  Chart type selection, matplotlib/seaborn/plotly patterns, publication-quality
  figures, interactive dashboards, and chaos experiment result visualisation.
  Activate when producing plots, charts, dashboards, or any visual output.
version: 1.0.0
argument-hint: "[chart type or data to visualise]"
---

# Data Visualisation Skill

## When to activate
- Plotting experiment results, metrics, or probe data
- EDA charts (distributions, correlations, outliers)
- Time series visualisation
- Comparing baseline vs post-chaos resilience scores
- Publication-quality static figures (PDF/SVG)
- Interactive dashboards with Plotly

---

## Library Selection Guide

| Use case | Library | Why |
|---|---|---|
| Static publication figures | `matplotlib` + `seaborn` | Full control, PDF/SVG export |
| Quick EDA | `seaborn` | High-level, sensible defaults |
| Interactive / web | `plotly` | HTML embed, zoom/hover |
| DataFrame-native | `pandas.DataFrame.plot` | Rapid prototyping only |
| Dashboards | `plotly + dash` | Full reactive UI |

---

## Setup — Consistent Style

```python
import matplotlib.pyplot as plt
import matplotlib as mpl
import seaborn as sns
import plotly.graph_objects as go
import plotly.express as px

# Global style (call once at module level)
def set_publication_style() -> None:
    sns.set_theme(style="whitegrid", palette="colorblind")
    mpl.rcParams.update({
        "figure.dpi": 150,
        "figure.figsize": (10, 6),
        "font.size": 11,
        "axes.titlesize": 13,
        "axes.labelsize": 11,
        "xtick.labelsize": 9,
        "ytick.labelsize": 9,
        "legend.fontsize": 9,
        "savefig.bbox": "tight",
        "savefig.dpi": 300,
    })
```

---

## Chart Type Selection

### Distribution

```python
# Single distribution — histogram + KDE
def plot_distribution(series: pd.Series, title: str, output: Path) -> None:
    fig, ax = plt.subplots()
    sns.histplot(series, kde=True, ax=ax, color="steelblue", bins=40)
    ax.set_title(title)
    ax.set_xlabel(series.name)
    ax.set_ylabel("Count")
    _add_percentile_lines(ax, series, percentiles=[50, 95, 99])
    fig.savefig(output)
    plt.close(fig)

def _add_percentile_lines(ax, series: pd.Series, percentiles: list[int]) -> None:
    colors = {50: "green", 95: "orange", 99: "red"}
    for p in percentiles:
        val = series.quantile(p / 100)
        ax.axvline(val, color=colors.get(p, "grey"), linestyle="--", linewidth=1, label=f"p{p}={val:.1f}")
    ax.legend()
```

### Comparison (boxplot / violin)

```python
def plot_comparison(df: pd.DataFrame, x: str, y: str, title: str, output: Path) -> None:
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))
    sns.boxplot(data=df, x=x, y=y, ax=ax1, palette="colorblind")
    ax1.set_title("Box plot")
    sns.violinplot(data=df, x=x, y=y, ax=ax2, palette="colorblind", inner="quartile")
    ax2.set_title("Violin plot")
    fig.suptitle(title)
    fig.savefig(output)
    plt.close(fig)
```

### Heatmap (correlation matrix)

```python
def plot_correlation_heatmap(df: pd.DataFrame, output: Path) -> None:
    corr = df.select_dtypes(include="number").corr()
    mask = np.triu(np.ones_like(corr, dtype=bool))
    fig, ax = plt.subplots(figsize=(max(8, len(corr)), max(6, len(corr) - 1)))
    sns.heatmap(
        corr, mask=mask, annot=True, fmt=".2f",
        cmap="coolwarm", center=0, linewidths=0.5,
        ax=ax, square=True, cbar_kws={"shrink": 0.8},
    )
    ax.set_title("Correlation Matrix")
    fig.savefig(output)
    plt.close(fig)
```

### Time series

```python
def plot_time_series(
    df: pd.DataFrame,
    time_col: str,
    value_col: str,
    title: str,
    output: Path,
    highlight_events: list[dict] | None = None,
) -> None:
    fig, ax = plt.subplots()
    ax.plot(df[time_col], df[value_col], linewidth=1.2, color="steelblue")
    if highlight_events:
        for ev in highlight_events:
            ax.axvline(ev["time"], color="red", linestyle="--", alpha=0.7, label=ev.get("label", "event"))
        ax.legend()
    ax.set_title(title)
    ax.set_xlabel("Time")
    ax.set_ylabel(value_col)
    fig.autofmt_xdate()
    fig.savefig(output)
    plt.close(fig)
```

---

## Interactive Plotly Patterns

```python
def interactive_line(
    df: pd.DataFrame,
    x: str,
    y: str | list[str],
    title: str,
    output_html: Path,
) -> None:
    fig = px.line(df, x=x, y=y, title=title, template="plotly_white")
    fig.update_layout(
        hovermode="x unified",
        legend=dict(orientation="h", yanchor="bottom", y=1.02),
    )
    fig.write_html(str(output_html), include_plotlyjs="cdn")

def interactive_scatter(
    df: pd.DataFrame,
    x: str,
    y: str,
    color: str | None = None,
    size: str | None = None,
    title: str = "",
    output_html: Path | None = None,
) -> go.Figure:
    fig = px.scatter(
        df, x=x, y=y, color=color, size=size,
        title=title, template="plotly_white",
        hover_data=df.columns.tolist(),
    )
    if output_html:
        fig.write_html(str(output_html), include_plotlyjs="cdn")
    return fig
```

---

## Chaos Experiment Result Chart

```python
def plot_resilience_comparison(
    baseline: dict[str, float],
    post_chaos: dict[str, float],
    output: Path,
) -> None:
    """Side-by-side bar chart: baseline vs post-chaos for each metric."""
    metrics = list(baseline.keys())
    x = np.arange(len(metrics))
    width = 0.35

    fig, ax = plt.subplots(figsize=(max(8, len(metrics) * 1.5), 6))
    ax.bar(x - width / 2, [baseline[m] for m in metrics], width, label="Baseline", color="steelblue")
    ax.bar(x + width / 2, [post_chaos[m] for m in metrics], width, label="Post-chaos", color="coral")

    ax.set_xticks(x)
    ax.set_xticklabels(metrics, rotation=30, ha="right")
    ax.set_ylabel("Value")
    ax.set_title("Baseline vs Post-Chaos Metrics")
    ax.legend()
    ax.grid(axis="y", alpha=0.4)
    fig.savefig(output)
    plt.close(fig)
```

---

## Rules

- Always `plt.close(fig)` after saving — prevents memory leaks in long analysis runs
- Always pass `output: Path` — never call `plt.show()` in library/pipeline code (only in notebooks)
- Use `colorblind` palette for all seaborn charts (accessibility)
- Export static charts as **PDF or SVG** for reports, **PNG** (300 dpi) for documents
- Export interactive charts as **HTML with `include_plotlyjs="cdn"`** — no bundled JS
- Never hardcode figure sizes — parameterise or derive from data shape

---

## Anti-Patterns

| Anti-pattern | Fix |
|---|---|
| `plt.show()` in non-notebook code | `fig.savefig(output); plt.close(fig)` |
| Global `plt.figure()` then forgetting close | Always use context or explicit `plt.close` |
| Default matplotlib colours | Set seaborn theme or colorblind palette |
| Saving PNG at default 72 dpi | `savefig(path, dpi=300)` |
| Hardcoded title strings | Pass `title: str` parameter |
