# Warehouse Patterns and Data Contracts

Snowflake / warehouse patterns (clustering, materialised views, loading, MERGE, RBAC) and data contract management (schema registries, formats, compatibility).

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
