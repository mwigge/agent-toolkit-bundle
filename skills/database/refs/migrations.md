# Safe Migrations

Follow the expand-migrate-contract pattern for zero-downtime schema changes.
See `templates/migration-runbook.md` for the full runbook template.

## Expand-Migrate-Contract Pattern

1. **Expand** — add new columns/tables alongside old ones (non-breaking)
2. **Migrate** — backfill data, deploy code that writes to both old and new
3. **Contract** — drop old columns/tables once all readers use the new schema

## Safe Patterns by Operation

**Add a column (all engines):**
```sql
-- Safe: nullable column with no default (instant in PostgreSQL 11+, MySQL 8.0+)
ALTER TABLE t ADD COLUMN new_col TEXT;

-- Then backfill in batches:
UPDATE t SET new_col = 'default_value' WHERE new_col IS NULL AND id BETWEEN $start AND $end;

-- Finally add NOT NULL constraint:
-- PostgreSQL:
ALTER TABLE t ALTER COLUMN new_col SET NOT NULL;
-- MySQL:
ALTER TABLE t MODIFY COLUMN new_col TEXT NOT NULL;
```

**Add an index without locking:**
```sql
-- PostgreSQL (non-blocking):
CREATE INDEX CONCURRENTLY idx_t_col ON t (col);

-- MySQL 8.0+ (online DDL, mostly non-blocking):
ALTER TABLE t ADD INDEX idx_t_col (col), ALGORITHM=INPLACE, LOCK=NONE;

-- SQLite (no CONCURRENTLY; but writes are serialised anyway):
CREATE INDEX idx_t_col ON t (col);
```

**Rename a column (expand-migrate-contract):**
1. Add new column
2. Deploy code writing to both columns
3. Backfill old rows
4. Deploy code reading from new column only
5. Drop old column

**Drop a column safely:**
1. Remove all code references to the column
2. Deploy and verify no errors
3. Drop the column in a migration

## Batch Backfill Pattern

```sql
-- PostgreSQL: process in chunks using ctid ranges
-- Adjust batch size based on table width and server load
DO $$
DECLARE
    batch_size INT := 5000;
    affected INT := 1;
BEGIN
    WHILE affected > 0 LOOP
        WITH batch AS (
            SELECT ctid FROM target_table
            WHERE new_col IS NULL
            LIMIT batch_size
        )
        UPDATE target_table
        SET new_col = compute_value(old_col)
        WHERE ctid IN (SELECT ctid FROM batch);

        GET DIAGNOSTICS affected = ROW_COUNT;
        COMMIT;
        PERFORM pg_sleep(0.1);  -- Throttle to reduce replication lag
    END LOOP;
END $$;
```

**MySQL batch backfill:**
```sql
-- Use a loop in application code or stored procedure
UPDATE target_table
SET new_col = compute_value(old_col)
WHERE new_col IS NULL
LIMIT 5000;
-- Repeat until 0 rows affected
```

## Rollback Rules

- Every migration must have a documented rollback procedure
- Test rollback on a staging copy before production
- Expanding migrations roll back by dropping the new column/table
- Data migrations roll back by restoring from the old column (keep it until contract phase)
- Never drop columns/tables in the same deployment that removes code references

## Migration Checklist

1. Wrap DDL in a transaction (PostgreSQL) or use `pt-online-schema-change` (MySQL large tables)
2. Run `EXPLAIN` on any new queries the migration enables
3. Verify indexes exist for new foreign keys
4. Test on a production-size dataset (not just dev)
5. Monitor replication lag during backfills
6. Have a rollback script ready and tested
