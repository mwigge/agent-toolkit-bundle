---
name: database
description: >
  Database patterns for query optimisation, schema design, table design, indexing,
  migrations, data quality auditing, and slow query debugging across PostgreSQL,
  MySQL, and SQLite. This skill should be used when writing SQL queries, designing
  schemas, creating tables, troubleshooting slow queries, running data quality
  audits, planning migrations, or inspecting database structure. For deep
  PostgreSQL table design guidance, load refs/postgresql-table-design.md.
version: 2.1.0
---

# Database Patterns

Multi-engine reference for database best practices covering PostgreSQL, MySQL,
and SQLite. For detailed review workflows, use the `database-reviewer` agent.

## When to Activate

- Writing SQL queries or migrations
- Designing database schemas
- Troubleshooting slow queries
- Implementing Row Level Security (PostgreSQL)
- Setting up connection pooling
- Auditing data quality (nulls, duplicates, orphans)
- Inspecting schema structure across engines
- Planning safe, zero-downtime migrations

---

## Quick Reference

### Index Cheat Sheet

| Query Pattern | Index Type | PostgreSQL | MySQL | SQLite |
|--------------|------------|------------|-------|--------|
| `WHERE col = value` | B-tree | `CREATE INDEX idx ON t (col)` | same | same |
| `WHERE col > value` | B-tree | same | same | same |
| `WHERE a = x AND b > y` | Composite | `CREATE INDEX idx ON t (a, b)` | same | same |
| `WHERE jsonb @> '{}'` | GIN | `USING gin (col)` | N/A (use generated columns) | N/A |
| `WHERE tsv @@ query` | GIN | `USING gin (col)` | `FULLTEXT` index | FTS5 virtual table |
| Time-series ranges | BRIN | `USING brin (col)` | partitioning | N/A |

### Data Type Quick Reference

| Use Case | PostgreSQL | MySQL | SQLite |
|----------|-----------|-------|--------|
| IDs | `bigint` | `BIGINT UNSIGNED AUTO_INCREMENT` | `INTEGER PRIMARY KEY` |
| Strings | `text` | `VARCHAR(N)` or `TEXT` | `TEXT` |
| Timestamps | `timestamptz` | `DATETIME` or `TIMESTAMP` | `TEXT` (ISO 8601) |
| Money | `numeric(10,2)` | `DECIMAL(10,2)` | `REAL` (with care) |
| Flags | `boolean` | `TINYINT(1)` or `BOOLEAN` | `INTEGER` (0/1) |
| JSON | `jsonb` | `JSON` | `TEXT` + `json_extract()` |

### Common Patterns

**Composite Index Order:**
```sql
-- Equality columns first, then range columns
CREATE INDEX idx ON orders (status, created_at);
-- Works for: WHERE status = 'pending' AND created_at > '2024-01-01'
```

**Covering Index (PostgreSQL):**
```sql
CREATE INDEX idx ON users (email) INCLUDE (name, created_at);
-- Avoids table lookup for SELECT email, name, created_at
```

**Partial Index (PostgreSQL):**
```sql
CREATE INDEX idx ON users (email) WHERE deleted_at IS NULL;
-- Smaller index, only includes active users
```

**RLS Policy (PostgreSQL, Optimized):**
```sql
CREATE POLICY policy ON orders
  USING ((SELECT auth.uid()) = user_id);  -- Wrap in SELECT!
```

**UPSERT:**
```sql
-- PostgreSQL
INSERT INTO settings (user_id, key, value)
VALUES (123, 'theme', 'dark')
ON CONFLICT (user_id, key)
DO UPDATE SET value = EXCLUDED.value;

-- MySQL
INSERT INTO settings (user_id, `key`, value)
VALUES (123, 'theme', 'dark')
ON DUPLICATE KEY UPDATE value = VALUES(value);

-- SQLite
INSERT OR REPLACE INTO settings (user_id, key, value)
VALUES (123, 'theme', 'dark');
```

**Cursor Pagination:**
```sql
SELECT * FROM products WHERE id > $last_id ORDER BY id LIMIT 20;
-- O(1) vs OFFSET which is O(n)
```

**Queue Processing (PostgreSQL):**
```sql
UPDATE jobs SET status = 'processing'
WHERE id = (
  SELECT id FROM jobs WHERE status = 'pending'
  ORDER BY created_at LIMIT 1
  FOR UPDATE SKIP LOCKED
) RETURNING *;
```

### Anti-Pattern Detection

