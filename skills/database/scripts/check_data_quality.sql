-- check_data_quality.sql — Portable data quality checks for PostgreSQL, MySQL, and SQLite.
--
-- Usage: Run each section against the target database, replacing
-- 'target_table', 'col', 'parent_table', etc. with actual names.
--
-- These queries use ANSI SQL and work across all three engines
-- unless marked with an engine-specific comment.

-- ---------------------------------------------------------------------------
-- 1. NULL ANALYSIS
--    Check null rates for all columns of interest.
--    Replace 'target_table' and 'col' with actual names.
-- ---------------------------------------------------------------------------

SELECT
    'target_table' AS table_name,
    'col' AS column_name,
    COUNT(*) AS total_rows,
    COUNT(col) AS non_null_count,
    COUNT(*) - COUNT(col) AS null_count,
    ROUND(100.0 * (COUNT(*) - COUNT(col)) / NULLIF(COUNT(*), 0), 2) AS null_pct
FROM target_table;

-- To check multiple columns at once (repeat the pattern):
-- SELECT
--     COUNT(*) AS total,
--     COUNT(*) - COUNT(col_a) AS col_a_nulls,
--     COUNT(*) - COUNT(col_b) AS col_b_nulls,
--     COUNT(*) - COUNT(col_c) AS col_c_nulls
-- FROM target_table;

-- ---------------------------------------------------------------------------
-- 2. DUPLICATE DETECTION
--    Find rows that share the same values on logical key columns.
--    Replace col_a, col_b with the columns that should be unique together.
-- ---------------------------------------------------------------------------

SELECT
    col_a,
    col_b,
    COUNT(*) AS dup_count
FROM target_table
GROUP BY col_a, col_b
HAVING COUNT(*) > 1
ORDER BY dup_count DESC
LIMIT 100;

-- To see the actual duplicate rows:
-- SELECT t.*
-- FROM target_table t
-- INNER JOIN (
--     SELECT col_a, col_b
--     FROM target_table
--     GROUP BY col_a, col_b
--     HAVING COUNT(*) > 1
-- ) dups ON t.col_a = dups.col_a AND t.col_b = dups.col_b
-- ORDER BY t.col_a, t.col_b;

-- ---------------------------------------------------------------------------
-- 3. ORPHAN DETECTION
--    Find child rows referencing non-existent parent rows.
--    Replace child_table, parent_id, parent_table, id with actual names.
-- ---------------------------------------------------------------------------

SELECT
    c.id,
    c.parent_id
FROM child_table AS c
LEFT JOIN parent_table AS p ON c.parent_id = p.id
WHERE p.id IS NULL
ORDER BY c.id
LIMIT 100;

-- ---------------------------------------------------------------------------
-- 4. RANGE VALIDATION
--    Check numeric and date columns for out-of-bounds values.
-- ---------------------------------------------------------------------------

-- Numeric range check
SELECT
    id,
    amount
FROM target_table
WHERE amount < 0 OR amount > 1000000
ORDER BY amount
LIMIT 100;

-- Date sanity check (no future dates, no ancient dates)
SELECT
    id,
    created_at
FROM target_table
WHERE
    created_at > CURRENT_TIMESTAMP
    OR created_at < '2000-01-01'
ORDER BY created_at
LIMIT 100;

-- ---------------------------------------------------------------------------
-- 5. REFERENTIAL INTEGRITY SUMMARY
--    Count orphans per FK relationship.
--    Repeat for each parent-child relationship in the schema.
-- ---------------------------------------------------------------------------

SELECT
    'child_table.parent_id -> parent_table.id' AS relationship,
    COUNT(*) AS orphan_count
FROM child_table AS c
LEFT JOIN parent_table AS p ON c.parent_id = p.id
WHERE p.id IS NULL;

-- ---------------------------------------------------------------------------
-- 6. TABLE STALENESS CHECK (PostgreSQL only)
--    Identify tables with no recent writes.
-- ---------------------------------------------------------------------------

-- PostgreSQL:
-- SELECT
--     relname AS table_name,
--     n_tup_ins AS inserts,
--     n_tup_upd AS updates,
--     n_tup_del AS deletes,
--     last_autovacuum,
--     last_autoanalyze
-- FROM pg_stat_user_tables
-- ORDER BY COALESCE(last_autovacuum, '1970-01-01') ASC;

-- MySQL:
-- SELECT
--     table_name,
--     update_time,
--     table_rows
-- FROM information_schema.tables
-- WHERE table_schema = DATABASE()
-- ORDER BY COALESCE(update_time, '1970-01-01') ASC;

-- ---------------------------------------------------------------------------
-- 7. DEDUPLICATION (when duplicates are found)
--    Keep the most recent row per logical key, delete the rest.
--    CAUTION: Test on staging first. Back up the table before running.
-- ---------------------------------------------------------------------------

-- PostgreSQL:
-- DELETE FROM target_table
-- WHERE ctid NOT IN (
--     SELECT DISTINCT ON (col_a, col_b) ctid
--     FROM target_table
--     ORDER BY col_a, col_b, created_at DESC
-- );

-- MySQL:
-- DELETE t1 FROM target_table t1
-- INNER JOIN target_table t2
--   ON t1.col_a = t2.col_a AND t1.col_b = t2.col_b
--   AND t1.created_at < t2.created_at;

-- SQLite:
-- DELETE FROM target_table
-- WHERE rowid NOT IN (
--     SELECT MAX(rowid)
--     FROM target_table
--     GROUP BY col_a, col_b
-- );
