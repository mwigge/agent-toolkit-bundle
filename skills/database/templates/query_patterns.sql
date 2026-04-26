-- query_patterns.sql — PostgreSQL query pattern reference.
--
-- Patterns covered:
--   1. Parameterised query (Python psycopg style)
--   2. CTE with EXPLAIN hint
--   3. Window function
--   4. UPSERT (INSERT ... ON CONFLICT)
--   5. Row-level security context setting
--   6. Partial index usage
--   7. JSONB query
--   8. Pagination with keyset (cursor-based)
--   9. Aggregate with FILTER
--  10. Advisory locks

-- ---------------------------------------------------------------------------
-- 1. Parameterised Queries
--    Always use %s placeholders (psycopg2/psycopg3), never f-strings or %
-- ---------------------------------------------------------------------------

-- Python usage:
--   cursor.execute(
--       "SELECT id, name, status FROM experiments WHERE id = %s AND status = %s",
--       (experiment_id, status),
--   )

SELECT id, name, status, duration_ms
FROM experiments
WHERE id = $1            -- PostgreSQL native param; psycopg uses %s
  AND created_by = $2;


-- ---------------------------------------------------------------------------
-- 2. CTE with readable structure
-- ---------------------------------------------------------------------------

WITH recent_experiments AS (
    SELECT
        id,
        name,
        status,
        success,
        blast_radius,
        duration_ms,
        created_at
    FROM experiments
    WHERE created_at >= now() - INTERVAL '7 days'
      AND status = 'completed'
),
scored AS (
    SELECT
        id,
        name,
        success,
        blast_radius,
        duration_ms,
        CASE
            WHEN success THEN (1.0 + blast_radius) * 100
            ELSE 0
        END AS weighted_score
    FROM recent_experiments
)
SELECT
    id,
    name,
    weighted_score,
    ROUND(weighted_score::NUMERIC, 2) AS rounded_score
FROM scored
ORDER BY weighted_score DESC
LIMIT 20;

-- To analyse: prepend EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)


-- ---------------------------------------------------------------------------
-- 3. Window Functions — running totals, ranking, lag/lead
-- ---------------------------------------------------------------------------

SELECT
    id,
    name,
    created_at,
    success,
    duration_ms,

    -- Rank within status group
    RANK() OVER (
        PARTITION BY status
        ORDER BY created_at DESC
    ) AS rank_in_status,

    -- Running success rate over time
    AVG(success::INT) OVER (
        ORDER BY created_at
        ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
    ) AS rolling_10_success_rate,

    -- Previous experiment duration for comparison
    LAG(duration_ms) OVER (
        PARTITION BY name
        ORDER BY created_at
    ) AS prev_duration_ms,

    -- Percent change vs previous run
    CASE
        WHEN LAG(duration_ms) OVER (PARTITION BY name ORDER BY created_at) IS NULL THEN NULL
        ELSE ROUND(
            (duration_ms - LAG(duration_ms) OVER (PARTITION BY name ORDER BY created_at))
            * 100.0
            / NULLIF(LAG(duration_ms) OVER (PARTITION BY name ORDER BY created_at), 0),
            1
        )
    END AS duration_pct_change

FROM experiments
WHERE status = 'completed'
ORDER BY created_at DESC;


-- ---------------------------------------------------------------------------
-- 4. UPSERT — INSERT ... ON CONFLICT DO UPDATE
-- ---------------------------------------------------------------------------

INSERT INTO experiments (id, name, status, blast_radius, created_by, config)
VALUES (
    $1,                       -- id (UUID)
    $2,                       -- name
    'pending',
    $3,                       -- blast_radius
    $4,                       -- created_by
    $5::jsonb                 -- config
)
ON CONFLICT (id) DO UPDATE
    SET
        name         = EXCLUDED.name,
        config       = EXCLUDED.config,
        blast_radius = EXCLUDED.blast_radius
    WHERE experiments.status = 'pending'  -- Only update if still pending
RETURNING id, created_at;


-- ---------------------------------------------------------------------------
-- 5. Row-Level Security — set app context for RLS policies
-- ---------------------------------------------------------------------------

-- Set before executing queries in a session/transaction:
SET LOCAL app.current_user_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';

-- Verify RLS is active:
SELECT current_setting('app.current_user_id');

-- In a transaction block (Python):
-- cursor.execute("SET LOCAL app.current_user_id = %s", (user_id,))
-- cursor.execute("SELECT * FROM experiments")  -- RLS filters automatically


-- ---------------------------------------------------------------------------
-- 6. Partial Index Usage — index only active experiments
-- ---------------------------------------------------------------------------

-- The partial index (from migration.sql):
-- CREATE INDEX idx_experiments_status ON experiments (status)
--   WHERE status IN ('pending', 'running');

-- This query will use the partial index:
SELECT id, name, started_at
FROM experiments
WHERE status = 'running'
ORDER BY started_at ASC
LIMIT 50;

-- Verify with: EXPLAIN (ANALYZE, BUFFERS) SELECT ...
-- Look for "Index Scan using idx_experiments_status"


-- ---------------------------------------------------------------------------
-- 7. JSONB Queries
-- ---------------------------------------------------------------------------

-- Select experiments with a specific config key
SELECT id, name, config->'timeout_ms' AS timeout
FROM experiments
WHERE config @> '{"fault_type": "latency"}';

-- JSON path query (PostgreSQL 12+)
SELECT id, name
FROM experiments
WHERE jsonb_path_exists(config, '$.targets[*] ? (@ == "payments-service")');

-- Extract nested value safely (no error if path missing)
SELECT
    id,
    config #>> '{database, host}' AS db_host,
    (config -> 'retries')::INT      AS retries
FROM experiments
WHERE config ? 'database';


-- ---------------------------------------------------------------------------
-- 8. Keyset Pagination (cursor-based) — more efficient than OFFSET
-- ---------------------------------------------------------------------------

-- First page (no cursor):
SELECT id, name, created_at
FROM experiments
WHERE status = 'completed'
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- Next page (pass last row's created_at and id as cursor):
SELECT id, name, created_at
FROM experiments
WHERE status = 'completed'
  AND (created_at, id) < ($1, $2)  -- cursor values from previous page
ORDER BY created_at DESC, id DESC
LIMIT 20;


-- ---------------------------------------------------------------------------
-- 9. Aggregate with FILTER — conditional aggregation
-- ---------------------------------------------------------------------------

SELECT
    DATE_TRUNC('day', created_at) AS day,
    COUNT(*)                      AS total,
    COUNT(*) FILTER (WHERE success = true)          AS passed,
    COUNT(*) FILTER (WHERE success = false)         AS failed,
    COUNT(*) FILTER (WHERE status = 'aborted')      AS aborted,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE success = true)
        / NULLIF(COUNT(*) FILTER (WHERE status = 'completed'), 0),
        1
    )                             AS success_pct
FROM experiments
WHERE created_at >= now() - INTERVAL '30 days'
GROUP BY DATE_TRUNC('day', created_at)
ORDER BY day DESC;


-- ---------------------------------------------------------------------------
-- 10. Advisory Locks — coordinate across connections without table locks
-- ---------------------------------------------------------------------------

-- Try lock (non-blocking) — returns true if acquired
SELECT pg_try_advisory_xact_lock(hashtext($1))  -- $1 = experiment_id string
  AS lock_acquired;

-- Usage pattern in Python:
-- cursor.execute("SELECT pg_try_advisory_xact_lock(hashtext(%s))", (experiment_id,))
-- row = cursor.fetchone()
-- if not row['lock_acquired']:
--     raise ConcurrencyError("Another process is running this experiment")
