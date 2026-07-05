# Data Quality Audit

Audit databases for nulls, duplicates, orphaned rows, and invalid ranges.
Produce a structured findings report. See `templates/data-quality-report.md`
and `scripts/check_data_quality.sql` for reusable artefacts.

## Audit Checklist

1. **Null analysis** — identify columns with unexpected NULL rates
2. **Duplicate detection** — find rows that violate logical uniqueness
3. **Orphan detection** — find rows referencing non-existent parents
4. **Range validation** — check numeric/date columns for out-of-bounds values
5. **Referential integrity** — verify all FK relationships hold
6. **Staleness check** — flag tables with no recent inserts/updates

## Null Analysis

```sql
-- PostgreSQL / MySQL / SQLite (portable)
SELECT
    COUNT(*) AS total_rows,
    COUNT(col) AS non_null,
    COUNT(*) - COUNT(col) AS null_count,
    ROUND(100.0 * (COUNT(*) - COUNT(col)) / NULLIF(COUNT(*), 0), 2) AS null_pct
FROM target_table;
```

## Duplicate Detection

```sql
-- Find duplicates on logical key columns
SELECT col_a, col_b, COUNT(*) AS dup_count
FROM target_table
GROUP BY col_a, col_b
HAVING COUNT(*) > 1
ORDER BY dup_count DESC;
```

## Orphan Detection

```sql
-- Find child rows with no matching parent
SELECT c.id, c.parent_id
FROM child_table c
LEFT JOIN parent_table p ON c.parent_id = p.id
WHERE p.id IS NULL;
```

## Range Validation

```sql
-- Find values outside expected bounds
SELECT id, amount
FROM orders
WHERE amount < 0 OR amount > 1000000;

-- Date sanity check
SELECT id, created_at
FROM events
WHERE created_at > CURRENT_TIMESTAMP
   OR created_at < '2000-01-01';
```

## Remediation Patterns

- **Nulls**: add `NOT NULL` constraint after backfilling defaults
- **Duplicates**: deduplicate with ROW_NUMBER window, keep latest
- **Orphans**: delete orphans OR add missing FK constraint with `ON DELETE CASCADE`/`SET NULL`
- **Invalid ranges**: add CHECK constraints after fixing data
