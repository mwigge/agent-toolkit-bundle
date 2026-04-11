---
name: data-engineer
description: Data pipeline patterns: dbt, Airflow, Spark, data quality checks, and warehouse modeling. Use when designing or reviewing ETL, data warehouses, or streaming pipelines.
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

## dbt

### Layer Architecture

```
models/
  staging/        # 1:1 with source tables; rename, cast, light cleaning only
  intermediate/   # business logic, joins, derived columns; not exposed to BI
  marts/          # business-ready, wide tables; consumed by BI / data products
    core/
    finance/
    marketing/
```

**Staging models**: one file per source table, named `stg_{source}__{table}.sql`. Always `SELECT *` from `{{ source() }}`, never from raw table name. Cast all columns to correct types here.

**Intermediate models**: prefix `int_`. Join staging models. Apply business rules. Keep reusable logic here rather than duplicating in marts.

**Mart models**: prefix `dim_` / `fct_`. Wide, denormalised, consumer-friendly. Joins should be cheap (surrogate keys already resolved upstream).

### Incremental Models

```sql
{{
  config(
    materialized='incremental',
    unique_key='event_id',
    incremental_strategy='merge',
    on_schema_change='append_new_columns'
  )
}}

SELECT ...
FROM {{ ref('stg_events') }}

{% if is_incremental() %}
  WHERE event_timestamp > (SELECT MAX(event_timestamp) FROM {{ this }})
{% endif %}
```

- Always specify `unique_key` with `merge` strategy
- Use `on_schema_change='append_new_columns'` as the safe default; never `'ignore'`
- For Snowflake: prefer `merge`; for BigQuery: prefer `insert_overwrite` with partition
- Add a `--full-refresh` runbook step when backfill is needed

### Snapshots

Use dbt snapshots for slowly-changing dimensions (SCD Type 2):

```sql
{% snapshot orders_snapshot %}
{{
  config(
    target_schema='snapshots',
    unique_key='order_id',
    strategy='timestamp',
    updated_at='updated_at',
  )
}}
SELECT * FROM {{ source('raw', 'orders') }}
{% endsnapshot %}
```

- `strategy='timestamp'` preferred over `'check'` — more reliable
- Never snapshot tables without an `updated_at` column; add it upstream

### Tests

**Built-in tests** (`schema.yml`):
```yaml
columns:
  - name: user_id
    tests:
      - not_null
      - unique
  - name: status
    tests:
      - accepted_values:
          values: ['active', 'inactive', 'pending']
  - name: account_id
    tests:
      - relationships:
          to: ref('dim_accounts')
          field: account_id
```

**Custom generic tests**: define in `tests/generic/`. Accept `model` and `column_name` as arguments.

**Singular tests**: SQL files in `tests/` that return rows on failure. Use for complex business rules.

Run only modified + downstream: `dbt test --select state:modified+`

### sources.yml

```yaml
sources:
  - name: raw_crm
    database: raw
    schema: crm
    freshness:
      warn_after: {count: 6, period: hour}
      error_after: {count: 24, period: hour}
    loaded_at_field: _loaded_at
    tables:
      - name: contacts
        description: "Raw CRM contacts from Salesforce"
        columns:
          - name: id
            tests: [not_null, unique]
```

Always define `freshness` on sources consumed by time-sensitive marts.

### Macros

```sql
-- macros/cents_to_dollars.sql
{% macro cents_to_dollars(column_name) %}
  ({{ column_name }} / 100.0)::numeric(18,2)
{% endmacro %}
```

- Macros live in `macros/`. Use for repeated expressions, not for hiding complexity.
- Document macros in `macros/schema.yml` with `arguments:` descriptions.
- Avoid Jinja logic in models; move it to macros.

### exposures.yml

```yaml
exposures:
  - name: revenue_dashboard
    type: dashboard
    maturity: high
    url: https://bi.example.com/dashboards/revenue
    description: "Executive revenue KPI dashboard"
    depends_on:
      - ref('fct_revenue')
      - ref('dim_customers')
    owner:
      name: Data Team
      email: data@example.com
```

Define exposures for every downstream consumer (BI tool, ML model, API). This enables impact analysis before schema changes.

---

## Airflow vs Prefect

### Airflow

**When to use**: mature, complex DAGs; Kubernetes Executor; existing Airflow infrastructure; RBAC requirements.

**DAG design**:
```python
# Use TaskFlow API (@task) for Python tasks — cleaner than PythonOperator
# Explicit task dependencies via >> operator
# Set dag_id to match filename
# Never use Variable.get() at import time — it queries the DB on every scheduler heartbeat
```

