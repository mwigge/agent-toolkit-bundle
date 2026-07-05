# Schema Inspection

Portable queries to inspect tables, columns, indexes, constraints, and
foreign key relationships across engines.

## List Tables

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

## List Columns

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

## List Indexes

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

## List Foreign Keys

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

## List CHECK Constraints (PostgreSQL)

```sql
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'target_table'::regclass
  AND contype = 'c';
```
