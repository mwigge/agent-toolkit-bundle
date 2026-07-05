# Debug Slow Queries

Follow this workflow to diagnose and fix slow queries. Apply the solution
hierarchy: rewrite query, add/fix index, update statistics, schema change.

## EXPLAIN Workflow

1. Run `EXPLAIN ANALYZE` (or engine equivalent) on the slow query
2. Read the plan from innermost node outward
3. Identify the highest-cost node
4. Match the node type to a known pattern (see below)
5. Apply the appropriate fix from the solution hierarchy

## Engine-Specific EXPLAIN Commands

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

## Common Plan Patterns and Fixes

| Plan Node | Meaning | Fix |
|-----------|---------|-----|
| Seq Scan / Full Table Scan | No usable index | Add index on WHERE/JOIN columns |
| Nested Loop (high rows) | O(N*M) join | Add index on inner table join column |
| Hash Join (large build) | Large hash table in memory | Reduce result set with WHERE, or increase `work_mem` |
| Sort (external) | Sort spills to disk | Add index matching ORDER BY, or increase `work_mem` |
| Bitmap Heap Scan | Index returns many rows | Consider partial index or tighter WHERE |
| Index Scan (high rows) | Index used but too many rows returned | Add more selective index or filter |

## Solution Hierarchy

Apply fixes in this order (cheapest to most expensive):

1. **Rewrite the query** — remove unnecessary joins, use EXISTS instead of IN for subqueries, avoid correlated subqueries, push filters down
2. **Add or fix an index** — composite index matching WHERE + ORDER BY, partial index, covering index
3. **Update statistics** — `ANALYZE table_name` (PostgreSQL/SQLite), `ANALYZE TABLE table_name` (MySQL)
4. **Schema change** — denormalise hot paths, add materialised views, partition large tables

## Performance Diagnostics (PostgreSQL)

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
