---
name: data-engineer
description: Use when designing, building, or reviewing data pipelines, dbt models, orchestration DAGs, Spark jobs, warehouse patterns, data contracts, or data-quality checks.
---

# Skill: Data Engineer

**Version**: 1.0.0 | **Updated**: 2026-04-05

Apply this skill when designing, building, or reviewing data pipelines, dbt models, orchestration DAGs, Spark jobs, warehouse patterns, data contracts, or data quality checks.

---

## Pipeline Design Principles

### Idempotency
Every pipeline run must produce the same result if re-run with the same input. Enforce this by:
- Using `MERGE` / `INSERT OVERWRITE` patterns, never plain `INSERT`
- Keying on natural business keys, not surrogate IDs generated at load time
- Writing to partition-aligned output paths; overwrite the partition, never append blindly

### Exactly-Once Semantics
Distinguish delivery guarantees:
- **At-most-once**: data may be lost, never duplicated — unacceptable for financial data
- **At-least-once**: data may be duplicated — tolerable with downstream deduplication
- **Exactly-once**: requires idempotent writes + transactional commits (Spark + Delta Lake, Flink checkpoints, Kafka transactions)

Practically: design for at-least-once delivery + idempotent sinks. True exactly-once end-to-end is expensive and usually unnecessary.

### Late-Arriving Data
- Define a **watermark** (event-time tolerance beyond which late records are dropped or sent to a dead-letter partition)
- For batch: use `processed_date` partitioning with a reprocessing window (e.g., always reload last 3 days)
- For streaming: Spark Structured Streaming `withWatermark("event_time", "2 hours")`
- Never assume data arrives in order; always sort or window before aggregation

### Schema Evolution
Classify changes before applying:
| Change | Backward-compatible | Forward-compatible |
|--------|--------------------|--------------------|
| Add optional column | Yes | No |
| Remove column | No | Yes |
| Rename column | No | No |
| Change type (widen, e.g. int→long) | Yes | Yes |
| Change type (narrow) | No | No |

- Use schema registries (Confluent Schema Registry, AWS Glue Schema Registry) to enforce compatibility mode
- Prefer Avro/Protobuf for event streams; JSON Schema for REST payloads
- Never drop a column in production without a deprecation period + consumer audit

---

## Deep-Dive Topics

Load the companion reference for the tool or pattern in play:

- **dbt** — layered project structure, incremental models, snapshots, tests, sources, macros, exposures. See `refs/dbt.md`.
- **Orchestration and Spark** — Airflow vs Prefect selection and DAG patterns, plus PySpark partitioning, broadcast joins, UDF avoidance, and structured streaming. See `refs/orchestration-and-spark.md`.
- **Warehouse patterns and data contracts** — Snowflake clustering, materialised/dynamic tables, `COPY INTO`, MERGE, RBAC, plus schema registries, format trade-offs, and breaking vs compatible changes. See `refs/warehouse-and-contracts.md`.
- **Data quality and medallion** — Great Expectations and Soda Core checks plus the Bronze/Silver/Gold layering model. See `refs/data-quality-and-medallion.md`.

---

## Observability

### OpenLineage / Marquez

```python
from openlineage.airflow import OpenLineageListener  # Airflow integration

# Emits START/COMPLETE/FAIL events to Marquez API automatically
# Every Airflow task becomes a lineage node
# Input/output datasets tracked with schema facets
```

- Run Marquez locally: `docker-compose up` from https://github.com/MarquezProject/marquez
- Use `OPENLINEAGE_URL` env var; never hardcode the endpoint
- Decorate custom operators with `@provide_dataset_lineage` for non-standard sources

### Data Freshness SLOs

Define per table in `sources.yml` (dbt) and in Montecarlo/Bigeye alerting:
```
fct_orders:   freshness SLO = data no older than 6 hours at 8 AM UTC
dim_products: freshness SLO = data no older than 24 hours
```

### Row Count Anomaly Detection

- Baseline: rolling 28-day same-weekday average ± 2 standard deviations
- Alert on: >20% deviation from baseline
- Track in a `data_quality_metrics` table: `(table_name, run_date, row_count, expected_min, expected_max, passed)`

---

## Security

- **Column-level masking** (Snowflake): `CREATE MASKING POLICY mask_email AS (val STRING) RETURNS STRING -> CASE WHEN CURRENT_ROLE() IN ('analyst') THEN '***@***.***' ELSE val END;`
- **Row-level security**: use Snowflake row access policies or dbt `{{ config(grants=...) }}`
- **PII tagging**: tag columns in your data catalog (Collibra, Alation, dbt `meta.pii: true`). Use tags to drive masking policy assignment automatically.
- **Never log PII**: structured logging must redact email, SSN, card numbers before emission. Implement a `sanitise_record()` function called before every log write.
- **Encryption**: data at rest (AES-256), data in transit (TLS 1.2+). Enforce SSE on S3 buckets with bucket policy deny on unencrypted PUT.
- **Key rotation**: rotate warehouse service account credentials every 90 days. Store in Vault or AWS Secrets Manager — never in `.env` files committed to VCS.

---

## Related

- Reference: `refs/dbt.md` — dbt modelling, testing, and project structure
- Reference: `refs/orchestration-and-spark.md` — Airflow/Prefect and PySpark patterns
- Reference: `refs/warehouse-and-contracts.md` — warehouse patterns and data contracts
- Reference: `refs/data-quality-and-medallion.md` — data quality tooling and medallion layering
- Reference: `refs/REFERENCES.md` — documentation links for the data engineering ecosystem
