# dbt

Layered dbt project structure, incremental models, snapshots, tests, sources, macros, and exposures.

## Layer Architecture

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

## Incremental Models

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

## Snapshots

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

## Tests

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

## sources.yml

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

## Macros

```sql
-- macros/cents_to_dollars.sql
{% macro cents_to_dollars(column_name) %}
  ({{ column_name }} / 100.0)::numeric(18,2)
{% endmacro %}
```

- Macros live in `macros/`. Use for repeated expressions, not for hiding complexity.
- Document macros in `macros/schema.yml` with `arguments:` descriptions.
- Avoid Jinja logic in models; move it to macros.

## exposures.yml

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