**Key settings**:
```python
default_args = {
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "max_retry_delay": timedelta(minutes=60),
    "on_failure_callback": alert_on_failure,
    "sla": timedelta(hours=2),
}
```

**Sensor patterns**:
- `ExternalTaskSensor`: wait for another DAG's task to complete
- `S3KeySensor` / `GCSObjectExistenceSensor`: wait for file arrival
- Set `poke_interval` and `timeout` — never leave sensors with default `timeout=604800`
- Prefer `mode='reschedule'` over `mode='poke'` to free worker slots

**Backfill**: `airflow dags backfill --start-date 2026-01-01 --end-date 2026-03-31 my_dag`
- Test with `--dry-run` first
- Disable sensors for historical backfill runs via `run_id` check

### Prefect

**When to use**: greenfield; Python-first teams; dynamic task mapping; simpler deployment model.

```python
from prefect import flow, task
from prefect.tasks import task_input_hash
from datetime import timedelta

@task(cache_key_fn=task_input_hash, cache_expiration=timedelta(hours=1), retries=3)
def extract(source: str) -> list[dict]: ...

@flow(name="etl-pipeline", log_prints=False)  # log_prints=False: avoid PII in logs
def etl_pipeline(date: str) -> None:
    data = extract(source="crm")
    ...
```

**Dynamic task mapping**:
```python
results = process_record.map(records)  # spawns one task per record
```

**Deployment**: use `prefect.yaml` with `work_pool` and `schedule`. Prefer `CronSchedule` over interval for predictability.

---

## Spark (PySpark)

### DataFrames over RDDs

Always use DataFrames. RDDs bypass the Catalyst optimizer — use only when DataFrame API genuinely cannot express the transformation (extremely rare).

### Partitioning

```python
# Read: set partition count to 2-4x number of cores
df = spark.read.parquet("s3://bucket/path/")

# Repartition before a wide shuffle (join, groupBy)
df = df.repartition(200, "customer_id")  # hash-partition on join key

# Coalesce before write to reduce small files
df.coalesce(10).write.parquet("s3://bucket/output/")

# Avoid: repartition(1) — creates a single file, kills parallelism
```

**Partition pruning**: always filter on the partition column early. The optimizer will prune files automatically.

### Broadcast Joins

```python
from pyspark.sql.functions import broadcast

# When one side is small (< spark.sql.autoBroadcastJoinThreshold, default 10MB)
result = large_df.join(broadcast(small_df), "key")

# For larger dims: increase threshold or force broadcast explicitly
spark.conf.set("spark.sql.autoBroadcastJoinThreshold", 50 * 1024 * 1024)  # 50MB
```

### Avoid UDFs

UDFs serialize rows to Python, bypassing vectorised execution:
- Prefer built-in `pyspark.sql.functions` — always check the API first
- If UDF is unavoidable, use **Pandas UDF** (`@pandas_udf`) for vectorised execution
- Never use Python UDFs in hot paths processing billions of rows

### Structured Streaming

```python
stream = (
    spark.readStream
    .format("kafka")
    .option("kafka.bootstrap.servers", "broker:9092")
    .option("subscribe", "events")
    .load()
)

query = (
    stream
    .withWatermark("event_time", "2 hours")
    .groupBy(window("event_time", "1 hour"), "user_id")
    .agg(count("*").alias("event_count"))
    .writeStream
    .format("delta")
    .outputMode("append")
    .option("checkpointLocation", "s3://bucket/checkpoints/events/")
    .trigger(processingTime="1 minute")
    .start()
)
```

- Always set `checkpointLocation` — this is how exactly-once is achieved
- Use `outputMode("append")` with watermarks; `"complete"` keeps full state in memory

---

## Snowflake / Warehouse Patterns

### Clustering Keys

```sql
ALTER TABLE fct_events CLUSTER BY (TO_DATE(event_timestamp), event_type);
```

- Use on large tables (>1TB) queried with range filters on dates
- Maximum 3-4 columns; more columns = diminishing returns + higher cost
- Monitor with `SYSTEM$CLUSTERING_INFORMATION('fct_events')`

### Materialised Views

```sql
CREATE OR REPLACE MATERIALIZED VIEW mv_daily_revenue AS
SELECT DATE_TRUNC('day', order_date) AS day, SUM(amount) AS revenue
FROM fct_orders
GROUP BY 1;
```

