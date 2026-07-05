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

## Deep-Dive Workflows

- **Data quality audit** — null/duplicate/orphan/range checks and remediation. See `refs/data-quality-audit.md` for the full audit checklist and portable SQL.
- **Debug slow queries** — EXPLAIN workflow, plan-pattern fixes, and the solution hierarchy. See `refs/slow-query-debugging.md`.
- **Schema inspection** — portable queries for tables, columns, indexes, foreign keys, and CHECK constraints across engines. See `refs/schema-inspection.md`.
- **Safe migrations** — expand-migrate-contract, non-locking index builds, batch backfills, and rollback rules. See `refs/migrations.md`.

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
