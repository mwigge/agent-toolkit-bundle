"""
analysis.py — Standalone data analysis script for chaos experiment metrics.

Demonstrates:
  - DuckDB query from Parquet file
  - Polars DataFrame operations (lazy API)
  - Statistical summary (mean, std, percentiles)
  - Output to JSON
  - Structured logging (no print())
  - Proper path handling

Dependencies: duckdb, polars  (install: pip install duckdb polars)
Usage:
    python analysis.py experiments.parquet [--output report.json]
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

try:
    import duckdb
except ImportError as exc:
    raise SystemExit("duckdb is required: pip install duckdb") from exc

try:
    import polars as pl
except ImportError as exc:
    raise SystemExit("polars is required: pip install polars") from exc


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("analysis")


def load_from_parquet(path: Path) -> pl.DataFrame:
    """Load experiment data from Parquet using DuckDB for SQL-based preprocessing."""
    logger.info("loading_data", extra={"path": str(path)})

    con = duckdb.connect()
    # Register the parquet file as a table
    result = con.execute(
        """
        SELECT
            id,
            name,
            status,
            success::BOOLEAN          AS success,
            blast_radius::DOUBLE      AS blast_radius,
            duration_ms::INTEGER      AS duration_ms,
            created_at::TIMESTAMP     AS created_at
        FROM read_parquet(?)
        WHERE status IN ('completed', 'failed')
          AND duration_ms IS NOT NULL
          AND duration_ms >= 0
        ORDER BY created_at ASC
        """,
        [str(path)],
    )
    arrow_table = result.arrow()
    df = pl.from_arrow(arrow_table)

    logger.info("data_loaded", extra={"rows": len(df), "columns": df.columns})
    return df


def compute_summary(df: pl.DataFrame) -> dict[str, object]:
    """Compute descriptive statistics for experiment duration and success rate."""
    logger.info("computing_summary")

    # Lazy plan for efficiency
    stats = (
        df.lazy()
        .filter(pl.col("status") == "completed")
        .with_columns([
            pl.col("duration_ms").cast(pl.Float64),
            pl.col("success").cast(pl.Int32),
        ])
        .select([
            pl.col("duration_ms").count().alias("n"),
            pl.col("duration_ms").mean().alias("mean_ms"),
            pl.col("duration_ms").std().alias("std_ms"),
            pl.col("duration_ms").median().alias("median_ms"),
            pl.col("duration_ms").quantile(0.25).alias("p25_ms"),
            pl.col("duration_ms").quantile(0.75).alias("p75_ms"),
            pl.col("duration_ms").quantile(0.95).alias("p95_ms"),
            pl.col("duration_ms").quantile(0.99).alias("p99_ms"),
            pl.col("duration_ms").min().alias("min_ms"),
            pl.col("duration_ms").max().alias("max_ms"),
            pl.col("success").mean().alias("success_rate"),
        ])
        .collect()
    )

    row = stats.row(0, named=True)

    # Success by blast radius bucket
    blast_summary = (
        df.lazy()
        .filter(pl.col("status") == "completed")
        .with_columns([
            pl.when(pl.col("blast_radius") < 0.1).then(pl.lit("low"))
            .when(pl.col("blast_radius") < 0.5).then(pl.lit("medium"))
            .otherwise(pl.lit("high"))
            .alias("blast_bucket")
        ])
        .group_by("blast_bucket")
        .agg([
            pl.col("success").cast(pl.Int32).mean().alias("success_rate"),
            pl.col("duration_ms").mean().alias("mean_duration_ms"),
            pl.len().alias("count"),
        ])
        .sort("blast_bucket")
        .collect()
    )

    return {
        "total_experiments": len(df),
        "completed_experiments": int(row["n"]),
        "success_rate": round(float(row["success_rate"]) * 100, 2),
        "duration_ms": {
            "mean":   round(float(row["mean_ms"]),   1) if row["mean_ms"]   else None,
            "std":    round(float(row["std_ms"]),    1) if row["std_ms"]    else None,
            "median": round(float(row["median_ms"]), 1) if row["median_ms"] else None,
            "p25":    round(float(row["p25_ms"]),    1) if row["p25_ms"]    else None,
            "p75":    round(float(row["p75_ms"]),    1) if row["p75_ms"]    else None,
            "p95":    round(float(row["p95_ms"]),    1) if row["p95_ms"]    else None,
            "p99":    round(float(row["p99_ms"]),    1) if row["p99_ms"]    else None,
            "min":    int(row["min_ms"]) if row["min_ms"] is not None else None,
            "max":    int(row["max_ms"]) if row["max_ms"] is not None else None,
        },
        "by_blast_radius": [
            {
                "bucket": row_b["blast_bucket"],
                "count": int(row_b["count"]),
                "success_rate_pct": round(float(row_b["success_rate"]) * 100, 2),
                "mean_duration_ms": round(float(row_b["mean_duration_ms"]), 1),
            }
            for row_b in blast_summary.iter_rows(named=True)
        ],
    }


def compute_outliers(df: pl.DataFrame) -> list[dict[str, object]]:
    """Identify experiments with anomalous duration using IQR method."""
    logger.info("detecting_outliers")

    completed = df.filter(pl.col("status") == "completed").filter(
        pl.col("duration_ms").is_not_null()
    )
    if len(completed) < 4:
        return []

    q1 = completed["duration_ms"].quantile(0.25) or 0.0
    q3 = completed["duration_ms"].quantile(0.75) or 0.0
    iqr = q3 - q1
    lower = q1 - 1.5 * iqr
    upper = q3 + 1.5 * iqr

    outliers = completed.filter(
        (pl.col("duration_ms") < lower) | (pl.col("duration_ms") > upper)
    )

    logger.info("outliers_detected", extra={"count": len(outliers), "lower": lower, "upper": upper})

    return [
        {"id": row["id"], "name": row["name"], "duration_ms": row["duration_ms"]}
        for row in outliers.iter_rows(named=True)
    ]


def write_report(report: dict[str, object], output_path: Path) -> None:
    logger.info("writing_report", extra={"path": str(output_path)})
    output_path.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")
    logger.info("report_written", extra={"path": str(output_path)})


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Analyse chaos experiment Parquet data")
    parser.add_argument("input", type=Path, help="Path to experiments Parquet file")
    parser.add_argument("--output", "-o", type=Path, default=Path("report.json"),
                        help="Output JSON report path (default: report.json)")
    args = parser.parse_args(argv)

    if not args.input.exists():
        logger.error("input_not_found", extra={"path": str(args.input)})
        return 1

    df = load_from_parquet(args.input)
    summary = compute_summary(df)
    outliers = compute_outliers(df)

    report: dict[str, object] = {
        "source": str(args.input),
        "summary": summary,
        "outliers": outliers,
        "outlier_count": len(outliers),
    }

    write_report(report, args.output)
    logger.info("analysis_complete", extra={"output": str(args.output)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
