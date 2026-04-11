-- migration.sql — Example Alembic-style migration for a chaos platform database.
--
-- Revision: 0001_create_experiments
-- Description: Create experiments table with RLS, indexes, and JSONB config
--
-- Up migration:   run the "-- +++ UP" section
-- Down migration: run the "-- --- DOWN" section

-- +++ UP

-- Enable required extensions (idempotent)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- ---------------------------------------------------------------------------
-- experiments table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS experiments (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name           TEXT         NOT NULL CHECK (char_length(name) BETWEEN 1 AND 255),
    status         TEXT         NOT NULL
                                  CHECK (status IN ('pending','running','completed','failed','aborted'))
                                  DEFAULT 'pending',
    blast_radius   NUMERIC(4,3) NOT NULL CHECK (blast_radius BETWEEN 0 AND 1),
    config         JSONB        NOT NULL DEFAULT '{}',
    labels         TEXT[]       NOT NULL DEFAULT '{}',
    success        BOOLEAN,
    duration_ms    INTEGER      CHECK (duration_ms >= 0),
    created_by     UUID         NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    started_at     TIMESTAMPTZ,
    completed_at   TIMESTAMPTZ,
    CONSTRAINT completed_requires_success
      CHECK (
        status NOT IN ('completed','failed') OR success IS NOT NULL
      )
);

COMMENT ON TABLE experiments IS 'Chaos experiment definitions and results';
COMMENT ON COLUMN experiments.blast_radius IS 'Fraction of system affected (0.0–1.0)';
COMMENT ON COLUMN experiments.config IS 'Experiment-specific configuration as JSONB';

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

-- Primary query patterns
CREATE INDEX IF NOT EXISTS idx_experiments_status
  ON experiments (status)
  WHERE status IN ('pending', 'running');

CREATE INDEX IF NOT EXISTS idx_experiments_created_by
  ON experiments (created_by, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_experiments_created_at
  ON experiments (created_at DESC);

-- JSONB index for config queries
CREATE INDEX IF NOT EXISTS idx_experiments_config_gin
  ON experiments USING GIN (config jsonb_path_ops);

-- Partial index for label filtering
CREATE INDEX IF NOT EXISTS idx_experiments_labels_gin
  ON experiments USING GIN (labels)
  WHERE labels != '{}';

-- ---------------------------------------------------------------------------
-- Row-Level Security
-- ---------------------------------------------------------------------------

ALTER TABLE experiments ENABLE ROW LEVEL SECURITY;

-- Service role can read/write all rows
CREATE POLICY experiments_service_all
  ON experiments
  FOR ALL
  TO chaos_service_role
  USING (true)
  WITH CHECK (true);

-- Regular users can only see their own experiments
CREATE POLICY experiments_user_select
  ON experiments
  FOR SELECT
  TO chaos_user_role
  USING (created_by = current_setting('app.current_user_id')::UUID);

CREATE POLICY experiments_user_insert
  ON experiments
  FOR INSERT
  TO chaos_user_role
  WITH CHECK (created_by = current_setting('app.current_user_id')::UUID);

-- Experiments can only be updated if still pending or running
CREATE POLICY experiments_user_update
  ON experiments
  FOR UPDATE
  TO chaos_user_role
  USING (
    created_by = current_setting('app.current_user_id')::UUID
    AND status IN ('pending', 'running')
  );

-- ---------------------------------------------------------------------------
-- experiment_events audit table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS experiment_events (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id  UUID         NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    event_type     TEXT         NOT NULL,
    payload        JSONB        NOT NULL DEFAULT '{}',
    occurred_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_experiment_events_experiment_id
  ON experiment_events (experiment_id, occurred_at DESC);

-- --- DOWN

-- Drop RLS policies
DROP POLICY IF EXISTS experiments_user_update  ON experiments;
DROP POLICY IF EXISTS experiments_user_insert  ON experiments;
DROP POLICY IF EXISTS experiments_user_select  ON experiments;
DROP POLICY IF EXISTS experiments_service_all  ON experiments;

-- Drop tables (CASCADE removes dependent objects)
DROP TABLE IF EXISTS experiment_events CASCADE;
DROP TABLE IF EXISTS experiments CASCADE;
