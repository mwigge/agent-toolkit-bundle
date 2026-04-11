# Database Patterns — Reference Links

## PostgreSQL

### Core Documentation
- https://www.postgresql.org/docs/16/index.html — PostgreSQL 16 official documentation
- https://www.postgresql.org/docs/16/sql.html — SQL command reference: all DDL and DML statements
- https://www.postgresql.org/docs/16/datatype.html — Data types: UUID, JSONB, timestamptz, arrays, ranges, enum

### Query Optimisation
- https://www.postgresql.org/docs/16/using-explain.html — EXPLAIN and EXPLAIN ANALYZE: reading query plans
- https://www.postgresql.org/docs/16/sql-explain.html — EXPLAIN syntax and all options (BUFFERS, FORMAT JSON, ANALYZE)
- https://use-the-index-luke.com/ — Use The Index, Luke: practical SQL indexing guide (B-tree, partial, composite)
- https://pganalyze.com/blog/5mins-postgres — 5 minutes of Postgres performance tips

### Monitoring & Observability
- https://www.postgresql.org/docs/16/pgstatstatements.html — pg_stat_statements: track query execution statistics
- https://www.postgresql.org/docs/16/monitoring-stats.html — pg_stat_activity, pg_stat_user_tables, pg_locks views

### Extensions
- https://github.com/pgvector/pgvector — pgvector: vector similarity search extension
- https://www.postgresql.org/docs/16/pgcrypto.html — pgcrypto: cryptographic functions (gen_random_uuid, crypt)

### Migrations
- https://alembic.sqlalchemy.org/en/latest/ — Alembic: SQLAlchemy migration tool for schema versioning
- https://alembic.sqlalchemy.org/en/latest/ops.html — Alembic operations reference: op.create_table, op.add_column, etc.

### Security
- https://www.postgresql.org/docs/16/ddl-rowsecurity.html — Row-Level Security (RLS): policies, ENABLE ROW LEVEL SECURITY
- https://www.postgresql.org/docs/16/sql-grant.html — GRANT: fine-grained privilege control

## MySQL

### Core Documentation
- https://dev.mysql.com/doc/refman/8.0/en/ — MySQL 8.0 reference manual
- https://dev.mysql.com/doc/refman/8.0/en/data-types.html — MySQL data types reference
- https://dev.mysql.com/doc/refman/8.0/en/sql-statements.html — SQL statement syntax

### Query Optimisation
- https://dev.mysql.com/doc/refman/8.0/en/explain.html — EXPLAIN output format and interpretation
- https://dev.mysql.com/doc/refman/8.0/en/explain-output.html — Understanding EXPLAIN output columns
- https://dev.mysql.com/doc/refman/8.0/en/optimization.html — Query optimisation overview

### Monitoring
- https://dev.mysql.com/doc/refman/8.0/en/performance-schema.html — Performance Schema reference
- https://dev.mysql.com/doc/refman/8.0/en/slow-query-log.html — Slow query log configuration

### Migrations
- https://dev.mysql.com/doc/refman/8.0/en/innodb-online-ddl.html — Online DDL (ALGORITHM, LOCK options)
- https://docs.percona.com/percona-toolkit/pt-online-schema-change.html — pt-online-schema-change for large table alterations

## SQLite

### Core Documentation
- https://www.sqlite.org/lang.html — SQLite SQL language reference
- https://www.sqlite.org/datatype3.html — SQLite type affinity and storage classes
- https://www.sqlite.org/pragma.html — PRAGMA statements for configuration and introspection

### Query Optimisation
- https://www.sqlite.org/eqp.html — EXPLAIN QUERY PLAN: interpreting scan vs search
- https://www.sqlite.org/optoverview.html — Query planner overview
- https://www.sqlite.org/queryplanner-ng.html — Next-generation query planner

### Full-Text Search
- https://www.sqlite.org/fts5.html — FTS5 full-text search extension

## Cross-Engine Resources

### Migration Best Practices
- https://blog.pragmaticengineer.com/zero-downtime-deployments/ — Zero-downtime deployment patterns
- https://stripe.com/blog/online-migrations — Stripe: online migrations at scale
- https://github.com/ankane/strong_migrations — strong_migrations: catch unsafe migrations (Ruby, but patterns are universal)

### Data Quality
- https://www.oreilly.com/library/view/data-quality-fundamentals/9781098112035/ — Data Quality Fundamentals (O'Reilly)

### Indexing
- https://use-the-index-luke.com/ — Use The Index, Luke: universal SQL indexing guide