```sql
-- Find unindexed foreign keys (PostgreSQL)
SELECT conrelid::regclass, a.attname
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE c.contype = 'f'
  AND NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indrelid = c.conrelid AND a.attnum = ANY(i.indkey)
  );

-- Find slow queries (PostgreSQL — requires pg_stat_statements)
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
WHERE mean_exec_time > 100
ORDER BY mean_exec_time DESC;

-- Check table bloat (PostgreSQL)
SELECT relname, n_dead_tup, last_vacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

### Configuration Template (PostgreSQL)

```sql
-- Connection limits (adjust for RAM)
ALTER SYSTEM SET max_connections = 100;
ALTER SYSTEM SET work_mem = '8MB';

-- Timeouts
ALTER SYSTEM SET idle_in_transaction_session_timeout = '30s';
ALTER SYSTEM SET statement_timeout = '30s';

-- Monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Security defaults
REVOKE ALL ON SCHEMA public FROM public;

SELECT pg_reload_conf();
```

---

## Data Quality Audit

Audit databases for nulls, duplicates, orphaned rows, and invalid ranges.
Produce a structured findings report. See `templates/data-quality-report.md`
and `scripts/check_data_quality.sql` for reusable artefacts.

### Audit Checklist

1. **Null analysis** — identify columns with unexpected NULL rates
2. **Duplicate detection** — find rows that violate logical uniqueness
3. **Orphan detection** — find rows referencing non-existent parents
4. **Range validation** — check numeric/date columns for out-of-bounds values
5. **Referential integrity** — verify all FK relationships hold
6. **Staleness check** — flag tables with no recent inserts/updates

### Null Analysis

```sql
-- PostgreSQL / MySQL / SQLite (portable)
SELECT
    COUNT(*) AS total_rows,
    COUNT(col) AS non_null,
    COUNT(*) - COUNT(col) AS null_count,
    ROUND(100.0 * (COUNT(*) - COUNT(col)) / NULLIF(COUNT(*), 0), 2) AS null_pct
FROM target_table;
```

### Duplicate Detection

```sql
-- Find duplicates on logical key columns
SELECT col_a, col_b, COUNT(*) AS dup_count
FROM target_table
GROUP BY col_a, col_b
HAVING COUNT(*) > 1
ORDER BY dup_count DESC;
```

### Orphan Detection

```sql
-- Find child rows with no matching parent
SELECT c.id, c.parent_id
FROM child_table c
LEFT JOIN parent_table p ON c.parent_id = p.id
WHERE p.id IS NULL;
```

### Range Validation

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

### Remediation Patterns

- **Nulls**: add `NOT NULL` constraint after backfilling defaults
- **Duplicates**: deduplicate with ROW_NUMBER window, keep latest
- **Orphans**: delete orphans OR add missing FK constraint with `ON DELETE CASCADE`/`SET NULL`
- **Invalid ranges**: add CHECK constraints after fixing data

---

## Debug Slow Queries

Follow this workflow to diagnose and fix slow queries. Apply the solution
hierarchy: rewrite query, add/fix index, update statistics, schema change.

### EXPLAIN Workflow

1. Run `EXPLAIN ANALYZE` (or engine equivalent) on the slow query
2. Read the plan from innermost node outward
3. Identify the highest-cost node
4. Match the node type to a known pattern (see below)
5. Apply the appropriate fix from the solution hierarchy

### Engine-Specific EXPLAIN Commands

**PostgreSQL:**
```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT ...;
-- Add VERBOSE for output column detail
-- Add SETTINGS to see non-default planner settings
```

**MySQL:**
```sql
EXPLAIN FORMAT=JSON SELECT ...;
EXPLAIN ANALYZE SELECT ...;  -- MySQL 8.0.18+
-- Check key_len, rows, filtered columns
```

**SQLite:**
```sql
EXPLAIN QUERY PLAN SELECT ...;
-- Look for SCAN (bad) vs SEARCH (good) vs COVERING INDEX
```

### Common Plan Patterns and Fixes

| Plan Node | Meaning | Fix |
|-----------|---------|-----|
| Seq Scan / Full Table Scan | No usable index | Add index on WHERE/JOIN columns |
| Nested Loop (high rows) | O(N*M) join | Add index on inner table join column |
| Hash Join (large build) | Large hash table in memory | Reduce result set with WHERE, or increase `work_mem` |
| Sort (external) | Sort spills to disk | Add index matching ORDER BY, or increase `work_mem` |
| Bitmap Heap Scan | Index returns many rows | Consider partial index or tighter WHERE |
| Index Scan (high rows) | Index used but too many rows returned | Add more selective index or filter |

### Solution Hierarchy

Apply fixes in this order (cheapest to most expensive):

1. **Rewrite the query** — remove unnecessary joins, use EXISTS instead of IN for subqueries, avoid correlated subqueries, push filters down
2. **Add or fix an index** — composite index matching WHERE + ORDER BY, partial index, covering index
3. **Update statistics** — `ANALYZE table_name` (PostgreSQL/SQLite), `ANALYZE TABLE table_name` (MySQL)
4. **Schema change** — denormalise hot paths, add materialised views, partition large tables

### Performance Diagnostics (PostgreSQL)

```sql
-- Top queries by total time
SELECT query, total_exec_time, calls, mean_exec_time
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;