- Automatically maintained by Snowflake; no manual refresh
- Cannot contain: `JOIN`, subqueries, window functions, `LIMIT` (as of 2024)
- Use **Dynamic Tables** instead for complex transformations:

```sql
CREATE OR REPLACE DYNAMIC TABLE dt_customer_summary
  TARGET_LAG = '1 hour'
  WAREHOUSE = transform_wh
AS SELECT customer_id, COUNT(*) AS order_count FROM fct_orders GROUP BY 1;
```

### COPY INTO

```sql
COPY INTO raw.events
FROM @my_s3_stage/events/
FILE_FORMAT = (TYPE = PARQUET)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
PURGE = FALSE  -- keep source files; set TRUE only after validation
ON_ERROR = 'SKIP_FILE';
```

- Always specify `FILE_FORMAT` explicitly
- Use `VALIDATION_MODE = 'RETURN_ERRORS'` to dry-run before production load
- Monitor load history: `SELECT * FROM information_schema.load_history WHERE table_name = 'EVENTS'`

### MERGE Pattern

```sql
MERGE INTO target t
USING (SELECT * FROM staging QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1) s
ON t.id = s.id
WHEN MATCHED AND s.updated_at > t.updated_at THEN UPDATE SET ...
WHEN NOT MATCHED THEN INSERT ...;
```

Always deduplicate the source before merging. A MERGE with duplicate keys in source throws an error.

### RBAC

```sql
-- Principle of least privilege
GRANT USAGE ON DATABASE analytics TO ROLE analyst;
GRANT USAGE ON SCHEMA analytics.marts TO ROLE analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics.marts TO ROLE analyst;
-- Never GRANT ACCOUNTADMIN to service accounts
-- Never use SYSADMIN for application reads
```

---

## Data Contracts

### Schema Registry

- Confluent Schema Registry (Kafka ecosystems): subjects keyed by `{topic}-value`
- AWS Glue Schema Registry: for Kinesis + Glue ETL
- Compatibility modes: `BACKWARD` (default), `FORWARD`, `FULL`, `NONE`
- Set `BACKWARD_TRANSITIVE` or `FULL_TRANSITIVE` for schemas shared across many consumers

### Avro / Protobuf / JSON Schema

| Format | Best for | Schema evolution | Human-readable |
|--------|----------|-----------------|----------------|
| Avro | Kafka, Hadoop | Excellent | No (binary) |
| Protobuf | gRPC, high-throughput | Excellent | No (binary) |
| JSON Schema | REST APIs, webhooks | Good | Yes |

### Breaking vs Compatible Changes

**Breaking** (require consumer migration + major version bump):
- Remove or rename a field
- Change field type incompatibly
- Change field from optional to required

**Compatible** (safe to deploy without consumer changes):
- Add optional field with default
- Add new enum value (forward-compatible only)
- Widen numeric type (int → long)

---

## Data Quality

### Great Expectations

```python
import great_expectations as gx

context = gx.get_context()
suite = context.add_expectation_suite("orders.critical")

validator = context.get_validator(
    datasource_name="snowflake_datasource",
    data_asset_name="fct_orders",
    expectation_suite_name="orders.critical",
)

validator.expect_column_values_to_not_be_null("order_id")
validator.expect_column_values_to_be_unique("order_id")
validator.expect_column_values_to_be_between("amount_cents", min_value=0, max_value=10_000_000)
validator.expect_table_row_count_to_be_between(min_value=1000, max_value=None)
validator.save_expectation_suite()
```

**Checkpoints**: run suites against new data batches. Integrate into Airflow/Prefect as a task before downstream consumers run.

### Soda Core

```yaml
# checks.yml
checks for fct_orders:
  - row_count > 0
  - missing_count(order_id) = 0
  - duplicate_count(order_id) = 0
  - freshness(created_at) < 6h
  - schema:
      fail:
        when required column missing: [order_id, customer_id, amount_cents]
```

```bash
soda scan -d snowflake -c soda_config.yml checks.yml
```

---

## Medallion Architecture

```
Bronze (raw)      — exact copy of source; append-only; never modify
Silver (cleaned)  — typed, deduplicated, standardised; validated schema
Gold (business)   — aggregated, enriched, business-ready; SLA-backed
```

**Rules**:
- Bronze writes must never fail silently — dead-letter all malformed records
- Silver applies no business logic; only cleansing and typing
- Gold models may join across Silver; never read from Bronze directly
- Each layer has its own database/schema; access is role-gated

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
