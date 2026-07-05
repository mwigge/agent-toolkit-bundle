# Orchestration and Spark

Choosing between Airflow and Prefect for orchestration, and PySpark patterns for distributed processing.

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