-- Unused indexes (candidates for removal)
SELECT schemaname, relname, indexrelname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;

-- Cache hit ratio (should be > 99%)
SELECT
    SUM(heap_blks_hit) * 100.0 / NULLIF(SUM(heap_blks_hit) + SUM(heap_blks_read), 0)
    AS cache_hit_pct
FROM pg_statio_user_tables;
```

---

## Schema Inspection

Portable queries to inspect tables, columns, indexes, constraints, and
foreign key relationships across engines.

### List Tables

**PostgreSQL:**
```sql
SELECT table_name, pg_size_pretty(pg_total_relation_size(quote_ident(table_name)))
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
ORDER BY table_name;
```

**MySQL:**
```sql
SELECT table_name, table_rows, ROUND(data_length / 1024 / 1024, 2) AS size_mb
FROM information_schema.tables
WHERE table_schema = DATABASE()
ORDER BY table_name;
```

**SQLite:**
```sql
SELECT name FROM sqlite_master
WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
ORDER BY name;
```

### List Columns

**PostgreSQL / MySQL (ANSI):**
```sql
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'target_table'
ORDER BY ordinal_position;
```

**SQLite:**
```sql
PRAGMA table_info('target_table');
```

### List Indexes

**PostgreSQL:**
```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'target_table'
ORDER BY indexname;
```

**MySQL:**
```sql
SHOW INDEX FROM target_table;
```

**SQLite:**
```sql
PRAGMA index_list('target_table');
-- Then for each index:
PRAGMA index_info('index_name');
```

### List Foreign Keys

**PostgreSQL:**
```sql
SELECT
    tc.constraint_name,
    kcu.column_name,
    ccu.table_name AS referenced_table,
    ccu.column_name AS referenced_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu
    ON tc.constraint_name = ccu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_name = 'target_table';
```

**MySQL:**
```sql
SELECT
    constraint_name,
    column_name,
    referenced_table_name,
    referenced_column_name
FROM information_schema.key_column_usage
WHERE table_schema = DATABASE()
  AND table_name = 'target_table'
  AND referenced_table_name IS NOT NULL;
```

**SQLite:**
```sql
PRAGMA foreign_key_list('target_table');
```

### List CHECK Constraints (PostgreSQL)

```sql
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'target_table'::regclass
  AND contype = 'c';
```

---

## Safe Migrations

Follow the expand-migrate-contract pattern for zero-downtime schema changes.
See `templates/migration-runbook.md` for the full runbook template.

### Expand-Migrate-Contract Pattern

1. **Expand** — add new columns/tables alongside old ones (non-breaking)
2. **Migrate** — backfill data, deploy code that writes to both old and new
3. **Contract** — drop old columns/tables once all readers use the new schema

### Safe Patterns by Operation

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

### Batch Backfill Pattern

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

### Rollback Rules

- Every migration must have a documented rollback procedure
- Test rollback on a staging copy before production
- Expanding migrations roll back by dropping the new column/table
- Data migrations roll back by restoring from the old column (keep it until contract phase)
- Never drop columns/tables in the same deployment that removes code references

### Migration Checklist

1. Wrap DDL in a transaction (PostgreSQL) or use `pt-online-schema-change` (MySQL large tables)
2. Run `EXPLAIN` on any new queries the migration enables
3. Verify indexes exist for new foreign keys
4. Test on a production-size dataset (not just dev)
5. Monitor replication lag during backfills
6. Have a rollback script ready and tested

---

## Related

- Agent: `database-reviewer` — Full database review workflow
- Skill: `clickhouse-io` — ClickHouse analytics patterns
- Skill: `backend-patterns` — API and backend patterns
- Reference: `refs/REFERENCES.md` — documentation links for all engines
- Template: `templates/migration-runbook.md` — migration runbook
- Template: `templates/data-quality-report.md` — audit findings report
- Script: `scripts/check_data_quality.sql` — portable data quality checks
- Script: `scripts/sql_check.py` — static analysis for SQL files

---

*PostgreSQL patterns based on [Supabase Agent Skills](https://github.com/supabase/agent-skills) (MIT License)*
