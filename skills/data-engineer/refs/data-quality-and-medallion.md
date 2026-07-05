# Data Quality and Medallion Architecture

Data-quality tooling (Great Expectations, Soda Core) and the Bronze/Silver/Gold medallion layering model.

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
